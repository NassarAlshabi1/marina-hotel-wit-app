import 'package:flutter/foundation.dart';
import '../auto_backup_manager.dart';

abstract class BaseRepository<T, TCompanion> {
  String get tableName;

  @protected
  Future<void> notifyBackup(String operation, Map<String, dynamic> recordData) async {
    try {
      AutoBackupManager.instance.onDataChange(tableName, operation, recordData: recordData);
    } catch (e) {
      debugPrint('⚠️ [$tableName] فشل إشعار النسخ الاحتياطي: $e');
    }
  }

  @protected
  Future<R> safeExecute<R>(Future<R> Function() operation, {
    String? operationName,
    R? fallbackValue,
  }) async {
    try {
      return await operation();
    } catch (e, stack) {
      debugPrint('❌ [$tableName] ${operationName ?? 'عملية'} فشلت: $e');
      if (fallbackValue != null) return fallbackValue;
      rethrow;
    }
  }
}
