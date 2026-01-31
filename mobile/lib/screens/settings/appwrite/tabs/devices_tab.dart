import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';

/// Appwrite Devices Tab - إدارة الأجهزة المسجلة
class AppwriteDevicesTab extends ConsumerWidget {
  const AppwriteDevicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        // Current Device
        _buildCurrentDeviceCard(),

        const SizedBox(height: UIConstants.spacingLG),

        // Registered Devices
        SectionHeader(
          title: 'الأجهزة المسجلة',
          icon: Icons.devices,
          action: IconButton(icon: const Icon(Icons.add), onPressed: () {}),
        ),
        _buildDevicesList(),
      ],
    );
  }

  Widget _buildCurrentDeviceCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(UIConstants.spacingLG),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.phone_android,
                size: 48,
                color: Colors.blue,
              ),
            ),
            const SizedBox(height: UIConstants.spacingMD),
            const Text(
              'هذا الجهاز',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: UIConstants.spacingSM),
            const StatusBadge(status: 'نشط'),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'اسم الجهاز',
              value: 'Samsung Galaxy S21',
              icon: Icons.phone_android,
            ),
            InfoRow(
              label: 'معرف الجهاز',
              value: 'device_abc123',
              icon: Icons.fingerprint,
            ),
            InfoRow(
              label: 'آخر نشاط',
              value: DateTimeFormatter.getRelativeTime('2024-01-29T18:00:00'),
              icon: Icons.schedule,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDevicesList() {
    final devices = [
      {
        'name': 'iPad Pro',
        'id': 'device_xyz789',
        'lastActive': '2024-01-28T15:00:00',
        'status': 'نشط',
      },
      {
        'name': 'Huawei Tablet',
        'id': 'device_def456',
        'lastActive': '2024-01-25T10:00:00',
        'status': 'غير نشط',
      },
    ];

    if (devices.isEmpty) {
      return const EmptyStateWidget(
        message: 'لا توجد أجهزة أخرى مسجلة',
        icon: Icons.devices_other,
      );
    }

    return Column(
      children: devices.map((device) => _buildDeviceItem(device)).toList(),
    );
  }

  Widget _buildDeviceItem(Map<String, dynamic> device) {
    final isActive = device['status'] == 'نشط';

    return Card(
      margin: EdgeInsets.only(bottom: UIConstants.spacingSM),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(UIConstants.spacingSM),
          decoration: BoxDecoration(
            color: (isActive ? Colors.green : Colors.grey).withOpacity(0.1),
            borderRadius: BorderRadius.circular(UIConstants.radiusMD),
          ),
          child: Icon(
            Icons.tablet_android,
            color: isActive ? Colors.green : Colors.grey,
          ),
        ),
        title: Text(device['name']),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'آخر نشاط: ${DateTimeFormatter.getRelativeTime(device['lastActive'])}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              device['id'],
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
            ),
          ],
        ),
        trailing: PopupMenuButton(
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'details',
              child: Row(
                children: [
                  Icon(Icons.info, size: 20),
                  SizedBox(width: 8),
                  Text('التفاصيل'),
                ],
              ),
            ),
            if (isActive)
              const PopupMenuItem(
                value: 'deactivate',
                child: Row(
                  children: [
                    Icon(Icons.block, size: 20, color: Colors.orange),
                    SizedBox(width: 8),
                    Text('تعطيل', style: TextStyle(color: Colors.orange)),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'remove',
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
