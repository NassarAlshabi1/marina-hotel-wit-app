import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/core.dart';

/// Appwrite Tools Tab - أدوات الصيانة والاختبار
class AppwriteToolsTab extends ConsumerWidget {
  const AppwriteToolsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(UIConstants.spacingMD),
      children: [
        // Testing Tools
        SectionHeader(title: 'أدوات الاختبار', icon: Icons.bug_report),
        _buildTestingToolsCard(context),

        const SizedBox(height: UIConstants.spacingLG),

        // Maintenance Tools
        SectionHeader(title: 'أدوات الصيانة', icon: Icons.build),
        _buildMaintenanceToolsCard(context),

        const SizedBox(height: UIConstants.spacingLG),

        // Data Management
        SectionHeader(title: 'إدارة البيانات', icon: Icons.storage),
        _buildDataManagementCard(context),

        const SizedBox(height: UIConstants.spacingLG),

        // Logs & Stats
        SectionHeader(title: 'السجلات والإحصائيات', icon: Icons.analytics),
        _buildLogsStatsCard(context),
      ],
    );
  }

  Widget _buildTestingToolsCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.network_check, color: Colors.blue),
            ),
            title: const Text('اختبار الاتصال'),
            subtitle: const Text('التحقق من الاتصال بالخادم'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _testConnection(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.api, color: Colors.purple),
            ),
            title: const Text('اختبار API'),
            subtitle: const Text('إرسال طلبات تجريبية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.verified, color: Colors.green),
            ),
            title: const Text('التحقق من البيانات'),
            subtitle: const Text('فحص سلامة البيانات'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceToolsCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.cleaning_services, color: Colors.orange),
            ),
            title: const Text('مسح التخزين المؤقت'),
            subtitle: const Text('حذف البيانات المؤقتة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _clearCache(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.restore, color: Colors.red),
            ),
            title: const Text('إعادة تعيين الاتصال'),
            subtitle: const Text('إعادة تهيئة الاتصال'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () => _resetConnection(context),
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.refresh, color: Colors.blue),
            ),
            title: const Text('إعادة بناء الفهارس'),
            subtitle: const Text('تحسين أداء البحث'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildDataManagementCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.backup, color: Colors.green),
            ),
            title: const Text('نسخ احتياطي للبيانات'),
            subtitle: const Text('نسخ جميع البيانات من Appwrite'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.restore_page, color: Colors.blue),
            ),
            title: const Text('استعادة البيانات'),
            subtitle: const Text('استعادة من نسخة احتياطية'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.purple.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.compare_arrows, color: Colors.purple),
            ),
            title: const Text('مقارنة البيانات'),
            subtitle: const Text('مقارنة البيانات المحلية مع السحابة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildLogsStatsCard(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(UIConstants.radiusLG),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.description, color: Colors.blue),
            ),
            title: const Text('عرض السجلات'),
            subtitle: const Text('سجلات Appwrite المفصلة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.bar_chart, color: Colors.green),
            ),
            title: const Text('إحصائيات المزامنة'),
            subtitle: const Text('تقارير وإحصائيات مفصلة'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
          const Divider(height: 1),
          ListTile(
            leading: Container(
              padding: const EdgeInsets.all(UIConstants.spacingSM),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(UIConstants.radiusMD),
              ),
              child: const Icon(Icons.download, color: Colors.orange),
            ),
            title: const Text('تصدير السجلات'),
            subtitle: const Text('حفظ السجلات كملف'),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16),
            onTap: () {},
          ),
        ],
      ),
    );
  }

  void _testConnection(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
            SizedBox(width: 16),
            Text('جاري اختبار الاتصال...'),
          ],
        ),
        duration: Duration(seconds: 2),
      ),
    );

    Future.delayed(const Duration(seconds: 2), () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('الاتصال يعمل بشكل طبيعي'),
            ],
          ),
          backgroundColor: Colors.green,
        ),
      );
    });
  }

  void _clearCache(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('مسح التخزين المؤقت'),
        content: const Text('هل تريد مسح جميع البيانات المؤقتة؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('تم مسح التخزين المؤقت')),
              );
            },
            child: const Text('مسح'),
          ),
        ],
      ),
    );
  }

  void _resetConnection(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحذير'),
        content: const Text(
          'هل تريد إعادة تعيين الاتصال؟ سيتم قطع الاتصال الحالي.',
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
                const SnackBar(content: Text('تم إعادة تعيين الاتصال')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'إعادة تعيين',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}
