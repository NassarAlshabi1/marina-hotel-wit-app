import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';

/// Local Backups Tab - إدارة النسخ المحلية
class LocalBackupsTab extends ConsumerWidget {
  const LocalBackupsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        // Storage Info
        _buildStorageInfoCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Quick Actions
        _buildQuickActionsRow(),

        const SizedBox(height: UIConstants.spacingLG),

        // Local Backups List
        SectionHeader(
          title: 'النسخ المحلية',
          icon: Icons.phone_android,
          action: IconButton(icon: const Icon(Icons.add), onPressed: () {}),
        ),
        _buildBackupsList(),
      ],
    );
  }

  Widget _buildStorageInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          children: [
            const Row(
              children: [
                Icon(
                  Icons.sd_storage,
                  color: Colors.green,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'تخزين الجهاز',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            const InfoRow(
              label: 'المسار',
              value: '/storage/emulated/0/Marina Hotel/backups',
              icon: Icons.folder,
              isExpandable: true,
            ),
            InfoRow(
              label: 'المساحة المستخدمة',
              value: FileSizeFormatter.formatBytes(45 * 1024 * 1024),
              icon: Icons.data_usage,
            ),
            InfoRow(
              label: 'المساحة المتاحة',
              value: FileSizeFormatter.formatBytes(12500 * 1024 * 1024),
              icon: Icons.storage,
            ),
            const SizedBox(height: UIConstants.spacingMD),
            LinearProgressIndicator(
              value: 0.35,
              backgroundColor: Colors.grey.shade200,
              color: Colors.green,
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              '35% مستخدم',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsRow() {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.backup),
            label: const Text('نسخ الآن'),
            style: ElevatedButton.styleFrom(
              backgroundColor: UIConstants.backupColor,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(UIConstants.spacingMD),
            ),
          ),
        ),
        const SizedBox(width: UIConstants.spacingMD),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.folder_open),
            label: const Text('فتح المجلد'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.all(UIConstants.spacingMD),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBackupsList() {
    final backups = [
      {
        'name': 'نسخة تلقائية',
        'date': '2024-01-29T18:00:00',
        'size': 15 * 1024 * 1024,
      },
      {
        'name': 'نسخة يدوية',
        'date': '2024-01-28T20:00:00',
        'size': 14 * 1024 * 1024,
      },
      {
        'name': 'نسخة تلقائية',
        'date': '2024-01-28T18:00:00',
        'size': 16 * 1024 * 1024,
      },
    ];

    return Column(
      children: backups.map(_buildBackupItem).toList(),
    );
  }

  Widget _buildBackupItem(Map<String, dynamic> backup) {
    return Card(
      margin: const EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: const Icon(Icons.file_present, color: Colors.green),
        ),
        title: Text(backup['name']),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              DateTimeFormatter.formatDateTime(backup['date']),
              style: const TextStyle(fontSize: 12),
            ),
            Text(
              FileSizeFormatter.formatBytes(backup['size']),
              style: const TextStyle(fontSize: 11),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore, size: 20),
                  SizedBox(width: 8),
                  Text('استعادة'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 8),
                  Text('مشاركة'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'upload',
              child: Row(
                children: [
                  Icon(Icons.cloud_upload, size: 20),
                  SizedBox(width: 8),
                  Text('رفع إلى Drive'),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 8),
                  Text('حذف', style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) {},
        ),
      ),
    );
  }
}
