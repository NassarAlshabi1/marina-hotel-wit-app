import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:marina_hotel_mobile/providers/backup_provider.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart';

/// ✅ Google Drive Tab - Backup & Restore Only
/// Sync is disabled. This tab provides manual backup and restore operations.
class GoogleDriveTab extends ConsumerStatefulWidget {
  const GoogleDriveTab({super.key});

  @override
  ConsumerState<GoogleDriveTab> createState() => _GoogleDriveTabState();
}

class _GoogleDriveTabState extends ConsumerState<GoogleDriveTab> {
  bool _isBackingUp = false;

  Future<void> _createBackup() async {
    setState(() => _isBackingUp = true);
    try {
      await ref.read(backupStatusProvider.notifier).createBackup();
    } finally {
      if (mounted) {
        setState(() => _isBackingUp = false);
      }
    }
  }

  Future<void> _restoreBackup(String fileId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: const Text(
          'سيتم استبدال جميع البيانات الحالية بالنسخة الاحتياطية. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('استعادة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    await ref.read(backupStatusProvider.notifier).restoreFromBackup(fileId);
  }

  Future<void> _deleteBackup(String fileId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تأكيد الحذف'),
        content: const Text('سيتم حذف هذه النسخة الاحتياطية نهائياً. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final service = GoogleDriveBackupService();
    await service.deleteBackup(fileId);
    ref.invalidate(backupStatusProvider);
  }

  String _formatDate(DateTime date) {
    return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final backupState = ref.watch(backupStatusProvider);

    if (!backupState.isSignedIn) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.cloud_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'يجب تسجيل الدخول إلى Google Drive',
              style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            const Text(
              'Google Drive مخصص للنسخ الاحتياطي والاستعادة فقط',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final backups = backupState.availableBackups;

    return Column(
      children: [
        // Header with backup button
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Google Drive - نسخ احتياطي واستعادة فقط',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _isBackingUp ? null : _createBackup,
                icon: _isBackingUp
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(_isBackingUp ? 'جارٍ النسخ...' : 'نسخ احتياطي'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),

        // Status message
        if (backupState.message != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: backupState.status == BackupStatus.error
                  ? Colors.red.shade50
                  : backupState.status == BackupStatus.success
                      ? Colors.green.shade50
                      : Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              backupState.message!,
              style: TextStyle(
                color: backupState.status == BackupStatus.error
                    ? Colors.red.shade700
                    : backupState.status == BackupStatus.success
                        ? Colors.green.shade700
                        : Colors.blue.shade700,
              ),
            ),
          ),

        // Progress bar
        if (backupState.progress != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(
              value: backupState.progress!.clamp(0.0, 1.0),
            ),
          ),

        // Backup list
        Expanded(
          child: backups.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.cloud_queue, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 12),
                      Text(
                        'لا توجد نسخ احتياطية',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: backups.length,
                  itemBuilder: (context, index) {
                    final backup = backups[index];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: Icon(Icons.cloud_circle, color: Colors.blue.shade400),
                        title: Text(
                          backup.name,
                          style: const TextStyle(fontSize: 13),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${_formatDate(backup.modifiedTime)} - ${_formatSize(backup.size)}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              onPressed: () => _restoreBackup(backup.fileId),
                              icon: const Icon(Icons.restore, color: Colors.orange),
                              tooltip: 'استعادة',
                            ),
                            IconButton(
                              onPressed: () => _deleteBackup(backup.id),
                              icon: Icon(Icons.delete, color: Colors.red.shade400),
                              tooltip: 'حذف',
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
