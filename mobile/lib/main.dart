import 'dart:async';

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
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/debts/debts_list.dart';
import 'screens/notes/notes_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'screens/auth/google_drive_login_screen.dart';
import 'screens/auth/login_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/repository_providers.dart';
import 'services/seed.dart';
import 'services/auto_backup_task.dart';
import 'services/auto_backup_manager.dart';
import 'services/app_session_manager.dart';
import 'services/smart_sync_manager.dart';
import 'services/google_drive_backup_service.dart';
import 'services/google_drive_sync_service.dart';
import 'services/sync_guardian.dart';
import 'services/alarm_backup.dart';
import 'components/admin_layout.dart';
import 'services/google_drive_logger.dart';
import 'services/local_db.dart';
import 'services/appwrite_config.dart';
import 'services/appwrite_logger.dart';
import 'services/appwrite_cache_manager.dart';
import 'services/appwrite_service.dart';
import 'services/appwrite_sync_manager.dart';
import 'package:device_info_plus/device_info_plus.dart';


void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // تهيئة نظام Alarm للنسخ الاحتياطي
  await AlarmBackup.initAlarmSystem();
  
  // تهيئة خدمة النسخ التلقائي التقليدي (المجدول)
  await AutoBackupTask.initialize();
  
  // تهيئة مدير النسخ التلقائي الذكي (على أساس التغييرات)
  await _initializeSmartAutoBackup();
  
  // تهيئة نظام Appwrite
  await _initializeAppwrite();
  
  debugPrint('BASE_API_URL=' + Env.baseApiUrl);
  runApp(const ProviderScope(child: App()));
}

/// تهيئة نظام النسخ التلقائي الذكي والمزامنة بين الأجهزة
Future<void> _initializeSmartAutoBackup() async {
  try {
    final driveLogger = GoogleDriveLogger();
    await driveLogger.initialize(minLevel: LogLevel.debug, enableConsole: true, enableFile: false);

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
    await autoBackupManager.setMaxBackupCount(10); // الاحتفاظ بـ 10 نسخ فقط
    await autoBackupManager.setRetentionDays(14); // لمدة 14 يوماً
    
    // تهيئة مدير المزامنة الذكية بين الأجهزة
    final smartSyncManager = SmartSyncManager.instance;
    await smartSyncManager.initialize(backupService);

    final syncGuardian = SyncGuardian.instance;
    final driveSyncService = GoogleDriveSyncService(googleSignIn: backupService.googleSignIn);
    await syncGuardian.initialize(
      database: DatabaseManager.instance,
      driveService: driveSyncService,
    );
    
    debugPrint('✅ تم تهيئة النسخ التلقائي والمزامنة الذكية بنجاح');
  } catch (e) {
    debugPrint('❌ خطأ في تهيئة النظام الذكي: $e');
  }
}

/// تهيئة نظام Appwrite للمزامنة السحابية
Future<void> _initializeAppwrite() async {
  try {
    // طباعة الإعدادات
    AppwriteConfig.printConfig();
    
    // تهيئة المسجل
    final logger = AppwriteLogger();
    await logger.initialize(
      minLevel: LogLevel.info,
      enableConsole: true,
      enableFile: false,
    );
    
    // تهيئة مدير الذاكرة المؤقتة
    final cacheManager = AppwriteCacheManager();
    cacheManager.startCleanup();
    
    // تهيئة خدمة Appwrite
    final appwriteService = AppwriteService();
    final prefs = await SharedPreferences.getInstance();

    if (!prefs.containsKey('appwrite_sync_enabled')) {
      await prefs.setBool('appwrite_sync_enabled', true);
    }
    if (!prefs.containsKey('appwrite_sync_interval')) {
      await prefs.setInt('appwrite_sync_interval', 15);
    }
    
    // التحقق من صحة الإعدادات قبل التهيئة
    if (AppwriteConfig.validateConfig()) {
      try {
        await appwriteService.initialize();
        
        // تهيئة مدير المزامنة
        final syncManager = AppwriteSyncManager(
          appwriteService: appwriteService,
          database: DatabaseManager.instance,
        );
        await syncManager.initialize();
        
        final syncEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;
        final syncIntervalMinutes = prefs.getInt('appwrite_sync_interval') ?? 15;
        if (syncEnabled) {
          syncManager.startAutoSync(interval: Duration(minutes: syncIntervalMinutes));
        }
        
        // تسجيل الجهاز (إذا كان متاحاً)
        try {
          final deviceInfo = await DeviceInfoPlugin().androidInfo;
          await syncManager.registerDevice(
            deviceName: deviceInfo.model,
            deviceModel: deviceInfo.device,
            osVersion: 'Android ${deviceInfo.version.release}',
          );
          debugPrint('✅ تم تسجيل الجهاز في Appwrite');
        } catch (e) {
          debugPrint('⚠️ تعذر تسجيل الجهاز: $e');
        }
        
        debugPrint('✅ تم تهيئة Appwrite بنجاح');
      } catch (e) {
        debugPrint('⚠️ فشل الاتصال بـ Appwrite (سيعمل التطبيق بدون مزامنة سحابية): $e');
      }
    } else {
      debugPrint('ℹ️ Appwrite غير مُعد - يرجى تعيين Project ID في appwrite_config.dart');
    }
  } catch (e, stackTrace) {
    debugPrint('❌ خطأ في تهيئة Appwrite: $e');
    debugPrint('Stack Trace: $stackTrace');
  }
}

class App extends ConsumerStatefulWidget {
  const App({super.key});

  @override
  ConsumerState<App> createState() => _AppState();
}

class _AppState extends ConsumerState<App> with WidgetsBindingObserver {
  bool _sessionConfigured = false;
  bool _isConfiguringSession = false;
  AppDatabase? _pendingDatabase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listen<AppDatabase>(
      databaseProvider,
      (previous, database) {
        if (_sessionConfigured && previous != null && identical(previous, database)) {
          return;
        }
        _enqueueDatabase(database);
      },
    );
  }

  void _enqueueDatabase(AppDatabase database) {
    _pendingDatabase = database;
    if (!_isConfiguringSession) {
      _processPendingDatabase();
    }
  }

  void _processPendingDatabase() {
    final database = _pendingDatabase;
    if (database == null) {
      return;
    }
    _pendingDatabase = null;
    _isConfiguringSession = true;
    Future.microtask(() async {
      try {
        if (_sessionConfigured) {
          await AppSessionManager.onAppCloseOrBackground();
        }
        AppSessionManager.configure(
          database: database,
          deviceIdResolver: () async => SmartSyncManager.instance.deviceId,
        );
        await Seeder(database).seedIfEmpty();
        await AppSessionManager.onAppOpen();
        _sessionConfigured = true;
      } finally {
        _isConfiguringSession = false;
        if (_pendingDatabase != null) {
          _processPendingDatabase();
        }
      }
    });
  }

  @override
  void dispose() {
    if (_sessionConfigured) {
      unawaited(AppSessionManager.onAppCloseOrBackground());
    }
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_sessionConfigured) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(AppSessionManager.onAppOpen());
      unawaited(SyncGuardian.instance.onAppForeground());
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      unawaited(AppSessionManager.onAppCloseOrBackground());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer(builder: (context, ref, _) {
        final isDark = ref.watch(themeSettingsProvider);
        return MaterialApp(
          title: 'مارينا هوتيل',
          theme: buildTheme(),
          darkTheme: buildDarkTheme(),
          themeMode: isDark ? ThemeMode.dark : ThemeMode.light,
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
        );
      }),
    );
  }
}

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final backup = ref.watch(backupStatusProvider);
    if (auth.isRestoring) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }
    if (!auth.isAuthenticated && backup.requiresDriveLogin) {
      return const GoogleDriveLoginScreen();
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
    final unreadCountAsync = ref.watch(simpleNotesUnreadCountProvider);
    final unreadCount = unreadCountAsync.maybeWhen(data: (count) => count, orElse: () => 0);
    final hasUnread = unreadCount > 0;

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
              Positioned(
                right: -2,
                top: -2,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(
                    minWidth: 16,
                    minHeight: 16,
                  ),
                  child: Text(
                    unreadCount > 9 ? '9+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
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
