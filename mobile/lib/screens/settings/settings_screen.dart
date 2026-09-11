// ignore_for_file: use_build_context_synchronously
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../components/app_scaffold.dart';
import '../../providers/repository_providers.dart';
import '../../providers/service_providers.dart';
import '../../providers/theme_provider.dart';
import '../../services/local_db.dart';
import '../../services/sync/sync_gate.dart';
import '../../utils/status_utils.dart';
import '../../widgets/settings/collapsible_section.dart';
import '../ai/ai_chat_screen.dart';
import '../inventory/inventory_screen.dart';
import '../security/blacklist_screen.dart';
import 'active_bookings_reminder_screen.dart';
import 'backup/comprehensive_backup_screen_v2.dart' as backup_v2;
import 'error_center_screen.dart';
import 'error_tracker_screen.dart';
import 'google_drive_backup_screen.dart';
import 'late_payment_whatsapp_screen.dart';
import 'remote_config_settings_screen.dart';
import 'settings_custom_lists.dart';
import 'settings_employees.dart';
import 'settings_guests.dart';
import 'settings_maintenance.dart';
import 'settings_users.dart';
import 'sync/unified_sync_settings_screen.dart';
import 'sync_health/sync_health_screen.dart';
import 'telegram_settings_screen.dart';
import 'whatsapp_daily_report_screen.dart';
import 'whatsapp_settings_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  // ✅ P1 (تقرير 2026-09-11): تحديث تلقائي لبطاقة الإحصائيات + طابع زمني
  // لآخر تحديث — التذيل يعرضه مع زر تحديث يدوي.
  Timer? _statsAutoRefreshTimer;
  DateTime? _lastStatsRefreshAt;

  @override
  void initState() {
    super.initState();
    _lastStatsRefreshAt = DateTime.now();
    _statsAutoRefreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        _refreshQuickStats();
      }
    });
  }

  @override
  void dispose() {
    _statsAutoRefreshTimer?.cancel();
    super.dispose();
  }

  void _refreshQuickStats() {
    setState(() {
      _lastStatsRefreshAt = DateTime.now();
    });
    ref.invalidate(roomsListProvider);
    ref.invalidate(bookingsListProvider);
    ref.invalidate(employeesListProvider);
    ref.invalidate(usersCountProvider);
  }

  /// ✅ قراءة رقم الإصدار ديناميكياً من package_info_plus
  Future<String> _getAppVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return '${info.version}+${info.buildNumber}';
    } catch (_) {
      return '1.2.0+3';
    }
  }

  @override
  Widget build(BuildContext context) {
    final roomsAsync = ref.watch(roomsListProvider);
    final bookingsAsync = ref.watch(bookingsListProvider);
    final employeesAsync = ref.watch(employeesListProvider);
    final usersCountAsync = ref.watch(usersCountProvider);
    // ✅ P1: مراقبة بوابة المزامنة — مؤشر الحالة الحيّ في شاشة الإعدادات
    final gateAsync = ref.watch(syncGateStateProvider);
    final gateState = gateAsync.valueOrNull ?? SyncGate.instance.state;

    return AppScaffold(
      title: 'الإعدادات',
      // ✅ (2026-09-11) P0: لا يوجد actions هنا — SyncActionButton موجود في AppScaffold
      body: Column(
        children: [
          // ✅ بطاقة الإحصائيات السريعة
          _buildQuickStatsCard(
            context,
            roomsAsync,
            bookingsAsync,
            employeesAsync,
            usersCountAsync,
            gateState,
          ),

          // ✅ P1: مؤشر حالة المزامنة الحيّ (بوابة SyncGate) — نقرة
          // تفتح شاشة صحة المزامنة
          _buildSyncStatusStrip(context, gateState),

          // ✅ العرض السابق: الأقسام ظاهرة دائماً بدون طيّ.
          // يحافظ ذلك على قابلية اكتشاف كل الوظائف مع إبقاء التمرير واحداً.
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverToBoxAdapter(
                  child: RepaintBoundary(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildSettingsContent(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsContent(BuildContext context) {
    // ✅ (2026-09-10) إعادة تنظيم UI/UX — Progressive Disclosure:
    // كانت الأقسام الأربعة ظاهرة دائماً (24 بطاقة دفعة واحدة) مما
    // يسبب تزاحماً بصرياً. الآن: قسم إدارة البيانات (الأكثر استخداماً)
    // مفتوح افتراضياً، والأقسام الأخرى مطوية بعناوين + عدّادات — كل
    // الخيارات على بعد نقرة واحدة، ولا حذف ولا تعطيل لأي وظيفة
    // (نفس _getSectionItems ونفس _buildSettingsGrid حرفياً).
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CollapsibleSection(
          title: 'إدارة البيانات',
          icon: Icons.manage_accounts,
          count: _getSectionItems(context, 'data').length,
          initiallyExpanded: true,
          children: [
            _buildSettingsGrid(context, _getSectionItems(context, 'data')),
          ],
        ),
        const SizedBox(height: 20),
        CollapsibleSection(
          title: 'المزامنة والنسخ الاحتياطي',
          icon: Icons.sync,
          count: _getSectionItems(context, 'sync').length,
          subtitle: 'Cloudflare · Google Drive · حالة المزامنة',
          children: [
            _buildSettingsGrid(context, _getSectionItems(context, 'sync')),
          ],
        ),
        const SizedBox(height: 20),
        CollapsibleSection(
          title: 'الإشعارات والتقارير',
          icon: Icons.notifications,
          count: _getSectionItems(context, 'whatsapp').length,
          subtitle: 'إقفال اليوم · WhatsApp · Telegram',
          children: [
            _buildSettingsGrid(
              context,
              _getSectionItems(context, 'whatsapp'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        CollapsibleSection(
          title: 'التطبيق والخدمات',
          icon: Icons.apps,
          count: _getSectionItems(context, 'app').length,
          subtitle: 'المظهر · المساعد الذكي · الأخطاء · Remote Config',
          children: [
            _buildSettingsGrid(context, _getSectionItems(context, 'app')),
          ],
        ),
      ],
    );
  }

  // ─── قوائم العناصر حسب القسم ───

  // ignore: unused_element
  List<_SettingsItem> _getAllSettingsItems(BuildContext context) {
    return [
      ..._getSectionItems(context, 'data'),
      ..._getSectionItems(context, 'sync'),
      ..._getSectionItems(context, 'whatsapp'),
      ..._getSectionItems(context, 'app'),
    ];
  }

  List<_SettingsItem> _getSectionItems(BuildContext context, String section) {
    switch (section) {
      case 'data':
        return [
          _SettingsItem(
            title: 'إدارة الموظفين',
            subtitle: 'إضافة وتعديل بيانات الموظفين',
            icon: Icons.people,
            color: Colors.blue,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const SettingsEmployeesScreen(),
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
              MaterialPageRoute<void>(
                builder: (context) => const SettingsUsersScreen(),
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
              MaterialPageRoute<void>(
                builder: (context) => const SettingsGuestsScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'القوائم المنسدلة',
            subtitle: 'إدارة أنواع المصروفات والهوية والدفع',
            icon: Icons.list_alt,
            color: Colors.teal,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const SettingsCustomListsScreen(),
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
              MaterialPageRoute<void>(
                builder: (context) => const SettingsMaintenanceScreen(),
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
              MaterialPageRoute<void>(
                builder: (context) => const BlacklistScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'المخزون',
            subtitle: 'الأصناف والرصيد والوارد والصرف والجرد',
            icon: Icons.inventory_2,
            color: Colors.brown,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const InventoryScreen(),
              ),
            ),
          ),
        ];

      case 'sync':
        return [
          _SettingsItem(
            title: 'المزامنة بين الأجهزة',
            subtitle: 'التحكم في مزامنة Cloudflare والأداء والشبكة',
            icon: Icons.sync,
            color: Colors.blue,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const UnifiedSyncSettingsScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'النسخ الاحتياطي والاستعادة',
            subtitle: 'نسخ محلية آمنة ومزامنة Cloudflare D1',
            icon: Icons.backup,
            color: Colors.deepOrange,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) =>
                    const backup_v2.ComprehensiveBackupScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'المزامنة السحابية',
            subtitle: 'رفع وسحب البيانات عبر Cloudflare D1 وحالة الأجهزة',
            icon: Icons.cloud_sync,
            color: Colors.pink,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const UnifiedSyncSettingsScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'حالة المزامنة',
            subtitle: 'مراقبة صحة النظام والعمليات المعلقة',
            icon: Icons.health_and_safety,
            color: Colors.green,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const SyncHealthScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'النسخ الاحتياطي - Google Drive',
            subtitle: 'نسخ احتياطي واستعادة من Google Drive',
            icon: Icons.cloud_upload,
            color: Colors.teal,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const GoogleDriveBackupScreen(),
              ),
            ),
          ),
        ];

      case 'whatsapp':
        return [
          _SettingsItem(
            title: 'إقفال اليوم',
            subtitle: 'تقرير يومي عبر WhatsApp و Telegram',
            icon: Icons.nightlight_round,
            color: Colors.indigo,
            onTap: () => _performNightAudit(context),
          ),
          _SettingsItem(
            title: 'تذكير المتبقي',
            subtitle: 'تذكير واتساب بالمتأخر للحجوزات النشطة',
            icon: Icons.payment,
            color: Colors.blue,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const ActiveBookingsReminderScreen(),
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
              MaterialPageRoute<void>(
                builder: (context) => const LatePaymentWhatsAppScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'ربط وقوالب WhatsApp',
            subtitle: 'إعداد الاتصال وتخصيص نص رسالة الدفع',
            icon: Icons.message,
            color: Colors.green,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const WhatsAppSettingsScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'إشعارات وتقارير WhatsApp',
            subtitle: 'تفعيل الأحداث الفورية والملخص اليومي',
            icon: Icons.chat,
            color: const Color(0xFF25D366),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const WhatsAppDailyReportScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'Telegram',
            subtitle: 'إعداد البوت وإشعارات الأحداث والتقرير اليومي',
            icon: Icons.send,
            color: Colors.lightBlue,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const TelegramSettingsScreen(),
              ),
            ),
          ),
        ];

      case 'app':
        return [
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
              MaterialPageRoute<void>(
                builder: (context) => const AiChatScreen(),
              ),
            ),
          ),
          _SettingsItem(
            // ✅ (2026-09-05) كانت تفتح حواراً مختصراً بينما شاشة تتبع
            // الأخطاء الكاملة (ErrorTrackerScreen — فلترة/نسخ/سجل) كانت
            // شاشة يتيمة غير قابلة للوصول. الآن الإدخال يفتح الشاشة
            // الكاملة (تستخدم CrashlyticsService داخلياً) — تجهيزاً
            // للإنتاج الحقيقي، مع إدخال ثانٍ لمركز أخطاء المزامنة.
            title: 'تتبع الأخطاء والأعطال',
            subtitle: 'سجل الأخطاء الكامل مع النسخ والفلترة',
            icon: Icons.bug_report,
            color: Colors.red.shade700,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const ErrorTrackerScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'مركز أخطاء المزامنة',
            subtitle: 'أخطاء السحابة والنسخ الاحتياطي وسجلات المزامنة',
            icon: Icons.report,
            color: Colors.deepOrange.shade700,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const ErrorCenterScreen(),
              ),
            ),
          ),
          _SettingsItem(
            title: 'Remote Config',
            subtitle: 'تحكم عن بُعد بالإعدادات',
            icon: Icons.cloud_sync,
            color: Colors.blue.shade700,
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(
                builder: (context) => const RemoteConfigSettingsScreen(),
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
        ];

      default:
        return [];
    }
  }

  // ─── بطاقة الإحصائيات ───

  Widget _buildQuickStatsCard(
    BuildContext context,
    AsyncValue<List<Room>> roomsAsync,
    AsyncValue<List<Booking>> bookingsAsync,
    AsyncValue<List<Employee>> employeesAsync,
    AsyncValue<int> usersCountAsync,
    SyncGateState gateState,
  ) {
    // ✅ بطاقة مُصغّرة: padding/margin/icon/font sizes كلها مُقلّصة
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.dashboard,
                  color: Theme.of(context).primaryColor,
                  size: 18,
                ),
                const SizedBox(width: 6),
                const Text(
                  'إحصائيات سريعة',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
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
                    'النشطة',
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
            const SizedBox(height: 6),
            // ✅ P1: مؤشر صحة المزامنة + تذييل التحديث التلقائي
            // التسمية Expanded مع ellipsis — لا overflow حتى مع الخطوط العريضة
            Row(
              children: [
                Icon(
                  gateState.isBusy ? Icons.sync : Icons.cloud_done,
                  size: 11,
                  color: gateState.isBusy ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    gateState.isBusy ? 'مزامنة جارية الآن' : 'المزامنة جاهزة',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: gateState.isBusy ? Colors.orange : Colors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _lastStatsRefreshAt == null
                      ? ''
                      : 'آخر تحديث: ${_formatTime(_lastStatsRefreshAt!)}',
                  maxLines: 1,
                  softWrap: false,
                  style: const TextStyle(fontSize: 10, color: Colors.grey),
                ),
                const SizedBox(width: 2),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 24,
                      minHeight: 24,
                    ),
                    iconSize: 14,
                    tooltip: 'تحديث الإحصائيات',
                    icon: const Icon(Icons.refresh),
                    onPressed: _refreshQuickStats,
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
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          title,
          style: const TextStyle(fontSize: 10, color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  // ─── ✅ P1: مؤشر حالة المزامنة الحيّ ───

  String _formatTime(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  /// شريط حالة المزامنة الحيّ — يراقب بوابة SyncGate عبر
  /// syncGateStateProvider: أثناء العملية يعرض النوع/المصدر/المدة،
  /// والنقرة تفتح شاشة صحة المزامنة.
  Widget _buildSyncStatusStrip(BuildContext context, SyncGateState gate) {
    final busy = gate.isBusy;
    final elapsed = gate.elapsedMs;
    final elapsedText = elapsed == null
        ? ''
        : ' · ${(elapsed / 1000).round()}s';
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: ListTile(
        dense: true,
        visualDensity: VisualDensity.compact,
        onTap: () => Navigator.push<void>(
          context,
          MaterialPageRoute<void>(
            builder: (context) => const SyncHealthScreen(),
          ),
        ),
        leading: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.cloud_done, color: Colors.green, size: 20),
        title: Text(
          busy ? 'جارٍ تنفيذ مزامنة الآن...' : 'لا مزامنة جارية — جاهزة',
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
        ),
        subtitle: busy
            ? Text(
                '${gate.operation ?? '-'} · ${gate.source ?? '-'}$elapsedText',
                style: const TextStyle(fontSize: 10),
              )
            : null,
        trailing: const Icon(Icons.chevron_right, size: 18),
      ),
    );
  }

  // ─── شبكة الإعدادات ───

  Widget _buildSettingsGrid(BuildContext context, List<_SettingsItem> items) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // نفس تخطيط فرع A: بطاقات صغيرة ثابتة بثلاثة أعمدة.
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
              elevation: 1,
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
                        style: const TextStyle(
                          fontSize: 12,
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
      },
    );
  }

  // ─── Dialogs ───

  /// ✅ إقفال اليوم (Night Audit) — يُغلق اليوم الفندقي ويرسل التقرير
  /// عبر WhatsApp و Telegram. نُقل من شاشة Dashboard إلى الإعدادات لتفادي
  /// اهتزاز الشاشة أثناء المزامنة (الـ header في Dashboard يُعاد بناؤه
  /// باستمرار مع تحديث حالة المزامنة).
  Future<void> _performNightAudit(BuildContext context) async {
    final service = ref.read(nightAuditServiceProvider);
    final isClosed = await service.isDayClosed(null);
    // ✅ فحص mounted بعد await لمنع استخدام context إذا أُغلقت الشاشة.
    // نتحقق أيضاً من context.mounted لأن context بارامتر (قد يختلف عن this.context).
    // (مراجعة PR #451 r3521832508)
    if (!mounted || !context.mounted) return;

    if (isClosed) {
      // اليوم مُقفل — اسأل عن إعادة الإرسال
      final reSend = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('إعادة إرسال التقرير'),
          content: const Text(
            'تم إقفال اليوم بالفعل. هل تريد إعادة إرسال التقرير؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إعادة الإرسال'),
            ),
          ],
        ),
      );
      if (reSend != true) return;
    } else {
      // تأكيد الإقفال
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.nightlight_round, color: Colors.indigo),
              SizedBox(width: 8),
              Text('إقفال اليوم'),
            ],
          ),
          content: const Text(
            'سيتم تجميع كل بيانات اليوم المالية وإقفال اليوم الفندقي '
            'وإرسال التقرير عبر WhatsApp و Telegram.\n\n'
            'هل تريد المتابعة؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إقفال وإرسال'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    // تنفيذ الإقفال
    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            SizedBox(width: 12),
            Text('جاري إقفال اليوم وإرسال التقرير...'),
          ],
        ),
        duration: Duration(minutes: 5),
      ),
    );

    final result = await service.closeDay(force: isClosed);

    if (!mounted || !context.mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message),
        backgroundColor: result.success ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showAppSettingsDialog(BuildContext context) {
    unawaited(
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
                  // ✅ تم إزالة عنصر "اللغة" الجامد — لم يكن функциaly
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
      ),
    );
  }

  /// ✅ قراءة الإصدار ديناميكياً
  Future<void> _showAboutDialog(BuildContext context) async {
    final version = await _getAppVersion();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AboutDialog(
        applicationName: 'تطبيق إدارة فندق مارينا',
        applicationVersion: version,
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
