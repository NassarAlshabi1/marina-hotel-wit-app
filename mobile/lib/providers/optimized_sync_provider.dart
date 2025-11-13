import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/optimized_sync_service.dart';
import 'backup_provider.dart';

/// Provider for OptimizedSyncService singleton
final optimizedSyncServiceProvider = Provider<OptimizedSyncService>((ref) {
  final service = OptimizedSyncService.instance;
  
  final driveService = ref.watch(googleDriveBackupServiceProvider);
  service.initialize(driveService);
  
  return service;
});

/// Current sync status
enum SyncStatus {
  idle,
  preparingDelta,
  uploading,
  downloading,
  merging,
  completed,
  error,
}

/// Provider for current sync status
final syncStatusProvider = StateProvider<SyncStatus>((ref) {
  return SyncStatus.idle;
});

/// Provider for last sync result
final lastSyncResultProvider = StateProvider<SyncResult?>((ref) {
  return null;
});

/// Auto-sync manager provider
final autoOptimizedSyncProvider = Provider<AutoOptimizedSyncManager>((ref) {
  final syncService = ref.watch(optimizedSyncServiceProvider);
  final backupState = ref.watch(backupStatusProvider);
  
  final manager = AutoOptimizedSyncManager(syncService);
  
  if (backupState.isSignedIn) {
    manager.startAutoSync();
  }
  
  ref.onDispose(() {
    manager.stopAutoSync();
  });
  
  return manager;
});

/// Auto-sync manager for periodic syncing
class AutoOptimizedSyncManager {
  final OptimizedSyncService _syncService;
  Timer? _syncTimer;
  bool _isEnabled = false;
  
  AutoOptimizedSyncManager(this._syncService);
  
  void startAutoSync({int intervalMinutes = 5}) {
    if (_isEnabled) return;
    
    _isEnabled = true;
    _syncTimer?.cancel();
    
    _syncTimer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (timer) async {
        debugPrint('🔄 Auto-sync triggered (interval: ${intervalMinutes}min)');
        await _syncService.performSync();
      },
    );
    
    debugPrint('✅ Auto-sync started (interval: ${intervalMinutes}min)');
    
    Future.microtask(() => _syncService.performSync());
  }
  
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _isEnabled = false;
    debugPrint('⏹️ Auto-sync stopped');
  }
  
  bool get isEnabled => _isEnabled;
}
