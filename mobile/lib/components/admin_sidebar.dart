import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_provider.dart';
import '../utils/theme.dart';

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
    
    return Container(
      width: 280,
      color: AppColors.primaryColor,
      child: Column(
        children: [
          // Sidebar Header - matching PHP design
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.1),
              border: Border(
                bottom: BorderSide(
                  color: Colors.white.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: Column(
              children: [
                // Logo section
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.1),
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
                    color: Colors.white.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        child: const Icon(
                          Icons.person,
                          color: Colors.white,
                        ),
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
                              auth.currentUser?.userType == 'admin' ? 'مدير النظام' : 'موظف',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.8),
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
                _buildMenuItem(
                  icon: Icons.dashboard,
                  title: 'لوحة التحكم',
                  route: '/dashboard',
                  isActive: currentRoute == '/dashboard',
                  onTap: () => onRouteSelected('/dashboard'),
                ),
                _buildMenuItem(
                  icon: Icons.bed,
                  title: 'إدارة الغرف',
                  route: '/rooms',
                  isActive: currentRoute.startsWith('/rooms'),
                  onTap: () => onRouteSelected('/rooms'),
                ),
                _buildMenuItem(
                  icon: Icons.assignment,
                  title: 'إدارة الحجوزات',
                  route: '/bookings',
                  isActive: currentRoute.startsWith('/bookings'),
                  onTap: () => onRouteSelected('/bookings'),
                ),
                _buildMenuItem(
                  icon: Icons.attach_money,
                  title: 'إدارة المدفوعات',
                  route: '/payments',
                  isActive: currentRoute.startsWith('/payments'),
                  onTap: () => onRouteSelected('/payments'),
                ),
                _buildMenuItem(
                  icon: Icons.group,
                  title: 'إدارة الموظفين',
                  route: '/employees',
                  isActive: currentRoute.startsWith('/employees'),
                  onTap: () => onRouteSelected('/employees'),
                ),
                _buildMenuItem(
                  icon: Icons.receipt_long,
                  title: 'إدارة المصروفات',
                  route: '/expenses',
                  isActive: currentRoute.startsWith('/expenses'),
                  onTap: () => onRouteSelected('/expenses'),
                ),
                _buildMenuItem(
                  icon: Icons.account_balance_wallet,
                  title: 'الصندوق والمالية',
                  route: '/finance',
                  isActive: currentRoute.startsWith('/finance'),
                  onTap: () => onRouteSelected('/finance'),
                ),
                _buildMenuItem(
                  icon: Icons.bar_chart,
                  title: 'التقارير',
                  route: '/reports',
                  isActive: currentRoute.startsWith('/reports'),
                  onTap: () => onRouteSelected('/reports'),
                ),
                _buildMenuItem(
                  icon: Icons.note,
                  title: 'الملاحظات والتنبيهات',
                  route: '/notes',
                  isActive: currentRoute.startsWith('/notes'),
                  onTap: () => onRouteSelected('/notes'),
                ),
                _buildMenuItem(
                  icon: Icons.settings,
                  title: 'الإعدادات',
                  route: '/settings',
                  isActive: currentRoute.startsWith('/settings'),
                  onTap: () => onRouteSelected('/settings'),
                ),
                
              ],
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
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isActive ? Colors.white.withOpacity(0.1) : null,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          icon,
          color: isActive ? Colors.white : Colors.white70,
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.white70,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        dense: true,
      ),
    );
  }
}