import 'package:synchronized/synchronized.dart';

class SyncLocks {
  SyncLocks._();

  static final mainSyncLock = Lock();

  static final deltaSyncLock = Lock();

  static final autoEngineLock = Lock();

  static final queueLock = Lock();

  static final smartSyncLock = Lock();

  static final baseSyncLock = Lock();

  static final schedulerLock = Lock();

  static final appwriteSyncLock = Lock();

  static final screenSyncLock = Lock();
}
