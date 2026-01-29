import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';

/// Google Drive Tab - إدارة النسخ على Google Drive
class GoogleDriveTab extends ConsumerStatefulWidget {
  const GoogleDriveTab({super.key});

  @override
  ConsumerState<GoogleDriveTab> createState() => _GoogleDriveTabState();
}

class _GoogleDriveTabState extends ConsumerState<GoogleDriveTab> {
  bool _isConnected = true;
  bool _autoBackup = true;
  bool _compression = true;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        // Connection Status
        _buildConnectionCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Settings
        _buildSettingsCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Backups List
        SectionHeader(
          title: 'النسخ على Google Drive',
          icon: Icons.cloud,
          action: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {},
          ),
        ),
        _buildBackupsList(),
      ],
    );
  }

  Widget _buildConnectionCard() {
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
              _isConnected ? Icons.cloud_done : Icons.cloud_off,
              size: UIConstants.iconSizeXL,
              color: _isConnected ? Colors.green : Colors.grey,
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              _isConnected ? 'متصل بـ Google Drive' : 'غير متصل',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: _isConnected ? Colors.green : Colors.grey,
              ),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            if (_isConnected) ...[
              Text(
                'user@gmail.com',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: UIConstants.spacingMD),
              InfoRow(
                label: 'المساحة المستخدمة',
                value: '25 ميجابايت / 15 جيجابايت',
                icon: Icons.storage,
              ),
            ],
            const SizedBox(height: UIConstants.spacingMD),
            ElevatedButton.icon(
              onPressed: () {},
              icon: Icon(_isConnected ? Icons.link_off : Icons.link),
              label: Text(_isConnected ? 'قطع الاتصال' : 'الاتصال'),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    _isConnected ? Colors.red : UIConstants.backupColor,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('النسخ التلقائي'),
            subtitle: const Text('نسخ احتياطي تلقائي على Google Drive'),
            value: _autoBackup,
            onChanged: (value) => setState(() => _autoBackup = value),
            secondary: const Icon(Icons.auto_awesome),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('ضغط الملفات'),
            subtitle: const Text('ضغط النسخ قبل الرفع'),
            value: _compression,
            onChanged: (value) => setState(() => _compression = value),
            secondary: const Icon(Icons.compress),
          ),
        ],
      ),
    );
  }

  Widget _buildBackupsList() {
    final backups = [
      {
        'name': 'نسخة تلقائية - 2024-01-29',
        'date': '2024-01-29T18:00:00',
        'size': 15 * 1024 * 1024,
      },
      {
        'name': 'نسخة تلقائية - 2024-01-28',
        'date': '2024-01-28T18:00:00',
        'size': 14 * 1024 * 1024,
      },
    ];

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

  Widget _buildBackupItem(Map<String, dynamic> backup) {
    return Card(
      margin: EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: const Icon(
            Icons.backup,
            color: Colors.blue,
          ),
        ),
        title: Text(backup['name']),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(DateTimeFormatter.formatDateTime(backup['date'])),
            Text(FileSizeFormatter.formatBytes(backup['size'])),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'download',
              child: Row(
                children: [
                  Icon(Icons.download, size: 20),
                  SizedBox(width: 8),
                  Text('تحميل'),
                ],
              ),
            ),
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
          onSelected: (value) {
            // Handle action
          },
        ),
      ),
    );
  }
}
