import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'components/admin_layout.dart';
import 'providers/appwrite_providers.dart' as appwrite;
import 'providers/auth_provider.dart';
import 'providers/repository_providers.dart';
import 'providers/theme_provider.dart';
import 'screens/ai/ai_chat_screen.dart';
import 'screens/auth/login_screen.dart';
import 'screens/bookings/bookings_list.dart';
import 'screens/dashboard_screen.dart';
import 'screens/debts/debts_list.dart';
import 'screens/employees/employees_list.dart';
import 'screens/expenses/expenses_list.dart';
import 'screens/finance/finance_screen.dart';
import 'screens/information/information_screen.dart';
import 'screens/notes/notes_screen.dart';
import 'screens/payments/payments_main_screen.dart';
import 'screens/reports/reports_screen.dart';
import 'screens/rooms/rooms_list.dart';
import 'screens/security/blacklist_screen.dart';
import 'screens/settings/settings_screen.dart';
import 'services/alarm_backup.dart';
import 'services/api_config_service.dart';
import 'services/app_session_manager.dart';
import 'services/appwrite_config_manager.dart';
import 'services/appwrite_realtime_service.dart';
import 'services/appwrite_realtime_sync.dart';
import 'services/appwrite_sync_manager.dart';
import 'services/background_sync_service.dart';
import 'services/battery_optimizer.dart';
import 'services/central_sync_coordinator.dart';
import 'services/connectivity_service.dart';
import 'services/crashlytics_service.dart';

import 'services/diagnostics/diagnostics_logger.dart';
import 'services/fcm_service.dart';
import 'services/google_drive_auto_sync_engine.dart';

import 'services/google_drive_unified_sync_coordinator.dart';
import 'services/local_db.dart';
import 'services/logging/log_models.dart';
import 'services/remote_config_service.dart';
import 'services/seed.dart';

import 'services/sync_conflict_event_bus.dart';
import 'services/sync_constants.dart';
import 'services/sync_guardian.dart';
import 'services/sync_performance_optimizer.dart';

import 'services/sync_service.dart';
import 'services/performance_optimizer.dart';
// ⚠️ Google Drive imports DISABLED
// import 'services/unified_sync_orchestrator.dart';
import 'utils/app_logger.dart';

import 'utils/env.dart';
import 'utils/hotel_day_ticker.dart';
import 'utils/id.dart';
import 'utils/theme.dart';

// Google Drive classes are now imported from their own files

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─── Firebase Core: تهيئة قبل كل خدمات Firebase ───
  try {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase Core initialized');
  } catch (e) {
    debugPrint('⚠️ Firebase Core initialization failed: $e');
    debugPrint('ℹ️ التطبيق يعمل بالإعدادات المحلية بدون Firebase');
  }

  // ─── Crashlytics: تهيئة قبل كل شيء ───
  await CrashlyticsService.instance.initialize();

  // ─── Remote Config: تهيئة مبكراً ───
  await RemoteConfigService.instance.initialize();

  await DiagnosticsLogger.instance.initialize();
  await ApiConfigService.instance.initialize();
  await PerformanceOptimizer().initialize();

  // تهيئة نظام الإنذارات المجدولة (نسخ احتياطي + تقارير Lark/Telegram)
  unawaited(AlarmBackup.initAlarmSystem());

  // ─── ربط Crashlytics + DiagnosticsLogger ───
  CrashlyticsService.instance.setupErrorHandlers(
    originalFlutterHandler: (details) {
      DiagnosticsLogger.instance.recordFlutterError(details);
      FlutterError.presentError(details);
    },
    originalPlatformHandler: (error, stack) {
      DiagnosticsLogger.instance.recordError(
        error,
        stack,
        tag: 'PLATFORM',
        level: LogLevel.critical,
      );
    },
    originalZonedHandler: (error, stack) {
      DiagnosticsLogger.instance.recordError(
        error,
        stack,
        tag: 'ZONED',
        level: LogLevel.critical,
      );
    },
  );

  unawaited(SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]),);

  debugPrint('BASE_API_URL=${Env.baseApiUrl}');
  runZonedGuarded(
    () => runApp(const ProviderScope(child: App())),
    (error, stack) async {
      // إرسال الخطأ إلى Crashlytics
      await CrashlyticsService.instance.recordUnexpectedError(
        error: error,
        stackTrace: stack,
        context: 'runZonedGuarded',
      );
      // تسجيل محلي
      DiagnosticsLogger.instance.recordError(
        error,
        stack,
        tag: 'ZONED',
        level: LogLevel.critical,
      );
    },
  );

  unawaited(_initializeFullyAutomatedSyncSystem());
}

Future<void> _initializeFullyAutomatedSyncSystem() async {
  // ⚠️⚠️⚠️ Google Drive Sync is COMPLETELY DISABLED ⚠️⚠️⚠️
  // This function intentionally does nothing related to Google Drive
  // All sync functionality is handled via Appwrite only
  
  try {
    final prefs = await SharedPreferences.getInstance();
    // Ensure only Appwrite sync is enabled
    await prefs.setBool('appwrite_sync_enabled', true);
    // Explicitly disable Google Drive sync flag
    await prefs.setBool('google_drive_sync_enabled', false);

    AppLogger.info('═══════════════════════════════════════════════════════', tag: 'MAIN');
    AppLogger.info('🚀 Initializing Appwrite Sync System Only', tag: 'MAIN');
    AppLogger.info('⚠️ Google Drive Sync: DISABLED', tag: 'MAIN');
    AppLogger.info('═══════════════════════════════════════════════════════', tag: 'MAIN');

    AppLogger.debug('📦 Initializing Appwrite Config Manager...', tag: 'MAIN');
    await AppwriteConfigManager.init();
    AppLogger.info('✅ Appwrite Config loaded', tag: 'MAIN');

    AppLogger.debug('🔧 Initializing Database...', tag: 'MAIN');
    DatabaseManager.instance; // Initialize database
    AppLogger.info('✅ Database ready', tag: 'MAIN');

    AppLogger.info('⚠️ Google Drive components NOT initialized (DISABLED)', tag: 'MAIN');
    AppLogger.info('═══════════════════════════════════════════════════════', tag: 'MAIN');
    AppLogger.info('✅ Sync System Ready (Appwrite Only)', tag: 'MAIN');
    AppLogger.info('📡 Network monitoring: ACTIVE', tag: 'MAIN');
    AppLogger.info('🔄 Appwrite sync: ACTIVE', tag: 'MAIN');
    AppLogger.info('💾 Data stream listening: ACTIVE', tag: 'MAIN');
    AppLogger.info('═══════════════════════════════════════════════════════', tag: 'MAIN');
    
  } catch (e, st) {
    AppLogger.error(
      '❌ Error in Sync System Initialization',
      tag: 'MAIN',
      error: e,
      stackTrace: st,
    );
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
  bool _initialLocalSyncDone = false;
  StreamSubscription<void>? _localAutoSyncSub;
  Timer? _localAutoSyncDebounce;
  DateTime? _lastLocalAutoSync;
  bool _localAutoSyncRunning = false;
  AppDatabase? _pendingDatabase;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ref.listen<AppDatabase>(databaseProvider, (previous, database) {
      if (_sessionConfigured &&
          previous != null &&
          identical(previous, database)) {
        return;
      }
      _enqueueDatabase(database);
    });
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
    Future<void>.delayed(const Duration(milliseconds: 100), () async {
      try {
        if (_sessionConfigured) {
          await AppSessionManager.onAppCloseOrBackground();
        }
        AppSessionManager.configure(
          database: database,
          deviceIdResolver: () async => 'appwrite_device', // ⚠️ Google Drive deviceId disabled
          syncManager: ref.read(appwrite.appwriteSyncManagerProvider),
        );
        await Seeder(database).seedIfEmpty();
        await AppSessionManager.onAppOpen();
        _sessionConfigured = true;
        _startRealtimeSync();
        _startLocalAutoSync(database);
        _listenForSyncConflicts();
        if (!_initialLocalSyncDone) {
          _initialLocalSyncDone = true;
          unawaited(_runLocalAutoSync());
        }
      } finally {
        _isConfiguringSession = false;
        if (_pendingDatabase != null) {
          _processPendingDatabase();
        }
      }
    });
  }

  void _startRealtimeSync() {
    Future<void>.delayed(const Duration(seconds: 5), () async {
      try {
        final syncManager = ref.read(appwrite.appwriteSyncManagerProvider);
        await syncManager.initialize();

        // تسجيل الجهاز تلقائياً
        try {
          await syncManager.registerDevice();
        } catch (e) {
          debugPrint('⚠️ Device registration error: $e');
        }

        // تهيئة FCM للإشعارات بين الأجهزة
        try {
          await _initializeFcm(syncManager);
        } catch (e) {
          debugPrint('⚠️ FCM initialization error: $e');
        }

        // بدء المزامنة التلقائية (push + pull كل 2 دقيقة)
        syncManager.startAutoSync(
          interval: const Duration(minutes: 2),
        );

        // سحب البيانات عند فتح التطبيق — مع فحص ذكي (مرة كل ساعة)
        try {
          final prefs = await SharedPreferences.getInstance();
          final lastPullEpochMs = prefs.getInt(SyncConstants.lastAppOpenPullKey);
          bool shouldSync = true;

          if (lastPullEpochMs != null) {
            final lastPull = DateTime.fromMillisecondsSinceEpoch(lastPullEpochMs);
            final elapsed = DateTime.now().difference(lastPull);
            if (elapsed < SyncConstants.appOpenSyncInterval) {
              final remaining = SyncConstants.appOpenSyncInterval - elapsed;
              debugPrint(
                '⏭️ تخطي المزامنة عند بدء التطبيق — مرت ${elapsed.inMinutes} دقيقة فقط '
                '(متبقي ${remaining.inMinutes} دقيقة)',
              );
              shouldSync = false;
            }
          }

          if (shouldSync) {
            debugPrint('📥 Pulling latest data from Appwrite on app start...');
            // push + pull معاً — لا نرفع بدون سحب
            await syncManager.sync();
            // تسجيل وقت هذا السحب
            await prefs.setInt(
              SyncConstants.lastAppOpenPullKey,
              DateTime.now().millisecondsSinceEpoch,
            );
            debugPrint('✅ Initial sync on app start completed');
          }
        } catch (e) {
          debugPrint('⚠️ Initial sync on app start failed: $e');
 }

        var deviceId = syncManager.currentDeviceId;
        if (deviceId == null) {
          final prefs = await SharedPreferences.getInstance();
          deviceId = prefs.getString('appwrite_realtime_device_id');
          if (deviceId == null) {
            deviceId = IdGen.uuid();
            await prefs.setString('appwrite_realtime_device_id', deviceId);
          }
        }

        await AppwriteRealtimeSync().initialize(
          deviceId: deviceId,
        );
        await AppwriteRealtimeSync().start();
        debugPrint('📡 Realtime sync + auto sync started');
      } catch (e) {
        debugPrint('❌ Realtime sync init error: $e');
      }
    });
  }

  void _startLocalAutoSync(AppDatabase database) {
    if (_localAutoSyncSub != null) {
      return;
    }
    // ✅ محسّن: تقليل الجداول المراقبة — فقط الجداول الأساسية التي تحتاج مزامنة فورية
    final watch = database.customSelect(
      'SELECT 1',
      readsFrom: {
        database.rooms,
        database.bookings,
        database.payments,
        database.expenses,
        database.cashTransactions,
        database.debts,
      },
    );
    // ✅ محسّن: إضافة debounce 2 ثانية لمنع تكرار المزامنة أثناء العمليات المتتالية
    Timer? debounceTimer;
    _localAutoSyncSub = watch.watch().listen((_) {
      debounceTimer?.cancel();
      debounceTimer = Timer(const Duration(seconds: 2), () {
        _scheduleLocalAutoSync();
      });
    });
  }

  /// الاستماع لأحداث تضاربات المزامنة وعرض إشعارات للمستخدم
  StreamSubscription<SyncConflictEvent>? _conflictSubscription;
  void _listenForSyncConflicts() {
    _conflictSubscription?.cancel();
    _conflictSubscription = SyncConflictEventBus.instance.events.listen(
      (event) {
        if (!mounted || !_sessionConfigured) {
          return;
        }
        final messenger = ScaffoldMessenger.maybeOf(context);
        if (messenger == null) {
          return;
        }
        final tableNames = {
          'bookings': 'حجوزات',
          'payments': 'مدفوعات',
          'debts': 'ديون',
          'expenses': 'مصروفات',
          'rooms': 'غرف',
          'employees': 'موظفين',
        };
        final tableName = tableNames[event.table] ?? event.table;
        final sideText = event.winnerSide == 'local'
            ? 'الإصدار المحلي'
            : 'إصدار السيرفر';
        messenger.showSnackBar(
          SnackBar(
            content: Text('تضارب في $tableName: تم تفضيل $sideText'),
            backgroundColor: Colors.orange.shade800,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
    );
  }

  void _scheduleLocalAutoSync() {
    if (_localAutoSyncRunning) {
      return;
    }
    _localAutoSyncDebounce?.cancel();
    _localAutoSyncDebounce = Timer(
      const Duration(seconds: 2),
      () => unawaited(_runLocalAutoSync()),
    );
  }

  Future<void> _runLocalAutoSync() async {
    if (_localAutoSyncRunning) {
      return;
    }
    final now = DateTime.now();
    final last = _lastLocalAutoSync;
    if (last != null && now.difference(last) < const Duration(seconds: 5)) {
      return;
    }
    _localAutoSyncRunning = true;
    try {
      await ref.read(syncServiceProvider).runSync();
    } catch (e) {
      debugPrint('❌ Local auto sync error: $e');
    } finally {
      _lastLocalAutoSync = DateTime.now();
      _localAutoSyncRunning = false;
    }
  }


  /// تهيئة FCM للإشعارات بين الأجهزة
  Future<void> _initializeFcm(dynamic syncManager) async {
    final fcm = FcmService();

    // حقن الاعتمادات لتجنب import دائري
    FcmService.injectDependencies(
      syncManager: syncManager as AppwriteSyncManager,
      realtimeSync: AppwriteRealtimeSync(),
    );

    await fcm.initialize();

    // تسجيل التوكن في SyncManager
    if (fcm.currentToken != null) {
      await syncManager.setFcmToken(fcm.currentToken!);
    }

    debugPrint('✅ FCM ready — cross-device notifications enabled');
  }

  /// رفع التغييرات المعلقة + سحب التغييرات الجديدة عند العودة للتطبيق
  Future<void> _syncOnResume() async {
    try {
      final syncManager = ref.read(appwrite.appwriteSyncManagerProvider);
      // push: رفع أي تغييرات معلقة في الـ outbox
      // pull: سحب أي تغييرات جديدة من السيرفر
      await syncManager.sync();
      debugPrint('✅ Sync on resume completed (push + pull)');
    } catch (e) {
      debugPrint('⚠️ Sync on resume error: $e');
    }
  }

  /// رفع التغييرات المعلقة عند خروج التطبيق للخلفية
  /// البيانات محفوظة في SQLite (outbox) حتى لو قُتل التطبيق قبل الاكتمال
  /// عند العودة للتطبيق ستتم إعادة المحاولة تلقائياً
  Future<void> _pushPendingChangesOnPause() async {
    try {
      final syncManager = ref.read(appwrite.appwriteSyncManagerProvider);
      // push فقط — لا نسحب لتوفير الوقت قبل أن يقتل النظام التطبيق
      // مهلة 10 ثوانٍ — إذا لم يكتمل، البيانات محفوظة في outbox
      await syncManager.sync(pull: false).timeout(
        const Duration(seconds: 10),
      );
      debugPrint('✅ Push on pause completed');
    } catch (e) {
      // البيانات محفوظة في outbox — لن تُفقد أبداً
      debugPrint('⚠️ Push on pause error (data safe in outbox): $e');
    }
  }

  @override
  void dispose() {
    AppwriteRealtimeSync().stop();
    _localAutoSyncSub?.cancel();
    _conflictSubscription?.cancel();
    _localAutoSyncDebounce?.cancel();
    if (_sessionConfigured) {
      unawaited(AppSessionManager.onAppCloseOrBackground());
    }
    // تنظيف موارد الخدمات Singleton لمنع تسرب الذاكرة
    unawaited(_disposeSingletonServices());
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// تنظيف جميع الخدمات Singleton عند إغلاق التطبيق
  static Future<void> _disposeSingletonServices() async {
    debugPrint('🧹 Disposing singleton services...');
    try {
      await FcmService.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing FcmService: $e');
    }
    try {
      await BatteryOptimizer.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing BatteryOptimizer: $e');
    }
    try {
      await AppwriteRealtimeService.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing AppwriteRealtimeService: $e');
    }
    try {
      await SyncPerformanceOptimizer.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing SyncPerformanceOptimizer: $e');
    }
    try {
      // ⚠️ DISABLED: SmartSyncManager.disposeInstance(); // Google Drive disabled
    } catch (e) {
      debugPrint('⚠️ Error disposing SmartSyncManager: $e');
    }
    try {
      ConnectivityService.instance.dispose();
    } catch (e) {
      debugPrint('⚠️ Error disposing ConnectivityService: $e');
    }
    try {
      HotelDayTicker.instance.dispose();
    } catch (e) {
      debugPrint('⚠️ Error disposing HotelDayTicker: $e');
    }
    try {
      await AutoSyncEngine.instance.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing GoogleDriveAutoSyncEngine: $e');
    }
    try {
      await GoogleDriveUnifiedSyncCoordinator.instance.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing GoogleDriveUnifiedSyncCoordinator: $e');
    }
    try {
      CentralSyncCoordinator.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing CentralSyncCoordinator: $e');
    }
    try {
      BackgroundSyncService.disposeInstance();
    } catch (e) {
      debugPrint('⚠️ Error disposing BackgroundSyncService: $e');
    }
    debugPrint('✅ All singleton services disposed');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_sessionConfigured) {
      return;
    }
    if (state == AppLifecycleState.resumed) {
      debugPrint('📱 التطبيق عاد للواجهة...');
      AppSessionManager.onAppOpen().catchError((Object e, StackTrace s) => debugPrint('Error in onAppOpen: $e\n$s'),
      );
      ref
          .read(backupStatusProvider.notifier)
          .refreshSignInStatus()
          .catchError((Object e, StackTrace s) => debugPrint('Error in refreshSignInStatus: $e\n$s'),
          );
      // رفع التغييرات المعلقة + سحب التغييرات الجديدة عند العودة
      unawaited(_syncOnResume());
      // ⚠️ DISABLED: Google Drive UnifiedSyncOrchestrator
      // UnifiedSyncOrchestrator.instance.onAppForeground().catchError(...);
      SyncGuardian.instance.onAppForeground().catchError((Object e, StackTrace s) => debugPrint('Error in SyncGuardian onAppForeground: $e\n$s'),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      debugPrint('📱 التطبيق في الخلفية...');
      // مزامنة فورية عند الخروج لضمان عدم ضياع البيانات
      unawaited(_pushPendingChangesOnPause());
      // إصلاح: استخدام Future.microtask لالتقاط الاستثناءات المتزامنة أيضاً
      Future.microtask(
        AppSessionManager.onAppCloseOrBackground,
      ).catchError((Object e, StackTrace s) => debugPrint('Error in onAppCloseOrBackground: $e\n$s'),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Consumer(
        builder: (context, ref, _) {
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
            onGenerateRoute: (settings) {
              // إنشاء المسارات بأسلوب lazy — الصفحة لا تُنشأ إلا عند التنقل إليها
              switch (settings.name) {
                case '/employees':
                  return MaterialPageRoute<void>(builder: (_) => const EmployeesListScreen());
                case '/expenses':
                  return MaterialPageRoute<void>(builder: (_) => const ExpensesListScreen());
                case '/finance/cash-register':
                case '/finance/cash-transactions':
                  return MaterialPageRoute<void>(builder: (_) => const FinanceScreen());
                case '/debts':
                  return MaterialPageRoute<void>(builder: (_) => const DebtsListScreen());
                case '/reports':
                  return MaterialPageRoute<void>(builder: (_) => const ReportsScreen());
                default:
                  return null;
              }
            },
            home: const RootRouter(),
          );
        },
      ),
    );
  }
}

class RootRouter extends ConsumerWidget {
  const RootRouter({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    // ✅ محسّن: إزالة ref.watch(backupStatusProvider) لأنه يسبب إعادة بناء
    // كاملة للـ RootRouter عند كل تغيير في حالة النسخ الاحتياطي
    if (auth.isRestoring) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }
    if (!auth.isAuthenticated) {
      // ⚠️ Google Drive login DISABLED - go directly to local login
      return const LoginScreen();
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

  /// قائمة بالمسارات الصالحة (للتحقق من الصلاحيات)
  static const _validRoutes = [
    '/dashboard', '/rooms', '/bookings', '/payments',
    '/debts', '/employees', '/expenses', '/finance',
    '/reports', '/notes', '/blacklist', '/information',
    '/settings', '/ai',
  ];

  /// إنشاء الصفحة المطلوبة بأسلوب lazy — لا تُنشأ أي صفحة حتى يتم طلبها
  Widget _buildRoute(String route) {
    switch (route) {
      case '/dashboard': return const DashboardScreen();
      case '/rooms': return const RoomsListScreen();
      case '/bookings': return const BookingsListScreen();
      case '/payments': return const PaymentsMainScreen();
      case '/debts': return const DebtsListScreen();
      case '/employees': return const EmployeesListScreen();
      case '/expenses': return const ExpensesListScreen();
      case '/finance': return const FinanceScreen();
      case '/reports': return const ReportsScreen();
      case '/notes': return const NotesScreen();
      case '/blacklist': return const BlacklistScreen();
      case '/information': return const InformationScreen();
      case '/settings': return const SettingsScreen();
      case '/ai': return const AiChatScreen();
      default: return const DashboardScreen();
    }
  }

  bool _can(String key) {
    final auth = ref.read(authProvider);
    final u = auth.currentUser;
    if (u == null) {
      return false;
    }
    if (u.userType == 'admin' || u.permissions.contains('all')) {
      return true;
    }
    return u.permissions.contains(key);
  }

  @override
  Widget build(BuildContext context) {
    final routeKey = _currentRoute.replaceAll('/', '');
    final allowed = _can(routeKey.isEmpty ? 'dashboard' : routeKey);
    final body = allowed
        ? _buildRoute(_currentRoute)
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
    final unreadCount = unreadCountAsync.maybeWhen(
      data: (count) => count,
      orElse: () => 0,
    );
    final hasUnread = unreadCount > 0;

    return [
      IconButton(
        onPressed: () {
          Navigator.of(
            context,
          ).push<void>(MaterialPageRoute<void>(builder: (_) => const NotesScreen()));
        },
        tooltip: 'التنبيهات',
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            Icon(
              hasUnread ? Icons.notifications_active : Icons.notifications_none,
            ),
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
    if (_validRoutes.contains(route)) {
      setState(() {
        _currentRoute = route;
      });
    }
  }
}

// SyncGuardian and SyncQueueService are imported from their own files
