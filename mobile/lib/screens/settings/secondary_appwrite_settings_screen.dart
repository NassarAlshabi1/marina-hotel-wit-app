// ignore_for_file: directives_ordering, prefer_const_constructors, use_if_null_to_convert_nulls_to_bools, unawaited_futures, use_build_context_synchronously, unused_field
import 'package:appwrite/appwrite.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/appwrite_config.dart';
import '../../services/secondary_appwrite_config.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/local_db.dart';
import '../../services/secondary_sync_manager.dart';

import '../../services/secondary_appwrite_service.dart';
import '../../services/secondary_backup_service.dart';
import '../../services/appwrite_sync_manager.dart';

/// شاشة إعدادات الوجهة الثانوية لـ Appwrite
/// تتيح: تفعيل/تعطيل + إدخال بيانات الاتصال + خيارات push/pull منفصلة + failover
class SecondaryAppwriteSettingsScreen extends ConsumerStatefulWidget {
  const SecondaryAppwriteSettingsScreen({super.key});

  @override
  ConsumerState<SecondaryAppwriteSettingsScreen> createState() =>
      _SecondaryAppwriteSettingsScreenState();
}

class _SecondaryAppwriteSettingsScreenState
    extends ConsumerState<SecondaryAppwriteSettingsScreen> {
  final _endpointCtrl = TextEditingController();
  final _projectIdCtrl = TextEditingController();
  final _databaseIdCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  bool _obscureApiKey = true;
  bool _testingConnection = false;
  String? _testResult;
  bool? _testSuccess;
  int? _testLatency;
  bool _saving = false;
  bool _switchingFailover = false;
  bool _uploadingFullBackup = false;
  String _fullBackupResult = '';
  bool? _fullBackupSuccess;
  int _totalCollectionsToUpload = 0;
  int _completedCollections = 0;
  int _totalRecordsToUpload = 0;
  int _completedRecords = 0;
  String _currentCollectionName = '';
  DateTime? _uploadStartTime;
  int _currentCollectionRecords = 0;
  int _currentCollectionDone = 0;
  StreamSubscription<BackupProgress>? _backupSub;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    _endpointCtrl.text = SecondaryAppwriteConfig.endpoint;
    _projectIdCtrl.text = SecondaryAppwriteConfig.projectId;
    _databaseIdCtrl.text = SecondaryAppwriteConfig.databaseId;
    _apiKeyCtrl.text = SecondaryAppwriteConfig.apiKey;
    setState(() {});
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _projectIdCtrl.dispose();
    _databaseIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    _backupSub?.cancel();
    super.dispose();
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📋 تم النسخ إلى الحافظة'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await SecondaryAppwriteConfig.saveConfig(
        enabled: SecondaryAppwriteConfig.isEnabled,
        endpoint: _endpointCtrl.text.trim(),
        projectId: _projectIdCtrl.text.trim(),
        databaseId: _databaseIdCtrl.text.trim(),
        apiKey: _apiKeyCtrl.text.trim(),
        pushEnabled: SecondaryAppwriteConfig.isPushEnabled,
        pullEnabled: SecondaryAppwriteConfig.isPullEnabled,
      );
      // إجبار SecondaryAppwriteService على إعادة التهيئة
      SecondaryAppwriteService().invalidate();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تم حفظ الإعدادات'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل الحفظ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// ✅ P1-3 fix: اختبار الاتصال **بدون** حفظ الإعدادات قسراً.
  ///
  /// قبل الإصلاح: `_testConnection()` يستدعي `await _save()` قبل الاختبار،
  /// فمجرّد الضغط على "اختبار الاتصال" يكتب فوق الإعدادات المحفوظة بقيم
  /// الحقول الحالية (قد تكون فارغة/خاطئة) ويستدعي `invalidate()` — فيتلف
  /// تكوين عامل يعمل، ويعيد تهيئة مدير المزامنة الحيّ بقيم غير مُتحقَّقة.
  ///
  /// بعد الإصلاح: نحن نُنشئ عميل اختبار مؤقت (TestableSecondaryService)
  /// يستخدم قيم الحقول الحالية مباشرة دون حفظها في SharedPreferences ولا
  /// استدعاء invalidate(). المستخدم حرّ في تجربة قيم مختلفة قبل الحفظ.
  Future<void> _testConnection() async {
    setState(() {
      _testingConnection = true;
      _testResult = null;
      _testSuccess = null;
      _testLatency = null;
    });
    try {
      // ✅ P2 fix: تحقق من صحّة المدخلات قبل الاختبار
      final endpoint = _endpointCtrl.text.trim();
      final projectId = _projectIdCtrl.text.trim();
      final databaseId = _databaseIdCtrl.text.trim();
      final apiKey = _apiKeyCtrl.text.trim();

      if (endpoint.isEmpty || projectId.isEmpty || databaseId.isEmpty) {
        setState(() {
          _testSuccess = false;
          _testResult = 'يرجى ملء جميع الحقول (Endpoint، Project ID، Database ID)';
        });
        return;
      }

      // ✅ P1-3: استخدم خدمة اختبار مؤقتة بدل الحفظ القسري
      final result = await _testConnectionWithoutSaving(
        endpoint: endpoint,
        projectId: projectId,
        databaseId: databaseId,
        apiKey: apiKey,
      );
      if (!mounted) return;
      setState(() {
        _testSuccess = result.success;
        _testResult = result.message;
        _testLatency = result.latencyMs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _testSuccess = false;
        _testResult = 'خطأ غير متوقع: $e';
      });
    } finally {
      if (mounted) setState(() => _testingConnection = false);
    }
  }

  /// ✅ P1-3: يبني عميل Appwrite مؤقت للاختبار دون حفظ الإعدادات.
  Future<ConnectionTestResult> _testConnectionWithoutSaving({
    required String endpoint,
    required String projectId,
    required String databaseId,
    required String apiKey,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final client = Client()
        ..setEndpoint(endpoint)
        ..setProject(projectId)
        ..setSelfSigned();
      if (apiKey.isNotEmpty) {
        client.addHeader('X-Appwrite-Key', apiKey);
      }
      final databases = Databases(client);
      // ignore: deprecated_member_use
      await databases.listDocuments(
        databaseId: databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      stopwatch.stop();
      return ConnectionTestResult(
        success: true,
        message: '✅ تم الاتصال بنجاح',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      return ConnectionTestResult(
        success: false,
        message: '❌ فشل: $e',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  Future<void> _uploadFullBackup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد رفع النسخة الشاملة'),
        content: const SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('سيتم رفع جميع البيانات المحلية إلى الوجهة الثانوية.'),
              SizedBox(height: 8),
              Text('• الغرف، الحجوزات، المدفوعات، الديون'),
              Text('• الموظفون، المصروفات، المعاملات النقدية'),
              Text('• ملاحظات الحجز، الليالي، النوبة'),
              Text('• دورات الرواتب، الدفعات، السحوبات'),
              SizedBox(height: 8),
              Text('⚠️ قد يستغرق وقتاً طويلاً حسب حجم البيانات'),
              Text('⚠️ يُفضل توفر اتصال مستقر بالإنترنت'),
              SizedBox(height: 4),
              Text('✅ يعمل في الخلفية — يمكنك التنقل بين الشاشات'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<bool>(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop<bool>(context, true),
            child: const Text('بدء الرفع'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _uploadingFullBackup = true;
      _fullBackupResult = '';
      _fullBackupSuccess = null;
      _totalCollectionsToUpload = 0;
      _completedCollections = 0;
      _totalRecordsToUpload = 0;
      _completedRecords = 0;
      _currentCollectionName = '';
      _uploadStartTime = DateTime.now();
      _currentCollectionRecords = 0;
      _currentCollectionDone = 0;
    });

    // ✅ استخدام SecondaryBackupService — يعمل في الخلفية
    final backupService = SecondaryBackupService.instance;
    _backupSub = backupService.progressStream.listen((progress) {
      if (!mounted) return;
      setState(() {
        _completedCollections = progress.completedCollections;
        _totalCollectionsToUpload = progress.totalCollections;
        _currentCollectionName = progress.currentCollection;
        _currentCollectionRecords = progress.totalRecords;
        _currentCollectionDone = progress.collectionProgress;
        _completedRecords = progress.successCount + progress.failureCount;
        _totalRecordsToUpload = progress.totalRecords > 0 ? progress.totalRecords : _totalRecordsToUpload;
      });
    });

    try {
      final stats = await backupService.startFullBackup();
      _backupSub?.cancel();
      _backupSub = null;

      if (mounted) {
        setState(() {
          _uploadingFullBackup = false;
          if (stats.error != null) {
            _fullBackupSuccess = false;
            _fullBackupResult = '❌ ${stats.error}';
          } else if (stats.failureCount == 0) {
            _fullBackupSuccess = true;
            _fullBackupResult =
                '✅ تم رفع ${stats.successCount} سجل بنجاح في ${stats.totalCollections} جدول';
          } else {
            _fullBackupSuccess = stats.successCount > 0;
            _fullBackupResult =
                '⚠️ نجح: ${stats.successCount} سجل، فشل: ${stats.failureCount} سجل'
                '\n📊 الجداول: ${stats.fullySuccessfulCollections} مكتمل، ${stats.failedCollections} فاشل';
          }
        });

        _showCollectionDetailsDialog(stats);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_fullBackupResult),
            backgroundColor: _fullBackupSuccess == true
                ? Colors.green
                : Colors.orange,
          ),
        );
      }
    } catch (e) {
      _backupSub?.cancel();
      _backupSub = null;
      if (mounted) {
        setState(() {
          _uploadingFullBackup = false;
          _fullBackupSuccess = false;
          _fullBackupResult = '❌ فشل غير متوقع: $e';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشل الرفع: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showCollectionDetailsDialog(FullBackupStats stats) {
    final details = stats.collectionDetails;
    if (details.isEmpty) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تفاصيل رفع الجداول'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: stats.failedCollections == 0
                      ? Colors.green.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildSummaryChip(
                      'إجمالي الجداول',
                      '${stats.totalCollections}',
                      Colors.blue,
                    ),
                    _buildSummaryChip(
                      'مكتمل',
                      '${stats.fullySuccessfulCollections}',
                      Colors.green,
                    ),
                    _buildSummaryChip(
                      'فاشل',
                      '${stats.failedCollections}',
                      stats.failedCollections > 0
                          ? Colors.red
                          : Colors.grey,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              if (stats.failedRecords.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.error_outline,
                              size: 16, color: Colors.red),
                          const SizedBox(width: 6),
                          Text(
                            'أسباب الفشل (${stats.failedRecords.length} سجل):',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.red),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      ...stats.errorsByReason.entries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 3),
                          child: Row(
                            children: [
                              const Icon(Icons.arrow_left,
                                  size: 12, color: Colors.red),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  entry.key,
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.red.shade700,
                                      fontFamily: 'monospace'),
                                ),
                              ),
                              Text(
                                '×${entry.value}',
                                style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.red.shade700),
                              ),
                              IconButton(
                                onPressed: () => _copyToClipboard(entry.key),
                                icon: const Icon(Icons.copy, size: 12),
                                tooltip: 'نسخ الخطأ',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              const Text(
                'تفاصيل كل جدول:',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: details.length,
                  itemBuilder: (context, index) {
                    final d = details[index];
                    final isOk = d['isFullySuccessful'] as bool;
                    final name = d['name'] as String;
                    final collectionFailures =
                        stats.failuresByCollection[name] ?? [];
                    return ExpansionTile(
                      dense: true,
                      tilePadding: EdgeInsets.zero,
                      leading: Icon(
                        isOk ? Icons.check_circle : Icons.error,
                        color: isOk ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                            fontSize: 12, fontFamily: 'monospace'),
                      ),
                      subtitle: Text(
                        'نجح: ${d['success']} / فشل: ${d['failure']} / إجمالي: ${d['total']}',
                        style: TextStyle(
                            fontSize: 10, color: Colors.grey.shade600),
                      ),
                      trailing: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isOk
                              ? Colors.green.shade50
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isOk ? '✓' : '✗',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isOk ? Colors.green : Colors.red,
                          ),
                        ),
                      ),
                      children: [
                        if (collectionFailures.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(
                                left: 32, right: 8, bottom: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: collectionFailures
                                  .take(5)
                                  .map((f) => Padding(
                                        padding: const EdgeInsets.only(
                                            bottom: 2),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                '• ${f.documentId ?? '?'}: ${f.reason}',
                                                style: TextStyle(
                                                    fontSize: 9,
                                                    color: Colors.red.shade600,
                                                    fontFamily: 'monospace'),
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () => _copyToClipboard(
                                                '${f.documentId ?? '?'}: ${f.reason}',
                                              ),
                                              icon: const Icon(Icons.copy, size: 12),
                                              tooltip: 'نسخ الخطأ',
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                            ),
                                          ],
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryChip(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildCountdownCard() {
    final remainingCollections =
        _totalCollectionsToUpload - _completedCollections;
    final collectionProgress = _totalCollectionsToUpload > 0
        ? _completedCollections / _totalCollectionsToUpload
        : 0.0;

    String elapsedStr = '';
    String etaStr = '';
    if (_uploadStartTime != null) {
      final elapsed = DateTime.now().difference(_uploadStartTime!);
      elapsedStr = '${elapsed.inMinutes}د ${elapsed.inSeconds % 60}ث';

      if (_completedCollections > 0 && _totalCollectionsToUpload > 0) {
        final avgPerCollection = elapsed.inSeconds / _completedCollections;
        final remainingSeconds =
            (remainingCollections * avgPerCollection).round();
        final etaMin = remainingSeconds ~/ 60;
        final etaSec = remainingSeconds % 60;
        etaStr = '$etaMinد $etaSecث';
      }
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text(
                  'جاري رفع البيانات...',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Text(
                  elapsedStr,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              children: [
                Text(
                  'الجداول: ',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                ),
                Text(
                  '$_completedCollections / $_totalCollectionsToUpload',
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Text(
                  '(متبقي: $remainingCollections)',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade700),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: collectionProgress,
              minHeight: 8,
              backgroundColor: Colors.grey.shade200,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.deepPurple),
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 12),

            if (_currentCollectionName.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.deepPurple.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.table_chart,
                        size: 14, color: Colors.deepPurple.shade700),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _currentCollectionName,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          fontFamily: 'monospace',
                          color: Colors.deepPurple.shade700,
                        ),
                      ),
                    ),
                    Text(
                      '$_currentCollectionDone / $_currentCollectionRecords',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.deepPurple.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _currentCollectionRecords > 0
                    ? _currentCollectionDone / _currentCollectionRecords
                    : 0,
                minHeight: 4,
                backgroundColor: Colors.grey.shade200,
                valueColor:
                    AlwaysStoppedAnimation<Color>(Colors.deepPurple.shade300),
                borderRadius: BorderRadius.circular(2),
              ),
            ],

            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildCountdownStat(
                  'منقضي',
                  elapsedStr,
                  Icons.timer,
                  Colors.blue,
                ),
                _buildCountdownStat(
                  'متبقي',
                  etaStr.isEmpty ? '—' : etaStr,
                  Icons.hourglass_top,
                  Colors.orange,
                ),
                _buildCountdownStat(
                  'سجلات',
                  '$_completedRecords',
                  Icons.list,
                  Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownStat(
      String label, String value, IconData icon, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        Text(label,
            style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
      ],
    );
  }


  Future<void> _toggleFailover(bool active) async {
    if (active && !SecondaryAppwriteConfig.isConfigured) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('⚠️ يجب إدخال بيانات الاتصال أولاً وحفظها'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _switchingFailover = true);
    try {
      await SecondaryAppwriteConfig.setFailoverActive(active);
      try {
        await AppwriteSyncManager.instance?.reinitializeAfterConfigChange();
      } catch (_) {}

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              active
                  ? '⚠️ تم تفعيل تجاوز الفشل — التطبيق يعمل الآن على الوجهة الثانوية'
                  : '✅ تم تعطيل تجاوز الفشل — العودة للوجهة الأساسية',
            ),
            backgroundColor: active ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل التبديل: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _switchingFailover = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = SecondaryAppwriteConfig.isEnabled;
    final pushEnabled = SecondaryAppwriteConfig.isPushEnabled;
    final pullEnabled = SecondaryAppwriteConfig.isPullEnabled;
    final failoverActive = SecondaryAppwriteConfig.isFailoverActive;
    final isConfigured = SecondaryAppwriteConfig.isConfigured;

    return Scaffold(
      appBar: AppBar(
        title: const Text('وجهة Appwrite الثانوية'),
        actions: [
          IconButton(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save),
            tooltip: 'حفظ',
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _InfoCard(
            icon: Icons.cloud_sync,
            color: Colors.blue,
            title: 'ما هي الوجهة الثانوية؟',
            body: 'نسخة احتياطية سحابية على حساب Appwrite آخر (أو region مختلف). '
                'تُرسل البيانات تلقائياً للوجهتين. عند تعطل الأساسية، يمكنك تفعيل '
                '"تجاوز الفشل" للعمل على الثانوية.',
          ),

          const SizedBox(height: 16),

          Card(
            child: SwitchListTile(
              title: const Text(
                'تفعيل الوجهة الثانوية',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                enabled ? 'مفعّل' : 'معطّل',
                style: TextStyle(
                  color: enabled ? Colors.green : Colors.grey,
                ),
              ),
              value: enabled,
              onChanged: (v) async {
                await SecondaryAppwriteConfig.saveConfig(
                  enabled: v,
                  endpoint: _endpointCtrl.text.trim(),
                  projectId: _projectIdCtrl.text.trim(),
                  databaseId: _databaseIdCtrl.text.trim(),
                  apiKey: _apiKeyCtrl.text.trim(),
                  pushEnabled: pushEnabled,
                  pullEnabled: pullEnabled,
                );
                SecondaryAppwriteService().invalidate();
                
                // ✅ تحديث علامات التسليم في outbox
                if (v) {
                  // تفعيل: نُعلّم كل السجلات كـ "غير مُسلّمة للثانوي" ليتم رفعها
                  final db = DatabaseManager.instance;
                  final outboxDao = OutboxDao(db);
                  final count = await outboxDao.markAllLocalAsUndeliveredToSecondary();
                  debugPrint('🔵 [Secondary] Marked $count records as undelivered to secondary');
                  if (SecondaryAppwriteConfig.isPushEnabled) {
                    SecondarySyncManager.instance.startAutoSync();
                  }
                } else {
                  // تعطيل: نُعلّم كل السجلات كـ "مُسلّمة للثانوي" لمنع حجبها
                  final db = DatabaseManager.instance;
                  final outboxDao = OutboxDao(db);
                  final count = await outboxDao.markAllLocalAsDeliveredToSecondary();
                  debugPrint('🔵 [Secondary] Marked $count records as delivered to secondary (disabled)');
                  SecondarySyncManager.instance.stopAutoSync();
                }
                setState(() {});
              },
            ),
          ),

          if (enabled && isConfigured) ...[
            const SizedBox(height: 8),
            Card(
              color: failoverActive
                  ? Colors.orange.shade50
                  : null,
              child: SwitchListTile(
                title: Row(
                  children: [
                    Icon(
                      failoverActive ? Icons.warning : Icons.swap_horiz,
                      color: failoverActive ? Colors.orange : Colors.blue,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'تجاوز الفشل (Failover)',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                subtitle: Text(
                  failoverActive
                      ? '⚠️ نشط — كل العمليات تتم على الوجهة الثانوية'
                      : 'عند التفعيل: استخدم الثانوية كوجهة أساسية مؤقتاً',
                  style: TextStyle(
                    color: failoverActive ? Colors.orange : Colors.grey,
                  ),
                ),
                value: failoverActive,
                onChanged: _switchingFailover ? null : _toggleFailover,
              ),
            ),
          ],

          const SizedBox(height: 16),

          if (enabled) ...[
            const Text(
              'بيانات الاتصال',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _endpointCtrl,
              decoration: const InputDecoration(
                labelText: 'Endpoint *',
                hintText: 'https://fra.cloud.appwrite.io/v1',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.link),
              ),
              keyboardType: TextInputType.url,
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _projectIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Project ID *',
                hintText: '690ff0da0025518570c1',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _databaseIdCtrl,
              decoration: const InputDecoration(
                labelText: 'Database ID *',
                hintText: 'hotel_db',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.storage),
              ),
              autocorrect: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _apiKeyCtrl,
              obscureText: _obscureApiKey,
              decoration: InputDecoration(
                labelText: 'API Key',
                hintText: 'standard_...',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.key),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureApiKey
                        ? Icons.visibility
                        : Icons.visibility_off,
                  ),
                  onPressed: () => setState(
                      () => _obscureApiKey = !_obscureApiKey),
                ),
              ),
              autocorrect: false,
            ),

            const SizedBox(height: 16),

            const Text(
              'العمليات المفعّلة',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Card(
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('Push (رفع البيانات)'),
                    subtitle: const Text(
                      'نسخ التغييرات من هذا الجهاز إلى الوجهة الثانوية',
                    ),
                    value: pushEnabled,
                    onChanged: (v) async {
                      await SecondaryAppwriteConfig.saveConfig(
                        enabled: enabled,
                        endpoint: _endpointCtrl.text.trim(),
                        projectId: _projectIdCtrl.text.trim(),
                        databaseId: _databaseIdCtrl.text.trim(),
                        apiKey: _apiKeyCtrl.text.trim(),
                        pushEnabled: v,
                        pullEnabled: pullEnabled,
                      );
                      setState(() {});
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    title: const Text('Pull (سحب البيانات)'),
                    subtitle: const Text(
                      'عند تفعيل Failover: السحب من الوجهة الثانوية',
                    ),
                    value: pullEnabled,
                    onChanged: (v) async {
                      await SecondaryAppwriteConfig.saveConfig(
                        enabled: enabled,
                        endpoint: _endpointCtrl.text.trim(),
                        projectId: _projectIdCtrl.text.trim(),
                        databaseId: _databaseIdCtrl.text.trim(),
                        apiKey: _apiKeyCtrl.text.trim(),
                        pushEnabled: pushEnabled,
                        pullEnabled: v,
                      );
                      setState(() {});
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            if (enabled && isConfigured) ...[
              if (_uploadingFullBackup) ...[
                _buildCountdownCard(),
                const SizedBox(height: 12),
              ],
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _uploadingFullBackup ? null : _uploadFullBackup,
                      icon: _uploadingFullBackup
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.backup),
                      label: Text(_uploadingFullBackup
                          ? 'جاري الرفع...'
                          : 'رفع نسخة شاملة'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
               if (_fullBackupResult.isNotEmpty) ...[
                 const SizedBox(height: 8),
                 Container(
                   padding: const EdgeInsets.all(12),
                   decoration: BoxDecoration(
                     color: _fullBackupSuccess == true
                         ? Colors.green.shade50
                         : Colors.red.shade50,
                     borderRadius: BorderRadius.circular(8),
                     border: Border.all(
                       color: _fullBackupSuccess == true
                           ? Colors.green.shade200
                           : Colors.red.shade200,
                     ),
                   ),
                   child: Row(
                     children: [
                       Icon(
                         _fullBackupSuccess == true
                             ? Icons.check_circle
                             : Icons.error,
                         color: _fullBackupSuccess == true
                             ? Colors.green
                             : Colors.red,
                       ),
                       const SizedBox(width: 8),
                       Expanded(
                         child: Text(_fullBackupResult),
                       ),
                       IconButton(
                         onPressed: () => _copyToClipboard(_fullBackupResult),
                         icon: const Icon(Icons.copy, size: 18),
                         tooltip: 'نسخ النص',
                       ),
                     ],
                   ),
                 ),
               ],
              const SizedBox(height: 16),
            ],

            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testingConnection ? null : _testConnection,
                    icon: _testingConnection
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.wifi_tethering),
                    label: const Text('اختبار الاتصال'),
                  ),
                ),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _testSuccess == true
                      ? Colors.green.shade50
                      : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: _testSuccess == true
                        ? Colors.green.shade200
                        : Colors.red.shade200,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _testSuccess == true ? Icons.check_circle : Icons.error,
                      color: _testSuccess == true
                          ? Colors.green
                          : Colors.red,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '$_testResult'
                        '${_testLatency != null ? " (latency: ${_testLatency}ms)" : ""}',
                      ),
                    ),
                    IconButton(
                      onPressed: () => _copyToClipboard(
                        '$_testResult'
                        '${_testLatency != null ? " (latency: ${_testLatency}ms)" : ""}',
                      ),
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'نسخ النص',
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            TextButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('تأكيد المسح'),
                    content: const Text(
                      'سيتم مسح كل إعدادات الوجهة الثانوية. '
                      'هل أنت متأكد؟',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('إلغاء'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('مسح'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;
                await SecondaryAppwriteConfig.clear();
                SecondaryAppwriteService().invalidate();
                _loadConfig();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('🧹 تم مسح الإعدادات'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text(
                'مسح الإعدادات',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }
}

/// بطاقة معلومات بسيطة
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
