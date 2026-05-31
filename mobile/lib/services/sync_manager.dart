// ignore_for_file: unused_element, unused_import

import 'dart:async';

import '../utils/app_logger.dart';

/// SyncManager - مدير المزامنة الرئيسي
/// ⚠️ ملاحظة: Google Drive Sync معطل حالياً
/// المزامنة تعمل فقط عبر Appwrite
class SyncManager {
  static SyncManager? _instance;

  static SyncManager get instance {
    final instance = _instance;
    if (instance == null) {
      throw StateError('SyncManager singleton is not configured');
    }
    return instance;
  }

  static void configureSingleton(SyncManager manager) {
    _instance ??= manager;
  }

  bool _isInitialized = false;

  /// تهيئة الخدمة - معطل Google Drive Sync
  Future<void> initSyncService({
    bool enableEncryption = false,
    String? encryptionKey,
    bool allowInteractiveSignIn = true,
  }) async {
    if (_isInitialized) return;

    AppLogger.info(
      '⚠️ SyncManager initialized (Google Drive Sync DISABLED)',
      tag: 'SYNC_MANAGER',
    );

    _isInitialized = true;
  }

  /// مزامنة - معطلة مؤقتاً
  Future<void> smartSync({bool force = false}) async {
    AppLogger.debug(
      'smartSync called (DISABLED - Use Appwrite Sync instead)',
      tag: 'SYNC_MANAGER',
    );
  }

  /// مزامنة كاملة - معطلة
  Future<void> syncAllTables({bool force = false}) async {
    AppLogger.debug(
      'syncAllTables called (DISABLED - Use Appwrite Sync instead)',
      tag: 'SYNC_MANAGER',
    );
  }

  Future<void> dispose() async {}
}

/// واجهة اختيارية - معطلة
abstract class SyncTriggerDispatcher {
  Future<void> sendTrigger({required String syncId, required String sourceDeviceId});
}