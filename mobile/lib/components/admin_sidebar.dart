import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/responsive/responsive.dart';
import '../providers/auth_provider.dart';

class AdminSidebar extends ConsumerWidget {

  const AdminSidebar({
    super.key,
    required this.currentRoute,
    required this.onRouteSelected,
  });
  final String currentRoute;
  final void Function(String) onRouteSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    bool can(String key) {
      final u = auth.currentUser;
      if (u == null) {
        return false;
      }
      if (u.permissions.contains('all') || u.userType == 'admin') {
        return true;
      }
      return u.permissions.contains(key);
    }

    const sidebarColor = Color(0xFF0F172A);
    const headerColor = Color(0xFF16213C);
    final cardOverlay = Colors.white.withValues(alpha: 0.08);
    final dividerColor = Colors.white.withValues(alpha: 0.12);
    final inactiveColor = Colors.white.withValues(alpha: 0.72);

    // ─── عرض الشريط الجانبي حسب حجم الشاشة ───
    final sidebarWidth = context.sidebarWidth;

    // ─── أحجام متجاوبة ───
    final isDesktop = context.isDesktopOrAbove;
    final headerPadding = isDesktop
        ? const EdgeInsets.all(24)
        : const EdgeInsets.symmetric(horizontal: 16, vertical: 18);
    final logoIconSize = isDesktop ? 32.0 : 28.0;
    final logoIconPadding = isDesktop ? 12.0 : 10.0;
    final hotelNameFontSize = isDesktop ? 18.0 : 16.0;
    final menuIconSize = isDesktop ? 24.0 : 22.0;
    final menuFontSize = isDesktop ? 14.0 : 13.0;
    final userCardPadding = isDesktop
        ? const EdgeInsets.all(12)
        : const EdgeInsets.symmetric(horizontal: 10, vertical: 8);
    final menuHPadding = isDesktop ? 16.0 : 12.0;

    return Container(
      width: sidebarWidth,
      color: sidebarColor,
      child: Column(
        children: [
          // ─── رأس الشريط الجانبي ───
          Container(
            padding: headerPadding,
            decoration: BoxDecoration(
              color: headerColor,
              border: Border(bottom: BorderSide(color: dividerColor)),
            ),
            child: Column(
              children: [
                // شعار الفندق
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(logoIconPadding),
                      decoration: BoxDecoration(
                        color: cardOverlay,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.hotel,
                        color: Colors.white,
                        size: logoIconSize,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'فندق مارينا بلازا',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: hotelNameFontSize,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: isDesktop ? 16 : 12),

                // بطاقة المستخدم
                Container(
                  padding: userCardPadding,
                  decoration: BoxDecoration(
                    color: cardOverlay,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: isDesktop ? 18 : 15,
                        backgroundColor: Colors.white.withValues(alpha: 0.2),
                        child: Icon(Icons.person, color: Colors.white,
                            size: isDesktop ? 20 : 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.currentUser?.name ?? 'مستخدم',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: isDesktop ? 14 : 13,
                              ),
                            ),
                            Text(
                              auth.currentUser?.userType == 'admin'
                                  ? 'مدير النظام'
                                  : 'موظف',
                              style: TextStyle(
                                color: inactiveColor,
                                fontSize: isDesktop ? 12 : 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ─── عناصر القائمة ───
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(
                vertical: isDesktop ? 12 : 8,
              ),
              children: [
                if (can('dashboard'))
                  _buildMenuItem(
                    icon: Icons.dashboard,
                    title: 'لوحة التحكم',
                    route: '/dashboard',
                    isActive: currentRoute == '/dashboard',
                    onTap: () => onRouteSelected('/dashboard'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('rooms'))
                  _buildMenuItem(
                    icon: Icons.bed,
                    title: 'إدارة الغرف',
                    route: '/rooms',
                    isActive: currentRoute.startsWith('/rooms'),
                    onTap: () => onRouteSelected('/rooms'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('bookings'))
                  _buildMenuItem(
                    icon: Icons.assignment,
                    title: 'إدارة الحجوزات',
                    route: '/bookings',
                    isActive: currentRoute.startsWith('/bookings'),
                    onTap: () => onRouteSelected('/bookings'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('payments'))
                  _buildMenuItem(
                    icon: Icons.attach_money,
                    title: 'إدارة المدفوعات',
                    route: '/payments',
                    isActive: currentRoute.startsWith('/payments'),
                    onTap: () => onRouteSelected('/payments'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('debts'))
                  _buildMenuItem(
                    icon: Icons.account_balance,
                    title: 'الديون',
                    route: '/debts',
                    isActive: currentRoute.startsWith('/debts'),
                    onTap: () => onRouteSelected('/debts'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('expenses'))
                  _buildMenuItem(
                    icon: Icons.receipt_long,
                    title: 'إدارة المصروفات',
                    route: '/expenses',
                    isActive: currentRoute.startsWith('/expenses'),
                    onTap: () => onRouteSelected('/expenses'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('finance'))
                  _buildMenuItem(
                    icon: Icons.account_balance_wallet,
                    title: 'الصندوق والمالية',
                    route: '/finance',
                    isActive: currentRoute.startsWith('/finance'),
                    onTap: () => onRouteSelected('/finance'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('reports'))
                  _buildMenuItem(
                    icon: Icons.bar_chart,
                    title: 'التقارير',
                    route: '/reports',
                    isActive: currentRoute.startsWith('/reports'),
                    onTap: () => onRouteSelected('/reports'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('notes'))
                  _buildMenuItem(
                    icon: Icons.note,
                    title: 'الملاحظات والتنبيهات',
                    route: '/notes',
                    isActive: currentRoute.startsWith('/notes'),
                    onTap: () => onRouteSelected('/notes'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('settings'))
                  _buildMenuItem(
                    icon: Icons.gavel,
                    title: 'القائمة السوداء',
                    route: '/blacklist',
                    isActive: currentRoute.startsWith('/blacklist'),
                    onTap: () => onRouteSelected('/blacklist'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('information'))
                  _buildMenuItem(
                    icon: Icons.badge,
                    title: 'سجل المعلومية',
                    route: '/information',
                    isActive: currentRoute.startsWith('/information'),
                    onTap: () => onRouteSelected('/information'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('settings'))
                  _buildMenuItem(
                    icon: Icons.smart_toy,
                    title: 'المساعد الذكي',
                    route: '/ai',
                    isActive: currentRoute.startsWith('/ai'),
                    onTap: () => onRouteSelected('/ai'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
                if (can('settings'))
                  _buildMenuItem(
                    icon: Icons.settings,
                    title: 'الإعدادات',
                    route: '/settings',
                    isActive: currentRoute.startsWith('/settings'),
                    onTap: () => onRouteSelected('/settings'),
                    context: context,
                    menuIconSize: menuIconSize,
                    menuFontSize: menuFontSize,
                    menuHPadding: menuHPadding,
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: _buildMenuItem(
              icon: Icons.logout,
              title: 'تسجيل الخروج',
              route: '/logout',
              isActive: false,
              onTap: () async {
                try {
                  if (context.isMobile && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                } catch (e) {
                  // تجاهل الأخطاء
                }
                await ref.read(authProvider.notifier).logout();
              },
              context: context,
              menuIconSize: menuIconSize,
              menuFontSize: menuFontSize,
              menuHPadding: menuHPadding,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String route,
    required bool isActive,
    required VoidCallback onTap,
    BuildContext? context,
    double menuIconSize = 24,
    double menuFontSize = 14,
    double menuHPadding = 16,
  }) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: menuHPadding - 4, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          size: menuIconSize,
          color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.72),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.72),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            fontSize: menuFontSize,
          ),
        ),
        onTap: () {
          if (context != null) {
            try {
              if (context.isMobile && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            } catch (e) {
              // تجاهل الأخطاء ومتابعة
            }
          }
          onTap();
        },
        contentPadding: EdgeInsets.symmetric(horizontal: menuHPadding),
        dense: true,
      ),
    );
  }
}
