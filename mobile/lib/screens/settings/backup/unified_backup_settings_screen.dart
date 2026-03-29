import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/core.dart';
import '../../../components/app_scaffold.dart';

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
                  Icons.backup,
                  color: UIConstants.backupColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'حالة النسخ الاحتياطي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'آخر نسخة احتياطية',
              value: DateTimeFormatter.getRelativeTime('2024-01-29T18:00:00'),
              icon: Icons.schedule,
            ),
            InfoRow(
              label: 'حجم قاعدة البيانات',
              value: FileSizeFormatter.formatBytes(1024 * 1024 * 15),
              icon: Icons.storage,
            ),
            const InfoRow(
              label: 'عدد النسخ',
              value: '5 نسخ',
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
          const Padding(
            padding: EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.schedule,
                  color: UIConstants.backupColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'النسخ الاحتياطي التلقائي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            onTap: _showBackupFrequencyDialog,
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.cloud,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'Google Drive',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('النسخ إلى Google Drive'),
            subtitle: const Text('نسخ احتياطي على السحابة'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.cloud_upload),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('الحساب المتصل'),
            subtitle: const Text('user@gmail.com'),
            leading: const Icon(Icons.account_circle),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('المساحة المستخدمة'),
            subtitle: const Text('25 ميجابايت من 15 جيجابايت'),
            leading: const Icon(Icons.cloud_queue),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('ضغط الملفات'),
            subtitle: const Text('ضغط النسخ قبل الرفع لتوفير المساحة'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.compress),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalBackupSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(UIConstants.spacingMD),
            child: Row(
              children: [
                Icon(
                  Icons.phone_android,
                  color: Colors.green,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'النسخ المحلي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('موقع التخزين'),
            subtitle: const Text('/storage/emulated/0/Marina Hotel/backups'),
            leading: const Icon(Icons.folder),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          const ListTile(
            title: Text('المساحة المتاحة'),
            subtitle: Text('12.5 جيجابايت من 64 جيجابايت'),
            leading: Icon(Icons.sd_storage),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('النسخ على بطاقة SD'),
            subtitle: const Text('استخدام بطاقة SD إن وُجدت'),
            value: false,
            onChanged: (value) {},
            secondary: const Icon(Icons.sd_card),
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
            leading: const Icon(Icons.backup, color: UIConstants.backupColor),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _performBackupNow,
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
            onTap: _showDeleteAllBackupsDialog,
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
              leading: Radio(
                value: 'daily',
                groupValue: 'daily',
                onChanged: (v) {},
              ),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('أسبوعياً'),
              leading: Radio(
                value: 'weekly',
                groupValue: 'daily',
                onChanged: (v) {},
              ),
              onTap: () => Navigator.pop(context),
            ),
            ListTile(
              title: const Text('شهرياً'),
              leading: Radio(
                value: 'monthly',
                groupValue: 'daily',
                onChanged: (v) {},
              ),
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

  void _performBackupNow() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('جاري إنشاء نسخة احتياطية...')),
    );
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
            onPressed: () {
              Navigator.pop(context);
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
