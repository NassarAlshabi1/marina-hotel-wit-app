import 'package:flutter/material.dart';
import '../screens/dashboard_screen.dart';
import '../screens/bookings/bookings_list.dart';
import '../screens/rooms/rooms_list.dart';
import '../screens/reports/reports_screen.dart';

class AppBottomNavShell extends StatefulWidget {
  const AppBottomNavShell({super.key});
  @override
  State<AppBottomNavShell> createState() => _AppBottomNavShellState();
}

class _AppBottomNavShellState extends State<AppBottomNavShell> {
  int _index = 0;
  final _pages = const [DashboardScreen(), BookingsListScreen(), RoomsListScreen(), ReportsScreen()];
  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: _pages[_index],
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'لوحة التحكم'),
            BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'الحجوزات'),
            BottomNavigationBarItem(icon: Icon(Icons.bed), label: 'الغرف'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'التقارير'),
          ],
        ),
      ),
    );
  }
}
