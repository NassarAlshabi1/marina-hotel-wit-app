import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'services/google_drive_auto_sync_engine.dart';
import 'services/google_drive_backup_service.dart';
import 'services/google_drive_conflict_resolver.dart';
import 'services/google_drive_logger.dart';
import 'services/unified_sync_orchestrator.dart';
import 'services/google_drive_unified_sync_coordinator.dart';
import 'services/local_db.dart';
import 'services/logging/log_models.dart';
import 'services/sync_guardian.dart';
import 'utils/auto_sync_preferences.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  await _initializeFullyAutomatedSyncSystem();

  runApp(const ProviderScope(child: MarinaHotelApp()));
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
    final unifiedOrchestrator = UnifiedSyncOrchestrator.instance;
    await unifiedOrchestrator.initialize(
      driveCoordinator: coordinator,
      database: database,
    );
    debugPrint('✅ Coordinator initialized');

    debugPrint('🤝 [5/6] Initializing Conflict Resolver...');
    final conflictResolver = GoogleDriveConflictResolver.instance;
    conflictResolver.initialize(driveLogger);

    await conflictResolver.setStrategy(ConflictResolutionStrategy.newerWins);
    await conflictResolver.setConflictThreshold(30);
    debugPrint('✅ Conflict Resolver initialized (strategy: newerWins)');

    debugPrint('🛡️ Initializing SyncGuardian...');
    final guardian = SyncGuardian.instance;
    await guardian.initialize(
      database: database,
    );
    debugPrint('✅ SyncGuardian initialized');

    debugPrint('🤖 Initializing & Starting Auto Sync Engine...');
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
    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    debugPrint('$statusIcon Running: ${state.isRunning}');
    debugPrint('$networkIcon Network: ${state.hasNetworkConnection}');
    debugPrint('$authIcon Signed in: ${state.isSignedIn}');
    debugPrint('📦 Pending changes: ${state.pendingChangesCount}');
    debugPrint(
        '✅ Last successful sync: ${state.lastSuccessfulSync ?? "Never"}');
    debugPrint('❌ Failed attempts: ${state.failedAttempts}');

    if (state.nextRetryAt != null) {
      final secondsUntil =
          state.nextRetryAt!.difference(DateTime.now()).inSeconds;
      debugPrint('⏰ Next retry in: ${secondsUntil}s');
    }

    if (state.lastError != null) {
      debugPrint('⚠️ Last error: ${state.lastError}');
    }

    debugPrint('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  });

  debugPrint('✅ Monitoring setup complete');
}

class MarinaHotelApp extends ConsumerWidget {
  const MarinaHotelApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Marina Hotel',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Tajawal',
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Marina Hotel'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            onPressed: () => _showSyncStatus(context),
          ),
        ],
      ),
      body: const Center(
        child: Text('Marina Hotel Management System'),
      ),
    );
  }

  Future<void> _showSyncStatus(BuildContext context) async {
    final engine = AutoSyncEngine.instance;
    final status = await engine.getEngineStatus();

    if (context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('حالة المزامنة التلقائية'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildStatusRow('المحرك يعمل', status['engine']['running']),
                _buildStatusRow(
                    'متصل بالشبكة', status['engine']['network_connected']),
                _buildStatusRow('مسجل الدخول', status['engine']['signed_in']),
                const Divider(),
                Text('تغييرات معلقة: ${status['engine']['pending_changes']}'),
                Text('محاولات فاشلة: ${status['engine']['failed_attempts']}'),
                if (status['engine']['last_successful_sync'] != null)
                  Text(
                      'آخر مزامنة: ${_formatTimestamp(status['engine']['last_successful_sync'])}'),
                if (status['engine']['next_retry'] != null)
                  Text(
                      'إعادة محاولة بعد: ${_formatTimestamp(status['engine']['next_retry'])}'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
            if (status['engine']['running'] == true)
              ElevatedButton(
                onPressed: () async {
                  Navigator.pop(context);
                  final result = await engine.forceSyncNow();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(result.success
                            ? '✅ ${result.message}'
                            : '❌ ${result.message}'),
                        backgroundColor:
                            result.success ? Colors.green : Colors.red,
                      ),
                    );
                  }
                },
                child: const Text('مزامنة الآن'),
              ),
          ],
        ),
      );
    }
  }

  Widget _buildStatusRow(String label, dynamic value) {
    final isTrue = value == true;
    return Row(
      children: [
        Icon(
          isTrue ? Icons.check_circle : Icons.cancel,
          color: isTrue ? Colors.green : Colors.red,
          size: 20,
        ),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }

  String _formatTimestamp(String? iso) {
    if (iso == null) return 'غير متوفر';
    try {
      final dt = DateTime.parse(iso);
      final now = DateTime.now();
      final diff = now.difference(dt);

      if (diff.inMinutes < 1) {
        return 'منذ ${diff.inSeconds} ثانية';
      } else if (diff.inHours < 1) {
        return 'منذ ${diff.inMinutes} دقيقة';
      } else if (diff.inDays < 1) {
        return 'منذ ${diff.inHours} ساعة';
      } else {
        return 'منذ ${diff.inDays} يوم';
      }
    } catch (_) {
      return iso;
    }
  }
}
