import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../components/app_scaffold.dart';
import '../../services/smart_sync_manager.dart';
import '../../services/sync_guardian.dart';
import '../../services/google_drive_backup_service.dart';
import '../../providers/smart_sync_provider.dart';
import '../../providers/repository_providers.dart';
import '../../providers/backup_provider.dart';

class SyncControlPanelScreen extends ConsumerStatefulWidget {
  const SyncControlPanelScreen({super.key});

  @override
  ConsumerState<SyncControlPanelScreen> createState() => _SyncControlPanelScreenState();
}

class _SyncControlPanelScreenState extends ConsumerState<SyncControlPanelScreen> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final smartSyncStatus = ref.watch(smartSyncStatusProvider);
    final backupState = ref.watch(backupStatusProvider);

    return AppScaffold(
      title: 'لوحة التحكم في المزامنة',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildMainToggleCard(smartSyncStatus, backupState),
          const SizedBox(height: 16),
          _buildIntervalCard(smartSyncStatus),
          const SizedBox(height: 16),
          _buildManualSyncCard(),
          const SizedBox(height: 16),
          _buildStatusCard(smartSyncStatus),
        ],
      ),
    );
  }

  Widget _buildMainToggleCard(
    AsyncValue<Map<String, dynamic>> smartSyncStatus,
    BackupStatusState backupState,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'المزامنة التلقائية',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'مزامنة تلقائية للبيانات بين جميع أجهزتك عبر Google Drive',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const Divider(),
            smartSyncStatus.when(
              data: (status) {
                final isEnabled = status['enabled'] as bool? ?? false;
                final isSignedIn = backupState.signedInAccount != null;

                return Column(
                  children: [
                    SwitchListTile(
                      value: isEnabled && isSignedIn,
                      onChanged: isSignedIn
                          ? (value) => _toggleSync(value)
                          : null,
                      title: Text(
                        isEnabled ? 'مُفعّلة' : 'معطّلة',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isEnabled ? Colors.green : Colors.grey,
                        ),
                      ),
                      subtitle: isSignedIn
                          ? Text(
                              isEnabled
                                  ? 'تعمل بشكل تلقائي في الخلفية'
                                  : 'قم بالتفعيل لبدء المزامنة',
                            )
                          : const Text(
                              'يجب تسجيل الدخول إلى Google Drive أولاً',
                              style: TextStyle(color: Colors.red),
                            ),
                      secondary: Icon(
                        isEnabled ? Icons.sync : Icons.sync_disabled,
                        color: isEnabled ? Colors.green : Colors.grey,
                      ),
                    ),
                    if (!isSignedIn)
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: ElevatedButton.icon(
                          onPressed: _navigateToGoogleDriveSettings,
                          icon: const Icon(Icons.login),
                          label: const Text('تسجيل الدخول إلى Google Drive'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(double.infinity, 48),
                          ),
                        ),
                      ),
                  ],
                );
              },
              loading: () => const Center(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                ),
              ),
              error: (err, _) => Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'خطأ في تحميل الحالة: $err',
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalCard(AsyncValue<Map<String, dynamic>> smartSyncStatus) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'فترة المزامنة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'كم مرة يتم التحقق من وجود تحديثات من الأجهزة الأخرى',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const Divider(),
            smartSyncStatus.when(
              data: (status) {
                final interval = status['interval'] as int? ?? 2;

                return Column(
                  children: [
                    Slider(
                      value: interval.toDouble(),
                      min: 1,
                      max: 60,
                      divisions: 11,
                      label: '$interval دقائق',
                      onChanged: _isLoading ? null : (value) => _changeSyncInterval(value.toInt()),
                    ),
                    Text(
                      'كل $interval دقائق',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      children: [
                        _buildIntervalChip(1),
                        _buildIntervalChip(2),
                        _buildIntervalChip(5),
                        _buildIntervalChip(10),
                        _buildIntervalChip(15),
                        _buildIntervalChip(30),
                      ],
                    ),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (err, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntervalChip(int minutes) {
    return ActionChip(
      label: Text('$minutes د'),
      onPressed: _isLoading ? null : () => _changeSyncInterval(minutes),
    );
  }

  Widget _buildManualSyncCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'مزامنة يدوية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'قم بإجراء مزامنة فورية الآن',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _performManualSync,
                    icon: const Icon(Icons.sync),
                    label: const Text('مزامنة الآن'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading ? null : _forceGuardianSync,
                    icon: const Icon(Icons.security),
                    label: const Text('مزامنة الحارس'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(AsyncValue<Map<String, dynamic>> smartSyncStatus) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'معلومات المزامنة',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const Divider(),
            smartSyncStatus.when(
              data: (status) {
                final deviceId = status['device_id'] as String? ?? 'غير معروف';
                final lastSync = status['last_sync'] as String? ?? 'لم يتم بعد';
                final conflictStrategy = status['conflict_resolution'] as String? ?? 'newerWins';

                final strategyLabel = {
                  'newerWins': 'الأحدث يفوز',
                  'manualResolve': 'حل يدوي',
                  'devicePriority': 'أولوية الجهاز',
                }[conflictStrategy] ?? conflictStrategy;

                return Column(
                  children: [
                    _buildInfoRow('معرف الجهاز', deviceId),
                    _buildInfoRow('آخر مزامنة', lastSync),
                    _buildInfoRow('حل التضارب', strategyLabel),
                  ],
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (err, _) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: Colors.grey),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleSync(bool enabled) async {
    setState(() => _isLoading = true);

    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.setEnabled(enabled);

      ref.invalidate(smartSyncStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(enabled ? '✅ تم تفعيل المزامنة التلقائية' : '⏸️ تم إيقاف المزامنة التلقائية'),
            backgroundColor: enabled ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _changeSyncInterval(int minutes) async {
    setState(() => _isLoading = true);

    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.setSyncInterval(minutes);

      ref.invalidate(smartSyncStatusProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⏰ تم تغيير الفترة إلى $minutes دقائق'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ خطأ: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _performManualSync() async {
    setState(() => _isLoading = true);

    try {
      final manager = ref.read(smartSyncManagerProvider);
      await manager.forceSyncNow();

      ref.invalidate(smartSyncStatusProvider);
      ref.invalidate(syncHealthProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت المزامنة بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشلت المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  Future<void> _forceGuardianSync() async {
    setState(() => _isLoading = true);

    try {
      final guardian = ref.read(syncGuardianProvider);
      await guardian.forceSync();

      ref.invalidate(syncHealthProvider);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ تمت مزامنة الحارس بنجاح'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشلت مزامنة الحارس: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }

    setState(() => _isLoading = false);
  }

  void _navigateToGoogleDriveSettings() {
    Navigator.pushNamed(context, '/settings/google-drive');
  }
}
