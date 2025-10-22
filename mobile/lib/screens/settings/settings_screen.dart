import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../services/providers.dart';
import '../../services/sync_service.dart';
import 'settings_employees.dart';
import 'settings_guests.dart';
import 'settings_users.dart';
import 'settings_maintenance.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsListProvider);
    final bookingsAsync = ref.watch(bookingsListProvider);
    final employeesAsync = ref.watch(employeesListProvider);

    return AppScaffold(
      title: 'الإعدادات الرئيسية',
      actions: [
        IconButton(
          onPressed: () => ref.read(syncServiceProvider).runSync(),
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة الإحصائيات السريعة
          _buildQuickStatsCard(context, roomsAsync, bookingsAsync, employeesAsync),
          
          const SizedBox(height: 20),
          
          // قسم إدارة البيانات
          _buildSectionTitle('إدارة البيانات', Icons.manage_accounts),
          _buildSettingsGrid(context, [
            _SettingsItem(
              title: 'إدارة الموظفين',
              subtitle: 'إضافة وتعديل بيانات الموظفين',
              icon: Icons.people,
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsEmployeesScreen()),
              ),
            ),
            _SettingsItem(
              title: 'إدارة الضيوف',
              subtitle: 'عرض تاريخ وإحصائيات الضيوف',
              icon: Icons.person,
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsGuestsScreen()),
              ),
            ),
            _SettingsItem(
              title: 'إدارة المستخدمين',
              subtitle: 'مستخدمي النظام والصلاحيات',
              icon: Icons.admin_panel_settings,
              color: Colors.purple,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsUsersScreen()),
              ),
            ),
            _SettingsItem(
              title: 'صيانة النظام',
              subtitle: 'أدوات الصيانة والفحص',
              icon: Icons.build,
              color: Colors.orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsMaintenanceScreen()),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // قسم النظام
          _buildSectionTitle('إعدادات النظام', Icons.settings),
          _buildSettingsGrid(context, [
            _SettingsItem(
              title: 'النسخ الاحتياطي',
              subtitle: 'إنشاء واستعادة النسخ الاحتياطية',
              icon: Icons.backup,
              color: Colors.indigo,
              onTap: () => _showBackupDialog(context),
            ),
            _SettingsItem(
              title: 'إعدادات التطبيق',
              subtitle: 'تخصيص إعدادات التطبيق',
              icon: Icons.app_settings_alt,
              color: Colors.teal,
              onTap: () => _showAppSettingsDialog(context),
            ),
            _SettingsItem(
              title: 'تقارير النظام',
              subtitle: 'عرض حالة وتقارير النظام',
              icon: Icons.assessment,
              color: Colors.red,
              onTap: () => _showSystemReports(context),
            ),
            _SettingsItem(
              title: 'معلومات التطبيق',
              subtitle: 'الإصدار ومعلومات المطور',
              icon: Icons.info,
              color: Colors.grey,
              onTap: () => _showAboutDialog(context),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildQuickStatsCard(
    BuildContext context,
    AsyncValue roomsAsync,
    AsyncValue bookingsAsync,
    AsyncValue employeesAsync,
  ) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dashboard, color: Theme.of(context).primaryColor, size: 28),
                const SizedBox(width: 12),
                const Text(
                  'إحصائيات سريعة',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatItem(
                    'الغرف',
                    roomsAsync.value?.length.toString() ?? '---',
                    Icons.hotel,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'الحجوزات النشطة',
                    bookingsAsync.value
                        ?.where((b) => b.status == 'محجوزة')
                        .length
                        .toString() ?? '---',
                    Icons.assignment,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'الموظفين',
                    employeesAsync.value?.length.toString() ?? '---',
                    Icons.people,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildStatItem(
                    'المستخدمين',
                    '1', // سيتم تحديثه لاحقاً
                    Icons.admin_panel_settings,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String title, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue, size: 24),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsGrid(BuildContext context, List<_SettingsItem> items) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 2,
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    size: 32,
                    color: item.color,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      fontSize: 10,
                      color: Colors.grey,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBackupDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('النسخ الاحتياطي'),
        content: const Text('هذه الميزة ستكون متاحة قريباً'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showAppSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('إعدادات التطبيق'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.dark_mode),
              title: Text('المظهر الداكن'),
              trailing: Switch(value: false, onChanged: null),
            ),
            ListTile(
              leading: Icon(Icons.language),
              title: Text('اللغة'),
              subtitle: Text('العربية'),
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

  void _showSystemReports(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تقارير النظام'),
        content: const Text('عرض تقارير حالة النظام والأداء'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AboutDialog(
        applicationName: 'تطبيق إدارة الفندق',
        applicationVersion: '1.0.0',
        applicationLegalese: '© 2024 Marina Hotel',
        children: [
          const Text('تطبيق شامل لإدارة العمليات الفندقية'),
        ],
      ),
    );
  }
}

class _SettingsItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SettingsItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}