import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../../core/core.dart';
import '../../../../providers/backup_provider.dart';
import '../../../../services/google_drive_backup_service.dart';

class GoogleDriveTab extends ConsumerStatefulWidget {
  const GoogleDriveTab({super.key});

  @override
  ConsumerState<GoogleDriveTab> createState() => _GoogleDriveTabState();
}

class _GoogleDriveTabState extends ConsumerState<GoogleDriveTab> {
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(backupStatusProvider);

    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        if (state.message != null) ...[
          _buildStatusMessage(state),
          const SizedBox(height: UIConstants.spacingLG),
        ],

        _buildConnectionCard(state),
        const SizedBox(height: UIConstants.spacingLG),

        if (state.isSignedIn) ...[
          _buildManualBackupCard(state),
          const SizedBox(height: UIConstants.spacingLG),

          SectionHeader(
            title: 'استعادة النسخ من Google Drive',
            icon: Icons.restore,
            action: IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: state.isWorking
                  ? null
                  : () => ref
                        .read(backupStatusProvider.notifier)
                        .refreshBackupsList(),
            ),
          ),
          _buildBackupsList(state),
        ],
      ],
    );
  }

  Widget _buildStatusMessage(BackupState state) {
    final isError = state.status == BackupStatus.error;
    return Container(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      decoration: BoxDecoration(
        color: isError ? Colors.red.shade50 : Colors.green.shade50,
        borderRadius: BorderRadius.circular(UIConstants.radiusMD),
        border: Border.all(color: isError ? Colors.red : Colors.green),
      ),
      child: Row(
        children: [
          Icon(
            isError ? Icons.error : Icons.check_circle,
            color: isError ? Colors.red : Colors.green,
          ),
          const SizedBox(width: UIConstants.spacingSM),
          Expanded(child: Text(state.message ?? '')),
        ],
      ),
    );
  }

  Widget _buildConnectionCard(BackupState state) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          children: [
            Icon(
              state.isSignedIn ? Icons.cloud_done : Icons.cloud_off,
              size: UIConstants.iconSizeXL,
              color: state.isSignedIn ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              state.isSignedIn ? 'متصل بـ Google Drive' : 'غير متصل',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: state.isSignedIn ? Colors.green : Colors.grey,
              ),
            ),
            if (state.isSignedIn && state.signedInAccount != null) ...[
              const SizedBox(height: UIConstants.spacingSM),
              Text(
                state.signedInAccount!.email,
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
            const SizedBox(height: UIConstants.spacingMD),
            ElevatedButton.icon(
              onPressed: state.isWorking
                  ? null
                  : () {
                      if (state.isSignedIn) {
                        ref.read(backupStatusProvider.notifier).signOut();
                      } else {
                        ref.read(backupStatusProvider.notifier).signInToDrive();
                      }
                    },
              icon: Icon(state.isSignedIn ? Icons.link_off : Icons.link),
              label: Text(state.isSignedIn ? 'قطع الاتصال' : 'الاتصال'),
              style: ElevatedButton.styleFrom(
                backgroundColor: state.isSignedIn
                    ? Colors.red
                    : UIConstants.backupColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualBackupCard(BackupState state) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.backup, color: Colors.green, size: 24),
                const SizedBox(width: UIConstants.spacingSM),
                Text(
                  'إنشاء نسخة احتياطية',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingSM),
            const Text(
              'إنشاء نسخة احتياطية شاملة ورفعها إلى Google Drive',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: UIConstants.spacingMD),
            if (state.status == BackupStatus.uploading &&
                state.progress != null) ...[
              LinearProgressIndicator(
                value: state.progress,
                backgroundColor: Colors.grey[300],
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
              ),
              const SizedBox(height: 8),
              Text(
                '${(state.progress! * 100).round()}% - ${state.message ?? "جاري الرفع..."}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: state.isWorking
                    ? null
                    : () => ref
                          .read(backupStatusProvider.notifier)
                          .createBackup(),
                icon: state.status == BackupStatus.uploading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cloud_upload),
                label: Text(
                  state.status == BackupStatus.uploading
                      ? 'جاري الرفع...'
                      : 'إنشاء نسخة احتياطية الآن',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackupsList(BackupState state) {
    final backups = state.availableBackups;

    if (backups.isEmpty) {
      return const EmptyStateWidget(
        message: 'لا توجد نسخ احتياطية على Google Drive',
        icon: Icons.cloud_off,
      );
    }

    return Column(
      children: backups.map((backup) => _buildBackupItem(backup)).toList(),
    );
  }

  Widget _buildBackupItem(DriveBackupFile backup) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    final sizeInMB = backup.size != null
        ? (backup.size! / (1024 * 1024)).toStringAsFixed(2)
        : '---';
    final recordsCount =
        (backup.metadata?['total_records'] as int?) ??
        int.tryParse(backup.appProperties['records_count'] ?? '') ??
        0;
    final recordsLabel = recordsCount > 0 ? recordsCount.toString() : '---';
    final formatLabel = backup.format == BackupFormat.sqlite
        ? 'SQLite'
        : 'JSON';

    return Card(
      margin: EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: const Icon(Icons.backup, color: Colors.blue),
        ),
        title: Text(
          dateFormatter.format(backup.createdTime),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          'حجم: $sizeInMB ميجابايت\nالسجلات: $recordsLabel\nالتنسيق: $formatLabel',
        ),
        trailing: IconButton(
          onPressed: () => _showRestoreConfirmation(backup),
          icon: const Icon(Icons.restore, color: Colors.orange),
          tooltip: 'استعادة',
        ),
        dense: true,
      ),
    );
  }

  void _showRestoreConfirmation(DriveBackupFile backup) {
    final dateFormatter = DateFormat('yyyy/MM/dd - HH:mm', 'ar');
    final recordsCount =
        (backup.metadata?['total_records'] as int?) ??
        int.tryParse(backup.appProperties['records_count'] ?? '') ??
        0;
    final recordsLabel = recordsCount > 0
        ? recordsCount.toString()
        : 'غير معروف';
    final formatLabel = backup.format == BackupFormat.sqlite
        ? 'SQLite'
        : 'JSON';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد الاستعادة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '⚠️ سيتم استبدال جميع البيانات الحالية بالنسخة المختارة:',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 12),
            Text('التاريخ: ${dateFormatter.format(backup.createdTime)}'),
            Text('السجلات: $recordsLabel'),
            Text('التنسيق: $formatLabel'),
            const SizedBox(height: 12),
            const Text(
              'هل أنت متأكد من المتابعة؟',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref
                  .read(backupStatusProvider.notifier)
                  .restoreFromBackup(backup.fileId);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('استعادة', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
