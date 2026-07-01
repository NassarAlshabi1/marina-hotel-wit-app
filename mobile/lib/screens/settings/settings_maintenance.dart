import 'dart:async';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import '../../components/app_scaffold.dart';
import '../../providers/appwrite_providers.dart';
import '../../providers/repository_providers.dart';
import '../../services/booking_derived_fields_service.dart';
import '../../services/daos/outbox_dao.dart';
import '../../services/diagnostics/diagnostics_logger.dart';
import '../../services/google_drive_auto_sync_engine.dart';
import '../../services/local_db.dart';
import '../../services/sqlite_backup_restore.dart';
import '../../services/sync_guardian.dart';
import '../../services/sync_orchestrator.dart';
import '../../services/unified_sync_orchestrator.dart';
import '../../utils/env.dart';

// ═══════════════════════════════════════════════════════════════
//  نموذج البيانات الحقيقية
// ═══════════════════════════════════════════════════════════════

class _SystemInfo {

  const _SystemInfo({
    required this.appVersion,
    required this.deviceModel,
    required this.osVersion,
    required this.dbConnected,
    required this.dbSchemaVersion,
    required this.dbSizeBytes,
    required this.totalRecords,
    this.lastSyncTime,
    required this.outboxCount,
    required this.logStats,
    required this.apiEndpoint,
  });
  final String appVersion;
  final String deviceModel;
  final String osVersion;
  final bool dbConnected;
  final int dbSchemaVersion;
  final int dbSizeBytes;
  final int totalRecords;
  final String? lastSyncTime;
  final int outboxCount;
  final Map<String, int> logStats;
  final String apiEndpoint;
}

// ═══════════════════════════════════════════════════════════════
//  الشاشة الرئيسية
// ═══════════════════════════════════════════════════════════════

class SettingsMaintenanceScreen extends ConsumerStatefulWidget {
  const SettingsMaintenanceScreen({super.key});

  @override
  ConsumerState<SettingsMaintenanceScreen> createState() =>
      _SettingsMaintenanceScreenState();
}

class _SettingsMaintenanceScreenState
    extends ConsumerState<SettingsMaintenanceScreen> {
  _SystemInfo? _info;
  bool _isLoadingInfo = true;
  bool _isWorking = false;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo();
  }

  // ─── تحميل البيانات الحقيقية ───────────────────────────

  Future<void> _loadSystemInfo() async {
    setState(() => _isLoadingInfo = true);
    try {
      final info = await _collectSystemInfo();
      if (mounted) {
        setState(() => _info = info);
      }
    } catch (e) {
      debugPrint('⚠️ Failed to load system info: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingInfo = false);
      }
    }
  }

  Future<_SystemInfo> _collectSystemInfo() async {
    final prefs = await SharedPreferences.getInstance();
    final db = DatabaseManager.instance;

    // حجم ملف قاعدة البيانات
    final dbDir = await sqflite.getDatabasesPath();
    int dbSizeBytes = 0;
    for (final ext in ['', '-wal', '-shm']) {
      final file = File(p.join(dbDir, 'marina_hotel.db$ext'));
      if (file.existsSync()) {
        dbSizeBytes += await file.length();
      }
    }

    // إجمالي السجلات (الجداول الرئيسية فقط)
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

    // آخر مزامنة
    final lastSyncMs = prefs.getInt('appwrite_last_sync_time');
    String? lastSyncTime;
    if (lastSyncMs != null) {
      final dt = DateTime.fromMillisecondsSinceEpoch(lastSyncMs);
      final diff = DateTime.now().difference(dt);
      if (diff.inMinutes < 1) {
        lastSyncTime = 'الآن';
      } else if (diff.inMinutes < 60) {
        lastSyncTime = 'منذ ${diff.inMinutes} دقيقة';
      } else if (diff.inHours < 24) {
        lastSyncTime = 'منذ ${diff.inHours} ساعة';
      } else {
        lastSyncTime = 'منذ ${diff.inDays} يوم';
      }
    }

    // Outbox
    int outboxCount = 0;
    try {
      outboxCount = await OutboxDao(db).count();
    } catch (_) {}

    // Logs
    final logStats = DiagnosticsLogger.instance.getStats();

    // Device info + App version
    String deviceModel = 'غير معروف';
    String osVersion = '';
    String appVersion = '1.2.0+3';
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      appVersion = '${packageInfo.version}+${packageInfo.buildNumber}';
    } catch (_) {}
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

    return _SystemInfo(
      appVersion: appVersion,
      deviceModel: deviceModel,
      osVersion: osVersion,
      dbConnected: DatabaseManager.isInitialized,
      dbSchemaVersion: db.schemaVersion,
      dbSizeBytes: dbSizeBytes,
      totalRecords: totalRecords,
      lastSyncTime: lastSyncTime,
      outboxCount: outboxCount,
      logStats: logStats,
      apiEndpoint: Env.baseApiUrl,
    );
  }

  // ─── بناء الواجهة ─────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'صيانة النظام',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── بطاقة معلومات النظام (بيانات حقيقية) ───
          _buildSystemInfoCard(),

          const SizedBox(height: 20),

          // ─── أدوات الصيانة ───
          _buildSectionTitle('أدوات الصيانة', Colors.blue),
          const SizedBox(height: 8),

          _buildMaintenanceCard(
            title: 'تنظيف البيانات المؤقتة',
            subtitle: 'حذف الملفات المؤقتة وتحسين الأداء',
            icon: Icons.cleaning_services,
            color: Colors.blue,
            onTap: () => _showCleanupDialog(context, ref),
          ),

          _buildMaintenanceCard(
            title: 'فحص قاعدة البيانات',
            subtitle: 'التحقق من سلامة البيانات وإصلاح الأخطاء',
            icon: Icons.storage,
            color: Colors.green,
            onTap: () => _showDatabaseCheckDialog(context),
          ),

          _buildMaintenanceCard(
            title: 'ضغط قاعدة البيانات (VACUUM)',
            subtitle: 'تحرير المساحة غير المستخدمة وتحسين الأداء',
            icon: Icons.compress,
            color: Colors.amber.shade700,
            onTap: () => _showVacuumDialog(context, ref),
          ),

          _buildMaintenanceCard(
            title: 'إعادة تعيين المزامنة',
            subtitle: 'إعادة ضبط خدمة المزامنة مع الخادم',
            icon: Icons.sync_problem,
            color: Colors.orange,
            onTap: () => _showResetSyncDialog(context, ref),
          ),

          const SizedBox(height: 20),

          // ─── أدوات متقدمة ───
          _buildSectionTitle('أدوات متقدمة', Colors.red),
          const SizedBox(height: 8),

          _buildMaintenanceCard(
            title: 'معالجة الرصيد التراكمي',
            subtitle: 'تحويل المدفوعات التراكمية المعلقة إلى مدفوعات فعلية',
            icon: Icons.account_balance_wallet,
            color: Colors.teal,
            onTap: () => _showProcessPendingBalanceDialog(context, ref),
          ),

          _buildMaintenanceCard(
            title: 'مسح Outbox المعطّل',
            subtitle: 'إعادة تعيين العمليات المعلقة في قائمة الانتظار',
            icon: Icons.outbox,
            color: Colors.deepPurple,
            onTap: () => _showOutboxResetDialog(context, ref),
          ),

          _buildMaintenanceCard(
            title: 'إعادة تشغيل الخدمات',
            subtitle: 'إعادة تشغيل جميع خدمات التطبيق',
            icon: Icons.restart_alt,
            color: Colors.red,
            onTap: () => _showRestartDialog(context),
          ),

          _buildMaintenanceCard(
            title: 'إعادة تعيين التطبيق',
            subtitle: 'حذف جميع البيانات المحلية وإعادة التهيئة',
            icon: Icons.delete_forever,
            color: Colors.red.shade900,
            onTap: () => _showResetAppDialog(context),
          ),

          const SizedBox(height: 24),

          // ─── تحذير ───
          _buildWarningBanner(),
        ],
      ),
    );
  }

  // ─── بطاقة معلومات النظام ─────────────────────────────

  Widget _buildSystemInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blue, size: 22),
                const SizedBox(width: 8),
                const Text(
                  'معلومات النظام',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
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
            else if (_info != null)
              _buildRealSystemInfo(_info!)
            else
              const Text('تعذر تحميل المعلومات', style: TextStyle(color: Colors.grey)),
          ],
        ),
      ),
    );
  }

  Widget _buildRealSystemInfo(_SystemInfo info) {
    final dbSizeMb = (info.dbSizeBytes / (1024 * 1024)).toStringAsFixed(1);
    final formattedRecords = _formatNumber(info.totalRecords);
    final errorCount = info.logStats['error'] ?? 0;
    final criticalCount = info.logStats['critical'] ?? 0;

    return Column(
      children: [
        _infoRow(Icons.verified, 'إصدار التطبيق', info.appVersion),
        _infoRow(Icons.devices, 'الجهاز', '${info.deviceModel} · ${info.osVersion}'),
        _infoRow(
          Icons.storage,
          'قاعدة البيانات',
          info.dbConnected
              ? 'متصلة (إصدار ${info.dbSchemaVersion})'
              : 'غير متصلة',
          valueColor: info.dbConnected ? Colors.green : Colors.red,
        ),
        _infoRow(Icons.sd_storage, 'حجم قاعدة البيانات', '$dbSizeMb MB'),
        _infoRow(Icons.table_chart, 'إجمالي السجلات', formattedRecords),
        _infoRow(
          Icons.sync,
          'آخر مزامنة',
          info.lastSyncTime ?? 'لم تتم بعد',
        ),
        _infoRow(
          Icons.outbox,
          'Outbox معلّق',
          '${info.outboxCount}',
          valueColor: info.outboxCount > 0 ? Colors.orange : Colors.green,
        ),
        if (errorCount > 0 || criticalCount > 0)
          _infoRow(
            Icons.bug_report,
            'أخطاء مُسجّلة',
            '$errorCount أخطاء · $criticalCount حرجة',
            valueColor: Colors.red,
          ),
      ],
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
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade700,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: valueColor ?? Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ─── عناصر واجهة المستخدم المشتركة ─────────────────────

  Widget _buildSectionTitle(String title, Color color) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: color,
      ),
    );
  }

  Widget _buildMaintenanceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
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

  Widget _buildWarningBanner() {
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
              'استخدام أدوات الصيانة المتقدمة قد يؤثر على البيانات. '
              'تأكد من إنشاء نسخة احتياطية قبل المتابعة.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          ),
        ],
      ),
    );
  }

  String _formatNumber(int n) {
    return n.toString().replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
      (m) => '${m[1]},',
    );
  }

  // ─── مساعد: مؤشر تقدم ─────────────────────────────────

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
    if (mounted) {
      setState(() => _isWorking = false);
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) {
        nav.pop();
      }
    }
  }

  void _showSnack(String message, {Color? color}) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: color),
      );
    }
  }

  // ═══════════════════════════════════════════════════════════
  //  حوارات الصيانة
  // ═══════════════════════════════════════════════════════════

  // ─── تنظيف البيانات المؤقتة ───────────────────────────

  void _showCleanupDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تنظيف البيانات المؤقتة'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cleaning_services, size: 40, color: Colors.blue),
            SizedBox(height: 12),
            Text('سيتم حذف الملفات المؤقتة والبيانات غير الضرورية.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري التنظيف...');
              try {
                await ref.read(backupStatusProvider.notifier).cleanupTempFiles();
                DiagnosticsLogger.instance.clear();
                _hideLoading();
                _showSnack('تم التنظيف بنجاح', color: Colors.green);
                unawaited(_loadSystemInfo());
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ: $e', color: Colors.red);
              }
            },
            child: const Text('تنظيف'),
          ),
        ],
      ),
    );
  }

  // ─── فحص قاعدة البيانات ──────────────────────────────

  void _showDatabaseCheckDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('فحص قاعدة البيانات'),
        content: const Text('سيتم التحقق من سلامة الجداول وبياناتها.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري فحص قاعدة البيانات...');
              try {
                final checks = await SyncOrchestrator.instance.verifyDataIntegrity();
                _hideLoading();
                if (mounted) {
                  _showIntegrityResults(checks);
                }
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ في الفحص: $e', color: Colors.red);
              }
            },
            child: const Text('بدء الفحص'),
          ),
        ],
      ),
    );
  }

  void _showIntegrityResults(List<dynamic> checks) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.verified, color: Colors.green),
            SizedBox(width: 8),
            Text('نتائج الفحص'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${checks.length} جدول تم فحصها',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
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
                      title: Text(check.tableName as String),
                      subtitle: Text('${check.recordCount} سجل'),
                      trailing: Text(
                        (check.checksum as String).substring(0, 8),
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
                      ),
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
    );
  }

  // ─── VACUUM ─────────────────────────────────────────────

  void _showVacuumDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ضغط قاعدة البيانات'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.compress, size: 40, color: Colors.amber),
            SizedBox(height: 12),
            Text(
              'سيتم تنفيذ VACUUM لتحرير المساحة غير المستخدمة.\n'
              'قد يستغرق ذلك بضع ثوانٍ.',
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري ضغط قاعدة البيانات (VACUUM)...');
              try {
                final db = ref.read(databaseProvider);
                final sizeBefore = await _getTotalDbSizeBytes();
                await db.customStatement('VACUUM');
                final sizeAfter = await _getTotalDbSizeBytes();
                final saved = sizeBefore - sizeAfter;
                _hideLoading();
                _showSnack(
                  'تم الضغط بنجاح — تم تحرير ${(saved / 1024).toStringAsFixed(0)} KB',
                  color: Colors.green,
                );
                unawaited(_loadSystemInfo());
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ في الضغط: $e', color: Colors.red);
              }
            },
            child: const Text('ضغط'),
          ),
        ],
      ),
    );
  }

  Future<int> _getTotalDbSizeBytes() async {
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

  // ─── إعادة تعيين المزامنة ─────────────────────────────

  void _showResetSyncDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تعيين المزامنة'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_problem, size: 40, color: Colors.orange),
            SizedBox(height: 12),
            Text('سيتم إيقاف المزامنة الحالية ومسح ذاكرة التخزين المؤقت '
                'ثم بدء مزامنة جديدة.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري إعادة تعيين المزامنة...');
              try {
                await ref.read(appwriteSyncManagerProvider).resetSyncState();
                await OutboxDao(DatabaseManager.instance).resetErrors();
                await UnifiedSyncOrchestrator.instance.syncNow(
                  reason: 'maintenance_reset',
                );
                _hideLoading();
                _showSnack('تم إعادة تعيين المزامنة بنجاح', color: Colors.green);
                unawaited(_loadSystemInfo());
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ في إعادة التعيين: $e', color: Colors.red);
              }
            },
            child: const Text('إعادة التعيين'),
          ),
        ],
      ),
    );
  }

  // ─── معالجة الرصيد التراكمي ──────────────────────────

  void _showProcessPendingBalanceDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.account_balance_wallet, color: Colors.teal),
            SizedBox(width: 8),
            Text('معالجة الرصيد التراكمي'),
          ],
        ),
        content: const Text(
          'سيتم البحث عن المدفوعات التراكمية المعلقة وتحويلها '
          'إلى مدفوعات فعلية مع إعادة حساب الأرصدة.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري معالجة الرصيد التراكمي...');
              try {
                final result = await _processPendingBalances(ref);
                _hideLoading();
                if (result.isEmpty) {
                  _showSnack('لا توجد مدفوعات تراكمية معلقة', color: Colors.blue);
                } else if (mounted) {
                  // ignore: use_build_context_synchronously
                  _showProcessingResultDialog(context, result);
                }
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ: $e', color: Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            child: const Text('معالجة'),
          ),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _processPendingBalances(WidgetRef ref) async {
    final db = ref.read(databaseProvider);
    final paymentsRepo = ref.read(paymentsRepoProvider);
    final derivedService = BookingDerivedFieldsService(db);
    final results = <Map<String, dynamic>>[];

    final pendingPayments = await (db.select(db.payments)
          ..where((p) => p.isPendingBalance.equals(true))
          ..where((p) => p.deletedAt.isNull()))
        .get();

    if (pendingPayments.isEmpty) {
      return results;
    }

    final affectedBookingIds = <int>{};
    for (final payment in pendingPayments) {
      await paymentsRepo.update(
        payment.id,
        isPendingBalance: false,
        revenueType: 'room',
      );
      results.add({
        'id': payment.id,
        'roomNumber': payment.roomNumber ?? '—',
        'amount': payment.amount,
        'paymentDate': payment.paymentDate,
        'paymentMethod': payment.paymentMethod,
      });
      if (payment.bookingLocalId != null) {
        affectedBookingIds.add(payment.bookingLocalId!);
      }
    }

    for (final bookingId in affectedBookingIds) {
      await derivedService.refreshForBookingId(bookingId);
    }
    await derivedService.refreshAllActiveBookings();

    return results;
  }

  void _showProcessingResultDialog(
    BuildContext context,
    List<Map<String, dynamic>> results,
  ) {
    final totalAmount = results.fold<double>(0, (s, r) => s + (r['amount'] as double));

    showDialog<void>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.teal),
              SizedBox(width: 8),
              Text('تمت المعالجة بنجاح'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.teal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.payments, color: Colors.teal, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${results.length} دفعة',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                    const Spacer(),
                    Text(
                      '${totalAmount.toStringAsFixed(0)} ر.ي',
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 250),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final r = results[i];
                    return ListTile(
                      dense: true,
                      leading: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.teal.withValues(alpha: 0.1),
                        child: Text(
                          r['roomNumber'] as String,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: Colors.teal,
                          ),
                        ),
                      ),
                      title: Text(
                        '${(r['amount'] as double).toStringAsFixed(0)} ر.ي — ${r['paymentMethod']}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      subtitle: Text(
                        r['paymentDate'] as String,
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إغلاق')),
          ],
        ),
      ),
    );
  }

  // ─── مسح Outbox ───────────────────────────────────────

  void _showOutboxResetDialog(BuildContext context, WidgetRef ref) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح Outbox المعطّل'),
        content: const Text(
          'سيتم إعادة تعيين جميع العمليات الفاشلة في قائمة الانتظار '
          'إلى حالة "معلقة" للمحاولة مرة أخرى.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري إعادة تعيين Outbox...');
              try {
                final db = ref.read(databaseProvider);
                final outboxDao = OutboxDao(db);
                await outboxDao.resetErrors();
                final stuckCount = await outboxDao.cleanupStuckEntries();
                _hideLoading();
                _showSnack(
                  'تم إعادة تعيين Outbox ($stuckCount عملية عالقة)',
                  color: Colors.green,
                );
                unawaited(_loadSystemInfo());
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ: $e', color: Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple),
            child: const Text('إعادة تعيين'),
          ),
        ],
      ),
    );
  }

  // ─── إعادة تشغيل الخدمات ──────────────────────────────

  void _showRestartDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إعادة تشغيل الخدمات'),
        content: const Text(
          'سيتم إعادة تشغيل جميع خدمات التطبيق. '
          'قد يستغرق ذلك بضع ثوانٍ.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري إعادة تشغيل الخدمات...');
              try {
                await SyncGuardian.instance.restart();
                await AutoSyncEngine.instance.restart();
                _hideLoading();
                _showSnack('تم إعادة تشغيل الخدمات بنجاح', color: Colors.green);
                unawaited(_loadSystemInfo());
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ: $e', color: Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إعادة التشغيل'),
          ),
        ],
      ),
    );
  }

  // ─── إعادة تعيين التطبيق ─────────────────────────────

  void _showResetAppDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: Colors.red),
            SizedBox(width: 8),
            Text('إعادة تعيين التطبيق', style: TextStyle(color: Colors.red)),
          ],
        ),
        content: const Text(
          'تحذير: هذا الإجراء لا يمكن التراجع عنه!\n\n'
          'سيتم حذف جميع البيانات المحلية نهائياً وإعادة التهيئة.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _showConfirmResetDialog(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إعادة التعيين'),
          ),
        ],
      ),
    );
  }

  void _showConfirmResetDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد نهائي'),
        content: const Text(
          'هل أنت متأكد تماماً؟\nسيتم فقدان جميع البيانات.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              _showLoading('جاري إعادة تعيين التطبيق...');
              try {
                await DatabaseManager.close();
                final dbPath = p.join(
                  await sqflite.getDatabasesPath(),
                  SqliteBackupRestore.kDefaultDbFileName,
                );
                await sqflite.deleteDatabase(dbPath);
                await DatabaseManager.reopen();

                // ✅ إصلاح P0: حذف مختار للمفاتيح بدلاً من prefs.clear()
                // نحذف فقط المفاتيح المتعلقة بالبيانات، ونحتفظ بالإعدادات الحرجة
                final prefs = await SharedPreferences.getInstance();
                const keysToRemove = [
                  'appwrite_last_sync_time',
                  'appwrite_pull_after_drive_skip_done',
                  'sync_last_pull_booking_nights',
                  'appwrite_delta_sync_enabled',
                  'last_auto_backup_timestamp',
                  'auto_backup_enabled',
                  'delta_sync_enabled',
                  'backup_mode',
                  'appwrite_last_delta_sync',
                  'last_app_open_pull',
                  'device_id',
                  'appwrite_delta_device_id',
                ];
                for (final key in keysToRemove) {
                  await prefs.remove(key);
                }

                // ✅ إصلاح P1: إعادة تهيئة المزامنة بعد reset
                try {
                  await SyncGuardian.instance.restart();
                } catch (_) {}

                _hideLoading();
                _showSnack('تم إعادة تعيين التطبيق بنجاح', color: Colors.green);
                unawaited(_loadSystemInfo());
              } catch (e) {
                _hideLoading();
                _showSnack('خطأ في إعادة التعيين: $e', color: Colors.red);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تأكيد الحذف'),
          ),
        ],
      ),
    );
  }
}
