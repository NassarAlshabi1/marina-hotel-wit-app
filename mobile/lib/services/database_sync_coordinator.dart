import 'dart:developer' as developer;

import 'local_db.dart';

/// Coordinator for managing sync operations lifecycle with database
/// 
/// This class coordinates stopping and restarting sync services
/// when database needs to be closed/reopened (e.g., during restore)
/// 
/// It uses a callback pattern to avoid circular dependencies
class DatabaseSyncCoordinator {
  static bool _initialized = false;
  static final List<Future<void> Function()> _stopCallbacks = [];
  static final List<Future<void> Function()> _restartCallbacks = [];

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

  /// Register a service's stop callback
  static void registerStopCallback(Future<void> Function() callback) {
    _stopCallbacks.add(callback);
    developer.log('📝 Registered stop callback (total: ${_stopCallbacks.length})', name: 'DatabaseSyncCoordinator');
  }

  /// Register a service's restart callback
  static void registerRestartCallback(Future<void> Function() callback) {
    _restartCallbacks.add(callback);
    developer.log('📝 Registered restart callback (total: ${_restartCallbacks.length})', name: 'DatabaseSyncCoordinator');
  }

  /// Stop all sync services
  static Future<void> _stopAllSyncServices() async {
    developer.log('⏸️ Stopping all sync services...', name: 'DatabaseSyncCoordinator');
    
    final errors = <String>[];
    
    for (var i = 0; i < _stopCallbacks.length; i++) {
      try {
        await _stopCallbacks[i]();
        developer.log('  ✓ Stopped service ${i + 1}/${_stopCallbacks.length}', name: 'DatabaseSyncCoordinator');
      } catch (e) {
        errors.add('Service $i: $e');
        developer.log('  ⚠️ Error stopping service $i: $e', name: 'DatabaseSyncCoordinator');
      }
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
    
    for (var i = 0; i < _restartCallbacks.length; i++) {
      try {
        await _restartCallbacks[i]();
        developer.log('  ✓ Restarted service ${i + 1}/${_restartCallbacks.length}', name: 'DatabaseSyncCoordinator');
      } catch (e) {
        errors.add('Service $i: $e');
        developer.log('  ⚠️ Error restarting service $i: $e', name: 'DatabaseSyncCoordinator');
      }
    }
    
    if (errors.isEmpty) {
      developer.log('✅ All sync services restarted successfully', name: 'DatabaseSyncCoordinator');
    } else {
      developer.log('⚠️ Restarted sync services with ${errors.length} errors', name: 'DatabaseSyncCoordinator');
    }
  }
}
