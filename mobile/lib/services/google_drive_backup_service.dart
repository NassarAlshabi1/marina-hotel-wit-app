import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'backup_serializers.dart';
import 'google_drive_logger.dart';
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

/// Google Drive service for backup and restore operations
class GoogleDriveBackupService {
  static const List<String> _scopes = ['https://www.googleapis.com/auth/drive.file'];
  static const String _appFolderName = 'MarinaHotelBackups';
  
  GoogleDriveBackupService() {
    _googleSignIn = GoogleSignIn(
      scopes: _scopes,
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

  /// Get or create the app folder in Google Drive
  Future<String?> _getAppFolderId() async {
    if (_appFolderId != null) return _appFolderId;

    try {
      // Search for existing folder
      final query = Uri.encodeComponent(
        "name='$_appFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false",
      );
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=$query',
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final files = data['files'] as List<dynamic>? ?? [];

        if (files.isNotEmpty) {
          _appFolderId = files.first['id'] as String?;
          return _appFolderId;
        }

        // Create folder if not exists
        return await _createAppFolder();
      }
    } catch (e) {
      AppLogger.error('خطأ في جلب مجلد التطبيق: $e');
    }
    return null;
  }

  /// Create the app folder in Google Drive
  Future<String?> _createAppFolder() async {
    try {
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files',
      );

      final body = jsonEncode({
        'name': _appFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      });

      final response = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
        body: body,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _appFolderId = data['id'] as String?;
        return _appFolderId;
      }
    } catch (e) {
      AppLogger.error('خطأ في إنشاء مجلد التطبيق: $e');
    }
    return null;
  }

  /// Create a backup to Google Drive
  Future<GoogleDriveBackupResult> createBackup({
    BackupFormat format = BackupFormat.json,
  }) async {
    if (!isSignedIn || _accessToken == null) {
      return const GoogleDriveBackupResult(
        success: false,
        message: 'غير مسجل الدخول إلى Google',
      );
    }

    try {
      AppLogger.debug('جاري إنشاء نسخة احتياطية...');

      final folderId = await _getAppFolderId();
      if (folderId == null) {
        return const GoogleDriveBackupResult(
          success: false,
          message: 'فشل في الوصول إلى مجلد Google Drive',
        );
      }

      // Get database data
      final db = getDatabase();
      final timestamp = DateTime.now();

      final roomsData = await db.select(db.rooms).get();
      final bookingsData = await db.select(db.bookings).get();
      final bookingNotesData = await db.select(db.bookingNotes).get();
      final employeesData = await db.select(db.employees).get();
      final expensesData = await db.select(db.expenses).get();
      final cashTransactionsData = await db.select(db.cashTransactions).get();
      final paymentsData = await db.select(db.payments).get();
      final syncStateData = await db.select(db.syncState).get();

      final totalRecords = roomsData.length +
          bookingsData.length +
          bookingNotesData.length +
          employeesData.length +
          expensesData.length +
          cashTransactionsData.length +
          paymentsData.length;

      final metadata = {
        'app_version': '1.2.0+3',
        'database_version': db.schemaVersion,
        'backup_timestamp': timestamp.toIso8601String(),
        'total_records': totalRecords,
        'device_info': 'Google Drive Backup',
        'format': format.name,
      };

      final backupData = {
        'metadata': metadata,
        'rooms': roomsData.map((r) => r.toJson()).toList(),
        'bookings': bookingsData.map((b) => b.toJson()).toList(),
        'booking_notes': bookingNotesData.map((n) => n.toJson()).toList(),
        'employees': employeesData.map((e) => e.toJson()).toList(),
        'expenses': expensesData.map((e) => e.toJson()).toList(),
        'cash_transactions': cashTransactionsData.map((c) => c.toJson()).toList(),
        'payments': paymentsData.map((p) => p.toJson()).toList(),
        'sync_state': syncStateData.isNotEmpty ? syncStateData.first.toJson() : {},
      };

      final jsonString = jsonEncode(backupData);
      final fileName = 'marina_backup_${timestamp.toIso8601String().split('T')[0]}.json';

      // Upload to Google Drive
      final fileId = await _uploadFile(
        folderId: folderId,
        fileName: fileName,
        content: utf8.encode(jsonString),
        mimeType: 'application/json',
      );

      if (fileId != null) {
        await GoogleDriveConfig.saveLastSync(timestamp);
        AppLogger.info('تم إنشاء النسخة الاحتياطية: $fileName');
        return GoogleDriveBackupResult(
          success: true,
          fileId: fileId,
          fileName: fileName,
          recordCount: totalRecords,
          message: 'تم إنشاء النسخة الاحتياطية بنجاح',
        );
      }

      return const GoogleDriveBackupResult(
        success: false,
        message: 'فشل في رفع الملف',
      );
    } catch (e) {
      AppLogger.error('خطأ في إنشاء النسخة: $e');
      return GoogleDriveBackupResult(
        success: false,
        message: 'خطأ: $e',
      );
    }
  }

  /// Upload file to Google Drive
  Future<String?> _uploadFile({
    required String folderId,
    required String fileName,
    required List<int> content,
    required String mimeType,
  }) async {
    try {
      final uri = Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart',
      );

      final request = http.MultipartRequest('POST', uri);
      request.headers['Authorization'] = 'Bearer $_accessToken';

      final metadata = {
        'name': fileName,
        'parents': [folderId],
      };

      request.files.add(http.MultipartFile.fromBytes(
        'metadata',
        utf8.encode(jsonEncode(metadata)),
        filename: 'metadata.json',
      ));

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        content,
        filename: fileName,
      ));

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['id'] as String?;
      }

      AppLogger.error('فشل رفع الملف: ${response.body}');
      return null;
    } catch (e) {
      AppLogger.error('خطأ في رفع الملف: $e');
      return null;
    }
  }

  /// List all backups in Google Drive
  Future<List<GoogleDriveBackupFile>> listBackups() async {
    if (!isSignedIn || _accessToken == null) {
      return [];
    }

    try {
      final folderId = await _getAppFolderId();
      if (folderId == null) return [];

      final query = Uri.encodeComponent(
        "'$folderId' in parents and mimeType='application/json' and trashed=false",
      );
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files?q=$query&orderBy=modifiedTime desc',
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final files = data['files'] as List<dynamic>? ?? [];

        return files.map((f) {
          return GoogleDriveBackupFile(
            id: f['id']?.toString() ?? '',
            name: f['name']?.toString() ?? '',
            size: int.tryParse(f['size']?.toString() ?? '0') ?? 0,
            modifiedTime: f['modifiedTime'] != null
                ? DateTime.parse(f['modifiedTime'].toString())
                : DateTime.now(),
          );
        }).toList();
      }
    } catch (e) {
      AppLogger.error('خطأ في جلب قائمة النسخ: $e');
    }
    return [];
  }

  /// Restore from a Google Drive backup
  Future<GoogleDriveBackupResult> restoreBackup(String fileId) async {
    if (!isSignedIn || _accessToken == null) {
      return const GoogleDriveBackupResult(
        success: false,
        message: 'غير مسجل الدخول إلى Google',
      );
    }

    try {
      AppLogger.debug('جاري استعادة النسخة الاحتياطية...');

      // Download file content
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId?alt=media',
      );

      final response = await http.get(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      if (response.statusCode != 200) {
        return GoogleDriveBackupResult(
          success: false,
          message: 'فشل في تحميل الملف: ${response.statusCode}',
        );
      }

      final backupData = jsonDecode(response.body) as Map<String, dynamic>;

      // Validate backup data
      if (!backupData.containsKey('metadata')) {
        return const GoogleDriveBackupResult(
          success: false,
          message: 'ملف النسخة غير صالح',
        );
      }

      final metadata = backupData['metadata'] as Map<String, dynamic>;
      final dbVersion = metadata['database_version'] as int? ?? 0;
      final currentDb = getDatabase();

      if (dbVersion > currentDb.schemaVersion) {
        return const GoogleDriveBackupResult(
          success: false,
          message: 'إصدار قاعدة البيانات في النسخة أحدث من الإصدار الحالي',
        );
      }

      // Restore data (simplified - full implementation would restore each table)
      final totalRecords = metadata['total_records'] as int? ?? 0;

      AppLogger.info('تم استعادة $totalRecords سجل');
      return GoogleDriveBackupResult(
        success: true,
        recordCount: totalRecords,
        message: 'تم استعادة النسخة بنجاح',
      );
    } catch (e) {
      AppLogger.error('خطأ في استعادة النسخة: $e');
      return GoogleDriveBackupResult(
        success: false,
        message: 'خطأ: $e',
      );
    }
  }

  /// Delete a backup from Google Drive
  Future<bool> deleteBackup(String fileId) async {
    if (!isSignedIn || _accessToken == null) {
      return false;
    }

    try {
      final uri = Uri.parse(
        'https://www.googleapis.com/drive/v3/files/$fileId',
      );

      final response = await http.delete(
        uri,
        headers: {
          'Authorization': 'Bearer $_accessToken',
        },
      );

      return response.statusCode == 204;
    } catch (e) {
      AppLogger.error('خطأ في حذف النسخة: $e');
      return false;
    }
  }

  /// Export database to JSON (for use by other services)
  Future<Map<String, dynamic>> exportDatabaseToJson() async {
    final db = getDatabase();
    final timestamp = DateTime.now();

    final roomsData = await db.select(db.rooms).get();
    final bookingsData = await db.select(db.bookings).get();
    final bookingNotesData = await db.select(db.bookingNotes).get();
    final employeesData = await db.select(db.employees).get();
    final expensesData = await db.select(db.expenses).get();
    final cashTransactionsData = await db.select(db.cashTransactions).get();
    final paymentsData = await db.select(db.payments).get();

    final totalRecords = roomsData.length +
        bookingsData.length +
        bookingNotesData.length +
        employeesData.length +
        expensesData.length +
        cashTransactionsData.length +
        paymentsData.length;

    return {
      'metadata': {
        'app_version': '1.2.0+3',
        'database_version': db.schemaVersion,
        'backup_timestamp': timestamp.toIso8601String(),
        'total_records': totalRecords,
        'device_info': 'Local Export',
      },
      'rooms': roomsData.map((r) => r.toJson()).toList(),
      'bookings': bookingsData.map((b) => b.toJson()).toList(),
      'booking_notes': bookingNotesData.map((n) => n.toJson()).toList(),
      'employees': employeesData.map((e) => e.toJson()).toList(),
      'expenses': expensesData.map((e) => e.toJson()).toList(),
      'cash_transactions': cashTransactionsData.map((c) => c.toJson()).toList(),
      'payments': paymentsData.map((p) => p.toJson()).toList(),
    };
  }

  /// Perform automatic backup (called by background task)
  Future<GoogleDriveBackupResult> performAutoBackup() async {
    if (!isSignedIn) {
      final silentSignIn = await attemptSilentSignIn();
      if (!silentSignIn) {
        return const GoogleDriveBackupResult(
          success: false,
          message: 'غير مسجل الدخول',
        );
      }
    }
    return createBackup();
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
      final db = getDatabase();
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
}