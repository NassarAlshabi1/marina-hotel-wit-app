import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import '../utils/debug_logs.dart';
import '../utils/system_settings_keys.dart';
import 'auto_backup_task.dart';
import 'local_db.dart';
import 'restore_fix_service.dart';
import 'backup_serializers.dart';
import 'google_drive_logger.dart';
import 'alarm_backup.dart'; // Added for rescheduling upon setting sync
import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'appwrite_sync_manager.dart';
import 'appwrite_service.dart';

enum BackupFormat { json, sqlite }

class DriveBackupFile {
  final String fileId;
  final String fileName;
  final DateTime createdTime;
  final int? size;
  final Map<String, dynamic>? metadata;

  Map<String, String> get appProperties =>
      metadata?.map((k, v) => MapEntry(k, v.toString())) ?? {};

  BackupFormat get format {
    final raw = metadata?['format'] as String?;
    return BackupFormat.values.firstWhere(
      (f) => f.name == raw,
      orElse: () => BackupFormat.json,
    );
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
      size: file.size != null ? int.tryParse(file.size!) : null,
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
      appVersion: (json['app_version'] as String?) ?? '',
      databaseVersion: (json['database_version'] as num?)?.toInt() ?? 1,
      backupTimestamp: DateTime.parse(json['backup_timestamp'] as String),
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      deviceInfo: (json['device_info'] as String?) ?? '',
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
    _googleSignIn = GoogleSignIn(scopes: _scopes);
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
        _log('⚠️ فشل signInSilently أثناء تحديث الاعتماديات: $e');
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
        _log(
          '⚠️ تم فقد صلاحية رمز Google Drive، إعادة المحاولة بعد التحديث...',
        );
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

      _log('🔄 محاولة تسجيل الدخول الصامت...');
      GoogleSignInAccount? account = await _googleSignIn!.signInSilently();

      if (account == null) {
        _log('🔄 تسجيل الدخول الصامت فشل، بدء تسجيل الدخول التفاعلي...');
        account = await _googleSignIn!.signIn();
      }

      if (account != null) {
        _log('🔑 الحصول على رؤوس المصادقة...');
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);

        _log('✅ تم تسجيل الدخول بنجاح في Google Drive: ${account.email}');
        _log('🔧 النطاقات المطلوبة: ${_scopes.join(', ')}');
      } else {
        _log('⚠️ تم إلغاء تسجيل الدخول أو فشل');
      }

      return account;
    } catch (e) {
      final arabicError = _getArabicErrorMessage(e);
      _log('❌ خطأ في تسجيل الدخول في Google Drive: $arabicError');
      _log('❌ تفاصيل الخطأ التقنية: $e');

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

      _log('🔄 محاولة استعادة جلسة Google Drive...');
      final GoogleSignInAccount? account = await _googleSignIn!
          .signInSilently();

      if (account != null) {
        _log('🔑 الحصول على رؤوس المصادقة...');
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);

        _log('✅ تم استعادة جلسة Google Drive: ${account.email}');
        return account;
      } else {
        _log('ℹ️ لا توجد جلسة محفوظة');
        return null;
      }
    } catch (e) {
      _log('⚠️ فشلت استعادة الجلسة: $e');
      return null;
    }
  }

  /// محاولة تسجيل الدخول بهدوء للاستخدام في الخلفية (Alarm Callback)
  Future<bool> signInSilentlyIfNeeded() async {
    try {
      if (_googleSignIn == null) _initializeGoogleSignIn();
      final account = await _googleSignIn!.signInSilently();

      if (account != null) {
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);
        _log('✅ تم تسجيل الدخول بهدوء: ${account.email}');
        return true;
      }

      _log('⚠️ لا توجد جلسة محفوظة للدخول الهادئ');
      return false;
    } catch (e) {
      _log('❌ signInSilently error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _googleSignIn?.signOut();
      _driveApi = null;
      _backupFolderId = null;
      _log('✅ تم تسجيل الخروج من Google Drive');
      _logger.info('تم تسجيل الخروج من Google Drive', tag: 'AUTH');
    } catch (e) {
      _log('❌ خطأ في تسجيل الخروج: $e');
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
        final query =
            "name='$_backupFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
        final searchResult = await _driveApi!.files.list(q: query);

        if (searchResult.files != null && searchResult.files!.isNotEmpty) {
          _backupFolderId = searchResult.files!.first.id;
          _log('✅ تم العثور على مجلد النسخ الاحتياطية: $_backupFolderId');
        } else {
          final folder = drive.File()
            ..name = _backupFolderName
            ..mimeType = 'application/vnd.google-apps.folder';

          final createdFolder = await _driveApi!.files.create(folder);
          _backupFolderId = createdFolder.id;
          _log('✅ تم إنشاء مجلد النسخ الاحتياطية: $_backupFolderId');
        }

        return _backupFolderId!;
      } catch (e) {
        _log('❌ خطأ في إنشاء/العثور على مجلد النسخ الاحتياطية: $e');
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
      final salaryCyclesData = await db.select(db.salaryCycles).get();
      final salaryPaymentsData = await db.select(db.salaryPayments).get();
      final priceAdjustmentsData = await db.select(db.priceAdjustments).get();
      final bookingPriceAdjData = await db.select(db.bookingPriceAdjustments).get();
      final auditLogsData = await db.select(db.auditLogs).get();
      final paymentVoidsData = await db.select(db.paymentVoids).get();
      final guestInfosData = await db.select(db.guestInfos).get();
      final salaryWithdrawalsData = await db.select(db.salaryWithdrawals).get();

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
          salaryCyclesData.length +
          salaryPaymentsData.length +
          priceAdjustmentsData.length +
          bookingPriceAdjData.length +
          auditLogsData.length +
          paymentVoidsData.length +
          guestInfosData.length +
          salaryWithdrawalsData.length;

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
        'booking_nights': bookingNightsData
            .map((night) => night.toJson())
            .toList(),
        'hotel_day_ledger': ledgerData.map((entry) => entry.toJson()).toList(),
        'shift_notes': shiftNotesData.map((note) => note.toJson()).toList(),
        'employees': employeesData
            .map((employee) => employee.toJson())
            .toList(),
        'expenses': expensesData.map((expense) => expense.toJson()).toList(),
        'cash_transactions': cashTransactionsData
            .map((transaction) => transaction.toJson())
            .toList(),
        'payments': paymentsData.map((payment) => payment.toJson()).toList(),
        'debts': debtsData.map((debt) => debt.toJson()).toList(),
        'salary_cycles': salaryCyclesData
            .map((cycle) => cycle.toJson())
            .toList(),
        'salary_payments': salaryPaymentsData
            .map((payment) => payment.toJson())
            .toList(),
        'price_adjustments': priceAdjustmentsData
            .map((adj) => adj.toJson())
            .toList(),
        'booking_price_adjustments': bookingPriceAdjData
            .map((adj) => adj.toJson())
            .toList(),
        'audit_logs': auditLogsData
            .map((log) => log.toJson())
            .toList(),
        'payment_voids': paymentVoidsData
            .map((v) => v.toJson())
            .toList(),
        'guest_infos': guestInfosData
            .map((g) => g.toJson())
            .toList(),
        'salary_withdrawals': salaryWithdrawalsData
            .map((s) => s.toJson())
            .toList(),
      };

      _log('✅ تم تصدير البيانات: $totalRecords سجل');
      return backupData;
    } catch (e) {
      _log('❌ خطأ في تصدير البيانات: $e');
      rethrow;
    }
  }

  static const fullBackupPrefix = 'marina_backup_full_';
  static const autoSyncPrefix = 'marina_sync_auto_';
  static const deltaSyncPrefix = 'marina_sync_delta_';

  void _log(String message) {
    DebugLogs.add('DriveBackup', message);
    debugPrint(message);
  }

  Future<String> uploadBackup(
    Map<String, dynamic> backupData, {
    bool isSync = false,
  }) async {
    String? partialFileId;

    return _runWithAuth<String>(() async {
      try {
        final folderId = await getOrCreateBackupFolder();

        final jsonString = const JsonEncoder.withIndent(
          '  ',
        ).convert(backupData);
        final jsonBytes = utf8.encode(jsonString);

        final timestamp = DateTime.now();

        // تحديد البادئة والنوع حسب نوع النسخة
        final rawMetadata = backupData['metadata'];
        final metadata = rawMetadata is Map
            ? Map<String, dynamic>.from(rawMetadata)
            : <String, dynamic>{};
        final backupType = metadata['backup_type'] as String?;
        final syncType = metadata['sync_type'] as String?;

        String prefix;
        String typeLabel;

        if (isSync || syncType == 'push') {
          prefix = autoSyncPrefix;
          typeLabel = 'مزامنة تلقائية';
        } else if (backupType == 'auto') {
          prefix = autoSyncPrefix;
          typeLabel = 'نسخ تلقائي';
        } else {
          prefix = fullBackupPrefix;
          typeLabel = 'نسخة شاملة';
        }

        final fileName =
            '${prefix}${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.json';

        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId]
          ..appProperties = _buildAppProperties(metadata, timestamp);

        final media = drive.Media(Stream.value(jsonBytes), jsonBytes.length);

        _log(
          '📤 بدء رفع $typeLabel: $fileName (${(jsonBytes.length / 1024).toStringAsFixed(2)} KB)',
        );

        final uploadedFile = await _driveApi!.files.create(
          driveFile,
          uploadMedia: media,
        );

        partialFileId = uploadedFile.id;

        // التحقق من اكتمال الرفع
        final verifyResult = await _verifyUploadedBackup(
          uploadedFile.id!,
          jsonBytes.length,
        );
        if (!(verifyResult['is_complete'] as bool? ?? false)) {
          _log('⚠️ النسخة غير مكتملة: ${verifyResult['message']}');
          // حذف النسخة الناقصة
          await deleteBackupFile(uploadedFile.id!);
          throw Exception(
            'فشل في رفع النسخة بشكل كامل: ${verifyResult['message']}',
          );
        }

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_prefsLastBackupKey, timestamp.toIso8601String());

        _log('✅ تم رفع $typeLabel بنجاح: ${uploadedFile.id}');
        partialFileId = null; // تم بنجاح، لا حاجة للتنظيف
        return uploadedFile.id!;
      } catch (e) {
        _log('❌ خطأ في رفع النسخة الاحتياطية: $e');

        // حذف النسخة الجزئية إذا كانت موجودة
        if (partialFileId != null) {
          try {
            _log('🧹 حذف النسخة الجزئية: $partialFileId');
            await deleteBackupFile(partialFileId!);
          } catch (cleanupError) {
            _log('⚠️ فشل حذف النسخة الجزئية: $cleanupError');
          }
        }

        rethrow;
      }
    });
  }

  Future<String> uploadBackupWithName(
    String fileName,
    List<int> bytes, {
    Map<String, String>? appProperties,
  }) async {
    return _runWithAuth<String>(() async {
      final folderId = await getOrCreateBackupFolder();
      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..appProperties = appProperties ?? {};
      final media = drive.Media(Stream.value(bytes), bytes.length);
      _log(
        '📤 رفع ملف مزامنة: $fileName (${(bytes.length / 1024).toStringAsFixed(2)} KB)',
      );
      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );
      _log('✅ تم رفع الملف: ${uploadedFile.id}');
      return uploadedFile.id!;
    });
  }

  Future<void> deleteBackup(String fileId) => deleteBackupFile(fileId);

  /// التحقق من اكتمال النسخة المرفوعة
  Future<Map<String, dynamic>> _verifyUploadedBackup(
    String fileId,
    int expectedSize,
  ) async {
    try {
      final file =
          await _driveApi!.files.get(
                fileId,
                $fields: 'id,name,size,appProperties',
              )
              as drive.File;

      final actualSize = file.size != null ? int.tryParse(file.size!) ?? 0 : 0;

      // التحقق من الحجم (يسمح بفارق 1% بسبب الضغط)
      final sizeDifference = (actualSize - expectedSize).abs();
      final maxAllowedDifference = expectedSize * 0.01; // 1%

      if (sizeDifference > maxAllowedDifference) {
        return {
          'is_complete': false,
          'message':
              'حجم الملف غير متطابق (متوقع: $expectedSize، فعلي: $actualSize)',
          'actual_size': actualSize,
          'expected_size': expectedSize,
        };
      }

      // التحقق من البيانات الوصفية
      if (file.appProperties == null || file.appProperties!.isEmpty) {
        return {'is_complete': false, 'message': 'البيانات الوصفية مفقودة'};
      }

      return {
        'is_complete': true,
        'message': 'النسخة مكتملة',
        'actual_size': actualSize,
      };
    } catch (e) {
      return {'is_complete': false, 'message': 'فشل التحقق: $e'};
    }
  }

  Map<String, String> _buildAppProperties(
    Map<String, dynamic> metadata,
    DateTime timestamp,
  ) {
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

      // البحث عن جميع أنواع النسخ الاحتياطية (الشاملة والتلقائية والتفاضلية)
      final query =
          "parents in '$folderId' and (name contains '$fullBackupPrefix' or name contains '$autoSyncPrefix' or name contains '$deltaSyncPrefix' or name contains '$_backupFilePrefix') and trashed=false";
      final allFiles = <drive.File>[];
      String? pageToken;
      do {
        final response = await _driveApi!.files.list(
          q: query,
          orderBy: 'createdTime desc',
          spaces: 'drive',
          pageToken: pageToken,
          $fields:
              'nextPageToken,files(id,name,createdTime,size,appProperties)',
        );
        if (response.files != null) {
          allFiles.addAll(response.files!);
        }
        pageToken = response.nextPageToken;
      } while (pageToken != null);

      final backupFiles = allFiles.map(DriveBackupFile.fromDriveFile).toList();

      _log('✅ تم جلب ${backupFiles.length} نسخة احتياطية');
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
      final media =
          await _driveApi!.files.get(
                fileId,
                downloadOptions: drive.DownloadOptions.fullMedia,
              )
              as drive.Media;

      final List<int> dataStore = [];
      await for (final data in media.stream) {
        dataStore.addAll(data);
      }

      final jsonString = utf8.decode(dataStore);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      _log('✅ تم تنزيل النسخة الاحتياطية: $fileId');
      return backupData;
    });
  }

  Future<void> restoreFromBackup(Map<String, dynamic> backupData) async {
    if (!DatabaseManager.isRestoring) {
      // Self-guard to avoid accidental destructive calls while keeping safety
      return DatabaseManager.runWithRestoreGuard(
        () => _restoreFromBackupInternal(backupData),
      );
    }
    return _restoreFromBackupInternal(backupData);
  }

  Future<void> _restoreFromBackupInternal(
    Map<String, dynamic> backupData,
  ) async {
    try {
      final db = DatabaseManager.instance;
      final adapterRegistry = AdapterRegistry(db);

      if (!backupData.containsKey('metadata')) {
        _log('⚠️ النسخة الاحتياطية لا تحتوي على بيانات وصفية، سيتم تجاوزها');
        _logger.warning(
          'Skipping restore: backup missing metadata',
          tag: 'RESTORE',
        );
        return;
      }

      final metadataJson = backupData['metadata'];
      if (metadataJson is! Map) {
        _log('⚠️ صيغة بيانات النسخة الاحتياطية غير صالحة، سيتم تجاوزها');
        _logger.warning(
          'Skipping restore: invalid metadata format',
          tag: 'RESTORE',
        );
        return;
      }
      final metadata = BackupMetadata.fromJson(
        Map<String, dynamic>.from(metadataJson),
      );
      _logger.info(
        'بدء استعادة نسخة بتاريخ ${metadata.backupTimestamp.toIso8601String()} تحتوي ${metadata.totalRecords} سجل',
        tag: 'RESTORE',
      );

      if (metadata.databaseVersion > DatabaseManager.instance.schemaVersion) {
        throw Exception(
          'إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي',
        );
      }

      _log('🔄 بدء استعادة البيانات...');

      await db.transaction(() async {
        await db.customStatement('PRAGMA foreign_keys = OFF');
        try {
          // حذف جميع الجداول (الأبناء أولاً لتجنب قيود المفاتيح الأجنبية)
          await db.delete(db.bookingNotes).go();
          await db.delete(db.bookingNights).go();
          await db.delete(db.payments).go();
          await db.delete(db.debts).go();
          await db.delete(db.bookingPriceAdjustments).go();
          await db.delete(db.bookings).go();
          await db.delete(db.rooms).go();
          await db.delete(db.salaryPayments).go();
          await db.delete(db.salaryCycles).go();
          await db.delete(db.integrityViolations).go();
          await db.delete(db.autoFixRuns).go();
          await db.delete(db.syncConflicts).go();
          await db.delete(db.syncLog).go();
          await db.delete(db.syncQueue).go();
          await db.delete(db.syncState).go();
          await db.delete(db.restoreFixLog).go();
          await db.delete(db.appSessions).go();
          await db.delete(db.hotelDayLedger).go();
          await db.delete(db.shiftNotes).go();
          await db.delete(db.employees).go();
          await db.delete(db.expenses).go();
          await db.delete(db.cashTransactions).go();
          await db.delete(db.auditLogs).go();
          await db.delete(db.paymentVoids).go();
          await db.delete(db.guestInfos).go();
          await db.delete(db.salaryWithdrawals).go();

          // استعادة البيانات بالترتيب الصحيح (الجداول الرئيسية أولاً)
          if (backupData.containsKey('rooms')) {
            final roomsData = backupData['rooms'] as List<dynamic>;
            for (final roomJson in roomsData) {
              await adapterRegistry.rooms.upsertFromJson(
                Map<String, dynamic>.from(roomJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('bookings')) {
            final bookingsData = backupData['bookings'] as List<dynamic>;
            for (final bookingJson in bookingsData) {
              await adapterRegistry.bookings.upsertFromJson(
                Map<String, dynamic>.from(bookingJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('booking_notes')) {
            final notesData = backupData['booking_notes'] as List<dynamic>;
            for (final noteJson in notesData) {
              await adapterRegistry.bookingNotes.upsertFromJson(
                Map<String, dynamic>.from(noteJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('booking_nights')) {
            final nightsData = backupData['booking_nights'] as List<dynamic>;
            for (final nightJson in nightsData) {
              await adapterRegistry.nights.upsertFromJson(
                Map<String, dynamic>.from(nightJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('hotel_day_ledger')) {
            final ledgerList = backupData['hotel_day_ledger'] as List<dynamic>;
            for (final ledgerJson in ledgerList) {
              final map = Map<String, dynamic>.from(ledgerJson as Map);
              final data = HotelDayLedgerEntry.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.hotelDayLedger).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('shift_notes')) {
            final shiftsData = backupData['shift_notes'] as List<dynamic>;
            for (final shiftJson in shiftsData) {
              final map = Map<String, dynamic>.from(shiftJson as Map);
              final data = ShiftNote.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.shiftNotes).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('employees')) {
            final employeesData = backupData['employees'] as List<dynamic>;
            for (final employeeJson in employeesData) {
              await adapterRegistry.employees.upsertFromJson(
                Map<String, dynamic>.from(employeeJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('expenses')) {
            final expensesData = backupData['expenses'] as List<dynamic>;
            for (final expenseJson in expensesData) {
              await adapterRegistry.expenses.upsertFromJson(
                Map<String, dynamic>.from(expenseJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('cash_transactions')) {
            final transactionsData =
                backupData['cash_transactions'] as List<dynamic>;
            for (final transactionJson in transactionsData) {
              final map = Map<String, dynamic>.from(transactionJson as Map);
              final data = CashTransaction.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.cashTransactions).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('payments')) {
            final paymentsData = backupData['payments'] as List<dynamic>;
            for (final paymentJson in paymentsData) {
              await adapterRegistry.payments.upsertFromJson(
                Map<String, dynamic>.from(paymentJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('debts')) {
            final debtsList = backupData['debts'] as List<dynamic>;
            for (final debtJson in debtsList) {
              await adapterRegistry.debts.upsertFromJson(
                Map<String, dynamic>.from(debtJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('auto_fix_runs')) {
            final runsList = backupData['auto_fix_runs'] as List<dynamic>;
            for (final runJson in runsList) {
              final map = Map<String, dynamic>.from(runJson as Map);
              final data = AutoFixRun.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.autoFixRuns).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('integrity_violations')) {
            final violationsList =
                backupData['integrity_violations'] as List<dynamic>;
            for (final violationJson in violationsList) {
              final map = Map<String, dynamic>.from(violationJson as Map);
              final data = IntegrityViolation.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db
                  .into(db.integrityViolations)
                  .insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('app_sessions')) {
            final sessionsList = backupData['app_sessions'] as List<dynamic>;
            for (final sessionJson in sessionsList) {
              final map = Map<String, dynamic>.from(sessionJson as Map);
              final data = AppSession.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.appSessions).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('salary_cycles')) {
            final cyclesList = backupData['salary_cycles'] as List<dynamic>;
            for (final cycleJson in cyclesList) {
              await adapterRegistry.salaryCycles.upsertFromJson(
                Map<String, dynamic>.from(cycleJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('salary_payments')) {
            final salaryList = backupData['salary_payments'] as List<dynamic>;
            for (final salaryJson in salaryList) {
              await adapterRegistry.salaryPayments.upsertFromJson(
                Map<String, dynamic>.from(salaryJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('salary_withdrawals')) {
            final withdrawalsList = backupData['salary_withdrawals'] as List<dynamic>;
            for (final wJson in withdrawalsList) {
              await adapterRegistry.salaryWithdrawals.upsertFromJson(
                Map<String, dynamic>.from(wJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('price_adjustments')) {
            final adjList = backupData['price_adjustments'] as List<dynamic>;
            for (final adjJson in adjList) {
              await adapterRegistry.priceAdjustments.upsertFromJson(
                Map<String, dynamic>.from(adjJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('booking_price_adjustments')) {
            final bpaList = backupData['booking_price_adjustments'] as List<dynamic>;
            for (final bpaJson in bpaList) {
              await adapterRegistry.bookingPriceAdjustments.upsertFromJson(
                Map<String, dynamic>.from(bpaJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('audit_logs')) {
            final logsList = backupData['audit_logs'] as List<dynamic>;
            for (final logJson in logsList) {
              await adapterRegistry.auditLogs.upsertFromJson(
                Map<String, dynamic>.from(logJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('payment_voids')) {
            final voidsList = backupData['payment_voids'] as List<dynamic>;
            for (final voidJson in voidsList) {
              await adapterRegistry.paymentVoids.upsertFromJson(
                Map<String, dynamic>.from(voidJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('guest_infos')) {
            final guestList = backupData['guest_infos'] as List<dynamic>;
            for (final guestJson in guestList) {
              await adapterRegistry.guestInfos.upsertFromJson(
                Map<String, dynamic>.from(guestJson as Map),
                src: Source.drive,
              );
            }
          }

          if (backupData.containsKey('restore_fix_log')) {
            final restoreList = backupData['restore_fix_log'] as List<dynamic>;
            for (final logJson in restoreList) {
              final map = Map<String, dynamic>.from(logJson as Map);
              final data = RestoreFixLogData.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.restoreFixLog).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('sync_queue')) {
            final queueList = backupData['sync_queue'] as List<dynamic>;
            for (final rowJson in queueList) {
              final map = Map<String, dynamic>.from(rowJson as Map);
              final data = SyncQueueData.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.syncQueue).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('sync_logs') ||
              backupData.containsKey('sync_log')) {
            final logList = backupData.containsKey('sync_logs')
                ? backupData['sync_logs'] as List<dynamic>
                : backupData['sync_log'] as List<dynamic>;
            for (final logJson in logList) {
              final map = Map<String, dynamic>.from(logJson as Map);
              final data = SyncLogData.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.syncLog).insertOnConflictUpdate(data);
            }
          }

          if (backupData.containsKey('sync_conflicts')) {
            final conflictsList = backupData['sync_conflicts'] as List<dynamic>;
            for (final conflictJson in conflictsList) {
              final map = Map<String, dynamic>.from(conflictJson as Map);
              final data = SyncConflictRow.fromJson(
                map,
                serializer: lenientValueSerializer,
              );
              await db.into(db.syncConflicts).insertOnConflictUpdate(data);
            }
          }

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

          // استعادة وتطبيق الإعدادات العامة إذا وجدت
          if (backupData.containsKey('system_settings')) {
            _log('⚙️ تطبيق إعدادات النظام من النسخة الاحتياطية...');
            try {
              final rawSettings = backupData['system_settings'];
              if (rawSettings is! Map) {
                throw Exception('صيغة إعدادات النظام غير صالحة');
              }
              final settings = Map<String, dynamic>.from(rawSettings);
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
                    _log('   UPDATED: $key = $val');
                  }
                }
              }

              // إعادة جدولة المهام إذا تغيرت الإعدادات
              if (settingsChanged) {
                _log(
                  '🔄 إعادة جدولة مهام النسخ الاحتياطي وفق الإعدادات الجديدة...',
                );

                final timeStr = prefs.getString('auto_backup_time') ?? '21:00';
                final parts = timeStr.split(':');
                final parsedHour = parts.isNotEmpty
                    ? int.tryParse(parts[0])
                    : null;
                final parsedMinute = parts.length > 1
                    ? int.tryParse(parts[1])
                    : null;

                final hour = (parsedHour ?? 21).clamp(0, 23);
                final minute = (parsedMinute ?? 0).clamp(0, 59);
                final scheduledEnabled =
                    prefs.getBool('scheduled_backup_enabled') ?? true;

                if (scheduledEnabled) {
                  await AlarmBackup.rescheduleDaily(hour, minute);
                  await AutoBackupTask.scheduleDaily(time: timeStr);
                } else {
                  await AlarmBackup.cancelAlarm();
                  await AutoBackupTask.cancelScheduled();
                }
              }
            } catch (e) {
              _log('⚠️ خطأ في تطبيق الإعدادات المستعادة: $e');
            }
          }

          _log('✅ تم استعادة ${metadata.totalRecords} سجل بنجاح');
          final fixService = RestoreFixService(db);
          await fixService.runAutoFixAfterRestore(
            backupTimestamp: metadata.backupTimestamp,
          );
        } finally {
          await db.customStatement('PRAGMA foreign_keys = ON');
          _log('🔓 تم إعادة تشغيل FOREIGN KEYS');

          // التحقق من سلامة Foreign Keys بعد الاستعادة
          try {
            final violations = await db.customSelect(
              'PRAGMA foreign_key_check',
            ).get();
            if (violations.isNotEmpty) {
              _log('⚠️ تحذير: تم العثور على ${violations.length} انتهاك FK بعد الاستعادة');
              for (final v in violations) {
                _log('  ↳ FK violation: $v');
              }
            } else {
              _log('✅ التحقق من FK: لا توجد انتهاكات');
            }
          } catch (e) {
            _log('⚠️ تعذر التحقق من سلامة FK: $e');
          }
        }
      });

      // مزامنة البيانات المستعادة مع Appwrite
      try {
        _log('🔄 بدء مزامنة البيانات مع Appwrite...');
        final prefs = await SharedPreferences.getInstance();
        final syncEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;

        if (syncEnabled) {
          final appwriteService = AppwriteService();
          await appwriteService.initialize();

          if (appwriteService.isInitialized) {
            final syncManager = AppwriteSyncManager(
              appwriteService: appwriteService,
              database: db,
            );

            final stats = await syncManager.pushAllLocalDataToAppwrite(
              skipDeleted: true,
            );

            final totalSynced = stats.entries
                .where((e) => e.key != 'errors' && e.value > 0)
                .fold(0, (sum, e) => sum + e.value);

            final tablesSummary = stats.entries
                .where((e) => e.key != 'errors' && e.value > 0)
                .map((e) => '${e.key}: ${e.value}')
                .join(', ');

            _log('✅ تم رفع $totalSynced سجل إلى Appwrite ($tablesSummary)');
            if (stats['errors']! > 0) {
              _log('⚠️ ${stats['errors']} خطأ أثناء المزامنة');
            }
            _logger.info(
              'تمت مزامنة البيانات مع Appwrite: $totalSynced سجل (${stats['errors']} خطأ)',
              tag: 'RESTORE',
            );
          } else {
            _log('⚠️ Appwrite غير متاح، تم تخطي المزامنة');
            _logger.warning(
              'تم تخطي مزامنة Appwrite (غير متصل)',
              tag: 'RESTORE',
            );
          }
        } else {
          _log('ℹ️ مزامنة Appwrite معطلة');
        }
      } catch (e, st) {
        _log('⚠️ خطأ في مزامنة Appwrite: $e');
        _logger.warning(
          'فشلت مزامنة Appwrite بعد الاستعادة: $e',
          tag: 'RESTORE',
        );
        debugPrint('Stack trace: $st');
      }
    } catch (e) {
      _log('❌ خطأ في استعادة البيانات: $e');
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

      _log('✅ تم جدولة النسخ التلقائي: $frequency في $timeString');
    } catch (e) {
      _log('❌ خطأ في جدولة النسخ التلقائي: $e');
    }
  }

  Future<void> cancelAutoBackup() async {
    try {
      await Workmanager().cancelByUniqueName(AutoBackupTask.taskId);
      _log('✅ تم إلغاء النسخ التلقائي');
    } catch (e) {
      _log('❌ خطأ في إلغاء النسخ التلقائي: $e');
    }
  }

  Future<void> performAutoBackup() async {
    try {
      if (!isSignedIn) {
        _log('⚠️ المستخدم غير مسجل دخول، تم تخطي النسخ التلقائي');
        return;
      }

      _log('🔄 بدء النسخ التلقائي...');

      final backupData = await exportDatabaseToJson();
      final fileId = await uploadBackup(backupData);

      _log('✅ تم النسخ التلقائي بنجاح: $fileId');
    } catch (e) {
      _log('❌ خطأ في النسخ التلقائي: $e');
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
      _log('❌ خطأ في تقدير حجم قاعدة البيانات: $e');
      return 0;
    }
  }

  Future<void> deleteBackupFile(String fileId) async {
    await _runWithAuth<void>(() async {
      await _driveApi!.files.delete(fileId);
      _log('🗑️ تم حذف النسخة الاحتياطية: $fileId');
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
      _log('🧹 بدء تنظيف النسخ القديمة...');
      _log(
        '📊 الإعدادات: maxBackups=$maxBackupsToKeep, maxAge=$maxAgeInDays أيام, dryRun=$dryRun',
      );

      // الحصول على جميع النسخ الاحتياطية
      final backups = await listBackups();

      if (backups.isEmpty) {
        _log('✅ لا توجد نسخ احتياطية للتنظيف');
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
        _log('✅ جميع النسخ ضمن الحدود المقبولة');
        return 0;
      }

      _log('📋 سيتم حذف ${backupsToDelete.length} نسخة احتياطية:');
      for (final backup in backupsToDelete) {
        final age = now.difference(backup.createdTime).inDays;
        final sizeKB = backup.size != null
            ? (backup.size! / 1024).toStringAsFixed(2)
            : 'غير معروف';
        _log('  - ${backup.fileName} (عمر: $age يوم، حجم: $sizeKB KB)');
      }

      // حذف النسخ فعلياً (إلا إذا كان dryRun)
      int deletedCount = 0;
      if (!dryRun) {
        for (final backup in backupsToDelete) {
          try {
            await deleteBackupFile(backup.fileId);
            deletedCount++;
          } catch (e) {
            _log('⚠️ فشل حذف النسخة ${backup.fileName}: $e');
          }
        }
        _log('✅ تم حذف $deletedCount نسخة احتياطية بنجاح');
      } else {
        _log('ℹ️ وضع المعاينة (dryRun) - لم يتم حذف أي شيء فعلياً');
        deletedCount = backupsToDelete.length;
      }

      // حساب المساحة المحررة
      if (deletedCount > 0 && !dryRun) {
        int totalSizeFreed = 0;
        for (final backup in backupsToDelete) {
          totalSizeFreed += backup.size ?? 0;
        }
        final sizeMB = (totalSizeFreed / (1024 * 1024)).toStringAsFixed(2);
        _log('💾 المساحة المحررة: $sizeMB MB');
      }

      return deletedCount;
    } catch (e) {
      _log('❌ خطأ في تنظيف النسخ القديمة: $e');
      rethrow;
    }
  }

  /// فحص وحذف النسخ الناقصة (التي فشل رفعها)
  ///
  /// Returns: عدد النسخ الناقصة التي تم حذفها
  Future<int> cleanupIncompleteBackups() async {
    try {
      _log('🔍 بدء فحص النسخ الناقصة...');
      _logger.info('بدء فحص النسخ الناقصة', tag: 'VALIDATE');

      final backups = await listBackups();

      if (backups.isEmpty) {
        _log('✅ لا توجد نسخ للفحص');
        _logger.info('لا توجد نسخ لفحصها', tag: 'VALIDATE');
        return 0;
      }

      final incompleteBackups = <DriveBackupFile>[];

      for (final backup in backups) {
        // التحقق من البيانات الوصفية
        if (backup.metadata == null || backup.metadata!.isEmpty) {
          _log('⚠️ نسخة بدون بيانات وصفية: ${backup.fileName}');
          incompleteBackups.add(backup);
          continue;
        }

        // التحقق من الحجم (النسخ الصغيرة جداً قد تكون ناقصة)
        if (backup.size != null && backup.size! < 1024) {
          // أقل من 1 KB
          _log('⚠️ نسخة صغيرة جداً (${backup.size} bytes): ${backup.fileName}');
          incompleteBackups.add(backup);
          continue;
        }

        // محاولة تنزيل وفك تشفير النسخة للتحقق
        try {
          final data = await downloadBackup(backup.fileId);

          // التحقق من البنية الأساسية
          if (!data.containsKey('metadata') || !data.containsKey('rooms')) {
            _log('⚠️ نسخة ببنية غير صحيحة: ${backup.fileName}');
            incompleteBackups.add(backup);
            continue;
          }
        } catch (e) {
          _log('⚠️ فشل قراءة النسخة (قد تكون تالفة): ${backup.fileName} - $e');
          incompleteBackups.add(backup);
          continue;
        }
      }

      if (incompleteBackups.isEmpty) {
        _log('✅ جميع النسخ سليمة');
        _logger.info('جميع النسخ سليمة بعد الفحص', tag: 'VALIDATE');
        return 0;
      }

      _log('📋 تم اكتشاف ${incompleteBackups.length} نسخة ناقصة:');
      for (final backup in incompleteBackups) {
        _log('  - ${backup.fileName}');
      }

      // حذف النسخ الناقصة
      int deletedCount = 0;
      for (final backup in incompleteBackups) {
        try {
          await deleteBackupFile(backup.fileId);
          deletedCount++;
        } catch (e) {
          _log('⚠️ فشل حذف النسخة الناقصة ${backup.fileName}: $e');
        }
      }

      _log('✅ تم حذف $deletedCount نسخة ناقصة');
      return deletedCount;
    } catch (e) {
      _log('❌ خطأ في فحص النسخ الناقصة: $e');
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
      _log('❌ خطأ في الحصول على إحصائيات النسخ: $e');
      return {};
    }
  }

  void dispose() {
    _driveApi = null;
    _backupFolderId = null;
  }
}
