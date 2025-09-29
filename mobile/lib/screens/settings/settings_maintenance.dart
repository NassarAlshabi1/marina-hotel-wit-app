import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/sync_service.dart';

class SettingsMaintenanceScreen extends ConsumerWidget {
  const SettingsMaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'صيانة النظام',
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // معلومات النظام
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.info, color: Colors.blue, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'معلومات النظام',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildSystemInfo(),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // أدوات الصيانة
          const Text(
            'أدوات الصيانة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          
          _buildMaintenanceCard(
            'تنظيف البيانات المؤقتة',
            'حذف الملفات المؤقتة وتحسين الأداء',
            Icons.cleaning_services,
            Colors.blue,
            () => _showCleanupDialog(context),
          ),
          
          _buildMaintenanceCard(
            'فحص قاعدة البيانات',
            'التحقق من سلامة البيانات وإصلاح الأخطاء',
            Icons.storage,
            Colors.green,
            () => _showDatabaseCheckDialog(context),
          ),
          
          _buildMaintenanceCard(
            'إعادة تعيين التزامن',
            'إعادة ضبط خدمة المزامنة مع الخادم',
            Icons.sync_problem,
            Colors.orange,
            () => _showResetSyncDialog(context, ref),
          ),
          
          _buildMaintenanceCard(
            'تصدير البيانات',
            'إنشاء نسخة احتياطية من جميع البيانات',
            Icons.download,
            Colors.purple,
            () => _showExportDialog(context),
          ),
          
          _buildMaintenanceCard(
            'استيراد البيانات',
            'استعادة البيانات من نسخة احتياطية',
            Icons.upload,
            Colors.indigo,
            () => _showImportDialog(context),
          ),
          
          const SizedBox(height: 16),
          
          // أدوات متقدمة
          const Text(
            'أدوات متقدمة',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red),
          ),
          const SizedBox(height: 12),
          
          _buildMaintenanceCard(
            'إعادة تشغيل الخدمات',
            'إعادة تشغيل جميع خدمات التطبيق',
            Icons.restart_alt,
            Colors.red,
            () => _showRestartDialog(context),
          ),
          
          _buildMaintenanceCard(
            'إعادة تعيين التطبيق',
            'حذف جميع البيانات المحلية وإعادة التهيئة',
            Icons.settings_backup_restore,
            Colors.red,
            () => _showResetAppDialog(context),
          ),
          
          const SizedBox(height: 20),
          
          // تحذير
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.withOpacity(0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.warning, color: Colors.red),
                    SizedBox(width: 8),
                    Text(
                      'تحذير مهم',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Text(
                  'استخدام أدوات الصيانة المتقدمة قد يؤثر على البيانات. تأكد من إنشاء نسخة احتياطية قبل المتابعة.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemInfo() {
    return Column(
      children: [
        _buildInfoRow('إصدار التطبيق:', '1.0.0'),
        _buildInfoRow('إصدار النظام:', 'Flutter 3.x'),
        _buildInfoRow('حالة قاعدة البيانات:', 'متصلة'),
        _buildInfoRow('آخر مزامنة:', 'منذ 5 دقائق'),
        _buildInfoRow('مساحة التخزين المستخدمة:', '45 MB'),
        _buildInfoRow('عدد السجلات:', '1,247'),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 160,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Widget _buildMaintenanceCard(
    String title,
    String subtitle,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withOpacity(0.2),
          child: Icon(icon, color: color),
        ),
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _showCleanupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تنظيف البيانات المؤقتة'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cleaning_services, size: 48, color: Colors.blue),
            SizedBox(height: 16),
            Text('هل تريد حذف البيانات المؤقتة؟'),
            SizedBox(height: 8),
            Text(
              'سيتم حذف:\n• ملفات التخزين المؤقت\n• سجلات الأخطاء القديمة\n• البيانات المكررة',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
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
                const SnackBar(content: Text('تم تنظيف البيانات المؤقتة (قيد التطوير)')),
              );
            },
            child: const Text('تنظيف'),
          ),
        ],
      ),
    );
  }

  void _showDatabaseCheckDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('فحص قاعدة البيانات'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.database, size: 48, color: Colors.green),
            SizedBox(height: 16),
            Text('فحص سلامة قاعدة البيانات'),
            SizedBox(height: 8),
            Text(
              'سيتم فحص:\n• سلامة الجداول\n• صحة البيانات\n• الفهارس المفقودة\n• العلاقات بين الجداول',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showProgressDialog(context, 'جاري فحص قاعدة البيانات...');
            },
            child: const Text('بدء الفحص'),
          ),
        ],
      ),
    );
  }

  void _showResetSyncDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تعيين التزامن'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync_problem, size: 48, color: Colors.orange),
            SizedBox(height: 16),
            Text('إعادة ضبط خدمة المزامنة'),
            SizedBox(height: 8),
            Text(
              'سيتم:\n• إيقاف المزامنة الحالية\n• مسح ذاكرة التخزين المؤقت\n• إعادة تشغيل الخدمة\n• بدء مزامنة جديدة',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                await ref.read(syncServiceProvider).runSync();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('تم إعادة تعيين المزامنة بنجاح')),
                );
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('خطأ في إعادة التعيين: $e')),
                );
              }
            },
            child: const Text('إعادة التعيين'),
          ),
        ],
      ),
    );
  }

  void _showExportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تصدير البيانات'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download, size: 48, color: Colors.purple),
            SizedBox(height: 16),
            Text('إنشاء نسخة احتياطية شاملة'),
            SizedBox(height: 8),
            Text(
              'سيتم تصدير:\n• جميع بيانات الغرف\n• الحجوزات والضيوف\n• بيانات الموظفين\n• الإعدادات والتفضيلات',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showProgressDialog(context, 'جاري تصدير البيانات...');
            },
            child: const Text('تصدير'),
          ),
        ],
      ),
    );
  }

  void _showImportDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('استيراد البيانات'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.upload, size: 48, color: Colors.indigo),
            SizedBox(height: 16),
            Text('استعادة من نسخة احتياطية'),
            SizedBox(height: 8),
            Text(
              'تحذير: سيتم استبدال البيانات الحالية بالبيانات المستوردة',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
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
                const SnackBar(content: Text('اختيار ملف الاستيراد (قيد التطوير)')),
              );
            },
            child: const Text('اختيار ملف'),
          ),
        ],
      ),
    );
  }

  void _showRestartDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تشغيل الخدمات'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.restart_alt, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text('إعادة تشغيل جميع خدمات التطبيق'),
            SizedBox(height: 8),
            Text(
              'قد يستغرق هذا عدة ثوانِ وقد يتم قطع الاتصال مؤقتاً',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showProgressDialog(context, 'جاري إعادة تشغيل الخدمات...');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إعادة التشغيل'),
          ),
        ],
      ),
    );
  }

  void _showResetAppDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعادة تعيين التطبيق'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings_backup_restore, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text('تحذير: هذا الإجراء لا يمكن التراجع عنه!'),
            SizedBox(height: 8),
            Text(
              'سيتم:\n• حذف جميع البيانات المحلية\n• إعادة تعيين الإعدادات\n• العودة للحالة الأولية\n• طلب تسجيل دخول جديد',
              style: TextStyle(fontSize: 12, color: Colors.red),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showConfirmResetDialog(context);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('إعادة التعيين'),
          ),
        ],
      ),
    );
  }

  void _showConfirmResetDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تأكيد إعادة التعيين'),
        content: const Text(
          'هل أنت متأكد من إعادة تعيين التطبيق؟\nسيتم فقدان جميع البيانات المحلية نهائياً.',
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
                const SnackBar(content: Text('إعادة تعيين التطبيق (قيد التطوير)')),
              );
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('تأكيد الإعادة'),
          ),
        ],
      ),
    );
  }

  void _showProgressDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );

    // محاكاة عملية
    Future.delayed(const Duration(seconds: 3), () {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت العملية بنجاح')),
      );
    });
  }
}