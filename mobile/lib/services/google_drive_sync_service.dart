import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import '../utils/app_logger.dart';
import 'google_drive_backup_service.dart';

/// SmartSyncManager - مدير المزامنة الذكية مع Google Drive
/// ⚠️ ملاحظة: Google Drive Sync معطل بالكامل
/// لا يتم استخدام هذا الكلاس anymore - المزامنة تتم عبر Appwrite فقط
class SmartSyncManager {
  static SmartSyncManager? _instance;
  static SmartSyncManager get instance => _instance ??= SmartSyncManager._();

  SmartSyncManager._();

  bool _isInitialized = false;
  String? _deviceId;

  /// معطل - Google Drive Sync معطل
  bool get isDriveSignedIn => false;

  String get deviceId => _deviceId ?? 'disabled_device';

  bool get isInitialized => _isInitialized;

  /// تهيئة SmartSyncManager - معطل بالكامل
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _deviceId = await _getDeviceId();
    _isInitialized = true;

    AppLogger.warning(
      '⚠️ SmartSyncManager initialized (Google Drive DISABLED)',
      tag: 'SMART_SYNC',
    );
  }

  /// معطل
  Future<void> onGoogleDriveSignInChanged(bool signedIn) async {
    AppLogger.debug(
      'onGoogleDriveSignInChanged called but DISABLED',
      tag: 'SMART_SYNC',
    );
  }

  /// معطل
  Future<List<GoogleDriveBackupFile>> listBackupFiles() async {
    AppLogger.debug('listBackupFiles called but DISABLED', tag: 'SMART_SYNC');
    return [];
  }

  /// معطل
  Future<String?> downloadBackup(String fileId, String destinationPath) async {
    AppLogger.debug('downloadBackup called but DISABLED', tag: 'SMART_SYNC');
    return null;
  }

  /// معطل
  Future<bool> restoreFromBackup(String fileId) async {
    AppLogger.debug('restoreFromBackup called but DISABLED', tag: 'SMART_SYNC');
    return false;
  }

  /// معطل
  Future<void> pushLocalChanges() async {
    AppLogger.debug('pushLocalChanges called but DISABLED', tag: 'SMART_SYNC');
  }

  /// معطل
  Future<Map<String, dynamic>> getStatus() async {
    return {
      'enabled': false,
      'message': 'Google Drive Sync DISABLED',
      'isSignedIn': false,
    };
  }

  /// معطل
  static Future<void> disposeInstance() async {
    AppLogger.debug('disposeInstance called but DISABLED', tag: 'SMART_SYNC');
  }

  /// الحصول على معرف الجهاز
  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString('smart_sync_device_id');
    if (existing != null) return existing;

    final id = 'marina_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
    await prefs.setString('smart_sync_device_id', id);
    return id;
  }
}