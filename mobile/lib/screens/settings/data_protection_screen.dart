import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/auto_backup_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/smart_sync_provider.dart';
import '../../providers/appwrite_providers.dart' as ap;
import '../../services/alarm_backup.dart';
import '../../services/auto_backup_manager.dart';
import '../../services/smart_sync_manager.dart';
import '../../services/google_drive_unified_sync_coordinator.dart';
import 'appwrite_settings_screen.dart';

class DataProtectionScreen extends ConsumerStatefulWidget {
  const DataProtectionScreen({super.key});

  @override
  ConsumerState<DataProtectionScreen> createState() =>
      _DataProtectionScreenState();
}

class _DataProtectionScreenState extends ConsumerState<DataProtectionScreen> {
  late TextEditingController _maxBackupsController;
  late TextEditingController _retentionDaysController;
  bool _backupBusy = false;
  bool _syncBusy = false;
  bool _appwriteBusy = false;
  bool _scheduledEnabled = false;
  bool _googleDriveSyncEnabled = false;
  bool _googleDriveSyncDisableOnStart = false;
  bool _googleDrivePushEnabled = true; // Push مفعّل افتراضياً
  bool _googleDrivePullEnabled = false; // Pull معطل افتراضياً (وضع Push فقط)
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 21, minute: 0);
  final List<int> _intervalOptions = [1, 2, 5, 10, 15, 30, 60];
  final Map<ConflictResolution, String> _conflictDescriptions = {
    ConflictResolution.newerWins: 'الأحدث يفوز (موصى به)',
    ConflictResolution.manualResolve: 'حل يدوي عند الكشف عن تضارب',
    ConflictResolution.devicePriority: 'أولوية للجهاز الحالي',
  };

  @override
  void initState() {
    super.initState();
    _maxBackupsController = TextEditingController();
    _retentionDaysController = TextEditingController();
    _loadBackupForm();
  }

  @override
  void dispose() {
    _maxBackupsController.dispose();
    _retentionDaysController.dispose();
    super.dispose();
  }

  Future<void> _loadBackupForm() async {
    final manager = AutoBackupManager.instance;
    final maxBackups = await manager.getMaxBackupCount();
    final retentionDays = await manager.getRetentionDays();
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString('auto_backup_time') ?? '21:0';
    final parts = timeString.split(':');
    final scheduled = prefs.getBool('scheduled_backup_enabled') ?? false;
    final googleDriveSyncEnabled =
        prefs.getBool('google_drive_sync_enabled') ?? false;
    final googleDriveSyncDisableOnStart =
        prefs.getBool('google_drive_sync_disable_on_start') ?? false;
    final googleDrivePushEnabled = prefs.getBool('gd_unified_push_enabled') ??
        true; // Push مفعّل افتراضياً
    final googleDrivePullEnabled = prefs.getBool('gd_unified_pull_enabled') ??
        false; // Pull معطل افتراضياً (Push فقط)
    if (!mounted) return;
    setState(() {
      _maxBackupsController.text = maxBackups.toString();
      _retentionDaysController.text = retentionDays.toString();
      _scheduledTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
      _scheduledEnabled = scheduled;
      _googleDriveSyncEnabled = googleDriveSyncEnabled;
      _googleDriveSyncDisableOnStart = googleDriveSyncDisableOnStart;
      _googleDrivePushEnabled = googleDrivePushEnabled;
      _googleDrivePullEnabled = googleDrivePullEnabled;
    });
  }

  Future<void> _saveBackupSettings() async {
    setState(() => _backupBusy = true);
    try {
      final manager = AutoBackupManager.instance;
      final maxBackups = int.tryParse(_maxBackupsController.text) ?? 25;
      final retentionDays = int.tryParse(_retentionDaysController.text) ?? 45;
      await manager.setMaxBackupCount(maxBackups);
      await manager.setRetentionDays(retentionDays);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات النسخ الاحتياطي')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الإعدادات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _toggleAutoBackup(bool enabled) async {
    setState(() => _backupBusy = true);
    try {
      final manager = AutoBackupManager.instance;
      await manager.setEnabled(enabled);
      ref.invalidate(autoBackupStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'تم تفعيل النسخ التلقائي' : 'تم إيقاف النسخ التلقائي',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تغيير الحالة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _cleanupBackups() async {
    setState(() => _backupBusy = true);
    try {
      await AutoBackupManager.instance.cleanupNow();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تنظيف النسخ القديمة')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل التنظيف: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _toggleScheduledBackup(bool enabled) async {
    setState(() => _backupBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('scheduled_backup_enabled', enabled);
      if (enabled) {
        await AlarmBackup.scheduleDailyAlarm(
          _scheduledTime.hour,
          _scheduledTime.minute,
        );
      } else {
        await AlarmBackup.cancelAlarm();
      }
      if (!mounted) return;
      setState(() => _scheduledEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'تم تفعيل النسخ المجدول' : 'تم إيقاف النسخ المجدول',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث الجدولة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (picked == null || picked == _scheduledTime) return;
    setState(() => _scheduledTime = picked);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auto_backup_time',
      '${picked.hour}:${picked.minute}',
    );
    if (_scheduledEnabled) {
      await AlarmBackup.rescheduleDaily(picked.hour, picked.minute);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث وقت النسخ إلى ${picked.format(context)}'),
        ),
      );
    }
  }

  Future<void> _toggleGoogleDriveSyncEnabled(bool enabled) async {
    setState(() => _syncBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_drive_sync_enabled', enabled);
      if (!enabled) {
        await GoogleDriveUnifiedSyncCoordinator.instance.setPushEnabled(false);
      }
      if (!mounted) return;
      setState(() {
        _googleDriveSyncEnabled = enabled;
        if (!enabled) {
          _googleDrivePushEnabled = false;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تم تفعيل مزامنة Google Drive'
                : 'تم إيقاف مزامنة Google Drive',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تغيير حالة مزامنة Google Drive: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _toggleGoogleDriveSyncDisableOnStart(bool enabled) async {
    setState(() => _syncBusy = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('google_drive_sync_disable_on_start', enabled);
      if (!mounted) return;
      setState(() => _googleDriveSyncDisableOnStart = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'سيتم تعطيل مزامنة Google Drive عند بدء التشغيل'
                : 'تم إيقاف التعطيل التلقائي عند بدء التشغيل',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تغيير إعداد بدء التشغيل: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _toggleGoogleDrivePushEnabled(bool enabled) async {
    if (!_googleDriveSyncEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فعّل مزامنة Google Drive أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _syncBusy = true);
    try {
      await GoogleDriveUnifiedSyncCoordinator.instance.setPushEnabled(enabled);
      if (!mounted) return;
      setState(() => _googleDrivePushEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'تم تفعيل الرفع إلى Google Drive' : 'تم إيقاف الرفع',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تغيير إعداد الرفع: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _toggleGoogleDrivePullEnabled(bool enabled) async {
    if (!_googleDriveSyncEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('فعّل مزامنة Google Drive أولاً'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _syncBusy = true);
    try {
      await GoogleDriveUnifiedSyncCoordinator.instance.setPullEnabled(enabled);
      if (!mounted) return;
      setState(() => _googleDrivePullEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تم تفعيل السحب من Google Drive - ستُنزّل التغييرات من السحابة'
                : 'تم إيقاف السحب من Google Drive - لن تُنزّل أي تغييرات من السحابة (رفع فقط)',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تغيير إعداد السحب: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _toggleSmartSync(bool enabled) async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).setEnabled(enabled);
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(enabled ? 'تم تفعيل المزامنة' : 'تم إيقاف المزامنة'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('خطأ في تغيير حالة المزامنة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _changeSyncInterval(int minutes) async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).setSyncInterval(minutes);
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تم ضبط الفحص على كل $minutes دقيقة')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تعديل الفترة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _changeConflictResolution(ConflictResolution strategy) async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).setConflictResolution(strategy);
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث استراتيجية حل التضارب')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث الاستراتيجية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _manualSync() async {
    setState(() => _syncBusy = true);
    try {
      await ref.read(smartSyncManagerProvider).forceSyncNow();
      ref.invalidate(smartSyncStatusProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تمت المزامنة اليدوية')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشلت المزامنة اليدوية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _syncBusy = false);
    }
  }

  Future<void> _runComprehensiveBackup() async {
    setState(() => _backupBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(backupStatusProvider.notifier).createComprehensiveBackup();
      ref.invalidate(autoBackupStatusProvider);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء النسخة الاحتياطية الشاملة')),
      );
      await _runAppwriteSync(triggeredByBackup: true);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('تعذر إنشاء النسخة الاحتياطية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _backupBusy = false);
    }
  }

  Future<void> _runAppwriteSync({bool triggeredByBackup = false}) async {
    if (_appwriteBusy) return;
    setState(() => _appwriteBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(ap.appwriteSyncManagerProvider).sync();
      if (!mounted) return;
      final pushed = result.recordsPushed;
      final pulled = result.recordsPulled;
      final label = triggeredByBackup
          ? 'تمت مزامنة Appwrite بعد النسخة الاحتياطية'
          : 'تمت مزامنة Appwrite بنجاح';
      messenger.showSnackBar(
        SnackBar(content: Text('$label (رفع $pushed / استقبل $pulled)')),
      );
      ref.invalidate(ap.syncStatsProvider);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('فشلت مزامنة Appwrite: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (!mounted) return;
      setState(() => _appwriteBusy = false);
    }
  }

  Future<void> _checkAppwriteConnection() async {
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
  }

  @override
  Widget build(BuildContext context) {
    final autoBackupStatus = ref.watch(autoBackupStatusProvider);
    final syncStatus = ref.watch(smartSyncStatusProvider);
    final backupState = ref.watch(backupStatusProvider);
    final appwriteConnection = ref.watch(ap.connectionStatusProvider);
    final appwriteStats = ref.watch(ap.syncStatsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة النسخ والمزامنة')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSummaryRow(
              autoBackupStatus,
              syncStatus,
              backupState,
              appwriteConnection,
              appwriteStats,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('مزامنة Appwrite السحابية', Icons.cloud_sync),
            const SizedBox(height: 12),
            _buildAppwriteSection(appwriteConnection, appwriteStats),
            const SizedBox(height: 32),
            _buildSectionTitle('المزامنة الذكية', Icons.sync_alt),
            const SizedBox(height: 12),
            _buildSyncSection(syncStatus),
            const SizedBox(height: 32),
            _buildSectionTitle('النسخ الاحتياطي الذكي', Icons.backup),
            const SizedBox(height: 12),
            _buildBackupSection(autoBackupStatus, backupState),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
    AsyncValue<Map<String, dynamic>> autoBackupStatus,
    AsyncValue<Map<String, dynamic>> syncStatus,
    BackupState backupState,
    ap.ConnectionState appwriteConnection,
    AsyncValue<Map<String, dynamic>> appwriteStats,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double cardWidth;
        if (width >= 900) {
          cardWidth = (width - 24) / 3;
        } else if (width >= 600) {
          cardWidth = (width - 12) / 2;
        } else {
          cardWidth = width;
        }
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(
              width: cardWidth,
              child: _buildAsyncSummaryTile(
                title: 'المزامنة بين الأجهزة',
                color: Colors.teal,
                status: syncStatus,
                primaryTimeKey: 'last_sync_check',
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildAsyncSummaryTile(
                title: 'النسخ الاحتياطي',
                color: Colors.indigo,
                status: autoBackupStatus,
                primaryTimeKey: 'last_auto_backup',
                overrideSubtitle: backupState.lastBackupTime?.toIso8601String(),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildAppwriteSummaryTile(
                appwriteConnection,
                appwriteStats,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAsyncSummaryTile({
    required String title,
    required AsyncValue<Map<String, dynamic>> status,
    required Color color,
    String? primaryTimeKey,
    String? secondaryTimeKey,
    String? overrideSubtitle,
  }) {
    return status.when(
      loading: () => _buildSummarySkeleton(title),
      error: (error, stack) => _buildSummaryError(title),
      data: (data) {
        final active = (data['enabled'] as bool?) ?? false;
        String? iso = overrideSubtitle;
        if (iso == null && primaryTimeKey != null) {
          final raw = data[primaryTimeKey];
          if (raw is String) iso = raw;
        }
        if (iso == null && secondaryTimeKey != null) {
          final raw = data[secondaryTimeKey];
          if (raw is String) iso = raw;
        }
        final subtitle = _formatOptionalDate(iso);
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: color),
                ),
                const SizedBox(height: 8),
                Text(
                  active ? 'مفعل' : 'معطل',
                  style: TextStyle(color: active ? Colors.green : Colors.red),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAppwriteSummaryTile(
    ap.ConnectionState state,
    AsyncValue<Map<String, dynamic>> statsAsync,
  ) {
    return statsAsync.when(
      loading: () => _buildSummarySkeleton('Appwrite'),
      error: (error, stack) => _buildSummaryError('Appwrite'),
      data: (stats) {
        final subtitle = _formatOptionalDate(stats['lastSyncTime'] as String?);
        final successRate = stats['successRate'];
        final rateText = successRate is num
            ? '${successRate.toStringAsFixed(0)}% نجاح'
            : null;
        return Card(
          elevation: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Appwrite',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blueGrey,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  state.isConnected ? 'متصل' : 'غير متصل',
                  style: TextStyle(
                    color: state.isConnected ? Colors.green : Colors.red,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'آخر مزامنة: $subtitle',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
                if (rateText != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    rateText,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummarySkeleton(String title) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryError(String title) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('تعذر التحميل', style: TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  Widget _buildAppwriteSection(
    ap.ConnectionState connectionState,
    AsyncValue<Map<String, dynamic>> statsAsync,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow(
                'الحالة',
                connectionState.isConnected ? 'متصل' : 'غير متصل',
              ),
              if (connectionState.errorMessage != null &&
                  connectionState.errorMessage!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    connectionState.errorMessage!,
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              statsAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stack) => const Text(
                  'تعذر تحميل إحصائيات Appwrite',
                  style: TextStyle(color: Colors.red),
                ),
                data: (stats) {
                  final lastSyncLabel =
                      _formatOptionalDate(stats['lastSyncTime'] as String?) ??
                          '---';
                  final successRate = stats['successRate'];
                  final successLabel = successRate is num
                      ? '${successRate.toStringAsFixed(0)}%'
                      : '---';
                  return Column(
                    children: [
                      _buildStatusRow('آخر مزامنة', lastSyncLabel),
                      _buildStatusRow('نسبة النجاح', successLabel),
                      _buildStatusRow(
                        'إجمالي المزامنات',
                        '${stats['totalSyncs'] ?? 0}',
                      ),
                      _buildStatusRow(
                        'سجلات مرفوعة',
                        '${stats['totalRecordsPushed'] ?? 0}',
                      ),
                      _buildStatusRow(
                        'سجلات مستقبلة',
                        '${stats['totalRecordsPulled'] ?? 0}',
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _appwriteBusy ? null : _runAppwriteSync,
                icon: _appwriteBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_sync),
                label: Text(
                  _appwriteBusy ? 'جارٍ المزامنة...' : 'مزامنة Appwrite الآن',
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: connectionState.isChecking
                    ? null
                    : _checkAppwriteConnection,
                icon: connectionState.isChecking
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh),
                label: Text(
                  connectionState.isChecking
                      ? 'جارٍ الفحص...'
                      : 'اختبار الاتصال',
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AppwriteSettingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('إعدادات Appwrite المتقدمة'),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.blue),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSyncSection(AsyncValue<Map<String, dynamic>> statusAsync) {
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) => _buildErrorCard('تعذر تحميل إعدادات المزامنة'),
      data: _buildSyncContent,
    );
  }

  Widget _buildSyncContent(Map<String, dynamic> status) {
    final isEnabled = status['enabled'] as bool;
    final monitoringActive = status['monitoring_active'] as bool;
    final isSyncing = status['is_syncing'] as bool;
    final isSignedIn = status['signed_in'] as bool;
    final lastSync = status['last_sync_check'] as String?;
    final deviceId = status['deviceId'] as String?;
    final syncInterval = status['sync_interval_minutes'] as int;
    final conflictKey = status['conflict_resolution'] as String;
    final resolution = ConflictResolution.values.firstWhere(
      (e) => e.name == conflictKey,
      orElse: () => ConflictResolution.newerWins,
    );
    return Column(
      children: [
        _buildCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow(
                'الحالة',
                isEnabled
                    ? (monitoringActive ? 'مفعلة ونشطة' : 'مفعلة لكن متوقفة')
                    : 'معطلة',
              ),
              _buildStatusRow(
                'تسجيل الدخول',
                isSignedIn ? 'متصل بـ Google Drive' : 'غير متصل',
              ),
              if (isSyncing) _buildStatusRow('النشاط الحالي', 'جارٍ المزامنة'),
              if (lastSync != null)
                _buildStatusRow(
                  'آخر فحص',
                  _formatDateTime(DateTime.parse(lastSync)),
                ),
              if (deviceId != null)
                _buildStatusRow(
                  'معرف الجهاز',
                  '${deviceId.substring(0, 8)}...',
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          SwitchListTile(
            title: const Text('تفعيل مزامنة Google Drive'),
            subtitle: Text(
              _googleDriveSyncEnabled
                  ? 'مفعلة - المزامنة تعمل عند الحاجة'
                  : 'معطلة - لن يتم أي رفع أو سحب',
            ),
            value: _googleDriveSyncEnabled,
            onChanged: _syncBusy ? null : _toggleGoogleDriveSyncEnabled,
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          SwitchListTile(
            title: const Text('تفعيل الرفع إلى Google Drive'),
            subtitle: Text(
              _googleDrivePushEnabled
                  ? 'سيرفع التغييرات والنسخ عند الحاجة'
                  : 'الرفع معطل بشكل كامل',
            ),
            value: _googleDrivePushEnabled,
            onChanged: (!_googleDriveSyncEnabled || _syncBusy)
                ? null
                : _toggleGoogleDrivePushEnabled,
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          SwitchListTile(
            title: const Text('تفعيل السحب من Google Drive'),
            subtitle: Text(
              _googleDrivePullEnabled
                  ? 'سينزل التغييرات من السحابة (Pull مفعّل)'
                  : 'السحب معطل - لن تُنزّل أي تغييرات من السحابة (رفع فقط / Push only)',
            ),
            value: _googleDrivePullEnabled,
            onChanged: (!_googleDriveSyncEnabled || _syncBusy)
                ? null
                : _toggleGoogleDrivePullEnabled,
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          SwitchListTile(
            title: const Text('تعطيل مزامنة Google Drive عند بدء التشغيل'),
            subtitle: Text(
              _googleDriveSyncDisableOnStart
                  ? 'ستتعطل تلقائياً عند فتح التطبيق'
                  : 'لن يتم التعطيل تلقائياً',
            ),
            value: _googleDriveSyncDisableOnStart,
            onChanged: _syncBusy ? null : _toggleGoogleDriveSyncDisableOnStart,
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          Column(
            children: [
              SwitchListTile(
                title: const Text('تفعيل المزامنة التلقائية بين الأجهزة'),
                subtitle: Text(
                  isEnabled
                      ? 'التحقق جارٍ بشكل دوري'
                      : 'لن يتم فحص النسخ الجديدة',
                ),
                value: isEnabled,
                onChanged: isSignedIn && !_syncBusy ? _toggleSmartSync : null,
              ),
              if (!isSignedIn)
                const Padding(
                  padding: EdgeInsets.only(bottom: 8),
                  child: Text(
                    'يتطلب تسجيل الدخول في Google Drive',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (isEnabled) ...[
          const SizedBox(height: 12),
          _buildCard(
            DropdownButtonFormField<int>(
              initialValue: _intervalOptions.contains(syncInterval)
                  ? syncInterval
                  : _intervalOptions.first,
              decoration: const InputDecoration(
                labelText: 'فترة الفحص بالدقائق',
                prefixIcon: Icon(Icons.timer),
              ),
              items: _intervalOptions
                  .map(
                    (minutes) => DropdownMenuItem(
                      value: minutes,
                      child: Text(_intervalLabel(minutes)),
                    ),
                  )
                  .toList(),
              onChanged: _syncBusy
                  ? null
                  : (value) {
                      if (value != null) _changeSyncInterval(value);
                    },
            ),
          ),
          const SizedBox(height: 12),
          _buildCard(
            Column(
              children: [
                DropdownButtonFormField<ConflictResolution>(
                  initialValue: resolution,
                  decoration: const InputDecoration(
                    labelText: 'استراتيجية حل التضارب',
                    prefixIcon: Icon(Icons.merge_type),
                  ),
                  items: _conflictDescriptions.entries
                      .map(
                        (entry) => DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                      )
                      .toList(),
                  onChanged: _syncBusy
                      ? null
                      : (value) {
                          if (value != null) _changeConflictResolution(value);
                        },
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _conflictDescriptions[resolution] ?? '',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _syncBusy || !isSignedIn ? null : _manualSync,
                icon: _syncBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.sync),
                label: const Text('مزامنة الآن'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBackupSection(
    AsyncValue<Map<String, dynamic>> statusAsync,
    BackupState backupState,
  ) {
    return statusAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stack) =>
          _buildErrorCard('تعذر تحميل إعدادات النسخ الاحتياطي'),
      data: (status) => _buildBackupContent(status, backupState),
    );
  }

  Widget _buildBackupContent(
    Map<String, dynamic> status,
    BackupState backupState,
  ) {
    final isEnabled = status['enabled'] as bool;
    final isBackingUp = status['is_backing_up'] as bool;
    final isSignedIn = status['signed_in'] as bool;
    final pendingChanges = status['pending_changes'] as int;
    final lastBackup = status['last_auto_backup'] as String?;
    final maxBackups = status['max_backups'] as int;
    final retentionDays = status['retention_days'] as int;
    if (_maxBackupsController.text.isEmpty) {
      _maxBackupsController.text = maxBackups.toString();
    }
    if (_retentionDaysController.text.isEmpty) {
      _retentionDaysController.text = retentionDays.toString();
    }
    final statusMessage = backupState.message;
    final double? progress = backupState.progress?.clamp(0.0, 1.0);
    final bool isErrorMessage = backupState.status == BackupStatus.error;
    final bool isSuccessMessage = backupState.status == BackupStatus.success;
    final lastLocalBackup = backupState.lastLocalBackupTime;
    return Column(
      children: [
        if (statusMessage != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isErrorMessage
                  ? Colors.red.shade50
                  : isSuccessMessage
                      ? Colors.green.shade50
                      : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusMessage,
              style: TextStyle(
                color: isErrorMessage
                    ? Colors.red.shade700
                    : isSuccessMessage
                        ? Colors.green.shade700
                        : Colors.blue.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (progress != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(value: progress),
          ),
          const SizedBox(height: 12),
        ],
        _buildCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow('الحالة', isEnabled ? 'مفعلة' : 'معطلة'),
              _buildStatusRow(
                'تسجيل الدخول',
                isSignedIn ? 'متصل بـ Google Drive' : 'غير متصل',
              ),
              if (isBackingUp)
                _buildStatusRow('النشاط الحالي', 'جارٍ إنشاء نسخة'),
              if (pendingChanges > 0)
                _buildStatusRow('تغييرات معلقة', pendingChanges.toString()),
              if (lastBackup != null)
                _buildStatusRow(
                  'آخر نسخة تلقائية',
                  _formatDateTime(DateTime.parse(lastBackup)),
                ),
              if (lastLocalBackup != null)
                _buildStatusRow(
                  'آخر نسخة محلية',
                  _formatDateTime(lastLocalBackup),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          SwitchListTile(
            title: const Text('تفعيل النسخ الاحتياطي التلقائي بعد التغييرات'),
            subtitle: Text(
              isEnabled
                  ? 'سيتم إنشاء نسخة بعد كل تعديل'
                  : 'لن يتم إنشاء نسخ تلقائية',
            ),
            value: isEnabled,
            onChanged: !_backupBusy ? _toggleAutoBackup : null,
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          Column(
            children: [
              TextFormField(
                controller: _maxBackupsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'عدد النسخ القصوى',
                  suffixIcon: Icon(Icons.numbers),
                ),
                enabled: !_backupBusy,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _retentionDaysController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'فترة الاحتفاظ بالأيام',
                  suffixIcon: Icon(Icons.calendar_today),
                ),
                enabled: !_backupBusy,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          Column(
            children: [
              SwitchListTile(
                title: const Text('النسخ الاحتياطي المجدول يومياً'),
                subtitle: Text(
                  _scheduledEnabled
                      ? 'وقت التنفيذ ${_scheduledTime.format(context)}'
                      : 'غير مفعل',
                ),
                value: _scheduledEnabled,
                onChanged: _backupBusy ? null : _toggleScheduledBackup,
              ),
              ListTile(
                leading: const Icon(Icons.access_time),
                title: const Text('وقت التنفيذ'),
                subtitle: Text(_scheduledTime.format(context)),
                trailing: const Icon(Icons.edit),
                enabled: !_backupBusy,
                onTap: _backupBusy ? null : _selectTime,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _backupBusy ? null : _saveBackupSettings,
                icon: _backupBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save),
                label: const Text('حفظ الإعدادات'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _backupBusy || !isSignedIn ? null : _cleanupBackups,
                icon: const Icon(Icons.cleaning_services),
                label: const Text('تنظيف النسخ القديمة'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _backupBusy ? null : _runComprehensiveBackup,
            icon: _backupBusy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.backup_table),
            label: Text(
              _backupBusy
                  ? 'جارٍ تجهيز النسخة...'
                  : 'نسخة شاملة + مزامنة Appwrite',
            ),
          ),
        ),
        if (!isSignedIn)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'يتطلب تسجيل الدخول في Google Drive لتنفيذ الإجراءات',
              style: TextStyle(color: Colors.orange, fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildCard(Widget child) {
    return Card(
      elevation: 2,
      child: Padding(padding: const EdgeInsets.all(16), child: child),
    );
  }

  Widget _buildStatusRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Expanded(child: Text(value, textAlign: TextAlign.end)),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(Icons.error, color: Colors.red, size: 32),
            const SizedBox(height: 8),
            Text(message, style: const TextStyle(color: Colors.red)),
          ],
        ),
      ),
    );
  }

  String? _formatOptionalDate(String? iso) {
    if (iso == null) return null;
    final dt = DateTime.tryParse(iso);
    if (dt == null) return null;
    return _formatDateTime(dt);
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m';
  }

  String _intervalLabel(int minutes) {
    if (minutes < 60) {
      return '$minutes دقيقة';
    }
    final hours = (minutes / 60).round();
    return '$hours ساعة';
  }
}
