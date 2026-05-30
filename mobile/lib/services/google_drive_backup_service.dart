import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'backup_serializers.dart';
import 'local_db.dart';

export 'backup_serializers.dart' show BackupFormat, BackupMetadata;
export 'google_drive_backup_service.dart' show GoogleDriveBackupFile, DriveBackupFile;

/// Google Drive API configuration
class GoogleDriveConfig {
  static const String _clientIdKey = 'google_drive_client_id';
  static const String _isConnectedKey = 'google_drive_connected';
  static const String _lastSyncKey = 'google_drive_last_sync';

  static const String _scopes = 'https://www.googleapis.com/auth/drive.file';
  static const String _appFolderName = 'MarinaHotelBackups';

  static Future<void> saveClientId(String clientId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_clientIdKey, clientId);
  }

  static Future<String?> getClientId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_clientIdKey);
  }

  static Future<void> setConnected(bool connected) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isConnectedKey, connected);
  }

  static Future<bool> isConnected() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isConnectedKey) ?? false;
  }

  static Future<void> saveLastSync(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, time.toIso8601String());
  }

  static Future<DateTime?> getLastSync() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString(_lastSyncKey);
    return str != null ? DateTime.parse(str) : null;
  }
}

/// Google Drive backup file info
class GoogleDriveBackupFile {
  const GoogleDriveBackupFile({
    required this.id,
    required this.name,
    required this.size,
    required this.modifiedTime,
    this.appProperties,
    this.createdTime,
  });

  final String id;
  final String name;
  final int size;
  final DateTime modifiedTime;
  final Map<String, dynamic>? appProperties;
  final DateTime? createdTime;
  
  /// Alias for id (for compatibility)
  String get fileId => id;
}

/// Alias for backward compatibility
typedef DriveBackupFile = GoogleDriveBackupFile;

/// Result of a Google Drive backup operation
class GoogleDriveBackupResult {
  const GoogleDriveBackupResult({
    required this.success,
    this.fileId,
    this.fileName,
    this.recordCount,
    this.message,
  });

  final bool success;
  final String? fileId;
  final String? fileName;
  final int? recordCount;
  final String? message;
}

/// ⚠️ Google Drive Sync DISABLED
/// Login (signIn/signOut) still works for authentication, but ALL
/// sync/backup/restore/upload/download operations return immediately
/// with a "disabled" result. No data is transferred to/from Google Drive.
class GoogleDriveBackupService {
  GoogleDriveBackupService() {
    _googleSignIn = GoogleSignIn(
      scopes: [GoogleDriveConfig._scopes],
      // Force server-side auth for better session persistence
      signInOption: SignInOption.games,
    );
  }

  late final GoogleSignIn _googleSignIn;
  String? _accessToken;
  String? _refreshToken;
  String? _appFolderId;
  DateTime? _tokenExpiry;

  bool get isSignedIn => _googleSignIn.currentUser != null;
  
  /// Get current signed in account (or attempt silent sign in)
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;
  
  /// Get the backup folder name for this device
  String get fullBackupPrefix => 'MarinaHotelBackup_${DateTime.now().year}';

  /// Initialize service and try to restore session silently
  Future<bool> initialize() async {
    // Try silent sign-in on app start
    return await attemptSilentSignIn();
  }

  /// Initialize Google Sign-In with interactive login
  Future<bool> signIn() async {
    try {
      AppLogger.debug('جاري تسجيل الدخول إلى Google...');
      final account = await _googleSignIn.signIn();
      if (account != null) {
        final auth = await account.authentication;
        _accessToken = auth.accessToken;
        _refreshToken = auth.idToken; // Store for session persistence
        
        // Save session data
        await _saveSession(account);
        
        AppLogger.info('تم تسجيل الدخول بنجاح');
        await GoogleDriveConfig.setConnected(true);
        return true;
      }
      return false;
    } catch (e) {
      AppLogger.error('خطأ في تسجيل الدخول: $e');
      return false;
    }
  }

  /// Sign out from Google and clear session
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      _accessToken = null;
      _refreshToken = null;
      _appFolderId = null;
      _tokenExpiry = null;
      
      // Clear saved session
      await _clearSession();
      
      await GoogleDriveConfig.setConnected(false);
      AppLogger.info('تم تسجيل الخروج');
    } catch (e) {
      AppLogger.error('خطأ في تسجيل الخروج: $e');
    }
  }

  /// Attempt silent sign-in (for auto-backup and session restore)
  Future<bool> attemptSilentSignIn() async {
    try {
      AppLogger.debug('محاولة استعادة الجلسة...');
      
      // First check if already signed in
      final isSignedIn = await _googleSignIn.isSignedIn();
      
      if (isSignedIn) {
        AppLogger.info('المستخدم مسجل دخول مسبقاً');
        final account = await _googleSignIn.signInSilently();
        if (account != null) {
          await _refreshAccessToken(account);
          await GoogleDriveConfig.setConnected(true);
          return true;
        }
      }
      
      AppLogger.warning('لا توجد جلسة سابقة');
      return false;
    } catch (e) {
      AppLogger.warning('فشل تسجيل الدخول التلقائي: $e');
      return false;
    }
  }

  /// Refresh access token
  Future<bool> _refreshAccessToken(GoogleSignInAccount account) async {
    try {
      final auth = await account.authentication;
      _accessToken = auth.accessToken;
      _refreshToken = auth.idToken;
      
      // Token typically expires in 1 hour
      _tokenExpiry = DateTime.now().add(const Duration(hours: 1));
      
      await _saveSession(account);
      AppLogger.info('تم تحديث الـ token');
      return true;
    } catch (e) {
      AppLogger.error('فشل تحديث الـ token: $e');
      return false;
    }
  }

  /// Save session to SharedPreferences
  Future<void> _saveSession(GoogleSignInAccount account) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('gdrive_user_email', account.email);
      await prefs.setString('gdrive_user_id', account.id);
      await prefs.setString('gdrive_user_display_name', account.displayName ?? '');
      await prefs.setString('gdrive_session_time', DateTime.now().toIso8601String());
      AppLogger.info('تم حفظ الجلسة');
    } catch (e) {
      AppLogger.error('خطأ في حفظ الجلسة: $e');
    }
  }

  /// Clear saved session
  Future<void> _clearSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('gdrive_user_email');
      await prefs.remove('gdrive_user_id');
      await prefs.remove('gdrive_user_display_name');
      await prefs.remove('gdrive_session_time');
      await prefs.remove('gdrive_access_token');
      AppLogger.info('تم مسح الجلسة المحفوظة');
    } catch (e) {
      AppLogger.error('خطأ في مسح الجلسة: $e');
    }
  }

  /// Get saved user info
  Future<Map<String, String?>> getSavedUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return {
        'email': prefs.getString('gdrive_user_email'),
        'id': prefs.getString('gdrive_user_id'),
        'displayName': prefs.getString('gdrive_user_display_name'),
        'sessionTime': prefs.getString('gdrive_session_time'),
      };
    } catch (e) {
      return {};
    }
  }

  /// Check if session is still valid
  Future<bool> isSessionValid() async {
    if (_tokenExpiry != null && DateTime.now().isAfter(_tokenExpiry!)) {
      return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    final sessionTime = prefs.getString('gdrive_session_time');
    
    if (sessionTime != null) {
      final lastSession = DateTime.parse(sessionTime);
      // Session valid for 360 days
      return DateTime.now().difference(lastSession).inDays < 360;
    }
    
    return false;
  }

  // ────────────────────────────────────────────────────────────
  // ⚠️ ALL SYNC/BACKUP/RESTORE OPERATIONS ARE DISABLED BELOW
  // Login still works, but NO data is transferred to/from Google Drive.
  // ────────────────────────────────────────────────────────────

  /// Create a backup to Google Drive — DISABLED
  Future<GoogleDriveBackupResult> createBackup({
    BackupFormat format = BackupFormat.json,
  }) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل إنشاء نسخة احتياطية');
    return const GoogleDriveBackupResult(
      success: false,
      message: 'مزامنة Google Drive معطلة',
    );
  }

  /// List all backups in Google Drive — DISABLED
  Future<List<GoogleDriveBackupFile>> listBackups() async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل جلب قائمة النسخ');
    return [];
  }

  /// Restore from a Google Drive backup — DISABLED
  Future<GoogleDriveBackupResult> restoreBackup(String fileId) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل استعادة النسخة');
    return const GoogleDriveBackupResult(
      success: false,
      message: 'مزامنة Google Drive معطلة',
    );
  }

  /// Delete a backup from Google Drive — DISABLED
  Future<bool> deleteBackup(String fileId) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل حذف النسخة');
    return false;
  }

  /// Export database to JSON (for use by other services) — DISABLED
  Future<Map<String, dynamic>> exportDatabaseToJson() async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل تصدير قاعدة البيانات');
    return {};
  }

  /// Perform automatic backup (called by background task) — DISABLED
  Future<GoogleDriveBackupResult> performAutoBackup() async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل النسخ التلقائي');
    return const GoogleDriveBackupResult(
      success: false,
      message: 'مزامنة Google Drive معطلة',
    );
  }

  /// Get last backup time
  Future<DateTime?> getLastBackupTime() async {
    return GoogleDriveConfig.getLastSync();
  }

  /// Check if auto backup is enabled
  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('google_drive_auto_backup_enabled') ?? false;
  }

  /// Set auto backup enabled
  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('google_drive_auto_backup_enabled', enabled);
  }

  /// Get auto backup frequency
  Future<String> getAutoBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('google_drive_auto_backup_frequency') ?? 'daily';
  }

  /// Set auto backup frequency
  Future<void> setAutoBackupFrequency(String frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_drive_auto_backup_frequency', frequency);
  }

  /// Get auto backup time
  Future<String> getAutoBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('google_drive_auto_backup_time') ?? '02:00';
  }

  /// Set auto backup time
  Future<void> setAutoBackupTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('google_drive_auto_backup_time', time);
  }

  /// Estimate database size
  Future<int> estimateDatabaseSize() async {
    try {
      final db = DatabaseManager.instance;
      int totalSize = 0;

      // Get size from each table
      final tables = ['rooms', 'bookings', 'employees', 'expenses',
                     'payments', 'cash_transactions', 'debts'];

      for (final table in tables) {
        try {
          final result = await db.customSelect(
            'SELECT COUNT(*) as count FROM $table',
          ).getSingle();
          final count = result.data['count'] as int? ?? 0;
          // Rough estimate: ~500 bytes per record
          totalSize += count * 500;
        } catch (_) {
          // Table might not exist
        }
      }

      return totalSize;
    } catch (e) {
      debugPrint('خطأ في تقدير حجم قاعدة البيانات: $e');
      return 0;
    }
  }

  // ─── Compatibility methods (aliases for callers that use different names) ───

  /// Alias for [attemptSilentSignIn] — used by alarm_backup.dart
  Future<bool> signInSilentlyIfNeeded() => attemptSilentSignIn();

  /// Alias for [signIn] — used by backup_provider.dart
  Future<GoogleSignInAccount?> signInForDrive() async {
    final ok = await signIn();
    return ok ? _googleSignIn.currentUser : null;
  }

  /// Alias for [listBackups] — used by backup_provider.dart, auto_backup_manager.dart, smart_sync_manager.dart — DISABLED
  Future<List<GoogleDriveBackupFile>> listBackupFiles() => listBackups();

  /// Upload backup data map to Google Drive and return the file ID — DISABLED
  Future<String?> uploadBackup(Map<String, dynamic> backupData) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل رفع النسخة');
    return null;
  }

  /// Upload backup data with a custom name — DISABLED
  Future<String?> uploadBackupWithName(
    Map<String, dynamic> backupData,
    String fileName,
  ) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل رفع النسخة بالاسم');
    return null;
  }

  /// Download a backup file and return its parsed JSON content — DISABLED
  Future<Map<String, dynamic>> downloadBackup(String fileId) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل تنزيل النسخة');
    throw Exception('مزامنة Google Drive معطلة');
  }

  /// Restore from a backup data map (downloaded JSON) — DISABLED
  Future<bool> restoreFromBackup(Map<String, dynamic> backupData) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل استعادة النسخة');
    return false;
  }

  /// Delete a backup file by its ID — DISABLED
  Future<bool> deleteBackupFile(String fileId) async {
    AppLogger.warning('مزامنة Google Drive معطلة - تم تجاهل حذف النسخة');
    return false;
  }
}
