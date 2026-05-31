import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
  static const String _lastSyncKey = 'google_drive_last_backup';

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

  static Future<void> saveLastBackup(DateTime time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSyncKey, time.toIso8601String());
  }

  static Future<DateTime?> getLastBackup() async {
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

/// ⚠️ Google Drive: BACKUP & RESTORE ONLY — NO SYNC
/// Login (signIn/signOut) works for authentication.
/// Backup and restore operations are fully functional.
/// All SYNC operations (auto-sync, delta sync, real-time sync) remain disabled.
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
  // ignore: unused_field
  String? _refreshToken;
  String? _appFolderId;
  DateTime? _tokenExpiry;

  bool get isSignedIn => _googleSignIn.currentUser != null;
  
  /// Get current signed in account (or attempt silent sign in)
  GoogleSignInAccount? get currentUser => _googleSignIn.currentUser;
  
  /// Get the backup folder name for this device
  String get fullBackupPrefix => 'MarinaHotelBackup_${DateTime.now().year}';

  // ────────────────────────────────────────────────────────────
  // AUTHENTICATION (signIn / signOut / session management)
  // ────────────────────────────────────────────────────────────

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

  /// Ensure we have a valid access token, refresh if needed
  Future<bool> _ensureValidToken() async {
    if (_accessToken == null || !_googleSignIn.currentUser!.id.isNotEmpty) {
      final account = _googleSignIn.currentUser;
      if (account == null) return false;
      return await _refreshAccessToken(account);
    }
    
    // Check if token is about to expire (refresh 5 min before expiry)
    if (_tokenExpiry != null && 
        DateTime.now().isAfter(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      final account = _googleSignIn.currentUser;
      if (account == null) return false;
      return await _refreshAccessToken(account);
    }
    
    return true;
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
  // GOOGLE DRIVE API HELPERS
  // ────────────────────────────────────────────────────────────

  static const String _driveApiBase = 'https://www.googleapis.com/drive/v3';
  static const String _driveUploadBase = 'https://www.googleapis.com/upload/drive/v3';

  /// Get or create the app folder in Google Drive
  Future<String> _getOrCreateAppFolder() async {
    if (_appFolderId != null) return _appFolderId!;

    if (!await _ensureValidToken()) {
      throw Exception('غير مسجل الدخول في Google Drive');
    }

    // Search for existing folder
    final query = "mimeType='application/vnd.google-apps.folder' "
        "and name='${GoogleDriveConfig._appFolderName}' "
        "and trashed=false";

    final response = await http.get(
      Uri.parse('$_driveApiBase/files?q=${Uri.encodeQueryComponent(query)}'
          '&spaces=drive&fields=files(id,name)'),
      headers: {'Authorization': 'Bearer $_accessToken'},
    );

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final files = data['files'] as List<dynamic>;
      
      if (files.isNotEmpty) {
        _appFolderId = files.first['id'] as String;
        return _appFolderId!;
      }
    }

    // Create new folder
    final createResponse = await http.post(
      Uri.parse('$_driveApiBase/files'),
      headers: {
        'Authorization': 'Bearer $_accessToken',
        'Content-Type': 'application/json; charset=utf-8',
      },
      body: jsonEncode({
        'name': GoogleDriveConfig._appFolderName,
        'mimeType': 'application/vnd.google-apps.folder',
      }),
    );

    if (createResponse.statusCode == 200 || createResponse.statusCode == 201) {
      final data = jsonDecode(createResponse.body) as Map<String, dynamic>;
      _appFolderId = data['id'] as String;
      AppLogger.info('تم إنشاء مجلد النسخ الاحتياطي في Google Drive');
      return _appFolderId!;
    }

    throw Exception('فشل إنشاء مجلد النسخ الاحتياطي: ${createResponse.body}');
  }

  // ────────────────────────────────────────────────────────────
  // ✅ BACKUP & RESTORE OPERATIONS (ENABLED)
  // ────────────────────────────────────────────────────────────

  /// Create a backup to Google Drive
  Future<GoogleDriveBackupResult> createBackup({
    BackupFormat format = BackupFormat.json,
  }) async {
    try {
      if (!isSignedIn) {
        return const GoogleDriveBackupResult(
          success: false,
          message: 'يجب تسجيل الدخول أولاً',
        );
      }

      AppLogger.info('بدء إنشاء نسخة احتياطية على Google Drive...');

      final backupData = await _exportDatabaseToJsonInternal();
      final fileName = '${fullBackupPrefix}_${DateTime.now().millisecondsSinceEpoch}.json.gz';
      
      final fileId = await uploadBackupWithName(backupData, fileName);
      
      if (fileId != null) {
        await GoogleDriveConfig.saveLastBackup(DateTime.now());
        final totalRecords = backupData['metadata']?['total_records'] as int? ?? 0;
        
        AppLogger.info('تم إنشاء النسخة الاحتياطية بنجاح على Google Drive ($totalRecords سجل)');
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
        message: 'فشل رفع النسخة الاحتياطية',
      );
    } catch (e) {
      AppLogger.error('خطأ في إنشاء النسخة الاحتياطية: $e');
      return GoogleDriveBackupResult(
        success: false,
        message: 'خطأ: $e',
      );
    }
  }

  /// List all backups in Google Drive
  Future<List<GoogleDriveBackupFile>> listBackups() async {
    try {
      if (!isSignedIn) return [];
      if (!await _ensureValidToken()) return [];

      final folderId = await _getOrCreateAppFolder();
      
      final query = "'$folderId' in parents "
          "and trashed=false";

      final response = await http.get(
        Uri.parse('$_driveApiBase/files?q=${Uri.encodeQueryComponent(query)}'
            '&spaces=drive'
            '&fields=files(id,name,size,modifiedTime,createdTime,appProperties)'
            '&orderBy=modifiedTime desc'
            '&pageSize=50'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final files = data['files'] as List<dynamic>;
        
        return files.map((file) {
          return GoogleDriveBackupFile(
            id: file['id'] as String,
            name: file['name'] as String,
            size: (file['size'] as dynamic) != null 
                ? int.parse(file['size'].toString()) 
                : 0,
            modifiedTime: DateTime.parse(file['modifiedTime'] as String),
            createdTime: file['createdTime'] != null 
                ? DateTime.parse(file['createdTime'] as String) 
                : null,
            appProperties: file['appProperties'] != null
                ? Map<String, dynamic>.from(file['appProperties'] as Map)
                : null,
          );
        }).toList();
      }

      AppLogger.warning('فشل جلب قائمة النسخ: ${response.statusCode}');
      return [];
    } catch (e) {
      AppLogger.error('خطأ في جلب قائمة النسخ الاحتياطية: $e');
      return [];
    }
  }

  /// Restore from a Google Drive backup by fileId
  Future<GoogleDriveBackupResult> restoreBackup(String fileId) async {
    try {
      if (!isSignedIn) {
        return const GoogleDriveBackupResult(
          success: false,
          message: 'يجب تسجيل الدخول أولاً',
        );
      }

      final backupData = await downloadBackup(fileId);
      final restored = await restoreFromBackup(backupData);

      if (restored) {
        return const GoogleDriveBackupResult(
          success: true,
          message: 'تم استعادة النسخة الاحتياطية بنجاح',
        );
      }

      return const GoogleDriveBackupResult(
        success: false,
        message: 'فشل استعادة النسخة الاحتياطية',
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
    try {
      if (!isSignedIn) return false;
      if (!await _ensureValidToken()) return false;

      final response = await http.delete(
        Uri.parse('$_driveApiBase/files/$fileId'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 204 || response.statusCode == 200) {
        AppLogger.info('تم حذف النسخة الاحتياطية من Google Drive');
        return true;
      }

      AppLogger.warning('فشل حذف النسخة: ${response.statusCode}');
      return false;
    } catch (e) {
      AppLogger.error('خطأ في حذف النسخة الاحتياطية: $e');
      return false;
    }
  }

  /// Export database to JSON (for use by other services)
  Future<Map<String, dynamic>> exportDatabaseToJson() async {
    return await _exportDatabaseToJsonInternal();
  }

  /// Internal method to export database to JSON
  Future<Map<String, dynamic>> _exportDatabaseToJsonInternal() async {
    final db = DatabaseManager.instance;
    final timestamp = DateTime.now();

    final roomsData = await db.select(db.rooms).get();
    final bookingsData = await db.select(db.bookings).get();
    final bookingNotesData = await db.select(db.bookingNotes).get();
    final bookingNightsData = await db.select(db.bookingNights).get();
    final ledgerData = await db.select(db.hotelDayLedger).get();
    final shiftNotesData = await db.select(db.shiftNotes).get();
    final employeesData = await db.select(db.employees).get();
    final expensesData = await db.select(db.expenses).get();
    final cashTransactionsData = await db.select(db.cashTransactions).get();
    final paymentsData = await db.select(db.payments).get();
    final syncStateData = await db.select(db.syncState).get();
    final debtsData = await db.select(db.debts).get();
    final salaryCyclesData = await db.select(db.salaryCycles).get();
    final salaryPaymentsData = await db.select(db.salaryPayments).get();
    final priceAdjustmentsData = await db.select(db.priceAdjustments).get();
    final bookingPriceAdjData = await db.select(db.bookingPriceAdjustments).get();
    final auditLogsData = await db.select(db.auditLogs).get();
    final paymentVoidsData = await db.select(db.paymentVoids).get();
    final guestInfosData = await db.select(db.guestInfos).get();
    final salaryWithdrawalsData = await db.select(db.salaryWithdrawals).get();

    final tableData = BackupTableData(
      roomsData: roomsData,
      bookingsData: bookingsData,
      bookingNotesData: bookingNotesData,
      bookingNightsData: bookingNightsData,
      ledgerData: ledgerData,
      shiftNotesData: shiftNotesData,
      employeesData: employeesData,
      expensesData: expensesData,
      cashTransactionsData: cashTransactionsData,
      paymentsData: paymentsData,
      debtsData: debtsData,
      salaryCyclesData: salaryCyclesData,
      salaryPaymentsData: salaryPaymentsData,
      priceAdjustmentsData: priceAdjustmentsData,
      bookingPriceAdjData: bookingPriceAdjData,
      auditLogsData: auditLogsData,
      paymentVoidsData: paymentVoidsData,
      guestInfosData: guestInfosData,
      salaryWithdrawalsData: salaryWithdrawalsData,
    );

    final totalRecords = tableData.totalRecords;

    final metadata = BackupMetadata(
      appVersion: '1.2.0+3',
      databaseVersion: db.schemaVersion,
      backupTimestamp: timestamp,
      totalRecords: totalRecords,
      deviceInfo: 'Google Drive Backup',
    );

    return tableData.toBackupDataMap(
      metadata: metadata.toJson(),
      syncStateData: syncStateData.isNotEmpty
          ? syncStateData.first.toJson()
          : <String, dynamic>{},
    );
  }

  /// Perform automatic backup (called by background task)
  Future<GoogleDriveBackupResult> performAutoBackup() async {
    try {
      if (!isSignedIn) {
        // Try silent sign-in for auto backup
        final signedIn = await attemptSilentSignIn();
        if (!signedIn) {
          return const GoogleDriveBackupResult(
            success: false,
            message: 'غير مسجل الدخول في Google Drive',
          );
        }
      }

      AppLogger.info('بدء النسخ الاحتياطي التلقائي على Google Drive...');
      return await createBackup();
    } catch (e) {
      AppLogger.error('خطأ في النسخ التلقائي: $e');
      return GoogleDriveBackupResult(
        success: false,
        message: 'خطأ في النسخ التلقائي: $e',
      );
    }
  }

  /// Get last backup time
  Future<DateTime?> getLastBackupTime() async {
    return GoogleDriveConfig.getLastBackup();
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

  /// Alias for [listBackups] — used by backup_provider.dart, auto_backup_manager.dart, smart_sync_manager.dart
  Future<List<GoogleDriveBackupFile>> listBackupFiles() => listBackups();

  /// Upload backup data map to Google Drive and return the file ID
  Future<String?> uploadBackup(Map<String, dynamic> backupData) async {
    final fileName = '${fullBackupPrefix}_${DateTime.now().millisecondsSinceEpoch}.json.gz';
    return uploadBackupWithName(backupData, fileName);
  }

  /// Upload backup data with a custom name — compressed gzip
  Future<String?> uploadBackupWithName(
    Map<String, dynamic> backupData,
    String fileName,
  ) async {
    try {
      if (!isSignedIn) {
        AppLogger.warning('غير مسجل الدخول - لا يمكن رفع النسخة');
        return null;
      }
      if (!await _ensureValidToken()) {
        AppLogger.warning('Token غير صالح - لا يمكن رفع النسخة');
        return null;
      }

      final folderId = await _getOrCreateAppFolder();

      // Compress JSON to gzip
      final jsonBytes = utf8.encode(jsonEncode(backupData));
      final compressedBytes = GZipCodec().encode(jsonBytes);

      AppLogger.debug(
        'رفع النسخة: ${(jsonBytes.length / 1024).toStringAsFixed(1)} KB → '
        '${(compressedBytes.length / 1024).toStringAsFixed(1)} KB (gzip)',
      );

      // Use multipart upload
      final boundary = 'marina_boundary_${DateTime.now().millisecondsSinceEpoch}';
      
      // Build multipart body
      final metadataPart = '--$boundary\r\n'
          'Content-Type: application/json; charset=utf-8\r\n\r\n'
          '${jsonEncode({
            'name': fileName,
            'parents': [folderId],
            'appProperties': {
              'type': 'marina_backup',
              'version': '1.2.0',
              'device': Platform.isAndroid ? 'android' : 'ios',
              'records': '${backupData['metadata']?['total_records'] ?? 0}',
            },
          })}\r\n';

      final mediaHeader = '--$boundary\r\n'
          'Content-Type: application/gzip\r\n'
          'Content-Transfer-Encoding: binary\r\n\r\n';
      
      final mediaFooter = '\r\n--$boundary--\r\n';

      final body = <int>[
        ...utf8.encode(metadataPart),
        ...utf8.encode(mediaHeader),
        ...compressedBytes,
        ...utf8.encode(mediaFooter),
      ];

      final response = await http.post(
        Uri.parse('$_driveUploadBase/files?uploadType=multipart'),
        headers: {
          'Authorization': 'Bearer $_accessToken',
          'Content-Type': 'multipart/related; boundary=$boundary',
        },
        body: body,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final fileId = data['id'] as String?;
        AppLogger.info('تم رفع النسخة الاحتياطية بنجاح (ID: $fileId)');
        return fileId;
      }

      AppLogger.error('فشل رفع النسخة: ${response.statusCode} - ${response.body}');
      return null;
    } catch (e) {
      AppLogger.error('خطأ في رفع النسخة الاحتياطية: $e');
      return null;
    }
  }

  /// Download a backup file and return its parsed JSON content
  Future<Map<String, dynamic>> downloadBackup(String fileId) async {
    try {
      if (!isSignedIn) {
        throw Exception('غير مسجل الدخول في Google Drive');
      }
      if (!await _ensureValidToken()) {
        throw Exception('Token غير صالح');
      }

      AppLogger.info('تنزيل النسخة الاحتياطية من Google Drive...');

      final response = await http.get(
        Uri.parse('$_driveApiBase/files/$fileId?alt=media'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final rawBytes = response.bodyBytes;
        
        // Try gzip decompression first
        List<int> decodedBytes;
        if (rawBytes.length >= 2 && rawBytes[0] == 0x1f && rawBytes[1] == 0x8b) {
          decodedBytes = GZipCodec().decode(rawBytes);
          AppLogger.debug(
            'فك ضغط gzip: ${(rawBytes.length / 1024).toStringAsFixed(1)} KB → '
            '${(decodedBytes.length / 1024).toStringAsFixed(1)} KB',
          );
        } else {
          decodedBytes = rawBytes;
        }

        final jsonString = utf8.decode(decodedBytes);
        final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
        
        AppLogger.info('تم تنزيل النسخة الاحتياطية بنجاح');
        return backupData;
      }

      throw Exception('فشل تنزيل النسخة: ${response.statusCode}');
    } catch (e) {
      AppLogger.error('خطأ في تنزيل النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// Restore from a backup data map (downloaded JSON)
  Future<bool> restoreFromBackup(Map<String, dynamic> backupData) async {
    try {
      if (!backupData.containsKey('metadata')) {
        throw Exception('النسخة الاحتياطية لا تحتوي على بيانات وصفية');
      }

      AppLogger.info('بدء استعادة البيانات من Google Drive...');
      final db = DatabaseManager.instance;

      // Disable foreign keys during restore
      await db.customStatement('PRAGMA foreign_keys = OFF');
      try {
        // Delete all tables in correct order (children first)
        await db.delete(db.salaryWithdrawals).go();
        await db.delete(db.paymentVoids).go();
        await db.delete(db.auditLogs).go();
        await db.delete(db.bookingPriceAdjustments).go();
        await db.delete(db.priceAdjustments).go();
        await db.delete(db.salaryPayments).go();
        await db.delete(db.salaryCycles).go();
        await db.delete(db.debts).go();
        await db.delete(db.payments).go();
        await db.delete(db.cashTransactions).go();
        await db.delete(db.expenses).go();
        await db.delete(db.shiftNotes).go();
        await db.delete(db.hotelDayLedger).go();
        await db.delete(db.bookingNights).go();
        await db.delete(db.bookingNotes).go();
        await db.delete(db.bookings).go();
        await db.delete(db.employees).go();
        await db.delete(db.rooms).go();
        await db.delete(db.syncState).go();

        // Helper to insert list of records
        Future<void> insertList<T>(
          String key,
          Future<void> Function(Map<String, dynamic> json) insert,
        ) async {
          if (!backupData.containsKey(key)) return;
          final list = backupData[key] as List<dynamic>;
          for (final json in list) {
            await insert(Map<String, dynamic>.from(json as Map));
          }
        }

        await insertList<dynamic>('rooms', (json) async {
          final data = Room.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.rooms).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('employees', (json) async {
          final data = Employee.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.employees).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('bookings', (json) async {
          final data = Booking.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.bookings).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('booking_notes', (json) async {
          final data = BookingNote.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.bookingNotes).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('booking_nights', (json) async {
          final data = BookingNight.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.bookingNights).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('hotel_day_ledger', (json) async {
          final data = HotelDayLedgerEntry.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.hotelDayLedger).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('shift_notes', (json) async {
          final data = ShiftNote.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.shiftNotes).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('expenses', (json) async {
          final data = Expense.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.expenses).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('cash_transactions', (json) async {
          final data = CashTransaction.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.cashTransactions).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('payments', (json) async {
          final data = Payment.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.payments).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('debts', (json) async {
          final data = Debt.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.debts).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('salary_cycles', (json) async {
          final data = SalaryCycle.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.salaryCycles).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('salary_payments', (json) async {
          final data = SalaryPayment.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.salaryPayments).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('price_adjustments', (json) async {
          final data = PriceAdjustment.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.priceAdjustments).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('booking_price_adjustments', (json) async {
          final data = BookingPriceAdjustment.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.bookingPriceAdjustments).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('audit_logs', (json) async {
          final data = AuditLog.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.auditLogs).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('payment_voids', (json) async {
          final data = PaymentVoid.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.paymentVoids).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('guest_infos', (json) async {
          final data = GuestInfo.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.guestInfos).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('salary_withdrawals', (json) async {
          final data = SalaryWithdrawal.fromJson(json, serializer: lenientValueSerializer);
          await db.into(db.salaryWithdrawals).insertOnConflictUpdate(data);
        });

        // Restore sync state if present
        if (backupData.containsKey('sync_state') &&
            backupData['sync_state'] is Map &&
            (backupData['sync_state'] as Map).isNotEmpty) {
          final syncStateJson = Map<String, dynamic>.from(
            backupData['sync_state'] as Map,
          );
          final data = SyncStateData.fromJson(
            syncStateJson,
            serializer: lenientValueSerializer,
          );
          await db.into(db.syncState).insertOnConflictUpdate(data);
        }

        AppLogger.info('تم استعادة البيانات من Google Drive بنجاح');
        return true;
      } finally {
        await db.customStatement('PRAGMA foreign_keys = ON');
      }
    } catch (e) {
      AppLogger.error('خطأ في استعادة البيانات: $e');
      return false;
    }
  }

  /// Delete a backup file by its ID
  Future<bool> deleteBackupFile(String fileId) => deleteBackup(fileId);

  // ────────────────────────────────────────────────────────────
  // ⚠️ SYNC OPERATIONS REMAIN DISABLED
  // Google Drive is for BACKUP & RESTORE ONLY — no sync
  // ────────────────────────────────────────────────────────────

}
