import 'dart:developer' as developer;

import 'local_db.dart';
import 'google_drive_auto_sync_engine.dart';
import 'sync_guardian.dart';
import 'realtime_sync_notifier.dart';

/// Coordinator for managing sync operations lifecycle with database
/// 
/// This class coordinates stopping and restarting sync services
/// when database needs to be closed/reopened (e.g., during restore)
class DatabaseSyncCoordinator {
  static bool _initialized = false;

  /// Initialize the coordinator and register callbacks with DatabaseManager
  static void initialize() {
    if (_initialized) {
      return;
    }

    DatabaseManager.registerSyncCallbacks(
      onStop: _stopAllSyncServices,
      onRestart: _restartAllSyncServices,
    );

    _initialized = true;
    developer.log('✅ DatabaseSyncCoordinator initialized', name: 'DatabaseSyncCoordinator');
  }

  /// Stop all sync services
  static Future<void> _stopAllSyncServices() async {
    developer.log('⏸️ Stopping all sync services...', name: 'DatabaseSyncCoordinator');
    
    final errors = <String>[];
    
    // Stop Auto Sync Engine
    try {
      await GoogleDriveAutoSyncEngine.instance?.stop();
      developer.log('  ✓ Stopped GoogleDriveAutoSyncEngine', name: 'DatabaseSyncCoordinator');
    } catch (e) {
      errors.add('GoogleDriveAutoSyncEngine: $e');
      developer.log('  ⚠️ Error stopping GoogleDriveAutoSyncEngine: $e', name: 'DatabaseSyncCoordinator');
    }
    
    // Stop Sync Guardian
    try {
      await SyncGuardian.instance.stop();
      developer.log('  ✓ Stopped SyncGuardian', name: 'DatabaseSyncCoordinator');
    } catch (e) {
      errors.add('SyncGuardian: $e');
      developer.log('  ⚠️ Error stopping SyncGuardian: $e', name: 'DatabaseSyncCoordinator');
    }
    
    // Stop Realtime Sync
    try {
      RealtimeSyncNotifier.instance?.stopListening();
      developer.log('  ✓ Stopped RealtimeSyncNotifier', name: 'DatabaseSyncCoordinator');
    } catch (e) {
      errors.add('RealtimeSyncNotifier: $e');
      developer.log('  ⚠️ Error stopping RealtimeSyncNotifier: $e', name: 'DatabaseSyncCoordinator');
    }
    
    if (errors.isEmpty) {
      developer.log('✅ All sync services stopped successfully', name: 'DatabaseSyncCoordinator');
    } else {
      developer.log('⚠️ Stopped sync services with ${errors.length} errors', name: 'DatabaseSyncCoordinator');
    }
  }

  /// Restart all sync services
  static Future<void> _restartAllSyncServices() async {
    developer.log('▶️ Restarting all sync services...', name: 'DatabaseSyncCoordinator');
    
    final errors = <String>[];
    
    // Restart Auto Sync Engine
    try {
      await GoogleDriveAutoSyncEngine.instance?.restart();
      developer.log('  ✓ Restarted GoogleDriveAutoSyncEngine', name: 'DatabaseSyncCoordinator');
    } catch (e) {
      errors.add('GoogleDriveAutoSyncEngine: $e');
      developer.log('  ⚠️ Error restarting GoogleDriveAutoSyncEngine: $e', name: 'DatabaseSyncCoordinator');
    }
    
    // Restart Sync Guardian
    try {
      await SyncGuardian.instance.restart();
      developer.log('  ✓ Restarted SyncGuardian', name: 'DatabaseSyncCoordinator');
    } catch (e) {
      errors.add('SyncGuardian: $e');
      developer.log('  ⚠️ Error restarting SyncGuardian: $e', name: 'DatabaseSyncCoordinator');
    }
    
    // Restart Realtime Sync
    try {
      RealtimeSyncNotifier.instance?.startListening();
      developer.log('  ✓ Restarted RealtimeSyncNotifier', name: 'DatabaseSyncCoordinator');
    } catch (e) {
      errors.add('RealtimeSyncNotifier: $e');
      developer.log('  ⚠️ Error restarting RealtimeSyncNotifier: $e', name: 'DatabaseSyncCoordinator');
    }
    
    if (errors.isEmpty) {
      developer.log('✅ All sync services restarted successfully', name: 'DatabaseSyncCoordinator');
    } else {
      developer.log('⚠️ Restarted sync services with ${errors.length} errors', name: 'DatabaseSyncCoordinator');
    }
  }
}
