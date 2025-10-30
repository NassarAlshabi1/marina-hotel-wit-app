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
import 'screens/debts/debts_list.dart';
import 'screens/notes/notes_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/auth/login_screen.dart';
import 'providers/auth_provider.dart';
import 'services/providers.dart';
import 'services/seed.dart';
import 'services/auto_backup_task.dart';
import 'services/auto_backup_manager.dart';
import 'services/smart_sync_manager.dart';
import 'services/google_drive_backup_service.dart';
import 'components/admin_layout.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة خدمة النسخ التلقائي التقليدي (المجدول)
  await AutoBackupTask.initialize();
  
  // تهيئة مدير النسخ التلقائي الذكي (على أساس التغييرات)
  await _initializeSmartAutoBackup();
  
  debugPrint('BASE_API_URL=' + Env.baseApiUrl);
  runApp(const ProviderScope(child: App()));
}

/// تهيئة نظام النسخ التلقائي الذكي والمزامنة بين الأجهزة
Future<void> _initializeSmartAutoBackup() async {
  try {
    final backupService = GoogleDriveBackupService();
    
    // محاولة استعادة جلسة Google Drive أولاً
    try {
      await backupService.attemptSilentSignIn();
    } catch (e) {
      debugPrint('⚠️ لم يتم استعادة جلسة Google Drive: $e');
    }
    
    // تهيئة مدير النسخ التلقائي
    final autoBackupManager = AutoBackupManager.instance;
    await autoBackupManager.initialize(backupService);
    
    // تفعيل النسخ التلقائي بشكل افتراضي
    await autoBackupManager.setEnabled(true);
    await autoBackupManager.setMaxBackupCount(25); // الاحتفاظ بـ 25 نسخة
    await autoBackupManager.setRetentionDays(45); // لمدة 45 يوماً
    
    // تهيئة مدير المزامنة الذكية بين الأجهزة
    final smartSyncManager = SmartSyncManager.instance;
    await smartSyncManager.initialize(backupService);
    
    debugPrint('✅ تم تهيئة النسخ التلقائي والمزامنة الذكية بنجاح');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة النظام الذكي: $e');
  }
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
          '/debts': (_) => const DebtsListScreen(),
          '/reports': (_) => const ReportsScreen(),
        },
        home: const RootRouter(),
      ),
    );
  }
}

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (auth.isRestoring) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (auth.isAuthenticated) {
      return const HomeShell();
    }
    return const LoginScreen();
  }
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});
  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  String _currentRoute = '/dashboard';
  
  final Map<String, Widget> _routes = {
    '/dashboard': const DashboardScreen(),
    '/rooms': const RoomsListScreen(),
    '/bookings': const BookingsListScreen(),
    '/payments': const PaymentsMainScreen(),
    '/debts': const DebtsListScreen(),
    '/employees': const EmployeesListScreen(),
    '/expenses': const ExpensesListScreen(),
    '/finance': const FinanceScreen(),
    '/reports': const ReportsScreen(),
    '/notes': const NotesScreen(),
    '/settings': const SettingsScreen(),
  };
  
  bool _can(String key) {
    final auth = ref.read(authProvider);
    final u = auth.currentUser;
    if (u == null) return false;
    if (u.userType == 'admin' || u.permissions.contains('all')) return true;
    return u.permissions.contains(key);
  }

  @override
  Widget build(BuildContext context) {
    final routeKey = _currentRoute.replaceAll('/', '');
    final allowed = _can(routeKey.isEmpty ? 'dashboard' : routeKey);
    final body = allowed
        ? (_routes[_currentRoute] ?? const DashboardScreen())
        : const Center(child: Text('ليس لديك صلاحية لعرض هذه الصفحة'));

    final actions = _buildGlobalActions(context);

    return AdminLayout(
      currentRoute: _currentRoute,
      body: body,
      actions: actions,
      onRouteSelected: _navigateToRoute,
    );
  }
  
  List<Widget> _buildGlobalActions(BuildContext context) {
    final notesAsync = ref.watch(activeNotesProvider);
    final hasUnread = notesAsync.maybeWhen(data: (notes) => notes.isNotEmpty, orElse: () => false);

    return [
      IconButton(
        onPressed: () {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NotesScreen()));
        },
        tooltip: 'التنبيهات',
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(hasUnread ? Icons.notifications_active : Icons.notifications_none),
            if (hasUnread)
              const Positioned(
                right: -2,
                top: -2,
                child: CircleAvatar(radius: 4, backgroundColor: Colors.red),
              ),
          ],
        ),
      ),
    ];
  }
  
  void _navigateToRoute(String route) {
    if (_routes.containsKey(route)) {
      setState(() {
        _currentRoute = route;
      });
    }
  }
}
