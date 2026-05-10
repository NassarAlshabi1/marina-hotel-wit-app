import 'package:synchronized/synchronized.dart';

/// أقفال المزامنة الفعالة — تم إزالة الأقفال الميتة (baseSyncLock, schedulerLock, queueLock)
class SyncLocks {
  SyncLocks._();

  static final mainSyncLock = Lock();
  static final deltaSyncLock = Lock();
  static final autoEngineLock = Lock();
  static final smartSyncLock = Lock();
  static final appwriteSyncLock = Lock();
  static final screenSyncLock = Lock();
}
