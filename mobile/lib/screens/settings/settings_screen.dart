import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../services/sync_service.dart';
import '../../providers/theme_provider.dart';
import '../../utils/status_utils.dart';
import 'settings_employees.dart';
import 'settings_guests.dart';
import 'settings_users.dart';
import 'settings_maintenance.dart';
import 'google_drive_backup_screen.dart';
import 'appwrite_settings_screen.dart';
import 'php_api_settings_screen.dart';
import 'whatsapp_settings_screen.dart';
import 'diagnostics_screen.dart';
import '../security/blacklist_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final roomsAsync = ref.watch(roomsListProvider);
    final bookingsAsync = ref.watch(bookingsListProvider);
    final employeesAsync = ref.watch(employeesListProvider);
    final usersCountAsync = ref.watch(usersCountProvider);

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
          _buildQuickStatsCard(context, roomsAsync, bookingsAsync,
              employeesAsync, usersCountAsync),

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
                MaterialPageRoute(
                    builder: (context) => const SettingsEmployeesScreen()),
              ),
            ),
            _SettingsItem(
              title: 'إدارة الضيوف',
              subtitle: 'عرض تاريخ وإحصائيات الضيوف',
              icon: Icons.person,
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SettingsGuestsScreen()),
              ),
            ),
            _SettingsItem(
              title: 'إدارة المستخدمين',
              subtitle: 'مستخدمي النظام والصلاحيات',
              icon: Icons.admin_panel_settings,
              color: Colors.purple,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SettingsUsersScreen()),
              ),
            ),
            _SettingsItem(
              title: 'صيانة النظام',
              subtitle: 'أدوات الصيانة والفحص',
              icon: Icons.build,
              color: Colors.orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const SettingsMaintenanceScreen()),
              ),
            ),
            _SettingsItem(
              title: 'القائمة السوداء',
              subtitle: 'إضافة/إدارة الأشخاص المطلوبين',
              icon: Icons.gavel,
              color: Colors.red,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const BlacklistScreen()),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // قسم المزامنة والنسخ الاحتياطي
          _buildSectionTitle('المزامنة والنسخ الاحتياطي', Icons.sync),
          _buildSettingsGrid(context, [
            _SettingsItem(
              title: 'Google Drive',
              subtitle: 'النسخ الاحتياطي والمزامنة والسجلات',
              icon: Icons.cloud,
              color: Colors.blue,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const GoogleDriveBackupScreen()),
              ),
            ),
            _SettingsItem(
              title: 'Appwrite',
              subtitle: 'المزامنة السحابية',
              icon: Icons.cloud_sync,
              color: Colors.pink,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const AppwriteSettingsScreen()),
              ),
            ),
            _SettingsItem(
              title: 'PHP API',
              subtitle: 'إعدادات الخادم والاتصال',
              icon: Icons.api,
              color: Colors.indigo,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const PhpApiSettingsScreen()),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // قسم إعدادات عامة
          _buildSectionTitle('إعدادات عامة', Icons.settings),
          _buildSettingsGrid(context, [
            _SettingsItem(
              title: 'رسالة الواتساب',
              subtitle: 'تخصيص نص رسالة الدفع',
              icon: Icons.message,
              color: Colors.green,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const WhatsAppSettingsScreen()),
              ),
            ),
            _SettingsItem(
              title: 'المظهر',
              subtitle: 'الوضع الليلي والألوان',
              icon: Icons.palette,
              color: Colors.purple,
              onTap: () => _showAppSettingsDialog(context),
            ),
            _SettingsItem(
              title: 'تشخيص شامل',
              subtitle: 'تقارير شاملة عن النظام والبيانات',
              icon: Icons.bug_report,
              color: Colors.teal,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const DiagnosticsScreen()),
              ),
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
    AsyncValue<int> usersCountAsync,
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
                Icon(Icons.dashboard,
                    color: Theme.of(context).primaryColor, size: 28),
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
                            ?.where(
                                (b) => StatusUtils.isActiveBooking(b.status))
                            .length
                            .toString() ??
                        '---',
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
                    (usersCountAsync.value?.toString()) ?? '---',
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

  Widget _buildStatItem(
      String title, String value, IconData icon, Color color) {
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
    final crossAxisCount = 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        childAspectRatio: 1.5,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
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
              padding: const EdgeInsets.all(10),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    item.icon,
                    size: 20,
                    color: item.color,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: const TextStyle(
                      fontSize: 9,
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


  void _showAppSettingsDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final isDark = ref.watch(themeSettingsProvider);
          return AlertDialog(
            title: const Text('إعدادات التطبيق'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.dark_mode),
                  title: const Text('المظهر الداكن'),
                  value: isDark,
                  onChanged: (v) =>
                      ref.read(themeSettingsProvider.notifier).setDarkMode(v),
                ),
                const ListTile(
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
          );
        },
      ),
    );
  }


  void _showAboutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AboutDialog(
        applicationName: 'تطبيق إدارة الفندق',
        applicationVersion: '1.2',
        applicationLegalese: '© 2026 Marina Hotel',
        children: const [
          Text('تطبيق شامل لإدارة العمليات الفندقية'),
          SizedBox(height: 6),
          Text('تصميم Eng: Nassar Alshabi'),
          Text('Phone: +967 734587456'),
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
