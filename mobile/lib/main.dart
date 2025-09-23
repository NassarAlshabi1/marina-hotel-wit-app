import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utils/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/rooms/rooms_list.dart';
import 'screens/bookings/bookings_list.dart';
import 'screens/employees/employees_list.dart';
import 'screens/expenses/expenses_list.dart';
import 'screens/finance/finance_screen.dart';
import 'screens/reports/reports_screen.dart';

void main() {
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        title: 'مارينا بلازا',
        theme: buildTheme(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar')],
        home: auth.isAuthenticated ? const HomeShell() : const LoginScreen(),
      ),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;
  @override
  Widget build(BuildContext context) {
    final pages = const [
      DashboardScreen(),
      RoomsListScreen(),
      BookingsListScreen(),
      EmployeesListScreen(),
      ExpensesListScreen(),
      FinanceScreen(),
      ReportsScreen(),
    ];
    final items = const [
      BottomNavigationBarItem(icon: Icon(Icons.dashboard), label: 'لوحة'),
      BottomNavigationBarItem(icon: Icon(Icons.bed), label: 'الغرف'),
      BottomNavigationBarItem(icon: Icon(Icons.assignment), label: 'الحجوزات'),
      BottomNavigationBarItem(icon: Icon(Icons.group), label: 'الموظفون'),
      BottomNavigationBarItem(icon: Icon(Icons.receipt_long), label: 'المصروفات'),
      BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet), label: 'الصندوق'),
      BottomNavigationBarItem(icon: Icon(Icons.bar_chart), label: 'التقارير'),
    ];
    return Scaffold(
      body: pages[_index],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'لوحة'),
          NavigationDestination(icon: Icon(Icons.bed), label: 'الغرف'),
          NavigationDestination(icon: Icon(Icons.assignment), label: 'الحجوزات'),
          NavigationDestination(icon: Icon(Icons.group), label: 'الموظفون'),
          NavigationDestination(icon: Icon(Icons.receipt_long), label: 'المصروفات'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet), label: 'الصندوق'),
          NavigationDestination(icon: Icon(Icons.bar_chart), label: 'التقارير'),
        ],
      ),
    );
  }
}
