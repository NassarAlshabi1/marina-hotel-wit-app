// TODO(phase-2): remove this ignore and fix violations (avoid_dynamic_calls)
// ignore_for_file: avoid_dynamic_calls
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:workmanager/workmanager.dart';

import '../utils/debug_logs.dart';
import '../utils/system_settings_keys.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'alarm_backup.dart'; // Added for rescheduling upon setting sync
import 'appwrite_service.dart';
import 'appwrite_sync_manager.dart';
import 'auto_backup_task.dart';
import 'backup_serializers.dart';
import 'google_drive_logger.dart';
import 'google_drive_sign_in_manager.dart';
import 'local_db.dart';
import 'restore_fix_service.dart';
import 'sqlite_backup_restore.dart';

enum BackupFormat { json, sqlite }

class DriveBackupFile {
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
  final String fileId;
  final String fileName;
  final DateTime createdTime;
  final int? size;
  final Map<String, dynamic>? metadata;

  Map<String, String> get appProperties =>
      metadata?.map((k, v) => MapEntry(k, v.toString())) ?? {};

  /// تحديد صيغة النسخة من اسم الملف أو metadata
  BackupFormat get format {
    final raw = metadata?['format'] as String?;

    // التحقق من اسم الملف أولاً (للتوافق مع النسخ القديمة)
    if (fileName.endsWith('.db') || fileName.startsWith('db_backup_')) {
      return BackupFormat.sqlite;
    }

    // التحقق من metadata
    if (raw == 'sqlite' || raw == 'db') {
      return BackupFormat.sqlite;
    }

    return BackupFormat.json;
  }
}

class BackupMetadata {
  BackupMetadata({
    required this.appVersion,
    required this.databaseVersion,
    required this.backupTimestamp,
    required this.totalRecords,
    required this.deviceInfo,
    this.format = BackupFormat.json,
    this.dataHash,
  });

  factory BackupMetadata.fromJson(Map<String, dynamic> json) {
    final rawFormat = json['format'] as String?;
    // Handle 'db' format as sqlite
    final formatName = rawFormat == 'db' ? 'sqlite' : rawFormat;
    final format = BackupFormat.values.firstWhere(
      (value) => value.name == formatName,
      orElse: () => BackupFormat.json,
    );
    return BackupMetadata(
      appVersion: (json['app_version'] as String?) ?? '',
      databaseVersion: (json['database_version'] as num?)?.toInt() ?? 1,
      backupTimestamp: DateTime.parse(json['backup_timestamp'] as String),
      totalRecords: (json['total_records'] as num?)?.toInt() ?? 0,
      deviceInfo: (json['device_info'] as String?) ?? '',
      format: format,
      dataHash: json['data_hash'] as String?,
    );
  }
  final String appVersion;
  final int databaseVersion;
  final DateTime backupTimestamp;
  final int totalRecords;
  final String deviceInfo;
  final BackupFormat format;

  /// تجزئة SHA-256 للتحقق من سلامة بيانات النسخة الاحتياطية
  final String? dataHash;

  Map<String, dynamic> toJson() => {
    'app_version': appVersion,
    'database_version': databaseVersion,
    'backup_timestamp': backupTimestamp.toIso8601String(),
    'total_records': totalRecords,
    'device_info': deviceInfo,
    'format': format.name,
    if (dataHash != null) 'data_hash': dataHash,
  };
}

class GoogleAuthClient extends http.BaseClient {
  GoogleAuthClient(this._headers) : _client = http.Client();
  final Map<String, String> _headers;
  final http.Client _client;

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
  GoogleDriveBackupService();
  static const String _backupFolderName = 'MarinaHotelBackups';
  static const String _backupFilePrefix = 'marina_hotel_backup_';
  // الصلاحيات مُعرَّفة في GoogleDriveSignInManager كنسخة موحّدة

  /// تحويل رموز خطأ Google Sign-In إلى رسائل عربية واضحة
  static String _getArabicErrorMessage(Object error) {
    if (error is PlatformException) {
      switch (error.code) {
        case 'sign_in_failed':
          if (error.message?.contains('10') ?? false) {
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

  /// كائن GoogleSignIn الموحّد — يُشاركه جميع الخدمات
  final GoogleDriveSignInManager _signInManager =
      GoogleDriveSignInManager.instance;
  drive.DriveApi? _driveApi;
  // ✅ مولد أرقام عشوائية لـ jitter في backoff
  final math.Random _random = math.Random();
  String? _backupFolderId;
  final GoogleDriveLogger _logger = GoogleDriveLogger();

  Future<void> _ensureDriveClient() async {
    GoogleSignInAccount? account = _signInManager.currentUser;
    if (account == null) {
      try {
        account = await _signInManager.signInSilently();
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

  /// ✅ إصلاح حرج (audit agent-8 H1):
  /// 1. await على المحاولة الثانية (كان `return action();` بدون await →
  ///    أخطاء المحاولة الثانية تُفقد صامتة)
  /// 2. إضافة backoff لـ 429 (rate limit) و 503 (server error)
  /// 3. إضافة 403 (forbidden) لمحاولة تحديث الاعتماديات
  Future<T> _runWithAuth<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
  }) async {
    await _ensureDriveClient();
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on drive.DetailedApiRequestError catch (e) {
        final isAuthError = e.status == 401 || e.status == 403;
        final isRateLimit = e.status == 429 || e.status == 503;
        if (!isAuthError && !isRateLimit) rethrow;
        if (attempt == maxAttempts) rethrow;
        _log(
          '⚠️ Drive API ${e.status} (محاولة $attempt/$maxAttempts)، '
          'إعادة المحاولة بعد backoff...',
        );
        _driveApi = null;
        if (isAuthError) {
          await _ensureDriveClient();
        } else {
          // Exponential backoff مع jitter لـ 429/503
          // 500ms, 1000ms, 2000ms... + jitter عشوائي 0-250ms
          final delayMs = (500 * (1 << (attempt - 1))) + _random.nextInt(250);
          await Future<void>.delayed(Duration(milliseconds: delayMs));
        }
      }
    }
    throw StateError('unreachable');
  }

  Future<GoogleSignInAccount?> signInForDrive() async {
    try {
      _log('🔄 محاولة تسجيل الدخول الصامت...');
      GoogleSignInAccount? account = await _signInManager.signInSilently();

      if (account == null) {
        _log('🔄 تسجيل الدخول الصامت فشل، بدء تسجيل الدخول التفاعلي...');
        account = await _signInManager.signIn();
      }

      if (account != null) {
        _log('🔑 الحصول على رؤوس المصادقة...');
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);

        _log('✅ تم تسجيل الدخول بنجاح في Google Drive: ${account.email}');
        _log('🔧 النطاقات المطلوبة: ${kGoogleDriveScopes.join(', ')}');
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
      _log('🔄 محاولة استعادة جلسة Google Drive...');
      final GoogleSignInAccount? account = await _signInManager
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
      final account = await _signInManager.signInSilently();

      if (account != null) {
        final headers = await account.authHeaders;
        final client = GoogleAuthClient(headers);
        _driveApi = drive.DriveApi(client);
        _log('✅ تم تسجيل الدخول بهدوء: ${account.email}');
        return true;
      }

      _log('⚠️ لا توجد جلسة محفوظة للدخول الهادئ');
      return false;
    } catch (e, st) {
      _log('❌ signInSilently error: $e');
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _signInManager.signOut();
      _driveApi = null;
      _backupFolderId = null;
      _log('✅ تم تسجيل الخروج من Google Drive');
      _logger.info('تم تسجيل الخروج من Google Drive', tag: 'AUTH');
    } catch (e) {
      _log('❌ خطأ في تسجيل الخروج: $e');
      rethrow;
    }
  }

  GoogleSignInAccount? get currentUser => _signInManager.currentUser;
  GoogleSignIn get googleSignIn => _signInManager.client;

  bool get isSignedIn => _signInManager.isSignedIn;

  Future<String> getOrCreateBackupFolder() async {
    if (_backupFolderId != null) {
      return _backupFolderId!;
    }

    return _runWithAuth<String>(() async {
      if (_backupFolderId != null) {
        return _backupFolderId!;
      }

      try {
        const query =
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

      // تحميل البيانات على دفعات لتجنب استهلاك الذاكرة في قواعد البيانات الكبيرة
      final roomsData = await _loadTableBatched<dynamic>(db.rooms);
      final bookingsData = await _loadTableBatched<dynamic>(db.bookings);
      final bookingNotesData = await _loadTableBatched<dynamic>(
        db.bookingNotes,
      );
      final bookingNightsData = await _loadTableBatched<dynamic>(
        db.bookingNights,
      );
      final ledgerData = await _loadTableBatched<dynamic>(db.hotelDayLedger);
      final shiftNotesData = await _loadTableBatched<dynamic>(db.shiftNotes);
      final employeesData = await _loadTableBatched<dynamic>(db.employees);
      final expensesData = await _loadTableBatched<dynamic>(db.expenses);
      final cashTransactionsData = await _loadTableBatched<dynamic>(
        db.cashTransactions,
      );
      final paymentsData = await _loadTableBatched<dynamic>(db.payments);
      final debtsData = await _loadTableBatched<dynamic>(db.debts);
      final salaryCyclesData = await _loadTableBatched<dynamic>(
        db.salaryCycles,
      );
      final salaryPaymentsData = await _loadTableBatched<dynamic>(
        db.salaryPayments,
      );
      final priceAdjustmentsData = await _loadTableBatched<dynamic>(
        db.priceAdjustments,
      );
      final bookingPriceAdjData = await _loadTableBatched<dynamic>(
        db.bookingPriceAdjustments,
      );
      final auditLogsData = await _loadTableBatched<dynamic>(db.auditLogs);
      final paymentVoidsData = await _loadTableBatched<dynamic>(
        db.paymentVoids,
      );
      final guestInfosData = await _loadTableBatched<dynamic>(db.guestInfos);
      final salaryWithdrawalsData = await _loadTableBatched<dynamic>(
        db.salaryWithdrawals,
      );
      final salaryCarryOverLogsData = await _loadTableBatched<dynamic>(
        db.salaryCarryOverLogs,
      );

      // استخراج عناصر القائمة السوداء بشكل منفصل (createdBy = 'blacklist')
      final blacklistQuery = db.select(db.shiftNotes)
        ..where((t) => t.createdBy.equals('blacklist'));
      final blacklistData = await blacklistQuery.get();

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
        salaryCarryOverLogsData: salaryCarryOverLogsData,
      );

      final totalRecords = tableData.totalRecords + blacklistData.length;

      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: DatabaseManager.instance.schemaVersion,
        backupTimestamp: DateTime.now(),
        totalRecords: totalRecords,
        deviceInfo: Platform.isAndroid ? 'Android' : 'iOS',
      );

      // إعدادات الواتساب من SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      final whatsappSettings = <String, dynamic>{};
      const waKeys = [
        'wa_api_type',
        'wa_api_base_url',
        'wa_api_instance_id',
        'wa_api_token',
        'wa_custom_url_template',
      ];
      for (final key in waKeys) {
        final value = prefs.getString(key);
        if (value != null && value.isNotEmpty) {
          whatsappSettings[key] = value;
        }
      }

      // ✅ إصلاح P3-15: دمج JSON serialization + FK enrichment + SHA-256 hash
      // في Isolate واحد بدلاً من isolate منفصل للـ hash فقط.
      //
      // السبب: buildBackupDataMap تُنفّذ .toJson() لكل صف من ~21 جدول (~8K صف
      // في الإنتاج)، وهذا كان يحدث على الـ main isolate قبل هذا الإصلاح،
      // مما يسبب ~85-120ms من jank في الـ UI أثناء النسخ الاحتياطي.
      //
      // الحل: نقل buildBackupDataMap + _enrichBackupWithFKUuids + SHA-256
      // بالكامل إلى isolate واحد. هذا آمن لأن:
      // 1. جميع Drift row classes هي POD (plain old data) — لا تحمل أي
      //    مراجع إلى كائن Database أو native handles
      // 2. BackupTableData/BackupMetadata هي كائنات بسيطة قابلة للتمرير
      // 3. _enrichBackupWithFKUuids لا يحتاج DB — يعمل فقط على البيانات المحلية
      // 4. Map insertion order محفوظ عبر isolate ports → SHA-256 متطابق
      //
      // النتيجة: ~65-100ms توفير في CPU على main isolate، مع hash متطابق
      // مع النسخ القديمة (backward compatible).
      final metadataJson = metadata.toJson();
      final backupData = await Isolate.run(() {
        // 1. بناء خريطة النسخ الاحتياطي (يشمل .toJson() لكل صف)
        final data = buildBackupDataMap(
          metadata: metadataJson,
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
          salaryCarryOverLogsData: salaryCarryOverLogsData,
          blacklistData: blacklistData,
          whatsappSettings: whatsappSettings,
        );

        // 2. إثراء بـ UUID للكيانات المرجعية (FK resolution at restore time)
        _enrichBackupWithFKUuidsInIsolate(
          data,
          employeesData,
          salaryCyclesData,
        );

        // 3. حساب SHA-256 hash (باستثناء حقل data_hash نفسه)
        final metadataForHash = Map<String, dynamic>.from(
          data['metadata'] as Map,
        )..remove('data_hash');
        final dataForHash = <String, dynamic>{
          ...data,
          'metadata': metadataForHash,
        };
        final jsonBytes = utf8.encode(jsonEncode(dataForHash));
        final digest = sha256.convert(jsonBytes);
        (data['metadata'] as Map<String, dynamic>)['data_hash'] = digest
            .toString();

        return data;
      });

      final dataHash = backupData['metadata']?['data_hash'] as String?;
      _log('🔐 تجزئة النسخة الاحتياطية: $dataHash');

      if (whatsappSettings.isNotEmpty) {
        _log('📱 تم تضمين إعدادات الواتساب في النسخة الاحتياطية');
      }

      _log('✅ تم تصدير البيانات: $totalRecords سجل');
      return backupData;
    } catch (e) {
      _log('❌ خطأ في تصدير البيانات: $e');
      rethrow;
    }
  }

  /// تحميل بيانات جدول على دفعات لتجنب استهلاك الذاكرة
  ///
  /// يقرأ السجلات بكميات [batchSize] بدلاً من تحميلها كلها مرة واحدة.
  /// يستخدم طريقة عامة للتعامل مع جميع جداول Drift.
  Future<List<T>> _loadTableBatched<T>(
    dynamic table, {
    int batchSize = 500,
  }) async {
    final db = DatabaseManager.instance;
    final allData = <T>[];
    int offset = 0;

    while (true) {
      // تحويل الجدول إلى TableInfo لاستخدامه مع select
      final tableInfo = table as TableInfo;
      final query = db.select(tableInfo)..limit(batchSize, offset: offset);
      final batch = await query.get();
      if (batch.isEmpty) {
        break;
      }
      allData.addAll(batch.cast<T>());
      offset += batchSize;
      // إذا كانت الدفعة الأخيرة أقل من الحجم المطلوب، فقد وصلنا للنهاية
      if (batch.length < batchSize) {
        break;
      }
    }

    return allData;
  }

  /// ✅ إثراء بيانات النسخة الاحتياطية بمعرفات UUID للكيانات المرجعية (FK)
  ///
  /// المشكلة: عند التصدير، يحتوي JSON فقط على معرفات Auto-increment المحلية
  /// (مثل employeeId=5). عند الاستعادة على جهاز مختلف، يتغير هذا المعرّف
  /// لأن SQLite يعيّن معرّفات جديدة تلقائياً. لكن UUID يبقى ثابتاً عبر الأجهزة.
  ///
  /// الحل: نضيف حقول UUID إضافية (employee_uuid, cycle_local_uuid) إلى JSON
  /// حتى يتمكن IdResolver من العثور على الكيان الصحيح باستخدام UUID أولاً.
  ///
  /// ✅ إصلاح P3-15: تم نقل التنفيذ إلى دالة top-level
  /// [_enrichBackupWithFKUuidsInIsolate] لقابلية الاستدعاء من Isolate.run.

  static const fullBackupPrefix = 'marina_backup_full_';
  static const autoSyncPrefix = 'marina_sync_auto_';
  static const deltaSyncPrefix = 'marina_sync_delta_';

  void _log(String message) {
    DebugLogs.add('DriveBackup', message);
    debugPrint(message);
  }

  /// حساب تجزئة SHA-256 لبيانات النسخة الاحتياطية (باستثناء حقل data_hash نفسه)
  static String _computeBackupChecksum(Map<String, dynamic> backupData) {
    // إزالة data_hash مؤقتاً من البيانات الوصفية قبل الحساب
    final metadata = Map<String, dynamic>.from(backupData['metadata'] as Map);
    metadata.remove('data_hash');

    final dataForHash = <String, dynamic>{...backupData, 'metadata': metadata};

    final jsonBytes = utf8.encode(jsonEncode(dataForHash));
    final digest = sha256.convert(jsonBytes);
    return digest.toString();
  }

  /// التحقق من تجزئة النسخة الاحتياطية عند الاستعادة
  static bool verifyBackupChecksum(Map<String, dynamic> backupData) {
    final metadata = backupData['metadata'];
    if (metadata is! Map) {
      return true; // لا يوجد بيانات وصفية = تجاوز التحقق
    }
    final storedHash = metadata['data_hash'] as String?;
    if (storedHash == null) {
      return true; // نسخ قديمة بدون تجزئة = تجاوز التحقق
    }

    final computedHash = _computeBackupChecksum(backupData);
    return storedHash == computedHash;
  }

  Future<String> uploadBackup(
    Map<String, dynamic> backupData, {
    bool isSync = false,
  }) async {
    String? partialFileId;

    return _runWithAuth<String>(() async {
      try {
        final folderId = await getOrCreateBackupFolder();

        // JSON مضغوط بدون مسافات + gzip أقصى ضغط — في خلفية isolate
        final compressedResult = await Isolate.run(() {
          final jsonBytes = utf8.encode(jsonEncode(backupData));
          final compressed = GZipCodec().encode(jsonBytes);
          return (jsonBytes.length, compressed);
        });
        final jsonSize = compressedResult.$1;
        final compressedBytes = compressedResult.$2;

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
            '$prefix${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.json.gz';

        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId]
          ..appProperties = _buildAppProperties(metadata, timestamp);

        final media = drive.Media(
          Stream.value(compressedBytes),
          compressedBytes.length,
        );

        final compressionRatio = compressedBytes.length / jsonSize;
        _log(
          '📤 بدء رفع $typeLabel: $fileName '
          '(${(jsonSize / 1024).toStringAsFixed(2)} KB → '
          '${(compressedBytes.length / 1024).toStringAsFixed(2)} KB, '
          '${(compressionRatio * 100).toStringAsFixed(1)}%)',
        );

        final uploadedFile = await _driveApi!.files.create(
          driveFile,
          uploadMedia: media,
        );

        partialFileId = uploadedFile.id;

        // التحقق من اكتمال الرفع
        final verifyResult = await _verifyUploadedBackup(
          uploadedFile.id!,
          compressedBytes.length,
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
        final fileId = uploadedFile.id;
        if (fileId == null) {
          throw Exception('فشل في الحصول على معرف الملف المرفوع');
        }
        return fileId;
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
      final uploadedId = uploadedFile.id;
      if (uploadedId == null) {
        throw Exception('فشل في الحصول على معرف الملف المرفوع');
      }
      return uploadedId;
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
      if (value == null) {
        return;
      }
      final stringValue = value.toString();
      if (stringValue.isEmpty) {
        return;
      }
      props[key] = stringValue;
    }

    addIfPresent('records_count', metadata['total_records']);
    addIfPresent('app_version', metadata['app_version']);
    addIfPresent('device_info', metadata['device_info']);
    addIfPresent('format', metadata['format']);
    addIfPresent('device_id', metadata['device_id']); // معرف الجهاز للمزامنة
    addIfPresent('backup_type', metadata['backup_type']);
    addIfPresent('changes_count', metadata['changes_count']);
    props['compression'] = 'gzip';

    return props;
  }

  Future<List<DriveBackupFile>> listBackups() async {
    return _runWithAuth<List<DriveBackupFile>>(() async {
      final folderId = await getOrCreateBackupFolder();

      // ✅ إصلاح (2026-06-28): إضافة بادئة نسخ .db للبحث
      // نسخ .db تُرفع باسم 'db_backup_...' لكن listBackups لم يكن يبحث عنها.
      final query =
          "parents in '$folderId' and (name contains '$fullBackupPrefix' or name contains '$autoSyncPrefix' or name contains '$deltaSyncPrefix' or name contains '$_backupFilePrefix' or name contains 'db_backup_') and trashed=false";
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
      await media.stream.forEach(dataStore.addAll);

      // محاولة فك ضغط gzip — مع دعم التوافق مع النسخ القديمة غير المضغوطة
      List<int> decodedBytes;
      if (dataStore.length >= 2 &&
          dataStore[0] == 0x1f &&
          dataStore[1] == 0x8b) {
        // magic bytes gzip → ملف مضغوط
        decodedBytes = gzip.decode(dataStore);
        _log(
          '📦 فك ضغط gzip: ${(dataStore.length / 1024).toStringAsFixed(2)} KB → '
          '${(decodedBytes.length / 1024).toStringAsFixed(2)} KB',
        );
      } else {
        // نسخة قديمة بدون ضغط
        decodedBytes = dataStore;
      }

      final jsonString = utf8.decode(decodedBytes);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      _log('✅ تم تنزيل النسخة الاحتياطية: $fileId');
      return backupData;
    });
  }

  /// رفع نسخة احتياطية بصيغة .db
  Future<String> uploadDbBackup({String? customFileName}) async {
    return _runWithAuth<String>(() async {
      try {
        final folderId = await getOrCreateBackupFolder();

        // إنشاء نسخة SQLite
        final dbPath = p.join(
          await sqflite.getDatabasesPath(),
          SqliteBackupRestore.kDefaultDbFileName,
        );

        final dbFile = File(dbPath);
        if (!dbFile.existsSync()) {
          throw Exception('Database file not found');
        }

        // ✅ إصلاح حرج: WAL checkpoint قبل قراءة ملف .db
        //
        // Marina's DB uses PRAGMA journal_mode = WAL (local_db.dart:770). في وضع
        // WAL، تُكتب المعاملات الحديثة إلى ملف -wal جانبي قبل دمجها في .db
        // الرئيسي. بدون checkpoint، dbFile.readAsBytes() يقرأ .db فقط — ويفقد
        // كل البيانات الحديثة الموجودة في -wal.
        //
        // الاختبار test/unit/backup_restore_test.dart أثبت هذا الخطأ:
        // بدون checkpoint: 50 سجل فقط في .db (out of 100)
        // بعد checkpoint: كل الـ100 سجل موجودة
        //
        // LocalBackupService.createLocalBackup(sqlite) ينفّذ checkpoint بالفعل،
        // لكن uploadDbBackup كان يفتقد هذه الخطوة الحرجة.
        try {
          final checkpointDb = await sqflite.openDatabase(
            dbPath,
            singleInstance: false,
          );
          try {
            await checkpointDb.execute('PRAGMA wal_checkpoint(TRUNCATE)');
            _log('✅ WAL checkpoint (TRUNCATE) قبل رفع نسخة .db');
          } finally {
            await checkpointDb.close();
          }
        } catch (e) {
          _log('⚠️ WAL checkpoint failed before .db upload (proceeding): $e');
        }

        final timestamp = DateTime.now();
        final fileName =
            customFileName ??
            'db_backup_${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.db';

        // قراءة ملف قاعدة البيانات (بعد checkpoint — كل البيانات مدموجة)
        final bytes = await dbFile.readAsBytes();

        // ✅ إصلاح (2026-06-28): حساب SHA-256 للملف الخام للتحقق من السلامة
        // بدون هذا، أي تلف أثناء النقل/التخزين يمر دون اكتشاف.
        final fileHash = sha256.convert(bytes).toString();

        final driveFile = drive.File()
          ..name = fileName
          ..parents = [folderId]
          ..appProperties = {
            'type': 'sqlite_backup',
            'backup_date': timestamp.toIso8601String(),
            'format': 'db',
            'data_hash': fileHash,
            'file_size': '${bytes.length}',
          };

        final media = drive.Media(Stream.value(bytes), bytes.length);

        _log(
          '📤 رفع نسخة .db: $fileName (${(bytes.length / 1024 / 1024).toStringAsFixed(2)} MB, hash=${fileHash.substring(0, 8)}...)',
        );

        final uploadedFile = await _driveApi!.files.create(
          driveFile,
          uploadMedia: media,
        );

        // ✅ التحقق من اكتمال الرفع (مثل JSON backups)
        final verifyResult = await _verifyUploadedBackup(
          uploadedFile.id!,
          bytes.length,
        );
        if (!(verifyResult['is_complete'] as bool? ?? false)) {
          await deleteBackupFile(uploadedFile.id!);
          throw Exception(
            'فشل في رفع نسخة .db بشكل كامل: ${verifyResult['message']}',
          );
        }

        _log('✅ تم رفع نسخة .db: ${uploadedFile.id}');
        return uploadedFile.id!;
      } catch (e) {
        _log('❌ خطأ في رفع نسخة .db: $e');
        rethrow;
      }
    });
  }

  /// تنزيل واستعادة نسخة .db
  Future<void> restoreDbBackup(String fileId) async {
    return _runWithAuth<void>(() async {
      try {
        // ✅ إصلاح (2026-06-28): جلب appProperties للتحقق من الـ checksum
        // قبل تنزيل المحتوى الكامل (تحسين الأداء + كشف التلف مبكراً)
        final metaResult =
            await _driveApi!.files.get(
                  fileId,
                  $fields: 'id,name,size,appProperties',
                )
                as drive.File;
        final appProps = metaResult.appProperties ?? <String, String?>{};
        final expectedHash = appProps['data_hash'];
        final expectedSizeStr = appProps['file_size'];
        final expectedSize = expectedSizeStr != null
            ? int.tryParse(expectedSizeStr)
            : null;

        final media =
            await _driveApi!.files.get(
                  fileId,
                  downloadOptions: drive.DownloadOptions.fullMedia,
                )
                as drive.Media;

        // إنشاء مجلد مؤقت
        final tempDir = await getTemporaryDirectory();
        final fileName = 'restore_${DateTime.now().millisecondsSinceEpoch}.db';
        final tempFile = File(p.join(tempDir.path, fileName));

        // كتابة البيانات إلى الملف المؤقت
        final List<int> dataStore = [];
        await media.stream.forEach(dataStore.addAll);
        await tempFile.writeAsBytes(dataStore);

        _log(
          '📥 تنزيل نسخة .db: ${(dataStore.length / 1024 / 1024).toStringAsFixed(2)} MB',
        );

        // ✅ التحقق من الحجم
        if (expectedSize != null && dataStore.length != expectedSize) {
          await tempFile.delete();
          throw Exception(
            'حجم الملف المنزّل (${dataStore.length} بايت) لا يطابق المتوقع ($expectedSize بايت). '
            'النسخة قد تكون تالفة أو غير مكتملة.',
          );
        }

        // ✅ التحقق من SHA-256 hash
        if (expectedHash != null && expectedHash.isNotEmpty) {
          final actualHash = sha256.convert(dataStore).toString();
          if (actualHash != expectedHash) {
            await tempFile.delete();
            _logger.error(
              '❌ فشل التحقق من تجزئة نسخة .db: متوقع=$expectedHash، فعلي=$actualHash',
              tag: 'RESTORE',
            );
            throw Exception(
              'النسخة الاحتياطية .db تالفة: تجزئة البيانات غير مطابقة. '
              'لا يمكن الاستعادة من ملف تالف.',
            );
          }
          _logger.info('✅ تم التحقق من سلامة نسخة .db', tag: 'RESTORE');
        } else {
          _logger.warning(
            '⚠️ نسخة .db قديمة بدون data_hash — التحقق من السلامة متخطّى',
            tag: 'RESTORE',
          );
        }

        // استعادة قاعدة البيانات
        await SqliteBackupRestore.restoreDatabase(tempFile.path);

        // حذف الملف المؤقت
        await tempFile.delete();

        _log('✅ تم استعادة نسخة .db بنجاح');
      } catch (e) {
        _log('❌ خطأ في استعادة نسخة .db: $e');
        rethrow;
      }
    });
  }

  /// الحصول على قائمة النسخ .db من Google Drive
  ///
  /// ✅ إصلاح (2026-06-28): إضافة pagination loop
  /// المنطق القديم كان يطلب pageSize: 50 بدون تابع nextPageToken،
  /// مما يُسكت العدد الزائد عن 50 نسخة. الآن نجلب كل الصفحات.
  Future<List<DriveBackupFile>> listDbBackups() async {
    return _runWithAuth<List<DriveBackupFile>>(() async {
      final folderId = await getOrCreateBackupFolder();

      final allFiles = <drive.File>[];
      String? pageToken;
      do {
        final result = await _driveApi!.files.list(
          q: "'$folderId' in parents and name contains 'db_backup' and name contains '.db' and trashed = false",
          orderBy: 'createdTime desc',
          pageSize: 100,
          pageToken: pageToken,
          $fields:
              'nextPageToken,files(id,name,createdTime,size,appProperties)',
        );
        if (result.files != null) {
          allFiles.addAll(result.files!);
        }
        pageToken = result.nextPageToken;
      } while (pageToken != null);

      return allFiles
          .where((f) => f.id != null && f.name != null)
          .map(DriveBackupFile.fromDriveFile)
          .toList();
    });
  }

  Future<void> restoreFromBackup(
    Map<String, dynamic> backupData, {
    void Function(int current, int total, String tableName)? onProgress,
  }) async {
    if (!DatabaseManager.isRestoring) {
      // Self-guard to avoid accidental destructive calls while keeping safety
      return DatabaseManager.runWithRestoreGuard(
        () => _restoreFromBackupInternal(backupData, onProgress: onProgress),
      );
    }
    return _restoreFromBackupInternal(backupData, onProgress: onProgress);
  }

  Future<void> _restoreFromBackupInternal(
    Map<String, dynamic> backupData, {
    void Function(int current, int total, String tableName)? onProgress,
  }) async {
    try {
      final db = DatabaseManager.instance;
      final adapterRegistry = AdapterRegistry.instance;

      if (!backupData.containsKey('metadata')) {
        _log('⚠️ النسخة الاحتياطية لا تحتوي على بيانات وصفية، سيتم تجاوزها');
        _logger.warning(
          'Skipping restore: backup missing metadata',
          tag: 'RESTORE',
        );
        return;
      }

      // ✅ إصلاح (2026-06-28): التحقق من سلامة البيانات قبل الاستعادة
      // verifyBackupChecksum كان موجوداً لكنه لم يُستدعى. الآن نتحقق
      // من SHA-256 hash قبل أي عملية تدميرية (حذف الجداول).
      // نسخ قديمة بدون data_hash تُتجاوز التحقق (ترجع true).
      if (!verifyBackupChecksum(backupData)) {
        _logger.error(
          '❌ فشل التحقق من سلامة النسخة الاحتياطية — البيانات تالفة',
          tag: 'RESTORE',
        );
        throw Exception(
          'النسخة الاحتياطية تالفة: تجزئة البيانات غير مطابقة. '
          'قد يكون الملف تعرّض للفساد أثناء النقل أو التخزين.',
        );
      }
      _logger.info('✅ تم التحقق من سلامة النسخة الاحتياطية', tag: 'RESTORE');

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

      // ✅ إصلاح حرج: PRAGMA foreign_keys = OFF يجب أن يكون خارج المعاملة
      // لأن SQLite يتجاهل هذا الأمر داخل transaction بصمت!
      // https://www.sqlite.org/pragma.html#pragma_foreign_keys
      await db.customStatement('PRAGMA foreign_keys = OFF');
      _log('🔓 تم تعطيل FOREIGN KEYS قبل المعاملة');

      try {
        await db.transaction(() async {
          // حذف جميع الجداول بالترتيب الصحيح (الأبناء قبل الآباء)
          // Level 3 – أبناء بعيدة (تشير لأبناء أو آباء)
          await db.delete(db.bookingNotes).go();
          await db.delete(db.bookingNights).go();
          await db.delete(db.bookingPriceAdjustments).go();
          await db.delete(db.paymentVoids).go();
          // Level 2 – أبناء مباشرة تشير للآباء الرئيسية
          await db.delete(db.payments).go();
          await db.delete(db.debts).go();
          await db
              .delete(db.salaryPayments)
              .go(); // FK → employees, salaryCycles
          await db.delete(db.salaryWithdrawals).go(); // FK → employees
          await db.delete(db.salaryCarryOverLogs).go(); // FK → employees
          await db.delete(db.expenses).go();
          await db.delete(db.cashTransactions).go();
          await db.delete(db.auditLogs).go();
          await db.delete(db.guestInfos).go();
          // Level 1 – آباء رئيسية (يُشار إليها من جداول أعلاه)
          await db.delete(db.bookings).go();
          await db.delete(db.rooms).go();
          await db.delete(db.employees).go();
          await db.delete(db.salaryCycles).go();
          // Level 0 – جداول مستقلة بدون FK صادرة
          await db.delete(db.hotelDayLedger).go();
          await db.delete(db.shiftNotes).go();
          await db.delete(db.integrityViolations).go();
          await db.delete(db.autoFixRuns).go();
          await db.delete(db.syncConflicts).go();
          await db.delete(db.syncLog).go();
          await db.delete(db.syncQueue).go();
          await db.delete(db.syncState).go();
          await db.delete(db.restoreFixLog).go();
          await db.delete(db.appSessions).go();

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
            // ✅ إصلاح P3-16 + PR review: استخدام batchUpsertFromJson لإدراج
            // آلاف الحجوزات في batch واحد بدلاً من INSERT منفصل لكل صف.
            // ✅ إصلاح PR review: استبدلنا Map.from بـ cast لتجنب استنساخ
            // الـ list بالكامل (يضاعف الذاكرة لـ 8K+ صف). batchUpsertFromJson
            // لا يُعدّل الـ Maps الأصلية (يستخدم jsonCopy داخلياً).
            final result = await adapterRegistry.bookings.batchUpsertFromJson(
              bookingsData.cast<Map<String, dynamic>>().toList(),
              src: Source.drive,
            );
            if (result.skipped > 0) {
              _log(
                '⚠️ تم تخطي ${result.skipped} حجز بسبب مراجع FK مفقودة '
                'أو بيانات غير صالحة',
              );
            }
            _log('✅ تم استعادة ${result.inserted} حجز');
          }

          if (backupData.containsKey('booking_notes')) {
            final notesData = backupData['booking_notes'] as List<dynamic>;
            int skippedNotes = 0;
            for (final noteJson in notesData) {
              try {
                await adapterRegistry.bookingNotes.upsertFromJson(
                  Map<String, dynamic>.from(noteJson as Map),
                  src: Source.drive,
                );
              } on InvalidDataException catch (e, st) {
                skippedNotes++;
                _log('⚠️ تم تخطي ملاحظة حجز بسبب FK مفقود: $e');
              } catch (e) {
                _log('⚠️ فشل استعادة ملاحظة حجز: $e');
              }
            }
            if (skippedNotes > 0) {
              _log('⚠️ تم تخطي $skippedNotes ملاحظة حجز بسبب مراجع FK مفقودة');
            }
          }

          if (backupData.containsKey('booking_nights')) {
            final nightsData = backupData['booking_nights'] as List<dynamic>;
            int skippedNights = 0;
            for (final nightJson in nightsData) {
              try {
                await adapterRegistry.nights.upsertFromJson(
                  Map<String, dynamic>.from(nightJson as Map),
                  src: Source.drive,
                );
              } on InvalidDataException catch (e, st) {
                skippedNights++;
                _log('⚠️ تم تخطي ليلة حجز بسبب FK مفقود: $e');
              } catch (e) {
                _log('⚠️ فشل استعادة ليلة حجز: $e');
              }
            }
            if (skippedNights > 0) {
              _log('⚠️ تم تخطي $skippedNights ليلة حجز بسبب مراجع FK مفقودة');
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
            // ✅ إصلاح P3-16: batch insert للمصروفات (قد تكون آلاف السجلات)
            // ✅ إصلاح PR review: استبدلنا Map.from بـ cast (تجنب استنساخ list)
            final result = await adapterRegistry.expenses.batchUpsertFromJson(
              expensesData.cast<Map<String, dynamic>>().toList(),
              src: Source.drive,
            );
            if (result.skipped > 0) {
              _log('⚠️ تم تخطي ${result.skipped} مصروف بسبب بيانات غير صالحة');
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
            // ✅ إصلاح P3-16: batch insert للمدفوعات (عادةً أكبر جدول — آلاف السجلات)
            // ✅ إصلاح PR review: استبدلنا Map.from بـ cast (تجنب استنساخ list)
            final result = await adapterRegistry.payments.batchUpsertFromJson(
              paymentsData.cast<Map<String, dynamic>>().toList(),
              src: Source.drive,
            );
            if (result.skipped > 0) {
              _log(
                '⚠️ تم تخطي ${result.skipped} دفعة بسبب مراجع FK مفقودة '
                'أو بيانات غير صالحة',
              );
            }
            _log('✅ تم استعادة ${result.inserted} دفعة');
          }

          if (backupData.containsKey('debts')) {
            final debtsList = backupData['debts'] as List<dynamic>;
            int skippedDebts = 0;
            for (final debtJson in debtsList) {
              try {
                await adapterRegistry.debts.upsertFromJson(
                  Map<String, dynamic>.from(debtJson as Map),
                  src: Source.drive,
                );
              } on InvalidDataException catch (e, st) {
                skippedDebts++;
                _log('⚠️ تم تخطي دين بسبب FK مفقود: $e');
              } catch (e) {
                _log('⚠️ فشل استعادة دين: $e');
              }
            }
            if (skippedDebts > 0) {
              _log('⚠️ تم تخطي $skippedDebts دين بسبب مراجع FK مفقودة');
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
            int skippedPayments = 0;
            for (final salaryJson in salaryList) {
              try {
                await adapterRegistry.salaryPayments.upsertFromJson(
                  Map<String, dynamic>.from(salaryJson as Map),
                  src: Source.drive,
                );
              } on InvalidDataException catch (e, st) {
                skippedPayments++;
                _log(
                  '⚠️ تم تخطي دفعة راتب بسبب بيانات غير صالحة (FK مفقود): $e',
                );
              } catch (e) {
                _log('⚠️ فشل استعادة دفعة راتب: $e');
              }
            }
            if (skippedPayments > 0) {
              _log(
                '⚠️ تم تخطي $skippedPayments دفعة راتب بسبب مراجع FK مفقودة',
              );
            }
          }

          if (backupData.containsKey('salary_withdrawals')) {
            final withdrawalsList =
                backupData['salary_withdrawals'] as List<dynamic>;
            int skippedWithdrawals = 0;
            for (final wJson in withdrawalsList) {
              try {
                await adapterRegistry.salaryWithdrawals.upsertFromJson(
                  Map<String, dynamic>.from(wJson as Map),
                  src: Source.drive,
                );
              } on InvalidDataException catch (e, st) {
                skippedWithdrawals++;
                _log(
                  '⚠️ تم تخطي سحب راتب بسبب بيانات غير صالحة (FK مفقود): $e',
                );
              } catch (e) {
                _log('⚠️ فشل استعادة سحب راتب: $e');
              }
            }
            if (skippedWithdrawals > 0) {
              _log(
                '⚠️ تم تخطي $skippedWithdrawals سحب راتب بسبب مراجع FK مفقودة',
              );
            }
          }

          if (backupData.containsKey('salary_carry_over_logs')) {
            final carryOverList =
                backupData['salary_carry_over_logs'] as List<dynamic>;
            for (final cJson in carryOverList) {
              try {
                await adapterRegistry.salaryCarryOverLogs.upsertFromJson(
                  Map<String, dynamic>.from(cJson as Map),
                  src: Source.drive,
                );
              } catch (e) {
                _log('⚠️ فشل استعادة سجل ترحيل راتب: $e');
              }
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
            final bpaList =
                backupData['booking_price_adjustments'] as List<dynamic>;
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

          // استعادة إعدادات الواتساب → SharedPreferences
          if (backupData.containsKey('whatsapp_settings')) {
            final restorePrefs = await SharedPreferences.getInstance();
            final waSettings = Map<String, dynamic>.from(
              backupData['whatsapp_settings'] as Map,
            );
            if (waSettings.isNotEmpty) {
              for (final entry in waSettings.entries) {
                final value = entry.value?.toString() ?? '';
                if (value.isNotEmpty) {
                  await restorePrefs.setString(entry.key, value);
                }
              }
              _log('📱 تم استعادة إعدادات الواتساب (${waSettings.length} حقل)');
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

          // BUG-3 FIX: Don't restore sync_state - new device should sync from scratch
          // sync_state contains lastPullTs/deviceId from source device
          if (backupData.containsKey('sync_state')) {
            await db.delete(db.syncState).go();
            _log('🔄 تم مسح sync_state — الجهاز الجديد سيبدأ مزامنة كاملة');
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

              const keys = SystemSettingKeys.all;

              bool settingsChanged = false;
              for (final key in keys) {
                if (settings.containsKey(key) && settings[key] != null) {
                  final val = settings[key];
                  final currentVal = prefs.get(key);

                  if (val != currentVal) {
                    if (val is bool) {
                      await prefs.setBool(key, val);
                    }
                    if (val is String) {
                      await prefs.setString(key, val);
                    }
                    if (val is int) {
                      await prefs.setInt(key, val);
                    }
                    if (val is double) {
                      await prefs.setDouble(key, val);
                    }
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

          // ✅ إصلاح حرج (2026-06-28): إعادة ربط المدفوعات والديون بالحجوزات
          // بعد استعادة نسخة من جهاز آخر، bookingLocalId (auto-increment) يختلف.
          // هذه الخطوة تربط المدفوعات بالحجوزات باستخدام bookingUuidCache/localUuid.
          await _relinkPaymentsToBookings(db);
          await _relinkDebtsToBookings(db);
        }); // نهاية db.transaction
      } finally {
        // ✅ إعادة تفعيل FOREIGN KEYS خارج المعاملة
        await db.customStatement('PRAGMA foreign_keys = ON');
        _log('🔓 تم إعادة تشغيل FOREIGN KEYS بعد المعاملة');

        // التحقق من سلامة Foreign Keys بعد الاستعادة
        try {
          final violations = await db
              .customSelect('PRAGMA foreign_key_check')
              .get();
          if (violations.isNotEmpty) {
            _log(
              '⚠️ تحذير: تم العثور على ${violations.length} انتهاك FK بعد الاستعادة',
            );
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

      // ✅ إصلاح (2026-06-28): إعادة ربط خارج transaction أيضاً (احتياطي)
      await _relinkPaymentsToBookings(db);
      await _relinkDebtsToBookings(db);

      // مزامنة البيانات المستعادة مع Appwrite
      try {
        _log('🔄 بدء مزامنة البيانات مع Appwrite...');
        final prefs = await SharedPreferences.getInstance();
        final syncEnabled = prefs.getBool('appwrite_sync_enabled') ?? true;

        if (syncEnabled) {
          final appwriteService = AppwriteService();
          await appwriteService.initialize();

          if (appwriteService.isInitialized) {
            final syncManager = AppwriteSyncManager();

            await syncManager.pushAllLocalDataToAppwrite();
            final stats = <String, int>{'errors': 0};

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
      case 'weekly':
        frequencyDuration = const Duration(days: 7);
      case 'monthly':
        frequencyDuration = const Duration(days: 30);
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
      await Future<void>.delayed(const Duration(seconds: 1));
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
    } catch (e, st) {
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
        } catch (e, st) {
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
    return cleanupOldBackups(maxBackupsToKeep: 15);
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

  // ════════════════════════════════════════════════════════════════════
  // ✅ إعادة ربط المدفوعات والديون بالحجوزات بعد الاستعادة (2026-06-28)
  // ════════════════════════════════════════════════════════════════════
  //
  // المشكلة: عند استعادة نسخة من جهاز آخر، bookingLocalId (auto-increment)
  // يختلف بين الأجهزة. المدفوعات تُستعادة لكن bookingLocalId لا يتطابق
  // مع id الحجز الجديد → المدفوعات لا تظهر.
  //
  // الحل: نربط المدفوعات بالحجوزات باستخدام bookingUuidCache (UUID)
  // الذي يتطابق عبر الأجهزة.

  /// إعادة ربط المدفوعات بالحجوزات باستخدام UUID
  Future<void> _relinkPaymentsToBookings(AppDatabase db) async {
    try {
      // جلب كل الحجوزات مع UUID → id
      final bookings = await db.select(db.bookings).get();
      final bookingByUuid = <String, int>{};
      for (final b in bookings) {
        bookingByUuid[b.localUuid] = b.id;
      }

      // جلب كل المدفوعات
      final payments = await db.select(db.payments).get();
      int relinked = 0;

      for (final p in payments) {
        // إذا bookingLocalId уже مضبوط بشكل صحيح، تخطّي
        if (p.bookingLocalId != null &&
            bookingByUuid.containsValue(p.bookingLocalId)) {
          continue;
        }

        // ابحث عن الحجز بـ UUID
        final uuid = p.bookingUuidCache;
        if (uuid != null &&
            uuid.isNotEmpty &&
            bookingByUuid.containsKey(uuid)) {
          final correctBookingId = bookingByUuid[uuid]!;
          await (db.update(
            db.payments,
          )..where((t) => t.id.equals(p.id))).write(
            PaymentsCompanion(bookingLocalId: Value(correctBookingId)),
          );
          relinked++;
        }
      }

      if (relinked > 0) {
        _log('🔗 تم إعادة ربط $relinked دفعة بالحجوزات بنجاح');
      }
    } catch (e) {
      _log('⚠️ فشل إعادة ربط المدفوعات: $e');
    }
  }

  /// إعادة ربط الديون بالحجوزات باستخدام UUID
  Future<void> _relinkDebtsToBookings(AppDatabase db) async {
    try {
      final bookings = await db.select(db.bookings).get();
      final bookingByUuid = <String, int>{};
      for (final b in bookings) {
        bookingByUuid[b.localUuid] = b.id;
      }

      final debts = await db.select(db.debts).get();
      int relinked = 0;

      for (final d in debts) {
        if (d.bookingLocalId != null &&
            bookingByUuid.containsValue(d.bookingLocalId)) {
          continue;
        }

        // الديون لا تحتوي على bookingUuidCache — نحاول المطابقة بـ guestName + checkinDate
        // كحل أخير: نبحث عن حجز بنفس اسم النزيل وتاريخ الدخول
        if (d.guestName.isNotEmpty && d.checkinDate.isNotEmpty) {
          final matchingBooking = bookings
              .where(
                (b) =>
                    b.guestName == d.guestName &&
                    b.checkinDate == d.checkinDate,
              )
              .firstOrNull;
          if (matchingBooking != null) {
            await (db.update(
              db.debts,
            )..where((t) => t.id.equals(d.id))).write(
              DebtsCompanion(bookingLocalId: Value(matchingBooking.id)),
            );
            relinked++;
          }
        }
      }

      if (relinked > 0) {
        _log('🔗 تم إعادة ربط $relinked دين بالحجوزات بنجاح');
      }
    } catch (e) {
      _log('⚠️ فشل إعادة ربط الديون: $e');
    }
  }
}

/// نسخة top-level من إثراء UUID — قابلة للاستدعاء من Isolate.run لأن
/// الـ isolates لا يمكنها الوصول إلى أساليب الكائنات (instance methods).
///
/// ✅ إصلاح P3-15: هذه الدالة تعمل بالكامل على البيانات المحلية المُمرَّرة
/// (backupData, employeesData, salaryCyclesData) بدون أي وصول إلى Database،
/// لذا هي آمنة للتنفيذ داخل isolate.
void _enrichBackupWithFKUuidsInIsolate(
  Map<String, dynamic> backupData,
  List<dynamic> employeesData,
  List<dynamic> salaryCyclesData,
) {
  // بناء خريطة: معرّف الموظف المحلي → UUID
  final employeeUuidMap = <int, String>{};
  for (final emp in employeesData) {
    final empMap = (emp as dynamic).toJson() as Map<String, dynamic>;
    final empId = empMap['id'] as int?;
    final empUuid = empMap['localUuid'] as String?;
    if (empId != null && empUuid != null) {
      employeeUuidMap[empId] = empUuid;
    }
  }

  // إثراء سحوبات الرواتب بـ UUID الموظف
  final withdrawalsList = backupData['salary_withdrawals'] as List<dynamic>?;
  if (withdrawalsList != null) {
    for (int i = 0; i < withdrawalsList.length; i++) {
      final wMap = withdrawalsList[i] as Map<String, dynamic>;
      final empId = wMap['employeeId'] as int?;
      if (empId != null && employeeUuidMap.containsKey(empId)) {
        wMap['employee_uuid'] = employeeUuidMap[empId];
      }
    }
  }

  // بناء خريطة: معرّف دورة الراتب المحلي → UUID
  final cycleUuidMap = <int, String>{};
  for (final cycle in salaryCyclesData) {
    final cycleMap = (cycle as dynamic).toJson() as Map<String, dynamic>;
    final cycleId = cycleMap['id'] as int?;
    final cycleUuid = cycleMap['localUuid'] as String?;
    if (cycleId != null && cycleUuid != null) {
      cycleUuidMap[cycleId] = cycleUuid;
    }
  }

  // إثراء مدفوعات الرواتب بـ UUID دورة الراتب
  final salaryPaymentsList = backupData['salary_payments'] as List<dynamic>?;
  if (salaryPaymentsList != null) {
    for (int i = 0; i < salaryPaymentsList.length; i++) {
      final pMap = salaryPaymentsList[i] as Map<String, dynamic>;
      final cycleId = pMap['cycleId'] as int?;
      if (cycleId != null && cycleUuidMap.containsKey(cycleId)) {
        pMap['cycle_local_uuid'] = cycleUuidMap[cycleId];
      }
    }
  }
}
