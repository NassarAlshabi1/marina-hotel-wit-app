import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';

class SettingsUsersScreen extends ConsumerWidget {
  const SettingsUsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppScaffold(
      title: 'إدارة المستخدمين',
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // بطاقة معلومات المستخدم الحالي
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.account_circle, size: 32, color: Colors.blue),
                        SizedBox(width: 12),
                        Text(
                          'المستخدم الحالي',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildInfoRow('اسم المستخدم:', 'admin'),
                    _buildInfoRow('الصلاحيات:', 'مدير النظام'),
                    _buildInfoRow('تاريخ آخر دخول:', DateTime.now().toString().split(' ')[0]),
                    _buildInfoRow('حالة الحساب:', 'نشط'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 20),
            
            // قائمة الإعدادات
            const Text(
              'إدارة الحسابات',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            
            _buildOptionCard(
              'تغيير كلمة المرور',
              'تحديث كلمة مرور الحساب الحالي',
              Icons.lock,
              Colors.orange,
              () => _showChangePasswordDialog(context),
            ),
            
            _buildOptionCard(
              'إعدادات الأمان',
              'تفعيل المصادقة الثنائية والأمان',
              Icons.security,
              Colors.red,
              () => _showSecurityDialog(context),
            ),
            
            _buildOptionCard(
              'إضافة مستخدم جديد',
              'إنشاء حساب مستخدم جديد للنظام',
              Icons.person_add,
              Colors.green,
              () => _showAddUserDialog(context),
            ),
            
            _buildOptionCard(
              'إدارة الصلاحيات',
              'تحديد صلاحيات المستخدمين',
              Icons.admin_panel_settings,
              Colors.blue,
              () => _showPermissionsDialog(context),
            ),
            
            const Spacer(),
            
            // تحذير
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'إدارة المستخدمين تتطلب صلاحيات إدارية عالية. تأكد من تأمين بياناتك.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
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

  Widget _buildOptionCard(
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
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
        onTap: onTap,
      ),
    );
  }

  void _showChangePasswordDialog(BuildContext context) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تغيير كلمة المرور'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: currentPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الحالية',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: newPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'كلمة المرور الجديدة',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmPasswordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'تأكيد كلمة المرور',
                  border: OutlineInputBorder(),
                ),
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
                  const SnackBar(content: Text('تم تغيير كلمة المرور (قيد التطوير)')),
                );
              },
              child: const Text('تحديث'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSecurityDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات الأمان'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.fingerprint),
              title: Text('المصادقة البيومترية'),
              trailing: Switch(value: false, onChanged: null),
            ),
            ListTile(
              leading: Icon(Icons.lock_clock),
              title: Text('انتهاء الجلسة التلقائي'),
              subtitle: Text('30 دقيقة'),
            ),
            ListTile(
              leading: Icon(Icons.shield),
              title: Text('المصادقة الثنائية'),
              trailing: Switch(value: false, onChanged: null),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showAddUserDialog(BuildContext context) {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();
    String role = 'موظف';

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('إضافة مستخدم جديد'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: usernameController,
                  decoration: const InputDecoration(
                    labelText: 'اسم المستخدم',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'كلمة المرور',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: role,
                  decoration: const InputDecoration(
                    labelText: 'الصلاحيات',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'مدير', child: Text('مدير النظام')),
                    DropdownMenuItem(value: 'موظف', child: Text('موظف')),
                    DropdownMenuItem(value: 'مشرف', child: Text('مشرف')),
                  ],
                  onChanged: (value) => setState(() => role = value ?? role),
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
                    const SnackBar(content: Text('تم إضافة المستخدم (قيد التطوير)')),
                  );
                },
                child: const Text('إضافة'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPermissionsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إدارة الصلاحيات'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('صلاحيات النظام:', style: TextStyle(fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.hotel),
              title: Text('إدارة الغرف'),
              trailing: Icon(Icons.check, color: Colors.green),
            ),
            ListTile(
              leading: Icon(Icons.assignment),
              title: Text('إدارة الحجوزات'),
              trailing: Icon(Icons.check, color: Colors.green),
            ),
            ListTile(
              leading: Icon(Icons.people),
              title: Text('إدارة الموظفين'),
              trailing: Icon(Icons.check, color: Colors.green),
            ),
            ListTile(
              leading: Icon(Icons.assessment),
              title: Text('عرض التقارير'),
              trailing: Icon(Icons.check, color: Colors.green),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }
}