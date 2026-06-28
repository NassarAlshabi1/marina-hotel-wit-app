// ignore_for_file: use_build_context_synchronously, unawaited_futures

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../providers/secondary_sync_provider.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/secondary_appwrite_config.dart';
import '../../services/secondary_appwrite_service.dart';
import '../../services/secondary_sync_manager.dart';

/// شاشة إعدادات الوجهة الثانوية لـ Appwrite
///
/// تتحكم في:
/// - تفعيل/تعطيل Secondary بالكامل
/// - تفعيل/تعطيل **الرفع (Push)** عبر outbox — رفع الأحداث أول بأول
/// - تفعيل/تعطيل **السحب (Pull)** — Failover للقراءة عند تعطل Primary
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
  bool _saving = false;
  bool _testing = false;
  bool _syncing = false;
  String? _message;
  bool? _success;
  DateTime? _lastSync;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    await SecondaryAppwriteConfig.ensureInitialized();
    setState(() {
      _endpointCtrl.text = SecondaryAppwriteConfig.endpoint;
      _projectIdCtrl.text = SecondaryAppwriteConfig.projectId;
      _databaseIdCtrl.text = SecondaryAppwriteConfig.databaseId;
      _apiKeyCtrl.text = SecondaryAppwriteConfig.apiKey;
      _lastSync = SecondaryAppwriteConfig.lastSyncTime;
    });
  }

  @override
  void dispose() {
    _endpointCtrl.dispose();
    _projectIdCtrl.dispose();
    _databaseIdCtrl.dispose();
    _apiKeyCtrl.dispose();
    super.dispose();
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
      SecondaryAppwriteService.instance.invalidate();
      ref.read(secondarySyncProvider.notifier).refresh();
      _showMessage(true, '✅ تم الحفظ');
    } catch (e) {
      _showMessage(false, '❌ فشل: $e');
    } finally {
      setState(() => _saving = false);
    }
  }

  /// تفعيل/تعطيل Secondary بالكامل
  ///
  /// عند التفعيل:
  ///   - نبدأ المزامنة التلقائية للرفع (Push) كل 15 دقيقة
  ///   - نُعلّم جميع سجلات outbox المحلية كـ "غير مُسلّمة للثانوي"
  ///     ليتم رفعها للثانوي في الدورة القادمة
  ///
  /// عند التعطيل:
  ///   - نوقف المزامنة التلقائية
  ///   - نُعلّم جميع السجلات كـ "مُسلّمة للثانوي" (للسماح بحذفها بعد نجاح Primary)
  Future<void> _toggleSync(bool value) async {
    await SecondaryAppwriteConfig.saveConfig(
      enabled: value,
      endpoint: _endpointCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      databaseId: _databaseIdCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      pushEnabled: SecondaryAppwriteConfig.isPushEnabled,
      pullEnabled: SecondaryAppwriteConfig.isPullEnabled,
    );

    ref.read(secondarySyncProvider.notifier).refresh();

    // ✅ تحديث علامات التسليم في outbox
    final db = ref.read(databaseProvider);
    final outboxDao = OutboxDao(db);
    if (value) {
      // تفعيل: نُعلّم كل السجلات كـ "غير مُسلّمة للثانوي" ليتم رفعها
      final count = await outboxDao.markAllLocalAsUndeliveredToSecondary();
      debugPrint('🔵 [Secondary] Marked $count records as undelivered to secondary');
      if (SecondaryAppwriteConfig.isPushEnabled) {
        SecondarySyncManager.instance.startAutoSync();

        // ✅ إصلاح (2026-06-28): مزامنة فورية للسجلات المتراكمة
        // لا ننتظر 15 دقيقة — ارفع فوراً
       
        SecondarySyncManager.instance.sync().then((result) {
          if (mounted && result.pushed > 0) {
            _showMessage(true, '✅ تم رفع ${result.pushed} سجل للوجهة الثانوية');
            setState(() => _lastSync = DateTime.now());
          }
        }).catchError((Object e) {
          if (mounted) {
            _showMessage(false, '⚠️ فشل الرفع الفوري: $e — سيُعاد تلقائياً');
          }
        });
      }
    } else {
      // تعطيل: نُعلّم كل السجلات كـ "مُسلّمة للثانوي" لمنع حجبها
      final count = await outboxDao.markAllLocalAsDeliveredToSecondary();
      debugPrint('🔵 [Secondary] Marked $count records as delivered to secondary (disabled)');
      SecondarySyncManager.instance.stopAutoSync();
    }

    setState(() {});
    _showMessage(true, value ? '✅ المزامنة مُفعّلة' : '⏹️ المزامنة معطّلة');
  }

  /// تفعيل/تعطيل الرفع (Push) لـ Secondary عبر outbox
  ///
  /// عند التفعيل: نبدأ المزامنة التلقائية + مزامنة فورية للسجلات المتراكمة
  /// عند التعطيل: نوقف المزامنة التلقائية، لكن السجلات المُعلّمة كـ
  ///   "غير مُسلّمة للثانوي" تبقى في outbox حتى يُعاد تفعيل الرفع
  Future<void> _togglePush(bool value) async {
    await SecondaryAppwriteConfig.saveConfig(
      enabled: SecondaryAppwriteConfig.isEnabled,
      endpoint: _endpointCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      databaseId: _databaseIdCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      pushEnabled: value,
      pullEnabled: SecondaryAppwriteConfig.isPullEnabled,
    );
    ref.read(secondarySyncProvider.notifier).refresh();

    if (value && SecondaryAppwriteConfig.isEnabled) {
      // ✅ بدء المزامنة التلقائية
      SecondarySyncManager.instance.startAutoSync();

      // ✅ إصلاح (2026-06-28): مزامنة فورية للسجلات المتراكمة في outbox
      // عندما كان Push معطلاً، السجلات تُكتب في outbox لكن لا تُرفع.
      // عند إعادة التفعيل، يجب رفعها فوراً — لا الانتظار 15 دقيقة.
      _showMessage(true, '✅ الرفع (Push) مُفعّل — جاري رفع السجلات المتراكمة...');

     
      SecondarySyncManager.instance.sync().then((result) {
        if (mounted) {
          if (result.success) {
            _showMessage(true, '✅ تم رفع ${result.pushed} سجل للوجهة الثانوية');
            setState(() => _lastSync = DateTime.now());
          } else if (result.pushed > 0) {
            _showMessage(true, '⚠️ تم رفع ${result.pushed} سجل، فشل ${result.failed}');
            setState(() => _lastSync = DateTime.now());
          }
        }
      }).catchError((Object e) {
        if (mounted) {
          _showMessage(false, '⚠️ فشل الرفع الفوري: $e — سيُعاد المحاولة تلقائياً');
        }
      });
    } else {
      // ✅ تعطيل Push: نوقف المزامنة + نُعلّم السجلات كـ "مُسلّمة للثانوي"
      // هذا يمنع انتظار السجلات في outbox — لا حاجة للانتظار إذا كان Push معطّل
      SecondarySyncManager.instance.stopAutoSync();
      final db = ref.read(databaseProvider);
      final outboxDao = OutboxDao(db);
      final count = await outboxDao.markAllLocalAsDeliveredToSecondary();
      debugPrint('🔵 [Secondary] Push disabled — marked $count records as delivered');
      _showMessage(true, '⏹️ الرفع (Push) معطّل — السجلات لن تنتظر في outbox');
    }

    setState(() {});
  }

  /// تفعيل/تعطيل السحب (Pull) من Secondary — أي Failover للقراءة
  ///
  /// عند التفعيل: عند فشل Primary، تُقرأ البيانات تلقائياً من Secondary
  /// عند التعطيل: عند فشل Primary، يفشل التطبيق في القراءة (لا Failover)
  Future<void> _togglePull(bool value) async {
    await SecondaryAppwriteConfig.saveConfig(
      enabled: SecondaryAppwriteConfig.isEnabled,
      endpoint: _endpointCtrl.text.trim(),
      projectId: _projectIdCtrl.text.trim(),
      databaseId: _databaseIdCtrl.text.trim(),
      apiKey: _apiKeyCtrl.text.trim(),
      pushEnabled: SecondaryAppwriteConfig.isPushEnabled,
      pullEnabled: value,
    );
    ref.read(secondarySyncProvider.notifier).refresh();
    setState(() {});
    _showMessage(
        true, value ? '✅ السحب (Pull/Failover) مُفعّل' : '⏹️ السحب (Pull/Failover) معطّل');
  }

  Future<void> _testConnection() async {
    setState(() {
      _testing = true;
      _message = null;
    });
    try {
      await _save();
      final result = await SecondaryAppwriteService.instance.testConnection();
      _showMessage(result, result ? '✅ الاتصال ناجح' : '❌ الاتصال فشل');
    } catch (e) {
      _showMessage(false, '❌ خطأ: $e');
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _syncNow() async {
    setState(() {
      _syncing = true;
      _message = null;
    });
    try {
      final result = await SecondarySyncManager.instance.sync();
      _showMessage(result.success, result.message);
      if (result.success) {
        setState(() => _lastSync = DateTime.now());
        ref.read(secondarySyncProvider.notifier).updateLastSync(DateTime.now());
      }
    } catch (e) {
      _showMessage(false, '❌ خطأ: $e');
    } finally {
      setState(() => _syncing = false);
    }
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد المسح'),
        content: const Text('هل تريد مسح إعدادات الوجهة الثانوية؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('مسح', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await SecondaryAppwriteConfig.clear();
    SecondaryAppwriteService.instance.invalidate();
    SecondarySyncManager.instance.stopAutoSync();
    await _loadConfig();
    ref.read(secondarySyncProvider.notifier).refresh();
    _showMessage(true, '🧹 تم المسح');
  }

  void _showMessage(bool success, String msg) {
    setState(() {
      _success = success;
      _message = msg;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(success ? Icons.check_circle : Icons.error,
                color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(msg)),
          ],
        ),
        backgroundColor: success ? Colors.green : Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = SecondaryAppwriteConfig.isEnabled;
    final isConfigured = SecondaryAppwriteConfig.isConfigured;
    final pushEnabled = SecondaryAppwriteConfig.isPushEnabled;
    final pullEnabled = SecondaryAppwriteConfig.isPullEnabled;

    return AppScaffold(
      title: 'Appwrite الثانوي',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── بطاقة التاريخ ──
          Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Icon(Icons.event, color: Colors.indigo.shade700, size: 20),
                  const SizedBox(width: 8),
                  const Text(
                    'تاريخ الإعداد: 2026-06-20',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── بطاقة معلوماتية ──
          Card(
            color: Colors.blue.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue.shade700, size: 18),
                      const SizedBox(width: 6),
                      const Text(
                        'كيف تعمل المزامنة الثانوية؟',
                        style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '• outbox المحلي يُسلّم للوجهتين بالتوازي\n'
                    '• السجل يُحذف فقط بعد نجاح كلا الوجهتين\n'
                    '• الرفع (Push): أحداث أول بأول لـ Secondary\n'
                    '• السحب (Pull): Failover تلقائي عند تعطل Primary\n'
                    '• لا فقدان بيانات، لا تكرار، لا سباق بيانات',
                    style: TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── حالة الاتصال ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.cloud, color: Colors.blue, size: 24),
                      SizedBox(width: 8),
                      Text('حالة الاتصال',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: !enabled
                          ? Colors.grey.shade50
                          : !isConfigured
                              ? Colors.orange.shade50
                              : Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: !enabled
                            ? Colors.grey
                            : !isConfigured
                                ? Colors.orange
                                : Colors.green,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          !enabled
                              ? Icons.power_off
                              : !isConfigured
                                  ? Icons.warning
                                  : Icons.check_circle,
                          color: !enabled
                              ? Colors.grey
                              : !isConfigured
                                  ? Colors.orange
                                  : Colors.green,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            !enabled
                                ? 'معطّل'
                                : !isConfigured
                                    ? 'غير مُعدّ'
                                    : 'جاهز',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: !enabled
                                  ? Colors.grey
                                  : !isConfigured
                                      ? Colors.orange
                                      : Colors.green,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _testing ? null : _testConnection,
                      icon: _testing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh),
                      label: Text(_testing ? 'جاري...' : 'اختبار الاتصال'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── إعدادات المزامنة (الأهم) ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.sync, color: Colors.cyan, size: 24),
                      SizedBox(width: 8),
                      Text('إعدادات المزامنة',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),

                  // ── المفتاح الرئيسي: تفعيل/تعطيل Secondary بالكامل ──
                  SwitchListTile(
                    title: const Text(
                      'تفعيل المزامنة الثانوية',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(enabled ? 'مُفعّلة' : 'معطّلة'),
                    value: enabled,
                    onChanged: _toggleSync,
                    activeThumbColor: Colors.green,
                  ),
                  if (enabled) ...[
                    const Divider(height: 16),

                    // ── خيار الرفع (Push) ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: pushEnabled
                            ? Colors.green.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: pushEnabled
                              ? Colors.green.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: SwitchListTile(
                        title: Row(
                          children: [
                            Icon(Icons.cloud_upload,
                                color: pushEnabled
                                    ? Colors.green
                                    : Colors.grey,
                                size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'الرفع (Push)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          pushEnabled
                              ? 'رفع الأحداث أول بأول لـ Secondary عبر outbox'
                              : 'معطّل — الأحداث تُرفع فقط للرئيسي',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: pushEnabled,
                        onChanged: _togglePush,
                        activeThumbColor: Colors.green,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ── خيار السحب (Pull / Failover) ──
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: pullEnabled
                            ? Colors.blue.shade50
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: pullEnabled
                              ? Colors.blue.shade300
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: SwitchListTile(
                        title: Row(
                          children: [
                            Icon(Icons.cloud_download,
                                color: pullEnabled
                                    ? Colors.blue
                                    : Colors.grey,
                                size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'السحب (Pull / Failover)',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          pullEnabled
                              ? 'عند تعطل Primary، تُقرأ البيانات تلقائياً من Secondary'
                              : 'معطّل — لا Failover للقراءة عند تعطل Primary',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: pullEnabled,
                        onChanged: _togglePull,
                        activeThumbColor: Colors.blue,
                      ),
                    ),

                    if (pushEnabled) ...[
                      const SizedBox(height: 16),
                      const Divider(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _syncing ? null : _syncNow,
                          icon: _syncing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2, color: Colors.white))
                              : const Icon(Icons.sync),
                          label: Text(_syncing ? 'جاري...' : 'مزامنة الآن'),
                        ),
                      ),
                      if (_lastSync != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          'آخر مزامنة: ${_formatDateTime(_lastSync!)}',
                          style:
                              const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── إعدادات الاتصال ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.settings, color: Colors.grey, size: 24),
                      SizedBox(width: 8),
                      Text('إعدادات الاتصال',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  TextField(
                    controller: _endpointCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Endpoint',
                      hintText: 'https://example.appwrite.io/v1',
                      prefixIcon: Icon(Icons.link),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _projectIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Project ID',
                      hintText: 'معرف المشروع',
                      prefixIcon: Icon(Icons.folder),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _databaseIdCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Database ID',
                      hintText: 'معرف قاعدة البيانات',
                      prefixIcon: Icon(Icons.storage),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _apiKeyCtrl,
                    obscureText: _obscureApiKey,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      prefixIcon: const Icon(Icons.key),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureApiKey
                            ? Icons.visibility
                            : Icons.visibility_off),
                        onPressed: () =>
                            setState(() => _obscureApiKey = !_obscureApiKey),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.save),
                      label: Text(_saving ? 'جاري...' : 'حفظ'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (_message != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: (_success ?? false)
                    ? Colors.green.shade50
                    : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(
                    (_success ?? false) ? Icons.check_circle : Icons.error,
                    color: (_success ?? false) ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_message!)),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── مسح ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red, size: 24),
                      SizedBox(width: 8),
                      Text('إدارة البيانات',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const Divider(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton.icon(
                      onPressed: _clear,
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      label: const Text('مسح الإعدادات',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dt) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dt);
  }
}
