import 'dart:async' show unawaited;\nimport 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'utils/theme.dart';
import 'utils/env.dart';
import 'utils/supabase_config.dart';
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
import 'services/local_db.dart';
import 'services/supabase_realtime_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // ✅ عرض UI فوراً بدون انتظار التهيئة المعقدة
  runApp(const ProviderScope(child: App()));
  
  // 🔄 تهيئة الخدمات في background بعد عرض UI
  _initializeServicesInBackground();
}

/// تهيئة الخدمات في background بدون تجميد UI
Future<void> _initializeServicesInBackground() async {
  // تشغيل العمليات بالتوازي بدلاً من التسلسل
  final futures = <Future>[
    SupabaseConfig.initialize().catchError((e) {
      debugPrint('⚠️ فشل تهيئة Supabase: $e');
    }),
    AutoBackupTask.initialize().catchError((e) {
      debugPrint('⚠️ فشل تهيئة AutoBackupTask: $e');
    }),
    _initializeSmartAutoBackupSafely().catchError((e) {
      debugPrint('⚠️ فشل تهيئة النسخ الذكي: $e');
    }),
  ];
  
  // انتظار جميع العمليات مع timeout
  await Future.wait(futures).timeout(
    const Duration(seconds: 30),
    onTimeout: () {
      debugPrint('⚠️ انتهت مهلة تهيئة الخدمات - سيتم المتابعة');
    },
  );
  
  debugPrint('✅ تم إكمال تهيئة الخدمات في background');
  debugPrint('BASE_API_URL=' + Env.baseApiUrl);
}

/// تهيئة نظام النسخ التلقائي الذكي والمزامنة بين الأجهزة (نسخة آمنة)
Future<void> _initializeSmartAutoBackupSafely() async {
  try {
    final backupService = GoogleDriveBackupService();
    
    // محاولة استعادة جلسة Google Drive بدون تجميد
    try {
      await backupService.attemptSilentSignIn().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ تم تجاوز مهلة تسجيل الدخول لـ Google Drive');
        },
      );
    } catch (e) {
      debugPrint('⚠️ لم يتم استعادة جلسة Google Drive: $e');
    }
    
    // تأجيل تهيئة الخدمات المعقدة إلى بعد بناء UI
    Future.delayed(const Duration(seconds: 2), () async {
      try {
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
        debugPrint('❌ خطأ في تهيئة النظام الذكي المؤجل: $e');
      }
    });
    
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة النظام الذكي: $e');
    // لا نعيد رفع الخطأ لتجنب crash التطبيق
  }
}

class App extends ConsumerStatefulWidget {
  const App({super.key});
  
  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> {
  bool _servicesInitialized = false;
  
  @override
  void initState() {
    super.initState();
    
    // ✅ تأجيل تهيئة قاعدة البيانات والrealtime services
    // إلى بعد بناء UI لتجنب التجمد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeServicesAfterUI();
    });
  }
  
  /// تهيئة قاعدة البيانات وrealtime services بعد عرض UI
  Future<void> _initializeServicesAfterUI() async {
    if (_servicesInitialized) return;
    
    try {
      // انتظار قصير لضمان عرض UI بسلاسة
      await Future.delayed(const Duration(milliseconds: 300));
      
      // تهيئة قاعدة البيانات
      final database = ref.read(databaseProvider);
      await Seeder(database).seedIfEmpty();
      
      // تفعيل realtime subscriptions بعد استقرار UI
      await Future.delayed(const Duration(seconds: 1));
      
      final realtimeService = ref.read(realtimeServiceProvider);
      if (realtimeService.currentStatus == RealtimeStatus.disconnected) {
        // تفعيل subscriptions بالتوازي بدلاً من التسلسل
        unawaited(realtimeService.subscribeToAll().catchError((e) {
          debugPrint('⚠️ فشل تفعيل Realtime Subscriptions: $e');
        }));
        debugPrint('🔄 تم بدء تفعيل Realtime Subscriptions');
      }
      
      _servicesInitialized = true;
      debugPrint('✅ تم إكمال تهيئة خدمات التطبيق بعد UI');
      
    } catch (e) {
      debugPrint('❌ خطأ في تهيئة خدمات التطبيق: $e');
      // لا نعيد رفع الخطأ لتجنب crash
    }
  }
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ✅ إزالة fireImmediately listener ونقل التهيئة إلى initState
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

class RootRouter extends ConsumerStatefulWidget {
  const RootRouter({super.key});
  
  @override
  ConsumerState<RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends ConsumerState<RootRouter> {
  @override
  void initState() {
    super.initState();
    
    // ✅ بدء استعادة الجلسة بعد بناء Widget لتجنب التجمد
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreSessionSafely();
    });
  }
  
  /// استعادة الجلسة بأمان بعد عرض UI
  Future<void> _restoreSessionSafely() async {
    try {
      final authNotifier = ref.read(authProvider.notifier);
      
      // تأخير قصير لضمان عرض loading state
      await Future.delayed(const Duration(milliseconds: 100));
      
      // استعادة الجلسة مع timeout
      await authNotifier.restoreSession().timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ تم تجاوز مهلة استعادة الجلسة');
        },
      );
    } catch (e) {
      debugPrint('❌ خطأ في استعادة الجلسة: $e');
    }
  }
  
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    
    // ✅ تحسين loading state
    if (auth.isRestoring) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Colors.white,
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
                SizedBox(height: 24),
                Text(
                  'جاري تحضير التطبيق...',
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey,
                    fontFamily: 'Tajawal',
                  ),
                ),
              ],
            ),
          ),
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
