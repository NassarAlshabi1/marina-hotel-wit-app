import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../components/app_scaffold.dart';
import '../../providers/backup_provider.dart';
import 'google_drive_logs_screen.dart';

class GoogleDriveBackupScreen extends ConsumerStatefulWidget {
  const GoogleDriveBackupScreen({super.key});

  @override
  ConsumerState<GoogleDriveBackupScreen> createState() =>
      _GoogleDriveBackupScreenState();
}

class _GoogleDriveBackupScreenState
    extends ConsumerState<GoogleDriveBackupScreen> {
  bool _showAutoBackup = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(databaseSizeProvider.notifier).refresh();
    });
  }

  void _showSnackBar(String message, Color color) {
    if (!mounted) return;
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
    final autoSettings = ref.watch(autoBackupSettingsProvider);
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
      body: RefreshIndicator(
        onRefresh: () async {
          ref.read(databaseSizeProvider.notifier).refresh();
          ref.invalidate(backupHistoryProvider);
          ref.invalidate(localBackupsProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildStatusCard(backupState, theme),
            const SizedBox(height: 16),
            _buildBackupActions(backupState, theme),
            const SizedBox(height: 16),
            _buildAutoBackupSection(autoSettings, theme),
          ],
        ),
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
                    color: (isSignedIn ? Colors.green : Colors.grey)
                        .withOpacity(0.1),
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
                      if (backupState.message != null &&
                          backupState.message!.isNotEmpty)
                        Text(
                          backupState.message!,
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: Colors.grey),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (isSignedIn)
                  TextButton(
                    onPressed: _signOut,
                    child:
                        const Text('خروج', style: TextStyle(color: Colors.red)),
                  )
                else
                  FilledButton.icon(
                    onPressed: backupState.isLoading ? null : _signIn,
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
                    label: 'آخر سحابية',
                    value: lastDrive.when(
                      data: (d) =>
                          d != null ? DateFormat('MM/dd HH:mm').format(d) : '---',
                      loading: () => '...',
                      error: (_, __) => '---',
                    ),
                  ),
                ),
                Expanded(
                  child: _InfoItem(
                    icon: Icons.phone_android,
                    label: 'آخر محلية',
                    value: lastLocal.when(
                      data: (d) =>
                          d != null ? DateFormat('MM/dd HH:mm').format(d) : '---',
                      loading: () => '...',
                      error: (_, __) => '---',
                    ),
                  ),
                ),
              ],
            ),
            if (backupState.isLoading) ...[
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
    final isWorking = backupState.isLoading;
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
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
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

  Widget _buildAutoBackupSection(
      AutoBackupSettings autoSettings, ThemeData theme) {
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
                  value: autoSettings.isEnabled,
                  onChanged: (v) =>
                      ref.read(autoBackupSettingsProvider.notifier).toggle(),
                  activeColor: Colors.green,
                ),
                Icon(_showAutoBackup ? Icons.expand_less : Icons.expand_more),
              ],
            ),
            onTap: () => setState(() => _showAutoBackup = !_showAutoBackup),
          ),
          if (_showAutoBackup && autoSettings.isEnabled) ...[
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text('التكرار'),
              trailing: DropdownButton<BackupFrequency>(
                value: autoSettings.frequency,
                underline: const SizedBox(),
                items: BackupFrequency.values
                    .map((f) => DropdownMenuItem(
                          value: f,
                          child: Text(f.displayName),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    ref
                        .read(autoBackupSettingsProvider.notifier)
                        .updateSettings(autoSettings.copyWith(frequency: v));
                  }
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('الوقت'),
              trailing: TextButton(
                onPressed: () => _selectTime(autoSettings),
                child: Text(
                  '${autoSettings.time.hour.toString().padLeft(2, '0')}:${autoSettings.time.minute.toString().padLeft(2, '0')}',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.cloud),
              title: const Text('النسخ إلى السحابة'),
              trailing: Switch(
                value: autoSettings.includeCloudBackup,
                onChanged: (v) {
                  ref
                      .read(autoBackupSettingsProvider.notifier)
                      .updateSettings(autoSettings.copyWith(includeCloudBackup: v));
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _signIn() async {
    try {
      final success =
          await ref.read(backupStatusProvider.notifier).signInToGoogle();
      _showSnackBar(
        success ? 'تم تسجيل الدخول بنجاح' : 'فشل تسجيل الدخول',
        success ? Colors.green : Colors.red,
      );
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  Future<void> _signOut() async {
    final confirm = await _showConfirmDialog(
      'تسجيل الخروج',
      'هل تريد تسجيل الخروج من Google Drive؟',
    );
    if (!confirm) return;

    await ref.read(backupStatusProvider.notifier).signOutFromGoogle();
    _showSnackBar('تم تسجيل الخروج', Colors.orange);
  }

  Future<void> _backupToDrive() async {
    final confirm = await _showConfirmDialog(
      'نسخ احتياطي سحابي',
      'سيتم رفع نسخة احتياطية إلى Google Drive',
    );
    if (!confirm) return;

    try {
      final result = await ref
          .read(backupStatusProvider.notifier)
          .createBackup(backupToDrive: true, localBackup: false);
      _showSnackBar(
        result != null ? 'تم النسخ الاحتياطي بنجاح' : 'فشل النسخ الاحتياطي',
        result != null ? Colors.green : Colors.red,
      );
      ref.invalidate(backupHistoryProvider);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  Future<void> _restoreFromDrive() async {
    final backupsAsync = ref.read(backupHistoryProvider);
    final backups = backupsAsync.value ?? [];
    if (backups.isEmpty) {
      _showSnackBar('لا توجد نسخ احتياطية سحابية', Colors.orange);
      return;
    }

    final selected = await _showDriveBackupSelectionDialog(backups);
    if (selected == null) return;

    final confirm = await _showConfirmDialog(
      'استعادة من السحابة',
      'سيتم استبدال البيانات الحالية. هل أنت متأكد؟',
      isDestructive: true,
    );
    if (!confirm) return;

    try {
      final success = await ref
          .read(backupStatusProvider.notifier)
          .restoreFromBackup(selected, fromDrive: true);
      _showSnackBar(
        success ? 'تمت الاستعادة بنجاح' : 'فشلت الاستعادة',
        success ? Colors.green : Colors.red,
      );
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  Future<void> _backupLocal() async {
    try {
      final result = await ref
          .read(backupStatusProvider.notifier)
          .createBackup(backupToDrive: false, localBackup: true);
      _showSnackBar(
        result != null ? 'تم النسخ المحلي بنجاح' : 'فشل النسخ المحلي',
        result != null ? Colors.green : Colors.red,
      );
      ref.invalidate(localBackupsProvider);
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  Future<void> _restoreFromLocal() async {
    final backupsAsync = ref.read(localBackupsProvider);
    final backups = backupsAsync.value ?? [];
    if (backups.isEmpty) {
      _showSnackBar('لا توجد نسخ محلية', Colors.orange);
      return;
    }

    final selected = await _showLocalBackupSelectionDialog(backups);
    if (selected == null) return;

    final confirm = await _showConfirmDialog(
      'استعادة محلية',
      'سيتم استبدال البيانات الحالية. هل أنت متأكد؟',
      isDestructive: true,
    );
    if (!confirm) return;

    try {
      final success = await ref
          .read(backupStatusProvider.notifier)
          .restoreFromBackup(selected, fromDrive: false);
      _showSnackBar(
        success ? 'تمت الاستعادة بنجاح' : 'فشلت الاستعادة',
        success ? Colors.green : Colors.red,
      );
    } catch (e) {
      _showSnackBar('خطأ: $e', Colors.red);
    }
  }

  void _selectTime(AutoBackupSettings currentSettings) {
    showTimePicker(
      context: context,
      initialTime: currentSettings.time,
      builder: (context, child) {
        return Directionality(
          textDirection: ui.TextDirection.rtl,
          child: child!,
        );
      },
    ).then((selectedTime) {
      if (selectedTime != null) {
        ref
            .read(autoBackupSettingsProvider.notifier)
            .updateSettings(currentSettings.copyWith(time: selectedTime));
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

  Future<String?> _showDriveBackupSelectionDialog(
      List<DriveBackupFile> backups) async {
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
                leading: const Icon(Icons.cloud, color: Colors.blue),
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

  Future<String?> _showLocalBackupSelectionDialog(
      List<LocalBackupFile> backups) async {
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
                leading: const Icon(Icons.phone_android, color: Colors.orange),
                title: Text(DateFormat('yyyy/MM/dd HH:mm').format(backup.date)),
                subtitle: Text(_formatSize(backup.size)),
                onTap: () => Navigator.pop(ctx, backup.path),
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
