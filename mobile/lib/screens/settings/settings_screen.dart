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
import 'comprehensive_backup_screen.dart';
import 'data_protection_screen.dart';
import 'sync_performance_settings_screen.dart';
import 'appwrite_settings_screen.dart';
import 'sync_debug_logs_screen.dart';
import 'error_center_screen.dart';
import 'whatsapp_settings_screen.dart';
import '../security/blacklist_screen.dart';
import 'server_id_fixer_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomsListProvider);
    final bookingsAsync = ref.watch(bookingsListProvider);
    final employeesAsync = ref.watch(employeesListProvider);
    final usersCountAsync = ref.watch(usersCountProvider);

    final sections = <_SettingsSection>[
      _SettingsSection(
        title: 'إدارة العمليات',
        icon: Icons.manage_accounts,
        items: [
          _SettingsItem(
            title: 'إدارة الموظفين',
            subtitle: 'إضافة وتعديل بيانات الموظفين',
            icon: Icons.people,
            color: Colors.blue,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SettingsEmployeesScreen(),
              ),
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
                builder: (context) => const SettingsGuestsScreen(),
              ),
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
                builder: (context) => const SettingsUsersScreen(),
              ),
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
                builder: (context) => const SettingsMaintenanceScreen(),
              ),
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
                builder: (context) => const BlacklistScreen(),
              ),
            ),
          ),
        ],
      ),
      _SettingsSection(
        title: 'المزامنة والنسخ الاحتياطي',
        icon: Icons.cloud_sync,
        items: [
          _SettingsItem(
            title: 'إصلاح Server IDs',
            subtitle: 'ربط الغرف مع Appwrite (إصلاح 404)',
            icon: Icons.build_circle,
            color: Colors.red,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ServerIdFixerScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'النسخ الاحتياطي',
            subtitle: 'Google Drive + التخزين المحلي',
            icon: Icons.backup,
            color: Colors.indigo,
            onTap: () => _showBackupDialog(context),
          ),
          _SettingsItem(
            title: 'مركز النسخ والمزامنة',
            subtitle: 'توحيد النسخ الاحتياطي والمزامنة الذكية',
            icon: Icons.shield_moon,
            color: Colors.cyan,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const DataProtectionScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'تحسين أداء المزامنة',
            subtitle: 'ضبط استهلاك البطارية والبيانات',
            icon: Icons.tune,
            color: Colors.deepPurple,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SyncPerformanceSettingsScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'إعدادات Appwrite',
            subtitle: 'مزامنة سحابية وإعدادات متقدمة',
            icon: Icons.cloud_sync,
            color: Colors.blueAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const AppwriteSettingsScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'مركز الأخطاء',
            subtitle: 'Appwrite + Google Drive + مزامنة',
            icon: Icons.error_outline,
            color: Colors.redAccent,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const ErrorCenterScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'سجلات المزامنة',
            subtitle: 'مراقبة مزامنة Google Drive',
            icon: Icons.monitor_heart,
            color: Colors.deepOrange,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const SyncDebugLogsScreen(),
              ),
            ),
          ),
        ],
      ),
      _SettingsSection(
        title: 'المعلومات والتخصيص',
        icon: Icons.info_outline,
        items: [
          _SettingsItem(
            title: 'رسالة الواتساب',
            subtitle: 'تخصيص نص رسالة الدفع',
            icon: Icons.message,
            color: Colors.green,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const WhatsAppSettingsScreen(),
              ),
            ),
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
        ],
      ),
    ];

    final hasResults = sections.any(
      (section) => _filterItems(section.items).isNotEmpty,
    );

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
          _buildQuickStatsCard(
            context,
            roomsAsync,
            bookingsAsync,
            employeesAsync,
            usersCountAsync,
          ),
          const SizedBox(height: 16),
          _buildSearchField(),
          const SizedBox(height: 16),
          _buildQuickActions(context),
          const SizedBox(height: 20),
          ...sections
              .map((section) => _buildSection(context, section))
              .where((widget) => widget != null)
              .cast<Widget>(),
          if (!hasResults)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: const [
                      Icon(Icons.search_off, color: Colors.grey),
                      SizedBox(width: 12),
                      Text('لا توجد نتائج مطابقة لكلمة البحث'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _query = value),
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                onPressed: () => setState(() {
                  _searchController.clear();
                  _query = '';
                }),
                icon: const Icon(Icons.close),
              ),
        hintText: 'ابحث داخل الإعدادات...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final actions = [
      _QuickAction(
        title: 'إصلاح Server IDs',
        subtitle: 'ربط الغرف مع Appwrite',
        icon: Icons.build_circle,
        color: Colors.red,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const ServerIdFixerScreen(),
          ),
        ),
      ),
      _QuickAction(
        title: 'مزامنة الآن',
        subtitle: 'تشغيل المزامنة فوراً',
        icon: Icons.sync,
        color: Colors.blue,
        onTap: () => ref.read(syncServiceProvider).runSync(),
      ),
      _QuickAction(
        title: 'نسخ احتياطي',
        subtitle: 'إنشاء نسخة شاملة',
        icon: Icons.backup,
        color: Colors.indigo,
        onTap: () => _showBackupDialog(context),
      ),
      _QuickAction(
        title: 'إعدادات Appwrite',
        subtitle: 'اتصال ومزامنة سحابية',
        icon: Icons.cloud_sync,
        color: Colors.blueAccent,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const AppwriteSettingsScreen(),
          ),
        ),
      ),
      _QuickAction(
        title: 'سجلات المزامنة',
        subtitle: 'تتبّع مزامنة Drive',
        icon: Icons.monitor_heart,
        color: Colors.deepOrange,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const SyncDebugLogsScreen(),
          ),
        ),
      ),
    ];

    final width = MediaQuery.sizeOf(context).width;
    final crossAxisCount = width > 600 ? 3 : 2;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('اختصارات سريعة', Icons.flash_on),
        const SizedBox(height: 8),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 2.8,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: actions.length,
          itemBuilder: (context, index) => _buildQuickActionCard(actions[index]),
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(_QuickAction action) {
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: action.color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(action.icon, size: 24, color: action.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      action.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      action.subtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildSection(BuildContext context, _SettingsSection section) {
    final items = _filterItems(section.items);
    if (items.isEmpty) {
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle(section.title, section.icon),
        _buildSettingsGrid(context, items),
        const SizedBox(height: 20),
      ],
    );
  }

  List<_SettingsItem> _filterItems(List<_SettingsItem> items) {
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) {
      return items;
    }

    return items
        .where(
          (item) =>
              item.title.toLowerCase().contains(query) ||
              item.subtitle.toLowerCase().contains(query),
        )
        .toList();
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
                Icon(
                  Icons.dashboard,
                  color: Theme.of(context).primaryColor,
                  size: 28,
                ),
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
                              (b) => StatusUtils.isActiveBooking(b.status),
                            )
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
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
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
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (context, index) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = items[index];
        return Card(
          elevation: 2,
          child: InkWell(
            onTap: item.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: item.color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(item.icon, size: 28, color: item.color),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          item.subtitle,
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showBackupDialog(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ComprehensiveBackupScreen(),
      ),
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

  void _showSystemReports(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => Consumer(
        builder: (context, ref, _) {
          final backupState = ref.watch(backupStatusProvider);
          final totalBackups = ref.watch(totalBackupsCountProvider);
          final dbSize = ref.watch(databaseSizeProvider);
          final lastDrive = ref.watch(lastBackupTimeProvider);
          final lastLocal = ref.watch(lastLocalBackupTimeProvider);
          return AlertDialog(
            title: const Text('تقارير النظام'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _infoRow(
                  'تسجيل Google Drive',
                  backupState.isSignedIn ? 'متصل' : 'غير متصل',
                ),
                const SizedBox(height: 6),
                _infoRow('عدد النسخ الاحتياطية', '$totalBackups'),
                const SizedBox(height: 6),
                _infoRow('آخر نسخة سحابية', lastDrive?.toString() ?? '—'),
                const SizedBox(height: 6),
                _infoRow('آخر نسخة محلية', lastLocal?.toString() ?? '—'),
                const SizedBox(height: 6),
                _infoRow(
                  'حجم قاعدة البيانات',
                  dbSize != null
                      ? '${(dbSize / (1024 * 1024)).toStringAsFixed(2)} MB'
                      : '—',
                ),
                const Divider(height: 16),
                Text(
                  backupState.message ?? '',
                  style: const TextStyle(fontSize: 12),
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
        applicationVersion: '1.0.0',
        applicationLegalese: '© 2024 Marina Hotel',
        children: const [Text('تطبيق شامل لإدارة العمليات الفندقية')],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.grey)),
        const SizedBox(width: 12),
        Flexible(child: Text(value, textAlign: TextAlign.end)),
      ],
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

class _SettingsSection {
  final String title;
  final IconData icon;
  final List<_SettingsItem> items;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.items,
  });
}

class _QuickAction {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickAction({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
}
