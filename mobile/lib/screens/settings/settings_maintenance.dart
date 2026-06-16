import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/backup_provider.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/diagnostics/diagnostics_logger.dart';
import '../../services/google_drive_auto_sync_engine.dart';
import '../../services/local_db.dart';
import '../../services/sync_guardian.dart';
import '../../services/sync_orchestrator.dart';

class SettingsMaintenanceScreen extends ConsumerStatefulWidget {
  const SettingsMaintenanceScreen({super.key});

  @override
  ConsumerState<SettingsMaintenanceScreen> createState() =>
      _SettingsMaintenanceScreenState();
}

class _SettingsMaintenanceScreenState
    extends ConsumerState<SettingsMaintenanceScreen> {
  String _appVersion = '';
  String _deviceModel = '';
  String _osVersion = '';
  bool _dbConnected = false;
  int _dbSchemaVersion = 0;
  int _dbSizeBytes = 0;
  int _totalRecords = 0;
  String? _lastSyncTime;
  int _outboxCount = 0;
  Map<String, int> _logStats = {};
  bool _isLoadingInfo = true;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  Future<void> _loadSystemInfo() async {
    setState(() => _isLoadingInfo = true);
    try {
      final info = await PackageInfo.fromPlatform();
      final prefs = getSharedPrefs();
      final db = DatabaseManager.instance;

      final dbDir = await sqflite.getDatabasesPath();
      int dbSizeBytes = 0;
      for (final ext in ['', '-wal', '-shm']) {
        final file = File(p.join(dbDir, 'marina_hotel.db$ext'));
        if (file.existsSync()) {
          dbSizeBytes += await file.length();
        }
      }

      int totalRecords = 0;
      const mainTables = [
        'rooms', 'bookings', 'booking_notes', 'employees',
        'expenses', 'cash_transactions', 'payments', 'debts',
        'booking_nights', 'hotel_day_ledger', 'shift_notes',
      ];
      for (final table in mainTables) {
        try {
          final result = await db
              .customSelect('SELECT COUNT(*) AS c FROM $table WHERE deleted_at IS NULL')
              .getSingle();
          final v = result.data['c'];
          totalRecords += (v is int) ? v : (v is num) ? v.toInt() : 0;
        } catch (_) {}
      }

      final lastSyncMs = prefs.getInt('appwrite_last_sync_time');
      String? lastSyncTime;
      if (lastSyncMs != null) {
        final dt = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
        final diff = DateTime.now().difference(dt);
        lastSyncTime = diff.inMinutes < 1
            ? 'الآن'
            : diff.inMinutes < 60
                ? 'منذ ${diff.inMinutes} دقيقة'
                : diff.inHours < 24
                    ? 'منذ ${diff.inHours} ساعة'
                    : 'منذ ${diff.inDays} يوم';
      }

      int outboxCount = 0;
      try {
        final result = await db.customSelect('SELECT COUNT(*) AS c FROM outbox').getSingle();
        outboxCount = (result.data['c'] as int?) ?? 0;
      } catch (_) {}

      String deviceModel = '';
      String osVersion = '';
      try {
        final deviceInfo = DeviceInfoPlugin();
        if (Platform.isAndroid) {
          final android = await deviceInfo.androidInfo;
          deviceModel = android.model;
          osVersion = 'Android ${android.version.release}';
        } else if (Platform.isIOS) {
          final ios = await deviceInfo.iosInfo;
          deviceModel = ios.name;
          osVersion = 'iOS ${ios.systemVersion}';
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _appVersion = '${info.version}+${info.buildNumber}';
          _deviceModel = deviceModel;
          _osVersion = osVersion;
          _dbConnected = DatabaseManager.isInitialized;
          _dbSchemaVersion = db.schemaVersion;
          _dbSizeBytes = dbSizeBytes;
          _totalRecords = totalRecords;
          _lastSyncTime = lastSyncTime;
          _outboxCount = outboxCount;
          _logStats = DiagnosticsLogger.instance.getStats();
        });
      }
    } catch (e) {
      AppLogger.warning('⚠️ SettingsMaintenance: فشل تحميل معلومات النظام: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingInfo = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dbSizeMb = (_dbSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final errorCount = _logStats['error'] ?? 0;
    final criticalCount = _logStats['critical'] ?? 0;

    return AppScaffold(
      title: 'صيانة النظام',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(dbSizeMb, errorCount, criticalCount),
          const SizedBox(height: 20),
          _buildSectionTitle('أدوات الصيانة', Colors.blue),
          const SizedBox(height: 8),
          _toolItem('تنظيف البيانات المؤقتة', 'حذف الملفات المؤقتة وتحسين الأداء',
              Icons.cleaning_services, Colors.blue, _onCleanup),
          _toolItem('فحص قاعدة البيانات', 'التحقق من سلامة البيانات',
              Icons.storage, Colors.green, _onDatabaseCheck),
          _toolItem('ضغط قاعدة البيانات (VACUUM)', 'تحرير المساحة غير المستخدمة',
              Icons.compress, Colors.amber, _onVacuum),
          _toolItem('إعادة تعيين المزامنة', 'إعادة ضبط خدمة المزامنة',
              Icons.sync_problem, Colors.orange, _onResetSync),
          const SizedBox(height: 20),
          _buildSectionTitle('أدوات متقدمة', Colors.red),
          const SizedBox(height: 8),
          _toolItem('إعادة إرسال العمليات الفاشلة', 'إعادة محاولة إرسال البيانات الفاشلة للمزامنة',
              Icons.sync, Colors.teal, _onRetryFailed),
          _toolItem('مسح Outbox المعطّل', 'حذف جميع العمليات الفاشلة من قائمة الانتظار',
              Icons.outbox, Colors.deepPurple, _onResetOutbox),
          _toolItem('إعادة تشغيل الخدمات', 'إعادة تشغيل جميع خدمات التطبيق',
              Icons.restart_alt, Colors.red, _onRestartServices),
          const SizedBox(height: 24),
          _buildWarning(),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String dbSizeMb, int errorCount, int criticalCount) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 22),
                const SizedBox(width: 8),
                const Text('معلومات النظام',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                const Spacer(),
                if (!_isLoadingInfo)
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'تحديث',
                    onPressed: _loadSystemInfo,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (_isLoadingInfo)
              const Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: CircularProgressIndicator(),
                ),
              )
            else ...[
              _infoRow(Icons.verified, 'إصدار التطبيق', _appVersion),
              if (_deviceModel.isNotEmpty)
                _infoRow(Icons.devices, 'الجهاز', '$_deviceModel · $_osVersion'),
              _infoRow(Icons.storage, 'قاعدة البيانات',
                  _dbConnected ? 'متصلة (إصدار $_dbSchemaVersion)' : 'غير متصلة'),
              _infoRow(Icons.sd_storage, 'حجم قاعدة البيانات', '$dbSizeMb MB'),
              _infoRow(Icons.table_chart, 'إجمالي السجلات', _formatNumber(_totalRecords)),
              _infoRow(Icons.sync, 'آخر مزامنة', _lastSyncTime ?? 'لم تتم بعد'),
              _infoRow(Icons.outbox, 'Outbox معلّق', '$_outboxCount',
                  valueColor: _outboxCount > 0 ? Colors.orange : null),
              if (errorCount > 0 || criticalCount > 0)
                _infoRow(Icons.bug_report, 'أخطاء مُسجّلة',
                    '$errorCount أخطاء · $criticalCount حرجة',
                    valueColor: Colors.red),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade700, fontWeight: FontWeight.w500)),
          ),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.end,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: valueColor ?? Colors.black87),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title, Color color) {
    return Text(title,
        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: color));
  }

  Widget _toolItem(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.15),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
        onTap: _isWorking ? null : onTap,
      ),
    );
  }

  Widget _buildWarning() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber, color: Colors.red, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'استخدام أدوات الصيانة المتقدمة قد يؤثر على البيانات. تأكد من إنشاء نسخة احتياطية قبل المتابعة.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) =>
      n.toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');

  // ── Helpers ────────────────────────────────────

  void _showLoading(String message) {
    setState(() => _isWorking = true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(strokeWidth: 2),
            const SizedBox(width: 16),
            Expanded(child: Text(message, style: const TextStyle(fontSize: 14))),
          ],
        ),
      ),
    );
  }

  void _hideLoading() {
    setState(() => _isWorking = false);
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  void _showSnack(String message, {Color? color}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color),
      );
    }
  }

  Future<void> _withLoading(String message, Future<void> Function() task) async {
    _showLoading(message);
    try {
      await task();
      _hideLoading();
    } catch (e) {
      _hideLoading();
      _showSnack('خطأ: $e', color: Colors.red);
    }
  }

  void _confirm(
    String title,
    String message,
    IconData icon,
    Color color,
    String actionLabel,
    Future<void> Function() onConfirm,
  ) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [Icon(icon, color: color), const SizedBox(width: 8), Text(title)]),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              unawaited(_withLoading('جاري التنفيذ...', onConfirm));
            },
            style: ElevatedButton.styleFrom(backgroundColor: color),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  // ── أدوات الصيانة ─────────────────────────────

  Future<void> _onCleanup() async {
    _confirm('تنظيف البيانات المؤقتة', 'سيتم حذف الملفات المؤقتة والبيانات غير الضرورية.',
        Icons.cleaning_services, Colors.blue, 'تنظيف', () async {
      await ref.read(backupStatusProvider.notifier).cleanupTempFiles();
      DiagnosticsLogger.instance.clear();
      unawaited(_loadSystemInfo());
      _showSnack('تم التنظيف بنجاح', color: Colors.green);
    });
  }

  Future<void> _onDatabaseCheck() async {
    _confirm('فحص قاعدة البيانات', 'سيتم التحقق من سلامة الجداول وبياناتها.',
        Icons.storage, Colors.green, 'بدء الفحص', () async {
      final checks = await SyncOrchestrator.instance().verifyDataIntegrity();
      if (mounted) {
        unawaited(showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [
              Icon(Icons.verified, color: Colors.green),
              SizedBox(width: 8),
              Text('نتائج الفحص'),
            ]),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${checks.length} جدول تم فحصها',
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 12),
                  Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: checks.length,
                      itemBuilder: (_, i) {
                        final check = checks[i];
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.table_chart, size: 18),
                          title: Text(check.tableName),
                          subtitle: Text('${check.recordCount} سجل'),
                          trailing: Text(check.checksum.substring(0, 8),
                              style: const TextStyle(fontFamily: 'monospace', fontSize: 10)),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
            ],
          ),
        ));
      }
    });
  }

  Future<void> _onVacuum() async {
    _confirm('ضغط قاعدة البيانات', 'سيتم تنفيذ VACUUM لتحرير المساحة غير المستخدمة.',
        Icons.compress, Colors.amber, 'ضغط', () async {
      final db = DatabaseManager.instance;
      final sizeBefore = await _getDbSize();
      await db.customStatement('VACUUM');
      final sizeAfter = await _getDbSize();
      final saved = sizeBefore - sizeAfter;
      _showSnack('تم الضغط — تم تحرير ${(saved / 1024).toStringAsFixed(0)} KB',
          color: Colors.green);
      unawaited(_loadSystemInfo());
    });
  }

  Future<int> _getDbSize() async {
    final dbDir = await sqflite.getDatabasesPath();
    int total = 0;
    for (final ext in ['', '-wal', '-shm']) {
      final file = File(p.join(dbDir, 'marina_hotel.db$ext'));
      if (file.existsSync()) {
        total += await file.length();
      }
    }
    return total;
  }

  Future<void> _onResetSync() async {
    _confirm('إعادة تعيين المزامنة',
        'سيتم إيقاف المزامنة الحالية ومسح ذاكرة التخزين المؤقت ثم بدء مزامنة جديدة.',
        Icons.sync_problem, Colors.orange, 'إعادة التعيين', () async {
      await ref.read(appwriteSyncManagerProvider).resetSyncState();
      // ✅ إصلاح: اسم العمود الصحيح هو processing_status وليس status
      await DatabaseManager.instance.customSelect('DELETE FROM outbox WHERE processing_status = \'failed\'').get();
      _showSnack('تم إعادة تعيين المزامنة بنجاح', color: Colors.green);
      unawaited(_loadSystemInfo());
    });
  }

  Future<void> _onRetryFailed() async {
    _confirm('إعادة إرسال العمليات الفاشلة',
        'سيتم إعادة تعيين جميع العمليات الفاشلة إلى حالة "معلق" لمحاولة إرسالها مرة أخرى. هذا مفيد بعد إصلاح أخطاء الكود وبناء نسخة جديدة.',
        Icons.sync, Colors.teal, 'إعادة الإرسال', () async {
      final db = DatabaseManager.instance;
      final dao = OutboxDao(db);
      await dao.resetErrors();
      // إعادة تشغيل المزامنة لمعالجة العناصر المُعاد تعيينها
      try {
        await ref.read(appwriteSyncManagerProvider).pushLocalChanges();
      } catch (_) {
        // إذا فشل الرفع الفوري، سيتم المحاولة تلقائياً لاحقاً
      }
      _showSnack('تم إعادة تعيين العمليات الفاشلة — سيتم إرسالها تلقائياً', color: Colors.green);
      unawaited(_loadSystemInfo());
    });
  }

  Future<void> _onResetOutbox() async {
    _confirm('مسح Outbox المعطّل',
        'سيتم حذف جميع العمليات الفاشلة من قائمة الانتظار.',
        Icons.outbox, Colors.deepPurple, 'مسح', () async {
      // ✅ إصلاح: اسم العمود الصحيح هو processing_status وليس status
      await DatabaseManager.instance
          .customSelect('DELETE FROM outbox WHERE processing_status = \'failed\'').get();
      _showSnack('تم مسح Outbox المعطّل بنجاح', color: Colors.green);
      unawaited(_loadSystemInfo());
    });
  }

  Future<void> _onRestartServices() async {
    _confirm('إعادة تشغيل الخدمات', 'سيتم إعادة تشغيل جميع خدمات التطبيق.',
        Icons.restart_alt, Colors.red, 'إعادة التشغيل', () async {
      await SyncGuardian.instance.restart();
      await AutoSyncEngine.instance.restart();
      _showSnack('تم إعادة تشغيل الخدمات', color: Colors.green);
    });
  }
}
