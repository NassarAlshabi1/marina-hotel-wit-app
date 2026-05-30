import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';

import '../utils/app_logger.dart';
import 'google_drive_backup_service.dart';

/// SmartSyncManager - مدير المزامنة الذكية مع Google Drive
/// ⚠️ ملاحظة: Google Drive Sync معطل حالياً
class SmartSyncManager {
  static SmartSyncManager? _instance;
  static SmartSyncManager get instance => _instance ??= SmartSyncManager._();

  SmartSyncManager._();

  bool _isInitialized = false;
  GoogleDriveBackupService? _backupService;
  String? _deviceId;

  String get deviceId => _deviceId ?? 'disabled_device';

  bool get isInitialized => _isInitialized;

  /// تهيئة SmartSyncManager - معطل حالياً
  Future<void> initialize(GoogleDriveBackupService backupService) async {
    _backupService = backupService;
    _deviceId = await _getDeviceId();
    _isInitialized = true;

    AppLogger.info(
      '⚠️ SmartSyncManager initialized (Google Drive Sync DISABLED)',
      tag: 'SMART_SYNC',
    );
  }

  /// معطل - لن يتم استدعاءه
  Future<void> onGoogleDriveSignInChanged(bool signedIn) async {
    AppLogger.debug(
      'Google Drive sign-in changed (DISABLED): $signedIn',
      tag: 'SMART_SYNC',
    );
  }

  /// معطل
  Future<List<GoogleDriveBackupFile>> listBackupFiles() async {
    return [];
  }

  /// معطل
  Future<String?> downloadBackup(String fileId, String destinationPath) async {
    return null;
  }

  /// معطل
  Future<bool> restoreFromBackup(String fileId) async {
    return false;
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