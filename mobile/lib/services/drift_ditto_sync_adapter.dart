import 'dart:async';
import 'package:flutter/material.dart';
import 'local_db.dart';
import 'ditto_sync_service.dart';
import 'ditto_realtime_service.dart';

class DriftDittoSyncAdapter {
  final AppDatabase db;
  final DittoSyncService syncService;
  final DittoRealtimeService realtimeService;

  bool _isInitialized = false;
  StreamSubscription<RealtimeEvent>? _eventsSubscription;
  Timer? _syncTimer;

  DriftDittoSyncAdapter({
    required this.db,
    required this.syncService,
    required this.realtimeService,
  });

  Future<void> initialize() async {
    if (_isInitialized) {
      debugPrint('⚠️ Drift-Ditto Adapter already initialized');
      return;
    }

    try {
      debugPrint('🔄 Initializing Drift-Ditto Sync Adapter...');

      await syncService.initialize();

      await realtimeService.subscribeToAll();

      _eventsSubscription = realtimeService.eventsStream.listen(
        _handleRealtimeEvent,
        onError: (error) {
          debugPrint('❌ Realtime event error: $error');
        },
      );

      _startPeriodicSync();

      _isInitialized = true;
      debugPrint('✅ Drift-Ditto Sync Adapter initialized successfully');
    } catch (e) {
      debugPrint('❌ Failed to initialize Drift-Ditto Adapter: $e');
      rethrow;
    }
  }

  void _startPeriodicSync() {
    _syncTimer?.cancel();
    
    _syncTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) async {
        try {
          await syncService.runSync();
        } catch (e) {
          debugPrint('❌ Periodic sync error: $e');
        }
      },
    );
  }

  void _handleRealtimeEvent(RealtimeEvent event) {
    debugPrint(
      '📡 Realtime: ${event.eventType} in ${event.collection}',
    );
  }

  Future<void> syncNow() async {
    try {
      debugPrint('🔄 Manual sync triggered...');
      await syncService.runSync();
      debugPrint('✅ Manual sync completed');
    } catch (e) {
      debugPrint('❌ Manual sync failed: $e');
      rethrow;
    }
  }

  Future<void> pauseSync() async {
    debugPrint('⏸️ Pausing sync...');
    _syncTimer?.cancel();
    await realtimeService.unsubscribeAll();
  }

  Future<void> resumeSync() async {
    debugPrint('▶️ Resuming sync...');
    await realtimeService.subscribeToAll();
    _startPeriodicSync();
  }

  Map<String, dynamic> getStats() {
    return {
      'isInitialized': _isInitialized,
      'syncService': syncService.getPerformanceStats(),
      'realtimeService': realtimeService.getStats(),
    };
  }

  Future<void> dispose() async {
    _isInitialized = false;
    _syncTimer?.cancel();
    await _eventsSubscription?.cancel();
    await syncService.dispose();
    await realtimeService.dispose();
    debugPrint('🔌 Drift-Ditto Sync Adapter disposed');
  }
}
