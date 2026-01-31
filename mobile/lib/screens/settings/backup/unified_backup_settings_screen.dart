import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/core.dart';
import '../../../components/app_scaffold.dart';
import '../../../services/sync_core/sync_core.dart';

/// Unified Backup Settings Screen
///
/// شاشة موحدة لجميع إعدادات النسخ الاحتياطي
/// تجمع الإعدادات من:
/// - auto_backup_settings_screen.dart
/// - google_drive_backup_screen.dart (جزء الإعدادات)
/// - comprehensive_backup_screen.dart (جزء الإعدادات)
class UnifiedBackupSettingsScreen extends ConsumerStatefulWidget {
  const UnifiedBackupSettingsScreen({super.key});

  @override
  ConsumerState<UnifiedBackupSettingsScreen> createState() =>
      _UnifiedBackupSettingsScreenState();
}

class _UnifiedBackupSettingsScreenState
    extends ConsumerState<UnifiedBackupSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات النسخ الاحتياطي',
      body: ListView(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        children: [
          // نظرة عامة
          _buildOverviewSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // النسخ الاحتياطي التلقائي
          _buildAutoBackupSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // Google Drive
          _buildGoogleDriveSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // النسخ الاحتياطي المحلي
          _buildLocalBackupSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // إعدادات متقدمة
          _buildAdvancedSection(),
        ],
      ),
    );
  }

  Widget _buildOverviewSection() {
    final statusesAsync = ref.watch(adapterStatusesProvider);
    final localStatus = statusesAsync.valueOrNull?[SyncTargetType.localJson];
    final driveStatus = statusesAsync.valueOrNull?[SyncTargetType.googleDrive];

    final lastBackupAt = localStatus?.lastSyncAt ?? driveStatus?.lastSyncAt;
    final lastBackupLabel = lastBackupAt != null
        ? DateTimeFormatter.getRelativeTime(lastBackupAt.toIso8601String())
        : 'غير متوفر';
    final backupCount =
        (localStatus?.metadata?['backupCount'] as int?) ?? 0;
    final directory = localStatus?.metadata?['directory'] as String? ??
        'غير متوفر';

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
                Icon(
                  Icons.backup,
                  color: UIConstants.backupColor,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'حالة النسخ الاحتياطي',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'آخر نسخة احتياطية',
              value: lastBackupLabel,
              icon: Icons.schedule,
            ),
            InfoRow(
              label: 'موقع النسخ المحلي',
              value: directory,
              icon: Icons.folder,
            ),
            InfoRow(
              label: 'عدد النسخ',
              value: '$backupCount',
              icon: Icons.layers,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoBackupSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: UIConstants.backupColor,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'النسخ الاحتياطي التلقائي',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل النسخ التلقائي'),
            subtitle: const Text('نسخ احتياطي تلقائي حسب الجدول المحدد'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.auto_awesome),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('تكرار النسخ'),
            subtitle: const Text('يومياً - 2:00 صباحاً'),
            leading: const Icon(Icons.repeat),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showBackupFrequencyDialog(),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('الاحتفاظ بعدد النسخ'),
            subtitle: const Text('5 نسخ'),
            leading: const Icon(Icons.inventory),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildGoogleDriveSection() {
    final statusesAsync = ref.watch(adapterStatusesProvider);
    final status = statusesAsync.valueOrNull?[SyncTargetType.googleDrive];
    final isEnabled = status?.isEnabled ?? false;
    final isSignedIn = status?.metadata?['isSignedIn'] as bool? ?? false;
    final connectionLabel = status == null
        ? 'جاري التحقق...'
        : isSignedIn
            ? 'متصل'
            : 'غير متصل';

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.cloud,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'Google Drive',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('النسخ إلى Google Drive'),
            subtitle: Text('حالة الاتصال: $connectionLabel'),
            value: isEnabled,
            onChanged: status == null
                ? null
                : (value) async {
                    final adapter =
                        ref.read(googleDriveAdapterProvider);
                    await adapter.initialize();
                    await adapter.setEnabled(value);
                    unawaited(ref.refresh(adapterStatusesProvider));
                  },
            secondary: const Icon(Icons.cloud_upload),
          ),
          const Divider(height: 1),
          ListTile(
            title: Text(isSignedIn ? 'تسجيل الخروج' : 'تسجيل الدخول'),
            subtitle: Text(isSignedIn ? 'الحساب متصل' : 'لم يتم تسجيل الدخول'),
            leading: const Icon(Icons.account_circle),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () async {
              final adapter = ref.read(googleDriveAdapterProvider);
              await adapter.initialize();
              if (isSignedIn) {
                await adapter.signOut();
              } else {
                await adapter.signIn();
              }
              unawaited(ref.refresh(adapterStatusesProvider));
            },
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('آخر مزامنة'),
            subtitle: Text(
              status?.lastSyncAt != null
                  ? DateTimeFormatter.getRelativeTime(
                      status!.lastSyncAt!.toIso8601String(),
                    )
                  : 'غير متوفر',
            ),
            leading: const Icon(Icons.schedule),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalBackupSection() {
    final statusesAsync = ref.watch(adapterStatusesProvider);
    final status = statusesAsync.valueOrNull?[SyncTargetType.localJson];
    final isEnabled = status?.isEnabled ?? true;
    final directory = status?.metadata?['directory'] as String? ??
        'غير متوفر';
    final backupCount = status?.metadata?['backupCount'] as int? ?? 0;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.phone_android,
                  color: Colors.green,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'النسخ المحلي',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل النسخ المحلي'),
            subtitle: Text('عدد النسخ: $backupCount'),
            value: isEnabled,
            onChanged: status == null
                ? null
                : (value) async {
                    final adapter = ref.read(localJsonAdapterProvider);
                    await adapter.initialize();
                    await adapter.setEnabled(value);
                    unawaited(ref.refresh(adapterStatusesProvider));
                  },
            secondary: const Icon(Icons.save),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('موقع التخزين'),
            subtitle: Text(directory),
            leading: const Icon(Icons.folder),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('آخر نسخة'),
            subtitle: Text(
              status?.lastSyncAt != null
                  ? DateTimeFormatter.getRelativeTime(
                      status!.lastSyncAt!.toIso8601String(),
                    )
                  : 'غير متوفر',
            ),
            leading: const Icon(Icons.schedule),
          ),
        ],
      ),
    );
  }

  Widget _buildAdvancedSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.settings_suggest,
                  color: Colors.grey.shade700,
                  size: UIConstants.iconSizeMD,
                ),
                const SizedBox(width: UIConstants.spacingSM),
                const Text(
                  'إعدادات متقدمة',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تشفير النسخ'),
            subtitle: const Text('حماية النسخ بكلمة مرور'),
            value: false,
            onChanged: (value) {},
            secondary: const Icon(Icons.lock),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('نسخ احتياطي الآن'),
            subtitle: const Text('إنشاء نسخة احتياطية فورية'),
            leading: Icon(Icons.backup, color: UIConstants.backupColor),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _performBackupNow(),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('استعادة من نسخة'),
            subtitle: const Text('اختيار نسخة للاستعادة'),
            leading: const Icon(Icons.restore, color: Colors.orange),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('حذف جميع النسخ'),
            subtitle: const Text('مسح جميع النسخ الاحتياطية'),
            leading: const Icon(Icons.delete_forever, color: Colors.red),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _showDeleteAllBackupsDialog(),
          ),
        ],
      ),
    );
  }

  void _showBackupFrequencyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تكرار النسخ الاحتياطي'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('يومياً'),
              leading:
                  Radio(value: 'daily', groupValue: 'daily', onChanged: (v) {}),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('أسبوعياً'),
              leading: Radio(
                  value: 'weekly', groupValue: 'daily', onChanged: (v) {}),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('شهرياً'),
              leading: Radio(
                  value: 'monthly', groupValue: 'daily', onChanged: (v) {}),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }

  Future<void> _performBackupNow() async {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء نسخة احتياطية...')),
    );

    try {
      final local = ref.read(localJsonAdapterProvider);
      await local.initialize();
      final localStatus = await local.getStatus();
      if (localStatus.isEnabled) {
        await local.createBackup(tag: 'manual');
      }

      final drive = ref.read(googleDriveAdapterProvider);
      await drive.initialize();
      final driveStatus = await drive.getStatus();
      if (driveStatus.isEnabled && driveStatus.isConnected) {
        await drive.createBackup(tag: 'manual');
      }

      unawaited(ref.refresh(adapterStatusesProvider));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إنشاء النسخة الاحتياطية')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('فشل النسخ الاحتياطي: $e')),
      );
    }
  }

  Future<void> _deleteAllBackups() async {
    final local = ref.read(localJsonAdapterProvider);
    await local.initialize();
    final backups = await local.listBackups();
    for (final backup in backups) {
      await local.deleteBackup(backup.id);
    }
    unawaited(ref.refresh(adapterStatusesProvider));
  }

  void _showDeleteAllBackupsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text(
          'هل أنت متأكد من حذف جميع النسخ الاحتياطية؟ لا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await _deleteAllBackups();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم حذف جميع النسخ الاحتياطية')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('حذف', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
