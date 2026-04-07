import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'screens/security/blacklist_screen.dart';
import 'screens/information/information_screen.dart';
import 'screens/auth/google_drive_login_screen.dart';
import 'screens/auth/login_screen.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/repository_providers.dart';
import 'services/seed.dart';
import 'services/app_session_manager.dart';
import 'services/google_drive_backup_service.dart';
import 'services/google_drive_logger.dart';
import 'services/local_db.dart';
import 'services/smart_sync_manager.dart';
import 'services/sync_guardian.dart';
import 'services/database_sync_coordinator.dart';
import 'utils/auto_sync_preferences.dart';
import 'utils/id.dart';

// AutoSync Engine imports
import 'services/unified_sync_orchestrator.dart';
import 'services/google_drive_auto_sync_engine.dart';
import 'services/google_drive_conflict_resolver.dart';
import 'services/google_drive_unified_sync_coordinator.dart';
import 'services/logging/log_models.dart';
import 'services/diagnostics/diagnostics_logger.dart';
import 'services/sync_queue_service.dart';
import 'services/api_config_service.dart';
import 'services/appwrite_config_manager.dart';
import 'services/appwrite_realtime_sync.dart';
import 'services/fcm_service.dart';
import 'services/sync_service.dart';
import 'providers/appwrite_providers.dart' as appwrite;

import 'components/admin_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DiagnosticsLogger.instance.initialize();
  await ApiConfigService.instance.initialize();

  FlutterError.onError = (details) {
    DiagnosticsLogger.instance.recordFlutterError(details);
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    DiagnosticsLogger.instance.recordError(
      error,
      stack,
      tag: 'PLATFORM',
      level: LogLevel.critical,
    );
    return true;
  };

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  debugPrint('BASE_API_URL=' + Env.baseApiUrl);
  runZonedGuarded(
    () => runApp(const ProviderScope(child: App())),
    (error, stack) => DiagnosticsLogger.instance.recordError(
      error,
      stack,
      tag: 'ZONED',
      level: LogLevel.critical,
    ),
  );

  unawaited(_initializeFullyAutomatedSyncSystem());
}

Future<void> _initializeFullyAutomatedSyncSystem() async {
  debugPrint('═══════════════════════════════════════════════════════');
  debugPrint('🚀 Initializing Fully Automated Sync System');
  debugPrint('═══════════════════════════════════════════════════════');

  try {
    final prefs = await SharedPreferences.getInstance();
    final disableGoogleDriveSyncOnStart =
        prefs.getBool('google_drive_sync_disable_on_start') ?? false;
    if (disableGoogleDriveSyncOnStart) {
      await prefs.setBool('google_drive_sync_enabled', false);
    }
    if (!prefs.containsKey('google_drive_sync_enabled')) {
      await prefs.setBool('google_drive_sync_enabled', false);
    }
    if (!prefs.containsKey('appwrite_sync_enabled')) {
      await prefs.setBool('appwrite_sync_enabled', true);
    }

    debugPrint('📦 Initializing Appwrite Config Manager...');
    await AppwriteConfigManager.init();
    debugPrint('✅ Appwrite Config loaded');

    debugPrint('📝 Initializing Google Drive Logger...');
    final driveLogger = GoogleDriveLogger();
    await driveLogger.initialize(
      minLevel: LogLevel.debug,
      enableConsole: true,
      enableFile: false,
    );
    debugPrint('✅ Logger initialized');

    debugPrint('🔐 Initializing Google Drive Backup Service...');
    final backupService = GoogleDriveBackupService();

    try {
      // محاولة استعادة الجلسة بشكل صامت
      final account = await backupService.attemptSilentSignIn();
      if (account != null) {
        debugPrint('✅ تم استعادة جلسة Google Drive: ${account.email}');
      } else {
        debugPrint('ℹ️ لا توجد جلسة محفوظة - المستخدم يحتاج لتسجيل دخول يدوي');
      }
    } catch (e) {
      debugPrint('⚠️ فشلت استعادة الجلسة: $e');
    }

    debugPrint('🔧 [3/7] Initializing Database...');
    final database = DatabaseManager.instance;
    debugPrint('✅ Database ready');

    debugPrint('🎯 [4/7] Initializing Unified Sync Orchestrator...');
    final unifiedOrchestrator = UnifiedSyncOrchestrator.instance;
    await unifiedOrchestrator.initialize(database: database);
    debugPrint('✅ Unified Sync Orchestrator ready');

    debugPrint('🎯 [5/7] Initializing Unified Sync Coordinator...');
    final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
    await coordinator.initialize(
      backupService: backupService,
      database: database,
      logger: driveLogger,
    );
    debugPrint('✅ Coordinator initialized');

    debugPrint('🤝 [6/7] Initializing Conflict Resolver...');
    final conflictResolver = GoogleDriveConflictResolver.instance;
    conflictResolver.initialize(driveLogger);

    await conflictResolver.setStrategy(ConflictResolutionStrategy.newerWins);
    await conflictResolver.setConflictThreshold(30);
    debugPrint('✅ Conflict Resolver initialized (strategy: newerWins)');

    debugPrint('🧠 [7/8] Initializing SmartSyncManager...');
    final smartSync = SmartSyncManager.instance;
    await smartSync.initialize(backupService);
    await unifiedOrchestrator.initialize(
      smart: smartSync,
      driveCoordinator: coordinator,
      database: database,
    );
    debugPrint('✅ SmartSyncManager initialized');

    debugPrint('🤖 [8/8] Initializing & Starting Auto Sync Engine...');
    final autoSyncEngine = AutoSyncEngine.instance;

    await autoSyncEngine.initialize(
      backupService: backupService,
      database: database,
      logger: driveLogger,
    );

    await _configureAutoSyncEngine(autoSyncEngine);

    // لا يتم بدء المزامنة تلقائياً عند فتح التطبيق
    // await autoSyncEngine.start();

    // if (backupService.isSignedIn) {
    //   debugPrint('🔔 إشعار أنظمة المزامنة بتسجيل الدخول...');
    //   await autoSyncEngine.onSignInChanged(true);
    //   await smartSync.onGoogleDriveSignInChanged(true);
    //   debugPrint('✅ تم إشعار جميع أنظمة المزامنة');
    // }
    debugPrint('ℹ️ المزامنة التلقائية معطلة عند بدء التطبيق');

    await SyncQueueService.instance.initialize();

    _setupEngineMonitoring(autoSyncEngine);

    debugPrint('✅ Auto Sync Engine started');

    debugPrint('🔗 Registering Database Sync Callbacks...');
    DatabaseSyncCoordinator.initialize();

    // Register stop callbacks
    DatabaseSyncCoordinator.registerStopCallback(() async {
      autoSyncEngine.stop();
    });
    DatabaseSyncCoordinator.registerStopCallback(() async {
      await SyncGuardian.instance.stop();
    });

    // Register restart callbacks
    DatabaseSyncCoordinator.registerRestartCallback(() async {
      await autoSyncEngine.restart();
    });
    DatabaseSyncCoordinator.registerRestartCallback(() async {
      await SyncGuardian.instance.restart();
    });

    debugPrint('✅ Sync callbacks registered');

    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('✅ Fully Automated Sync System Ready!');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('📡 Network monitoring: ACTIVE');
    debugPrint('🔄 Lifecycle monitoring: ACTIVE');
    debugPrint('💾 Data stream listening: ACTIVE');
    debugPrint('❤️ Health checks: ACTIVE (every 5 minutes)');
    debugPrint('🔁 Auto-retry: ACTIVE (exponential backoff)');
    debugPrint('═══════════════════════════════════════════════════════');
  } catch (e, stackTrace) {
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('❌ CRITICAL ERROR in Sync System Initialization');
    debugPrint('═══════════════════════════════════════════════════════');
    debugPrint('Error: $e');
    debugPrint('Stack trace: $stackTrace');
    debugPrint('═══════════════════════════════════════════════════════');
  }
}

Future<void> _configureAutoSyncEngine(AutoSyncEngine engine) async {
  debugPrint('⚙️ Configuring Auto Sync Engine...');

  const engineDebounceKey = 'auto_sync_engine_debounce';
  const legacyDebounceKey = 'auto_sync_debounce';
  const enginePullIntervalKey = 'auto_sync_engine_pull_interval';
  const legacyPullIntervalKey = 'auto_sync_pull_interval';
  const engineRetryKey = 'auto_sync_engine_retry_enabled';
  const legacyRetryKey = 'auto_sync_retry_enabled';

  final prefs = await SharedPreferences.getInstance();

  final debounceSeconds = await migrateAutoSyncPreference<int>(
    prefs: prefs,
    newKey: engineDebounceKey,
    legacyKey: legacyDebounceKey,
    defaultValue: 5,
    apply: (value) => engine.setDebounceSeconds(value),
  );
  debugPrint('   ⏱️ Debounce: ${debounceSeconds}s');

  final pullInterval = await migrateAutoSyncPreference<int>(
    prefs: prefs,
    newKey: enginePullIntervalKey,
    legacyKey: legacyPullIntervalKey,
    defaultValue: 2,
    apply: (value) => engine.setPullInterval(value),
  );
  debugPrint('   ⏰ Pull interval: ${pullInterval}min');

  final retryEnabled = await migrateAutoSyncPreference<bool>(
    prefs: prefs,
    newKey: engineRetryKey,
    legacyKey: legacyRetryKey,
    defaultValue: true,
    apply: (value) => engine.setRetryEnabled(value),
  );
  debugPrint('   🔁 Auto-retry: $retryEnabled');

  final conflictStrategy = prefs.getString('conflict_strategy') ?? 'newerWins';
  final strategy = ConflictResolutionStrategy.values.firstWhere(
    (s) => s.name == conflictStrategy,
    orElse: () => ConflictResolutionStrategy.newerWins,
  );
  await engine.setConflictStrategy(strategy);
  debugPrint('   🤝 Conflict strategy: ${strategy.name}');

  debugPrint('✅ Configuration complete');
}

void _setupEngineMonitoring(AutoSyncEngine engine) {
  debugPrint('📊 Setting up engine state monitoring...');

  engine.stateStream.listen((state) {
    final statusIcon = state.isRunning ? '🟢' : '🔴';
    final networkIcon = state.hasNetworkConnection ? '🌐' : '📴';
    final authIcon = state.isSignedIn ? '🔐' : '🔓';

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('📊 ENGINE STATE UPDATE');
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━====');
    debugPrint('$statusIcon Running: ${state.isRunning}');
    debugPrint('$networkIcon Network: ${state.hasNetworkConnection}');
    debugPrint('$authIcon Signed in: ${state.isSignedIn}');
    debugPrint('📦 Pending changes: ${state.pendingChangesCount}');
    debugPrint(
      '✅ Last successful sync: ${state.lastSuccessfulSync ?? "Never"}',
    );
    debugPrint('❌ Failed attempts: ${state.failedAttempts}');

    if (state.nextRetryAt != null) {
      final secondsUntil = state.nextRetryAt!
          .difference(DateTime.now())
          .inSeconds;
      debugPrint('⏰ Next retry in: ${secondsUntil}s');
    }

    if (state.lastError != null) {
      debugPrint('⚠️ Last error: ${state.lastError}');
    }

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  });

  debugPrint('✅ Monitoring setup complete');
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
  DateTime? _lastAppwriteAutoPull;
  StreamSubscription? _localAutoSyncSub;
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
    Future.delayed(const Duration(milliseconds: 100), () async {
      try {
        if (_sessionConfigured) {
          await AppSessionManager.onAppCloseOrBackground();
        }
        AppSessionManager.configure(
          database: database,
          deviceIdResolver: () async =>
              GoogleDriveUnifiedSyncCoordinator.instance.deviceId,
        );
        await Seeder(database).seedIfEmpty();
        await AppSessionManager.onAppOpen();
        _sessionConfigured = true;
        _startRealtimeSync();
        _startLocalAutoSync(database);
        if (!_initialLocalSyncDone) {
          _initialLocalSyncDone = true;
          unawaited(_runLocalAutoSync());
        }
        unawaited(_autoPullLatestFromAppwrite());
      } finally {
        _isConfiguringSession = false;
        if (_pendingDatabase != null) {
          _processPendingDatabase();
        }
      }
    });
  }

  void _startRealtimeSync() {
    Future.delayed(const Duration(seconds: 3), () async {
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

        var deviceId = GoogleDriveUnifiedSyncCoordinator.instance.deviceId;
        deviceId ??= syncManager.currentDeviceId;
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
    final watch = database.customSelect(
      'SELECT 1',
      readsFrom: {
        database.rooms,
        database.bookings,
        database.bookingNotes,
        database.bookingNights,
        database.employees,
        database.expenses,
        database.cashTransactions,
        database.payments,
        database.debts,
        database.hotelDayLedger,
        database.shiftNotes,
      },
    );
    _localAutoSyncSub = watch.watch().listen((_) => _scheduleLocalAutoSync());
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

  Future<void> _autoPullLatestFromAppwrite() async {
    try {
      final syncManager = ref.read(appwrite.appwriteSyncManagerProvider);
      await syncManager.initialize();
      await syncManager.pullRemoteChanges();
      _lastAppwriteAutoPull = DateTime.now();
    } catch (e) {
      debugPrint('❌ Appwrite auto-pull error: $e');
    }
  }

  /// تهيئة FCM للإشعارات بين الأجهزة
  Future<void> _initializeFcm(dynamic syncManager) async {
    final fcm = FcmService();

    // حقن الاعتمادات لتجنب import دائري
    FcmService.injectDependencies(
      syncManager: syncManager,
      realtimeSync: AppwriteRealtimeSync(),
    );

    await fcm.initialize();

    // تسجيل التوكن في SyncManager
    if (fcm.currentToken != null) {
      await syncManager.setFcmToken(fcm.currentToken!);
    }

    debugPrint('✅ FCM ready — cross-device notifications enabled');
  }

  Future<void> _autoPullAppwriteOnResume() async {
    final last = _lastAppwriteAutoPull;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(seconds: 30)) {
      return;
    }
    await _autoPullLatestFromAppwrite();
  }

  @override
  void dispose() {
    AppwriteRealtimeSync().stop();
    _localAutoSyncSub?.cancel();
    _localAutoSyncDebounce?.cancel();
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
      debugPrint('📱 التطبيق عاد للواجهة...');
      AppSessionManager.onAppOpen().catchError(
        (e, s) => debugPrint('Error in onAppOpen: $e\n$s'),
      );
      ref
          .read(backupStatusProvider.notifier)
          .refreshSignInStatus()
          .catchError(
            (e, s) => debugPrint('Error in refreshSignInStatus: $e\n$s'),
          );
      unawaited(_autoPullAppwriteOnResume());
      UnifiedSyncOrchestrator.instance.onAppForeground().catchError(
        (e, s) => debugPrint('Error in UnifiedSync onAppForeground: $e\n$s'),
      );
      SyncGuardian.instance.onAppForeground().catchError(
        (e, s) => debugPrint('Error in SyncGuardian onAppForeground: $e\n$s'),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      debugPrint('📱 التطبيق في الخلفية...');
      // إصلاح: استخدام Future.microtask لالتقاط الاستثناءات المتزامنة أيضاً
      Future.microtask(
        () => AppSessionManager.onAppCloseOrBackground(),
      ).catchError(
        (e, s) => debugPrint('Error in onAppCloseOrBackground: $e\n$s'),
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
    final backup = ref.watch(backupStatusProvider);
    if (auth.isRestoring) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: Center(child: CircularProgressIndicator())),
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
    '/blacklist': const BlacklistScreen(),
    '/information': const InformationScreen(),
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
          ).push(MaterialPageRoute(builder: (_) => const NotesScreen()));
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
    if (_routes.containsKey(route)) {
      setState(() {
        _currentRoute = route;
      });
    }
  }
}
