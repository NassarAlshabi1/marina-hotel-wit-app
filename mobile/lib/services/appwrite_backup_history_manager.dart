import 'dart:convert';

import 'package:marina_hotel_mobile/utils/app_logger.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';
import 'package:uuid/uuid.dart';

import 'appwrite_backup_operation_log.dart';

/// مدير سجل عمليات النقاط الاحتياطية
class BackupHistoryManager {
  static const String _storageKey = 'backup_operation_logs';
  static const int _maxLogs = 100;

  static Future<List<BackupOperationLog>> loadLogs() async {
    final prefs = getSharedPrefs();
    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return [];

    try {
      final jsonList = jsonDecode(jsonStr) as List<dynamic>;
      return jsonList
          .map((e) => BackupOperationLog.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      AppLogger.error('❌ Failed to load backup history: $e');
      return [];
    }
  }

  static Future<void> addLog(BackupOperationLog log) async {
    final logs = await loadLogs();
    logs.insert(0, log);

    // Maintain max size
    while (logs.length > _maxLogs) {
      logs.removeLast();
    }

    await _saveLogs(logs);
  }

  static Future<void> clearLogs() async {
    final prefs = getSharedPrefs();
    await prefs.remove(_storageKey);
  }

  static Future<List<BackupOperationLog>> loadLogsForEndpoint(
      String endpointId) async {
    final logs = await loadLogs();
    return logs.where((l) => l.endpointId == endpointId).toList();
  }

  static Future<void> _saveLogs(List<BackupOperationLog> logs) async {
    final prefs = getSharedPrefs();
    final jsonList = logs.map((l) => l.toJson()).toList();
    await prefs.setString(_storageKey, jsonEncode(jsonList));
  }

  static String generateId() => const Uuid().v4();
}
