import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../local_db.dart';
import 'adapters/appwrite_target_adapter.dart';
import 'adapters/google_drive_target_adapter.dart';
import 'adapters/local_json_target_adapter.dart';
import 'adapters/sync_target_adapter.dart';
import 'enhanced_event_bus.dart';
import 'events/sync_event.dart';
import 'persistence/event_persistence.dart';
import 'persistence/sqlite_event_persistence.dart';
import 'router/enhanced_sync_router.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  return DatabaseManager.instance;
});

final eventPersistenceProvider = Provider<EventPersistence>((ref) {
  final db = ref.watch(databaseProvider);
  return SqliteEventPersistence(db);
});

final eventBusProvider = Provider<EnhancedEventBus>((ref) {
  final persistence = ref.watch(eventPersistenceProvider);
  final bus = EnhancedEventBus(persistence);

  ref.onDispose(() => bus.dispose());

  return bus;
});

final appwriteAdapterProvider = Provider<AppwriteTargetAdapter>((ref) {
  final db = ref.watch(databaseProvider);
  return AppwriteTargetAdapter(database: db);
});

final googleDriveAdapterProvider = Provider<GoogleDriveTargetAdapter>((ref) {
  final db = ref.watch(databaseProvider);
  return GoogleDriveTargetAdapter(database: db);
});

final localJsonAdapterProvider = Provider<LocalJsonTargetAdapter>((ref) {
  final db = ref.watch(databaseProvider);
  return LocalJsonTargetAdapter(database: db);
});

final syncRouterConfigProvider = StateProvider<SyncRouterConfig>((ref) {
  return const SyncRouterConfig(
    strategy: RoutingStrategy.all,
    debounceWindow: Duration(seconds: 2),
    maxBatchSize: 50,
    maxRetries: 3,
    enableParallel: true,
    primaryTarget: SyncTargetType.appwrite,
  );
});

final syncRouterProvider = Provider<EnhancedSyncRouter>((ref) {
  final eventBus = ref.watch(eventBusProvider);
  final config = ref.watch(syncRouterConfigProvider);

  final router = EnhancedSyncRouter(
    eventBus: eventBus,
    config: config,
  );

  final appwrite = ref.watch(appwriteAdapterProvider);
  final drive = ref.watch(googleDriveAdapterProvider);
  final local = ref.watch(localJsonAdapterProvider);

  router.registerAdapter(appwrite);
  router.registerAdapter(drive);
  router.registerAdapter(local);

  ref.onDispose(() => router.dispose());

  return router;
});

final syncRouterStateProvider = StreamProvider<SyncRouterState>((ref) {
  final router = ref.watch(syncRouterProvider);
  return router.stateStream;
});

final pendingEventsCountProvider = FutureProvider<int>((ref) async {
  final eventBus = ref.watch(eventBusProvider);
  return eventBus.pendingCount();
});

final syncStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final eventBus = ref.watch(eventBusProvider);
  return eventBus.getStats();
});

final adapterStatusesProvider =
    FutureProvider<Map<SyncTargetType, SyncTargetStatus>>((ref) async {
  final router = ref.watch(syncRouterProvider);
  return router.getAdapterStatuses();
});

final isAppwriteEnabledProvider = Provider<bool>((ref) {
  final adapter = ref.watch(appwriteAdapterProvider);
  return adapter.isEnabled;
});

final isGoogleDriveEnabledProvider = Provider<bool>((ref) {
  final adapter = ref.watch(googleDriveAdapterProvider);
  return adapter.isEnabled;
});

final isLocalBackupEnabledProvider = Provider<bool>((ref) {
  final adapter = ref.watch(localJsonAdapterProvider);
  return adapter.isEnabled;
});

class SyncService {
  final EnhancedEventBus _eventBus;
  final EnhancedSyncRouter _router;

  SyncService(this._eventBus, this._router);

  Future<void> initialize() async {
    await _eventBus.initialize();
    await _router.start();
    await _eventBus.replayUnacknowledged();
  }

  Future<void> publishCreate({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    SyncPriority priority = SyncPriority.normal,
  }) async {
    await _eventBus.publishCreate(
      table: table,
      entityId: entityId,
      payload: payload,
      priority: priority,
    );
  }

  Future<void> publishUpdate({
    required String table,
    required String entityId,
    required Map<String, dynamic> payload,
    Map<String, dynamic>? previousPayload,
    SyncPriority priority = SyncPriority.normal,
  }) async {
    await _eventBus.publishUpdate(
      table: table,
      entityId: entityId,
      payload: payload,
      previousPayload: previousPayload,
      priority: priority,
    );
  }

  Future<void> publishDelete({
    required String table,
    required String entityId,
    SyncPriority priority = SyncPriority.normal,
  }) async {
    await _eventBus.publishDelete(
      table: table,
      entityId: entityId,
      priority: priority,
    );
  }

  Future<RouteResult> syncNow({bool push = true, bool pull = true}) async {
    return _router.syncNow(push: push, pull: pull);
  }

  Stream<SyncRouterState> get stateStream => _router.stateStream;

  Future<void> dispose() async {
    await _router.dispose();
    await _eventBus.dispose();
  }
}

final syncServiceProvider = Provider<SyncService>((ref) {
  final eventBus = ref.watch(eventBusProvider);
  final router = ref.watch(syncRouterProvider);
  final service = SyncService(eventBus, router);

  ref.onDispose(() => service.dispose());

  return service;
});

final syncServiceInitializerProvider = FutureProvider<void>((ref) async {
  final service = ref.watch(syncServiceProvider);
  await service.initialize();
});

class SyncNotifier extends StateNotifier<SyncState> {
  final SyncService _service;

  SyncNotifier(this._service) : super(const SyncState());

  Future<void> syncNow() async {
    state = state.copyWith(isSyncing: true, error: null);

    try {
      final result = await _service.syncNow();
      state = state.copyWith(
        isSyncing: false,
        lastSyncAt: DateTime.now(),
        lastResult: result,
      );
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        error: e.toString(),
      );
    }
  }

  Future<void> pushOnly() async {
    state = state.copyWith(isSyncing: true, error: null);

    try {
      final result = await _service.syncNow(push: true, pull: false);
      state = state.copyWith(
        isSyncing: false,
        lastSyncAt: DateTime.now(),
        lastResult: result,
      );
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        error: e.toString(),
      );
    }
  }

  Future<void> pullOnly() async {
    state = state.copyWith(isSyncing: true, error: null);

    try {
      final result = await _service.syncNow(push: false, pull: true);
      state = state.copyWith(
        isSyncing: false,
        lastSyncAt: DateTime.now(),
        lastResult: result,
      );
    } catch (e) {
      state = state.copyWith(
        isSyncing: false,
        error: e.toString(),
      );
    }
  }
}

class SyncState {
  final bool isSyncing;
  final DateTime? lastSyncAt;
  final String? error;
  final RouteResult? lastResult;

  const SyncState({
    this.isSyncing = false,
    this.lastSyncAt,
    this.error,
    this.lastResult,
  });

  SyncState copyWith({
    bool? isSyncing,
    DateTime? lastSyncAt,
    String? error,
    RouteResult? lastResult,
  }) {
    return SyncState(
      isSyncing: isSyncing ?? this.isSyncing,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      error: error,
      lastResult: lastResult ?? this.lastResult,
    );
  }
}

final syncNotifierProvider =
    StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  final service = ref.watch(syncServiceProvider);
  return SyncNotifier(service);
});
