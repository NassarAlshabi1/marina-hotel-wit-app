import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../components/app_scaffold.dart';
import '../../../core/core.dart';

/// Unified Sync Settings Screen
///
/// شاشة موحدة لجميع إعدادات المزامنة
/// تجمع الإعدادات المبعثرة في:
/// - smart_sync_settings_screen.dart
/// - appwrite_settings_screen.dart (جزء المزامنة)
/// - data_protection_screen.dart (جزء المزامنة)
/// - sync_performance_settings_screen.dart
class UnifiedSyncSettingsScreen extends ConsumerStatefulWidget {
  const UnifiedSyncSettingsScreen({super.key});

  @override
  ConsumerState<UnifiedSyncSettingsScreen> createState() =>
      _UnifiedSyncSettingsScreenState();
}

class _UnifiedSyncSettingsScreenState
    extends ConsumerState<UnifiedSyncSettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'إعدادات المزامنة',
      body: ListView(
        padding: const EdgeInsets.all(UIConstants.spacingMD),
        children: [
          // نظرة عامة
          _buildOverviewSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // الإعدادات العامة
          _buildGeneralSettingsSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // إعدادات الأداء
          _buildPerformanceSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // المزامنة الذكية
          _buildSmartSyncSection(),

          const SizedBox(height: UIConstants.spacingLG),

          // Appwrite Sync
          _buildAppwriteSyncSection(),

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
                  Icons.info_outline,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'حالة المزامنة',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: UIConstants.spacingMD),
            InfoRow(
              label: 'آخر مزامنة',
              value: DateTimeFormatter.getRelativeTime('2024-01-29T18:00:00'),
              icon: Icons.schedule,
            ),
            const InfoRow(
              label: 'حالة الاتصال',
              value: 'متصل',
              icon: Icons.wifi,
              iconColor: Colors.green,
            ),
            const InfoRow(
              label: 'عناصر معلقة',
              value: '0',
              icon: Icons.pending,
              iconColor: Colors.orange,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeneralSettingsSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          SwitchListTile(
            title: const Text('تفعيل المزامنة التلقائية'),
            subtitle: const Text('مزامنة البيانات تلقائياً عند التغيير'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.sync),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('المزامنة عند بدء التشغيل'),
            subtitle: const Text('مزامنة البيانات عند فتح التطبيق'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.power_settings_new),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('فترة المزامنة'),
            subtitle: const Text('15 دقيقة'),
            leading: const Icon(Icons.timer),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: _showSyncIntervalDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildPerformanceSection() {
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
                  Icons.speed,
                  color: UIConstants.syncColor,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'الأداء والبطارية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تحسين البطارية'),
            subtitle: const Text('تقليل استهلاك البطارية أثناء المزامنة'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.battery_saver),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('WiFi فقط'),
            subtitle: const Text('مزامنة عند الاتصال بـ WiFi فقط'),
            value: false,
            onChanged: (value) {},
            secondary: const Icon(Icons.wifi),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('الحد اليومي للبيانات'),
            subtitle: const Text('50 ميجابايت'),
            leading: const Icon(Icons.data_usage),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSmartSyncSection() {
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
                  Icons.psychology,
                  color: Colors.purple,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'المزامنة الذكية',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل المزامنة الذكية'),
            subtitle: const Text('مزامنة تكيفية حسب الاستخدام والظروف'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.smart_toy),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('حل التعارضات'),
            subtitle: const Text('الأحدث يفوز'),
            leading: const Icon(Icons.merge),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('أولوية الجهاز'),
            subtitle: const Text('عادية'),
            leading: const Icon(Icons.device_hub),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildAppwriteSyncSection() {
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
                  Icons.cloud_sync,
                  color: Colors.blue,
                  size: UIConstants.iconSizeMD,
                ),
                SizedBox(width: UIConstants.spacingSM),
                Text(
                  'Appwrite Sync',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('تفعيل مزامنة Appwrite'),
            subtitle: const Text('مزامنة البيانات مع سحابة Appwrite'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.cloud),
          ),
          const Divider(height: 1),
          SwitchListTile(
            title: const Text('المزامنة الفورية'),
            subtitle: const Text('مزامنة فورية عند حدوث تغييرات'),
            value: true,
            onChanged: (value) {},
            secondary: const Icon(Icons.flash_on),
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('جداول المزامنة'),
            subtitle: const Text('اختر الجداول للمزامنة'),
            leading: const Icon(Icons.table_chart),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
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
          ListTile(
            title: const Text('مسح ذاكرة التخزين المؤقت'),
            subtitle: const Text('حذف البيانات المخزنة مؤقتاً'),
            leading: const Icon(Icons.cleaning_services),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('إعادة تعيين المزامنة'),
            subtitle: const Text('إعادة تهيئة نظام المزامنة'),
            leading: const Icon(Icons.restore, color: Colors.orange),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            title: const Text('عرض السجلات'),
            subtitle: const Text('سجلات المزامنة والأخطاء'),
            leading: const Icon(Icons.description),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  void _showSyncIntervalDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فترة المزامنة'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('5 دقائق'),
              leading: Radio(value: 5, groupValue: 15, onChanged: (v) {}),
              onTap: () => Navigator.pop<void>(context),
            ),
            ListTile(
              title: const Text('15 دقيقة'),
              leading: Radio(value: 15, groupValue: 15, onChanged: (v) {}),
              onTap: () => Navigator.pop<void>(context),
            ),
            ListTile(
              title: const Text('30 دقيقة'),
              leading: Radio(value: 30, groupValue: 15, onChanged: (v) {}),
              onTap: () => Navigator.pop<void>(context),
            ),
            ListTile(
              title: const Text('ساعة واحدة'),
              leading: Radio(value: 60, groupValue: 15, onChanged: (v) {}),
              onTap: () => Navigator.pop<void>(context),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop<void>(context),
            child: const Text('إلغاء'),
          ),
        ],
      ),
    );
  }
}
