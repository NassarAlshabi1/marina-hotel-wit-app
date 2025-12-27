import 'package:shared_preferences/shared_preferences.dart';

class SyncConfig {
  static const Duration conflictThreshold = Duration(seconds: 30);
  static const Duration snapshotInterval = Duration(minutes: 20);
  static const int defaultDevicePriority = 100;
  static const int maxSilentSignInRetries = 3;
  static const int maxQueueSize = 100;
  static const int defaultSyncIntervalMinutes = 2;
  static const int periodicFullSyncHours = 24;
  static const Duration syncMutexTimeout = Duration(seconds: 5);
  
  static const String _prefsConflictThresholdKey = 'sync_config_conflict_threshold_seconds';
  static const String _prefsSnapshotIntervalKey = 'sync_config_snapshot_interval_minutes';
  static const String _prefsDevicePriorityKey = 'sync_config_device_priority';
  
  static Future<Duration> getAdaptiveConflictThreshold() async {
    final prefs = await SharedPreferences.getInstance();
    final seconds = prefs.getInt(_prefsConflictThresholdKey);
    if (seconds != null && seconds > 0) {
      return Duration(seconds: seconds);
    }
    return conflictThreshold;
  }
  
  static Future<void> setConflictThreshold(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsConflictThresholdKey, duration.inSeconds);
  }
  
  static Future<Duration> getSnapshotInterval() async {
    final prefs = await SharedPreferences.getInstance();
    final minutes = prefs.getInt(_prefsSnapshotIntervalKey);
    if (minutes != null && minutes > 0) {
      return Duration(minutes: minutes);
    }
    return snapshotInterval;
  }
  
  static Future<void> setSnapshotInterval(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsSnapshotIntervalKey, duration.inMinutes);
  }
  
  static Future<int> getDevicePriority() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsDevicePriorityKey) ?? defaultDevicePriority;
  }
  
  static Future<void> setDevicePriority(int priority) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsDevicePriorityKey, priority);
  }
  
  static Future<Map<String, dynamic>> getAllSettings() async {
    return {
      'conflictThreshold': (await getAdaptiveConflictThreshold()).inSeconds,
      'snapshotInterval': (await getSnapshotInterval()).inMinutes,
      'devicePriority': await getDevicePriority(),
      'maxSilentSignInRetries': maxSilentSignInRetries,
      'maxQueueSize': maxQueueSize,
      'defaultSyncIntervalMinutes': defaultSyncIntervalMinutes,
      'periodicFullSyncHours': periodicFullSyncHours,
      'syncMutexTimeout': syncMutexTimeout.inSeconds,
    };
  }
  
  static Future<void> resetToDefaults() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsConflictThresholdKey);
    await prefs.remove(_prefsSnapshotIntervalKey);
    await prefs.remove(_prefsDevicePriorityKey);
  }
}
