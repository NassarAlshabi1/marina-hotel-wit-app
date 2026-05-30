import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/appwrite_providers.dart' as ap;
import '../../providers/auto_backup_provider.dart';
import '../../providers/backup_provider.dart';
import '../../services/alarm_backup.dart';
import '../../services/auto_backup_manager.dart';
import 'appwrite_settings_screen.dart';
import 'google_drive_settings_screen.dart';

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
  bool _appwriteBusy = false;
  bool _scheduledEnabled = false;
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 21, minute: 0);

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
    if (!mounted) {
      return;
    }
    setState(() {
      _maxBackupsController.text = maxBackups.toString();
      _retentionDaysController.text = retentionDays.toString();
      _scheduledTime = TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
      _scheduledEnabled = scheduled;
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
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ إعدادات النسخ الاحتياطي')),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل حفظ الإعدادات: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  Future<void> _toggleAutoBackup(bool enabled) async {
    setState(() => _backupBusy = true);
    try {
      final manager = AutoBackupManager.instance;
      await manager.setEnabled(enabled);
      ref.invalidate(autoBackupStatusProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'تم تفعيل النسخ التلقائي' : 'تم إيقاف النسخ التلقائي',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('فشل تغيير الحالة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  Future<void> _cleanupBackups() async {
    setState(() => _backupBusy = true);
    try {
      await AutoBackupManager.instance.cleanupNow();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم تنظيف النسخ القديمة')));
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل التنظيف: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
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
      if (!mounted) {
        return;
      }
      setState(() => _scheduledEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled ? 'تم تفعيل النسخ المجدول' : 'تم إيقاف النسخ المجدول',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تعذر تحديث الجدولة: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  Future<void> _selectTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _scheduledTime,
      builder: (context, child) =>
          Directionality(textDirection: TextDirection.rtl, child: child!),
    );
    if (picked == null || picked == _scheduledTime) {
      return;
    }
    setState(() => _scheduledTime = picked);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'auto_backup_time',
      '${picked.hour}:${picked.minute}',
    );
    if (_scheduledEnabled) {
      await AlarmBackup.rescheduleDaily(picked.hour, picked.minute);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تحديث وقت النسخ إلى ${picked.format(context)}'),
        ),
      );
    }
  }



  Future<void> _runComprehensiveBackup() async {
    setState(() => _backupBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(backupStatusProvider.notifier).createComprehensiveBackup();
      ref.invalidate(autoBackupStatusProvider);
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('تم إنشاء النسخة الاحتياطية الشاملة')),
      );
      await _runAppwriteSync(triggeredByBackup: true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('تعذر إنشاء النسخة الاحتياطية: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _backupBusy = false);
      }
    }
  }

  Future<void> _runAppwriteSync({bool triggeredByBackup = false}) async {
    if (_appwriteBusy) {
      return;
    }
    setState(() => _appwriteBusy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final result = await ref.read(ap.appwriteSyncManagerProvider).sync();
      if (!mounted) {
        return;
      }
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
      if (!mounted) {
        return;
      }
      messenger.showSnackBar(
        SnackBar(
          content: Text('فشلت مزامنة Appwrite: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _appwriteBusy = false);
      }
    }
  }

  Future<void> _checkAppwriteConnection() async {
    await ref.read(ap.connectionStatusProvider.notifier).checkConnection();
  }

  @override
  Widget build(BuildContext context) {
    final autoBackupStatus = ref.watch(autoBackupStatusProvider);
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
              backupState,
              appwriteConnection,
              appwriteStats,
            ),
            const SizedBox(height: 24),
            _buildSectionTitle('مزامنة Appwrite السحابية', Icons.cloud_sync),
            const SizedBox(height: 12),
            _buildAppwriteSection(appwriteConnection, appwriteStats),
            const SizedBox(height: 32),
            _buildSectionTitle('Google Drive - نسخ احتياطي واستعادة', Icons.cloud_upload),
            const SizedBox(height: 12),
            _buildGoogleDriveBackupSection(backupState),
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
    BackupState backupState,
    ap.ConnectionState appwriteConnection,
    AsyncValue<Map<String, dynamic>> appwriteStats,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        double cardWidth;
        if (width >= 900) {
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
          if (raw is String) {
            iso = raw;
          }
        }
        if (iso == null && secondaryTimeKey != null) {
          final raw = data[secondaryTimeKey];
          if (raw is String) {
            iso = raw;
          }
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
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const AppwriteSettingsScreen(),
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

  Widget _buildGoogleDriveBackupSection(BackupState backupState) {
    final isSignedIn = backupState.isSignedIn;
    final lastBackupTime = backupState.lastBackupTime;
    final availableBackups = backupState.availableBackups;
    return Column(
      children: [
        // Info banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Google Drive مخصص للنسخ الاحتياطي والاستعادة فقط. المزامنة التلقائية معطلة.',
                  style: TextStyle(color: Colors.blue.shade700, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _buildCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildStatusRow(
                'تسجيل الدخول',
                isSignedIn ? 'متصل بـ Google Drive' : 'غير متصل',
              ),
              _buildStatusRow(
                'الوضع',
                'نسخ احتياطي واستعادة فقط',
              ),
              _buildStatusRow(
                'المزامنة التلقائية',
                'معطلة',
              ),
              if (lastBackupTime != null)
                _buildStatusRow(
                  'آخر نسخة احتياطية',
                  _formatDateTime(lastBackupTime),
                ),
              _buildStatusRow(
                'عدد النسخ المتاحة',
                '${availableBackups.length}',
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Sync disabled notice
        _buildCard(
          SwitchListTile(
            title: const Text('مزامنة Google Drive التلقائية'),
            subtitle: const Text(
              'معطلة - Google Drive للنسخ الاحتياطي والاستعادة فقط',
            ),
            value: false,
            onChanged: null, // Permanently disabled
          ),
        ),
        const SizedBox(height: 12),
        // Navigate to Google Drive settings
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.push<void>(
                context,
                MaterialPageRoute<void>(
                  builder: (context) => const GoogleDriveSettingsScreen(),
                ),
              );
            },
            icon: const Icon(Icons.cloud_upload),
            label: const Text('إدارة النسخ الاحتياطي على Google Drive'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
          ),
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
                      ? 'الساعة ${_scheduledTime.format(context)}'
                      : 'غير مفعل',
                ),
                value: _scheduledEnabled,
                onChanged: _backupBusy ? null : _toggleScheduledBackup,
              ),
              if (_scheduledEnabled)
                ListTile(
                  leading: const Icon(Icons.access_time),
                  title: const Text('تعديل الوقت'),
                  trailing: Text(
                    _scheduledTime.format(context),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).primaryColor,
                    ),
                  ),
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
    if (iso == null) {
      return null;
    }
    final dt = DateTime.tryParse(iso);
    if (dt == null) {
      return null;
    }
    return _formatDateTime(dt);
  }

  String _formatDateTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '${dt.day}/${dt.month}/${dt.year} $h:$m';
  }

}