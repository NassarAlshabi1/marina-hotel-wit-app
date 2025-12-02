import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../utils/system_settings_keys.dart';
import 'auto_backup_task.dart';
import 'local_db.dart';
import 'restore_fix_service.dart';
import 'backup_serializers.dart';
import 'google_drive_logger.dart';
import 'alarm_backup.dart'; // Added for rescheduling upon setting sync

enum BackupFormat { json, sqlite }

class DriveBackupFile {
  final String fileId;
  final String fileName;
  final DateTime createdTime;
  final int? size;
  final Map<String, dynamic>? metadata;

  Map<String, String> get appProperties => metadata?.map((k, v) => MapEntry(k, v.toString())) ?? {};

  BackupFormat get format {
    final raw = metadata?['format'] as String?;
    return BackupFormat.values.firstWhere((f) => f.name == raw, orElse: () => BackupFormat.json);
  }

  DriveBackupFile({
    required this.fileId,
    required this.fileName,
    required this.createdTime,
    this.size,
    this.metadata,
  });

  factory DriveBackupFile.fromDriveFile(drive.File file) {
    return DriveBackupFile(
      fileId: file.id!,
      fileName: file.name!,
      createdTime: file.createdTime!,
      size: file.size != null ? int.parse(file.size!) : null,
      metadata: file.appProperties,
    );
  }
}

class BackupMetadata {
  final String appVersion;
  final int databaseVersion;
  final DateTime backupTimestamp;
  final int totalRecords;
  final String deviceInfo;
  final BackupFormat format;

  BackupMetadata({
    required this.appVersion,
    required this.databaseVersion,
    required this.backupTimestamp,
    required this.totalRecords,
    required this.deviceInfo,
    this.format = BackupFormat.json,
  });

  Map<String, dynamic> toJson() => {
        'app_version': appVersion,
        'database_version': databaseVersion,
        'backup_timestamp': backupTimestamp.toIso8601String(),
        'total_records': totalRecords,
        'device_info': deviceInfo,
        'format': format.name,
      };

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    final rawFormat = json['format'] as String?;
    final format = BackupFormat.values.firstWhere(
      (value) => value.name == rawFormat,
      orElse: () => BackupFormat.json,
    );
    return BackupMetadata(
      appVersion: json['app_version'] ?? '',
      databaseVersion: json['database_version'] ?? 1,
      backupTimestamp: DateTime.parse(json['backup_timestamp']),
      totalRecords: json['total_records'] ?? 0,
      deviceInfo: json['device_info'] ?? '',
      format: format,
    );
  }
}

class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client;

  GoogleAuthClient(this._headers) : _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
  }
}

class GoogleDriveBackupService {
  static const String _backupFolderName = 'MarinaHotelBackups';
  static const String _backupFilePrefix = 'marina_hotel_backup_';
  static const List<String> _scopes = [
    drive.DriveApi.driveFileScope,
    drive.DriveApi.driveAppdataScope,
  ];

  /// تحويل رموز خطأ Google Sign-In إلى رسائل عربية واضحة
  static String _getArabicErrorMessage(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'sign_in_failed':
          if (error.message?.contains('10') == true) {
            return 'خطأ في إعدادات التطبيق. تم إصلاح هذا الخطأ في التحديث الجديد.';
          }
          return 'فشل في تسجيل الدخول. تأكد من اتصال الإنترنت وأعد المحاولة.';
        case 'network_error':
          return 'خطأ في الشبكة. تحقق من اتصال الإنترنت وأعد المحاولة.';
        case 'sign_in_canceled':
          return 'تم إلغاء تسجيل الدخول من قبل المستخدم.';
        case 'sign_in_required':
          return 'مطلوب تسجيل الدخول للوصول إلى هذه الميزة.';
        default:
          return 'خطأ في تسجيل الدخول: ${error.code}';
      }
    }
    return 'خطأ غير متوقع في تسجيل الدخول: $error';
  }

  static const String _prefsLastBackupKey = 'last_backup_timestamp';
  static const String _prefsAutoBackupKey = 'auto_backup_enabled';
  static const String _prefsAutoBackupFrequencyKey = 'auto_backup_frequency';
  static const String _prefsAutoBackupTimeKey = 'auto_backup_time';

  GoogleSignIn? _googleSignIn;
  drive.DriveApi? _driveApi;
  String? _backupFolderId;
  final GoogleDriveLogger _logger = GoogleDriveLogger();

  GoogleDriveBackupService() {
    _initializeGoogleSignIn();
  }

  void _initializeGoogleSignIn() {
    _googleSignIn = GoogleSignIn(
      scopes: _scopes,
    );
  }

  Future<void> _ensureDriveClient() async {
    if (_googleSignIn == null) {
      _initializeGoogleSignIn();
    }

    GoogleSignInAccount? account = _googleSignIn?.currentUser;
    if (account == null) {
      try {
        account = await _googleSignIn?.signInSilently();
      } catch (e) {
        debugPrint('⚠️ فشل signInSilently أثناء تحديث الاعتماديات: $e');
      }
    }

    if (account == null) {
      throw Exception('يجب إعادة تسجيل الدخول في Google Drive لإكمال العملية');
    }

    final headers = await account.authHeaders;
    _driveApi = drive.DriveApi(GoogleAuthClient(headers));
  }

  Future<T> _runWithAuth<T>(Future<T> Function() action) async {
    await _ensureDriveClient();
    try {
      return await action();
    } on drive.DetailedApiRequestError catch (e) {
      if (e.status == 401) {
        debugPrint('⚠️ تم فقد صلاحية رمز Google Drive، إعادة المحاولة بعد التحديث...');
        _driveApi = null;
        await _ensureDriveClient();
        return await action();
      }
      rethrow;
    }
  }

  Future<GoogleSignInAccount?> signInForDrive() async {
    try {
      if (_googleSignIn == null) {
        throw Exception('Google Sign-In لم يتم تهيئته بشكل صحيح');
      }

      debugPrint('🔄 محاولة تسجيل الدخول الصامت...');
      GoogleSignInAccount? account = await _googleSignIn!.signInSilently();

      if (account == null) {
        debugPrint('🔄 تسجيل الدخول الصامت فشل، بدء تسجيل الدخول التفاعلي...');
        account = await _googleSignIn!.signIn();
      }

      if (account != null) {
        debugPrint('🔑 الحصول على رؤوس المصادقة...');
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);

        debugPrint('✅ تم تسجيل الدخول بنجاح في Google Drive: ${account.email}');
        debugPrint('🔧 النطاقات المطلوبة: ${_scopes.join(', ')}');
      } else {
        debugPrint('⚠️ تم إلغاء تسجيل الدخول أو فشل');
      }

      return account;
    } catch (e) {
      final arabicError = _getArabicErrorMessage(e);
      debugPrint('❌ خطأ في تسجيل الدخول في Google Drive: $arabicError');
      debugPrint('❌ تفاصيل الخطأ التقنية: $e');
      
      // رمي الخطأ مع الرسالة العربية
      throw Exception(arabicError);
    }
  }

  /// محاولة استعادة جلسة تسجيل الدخول بشكل صامت
  Future<GoogleSignInAccount?> attemptSilentSignIn() async {
    try {
      if (_googleSignIn == null) {
        _initializeGoogleSignIn();
      }
      
      debugPrint('🔄 محاولة استعادة جلسة Google Drive...');
      GoogleSignInAccount? account = await _googleSignIn!.signInSilently(suppressErrors: true);
      
      if (account != null) {
        debugPrint('🔑 الحصول على رؤوس المصادقة...');
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);
        
        debugPrint('✅ تم استعادة جلسة Google Drive: ${account.email}');
        return account;
      } else {
        debugPrint('ℹ️ لا توجد جلسة محفوظة');
        return null;
      }
    } catch (e) {
      debugPrint('⚠️ فشلت استعادة الجلسة: $e');
      return null;
    }
  }

  /// محاولة تسجيل الدخول بهدوء للاستخدام في الخلفية (Alarm Callback)
  Future<bool> signInSilentlyIfNeeded() async {
    try {
      if (_googleSignIn == null) _initializeGoogleSignIn();
      final account = await _googleSignIn!.signInSilently(suppressErrors: true);
      
      if (account != null) {
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);
        debugPrint('✅ تم تسجيل الدخول بهدوء: ${account.email}');
        return true;
      }
      
      debugPrint('⚠️ لا توجد جلسة محفوظة للدخول الهادئ');
      return false;
    } catch (e) {
      debugPrint('❌ signInSilently error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn?.signOut();
      _driveApi = null;
      _backupFolderId = null;
      debugPrint('✅ تم تسجيل الخروج من Google Drive');
      _logger.info('تم تسجيل الخروج من Google Drive', tag: 'AUTH');
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الخروج: $e');
      rethrow;
    }
  }

  GoogleSignInAccount? get currentUser => _googleSignIn?.currentUser;
  GoogleSignIn? get googleSignIn => _googleSignIn;

  bool get isSignedIn => _googleSignIn?.currentUser != null;

  Future<String> getOrCreateBackupFolder() async {
    if (_backupFolderId != null) {
      return _backupFolderId!;
    }

    return _runWithAuth<String>(() async {
      if (_backupFolderId != null) {
        return _backupFolderId!;
      }

      try {
        final query = "name='$_backupFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
        final searchResult = await _driveApi!.files.list(q: query);

        if (searchResult.files != null && searchResult.files!.isNotEmpty) {
          _backupFolderId = searchResult.files!.first.id;
          debugPrint('✅ تم العثور على مجلد النسخ الاحتياطية: $_backupFolderId');
        } else {
          final folder = drive.File()
            ..name = _backupFolderName
            ..mimeType = 'application/vnd.google-apps.folder';

          final createdFolder = await _driveApi!.files.create(folder);
          _backupFolderId = createdFolder.id;
          debugPrint('✅ تم إنشاء مجلد النسخ الاحتياطية: $_backupFolderId');
        }

        return _backupFolderId!;
      } catch (e) {
        debugPrint('❌ خطأ في إنشاء/العثور على مجلد النسخ الاحتياطية: $e');
        rethrow;
      }
    });
  }

  Future<Map<String, dynamic>> exportDatabaseToJson() async {
    try {
      final db = DatabaseManager.instance;

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
      final debtsData = await db.select(db.debts).get();
      final autoFixRunsData = await db.select(db.autoFixRuns).get();
      final violationsData = await db.select(db.integrityViolations).get();
      final sessionsData = await db.select(db.appSessions).get();
      final salaryCyclesData = await db.select(db.salaryCycles).get();
      final salaryPaymentsData = await db.select(db.salaryPayments).get();
      final restoreFixLogsData = await db.select(db.restoreFixLog).get();
      final syncQueueData = await db.select(db.syncQueue).get();
      final syncLogData = await db.select(db.syncLog).get();
      final syncConflictsData = await db.select(db.syncConflicts).get();
      final syncStateData = await db.select(db.syncState).get();

      // جلب الإعدادات العامة لدمجها في النسخة الاحتياطية
      final prefs = await SharedPreferences.getInstance();
      final systemSettings = {
        SystemSettingKeys.autoBackupEnabled: prefs.getBool(SystemSettingKeys.autoBackupEnabled),
        SystemSettingKeys.autoBackupTime: prefs.getString(SystemSettingKeys.autoBackupTime),
        SystemSettingKeys.autoBackupFrequency: prefs.getString(SystemSettingKeys.autoBackupFrequency),
        SystemSettingKeys.scheduledBackupEnabled: prefs.getBool(SystemSettingKeys.scheduledBackupEnabled),
        SystemSettingKeys.autoLocalBackupEnabled: prefs.getBool(SystemSettingKeys.autoLocalBackupEnabled),
        SystemSettingKeys.smartSyncInterval: prefs.getInt(SystemSettingKeys.smartSyncInterval),
        SystemSettingKeys.wifiOnlySync: prefs.getBool(SystemSettingKeys.wifiOnlySync),
      };

      final totalRecords =
          roomsData.length +
          bookingsData.length +
          bookingNotesData.length +
          bookingNightsData.length +
          ledgerData.length +
          shiftNotesData.length +
          employeesData.length +
          expensesData.length +
          cashTransactionsData.length +
          paymentsData.length +
          debtsData.length +
          autoFixRunsData.length +
          violationsData.length +
          sessionsData.length +
          salaryCyclesData.length +
          salaryPaymentsData.length +
          restoreFixLogsData.length +
          syncQueueData.length +
          syncLogData.length +
          syncConflictsData.length +
          syncStateData.length;

      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: 3,
        backupTimestamp: DateTime.now(),
        totalRecords: totalRecords,
        deviceInfo: Platform.isAndroid ? 'Android' : 'iOS',
        format: BackupFormat.json,
      );

      final backupData = {
        'metadata': metadata.toJson(),
        'rooms': roomsData.map((room) => room.toJson()).toList(),
        'bookings': bookingsData.map((booking) => booking.toJson()).toList(),
        'booking_notes': bookingNotesData.map((note) => note.toJson()).toList(),
        'booking_nights': bookingNightsData.map((night) => night.toJson()).toList(),
        'hotel_day_ledger': ledgerData.map((entry) => entry.toJson()).toList(),
        'shift_notes': shiftNotesData.map((note) => note.toJson()).toList(),
        'employees': employeesData.map((employee) => employee.toJson()).toList(),
        'expenses': expensesData.map((expense) => expense.toJson()).toList(),
        'cash_transactions': cashTransactionsData.map((transaction) => transaction.toJson()).toList(),
        'payments': paymentsData.map((payment) => payment.toJson()).toList(),
        'debts': debtsData.map((debt) => debt.toJson()).toList(),
        'auto_fix_runs': autoFixRunsData.map((run) => run.toJson()).toList(),
        'integrity_violations': violationsData.map((violation) => violation.toJson()).toList(),
        'app_sessions': sessionsData.map((session) => session.toJson()).toList(),
        'salary_cycles': salaryCyclesData.map((cycle) => cycle.toJson()).toList(),
        'salary_payments': salaryPaymentsData.map((payment) => payment.toJson()).toList(),
        'restore_fix_log': restoreFixLogsData.map((log) => log.toJson()).toList(),
        'sync_queue': syncQueueData.map((row) => row.toJson()).toList(),
        'sync_log': syncLogData.map((row) => row.toJson()).toList(),
        'sync_conflicts': syncConflictsData.map((row) => row.toJson()).toList(),
        'sync_state': syncStateData.isNotEmpty ? syncStateData.first.toJson() : {},
        'system_settings': systemSettings, // تصدير الإعدادات
      };

      debugPrint('✅ تم تصدير البيانات: $totalRecords سجل');
      return backupData;
    } catch (e) {
      debugPrint('❌ خطأ في تصدير البيانات: $e');
      rethrow;
    }
  }

  static const fullBackupPrefix = 'marina_backup_full_';
  static const deltaSyncPrefix = 'marina_sync_delta_';

  Future<String> uploadBackup(Map<String, dynamic> backupData) async {
    String? partialFileId;
    
    return _runWithAuth<String>(() async {
      try {
        final folderId = await getOrCreateBackupFolder();

        final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
        final jsonBytes = utf8.encode(jsonString);

        final timestamp = DateTime.now();
        final fileName = '${fullBackupPrefix}${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.json';

        final metadata = backupData['metadata'] as Map<String, dynamic>? ?? {};

        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId]
          ..appProperties = _buildAppProperties(metadata, timestamp);

        final media = drive.Media(Stream.value(jsonBytes), jsonBytes.length);
        
        debugPrint('📤 بدء رفع النسخة الاحتياطية: $fileName (${(jsonBytes.length / 1024).toStringAsFixed(2)} KB)');
        
        final uploadedFile = await _driveApi!.files.create(
          driveFile,
          uploadMedia: media,
        );

        partialFileId = uploadedFile.id;

        // التحقق من اكتمال الرفع
        final verifyResult = await _verifyUploadedBackup(uploadedFile.id!, jsonBytes.length);
        if (!verifyResult['is_complete']) {
          debugPrint('⚠️ النسخة غير مكتملة: ${verifyResult['message']}');
          // حذف النسخة الناقصة
          await deleteBackupFile(uploadedFile.id!);
          throw Exception('فشل في رفع النسخة بشكل كامل: ${verifyResult['message']}');
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsLastBackupKey, timestamp.toIso8601String());

        debugPrint('✅ تم رفع النسخة الاحتياطية بنجاح: ${uploadedFile.id}');
        partialFileId = null; // تم بنجاح، لا حاجة للتنظيف
        return uploadedFile.id!;
      } catch (e) {
        debugPrint('❌ خطأ في رفع النسخة الاحتياطية: $e');
        
        // حذف النسخة الجزئية إذا كانت موجودة
        if (partialFileId != null) {
          try {
            debugPrint('🧹 حذف النسخة الجزئية: $partialFileId');
            await deleteBackupFile(partialFileId!);
          } catch (cleanupError) {
            debugPrint('⚠️ فشل حذف النسخة الجزئية: $cleanupError');
          }
        }
        
        rethrow;
      }
    });
  }

  Future<String> uploadBackupWithName(String fileName, List<int> bytes, {Map<String, String>? appProperties}) async {
    return _runWithAuth<String>(() async {
      final folderId = await getOrCreateBackupFolder();
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..appProperties = appProperties ?? {};
      final media = drive.Media(Stream.value(bytes), bytes.length);
      debugPrint('📤 رفع ملف مزامنة: $fileName (${(bytes.length / 1024).toStringAsFixed(2)} KB)');
      final uploadedFile = await _driveApi!.files.create(driveFile, uploadMedia: media);
      debugPrint('✅ تم رفع الملف: ${uploadedFile.id}');
      return uploadedFile.id!;
    });
  }

  Future<void> deleteBackup(String fileId) => deleteBackupFile(fileId);

  /// التحقق من اكتمال النسخة المرفوعة
  Future<Map<String, dynamic>> _verifyUploadedBackup(String fileId, int expectedSize) async {
    try {
      final file = await _driveApi!.files.get(
        fileId,
        $fields: 'id,name,size,appProperties',
      ) as drive.File;

      final actualSize = file.size != null ? int.tryParse(file.size!) ?? 0 : 0;

      // التحقق من الحجم (يسمح بفارق 1% بسبب الضغط)
      final sizeDifference = (actualSize - expectedSize).abs();
      final maxAllowedDifference = expectedSize * 0.01; // 1%

      if (sizeDifference > maxAllowedDifference) {
        return {
          'is_complete': false,
          'message': 'حجم الملف غير متطابق (متوقع: $expectedSize، فعلي: $actualSize)',
          'actual_size': actualSize,
          'expected_size': expectedSize,
        };
      }

      // التحقق من البيانات الوصفية
      if (file.appProperties == null || file.appProperties!.isEmpty) {
        return {
          'is_complete': false,
          'message': 'البيانات الوصفية مفقودة',
        };
      }

      return {
        'is_complete': true,
        'message': 'النسخة مكتملة',
        'actual_size': actualSize,
      };
    } catch (e) {
      return {
        'is_complete': false,
        'message': 'فشل التحقق: $e',
      };
    }
  }

  Map<String, String> _buildAppProperties(Map<String, dynamic> metadata, DateTime timestamp) {
    final props = <String, String>{
      'app_name': 'MarinaHotel',
      'backup_timestamp': timestamp.toIso8601String(),
    };

    void addIfPresent(String key, dynamic value) {
      if (value == null) return;
      final stringValue = value.toString();
      if (stringValue.isEmpty) return;
      props[key] = stringValue;
    }

    addIfPresent('records_count', metadata['total_records']);
    addIfPresent('app_version', metadata['app_version']);
    addIfPresent('device_info', metadata['device_info']);
    addIfPresent('format', metadata['format']);
    addIfPresent('device_id', metadata['device_id']); // معرف الجهاز للمزامنة
    addIfPresent('backup_type', metadata['backup_type']);
    addIfPresent('changes_count', metadata['changes_count']);

    return props;
  }

  Future<List<DriveBackupFile>> listBackups() async {
    return _runWithAuth<List<DriveBackupFile>>(() async {
      final folderId = await getOrCreateBackupFolder();

      final query = "parents in '$folderId' and name contains '$_backupFilePrefix' and trashed=false";
      final listResult = await _driveApi!.files.list(
        q: query,
        orderBy: 'createdTime desc',
        spaces: 'drive',
        $fields: 'files(id,name,createdTime,size,appProperties)',
      );

      final backupFiles = <DriveBackupFile>[];
      if (listResult.files != null) {
        for (final file in listResult.files!) {
          backupFiles.add(DriveBackupFile.fromDriveFile(file));
        }
      }

      debugPrint('✅ تم جلب ${backupFiles.length} نسخة احتياطية');
      return backupFiles;
    });
  }

  Future<List<DriveBackupFile>> listBackupFiles({int? limit}) async {
    final backups = await listBackups();
    if (limit == null || limit >= backups.length) {
      return backups;
    }
    return backups.sublist(0, limit);
  }

  Future<Map<String, dynamic>> downloadBackup(String fileId) async {
    return _runWithAuth<Map<String, dynamic>>(() async {
      final media = await _driveApi!.files.get(
        fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final List<int> dataStore = [];
      await for (final data in media.stream) {
        dataStore.addAll(data);
      }

      final jsonString = utf8.decode(dataStore);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      debugPrint('✅ تم تنزيل النسخة الاحتياطية: $fileId');
      return backupData;
    });
  }

  Future<void> restoreFromBackup(Map<String, dynamic> backupData) async {
    try {
      final db = DatabaseManager.instance;

      if (!backupData.containsKey('metadata')) {
        throw Exception('النسخة الاحتياطية لا تحتوي على بيانات وصفية');
      }

      final metadata = BackupMetadata.fromJson(backupData['metadata']);
      _logger.info('بدء استعادة نسخة بتاريخ ${metadata.backupTimestamp.toIso8601String()} تحتوي ${metadata.totalRecords} سجل', tag: 'RESTORE');

      if (metadata.databaseVersion > 3) {
        throw Exception('إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي');
      }

      debugPrint('🔄 بدء استعادة البيانات...');

      await db.delete(db.rooms).go();
      await db.delete(db.bookings).go();
      await db.delete(db.bookingNotes).go();
      await db.delete(db.bookingNights).go();
      await db.delete(db.hotelDayLedger).go();
      await db.delete(db.shiftNotes).go();
      await db.delete(db.employees).go();
      await db.delete(db.expenses).go();
      await db.delete(db.cashTransactions).go();
      await db.delete(db.payments).go();
      await db.delete(db.debts).go();
      await db.delete(db.autoFixRuns).go();
      await db.delete(db.integrityViolations).go();
      await db.delete(db.appSessions).go();
      await db.delete(db.salaryCycles).go();
      await db.delete(db.salaryPayments).go();
      await db.delete(db.restoreFixLog).go();
      await db.delete(db.syncQueue).go();
      await db.delete(db.syncLog).go();
      await db.delete(db.syncConflicts).go();
      await db.delete(db.syncState).go();

      if (backupData.containsKey('rooms')) {
        final roomsData = backupData['rooms'] as List<dynamic>;
        for (final roomJson in roomsData) {
          final map = Map<String, dynamic>.from(roomJson as Map);
          final data = Room.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.rooms).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('bookings')) {
        final bookingsData = backupData['bookings'] as List<dynamic>;
        for (final bookingJson in bookingsData) {
          final map = Map<String, dynamic>.from(bookingJson as Map);
          final data = Booking.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.bookings).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('booking_notes')) {
        final notesData = backupData['booking_notes'] as List<dynamic>;
        for (final noteJson in notesData) {
          final map = Map<String, dynamic>.from(noteJson as Map);
          final data = BookingNote.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.bookingNotes).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('booking_nights')) {
        final nightsData = backupData['booking_nights'] as List<dynamic>;
        for (final nightJson in nightsData) {
          final map = Map<String, dynamic>.from(nightJson as Map);
          final data = BookingNight.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.bookingNights).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('hotel_day_ledger')) {
        final ledgerList = backupData['hotel_day_ledger'] as List<dynamic>;
        for (final ledgerJson in ledgerList) {
          final map = Map<String, dynamic>.from(ledgerJson as Map);
          final data = HotelDayLedgerEntry.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.hotelDayLedger).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('shift_notes')) {
        final shiftsData = backupData['shift_notes'] as List<dynamic>;
        for (final shiftJson in shiftsData) {
          final map = Map<String, dynamic>.from(shiftJson as Map);
          final data = ShiftNote.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.shiftNotes).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('employees')) {
        final employeesData = backupData['employees'] as List<dynamic>;
        for (final employeeJson in employeesData) {
          final map = Map<String, dynamic>.from(employeeJson as Map);
          final data = Employee.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.employees).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('expenses')) {
        final expensesData = backupData['expenses'] as List<dynamic>;
        for (final expenseJson in expensesData) {
          final map = Map<String, dynamic>.from(expenseJson as Map);
          final data = Expense.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.expenses).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('cash_transactions')) {
        final transactionsData = backupData['cash_transactions'] as List<dynamic>;
        for (final transactionJson in transactionsData) {
          final map = Map<String, dynamic>.from(transactionJson as Map);
          final data = CashTransaction.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.cashTransactions).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('payments')) {
        final paymentsData = backupData['payments'] as List<dynamic>;
        for (final paymentJson in paymentsData) {
          final map = Map<String, dynamic>.from(paymentJson as Map);
          final data = Payment.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.payments).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('debts')) {
        final debtsList = backupData['debts'] as List<dynamic>;
        for (final debtJson in debtsList) {
          final map = Map<String, dynamic>.from(debtJson as Map);
          final data = Debt.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.debts).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('auto_fix_runs')) {
        final runsList = backupData['auto_fix_runs'] as List<dynamic>;
        for (final runJson in runsList) {
          final map = Map<String, dynamic>.from(runJson as Map);
          final data = AutoFixRun.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.autoFixRuns).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('integrity_violations')) {
        final violationsList = backupData['integrity_violations'] as List<dynamic>;
        for (final violationJson in violationsList) {
          final map = Map<String, dynamic>.from(violationJson as Map);
          final data = IntegrityViolation.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.integrityViolations).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('app_sessions')) {
        final sessionsList = backupData['app_sessions'] as List<dynamic>;
        for (final sessionJson in sessionsList) {
          final map = Map<String, dynamic>.from(sessionJson as Map);
          final data = AppSession.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.appSessions).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('salary_cycles')) {
        final cyclesList = backupData['salary_cycles'] as List<dynamic>;
        for (final cycleJson in cyclesList) {
          final map = Map<String, dynamic>.from(cycleJson as Map);
          final data = SalaryCycle.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.salaryCycles).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('salary_payments')) {
        final salaryList = backupData['salary_payments'] as List<dynamic>;
        for (final salaryJson in salaryList) {
          final map = Map<String, dynamic>.from(salaryJson as Map);
          final data = SalaryPayment.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.salaryPayments).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('restore_fix_log')) {
        final restoreList = backupData['restore_fix_log'] as List<dynamic>;
        for (final logJson in restoreList) {
          final map = Map<String, dynamic>.from(logJson as Map);
          final data = RestoreFixLogData.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.restoreFixLog).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('sync_queue')) {
        final queueList = backupData['sync_queue'] as List<dynamic>;
        for (final rowJson in queueList) {
          final map = Map<String, dynamic>.from(rowJson as Map);
          final data = SyncQueueData.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.syncQueue).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('sync_log')) {
        final logList = backupData['sync_log'] as List<dynamic>;
        for (final logJson in logList) {
          final map = Map<String, dynamic>.from(logJson as Map);
          final data = SyncLogData.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.syncLog).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('sync_conflicts')) {
        final conflictsList = backupData['sync_conflicts'] as List<dynamic>;
        for (final conflictJson in conflictsList) {
          final map = Map<String, dynamic>.from(conflictJson as Map);
          final data = SyncConflictRow.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.syncConflicts).insertOnConflictUpdate(data);
        }
      }

      if (backupData.containsKey('sync_state') && backupData['sync_state'] is Map && (backupData['sync_state'] as Map).isNotEmpty) {
        final syncStateJson = Map<String, dynamic>.from(backupData['sync_state'] as Map);
        final data = SyncStateData.fromJson(syncStateJson, serializer: lenientValueSerializer);
        await db.into(db.syncState).insertOnConflictUpdate(data);
      }

      // استعادة وتطبيق الإعدادات العامة إذا وجدت
      if (backupData.containsKey('system_settings')) {
        debugPrint('⚙️ تطبيق إعدادات النظام من النسخة الاحتياطية...');
        try {
          final settings = backupData['system_settings'] as Map<String, dynamic>;
          final prefs = await SharedPreferences.getInstance();
          
          final keys = SystemSettingKeys.all;

          bool settingsChanged = false;
          for (final key in keys) {
            if (settings.containsKey(key) && settings[key] != null) {
              final val = settings[key];
              final currentVal = prefs.get(key);
              
              if (val != currentVal) {
                if (val is bool) await prefs.setBool(key, val);
                if (val is String) await prefs.setString(key, val);
                if (val is int) await prefs.setInt(key, val);
                if (val is double) await prefs.setDouble(key, val);
                settingsChanged = true;
                debugPrint('   UPDATED: $key = $val');
              }
            }
          }

          // إعادة جدولة المهام إذا تغيرت الإعدادات
          if (settingsChanged) {
             debugPrint('🔄 إعادة جدولة مهام النسخ الاحتياطي وفق الإعدادات الجديدة...');
             
             final timeStr = prefs.getString('auto_backup_time') ?? '21:00';
             final parts = timeStr.split(':');
             final hour = int.parse(parts[0]);
             final minute = int.parse(parts[1]);
             final scheduledEnabled = prefs.getBool('scheduled_backup_enabled') ?? true;

             if (scheduledEnabled) {
               await AlarmBackup.rescheduleDaily(hour, minute);
               await AutoBackupTask.scheduleDaily(time: timeStr);
             } else {
               await AlarmBackup.cancelAlarm();
               await AutoBackupTask.cancelScheduled();
             }
          }
        } catch (e) {
          debugPrint('⚠️ خطأ في تطبيق الإعدادات المستعادة: $e');
        }
      }

      debugPrint('✅ تم استعادة ${metadata.totalRecords} سجل بنجاح');
      final fixService = RestoreFixService(db);
      await fixService.runAutoFixAfterRestore(backupTimestamp: metadata.backupTimestamp);
    } catch (e) {
      debugPrint('❌ خطأ في استعادة البيانات: $e');
      rethrow;
    }
  }

  Future<void> scheduleAutoBackup() async {
    final prefs = await SharedPreferences.getInstance();
    final isEnabled = prefs.getBool(_prefsAutoBackupKey) ?? false;

    if (!isEnabled) {
      await cancelAutoBackup();
      return;
    }

    final frequency = prefs.getString(_prefsAutoBackupFrequencyKey) ?? 'daily';
    final timeString = prefs.getString(_prefsAutoBackupTimeKey) ?? '02:00';

    Duration initialDelay;
    Duration frequencyDuration;

    switch (frequency) {
      case 'daily':
        frequencyDuration = const Duration(days: 1);
        break;
      case 'weekly':
        frequencyDuration = const Duration(days: 7);
        break;
      case 'monthly':
        frequencyDuration = const Duration(days: 30);
        break;
      default:
        frequencyDuration = const Duration(days: 1);
    }

    final now = DateTime.now();
    final timeParts = timeString.split(':');
    final targetTime = DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
    );

    if (targetTime.isBefore(now)) {
      initialDelay = targetTime.add(frequencyDuration).difference(now);
    } else {
      initialDelay = targetTime.difference(now);
    }

    try {
      await Workmanager().cancelByUniqueName(AutoBackupTask.taskId);
      await Future.delayed(const Duration(seconds: 1));
      await AutoBackupTask.initialize();

      await Workmanager().registerPeriodicTask(
        AutoBackupTask.taskId,
        AutoBackupTask.taskName,
        frequency: frequencyDuration,
        initialDelay: initialDelay,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.replace,
        inputData: const <String, dynamic>{},
      );

      debugPrint('✅ تم جدولة النسخ التلقائي: $frequency في $timeString');
    } catch (e) {
      debugPrint('❌ خطأ في جدولة النسخ التلقائي: $e');
    }
  }

  Future<void> cancelAutoBackup() async {
    try {
      await Workmanager().cancelByUniqueName('autoBackup');
      debugPrint('✅ تم إلغاء النسخ التلقائي');
    } catch (e) {
      debugPrint('❌ خطأ في إلغاء النسخ التلقائي: $e');
    }
  }

  Future<void> performAutoBackup() async {
    try {
      if (!isSignedIn) {
        debugPrint('⚠️ المستخدم غير مسجل دخول، تم تخطي النسخ التلقائي');
        return;
      }

      debugPrint('🔄 بدء النسخ التلقائي...');

      final backupData = await exportDatabaseToJson();
      final fileId = await uploadBackup(backupData);

      debugPrint('✅ تم النسخ التلقائي بنجاح: $fileId');
    } catch (e) {
      debugPrint('❌ خطأ في النسخ التلقائي: $e');
    }
  }

  Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString(_prefsLastBackupKey);
    return timeString != null ? DateTime.parse(timeString) : null;
  }

  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoBackupKey, enabled);

    if (enabled) {
      await scheduleAutoBackup();
    } else {
      await cancelAutoBackup();
    }
  }

  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_prefsAutoBackupKey)) {
      await prefs.setBool(_prefsAutoBackupKey, true);
      await scheduleAutoBackup();
      return true;
    }
    return prefs.getBool(_prefsAutoBackupKey) ?? true;
  }

  Future<void> setAutoBackupFrequency(String frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAutoBackupFrequencyKey, frequency);

    final isEnabled = await isAutoBackupEnabled();
    if (isEnabled) {
      await scheduleAutoBackup();
    }
  }

  Future<String> getAutoBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsAutoBackupFrequencyKey) ?? 'daily';
  }

  Future<void> setAutoBackupTime(String time) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAutoBackupTimeKey, time);

    final isEnabled = await isAutoBackupEnabled();
    if (isEnabled) {
      await scheduleAutoBackup();
    }
  }

  Future<String> getAutoBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsAutoBackupTimeKey) ?? '02:00';
  }

  Future<int> estimateDatabaseSize() async {
    try {
      final backupData = await exportDatabaseToJson();
      final jsonString = const JsonEncoder().convert(backupData);
      return utf8.encode(jsonString).length;
    } catch (e) {
      debugPrint('❌ خطأ في تقدير حجم قاعدة البيانات: $e');
      return 0;
    }
  }

  Future<void> deleteBackupFile(String fileId) async {
    await _runWithAuth<void>(() async {
      await _driveApi!.files.delete(fileId);
      debugPrint('🗑️ تم حذف النسخة الاحتياطية: $fileId');
    });
  }

  /// تنظيف النسخ الاحتياطية القديمة تلقائياً
  /// 
  /// [maxBackupsToKeep] - عدد النسخ الاحتياطية المراد الاحتفاظ بها (افتراضي: 10)
  /// [maxAgeInDays] - عمر النسخة بالأيام قبل الحذف (افتراضي: 30 يوم)
  /// [dryRun] - إذا true، لا يتم الحذف فعلياً (للمعاينة فقط)
  /// 
  /// Returns: عدد النسخ التي تم حذفها
  Future<int> cleanupOldBackups({
    int maxBackupsToKeep = 10,
    int maxAgeInDays = 30,
    bool dryRun = false,
  }) async {
    try {
      debugPrint('🧹 بدء تنظيف النسخ القديمة...');
      debugPrint('📊 الإعدادات: maxBackups=$maxBackupsToKeep, maxAge=$maxAgeInDays أيام, dryRun=$dryRun');

      // الحصول على جميع النسخ الاحتياطية
      final backups = await listBackups();
      
      if (backups.isEmpty) {
        debugPrint('✅ لا توجد نسخ احتياطية للتنظيف');
        _logger.info('لا توجد نسخ احتياطية لتنظيفها', tag: 'CLEANUP');
        return 0;
      }

      // ترتيب النسخ حسب التاريخ (الأحدث أولاً)
      backups.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      
      final now = DateTime.now();
      final cutoffDate = now.subtract(Duration(days: maxAgeInDays));
      final backupsToDelete = <DriveBackupFile>[];

      // 1. حذف النسخ التي تجاوزت العمر المحدد
      for (final backup in backups) {
        if (backup.createdTime.isBefore(cutoffDate)) {
          backupsToDelete.add(backup);
        }
      }

      // 2. حذف النسخ الزائدة (الاحتفاظ بـ maxBackupsToKeep فقط)
      if (backups.length > maxBackupsToKeep) {
        final excessBackups = backups.skip(maxBackupsToKeep).toList();
        for (final backup in excessBackups) {
          if (!backupsToDelete.contains(backup)) {
            backupsToDelete.add(backup);
          }
        }
      }

      if (backupsToDelete.isEmpty) {
        debugPrint('✅ جميع النسخ ضمن الحدود المقبولة');
        return 0;
      }

      debugPrint('📋 سيتم حذف ${backupsToDelete.length} نسخة احتياطية:');
      for (final backup in backupsToDelete) {
        final age = now.difference(backup.createdTime).inDays;
        final sizeKB = backup.size != null ? (backup.size! / 1024).toStringAsFixed(2) : 'غير معروف';
        debugPrint('  - ${backup.fileName} (عمر: $age يوم، حجم: $sizeKB KB)');
      }

      // حذف النسخ فعلياً (إلا إذا كان dryRun)
      int deletedCount = 0;
      if (!dryRun) {
        for (final backup in backupsToDelete) {
          try {
            await deleteBackupFile(backup.fileId);
            deletedCount++;
          } catch (e) {
            debugPrint('⚠️ فشل حذف النسخة ${backup.fileName}: $e');
          }
        }
        debugPrint('✅ تم حذف $deletedCount نسخة احتياطية بنجاح');
      } else {
        debugPrint('ℹ️ وضع المعاينة (dryRun) - لم يتم حذف أي شيء فعلياً');
        deletedCount = backupsToDelete.length;
      }

      // حساب المساحة المحررة
      if (deletedCount > 0 && !dryRun) {
        int totalSizeFreed = 0;
        for (final backup in backupsToDelete) {
          totalSizeFreed += backup.size ?? 0;
        }
        final sizeMB = (totalSizeFreed / (1024 * 1024)).toStringAsFixed(2);
        debugPrint('💾 المساحة المحررة: $sizeMB MB');
      }

      return deletedCount;
    } catch (e) {
      debugPrint('❌ خطأ في تنظيف النسخ القديمة: $e');
      rethrow;
    }
  }

  /// فحص وحذف النسخ الناقصة (التي فشل رفعها)
  /// 
  /// Returns: عدد النسخ الناقصة التي تم حذفها
  Future<int> cleanupIncompleteBackups() async {
    try {
      debugPrint('🔍 بدء فحص النسخ الناقصة...');
      _logger.info('بدء فحص النسخ الناقصة', tag: 'VALIDATE');
      
      final backups = await listBackups();
      
      if (backups.isEmpty) {
        debugPrint('✅ لا توجد نسخ للفحص');
        _logger.info('لا توجد نسخ لفحصها', tag: 'VALIDATE');
        return 0;
      }

      final incompleteBackups = <DriveBackupFile>[];

      for (final backup in backups) {
        // التحقق من البيانات الوصفية
        if (backup.metadata == null || backup.metadata!.isEmpty) {
          debugPrint('⚠️ نسخة بدون بيانات وصفية: ${backup.fileName}');
          incompleteBackups.add(backup);
          continue;
        }

        // التحقق من الحجم (النسخ الصغيرة جداً قد تكون ناقصة)
        if (backup.size != null && backup.size! < 1024) { // أقل من 1 KB
          debugPrint('⚠️ نسخة صغيرة جداً (${backup.size} bytes): ${backup.fileName}');
          incompleteBackups.add(backup);
          continue;
        }

        // محاولة تنزيل وفك تشفير النسخة للتحقق
        try {
          final data = await downloadBackup(backup.fileId);
          
          // التحقق من البنية الأساسية
          if (!data.containsKey('metadata') || !data.containsKey('rooms')) {
            debugPrint('⚠️ نسخة ببنية غير صحيحة: ${backup.fileName}');
            incompleteBackups.add(backup);
            continue;
          }
        } catch (e) {
          debugPrint('⚠️ فشل قراءة النسخة (قد تكون تالفة): ${backup.fileName} - $e');
          incompleteBackups.add(backup);
          continue;
        }
      }

      if (incompleteBackups.isEmpty) {
        debugPrint('✅ جميع النسخ سليمة');
        _logger.info('جميع النسخ سليمة بعد الفحص', tag: 'VALIDATE');
        return 0;
      }

      debugPrint('📋 تم اكتشاف ${incompleteBackups.length} نسخة ناقصة:');
      for (final backup in incompleteBackups) {
        debugPrint('  - ${backup.fileName}');
      }

      // حذف النسخ الناقصة
      int deletedCount = 0;
      for (final backup in incompleteBackups) {
        try {
          await deleteBackupFile(backup.fileId);
          deletedCount++;
        } catch (e) {
          debugPrint('⚠️ فشل حذف النسخة الناقصة ${backup.fileName}: $e');
        }
      }

      debugPrint('✅ تم حذف $deletedCount نسخة ناقصة');
      return deletedCount;
    } catch (e) {
      debugPrint('❌ خطأ في فحص النسخ الناقصة: $e');
      return 0;
    }
  }

  /// تنظيف تلقائي مع إعدادات افتراضية معقولة
  Future<int> autoCleanup() async {
    return cleanupOldBackups(
      maxBackupsToKeep: 15,
      maxAgeInDays: 30,
      dryRun: false,
    );
  }

  /// الحصول على إحصائيات النسخ الاحتياطية
  Future<Map<String, dynamic>> getBackupStatistics() async {
    try {
      final backups = await listBackups();
      
      if (backups.isEmpty) {
        _logger.info('لا توجد نسخ احتياطية لعرض الإحصائيات', tag: 'METRICS');
        return {
          'total_backups': 0,
          'total_size_bytes': 0,
          'total_size_mb': '0.00',
          'oldest_backup': null,
          'newest_backup': null,
        };
      }

      backups.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      
      int totalSize = 0;
      for (final backup in backups) {
        totalSize += backup.size ?? 0;
      }

      return {
        'total_backups': backups.length,
        'total_size_bytes': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
        'oldest_backup': backups.last.createdTime.toIso8601String(),
        'newest_backup': backups.first.createdTime.toIso8601String(),
        'oldest_backup_name': backups.last.fileName,
        'newest_backup_name': backups.first.fileName,
      };
    } catch (e) {
      debugPrint('❌ خطأ في الحصول على إحصائيات النسخ: $e');
      return {};
    }
  }

  void dispose() {
    _driveApi = null;
    _backupFolderId = null;
  }
}
