import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';

/// Backup Overview Tab - نظرة عامة على النسخ الاحتياطي
class BackupOverviewTab extends ConsumerWidget {
  const BackupOverviewTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        // System Info Card
        _buildSystemInfoCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Quick Stats Grid
        _buildQuickStatsGrid(context),

        const SizedBox(height: UIConstants.spacingLG),

        // Recent Backups
        const SectionHeader(title: 'آخر النسخ الاحتياطية', icon: Icons.history),
        _buildRecentBackupsList(),

        const SizedBox(height: UIConstants.spacingLG),

        // Quick Actions
        const SectionHeader(title: 'إجراءات سريعة', icon: Icons.flash_on),
        _buildQuickActionsGrid(context),
      ],
    );
  }

  Widget _buildSystemInfoCard() {
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
            const Row(
              children: [
                Icon(
                  Icons.info_outline,
                  color: UIConstants.backupColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'معلومات النظام',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'حجم قاعدة البيانات',
              value: FileSizeFormatter.formatBytes(15 * 1024 * 1024),
              icon: Icons.storage,
            ),
            InfoRow(
              label: 'آخر نسخة احتياطية',
              value: DateTimeFormatter.getRelativeTime('2024-01-29T18:00:00'),
              icon: Icons.schedule,
            ),
            const InfoRow(label: 'عدد النسخ', value: '5 نسخ', icon: Icons.layers),
            InfoRow(
              label: 'المساحة الإجمالية',
              value: FileSizeFormatter.formatBytes(75 * 1024 * 1024),
              icon: Icons.pie_chart,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStatsGrid(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 360
        ? 1
        : width < 600
        ? 2
        : 3;
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: UIConstants.spacingMD,
      crossAxisSpacing: UIConstants.spacingMD,
      childAspectRatio: 1.3,
      children: [
        StatCard(
          title: 'النسخ المحلية',
          value: '3',
          icon: Icons.phone_android,
          color: Colors.green,
          onTap: () {},
        ),
        StatCard(
          title: 'Google Drive',
          value: '2',
          icon: Icons.cloud,
          color: Colors.blue,
          onTap: () {},
        ),
        StatCard(
          title: 'حجم النسخ',
          value: FileSizeFormatter.formatBytesShort(75 * 1024 * 1024),
          icon: Icons.data_usage,
          color: Colors.orange,
          onTap: () {},
        ),
        StatCard(
          title: 'حالة النظام',
          value: 'جيدة',
          icon: Icons.check_circle,
          color: Colors.green,
          onTap: () {},
        ),
      ],
    );
  }

  Widget _buildRecentBackupsList() {
    final backups = [
      {
        'name': 'نسخة تلقائية',
        'date': '2024-01-29T18:00:00',
        'size': 15 * 1024 * 1024,
        'type': 'local',
      },
      {
        'name': 'نسخة Google Drive',
        'date': '2024-01-29T12:00:00',
        'size': 15 * 1024 * 1024,
        'type': 'cloud',
      },
      {
        'name': 'نسخة يدوية',
        'date': '2024-01-28T20:00:00',
        'size': 14 * 1024 * 1024,
        'type': 'local',
      },
    ];

    return Column(
      children: backups.map(_buildBackupItem).toList(),
    );
  }

  Widget _buildBackupItem(Map<String, dynamic> backup) {
    final isCloud = backup['type'] == 'cloud';

    return Card(
      margin: const EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: (isCloud ? Colors.blue : Colors.green).withOpacity(0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: Icon(
            isCloud ? Icons.cloud : Icons.phone_android,
            color: isCloud ? Colors.blue : Colors.green,
            size: UIConstants.iconSizeMD,
          ),
        ),
        title: Text(
          backup['name'],
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              DateTimeFormatter.getRelativeTime(backup['date']),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 2),
            Text(
              FileSizeFormatter.formatBytes(backup['size']),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        trailing: IconButton(
          icon: const Icon(Icons.more_vert),
          onPressed: () {},
        ),
      ),
    );
  }

  Widget _buildQuickActionsGrid(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width < 360
        ? 1
        : width < 600
        ? 2
        : 3;
    return GridView.count(
      crossAxisCount: crossAxisCount,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: UIConstants.spacingMD,
      crossAxisSpacing: UIConstants.spacingMD,
      childAspectRatio: 1.5,
      children: [
        _buildQuickActionCard(
          'نسخ الآن',
          Icons.backup,
          UIConstants.backupColor,
          () {},
        ),
        _buildQuickActionCard('استعادة', Icons.restore, Colors.orange, () {}),
        _buildQuickActionCard(
          'رفع إلى Drive',
          Icons.cloud_upload,
          Colors.blue,
          () {},
        ),
        _buildQuickActionCard('الإعدادات', Icons.settings, Colors.grey, () {}),
      ],
    );
  }

  Widget _buildQuickActionCard(
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(UIConstants.spacingMD),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: UIConstants.iconSizeLG),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
