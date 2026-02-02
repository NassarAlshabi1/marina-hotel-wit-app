import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';

class AdminSidebar extends ConsumerWidget {
  final String currentRoute;
  final Function(String) onRouteSelected;

  const AdminSidebar({
    super.key,
    required this.currentRoute,
    required this.onRouteSelected,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    bool can(String key) {
      final u = auth.currentUser;
      if (u == null) return false;
      if (u.permissions.contains('all') || u.userType == 'admin') return true;
      return u.permissions.contains(key);
    }

    final sidebarColor = const Color(0xFF0F172A);
    final headerColor = const Color(0xFF16213C);
    final cardOverlay = Colors.white.withOpacity(0.08);
    final dividerColor = Colors.white.withOpacity(0.12);
    final inactiveColor = Colors.white.withOpacity(0.72);

    return Container(
      width: 280,
      color: sidebarColor,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: headerColor,
              border: Border(bottom: BorderSide(color: dividerColor, width: 1)),
            ),
            child: Column(
              children: [
                // Logo section
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardOverlay,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.hotel,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Text(
                        'فندق مارينا بلازا',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // User info section
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cardOverlay,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: const Icon(Icons.person, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              auth.currentUser?.name ?? 'مستخدم',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                            ),
                            Text(
                              auth.currentUser?.userType == 'admin'
                                  ? 'مدير النظام'
                                  : 'موظف',
                              style: TextStyle(
                                color: inactiveColor,
                                fontSize: 12,
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

          // Menu Items - exactly matching PHP sidebar
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 16),
              children: [
                if (can('dashboard'))
                  _buildMenuItem(
                    icon: Icons.dashboard,
                    title: 'لوحة التحكم',
                    route: '/dashboard',
                    isActive: currentRoute == '/dashboard',
                    onTap: () => onRouteSelected('/dashboard'),
                    context: context,
                  ),
                if (can('rooms'))
                  _buildMenuItem(
                    icon: Icons.bed,
                    title: 'إدارة الغرف',
                    route: '/rooms',
                    isActive: currentRoute.startsWith('/rooms'),
                    onTap: () => onRouteSelected('/rooms'),
                    context: context,
                  ),
                if (can('bookings'))
                  _buildMenuItem(
                    icon: Icons.assignment,
                    title: 'إدارة الحجوزات',
                    route: '/bookings',
                    isActive: currentRoute.startsWith('/bookings'),
                    onTap: () => onRouteSelected('/bookings'),
                    context: context,
                  ),
                if (can('payments'))
                  _buildMenuItem(
                    icon: Icons.attach_money,
                    title: 'إدارة المدفوعات',
                    route: '/payments',
                    isActive: currentRoute.startsWith('/payments'),
                    onTap: () => onRouteSelected('/payments'),
                    context: context,
                  ),
                if (can('debts'))
                  _buildMenuItem(
                    icon: Icons.account_balance,
                    title: 'الديون',
                    route: '/debts',
                    isActive: currentRoute.startsWith('/debts'),
                    onTap: () => onRouteSelected('/debts'),
                    context: context,
                  ),
                if (can('expenses'))
                  _buildMenuItem(
                    icon: Icons.receipt_long,
                    title: 'إدارة المصروفات',
                    route: '/expenses',
                    isActive: currentRoute.startsWith('/expenses'),
                    onTap: () => onRouteSelected('/expenses'),
                    context: context,
                  ),
                if (can('finance'))
                  _buildMenuItem(
                    icon: Icons.account_balance_wallet,
                    title: 'الصندوق والمالية',
                    route: '/finance',
                    isActive: currentRoute.startsWith('/finance'),
                    onTap: () => onRouteSelected('/finance'),
                    context: context,
                  ),
                if (can('reports'))
                  _buildMenuItem(
                    icon: Icons.bar_chart,
                    title: 'التقارير',
                    route: '/reports',
                    isActive: currentRoute.startsWith('/reports'),
                    onTap: () => onRouteSelected('/reports'),
                    context: context,
                  ),
                if (can('notes'))
                  _buildMenuItem(
                    icon: Icons.note,
                    title: 'الملاحظات والتنبيهات',
                    route: '/notes',
                    isActive: currentRoute.startsWith('/notes'),
                    onTap: () => onRouteSelected('/notes'),
                    context: context,
                  ),
                if (can('settings'))
                  _buildMenuItem(
                    icon: Icons.gavel,
                    title: 'القائمة السوداء',
                    route: '/blacklist',
                    isActive: currentRoute.startsWith('/blacklist'),
                    onTap: () => onRouteSelected('/blacklist'),
                    context: context,
                  ),
                if (can('settings'))
                  _buildMenuItem(
                    icon: Icons.settings,
                    title: 'الإعدادات',
                    route: '/settings',
                    isActive: currentRoute.startsWith('/settings'),
                    onTap: () => onRouteSelected('/settings'),
                    context: context,
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
                // إغلاق الـ Drawer في الموبايل قبل تسجيل الخروج
                try {
                  final isTablet = MediaQuery.of(context).size.width >= 768;
                  if (!isTablet && Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  }
                } catch (e) {
                  // تجاهل الأخطاء
                }

                await ref.read(authProvider.notifier).logout();
              },
              context: context,
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
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.12) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white.withOpacity(0.72),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white.withOpacity(0.72),
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onTap: () {
          // إغلاق الـ Drawer في الموبايل قبل التنقل
          if (context != null) {
            try {
              // تحقق مما إذا كان هناك drawer مفتوح وأغلقه
              final isTablet = MediaQuery.of(context).size.width >= 768;
              if (!isTablet && Navigator.of(context).canPop()) {
                Navigator.of(context).pop();
              }
            } catch (e) {
              // تجاهل الأخطاء ومتابع
            }
          }
          onTap();
        },
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        dense: true,
      ),
    );
  }
}
