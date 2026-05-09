import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../providers/theme_provider.dart';
import '../../services/crashlytics_service.dart';
import '../../services/local_db.dart';
import '../../services/sync_service.dart';
import '../../utils/status_utils.dart';
import '../ai/ai_chat_screen.dart';
import '../security/blacklist_screen.dart';
import 'active_bookings_reminder_screen.dart';
import 'appwrite_settings_screen.dart';
import 'backup/comprehensive_backup_screen_v2.dart' as backup_v2;
import 'data_protection_screen.dart';
import 'google_drive_backup_screen.dart';
import 'late_payment_whatsapp_screen.dart';
import 'php_api_settings_screen.dart';
import 'remote_config_settings_screen.dart';
import 'settings_employees.dart';
import 'settings_expense_types.dart';
import 'settings_guests.dart';
import 'settings_maintenance.dart';
import 'settings_users.dart';
import 'whatsapp_daily_report_screen.dart';
import 'whatsapp_settings_screen.dart';

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
          onPressed: () async {
            await ref.read(syncServiceProvider).runSync();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('✅ تمت المزامنة بنجاح'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            }
          },
          icon: const Icon(Icons.sync),
          tooltip: 'مزامنة',
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // بطاقة الإحصائيات السريعة
          _buildQuickStatsCard(
            context,
            roomsAsync,
            bookingsAsync,
            employeesAsync,
            usersCountAsync,
          ),

          const SizedBox(height: 20),

          // قسم إدارة البيانات
          _buildSectionTitle('إدارة البيانات', Icons.manage_accounts),
          _buildSettingsGrid(context, [
            _SettingsItem(
              title: 'إدارة الموظفين',
              subtitle: 'إضافة وتعديل بيانات الموظفين',
              icon: Icons.people,
              color: Colors.blue,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const SettingsEmployeesScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'إدارة الضيوف',
              subtitle: 'عرض تاريخ وإحصائيات الضيوف',
              icon: Icons.person,
              color: Colors.green,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const SettingsGuestsScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'إدارة المستخدمين',
              subtitle: 'مستخدمي النظام والصلاحيات',
              icon: Icons.admin_panel_settings,
              color: Colors.purple,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const SettingsUsersScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'صيانة النظام',
              subtitle: 'أدوات الصيانة والفحص',
              icon: Icons.build,
              color: Colors.orange,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const SettingsMaintenanceScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'أنواع المصروفات',
              subtitle: 'إضافة وتعديل أنواع المصروفات',
              icon: Icons.category,
              color: Colors.teal,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const SettingsExpenseTypesScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'القائمة السوداء',
              subtitle: 'إضافة/إدارة الأشخاص المطلوبين',
              icon: Icons.gavel,
              color: Colors.red,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const BlacklistScreen(),
                ),
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
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const GoogleDriveBackupScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'Appwrite',
              subtitle: 'المزامنة السحابية',
              icon: Icons.cloud_sync,
              color: Colors.pink,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const AppwriteSettingsScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'PHP API',
              subtitle: 'إعدادات الخادم والاتصال',
              icon: Icons.api,
              color: Colors.indigo,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const PhpApiSettingsScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'النسخ الاحتياطي',
              subtitle: 'محلي · Google Drive · Appwrite',
              icon: Icons.backup,
              color: Colors.deepOrange,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const backup_v2.ComprehensiveBackupScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'حماية البيانات',
              subtitle: 'إعدادات المزامنة (Push/Pull)',
              icon: Icons.security,
              color: Colors.teal,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const DataProtectionScreen(),
                ),
              ),
            ),
          ]),

          const SizedBox(height: 20),

          // قسم إعدادات عامة
          _buildSectionTitle('إعدادات عامة', Icons.settings),
          _buildSettingsGrid(context, [
            _SettingsItem(
              title: 'تذكير المتبقي',
              subtitle: 'تذكير واتساب بالمتأخر للحجوزات النشطة',
              icon: Icons.payment,
              color: Colors.blue,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const ActiveBookingsReminderScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'تنبيه تأخر الدفع',
              subtitle: 'إرسال تنبيه واتساب للديون المتأخرة',
              icon: Icons.notifications_active,
              color: Colors.red,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const LatePaymentWhatsAppScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'رسالة الواتساب',
              subtitle: 'تخصيص نص رسالة الدفع',
              icon: Icons.message,
              color: Colors.green,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const WhatsAppSettingsScreen(),
                ),
              ),
            ),

            _SettingsItem(
              title: 'واتساب',
              subtitle: 'الإشعارات الفورية والتقارير اليومية',
              icon: Icons.chat,
              color: const Color(0xFF25D366),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const WhatsAppDailyReportScreen(),
                ),
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
              title: 'المساعد الذكي',
              subtitle: 'Gemini AI - تحكم ذكي بالبيانات',
              icon: Icons.smart_toy,
              color: Colors.amber.shade700,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const AiChatScreen(),
                ),
              ),
            ),
            _SettingsItem(
              title: 'Crashlytics',
              subtitle: 'مراقبة الأخطاء والأعطال',
              icon: Icons.bug_report,
              color: Colors.red.shade700,
              onTap: () => _showCrashlyticsDialog(context),
            ),
            _SettingsItem(
              title: 'Remote Config',
              subtitle: 'تحكم عن بُعد بالإعدادات',
              icon: Icons.cloud_sync,
              color: Colors.blue.shade700,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute<void>(builder: (context) => const RemoteConfigSettingsScreen(),
                ),
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
    AsyncValue<List<Room>> roomsAsync,
    AsyncValue<List<Booking>> bookingsAsync,
    AsyncValue<List<Employee>> employeesAsync,
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
                    usersCountAsync.value?.toString() ?? '---',
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
    const crossAxisCount = 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: 12,
        crossAxisSpacing: 12,
        mainAxisExtent: 130,
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
                  Icon(item.icon, size: 20, color: item.color),
                  const SizedBox(height: 8),
                  Text(
                    item.title,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.subtitle,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
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
    showDialog<void>(
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

  void _showCrashlyticsDialog(BuildContext context) {
    final crashlytics = CrashlyticsService.instance;
    final isInitialized = crashlytics.isInitialized;
    final isFirebaseConnected = crashlytics.isFirebaseConnected;
    final errorCount = crashlytics.errorCount;
    final history = crashlytics.getErrorHistory();

    // تحديد النص والأيقونة واللون حسب الحالة
    final String statusText;
    final IconData statusIcon;
    final Color statusColor;
    final Color bgColor;

    if (!isInitialized) {
      statusText = 'الخدمة غير مهيأة';
      statusIcon = Icons.error;
      statusColor = Colors.red;
      bgColor = Colors.red.shade50;
    } else if (isFirebaseConnected) {
      statusText = 'الخدمة مفعلة وتعمل';
      statusIcon = Icons.check_circle;
      statusColor = Colors.green;
      bgColor = Colors.green.shade50;
    } else {
      statusText = 'الخدمة تعمل بالتسجيل المحلي';
      statusIcon = Icons.cloud_queue;
      statusColor = Colors.orange;
      bgColor = Colors.orange.shade50;
    }

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bug_report, color: Colors.red),
            SizedBox(width: 8),
            Text('Firebase Crashlytics'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // حالة الخدمة
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(statusIcon, color: statusColor),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          statusText,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: statusColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isInitialized && !isFirebaseConnected) ...[
                  const SizedBox(height: 8),
                  Text(
                    'الاتصال بـ Firebase غير متوفر. الأخطاء تُسجل محلياً فقط.',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                  ),
                ],
                const SizedBox(height: 16),

                // إحصائيات
                Text(
                  'الأخطاء المسجلة: $errorCount',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),

                // قائمة الأخطاء الأخيرة
                if (history.isEmpty)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'لا توجد أخطاء مسجلة',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                else
                  ...history.reversed.take(10).map((entry) {
                    final severity = entry['severity'] as String;
                    final color = severity == 'fatal'
                        ? Colors.red
                        : severity == 'error'
                            ? Colors.orange
                            : Colors.amber;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        border: Border.all(color: color.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  severity.toUpperCase(),
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: color,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${entry['source']} — ${entry['action']}',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${entry['error']}',
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade700,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            entry['timestamp']?.toString() ?? '',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await crashlytics.sendUnsentReports();
              if (context.mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم إرسال التقارير المعلقة'),
                    backgroundColor: Colors.green,
                  ),
                );
              }
            },
            child: const Text('إرسال التقارير'),
          ),
          if (history.isNotEmpty)
            TextButton(
              onPressed: () {
                crashlytics.clearErrorHistory();
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم مسح سجل الأخطاء'),
                  ),
                );
              },
              child: const Text('مسح السجل', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  void _showAboutDialog(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => const AboutDialog(
        applicationName: 'تطبيق إدارة الفندق',
        applicationVersion: '1.2',
        applicationLegalese: '© 2026 Marina Hotel',
        children: [
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
  const _SettingsItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}
