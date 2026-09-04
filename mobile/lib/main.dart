// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: unused_catch_stack, discarded_futures
import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io' show Platform;
import 'dart:ui' show DartPluginRegistrant;

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as sqflite_ffi;
import 'package:workmanager/workmanager.dart';

import 'components/admin_layout.dart';
import 'providers/auth_provider.dart';
import 'providers/cloudflare_providers.dart' as cloudflare;
import 'providers/repository_providers.dart';
import 'providers/theme_provider.dart';
import 'screens/ai/ai_chat_screen.dart';
import 'screens/auth/google_drive_login_screen.dart';
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
import 'services/auto_backup_manager.dart';
import 'services/background_sync_service.dart';
import 'services/blacklist_alert_service.dart';
import 'services/battery_optimizer.dart';
import 'services/central_sync_coordinator.dart';
import 'services/cloudflare_config.dart';
import 'services/cloudflare_migration_service.dart';
import 'services/cloudflare_sync_manager.dart';
import 'services/connectivity_service.dart';
import 'services/crashlytics_service.dart';
import 'services/database_sync_coordinator.dart';
import 'services/diagnostics/diagnostics_logger.dart';
import 'services/fcm_service.dart';
import 'services/google_drive_auto_sync_engine.dart';
import 'services/google_drive_backup_service.dart';
import 'services/google_drive_conflict_resolver.dart';
import 'services/google_drive_logger.dart';
import 'services/google_drive_unified_sync_coordinator.dart';
import 'services/hotel_day_key_fix_service.dart';
import 'services/local_db.dart';
import 'services/local_notification_service.dart';
import 'services/logging/log_models.dart';
import 'services/posthog_service.dart';
import 'services/remote_config_service.dart';
import 'services/seed.dart';
import 'services/smart_sync_manager.dart';
import 'services/sync_conflict_event_bus.dart';
import 'services/sync_constants.dart';
import 'services/sync_continuation_service.dart';
import 'services/sync_guardian.dart';
import 'services/sync_performance_optimizer.dart';
import 'services/sync_queue_service.dart';
import 'services/sync_service.dart';
// AutoSync Engine imports
import 'services/unified_sync_orchestrator.dart';
import 'utils/auto_sync_preferences.dart';
import 'utils/debug_log.dart';
import 'utils/env.dart';
import 'utils/hotel_day_ticker.dart';
import 'utils/id.dart';
import 'utils/performance_config.dart';
import 'utils/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ─── Performance: تحسينات الأداء للأجهزة الضعيفة ───
  configurePerformance();

  // ─── Desktop: تهيئة sqflite_common_ffi لـ Windows/Linux/macOS ───
  // sqflite العادي لا يدعم Desktop — نستخدم sqflite_common_ffi
  // الذي يوفّر FFI-based SQLite implementation للمنصات غير المحمولة
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    try {
      sqflite_ffi.sqfliteFfiInit();
      sqflite_ffi.databaseFactory = sqflite_ffi.databaseFactoryFfi;
      debugPrint('✅ sqflite_common_ffi initialized for desktop');
    } catch (e, st) {
      debugPrint('sqflite_common_ffi init failed: $e');
    }
  }

  // ─── Firebase Core: تهيئة قبل كل خدمات Firebase ───
  try {
    await Firebase.initializeApp();
    debugPrint('✅ Firebase Core initialized');
  } catch (e) {
    debugPrint('Firebase Core initialization failed: $e');
    debugPrint('ℹ️ التطبيق يعمل بالإعدادات المحلية بدون Firebase');
  }

  // ─── SecondaryAppwriteConfig: تهيئة SharedPreferences قبل أي وصول للإعدادات ───
  // ⚠️ هذه SERVICE إلزامية — فشلها يعني فشل وصول كامل للإعدادات لاحقاً، فلا نلفّها
  // في try-catch (نُفضّل crash مبكر واضح على crash متأخر غامض عند أول وصول لـ prefs).
  // يجب أن تنتهي قبل باقي الخدمات لأنها تُهيّئ SharedPreferences الذي تعتمد عليه
  // بقية الخدمات (RemoteConfigService، ApiConfigService، DiagnosticsLogger).
  // SecondaryAppwriteConfig removed (Cloudflare migration)

  // ─── Parallel initialization of CRITICAL-ONLY services ───
  // على الأجهزة الضعيفة (1GB RAM)، نُهيّئ فقط Crashlytics + DiagnosticsLogger
  // قبل runApp. باقي الخدمات (RemoteConfig, PostHog, ApiConfig) تُهيّأ بعد أول frame.
  await Future.wait<void>([
    _safeInit('CrashlyticsService', CrashlyticsService.instance.initialize),
    _safeInit('DiagnosticsLogger', DiagnosticsLogger.instance.initialize),
  ]);

  // ─── Deferred initialization (بعد runApp، non-blocking) ───
  // هذه الخدمات لا تؤثر على UI الأولي — يمكن تأجيلها بأمان
  unawaited(
    _safeInit('RemoteConfigService', RemoteConfigService.instance.initialize),
  );
  unawaited(
    _safeInit('ApiConfigService', ApiConfigService.instance.initialize),
  );
  unawaited(_safeInit('PostHogService', PostHogService.instance.initialize));

  // تهيئة نظام الإنذارات المجدولة (نسخ احتياطي + تقارير Telegram)
  // ✅ catchError بدلاً من unawaited المُجرّد — لو فشل initAlarmSystem، نسجّل
  // الخطأ بدل تركه silent (البوت أشار لهذا بشكل صحيح).
  unawaited(
    AlarmBackup.initAlarmSystem().catchError(
      (Object e) => debugPrint('Alarm system init failed: $e'),
    ),
  );

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

  unawaited(
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]),
  );

  debugPrint('BASE_API_URL=${Env.baseApiUrl}');
  runZonedGuarded(() => runApp(const ProviderScope(child: App())), (
    error,
    stack,
  ) async {
    // إرسال الخطأ إلى Crashlytics
    await CrashlyticsService.instance.recordUnexpectedError(
      error: error,
      stackTrace: stack,
      context: 'runZonedGuarded',
    );
    // إرسال الخطأ إلى PostHog (يظهر في session replay مع باقي الأحداث)
    await PostHogService.instance.captureError(
      error,
      stack,
      context: 'runZonedGuarded',
    );
    // تسجيل محلي
    DiagnosticsLogger.instance.recordError(
      error,
      stack,
      tag: 'ZONED',
      level: LogLevel.critical,
    );
  });

  unawaited(_initializeFullyAutomatedSyncSystem());

  // ✅ Secondary sync + blacklist alerts — deferred (non-blocking)
  unawaited(_initializeSecondarySync());
  unawaited(_initializeBlacklistAlerts());

  // ✅ Health checker — deferred 10s to reduce startup CPU pressure
  Timer(const Duration(seconds: 10), _startHealthChecker);
}

/// تهيئة خدمة تنبيهات القائمة السوداء + فحص النزلاء الحاليين
Future<void> _initializeBlacklistAlerts() async {
  try {
    final db = DatabaseManager.instance;
    await BlacklistAlertService.instance.initialize(db);
    debugPrint('✅ BlacklistAlertService initialized');
  } catch (e) {
    debugPrint('⚠️ BlacklistAlertService init failed: $e');
  }
}

/// تهيئة آمنة لخدمة اختيارية — تلتقط الأخطاء وتسجّلها بدلاً من تعطيل التطبيق.
/// تُستخدم مع Future.wait لتشغيل عدة خدمات بالتوازي أثناء إقلاع التطبيق.
Future<void> _safeInit(String label, Future<void> Function() init) async {
  try {
    await init();
  } catch (e, stack) {
    debugPrint('$label initialization failed: $e\n$stack');
  }
}

/// بدء فحص صحة Primary و Secondary كل 30 ثانية.
/// عند تعطل Primary، يتحول Failover تلقائياً لقراءة البيانات من Secondary.
void _startHealthChecker() {
  try {
    // نستخدم AppwriteHealthStatus.instance مباشرة لأنه singleton
    // الـ Riverpod provider سيُستخدم في الـ UI لعرض الحالة
    // AppwriteHealthNotifier removed
    // ✅ Forensic audit fix (2026-07-22):
    // كان الفحص كل 30 ثانية (الافتراضي في startPeriodicCheck). كل فحص ينفذ
    // listDocuments(Query.limit(1)) على rooms (Primary) + listDocuments على
    // rooms (Secondary إن مُفعّل) = 1-2 listDocuments API calls كل 30 ثانية.
    // رفعنا الفاصل إلى 5 دقائق — لا حاجة لكشف التعطل خلال 30 ثانية،
    // فالـ auto-sync (دقيقتين) سيرصد الفشل عبر retry/backoff على أي حال.
    //
    /// للتراجع: أزل المعامل interval للعودة للافتراضي (30 ثانية).
    // notifier.startPeriodicCheck(interval: const Duration(minutes: 5));
    debugPrint('🏥 [Main] Health checker started (5min interval)');
  } catch (e, st) {
    debugPrint('[Main] Health checker init failed: $e');
  }
}

/// تهيئة المزامنة الثانوية عند بدء التطبيق.
/// إذا كان Secondary مُفعّلاً من قبل المستخدم، نبدأ المزامنة التلقائية.
Future<void> _initializeSecondarySync() async {
  try {
    // SecondaryAppwriteConfig removed (Cloudflare migration)
    debugPrint('🔵 [Main] Secondary sync disabled or not configured');
  } catch (e) {
    debugPrint('[Main] Secondary sync init failed: $e');
  }
}

Future<void> _initializeFullyAutomatedSyncSystem() async {
  debugPrint('🚀 Initializing Sync System (deferred)');

  try {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('google_drive_sync_enabled')) {
      await prefs.setBool('google_drive_sync_enabled', false);
    }
    if (!prefs.containsKey('appwrite_sync_enabled')) {
      await prefs.setBool('appwrite_sync_enabled', true);
    }

    // ✅ Database first (critical for everything)
    final database = DatabaseManager.instance;

    // ✅ Unified Sync Orchestrator (Cloudflare push/pull)
    final unifiedOrchestrator = UnifiedSyncOrchestrator.instance;
    await unifiedOrchestrator.initialize(database: database);

    // ✅ Google Drive — LAZY: only if user has previously signed in
    final driveEnabled = prefs.getBool('google_drive_sync_enabled') ?? false;
    if (driveEnabled) {
      debugPrint('📝 Initializing Google Drive (enabled in settings)...');
      final driveLogger = GoogleDriveLogger();
      await driveLogger.initialize(minLevel: LogLevel.debug);

      final backupService = GoogleDriveBackupService();
      try {
        final account = await backupService.attemptSilentSignIn();
        if (account != null) {
          debugPrint('✅ Google Drive session restored');
          final coordinator = GoogleDriveUnifiedSyncCoordinator.instance;
          await coordinator.initialize(
            backupService: backupService,
            database: database,
            logger: driveLogger,
          );
          final conflictResolver = GoogleDriveConflictResolver.instance;
          conflictResolver.initialize(driveLogger);
          await conflictResolver.setStrategy(
            ConflictResolutionStrategy.newerWins,
          );
          await conflictResolver.setConflictThreshold(30);

          // SmartSync + AutoSyncEngine only if Drive is active
          final smartSync = SmartSyncManager.instance;
          await smartSync.initialize(backupService);
          await unifiedOrchestrator.initialize(
            smart: smartSync,
            driveCoordinator: coordinator,
            database: database,
          );

          // SyncGuardian (non-fatal)
          try {
            await SyncGuardian.instance.initialize(database: database);
          } catch (e) {
            debugPrint('SyncGuardian init (non-fatal): $e');
          }

          // WorkManager (non-fatal)
          try {
            await Workmanager().initialize(_unifiedCallbackDispatcher);
            await SyncContinuationService.initialize(debug: kDebugMode);
            await SyncContinuationService.schedulePeriodicCheck();
          } catch (e) {
            debugPrint('WorkManager init (non-fatal): $e');
          }

          // AutoSyncEngine
          final autoSyncEngine = AutoSyncEngine.instance;
          await autoSyncEngine.initialize(
            backupService: backupService,
            database: database,
            logger: driveLogger,
          );
          await _configureAutoSyncEngine(autoSyncEngine);

          final driveSyncEnabled =
              prefs.getBool('google_drive_sync_enabled') ?? false;
          if (backupService.isSignedIn && driveSyncEnabled) {
            await autoSyncEngine.start();
            await autoSyncEngine.onSignInChanged(true);
            await smartSync.onGoogleDriveSignInChanged(true);
          }

          await SyncQueueService.instance.initialize();
          _startEngineMonitoring(autoSyncEngine);
          DatabaseSyncCoordinator.initialize();
          DatabaseSyncCoordinator.registerStopCallback(() async {
            autoSyncEngine.stop();
          });
        } else {
          debugPrint('ℹ️ No Google Drive session — skipping Drive sync init');
        }
      } catch (e) {
        debugPrint('Google Drive init (non-fatal): $e');
      }
    } else {
      debugPrint('ℹ️ Google Drive sync disabled — skipping all Drive init');
    }

    // ✅ SyncGuardian + Database callbacks — always (Cloudflare sync needs these)
    try {
      await SyncGuardian.instance.initialize(database: database);
    } catch (e) {
      debugPrint('SyncGuardian init (non-fatal): $e');
    }
    DatabaseSyncCoordinator.initialize();

    debugPrint('✅ Sync system initialized');
  } catch (e) {
    debugPrint('❌ Sync system init failed: $e');
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

/// يخزن اشتراك مراقبة المحرك لاستخدامه في Dispose
StreamSubscription<void>? _globalEngineMonitoringSub;

void _startEngineMonitoring(AutoSyncEngine engine) {
  _globalEngineMonitoringSub?.cancel();
  _globalEngineMonitoringSub = engine.stateStream.listen((state) {
    debugPrint(
      '📊 ENGINE ${state.isRunning ? '🟢' : '🔴'} | '
      'Net: ${state.hasNetworkConnection ? '🌐' : '📴'} | '
      'Auth: ${state.isSignedIn ? '🔐' : '🔓'} | '
      'Pending: ${state.pendingChangesCount}',
    );
  });
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
          database: DatabaseManager.instance,
          deviceIdResolver: () async =>
              GoogleDriveUnifiedSyncCoordinator.instance.deviceId,
          syncManager: ref.read(cloudflare.cloudflareSyncManagerProvider),
        );
        await Seeder(database).seedIfEmpty();
        // ✅ إصلاح hotelDayKey القديم (14:00 → 14:01) لجميع الجداول
        // يعمل مرة واحدة فقط لكل جلسة — يُصلح البيانات المحلية
        // وعند المزامنة التالية يُرفع hotelDayKey المصحح إلى Cloudflare D1
        await HotelDayKeyFixService.instance.runIfNeeded(database);
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
    Future<void>.delayed(const Duration(seconds: 2), () async {
      try {
        final syncManager = ref.read(cloudflare.cloudflareSyncManagerProvider);
        await syncManager.initialize(database: DatabaseManager.instance);

        // ✅ Cloudflare migration: push local data to D1 on first run
        if (!await CloudflareMigrationService.instance.isMigrationComplete()) {
          debugPrint('🔄 Starting Cloudflare migration...');
          try {
            final result = await CloudflareMigrationService.instance.migrate(
              db: DatabaseManager.instance,
              token: syncManager.token!,
              deviceId: AppwriteSyncManager.currentDeviceIdStatic!,
            );
            debugPrint(
              '🔄 Migration: ${result.totalPushed}/${result.totalRecords} pushed, ${result.totalFailed} failed',
            );
          } catch (e, st) {
            debugPrint('⚠️ Migration error: $e');
          }
        }

        // تسجيل الجهاز تلقائياً
        try {
          await syncManager.registerDevice();
        } catch (e, st) {
          debugPrint('Device registration error: $e');
        }

        // ✅ تهيئة الإشعارات المحلية (للأحداث على نفس الجهاز)
        // تُظهر notifications عند إنشاء حجز/دفعة/مصروف على نفس الجهاز
        // (مكمّلة لـ FCM الذي يُرسل للأجهزة الأخرى).
        try {
          await LocalNotificationService.instance.initialize();
        } catch (e, st) {
          debugPrint('Local notifications init error: $e');
        }

        // تهيئة FCM للإشعارات بين الأجهزة
        try {
          await _initializeFcm(syncManager);
        } catch (e) {
          debugPrint('FCM initialization error: $e');
        }

        // بدء المزامنة التلقائية (push + pull)
        // ✅ Forensic audit fix (2026-07-22):
        // كان الفاصل دقيقتين → 30 دورة/ساعة × 3 أجهزة × 20 collection
        // = 1,800 listDocuments/ساعة. مع 15 دقيقة → 4 دورات/ساعة = 240/ساعة.
        // توفير: ~87% من auto-sync reads.
        //
        // ✅ قابل للتغيير من الإعدادات (SyncConstants.autoSyncIntervalPrefKey):
        //   5  — للموظفين النشطين
        //   15 — افتراضي
        //   30 — للأجهزة الثابتة
        //   60 — للأجهزة منخفضة الأولوية
        //
        // Delta Sync يضمن وصول التغييرات عبر $updatedAt filter.
        // Realtime WebSocket (عند تفعيله) يوفر إشعارات فورية بين الأدوار.
        final syncPrefs = await SharedPreferences.getInstance();
        final intervalMinutes =
            syncPrefs.getInt(SyncConstants.autoSyncIntervalPrefKey) ??
            SyncConstants.autoSyncIntervalDefaultMinutes;
        final clampedMinutes = intervalMinutes.clamp(
          SyncConstants.autoSyncIntervalMinMinutes,
          SyncConstants.autoSyncIntervalMaxMinutes,
        );
        syncManager.startAutoSync(interval: Duration(minutes: clampedMinutes));
        debugPrint('⏰ Auto-sync started: every $clampedMinutes minutes');

        // سحب البيانات عند فتح التطبيق — مع فحص ذكي (مرة كل ساعة)
        try {
          final prefs = await SharedPreferences.getInstance();
          final lastPullEpochMs = prefs.getInt(
            SyncConstants.lastAppOpenPullKey,
          );
          bool shouldSync = true;

          if (lastPullEpochMs != null) {
            final lastPull = DateTime.fromMillisecondsSinceEpoch(
              lastPullEpochMs,
            );
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
            debugPrint(
              '📥 Pulling latest data from Cloudflare D1 on app start...',
            );
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
          debugPrint('Initial sync on app start failed: $e');
        }

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

        // Realtime sync started
        // Realtime sync started
        debugPrint('📡 Realtime sync + auto sync started');
      } catch (e) {
        derr(() => 'Realtime sync init error: $e');
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

  /// الاستماع لأحداث تضاربات المزامنة وعرض إشعارات للمستخدم
  StreamSubscription<SyncConflictEvent>? _conflictSubscription;
  void _listenForSyncConflicts() {
    _conflictSubscription?.cancel();
    _conflictSubscription = SyncConflictEventBus.instance.events.listen((
      event,
    ) {
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
    });
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
      derr(() => 'Local auto sync error: $e');
    } finally {
      _lastLocalAutoSync = DateTime.now();
      _localAutoSyncRunning = false;
    }
  }

  /// تهيئة FCM للإشعارات بين الأجهزة
  Future<void> _initializeFcm(AppwriteSyncManager syncManager) async {
    final fcm = FcmService();

    // ✅ المرحلة 3: Realtime كامل عبر WebSocket (SyncLockDO) — نفس
    // المثال singleton يُحقن في FCM (شارة UI) ويُضبط trigger السحب
    // على المسار الدلتا-فقط للمدير (realtimeTriggeredPull).
    final realtime = AppwriteRealtimeSync();
    realtime.setSyncTrigger(syncManager.realtimeTriggeredPull);
    realtime.configure(
      baseUrl: CloudflareConfig.workerUrl,
      tokenProvider: () async => CloudflareSyncManager().token,
    );
    await realtime.initialize(deviceId: syncManager.currentDeviceId);
    unawaited(realtime.start());

    // حقن الاعتمادات لتجنب import دائري
    FcmService.injectDependencies(
      syncManager: syncManager,
      realtimeSync: realtime,
    );

    await fcm.initialize();

    // تسجيل التوكن في SyncManager
    if (fcm.currentToken != null) {
      await syncManager.setFcmToken(fcm.currentToken!);
    }

    debugPrint('✅ FCM ready — cross-device notifications enabled');
  }

  /// رفع التغييرات المعلقة عند العودة للتطبيق.
  ///
  /// ✅ Forensic audit fix (2026-07-22):
  /// كان الكود السابق ينفذ sync(push: true, pull: true) — أي push + pull
  /// كامل (20 listDocuments API calls). لكن UnifiedSyncOrchestrator.onAppForeground()
  /// (main.dart:861) ينفذ بالفعل syncNow(push: false, pull: true) — أي pull كامل.
  /// النتيجة: pull مزدوج عند كل عودة من الخلفية (40 listDocuments بدل 20).
  ///
  /// الإصلاح: تحويل _syncOnResume ليعمل push فقط (sync(push: true, pull: false)).
  /// هذا يحافظ على الوظيفة الحرجة (رفع التغييرات المعلقة في outbox عند العودة)
  /// ويزيل pull المكرر الذي يغطيه UnifiedSyncOrchestrator.onAppForeground.
  ///
  /// للتراجع: أعد pull: true (الافتراضي) في السطر التالي.
  /// للقياس: شغّل التطبيق على جهازين، أنشئ حجزاً على أحدهما، أخرج للخلفية،
  /// عُد للتطبيق، وتحقق من وصول التغيير للجهاز الثاني + راقب Cloudflare Dashboard
  /// → Usage → Database Reads قبل وبعد هذا التغيير.
  Future<void> _syncOnResume() async {
    try {
      final syncManager = ref.read(cloudflare.cloudflareSyncManagerProvider);
      // push فقط — pull يُغطَّى بواسطة UnifiedSyncOrchestrator.onAppForeground()
      await syncManager.sync(pull: false);
      debugPrint(
        '✅ Push on resume completed (pull handled by UnifiedSyncOrchestrator)',
      );
    } catch (e) {
      debugPrint('Sync on resume error: $e');
    }
  }

  /// رفع التغييرات المعلقة عند خروج التطبيق للخلفية
  /// البيانات محفوظة في SQLite (outbox) حتى لو قُتل التطبيق قبل الاكتمال
  /// عند العودة للتطبيق ستتم إعادة المحاولة تلقائياً
  ///
  /// ✅ إصلاح جذري: إضافة جدولة مهمة WorkManager لإكمال المزامنة
  /// في الخلفية بدلاً من الاعتماد على timeout 10 ثوانٍ فقط.
  /// السيناريو:
  ///   1. المستخدم يضغط Push/Pull
  ///   2. يخرج من الشاشة أو يُغلق التطبيق
  ///   3. timeout 10 ثوانٍ قد لا يكفي للمزامنة الكاملة
  ///   4. WorkManager يُكمل المزامنة في الخلفية مع constraints (network)
  Future<void> _pushPendingChangesOnPause() async {
    try {
      final syncManager = ref.read(cloudflare.cloudflareSyncManagerProvider);
      // push فقط — لا نسحب لتوفير الوقت قبل أن يقتل النظام التطبيق
      // مهلة 10 ثوانٍ — إذا لم يكتمل، البيانات محفوظة في outbox
      await syncManager.sync(pull: false).timeout(const Duration(seconds: 10));
      debugPrint('✅ Push on pause completed');
    } catch (e) {
      // البيانات محفوظة في outbox — لن تُفقد أبداً
      debugPrint('Push on pause error (data safe in outbox): $e');

      // ✅ جدولة مهمة WorkManager لإكمال المزامنة في الخلفية
      // البيانات محفوظة في outbox، لكن push للسحابة لم يكتمل —
      // WorkManager سيُحاول إكماله عند توفر الشبكة.
      try {
        await SyncContinuationService.scheduleSyncCompletion();
        debugPrint('📅 Scheduled WorkManager to complete sync in background');
      } catch (schedErr) {
        debugPrint('Failed to schedule sync continuation: $schedErr');
      }
    }
  }

  @override
  void dispose() {
    // Realtime sync stopped
    _globalEngineMonitoringSub?.cancel();
    _localAutoSyncSub?.cancel();
    _conflictSubscription?.cancel();
    _localAutoSyncDebounce?.cancel();
    if (_sessionConfigured) {
      unawaited(AppSessionManager.onAppCloseOrBackground());
      // ✅ جدولة مهمة WorkManager لإكمال أي مزامنة معلّقة
      // قبل تدمير الـ widget نهائياً. هذا يضمن أن البيانات
      // ستُرفع للسحابة حتى لو قُتل التطبيق فوراً بعد dispose().
      unawaited(
        SyncContinuationService.scheduleSyncCompletion().catchError(
          (Object e, StackTrace s) => derr(
            () => 'Error scheduling sync continuation on dispose: $e\n$s',
          ),
        ),
      );
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
    } catch (e, st) {
      debugPrint('Error disposing FcmService: $e');
    }
    try {
      await BatteryOptimizer.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing BatteryOptimizer: $e');
    }
    try {
      // Realtime disposed
    } catch (e, st) {
      debugPrint('Error disposing realtime: $e');
    }
    try {
      await SyncPerformanceOptimizer.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing SyncPerformanceOptimizer: $e');
    }
    try {
      await SmartSyncManager.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing SmartSyncManager: $e');
    }
    try {
      ConnectivityService.instance.dispose();
    } catch (e, st) {
      debugPrint('Error disposing ConnectivityService: $e');
    }
    try {
      HotelDayTicker.instance.dispose();
    } catch (e, st) {
      debugPrint('Error disposing HotelDayTicker: $e');
    }
    try {
      AutoSyncEngine.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing GoogleDriveAutoSyncEngine: $e');
    }
    try {
      UnifiedSyncOrchestrator.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing UnifiedSyncOrchestrator: $e');
    }
    try {
      GoogleDriveUnifiedSyncCoordinator.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing GoogleDriveUnifiedSyncCoordinator: $e');
    }
    try {
      CentralSyncCoordinator.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing CentralSyncCoordinator: $e');
    }
    try {
      BackgroundSyncService.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing BackgroundSyncService: $e');
    }
    // ✅ تنظيف خدمات إضافية كانت تتسرب StreamController
    try {
      SyncConflictEventBus.instance.dispose();
    } catch (e, st) {
      debugPrint('Error disposing SyncConflictEventBus: $e');
    }
    // ✅ Batch 3: تنظيف AutoBackupManager timers + SmartSyncManager timers
    try {
      AutoBackupManager.disposeInstance();
    } catch (e, st) {
      debugPrint('Error disposing AutoBackupManager: $e');
    }
    // ✅ Batch 3: تنظيف SyncGuardian timer + StreamController
    try {
      await SyncGuardian.disposeInstance();
    } catch (e) {
      debugPrint('Error disposing SyncGuardian: $e');
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
      AppSessionManager.onAppOpen().catchError(
        (Object e, StackTrace s) => derr(() => 'Error in onAppOpen: $e\n$s'),
      );
      ref
          .read(backupStatusProvider.notifier)
          .refreshSignInStatus()
          .catchError(
            (Object e, StackTrace s) =>
                derr(() => 'Error in refreshSignInStatus: $e\n$s'),
          );
      // ✅ تحسين أداء: تقليل تكرار المزامنة عند العودة — مزامنة واحدة فقط
      // سابقاً: 4 عمليات مزامنة متوازية (consumePendingAndSync + _syncOnResume +
      // UnifiedSyncOrchestrator.onAppForeground + SyncGuardian.onAppForeground)
      // الآن: _syncOnResume كعملية أساسية + إشعار UnifiedSyncOrchestrator بدون مزامنة مستقلة
      unawaited(_syncOnResume());
      // إشعار خدمات المزامنة بالعودة — بدون بدء مزامنة مستقلة (ستكتفي بالتحقق)
      UnifiedSyncOrchestrator.instance.onAppForeground().catchError(
        (Object e, StackTrace s) =>
            derr(() => 'Error in UnifiedSync onAppForeground: $e\n$s'),
      );
      SyncGuardian.instance.onAppForeground().catchError(
        (Object e, StackTrace s) =>
            derr(() => 'Error in SyncGuardian onAppForeground: $e\n$s'),
      );
      // ✅ المرحلة 3.3: إعادة فتح Realtime عند العودة للواجهة
      // (+ استرداد دلتا لما فات أثناء الخمول عبر recovery pull)
      unawaited(
        AppwriteRealtimeSync().ensureStarted().catchError(
          (Object e, StackTrace s) =>
              derr(() => 'Error in realtime ensureStarted: $e\n$s'),
        ),
      );
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      debugPrint('📱 التطبيق في الخلفية...');
      // ✅ المرحلة 3.3: إغلاق Realtime في الخلفية (توفير بطارية/وحدات DO)
      unawaited(AppwriteRealtimeSync().stop());
      // مزامنة فورية عند الخروج لضمان عدم ضياع البيانات
      unawaited(_pushPendingChangesOnPause());
      // ✅ جدولة مهمة WorkManager لإكمال المزامنة في الخلفية
      // حتى لو قُتل التطبيق قبل اكتمال _pushPendingChangesOnPause
      unawaited(
        SyncContinuationService.scheduleSyncCompletion().catchError(
          (Object e, StackTrace s) =>
              derr(() => 'Error scheduling sync continuation: $e\n$s'),
        ),
      );
      // إصلاح: استخدام Future.microtask لالتقاط الاستثناءات المتزامنة أيضاً
      Future.microtask(
        AppSessionManager.onAppCloseOrBackground,
      ).catchError(
        (Object e, StackTrace s) =>
            derr(() => 'Error in onAppCloseOrBackground: $e\n$s'),
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
            // ✅ تم إزالة onGenerateRoute — جميع المسارات تُدار عبر HomeShell
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

  /// قائمة بالمسارات الصالحة (للتحقق من الصلاحيات)
  static const _validRoutes = [
    '/dashboard',
    '/rooms',
    '/bookings',
    '/payments',
    '/debts',
    '/employees',
    '/expenses',
    '/finance',
    '/reports',
    '/notes',
    '/blacklist',
    '/information',
    '/settings',
    '/ai',
  ];

  /// إنشاء الصفحة المطلوبة بأسلوب lazy — لا تُنشأ أي صفحة حتى يتم طلبها
  Widget _buildRoute(String route) {
    switch (route) {
      case '/dashboard':
        return const DashboardScreen();
      case '/rooms':
        return const RoomsListScreen();
      case '/bookings':
        return const BookingsListScreen();
      case '/payments':
        return const PaymentsMainScreen();
      case '/debts':
        return const DebtsListScreen();
      case '/employees':
        return const EmployeesListScreen();
      case '/expenses':
        return const ExpensesListScreen();
      case '/finance':
        return const FinanceScreen();
      case '/reports':
        return const ReportsScreen();
      case '/notes':
        return const NotesScreen();
      case '/blacklist':
        return const BlacklistScreen();
      case '/information':
        return const InformationScreen();
      case '/settings':
        return const SettingsScreen();
      case '/ai':
        return const AiChatScreen();
      default:
        return const DashboardScreen();
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
          Navigator.of(context).push<void>(
            MaterialPageRoute<void>(builder: (_) => const NotesScreen()),
          );
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

// ═══════════════════════════════════════════════════════════════
//  Unified WorkManager Callback Dispatcher
// ═══════════════════════════════════════════════════════════════
//
// ✅ نقطة دخول موحّدة لكل مهام WorkManager في التطبيق.
// ضرورية لأن Workmanager().initialize() يقبل callback واحد فقط.
//
// المهام المُغطّاة:
// - marina_sync_completion_immediate (SyncContinuationService)
// - marina_sync_completion (SyncContinuationService periodic)
// - marina_auto_sync_now (AutoSyncTask)
// - marina_auto_sync_periodic (AutoSyncTask)
// - backupAfterInactivity (AppSessionManager)
// - marina-hotel-background-sync (BackgroundSyncService legacy)
// - marina-hotel-periodic-sync (BackgroundSyncService legacy)
// - marina-hotel-battery-aware-sync (BackgroundSyncService legacy)
// - autoBackup / autoBackupTask
// - default → محاولة المزامنة كـ fallback

@pragma('vm:entry-point')
void _unifiedCallbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    // ✅ تهيئة إلزامية في بداية الـ callback — قبل أي عمل.
    // WidgetsFlutterBinding: ضروري لـ MethodChannel, SharedPreferences, Firebase.
    // DartPluginRegistrant: ضروري لـ plugins المُسجّلة (connectivity_plus,
    // shared_preferences_android, firebase_*) في background context.
    // بدونها: MissingPluginException عند أول استدعاء لـ SharedPreferences.
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

    // ✅ Gemini #4: تهيئة الإعدادات والـ singletons داخل isolate المنفصل
    // Workmanager يعمل في isolate منفصل — لا يشارك state من main()
    try {
      // SecondaryAppwriteConfig removed (Cloudflare migration)
      // AppwriteConfigManager removed
    } catch (e) {
      developer.log('⚠️ [WorkManager] Init failed: $e', name: 'WorkManager');
    }

    developer.log('📋 [WorkManager] Task executed: $task', name: 'WorkManager');

    try {
      // توجيه المهمة بناءً على اسمها
      switch (task) {
        case kSyncCompletionImmediateTask:
        case kSyncCompletionTask:
          return await _executeSyncCompletionTask(task, inputData);

        case 'marina_auto_sync_now':
        case 'marina_auto_sync_periodic':
          return await _executeAutoSyncTask(task, inputData);

        case 'backupAfterInactivity':
          return await _executeBackupAfterInactivity(task, inputData);

        case 'marina-hotel-background-sync':
        case 'marina-hotel-periodic-sync':
        case 'marina-hotel-battery-aware-sync':
        case 'autoBackup':
        case 'autoBackupTask':
          return await _executeLegacySyncTask(task, inputData);

        default:
          developer.log(
            '⚠️ [WorkManager] Unknown task: $task → fallback to sync',
            name: 'WorkManager',
          );
          return await _executeLegacySyncTask(task, inputData);
      }
    } catch (e, st) {
      developer.log(
        '❌ [WorkManager] Task $task failed',
        name: 'WorkManager',
        error: e,
        stackTrace: st,
      );
      return false;
    }
  });
}

/// تنفيذ مهمة إكمال المزامنة (SyncContinuationService)
///
/// ✅ تستخدم public constants من sync_continuation_service.dart (kSyncPendingPushFlag,
/// kSyncPendingPullFlag, kSyncActiveFlag, kSyncStartTimeKey) — لا string literals.
/// ✅ تتحقق من المدة المنقضية (kMaxSyncDuration) لتجنّب المزامنات القديمة جداً.
/// ✅ تنظيف flags عند النجاح فقط — عند الفشل، WorkManager يُعيد المحاولة تلقائياً.
Future<bool> _executeSyncCompletionTask(
  String task,
  Map<String, dynamic>? inputData,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final hasPendingPush = prefs.getBool(kSyncPendingPushFlag) ?? false;
    final hasPendingPull = prefs.getBool(kSyncPendingPullFlag) ?? false;

    if (!hasPendingPush && !hasPendingPull) {
      developer.log(
        'ℹ️ [SyncContinuation] لا توجد عمليات معلّقة',
        name: 'SyncContinuation',
      );
      return true;
    }

    // ✅ فحص المدة — إذا تجاوزت kMaxSyncDuration، نُلغي (المزامنة الدورية ستلتقط لاحقاً)
    final startTimeMs = prefs.getInt(kSyncStartTimeKey) ?? 0;
    if (startTimeMs > 0) {
      final elapsedMs = DateTime.now().millisecondsSinceEpoch - startTimeMs;
      if (elapsedMs > kMaxSyncDuration.inMilliseconds) {
        developer.log(
          '⚠️ [SyncContinuation] تجاوز الحد الزمني (${elapsedMs ~/ 1000}s) — إلغاء',
          name: 'SyncContinuation',
        );
        // تنظيف flags لأن المهمة قديمة جداً
        await prefs.setBool(kSyncActiveFlag, false);
        await prefs.setBool(kSyncPendingPushFlag, false);
        await prefs.setBool(kSyncPendingPullFlag, false);
        await prefs.remove(kSyncStartTimeKey);
        return true; // نجاح (ألغينا المهمة عمداً)
      }
    }

    developer.log(
      '🔄 [SyncContinuation] تنفيذ push=$hasPendingPush, pull=$hasPendingPull',
      name: 'SyncContinuation',
    );

    // ✅ UnifiedSyncOrchestrator.instance هو singleton — syncNow() يُهيّئ
    // _appwrite و _database داخلياً عبر _ensureAppwriteManager() إن كانا null.
    final success = await UnifiedSyncOrchestrator.instance.syncNow(
      push: hasPendingPush,
      pull: hasPendingPull,
      reason: 'workmanager_sync_completion',
    );

    if (success) {
      // ✅ تنظيف flags باستخدام public constants (لا string literals)
      await prefs.setBool(kSyncActiveFlag, false);
      await prefs.setBool(kSyncPendingPushFlag, false);
      await prefs.setBool(kSyncPendingPullFlag, false);
      await prefs.remove(kSyncStartTimeKey);
      developer.log(
        '✅ [SyncContinuation] اكتملت المزامنة في الخلفية',
        name: 'SyncContinuation',
      );
    } else {
      developer.log(
        '⚠️ [SyncContinuation] فشلت — سيُعيد WorkManager المحاولة',
        name: 'SyncContinuation',
      );
    }

    return success;
  } catch (e, st) {
    developer.log(
      '❌ [SyncContinuation] فشل',
      name: 'SyncContinuation',
      error: e,
      stackTrace: st,
    );
    return false;
  }
}

/// تنفيذ مهمة AutoSyncTask (Google Drive)
Future<bool> _executeAutoSyncTask(
  String task,
  Map<String, dynamic>? inputData,
) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final googleDriveEnabled =
        prefs.getBool('google_drive_sync_enabled') ?? false;

    if (!googleDriveEnabled) {
      developer.log(
        'ℹ️ [AutoSyncTask] Google Drive معطّل — تخطّي',
        name: 'AutoSyncTask',
      );
      return true;
    }

    final success = await UnifiedSyncOrchestrator.instance.syncNow(
      reason: 'workmanager_auto_sync',
    );

    // ✅ تحديث flag المعلّق (يُستخدم من SyncGuardian)
    await prefs.setBool('auto_sync_pending', !success);

    return success;
  } catch (e, st) {
    developer.log(
      '❌ [AutoSyncTask] فشل',
      name: 'AutoSyncTask',
      error: e,
      stackTrace: st,
    );
    return false;
  }
}

/// تنفيذ مهمة backupAfterInactivity (AppSessionManager)
Future<bool> _executeBackupAfterInactivity(
  String task,
  Map<String, dynamic>? inputData,
) async {
  try {
    final success = await UnifiedSyncOrchestrator.instance.syncNow(
      reason: 'workmanager_backup_inactivity',
    );
    return success;
  } catch (e, st) {
    developer.log(
      '❌ [BackupInactivity] فشل',
      name: 'BackupInactivity',
      error: e,
      stackTrace: st,
    );
    return false;
  }
}

/// تنفيذ مهمة legacy sync
Future<bool> _executeLegacySyncTask(
  String task,
  Map<String, dynamic>? inputData,
) async {
  try {
    final success = await UnifiedSyncOrchestrator.instance.syncNow(
      reason: 'workmanager_legacy_$task',
    );
    return success;
  } catch (e, st) {
    developer.log(
      '❌ [LegacySync] فشل ($task)',
      name: 'LegacySync',
      error: e,
      stackTrace: st,
    );
    return false;
  }
}
