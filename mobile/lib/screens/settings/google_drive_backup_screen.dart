import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/backup_provider.dart';
import '../../services/google_drive_backup_service.dart';
import 'google_drive_logs_screen.dart';

class GoogleDriveBackupScreen extends ConsumerStatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  ConsumerState<GoogleDriveBackupScreen> createState() =>
      _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState
    extends ConsumerState<GoogleDriveBackupScreen> {
  bool _isLoading = false;
  bool _showAutoBackup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(databaseSizeProvider.notifier).refresh();
    });
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);
    final theme = Theme.of(context);

    return AppScaffold(
      title: 'Google Drive',
      actions: [
        IconButton(
          icon: const Icon(Icons.history),
          tooltip: 'السجلات',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const GoogleDriveLogsScreen()),
          ),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(backupState, theme),
          const SizedBox(height: 16),
          _buildBackupActions(backupState, theme),
          const SizedBox(height: 16),
          _buildAutoBackupSection(theme),
        ],
      ),
    );
  }

  Widget _buildStatusCard(BackupState backupState, ThemeData theme) {
    final isSignedIn = backupState.isSignedIn;
    final lastDrive = ref.watch(lastBackupTimeProvider);
    final lastLocal = ref.watch(lastLocalBackupTimeProvider);
    final dbSize = ref.watch(databaseSizeProvider);

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: (isSignedIn ? Colors.green : Colors.grey).withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    isSignedIn ? Icons.cloud_done : Icons.cloud_off,
                    color: isSignedIn ? Colors.green : Colors.grey,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSignedIn ? 'متصل بـ Google Drive' : 'غير متصل',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isSignedIn ? Colors.green : Colors.grey,
                        ),
                      ),
                      if (backupState.userEmail != null)
                        Text(
                          backupState.userEmail!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                    ],
                  ),
                ),
                if (isSignedIn)
                  TextButton(
                    onPressed: _signOut,
                    child: const Text('خروج', style: TextStyle(color: Colors.red)),
                  )
                else
                  FilledButton.icon(
                    onPressed: _signIn,
                    icon: const Icon(Icons.login, size: 18),
                    label: const Text('دخول'),
                  ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                Expanded(
                  child: _InfoItem(
                    icon: Icons.storage,
                    label: 'حجم القاعدة',
                    value: dbSize != null
                        ? '${(dbSize / (1024 * 1024)).toStringAsFixed(1)} MB'
                        : '---',
                  ),
                ),
                Expanded(
                  child: _InfoItem(
                    icon: Icons.cloud_upload,
                    label: 'آخر نسخة سحابية',
                    value: lastDrive != null
                        ? DateFormat('MM/dd HH:mm').format(lastDrive)
                        : '---',
                  ),
                ),
                Expanded(
                  child: _InfoItem(
                    icon: Icons.phone_android,
                    label: 'آخر نسخة محلية',
                    value: lastLocal != null
                        ? DateFormat('MM/dd HH:mm').format(lastLocal)
                        : '---',
                  ),
                ),
              ],
            ),
            if (backupState.isBackingUp || backupState.isRestoring) ...[
              const Divider(height: 24),
              Row(
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      backupState.message ?? 'جاري العمل...',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBackupActions(BackupState backupState, ThemeData theme) {
    final isWorking = backupState.isBackingUp || backupState.isRestoring || _isLoading;
    final isSignedIn = backupState.isSignedIn;

    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'النسخ الاحتياطي',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.cloud_upload,
                    label: 'نسخ سحابي',
                    color: Colors.blue,
                    isLoading: isWorking,
                    enabled: isSignedIn,
                    onPressed: _backupToDrive,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.cloud_download,
                    label: 'استعادة سحابي',
                    color: Colors.green,
                    isLoading: isWorking,
                    enabled: isSignedIn,
                    onPressed: _restoreFromDrive,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ActionButton(
                    icon: Icons.phone_android,
                    label: 'نسخ محلي',
                    color: Colors.orange,
                    isLoading: isWorking,
                    onPressed: _backupLocal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionButton(
                    icon: Icons.restore,
                    label: 'استعادة محلي',
                    color: Colors.purple,
                    isLoading: isWorking,
                    onPressed: _restoreFromLocal,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoBackupSection(ThemeData theme) {
    final autoSettings = ref.watch(autoBackupSettingsProvider);

    return Card(
      elevation: 2,
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('النسخ التلقائي'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Switch(
                  value: autoSettings.enabled,
                  onChanged: (v) => _toggleAutoBackup(v, autoSettings),
                  activeColor: Colors.green,
                ),
                Icon(_showAutoBackup ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() => _showAutoBackup = !_showAutoBackup),
          ),
          if (_showAutoBackup && autoSettings.enabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('التكرار'),
              trailing: DropdownButton<String>(
                value: autoSettings.frequency,
                underline: const SizedBox(),
                items: const [
                  DropdownMenuItem(value: 'daily', child: Text('يومي')),
                  DropdownMenuItem(value: 'weekly', child: Text('أسبوعي')),
                  DropdownMenuItem(value: 'monthly', child: Text('شهري')),
                ],
                onChanged: (v) {
                  if (v != null) {
                    ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
                      autoSettings.copyWith(frequency: v),
                    );
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('الوقت'),
              trailing: TextButton(
                onPressed: () => _selectTime(autoSettings),
                child: Text(autoSettings.time),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('النسخ إلى السحابة'),
              trailing: Switch(
                value: autoSettings.backupToDrive,
                onChanged: (v) {
                  ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
                    autoSettings.copyWith(backupToDrive: v),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(backupStatusProvider.notifier).signIn();
      _showSnackBar('تم تسجيل الدخول بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ في تسجيل الدخول', Colors.red);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _signOut() async {
    final confirm = await _showConfirmDialog(
      'تسجيل الخروج',
      'هل تريد تسجيل الخروج من Google Drive؟',
    );
    if (!confirm) return;

    await ref.read(backupStatusProvider.notifier).signOut();
    _showSnackBar('تم تسجيل الخروج', Colors.orange);
  }

  Future<void> _backupToDrive() async {
    final confirm = await _showConfirmDialog(
      'نسخ احتياطي سحابي',
      'سيتم رفع نسخة احتياطية إلى Google Drive',
    );
    if (!confirm) return;

    try {
      await ref.read(backupStatusProvider.notifier).backupToGoogleDrive();
      _showSnackBar('تم النسخ الاحتياطي بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  Future<void> _restoreFromDrive() async {
    final backups = await ref.read(backupStatusProvider.notifier).listGoogleDriveBackups();
    if (backups.isEmpty) {
      _showSnackBar('لا توجد نسخ احتياطية', Colors.orange);
      return;
    }

    final selected = await _showBackupSelectionDialog(backups);
    if (selected == null) return;

    final confirm = await _showConfirmDialog(
      'استعادة من السحابة',
      'سيتم استبدال البيانات الحالية. هل أنت متأكد؟',
      isDestructive: true,
    );
    if (!confirm) return;

    try {
      await ref.read(backupStatusProvider.notifier).restoreFromGoogleDrive(selected);
      _showSnackBar('تمت الاستعادة بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  Future<void> _backupLocal() async {
    try {
      await ref.read(backupStatusProvider.notifier).backupLocally();
      _showSnackBar('تم النسخ المحلي بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  Future<void> _restoreFromLocal() async {
    final backups = await ref.read(backupStatusProvider.notifier).listLocalBackups();
    if (backups.isEmpty) {
      _showSnackBar('لا توجد نسخ محلية', Colors.orange);
      return;
    }

    final selected = await _showBackupSelectionDialog(backups);
    if (selected == null) return;

    final confirm = await _showConfirmDialog(
      'استعادة محلية',
      'سيتم استبدال البيانات الحالية. هل أنت متأكد؟',
      isDestructive: true,
    );
    if (!confirm) return;

    try {
      await ref.read(backupStatusProvider.notifier).restoreFromLocal(selected);
      _showSnackBar('تمت الاستعادة بنجاح', Colors.green);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  void _toggleAutoBackup(bool value, AutoBackupSettings settings) {
    ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
      settings.copyWith(enabled: value),
    );
    if (value) {
      setState(() => _showAutoBackup = true);
    }
  }

  void _selectTime(AutoBackupSettings currentSettings) {
    final timeParts = currentSettings.time.split(':');
    final currentTime = TimeOfDay(
      hour: int.parse(timeParts[0]),
      minute: int.parse(timeParts[1]),
    );

    showTimePicker(
      context: context,
      initialTime: currentTime,
      builder: (context, child) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: child!,
        );
      },
    ).then((selectedTime) {
      if (selectedTime != null) {
        final timeString =
            '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}';
        ref.read(backupStatusProvider.notifier).updateAutoBackupSettings(
          currentSettings.copyWith(time: timeString),
        );
      }
    });
  }

  Future<bool> _showConfirmDialog(
    String title,
    String message, {
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: isDestructive
                ? FilledButton.styleFrom(backgroundColor: Colors.red)
                : null,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<String?> _showBackupSelectionDialog(List<BackupInfo> backups) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('اختر نسخة احتياطية'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: backups.length,
            itemBuilder: (context, index) {
              final backup = backups[index];
              return ListTile(
                leading: Icon(
                  backup.isLocal ? Icons.phone_android : Icons.cloud,
                  color: backup.isLocal ? Colors.orange : Colors.blue,
                ),
                title: Text(DateFormat('yyyy/MM/dd HH:mm').format(backup.date)),
                subtitle: Text(_formatSize(backup.size)),
                onTap: () => Navigator.pop(ctx, backup.id),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _InfoItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.grey),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isLoading;
  final bool enabled;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.isLoading,
    this.enabled = true,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = enabled ? color : Colors.grey;
    return Material(
      color: effectiveColor.withOpacity(0.1),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: (isLoading || !enabled) ? null : onPressed,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Icon(icon, color: effectiveColor, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(
                  color: effectiveColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
