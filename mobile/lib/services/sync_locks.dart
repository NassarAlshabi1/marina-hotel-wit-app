import 'package:synchronized/synchronized.dart';

/// أقفال المزامنة الفعالة — تم إزالة الأقفال الميتة (baseSyncLock, schedulerLock, queueLock)
class SyncLocks {
  SyncLocks._();

  static final mainSyncLock = Lock();

  /// يشغّل المزامنة أو صيانة قاعدة البيانات تحت قفل العملية المشترك.
  /// الاستعادة تستخدمه أيضاً كي لا تتداخل مع push/pull.
  static Future<T> runMain<T>(Future<T> Function() action) =>
      mainSyncLock.synchronized(action);

  static final deltaSyncLock = Lock();
  static final autoEngineLock = Lock();
  static final smartSyncLock = Lock();
  static final appwriteSyncLock = Lock();
  static final screenSyncLock = Lock();
}
