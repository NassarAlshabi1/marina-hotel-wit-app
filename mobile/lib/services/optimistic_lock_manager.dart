import 'package:drift/drift.dart' as d;
import 'package:flutter/foundation.dart';

import 'local_db.dart';
import 'sync_constants.dart';

class OptimisticLockException implements Exception {
  OptimisticLockException(
    this.message, {
    this.currentVersion,
    this.expectedVersion,
  });

  final String message;
  final int? currentVersion;
  final int? expectedVersion;

  @override
  String toString() =>
      'OptimisticLockException: $message (expected: $expectedVersion, current: $currentVersion)';
}

/// مدير Optimistic Locking - يمنع التعديلات المتزامنة على نفس الصف
class OptimisticLockManager {
  OptimisticLockManager(this.db);

  final AppDatabase db;

  /// التحقق وزيادة الإصدار قبل التحديث
  Future<int> checkAndIncrementVersion({
    required String table,
    required String uuid,
    required int expectedVersion,
  }) async {
    final currentVersion = await _getCurrentVersion(table, uuid);

    if (currentVersion == null) {
      throw OptimisticLockException(
        'السجل غير موجود',
        expectedVersion: expectedVersion,
      );
    }

    if (currentVersion != expectedVersion) {
      throw OptimisticLockException(
        'تعارض في الإصدار - تم تعديل السجل من جهاز آخر',
        currentVersion: currentVersion,
        expectedVersion: expectedVersion,
      );
    }

    final newVersion = currentVersion + 1;
    await _updateVersion(table, uuid, newVersion);

    return newVersion;
  }

  /// الحصول على الإصدار الحالي لصف
  Future<int?> _getCurrentVersion(String table, String uuid) async {
    // ✅ SECURITY: استخدام القائمة البيضاء الموحدة من SyncConstants
    if (!SyncConstants.sqlAllowedTables.contains(table)) {
      throw ArgumentError('جدول غير مسموح: $table');
    }

    try {
      final result = await db
          .customSelect(
            'SELECT version FROM $table WHERE local_uuid = ?',
            variables: [d.Variable.withString(uuid)],
          )
          .getSingleOrNull();

      return result?.read<int?>('version');
    } catch (e) {
      debugPrint('❌ خطأ في قراءة الإصدار: $e');
      return null;
    }
  }

  /// تحديث الإصدار
  Future<void> _updateVersion(String table, String uuid, int newVersion) async {
    try {
      await db.customUpdate(
        'UPDATE $table SET version = ?, last_modified = ?, last_modified_epoch = ? WHERE local_uuid = ?',
        variables: [
          d.Variable.withInt(newVersion),
          d.Variable.withInt(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          d.Variable.withInt(DateTime.now().millisecondsSinceEpoch ~/ 1000),
          d.Variable.withString(uuid),
        ],
      );
    } catch (e) {
      debugPrint('❌ خطأ في تحديث الإصدار: $e');
      rethrow;
    }
  }

  /// تنفيذ تحديث مع حماية optimistic locking
  Future<T> executeWithLock<T>({
    required String table,
    required String uuid,
    required int expectedVersion,
    required Future<T> Function(int newVersion) operation,
  }) async {
    final newVersion = await checkAndIncrementVersion(
      table: table,
      uuid: uuid,
      expectedVersion: expectedVersion,
    );

    try {
      return await operation(newVersion);
    } catch (e) {
      try {
        await db.customUpdate(
          'UPDATE $table SET version = ? WHERE local_uuid = ? AND version = ?',
          variables: [
            d.Variable.withInt(expectedVersion),
            d.Variable.withString(uuid),
            d.Variable.withInt(newVersion),
          ],
        );
      } catch (e) {
        debugPrint('⚠️ Version rollback failed after optimistic lock conflict: $e');
      }
      rethrow;
    }
  }
}
