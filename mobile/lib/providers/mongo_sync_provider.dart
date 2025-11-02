import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/flutter_mongo_sync_service.dart';
import '../services/local_db.dart';
import 'core_providers.dart';

final mongoSyncServiceProvider = Provider<FlutterMongoSyncService>((ref) {
  final db = ref.watch(databaseProvider);
  return FlutterMongoSyncService.getInstance(db);
});

final syncStatusProvider = StreamProvider<SyncStatus>((ref) {
  final syncService = ref.watch(mongoSyncServiceProvider);
  return syncService.syncStatusStream;
});

final mongoConnectionProvider = StateNotifierProvider<MongoConnectionNotifier, MongoConnectionState>(
  (ref) => MongoConnectionNotifier(ref),
);

class MongoConnectionState {
  final bool isConnected;
  final bool isLoading;
  final String? error;
  final bool autoSyncEnabled;

  MongoConnectionState({
    this.isConnected = false,
    this.isLoading = false,
    this.error,
    this.autoSyncEnabled = false,
  });

  MongoConnectionState copyWith({
    bool? isConnected,
    bool? isLoading,
    String? error,
    bool? autoSyncEnabled,
  }) {
    return MongoConnectionState(
      isConnected: isConnected ?? this.isConnected,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      autoSyncEnabled: autoSyncEnabled ?? this.autoSyncEnabled,
    );
  }
}

class MongoConnectionNotifier extends StateNotifier<MongoConnectionState> {
  final Ref ref;

  MongoConnectionNotifier(this.ref) : super(MongoConnectionState());

  Future<void> connect(String password) async {
    state = state.copyWith(isLoading: true, error: null);

    try {
      final syncService = ref.read(mongoSyncServiceProvider);
      await syncService.initialize(password);
      
      state = state.copyWith(
        isConnected: true,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isConnected: false,
        isLoading: false,
        error: e.toString(),
      );
      rethrow;
    }
  }

  Future<void> startAutoSync({Duration? interval}) async {
    final syncService = ref.read(mongoSyncServiceProvider);
    
    if (interval != null) {
      syncService.startAutoSync(interval: interval);
    } else {
      syncService.startAutoSync();
    }
    
    state = state.copyWith(autoSyncEnabled: true);
  }

  void stopAutoSync() {
    final syncService = ref.read(mongoSyncServiceProvider);
    syncService.stopAutoSync();
    
    state = state.copyWith(autoSyncEnabled: false);
  }

  Future<SyncResult> syncNow() async {
    final syncService = ref.read(mongoSyncServiceProvider);
    return await syncService.syncAll();
  }
}

final syncStatsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final syncService = ref.watch(mongoSyncServiceProvider);
  return await syncService.getStats();
});
