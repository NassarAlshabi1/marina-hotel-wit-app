import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';
import '../../../../providers/appwrite_providers.dart' as ap;
import '../../../../services/appwrite_models.dart';

/// Appwrite Devices Tab - إدارة الأجهزة المسجلة
class AppwriteDevicesTab extends ConsumerWidget {
  const AppwriteDevicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manager = ref.watch(ap.appwriteSyncManagerProvider);
    final currentId = manager.currentDeviceId;
    final devicesAsync = ref.watch(ap.devicesListProvider);

    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        _buildCurrentDeviceCard(currentId, devicesAsync),
        const SizedBox(height: UIConstants.spacingLG),
        SectionHeader(
          title: 'الأجهزة المسجلة',
          icon: Icons.devices,
          action: IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(ap.devicesListProvider),
          ),
        ),
        _buildDevicesList(devicesAsync, currentId),
      ],
    );
  }

  Widget _buildCurrentDeviceCard(
    String? currentId,
    AsyncValue<List<AppwriteDevice>> devicesAsync,
  ) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Padding(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        child: devicesAsync.when(
          data: (devices) {
            final device = _findDevice(devices, currentId);
            final statusLabel = _statusLabel(device?.status ?? 'active');
            final lastActive =
                device?.lastActive ?? device?.lastSeen ?? DateTime.now();

            return Column(
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
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: UIConstants.spacingSM),
                StatusBadge(status: statusLabel),
                const SizedBox(height: UIConstants.spacingMD),
                InfoRow(
                  label: 'اسم الجهاز',
                  value: device?.deviceName.isNotEmpty == true
                      ? device!.deviceName
                      : 'غير معروف',
                  icon: Icons.phone_android,
                ),
                InfoRow(
                  label: 'معرف الجهاز',
                  value: currentId ?? 'غير مسجل',
                  icon: Icons.fingerprint,
                ),
                InfoRow(
                  label: 'آخر نشاط',
                  value: DateTimeFormatter.getRelativeTime(
                    DateTimeFormatter.toIsoString(lastActive),
                  ),
                  icon: Icons.schedule,
                ),
              ],
            );
          },
          loading: () => Column(
            children: const [
              SizedBox(height: 16),
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('جاري تحميل بيانات الجهاز...'),
              SizedBox(height: 16),
            ],
          ),
          error: (error, _) => Column(
            children: [
              const Icon(Icons.error, color: Colors.red, size: 32),
              const SizedBox(height: 8),
              Text('تعذر تحميل معلومات الجهاز'),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDevicesList(
    AsyncValue<List<AppwriteDevice>> devicesAsync,
    String? currentId,
  ) {
    return devicesAsync.when(
      data: (devices) {
        final filtered =
            devices.where((device) => device.id != currentId).toList();

        if (filtered.isEmpty) {
          return const EmptyStateWidget(
            message: 'لا توجد أجهزة أخرى مسجلة',
            icon: Icons.devices_other,
          );
        }

        return Column(
          children: filtered.map(_buildDeviceItem).toList(),
        );
      },
      loading: () => const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (error, _) => const EmptyStateWidget(
        message: 'تعذر تحميل الأجهزة',
        icon: Icons.devices_other,
      ),
    );
  }

  Widget _buildDeviceItem(AppwriteDevice device) {
    final isActive = device.status == 'active';
    final lastActive = device.lastActive ?? device.lastSeen;

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
        title: Text(device.deviceName),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Text(
              'آخر نشاط: ${DateTimeFormatter.getRelativeTime(DateTimeFormatter.toIsoString(lastActive))}',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 2),
            Text(
              device.id,
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

  AppwriteDevice? _findDevice(List<AppwriteDevice> devices, String? deviceId) {
    if (deviceId == null) return null;
    for (final device in devices) {
      if (device.id == deviceId) {
        return device;
      }
    }
    return null;
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'inactive':
        return 'غير نشط';
      case 'suspended':
        return 'موقوف';
      default:
        return 'نشط';
    }
  }
}
