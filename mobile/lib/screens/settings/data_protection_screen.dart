import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../providers/appwrite_providers.dart' as ap;
import '../../providers/backup_provider.dart';
import '../../services/alarm_backup.dart';
import '../../utils/performance_monitor.dart';
import 'sync/unified_sync_settings_screen.dart';

/// ✅ (2026-09-17) Cloudflare + نسخ محلي فقط: أُزيلت أقسام Google Drive
/// (المزامنة الذكية/تفعيل Drive/الرفع إلى Drive/تعطيل Drive عند التشغيل)
/// وأُعيد بناء قسم النسخ الاحتياطي على مزود النسخ المحلي الحقيقي بعد
/// حذف AutoBackupManager (كان قلب نظام Drive) بطلب المستخدم.
class DataProtectionScreen extends ConsumerStatefulWidget {
  const DataProtectionScreen({super.key});

  @override
  ConsumerState<DataProtectionScreen> createState() =>
      _DataProtectionScreenState();
}

class _DataProtectionScreenState extends ConsumerState<DataProtectionScreen> {
  bool _backupBusy = false;
  bool _appwriteBusy = false;
  bool _scheduledEnabled = false;
  bool _localAutoBackupEnabled = false;
  TimeOfDay _scheduledTime = const TimeOfDay(hour: 21, minute: 0);

  @override
  void initState() {
    super.initState();
    unawaited(_loadBackupForm());
  }

  Future<void> _loadBackupForm() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString('auto_backup_time') ?? '21:0';
    final parts = timeString.split(':');
    final scheduled = prefs.getBool('scheduled_backup_enabled') ?? false;
    final localAuto = prefs.getBool('auto_local_backup_enabled') ?? true;
    if (!mounted) {
      return;
    }
    setState(() {
      _scheduledTime = TimeOfDay(
        hour: int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 21,
        minute: int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      );
      _scheduledEnabled = scheduled;
      _localAutoBackupEnabled = localAuto;
    });
  }

  Future<void> _toggleLocalAutoBackup(bool enabled) async {
    setState(() => _backupBusy = true);
    try {
      await ref
          .read(backupStatusProvider.notifier)
          .updateAutoBackupSettings(
            ref
                .read(backupStatusProvider)
                .autoSettings
                .copyWith(
                  isEnabled: enabled,
                  enableLocalBackup: enabled,
                  time: '${_scheduledTime.hour}:${_scheduledTime.minute}',
                ),
          );
      if (!mounted) {
        return;
      }
      setState(() => _localAutoBackupEnabled = enabled);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? 'تم تفعيل النسخ المحلي التلقائي'
                : 'تم إيقاف النسخ المحلي التلقائي',
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
      await ref.read(backupStatusProvider.notifier).cleanOldLocalBackups();
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
          ? 'تمت مزامنة Cloudflare بعد النسخة الاحتياطية'
          : 'تمت مزامنة Cloudflare بنجاح';
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
          content: Text('فشلت مزامنة Cloudflare: $e'),
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
    final backupState = ref.watch(backupStatusProvider);
    final appwriteConnection = ref.watch(ap.connectionStatusProvider);
    final appwriteStats = ref.watch(ap.syncStatsProvider);
    return PerformanceInspector(
      name: 'DataProtectionScreen',
      child: Scaffold(
        appBar: AppBar(title: const Text('إدارة النسخ والمزامنة')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSummaryRow(
                backupState,
                appwriteConnection,
                appwriteStats,
              ),
              const SizedBox(height: 24),
              _buildSectionTitle(
                'مزامنة Cloudflare السحابية',
                Icons.cloud_sync,
              ),
              const SizedBox(height: 12),
              _buildAppwriteSection(appwriteConnection, appwriteStats),
              const SizedBox(height: 32),
              _buildSectionTitle('النسخ الاحتياطي المحلي', Icons.backup),
              const SizedBox(height: 12),
              _buildBackupSection(backupState),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow(
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
              child: _buildAppwriteSummaryTile(
                appwriteConnection,
                appwriteStats,
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _buildLocalBackupSummaryTile(backupState),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLocalBackupSummaryTile(BackupState state) {
    final active = state.autoSettings.isEnabled;
    final last = state.lastLocalBackupTime;
    final subtitle = last == null ? null : _formatDateTime(last);
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'النسخ الاحتياطي المحلي',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              active ? 'مفعل' : 'معطل',
              style: TextStyle(color: active ? Colors.green : Colors.red),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                'آخر نسخة: $subtitle',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 4),
            Text(
              '${state.localBackups.length} نسخة محفوظة',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppwriteSummaryTile(
    ap.ConnectionState state,
    AsyncValue<Map<String, dynamic>> statsAsync,
  ) {
    return statsAsync.when(
      loading: () => _buildSummarySkeleton('Cloudflare'),
      error: (error, stack) => _buildSummaryError('Cloudflare'),
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
                  'Cloudflare',
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
                  'تعذر تحميل إحصائيات Cloudflare',
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
                  _appwriteBusy ? 'جارٍ المزامنة...' : 'مزامنة Cloudflare الآن',
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
              unawaited(
                Navigator.push<void>(
                  context,
                  MaterialPageRoute<void>(
                    builder: (context) => const UnifiedSyncSettingsScreen(),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.settings),
            label: const Text('إعدادات المزامنة المتقدمة'),
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

  Widget _buildBackupSection(BackupState backupState) {
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
              _buildStatusRow(
                'الحالة',
                _localAutoBackupEnabled ? 'مفعلة' : 'معطلة',
              ),
              _buildStatusRow(
                'أذونات التخزين',
                backupState.hasStoragePermission ? 'ممنوحة' : 'غير ممنوحة',
              ),
              if (backupState.databaseSizeBytes != null)
                _buildStatusRow(
                  'حجم قاعدة البيانات',
                  '${(backupState.databaseSizeBytes! / 1024).toStringAsFixed(0)} KB',
                ),
              if (backupState.localBackups.isNotEmpty)
                _buildStatusRow(
                  'النسخ المحفوظة',
                  '${backupState.localBackups.length} نسخة',
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
              _localAutoBackupEnabled
                  ? 'سيتم إنشاء نسخة محلية بعد كل تعديل'
                  : 'لن يتم إنشاء نسخ تلقائية',
            ),
            value: _localAutoBackupEnabled,
            onChanged: !_backupBusy && backupState.hasStoragePermission
                ? _toggleLocalAutoBackup
                : null,
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
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _backupBusy ? null : _cleanupBackups,
            icon: const Icon(Icons.cleaning_services),
            label: const Text('تنظيف النسخ القديمة'),
          ),
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
                  : 'نسخة شاملة + مزامنة Cloudflare',
            ),
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
