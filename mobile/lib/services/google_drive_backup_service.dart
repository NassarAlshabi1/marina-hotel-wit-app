import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:workmanager/workmanager.dart';

import 'local_db.dart';
import 'providers.dart';
import 'restore_fix_service.dart';
import 'backup_serializers.dart';

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
  static const List<String> _scopes = [drive.DriveApi.driveFileScope];

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

  Future<void> signOut() async {
    try {
      await _googleSignIn?.signOut();
      _driveApi = null;
      _backupFolderId = null;
      debugPrint('✅ تم تسجيل الخروج من Google Drive');
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الخروج: $e');
      rethrow;
    }
  }

  GoogleSignInAccount? get currentUser => _googleSignIn?.currentUser;

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
      final db = getDatabase();

      final roomsData = await db.select(db.rooms).get();
      final bookingsData = await db.select(db.bookings).get();
      final bookingNotesData = await db.select(db.bookingNotes).get();
      final employeesData = await db.select(db.employees).get();
      final expensesData = await db.select(db.expenses).get();
      final cashTransactionsData = await db.select(db.cashTransactions).get();
      final paymentsData = await db.select(db.payments).get();
      final syncStateData = await db.select(db.syncState).get();

      final totalRecords =
          roomsData.length +
          bookingsData.length +
          bookingNotesData.length +
          employeesData.length +
          expensesData.length +
          cashTransactionsData.length +
          paymentsData.length;

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
        'employees': employeesData.map((employee) => employee.toJson()).toList(),
        'expenses': expensesData.map((expense) => expense.toJson()).toList(),
        'cash_transactions': cashTransactionsData.map((transaction) => transaction.toJson()).toList(),
        'payments': paymentsData.map((payment) => payment.toJson()).toList(),
        'sync_state': syncStateData.isNotEmpty ? syncStateData.first.toJson() : {},
      };

      debugPrint('✅ تم تصدير البيانات: $totalRecords سجل');
      return backupData;
    } catch (e) {
      debugPrint('❌ خطأ في تصدير البيانات: $e');
      rethrow;
    }
  }

  Future<String> uploadBackup(Map<String, dynamic> backupData) async {
    return _runWithAuth<String>(() async {
      final folderId = await getOrCreateBackupFolder();

      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);

      final timestamp = DateTime.now();
      final fileName = '$_backupFilePrefix${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.json';

      final metadata = backupData['metadata'] as Map<String, dynamic>? ?? {};

      final driveFile = drive.File()
        ..name = fileName
        ..parents = [folderId]
        ..appProperties = _buildAppProperties(metadata, timestamp);

      final media = drive.Media(Stream.value(jsonBytes), jsonBytes.length);
      final uploadedFile = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLastBackupKey, timestamp.toIso8601String());

      debugPrint('✅ تم رفع النسخة الاحتياطية: ${uploadedFile.id}');
      return uploadedFile.id!;
    });
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

  Future<List<DriveBackupFile>> listBackupFiles() async {
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
      final db = getDatabase();

      if (!backupData.containsKey('metadata')) {
        throw Exception('النسخة الاحتياطية لا تحتوي على بيانات وصفية');
      }

      final metadata = BackupMetadata.fromJson(backupData['metadata']);

      if (metadata.databaseVersion > 3) {
        throw Exception('إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي');
      }

      debugPrint('🔄 بدء استعادة البيانات...');

      await db.delete(db.rooms).go();
      await db.delete(db.bookings).go();
      await db.delete(db.bookingNotes).go();
      await db.delete(db.employees).go();
      await db.delete(db.expenses).go();
      await db.delete(db.cashTransactions).go();
      await db.delete(db.payments).go();
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

      if (backupData.containsKey('sync_state') && backupData['sync_state'] is Map && (backupData['sync_state'] as Map).isNotEmpty) {
        final syncStateJson = Map<String, dynamic>.from(backupData['sync_state'] as Map);
        final data = SyncStateData.fromJson(syncStateJson, serializer: lenientValueSerializer);
        await db.into(db.syncState).insertOnConflictUpdate(data);
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
      await Workmanager().registerPeriodicTask(
        'autoBackup',
        'autoBackupTask',
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
    return prefs.getBool(_prefsAutoBackupKey) ?? false;
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

  void dispose() {
    _driveApi = null;
    _backupFolderId = null;
  }
}
