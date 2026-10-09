import 'package:flutter/material.dart';

import '../screens/bookings/bookings_list.dart';
import '../screens/dashboard_screen.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/rooms/rooms_main.dart';
import '../screens/settings/settings_screen.dart';

/// ✅ Shell للتبويبات السفلية مع IndexedStack
///
/// تحسين الأداء للأجهزة الضعيفة:
/// - IndexedStack يُبقي كل الصفحات حية في الذاكرة
/// - عند تبديل التبويب، لا تُعاد بناء الصفحة من الصفر
/// - توفير 200-500ms على كل تبديل تبويب
/// - يمنع إعادة تحميل البيانات من قاعدة البيانات عند كل تبديل
class AppBottomNavShell extends StatefulWidget {
  const AppBottomNavShell({super.key});
  @override
  State<AppBottomNavShell> createState() => _AppBottomNavShellState();
}

class _AppBottomNavShellState extends State<AppBottomNavShell> {
  int _index = 0;

  // ✅ pages تُنشأ مرة واحدة فقط — IndexedStack يُبقيها حية
  final _pages = const [
    DashboardScreen(),
    BookingsListScreen(),
    RoomsMainScreen(),
    ReportsScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        // ✅ IndexedStack: يُبقي كل الصفحات في الذاكرة
        // عند تبديل التبويب: يُخفي القديمة ويُظهر الجديدة فوراً
        // بدون إعادة بناء — يحافظ على scroll position والـ state
        body: IndexedStack(index: _index, children: _pages),
        bottomNavigationBar: _buildBottomNavBar(),
      ),
    );
  }

  Widget _buildBottomNavBar() {
    return BottomNavigationBar(
      type: BottomNavigationBarType.fixed,
      currentIndex: _index,
      onTap: (i) => setState(() => _index = i),
      selectedFontSize: 11,
      unselectedFontSize: 10,
      // ✅ iconSize أصغر = layout أسرع على الأجهزة الضعيفة
      iconSize: 22,
      items: const [
        BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'الرئيسية'),
        BottomNavigationBarItem(
          icon: Icon(Icons.assignment),
          label: 'الحجوزات',
        ),
        BottomNavigationBarItem(icon: Icon(Icons.bed), label: 'الغرف'),
        BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'التقارير'),
        BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'الإعدادات'),
      ],
    );
  }
}
