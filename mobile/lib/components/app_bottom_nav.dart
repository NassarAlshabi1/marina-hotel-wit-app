import 'package:flutter/material.dart';
import '../screens/dashboard_screen.dart';
import '../screens/bookings/bookings_list.dart';
import '../screens/rooms/rooms_main.dart';
import '../screens/reports/reports_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/notes/notes_screen.dart';

class AppBottomNavShell extends StatefulWidget {
  const AppBottomNavShell({super.key});
  @override
  State<AppBottomNavShell> createState() => _AppBottomNavShellState();
}

class _AppBottomNavShellState extends State<AppBottomNavShell> {
  int _index = 0;
  final _pages = const [DashboardScreen(), BookingsListScreen(), RoomsMainScreen(), ReportsScreen(), SettingsScreen()];
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: _pages[_index],
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
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.dashboard),
          label: 'الرئيسية',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.assignment),
          label: 'الحجوزات',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bed),
          label: 'الغرف',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart),
          label: 'التقارير',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'الإعدادات',
        ),
      ],
    );
  }
}
