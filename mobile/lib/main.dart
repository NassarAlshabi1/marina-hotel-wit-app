import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utils/theme.dart';
import 'utils/env.dart';
import 'screens/dashboard_screen.dart';
import 'screens/rooms/rooms_list.dart';
import 'screens/bookings/bookings_list.dart';
import 'screens/employees/employees_list.dart';
import 'screens/expenses/expenses_list.dart';
import 'screens/finance/finance_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/payments/payments_main_screen.dart';
import 'screens/notes/notes_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'services/providers.dart';
import 'services/seed.dart';
import 'components/admin_layout.dart';

void main() {
  debugPrint('BASE_API_URL=' + Env.baseApiUrl);
  runApp(const ProviderScope(child: App()));
}

class App extends ConsumerWidget {
  const App({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(databaseProvider, (prev, db) async {
      await Seeder(db).seedIfEmpty();
    });
    return Directionality(
      textDirection: TextDirection.rtl,
      child: MaterialApp(
        title: 'مارينا هوتيل',
        theme: buildTheme(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: const [Locale('ar')],
        routes: {
          '/employees': (_) => const EmployeesListScreen(),
          '/expenses': (_) => const ExpensesListScreen(),
          '/finance/cash-register': (_) => const FinanceScreen(),
          '/finance/cash-transactions': (_) => const FinanceScreen(),
          '/reports': (_) => const ReportsScreen(),
        },
        home: const HomeShell(),
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
  String _currentRoute = '/dashboard';
  
  final Map<String, Widget> _routes = {
    '/dashboard': const DashboardScreen(),
    '/rooms': const RoomsListScreen(),
    '/bookings': const BookingsListScreen(),
    '/payments': const PaymentsMainScreen(),
    '/employees': const EmployeesListScreen(),
    '/expenses': const ExpensesListScreen(),
    '/finance': const FinanceScreen(),
    '/reports': const ReportsScreen(),
    '/notes': const NotesScreen(),
    '/settings': const SettingsScreen(),
  };
  
  @override
  Widget build(BuildContext context) {
    return AdminLayout(
      currentRoute: _currentRoute,
      body: _routes[_currentRoute] ?? const DashboardScreen(),
      onRouteSelected: _navigateToRoute,
    );
  }
  
  void _navigateToRoute(String route) {
    if (_routes.containsKey(route)) {
      setState(() {
        _currentRoute = route;
      });
    }
  }
}
