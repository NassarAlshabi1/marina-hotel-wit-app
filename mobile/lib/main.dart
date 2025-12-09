import 'dart:async';

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

// AutoSync Engine imports
import 'services/google_drive_auto_sync_engine.dart';
import 'services/google_drive_conflict_resolver.dart';
import 'services/google_drive_unified_sync_coordinator.dart';
import 'services/logging/log_models.dart';

import 'components/admin_layout.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  
  await _initializeFullyAutomatedSyncSystem();
  
  debugPrint('BASE_API_URL=' + Env.baseApiUrl);
  runApp(const ProviderScope(child: App()));
}

Future<void> _initializeFullyAutomatedSyncSystem() async {
  debugPrint('═══════════════════════════════════════════════════════');
  debugPrint('🚀 Initializing Fully Automated Sync System');
  debugPrint('═══════════════════════════════════════════════════════');
  
  try {
    debugPrint('📝 [1/6] Initializing Google Drive Logger...');
    final driveLogger = GoogleDriveLogger();
    await driveLogger.initialize(
      minLevel: LogLevel.debug,
      enableConsole: true,
      enableFile: false,
    );
    debugPrint('✅ Logger initialized');
    
    debugPrint('🔐 [2/6] Initializing Google Drive Backup Service...');
    final backupService = GoogleDriveBackupService();
    
    try {
      final account = await backupService.attemptSilentSignIn();
      if (account != null) {
        debugPrint('✅ Silent sign-in successful: ${account.email}');
      } else {
        debugPrint('ℹ️ No saved session - user must sign in manually');
      }
    } catch (e) {
      debugPrint('⚠️ Silent sign-in failed: $e');
    }
    
    debugPrint('🔧 [3/6] Initializing Database...');
    final database = DatabaseManager.instance;
    debugPrint('✅ Database ready');
    
    debugPrint('🎯 [4/6] Initializing Unified Sync Coordinator...');
    final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
    await coordinator.initialize(
      backupService: backupService,
      database: database,
      logger: driveLogger,
    );
    debugPrint('✅ Coordinator initialized');
    
    debugPrint('🤝 [5/6] Initializing Conflict Resolver...');
    final conflictResolver = GoogleDriveConflictResolver.instance;
    conflictResolver.initialize(driveLogger);
    
    await conflictResolver.setStrategy(ConflictResolutionStrategy.newerWins);
    await conflictResolver.setConflictThreshold(30);
    debugPrint('✅ Conflict Resolver initialized (strategy: newerWins)');
    
    debugPrint('🤖 [6/6] Initializing & Starting Auto Sync Engine...');
    final autoSyncEngine = AutoSyncEngine.instance;
    
    await autoSyncEngine.initialize(
      backupService: backupService,
      database: database,
      logger: driveLogger,
    );
    
    await _configureAutoSyncEngine(autoSyncEngine);
    
    await autoSyncEngine.start();
    
    if (backupService.isSignedIn) {
      await autoSyncEngine.onSignInChanged(true);
    }
    
    _setupEngineMonitoring(autoSyncEngine);
    
    debugPrint('✅ Auto Sync Engine started');
    
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
  
  final prefs = await SharedPreferences.getInstance();
  
  final debounceSeconds = prefs.getInt('auto_sync_debounce') ?? 5;
  await engine.setDebounceSeconds(debounceSeconds);
  debugPrint('   ⏱️ Debounce: ${debounceSeconds}s');
  
  final pullInterval = prefs.getInt('auto_sync_pull_interval') ?? 2;
  await engine.setPullInterval(pullInterval);
  debugPrint('   ⏰ Pull interval: ${pullInterval}min');
  
  final retryEnabled = prefs.getBool('auto_sync_retry_enabled') ?? true;
  await engine.setRetryEnabled(retryEnabled);
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
    debugPrint('✅ Last successful sync: ${state.lastSuccessfulSync ?? "Never"}');
    debugPrint('❌ Failed attempts: ${state.failedAttempts}');
    
    if (state.nextRetryAt != null) {
      final secondsUntil = state.nextRetryAt!.difference(DateTime.now()).inSeconds;
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
          deviceIdResolver: () async => GoogleDriveUnifiedSyncCoordinator.instance.deviceId,
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
      unawaited(GoogleDriveUnifiedSyncCoordinator.instance.onAppForeground());
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
