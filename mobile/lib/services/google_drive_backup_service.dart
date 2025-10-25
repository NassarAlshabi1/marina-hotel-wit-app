import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:workmanager/workmanager.dart';
import 'local_db.dart';
import 'providers.dart';

class DriveBackupFile {
  final String fileId;
  final String fileName;
  final DateTime createdTime;
  final int? size;
  final Map<String, String>? appProperties;
  final BackupFormat format;
  final BackupMetadata? metadata;

  DriveBackupFile({
    required this.fileId,
    required this.fileName,
    required this.createdTime,
    this.size,
    this.appProperties,
    this.format = BackupFormat.json,
    this.metadata,
  });

  factory DriveBackupFile.fromDriveFile(drive.File file) {
    final props = <String, String>{};
    if (file.appProperties != null) {
      props.addAll(file.appProperties!);
    }

    final rawFormat = props['format'];
    final format = BackupFormat.values.firstWhere(
      (f) => f.name == rawFormat,
      orElse: () => file.name?.toLowerCase().endsWith('.sqlite') == true
          ? BackupFormat.sqlite
          : BackupFormat.json,
    );

    BackupMetadata? metadata;
    try {
      metadata = BackupMetadata(
        appVersion: props['app_version'] ?? '',
        databaseVersion: int.tryParse(props['database_version'] ?? '') ?? 1,
        backupTimestamp: props.containsKey('backup_timestamp')
            ? (DateTime.tryParse(props['backup_timestamp']!) ?? file.createdTime ?? DateTime.now())
            : file.createdTime ?? DateTime.now(),
        totalRecords: int.tryParse(props['records_count'] ?? '') ?? 0,
        deviceInfo: props['device_info'] ?? 'Google Drive',
        format: format,
      );
    } catch (_) {
      metadata = null;
    }

    return DriveBackupFile(
      fileId: file.id!,
      fileName: file.name ?? 'backup-${file.id}',
      createdTime: file.createdTime ?? DateTime.now(),
      size: file.size != null ? int.tryParse(file.size!) : null,
      appProperties: props.isEmpty ? null : props,
      format: format,
      metadata: metadata,
    );
  }
}

class _DriveBackupPayload {
  _DriveBackupPayload({
    required this.metadata,
    required this.fileName,
    required this.length,
    required this.stream,
    this.tempFilePath,
  });

  final BackupMetadata metadata;
  final String fileName;
  final int length;
  final Stream<List<int>> stream;
  final String? tempFilePath;
}

class DownloadedBackup {
  DownloadedBackup.json(this.data, this.metadata)
      : format = BackupFormat.json,
        filePath = null;

  DownloadedBackup.sqlite(this.filePath, this.metadata)
      : format = BackupFormat.sqlite,
        data = null;

  final BackupFormat format;
  final Map<String, dynamic>? data;
  final String? filePath;
  final BackupMetadata metadata;
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
    return BackupMetadata(
      appVersion: json['app_version'] ?? '',
      databaseVersion: json['database_version'] ?? 1,
      backupTimestamp: DateTime.parse(json['backup_timestamp']),
      totalRecords: json['total_records'] ?? 0,
      deviceInfo: json['device_info'] ?? '',
      format: BackupFormat.values.firstWhere(
        (f) => f.name == rawFormat,
        orElse: () => BackupFormat.json,
      ),
    );
  }
}

class GoogleDriveBackupService {
  static const String _backupFolderName = 'MarinaHotelBackups';
  static const String _backupFilePrefix = 'marina_hotel_backup_';
  static const List<String> _scopes = [drive.DriveApi.driveFileScope];
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
      serverClientId: null, // سيتم تكوينه من google-services.json
    );
  }

  /// تسجيل الدخول في Google Drive
  Future<GoogleSignInAccount?> signInForDrive() async {
    try {
      if (_googleSignIn == null) {
        throw Exception('Google Sign-In لم يتم تهيئته بشكل صحيح');
      }

      // محاولة تسجيل دخول صامت أولاً
      GoogleSignInAccount? account = await _googleSignIn!.signInSilently();
      
      if (account == null) {
        // تسجيل دخول تفاعلي
        account = await _googleSignIn!.signIn();
      }

      if (account != null) {
        final authentication = await account.authentication;
        final credentials = AccessCredentials(
          AccessToken('Bearer', authentication.accessToken!, DateTime.now().add(Duration(hours: 1))),
          authentication.idToken,
          _scopes,
        );

        final client = authenticatedClient(http.Client(), credentials);
        _driveApi = drive.DriveApi(client);
        
        debugPrint('✅ تم تسجيل الدخول بنجاح في Google Drive: ${account.email}');
      }

      return account;
    } catch (e) {
      debugPrint('❌ خطأ في تسجيل الدخول في Google Drive: $e');
      rethrow;
    }
  }

  /// تسجيل الخروج من Google Drive
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

  /// الحصول على المستخدم الحالي
  GoogleSignInAccount? get currentUser => _googleSignIn?.currentUser;

  /// التحقق من حالة تسجيل الدخول
  bool get isSignedIn => _googleSignIn?.currentUser != null;

  /// إنشاء أو العثور على مجلد النسخ الاحتياطية
  Future<String> getOrCreateBackupFolder() async {
    if (_driveApi == null) {
      throw Exception('يجب تسجيل الدخول في Google Drive أولاً');
    }

    if (_backupFolderId != null) {
      return _backupFolderId!;
    }

    try {
      // البحث عن المجلد الموجود
      final query = "name='$_backupFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false";
      final searchResult = await _driveApi!.files.list(q: query);

      if (searchResult.files != null && searchResult.files!.isNotEmpty) {
        _backupFolderId = searchResult.files!.first.id;
        debugPrint('✅ تم العثور على مجلد النسخ الاحتياطية: $_backupFolderId');
      } else {
        // إنشاء مجلد جديد
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
  }

  /// تصدير قاعدة البيانات إلى JSON
  Future<Map<String, dynamic>> exportDatabaseToJson() async {
    try {
      final db = getDatabase();
      
      // تصدير جميع الجداول
      final roomsData = await db.select(db.rooms).get();
      final bookingsData = await db.select(db.bookings).get();
      final bookingNotesData = await db.select(db.bookingNotes).get();
      final employeesData = await db.select(db.employees).get();
      final expensesData = await db.select(db.expenses).get();
      final cashTransactionsData = await db.select(db.cashTransactions).get();
      final paymentsData = await db.select(db.payments).get();
      final syncStateData = await db.select(db.syncState).get();

      // حساب إجمالي السجلات
      final totalRecords = roomsData.length + 
                          bookingsData.length + 
                          bookingNotesData.length + 
                          employeesData.length + 
                          expensesData.length + 
                          cashTransactionsData.length + 
                          paymentsData.length;

      // إنشاء البيانات الوصفية
      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: db.schemaVersion,
        backupTimestamp: DateTime.now(),
        totalRecords: totalRecords,
        deviceInfo: Platform.isAndroid ? 'Android Drive' : 'iOS Drive',
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

  Future<Map<String, int>> _collectRecordCounts(AppDatabase db) async {
    Future<int> count(String table) async {
      final row = await db.customSelect('SELECT COUNT(*) AS count FROM $table').getSingle();
      final value = row.data['count'];
      if (value is int) {
        return value;
      }
      if (value is num) {
        return value.toInt();
      }
      return 0;
    }

    return {
      'rooms': await count('rooms'),
      'bookings': await count('bookings'),
      'booking_notes': await count('booking_notes'),
      'employees': await count('employees'),
      'expenses': await count('expenses'),
      'cash_transactions': await count('cash_transactions'),
      'payments': await count('payments'),
    };
  }

  Future<_DriveBackupPayload> _prepareBackupPayload(BackupFormat format) async {
    final db = getDatabase();
    final timestamp = DateTime.now();
    final deviceLabel = Platform.isAndroid ? 'Android Drive' : 'iOS Drive';

    if (format == BackupFormat.json) {
      final backupData = await exportDatabaseToJson();
      final metadata = BackupMetadata.fromJson(backupData['metadata']);
      final jsonString = const JsonEncoder.withIndent('  ').convert(backupData);
      final jsonBytes = utf8.encode(jsonString);
      final fileName = '$_backupFilePrefix${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.json';

      return _DriveBackupPayload(
        metadata: metadata,
        fileName: fileName,
        length: jsonBytes.length,
        stream: Stream.value(jsonBytes),
      );
    }

    if (format == BackupFormat.sqlite) {
      final counts = await _collectRecordCounts(db);
      final totalRecords = counts.values.fold<int>(0, (prev, element) => prev + element);
      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: db.schemaVersion,
        backupTimestamp: timestamp,
        totalRecords: totalRecords,
        deviceInfo: deviceLabel,
        format: BackupFormat.sqlite,
      );

      final databasesPath = await getDatabasesPath();
      final dbPath = p.join(databasesPath, 'marina_hotel.db');
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'drive_${timestamp.millisecondsSinceEpoch}.sqlite');

      try {
        await db.customSelect('PRAGMA wal_checkpoint(FULL)').get();
      } catch (_) {}
      try {
        await db.customStatement('VACUUM');
      } catch (_) {}

      await File(dbPath).copy(tempPath);
      final tempFile = File(tempPath);
      final length = await tempFile.length();
      final fileName = '$_backupFilePrefix${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}.sqlite';

      return _DriveBackupPayload(
        metadata: metadata,
        fileName: fileName,
        length: length,
        stream: tempFile.openRead(),
        tempFilePath: tempPath,
      );
    }

    throw UnsupportedError('تنسيق النسخة الاحتياطية غير مدعوم: ${format.name}');
  }

  Future<String> _uploadBackupPayload(_DriveBackupPayload payload) async {
    final folderId = await getOrCreateBackupFolder();

    final driveFile = drive.File()
      ..name = payload.fileName
      ..parents = [folderId]
      ..appProperties = {
        'app_name': 'MarinaHotel',
        'backup_timestamp': payload.metadata.backupTimestamp.toIso8601String(),
        'records_count': payload.metadata.totalRecords.toString(),
        'app_version': payload.metadata.appVersion,
        'database_version': payload.metadata.databaseVersion.toString(),
        'device_info': payload.metadata.deviceInfo,
        'format': payload.metadata.format.name,
      };

    final uploadedFile = await _driveApi!.files.create(
      driveFile,
      uploadMedia: drive.Media(payload.stream, payload.length),
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsLastBackupKey, payload.metadata.backupTimestamp.toIso8601String());

    debugPrint('✅ تم رفع النسخة الاحتياطية: ${uploadedFile.id}');
    return uploadedFile.id!;
  }

  Future<String> uploadBackupWithFormat(BackupFormat format) async {
    if (_driveApi == null) {
      throw Exception('يجب تسجيل الدخول في Google Drive أولاً');
    }

    final payload = await _prepareBackupPayload(format);
    try {
      return await _uploadBackupPayload(payload);
    } finally {
      if (payload.tempFilePath != null) {
        await File(payload.tempFilePath!).delete().catchError((_) {});
      }
    }
  }

  /// جلب قائمة النسخ الاحتياطية
  Future<List<DriveBackupFile>> listBackupFiles() async {
    if (_driveApi == null) {
      throw Exception('يجب تسجيل الدخول في Google Drive أولاً');
    }

    try {
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
    } catch (e) {
      debugPrint('❌ خطأ في جلب قائمة النسخ الاحتياطية: $e');
      rethrow;
    }
  }

  /// تنزيل النسخة الاحتياطية
  Future<DownloadedBackup> downloadBackup(DriveBackupFile file) async {
    if (_driveApi == null) {
      throw Exception('يجب تسجيل الدخول في Google Drive أولاً');
    }

    try {
      final media = await _driveApi!.files.get(
        file.fileId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      if (file.format == BackupFormat.json) {
        final List<int> dataStore = [];
        await for (final data in media.stream) {
          dataStore.addAll(data);
        }
        final jsonString = utf8.decode(dataStore);
        final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
        final metadata = backupData.containsKey('metadata')
            ? BackupMetadata.fromJson(backupData['metadata'])
            : file.metadata ??
                BackupMetadata(
                  appVersion: 'unknown',
                  databaseVersion: AppDatabase().schemaVersion,
                  backupTimestamp: file.createdTime,
                  totalRecords: int.tryParse(file.appProperties?['records_count'] ?? '0') ?? 0,
                  deviceInfo: file.appProperties?['device_info'] ?? 'Google Drive',
                  format: BackupFormat.json,
                );
        debugPrint('✅ تم تنزيل النسخة الاحتياطية (JSON): ${file.fileId}');
        return DownloadedBackup.json(backupData, metadata);
      }

      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, '${file.fileId}_${file.fileName}');
      final outFile = File(tempPath);
      final sink = outFile.openWrite();
      await media.stream.pipe(sink);
      await sink.flush();
      await sink.close();

      final metadata = file.metadata ??
          BackupMetadata(
            appVersion: file.appProperties?['app_version'] ?? 'unknown',
            databaseVersion: int.tryParse(file.appProperties?['database_version'] ?? '') ?? 1,
            backupTimestamp: file.createdTime,
            totalRecords: int.tryParse(file.appProperties?['records_count'] ?? '0') ?? 0,
            deviceInfo: file.appProperties?['device_info'] ?? 'Google Drive',
            format: BackupFormat.sqlite,
          );

      debugPrint('✅ تم تنزيل النسخة الاحتياطية (SQLite): ${file.fileId}');
      return DownloadedBackup.sqlite(tempPath, metadata);
    } catch (e) {
      debugPrint('❌ خطأ في تنزيل النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// استعادة البيانات من النسخة الاحتياطية
  Future<void> restoreFromBackup(Map<String, dynamic> backupData) async {
    try {
      final db = getDatabase();

      // التحقق من البيانات الوصفية
      if (!backupData.containsKey('metadata')) {
        throw Exception('النسخة الاحتياطية لا تحتوي على بيانات وصفية');
      }

      final metadata = BackupMetadata.fromJson(backupData['metadata']);
      
      // التحقق من توافق إصدار قاعدة البيانات
      if (metadata.databaseVersion > db.schemaVersion) {
        throw Exception('إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي');
      }

      debugPrint('🔄 بدء استعادة البيانات...');

      // مسح البيانات الموجودة (عدا Outbox)
      await db.delete(db.rooms).go();
      await db.delete(db.bookings).go();
      await db.delete(db.bookingNotes).go();
      await db.delete(db.employees).go();
      await db.delete(db.expenses).go();
      await db.delete(db.cashTransactions).go();
      await db.delete(db.payments).go();
      await db.delete(db.syncState).go();

      // استعادة البيانات
      if (backupData.containsKey('rooms')) {
        final roomsData = backupData['rooms'] as List<dynamic>;
        for (final roomJson in roomsData) {
          await db.into(db.rooms).insert(Room.fromJson(roomJson));
        }
      }

      if (backupData.containsKey('bookings')) {
        final bookingsData = backupData['bookings'] as List<dynamic>;
        for (final bookingJson in bookingsData) {
          await db.into(db.bookings).insert(Booking.fromJson(bookingJson));
        }
      }

      if (backupData.containsKey('booking_notes')) {
        final notesData = backupData['booking_notes'] as List<dynamic>;
        for (final noteJson in notesData) {
          await db.into(db.bookingNotes).insert(BookingNote.fromJson(noteJson));
        }
      }

      if (backupData.containsKey('employees')) {
        final employeesData = backupData['employees'] as List<dynamic>;
        for (final employeeJson in employeesData) {
          await db.into(db.employees).insert(Employee.fromJson(employeeJson));
        }
      }

      if (backupData.containsKey('expenses')) {
        final expensesData = backupData['expenses'] as List<dynamic>;
        for (final expenseJson in expensesData) {
          await db.into(db.expenses).insert(Expense.fromJson(expenseJson));
        }
      }

      if (backupData.containsKey('cash_transactions')) {
        final transactionsData = backupData['cash_transactions'] as List<dynamic>;
        for (final transactionJson in transactionsData) {
          await db.into(db.cashTransactions).insert(CashTransaction.fromJson(transactionJson));
        }
      }

      if (backupData.containsKey('payments')) {
        final paymentsData = backupData['payments'] as List<dynamic>;
        for (final paymentJson in paymentsData) {
          await db.into(db.payments).insert(Payment.fromJson(paymentJson));
        }
      }

      if (backupData.containsKey('sync_state') && backupData['sync_state'] is Map && (backupData['sync_state'] as Map).isNotEmpty) {
        await db.into(db.syncState).insert(SyncStateData.fromJson(backupData['sync_state']));
      }

      debugPrint('✅ تم استعادة ${metadata.totalRecords} سجل بنجاح');
    } catch (e) {
      debugPrint('❌ خطأ في استعادة البيانات: $e');
      rethrow;
    }
  }

  /// جدولة النسخ التلقائي
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
    Duration frequency_duration;

    switch (frequency) {
      case 'daily':
        frequency_duration = const Duration(days: 1);
        break;
      case 'weekly':
        frequency_duration = const Duration(days: 7);
        break;
      case 'monthly':
        frequency_duration = const Duration(days: 30);
        break;
      default:
        frequency_duration = const Duration(days: 1);
    }

    // حساب التأخير الأولي حتى الوقت المحدد
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
      initialDelay = targetTime.add(frequency_duration).difference(now);
    } else {
      initialDelay = targetTime.difference(now);
    }

    try {
      await Workmanager().registerPeriodicTask(
        'autoBackup',
        'autoBackupTask',
        frequency: frequency_duration,
        initialDelay: initialDelay,
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
      );
      
      debugPrint('✅ تم جدولة النسخ التلقائي: $frequency في $timeString');
    } catch (e) {
      debugPrint('❌ خطأ في جدولة النسخ التلقائي: $e');
    }
  }

  /// إلغاء النسخ التلقائي
  Future<void> cancelAutoBackup() async {
    try {
      await Workmanager().cancelByUniqueName('autoBackup');
      debugPrint('✅ تم إلغاء النسخ التلقائي');
    } catch (e) {
      debugPrint('❌ خطأ في إلغاء النسخ التلقائي: $e');
    }
  }

  /// تنفيذ النسخ التلقائي
  Future<void> performAutoBackup({BackupFormat format = BackupFormat.json}) async {
    try {
      if (!isSignedIn) {
        debugPrint('⚠️ المستخدم غير مسجل دخول، تم تخطي النسخ التلقائي');
        return;
      }

      debugPrint('🔄 بدء النسخ التلقائي (${format.name})...');
      final fileId = await uploadBackupWithFormat(format);
      debugPrint('✅ تم النسخ التلقائي بنجاح: $fileId');
    } catch (e) {
      debugPrint('❌ خطأ في النسخ التلقائي: $e');
    }
  }

  /// الحصول على وقت آخر نسخة احتياطية
  Future<DateTime?> getLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString(_prefsLastBackupKey);
    return timeString != null ? DateTime.parse(timeString) : null;
  }

  /// إعدادات النسخ التلقائي
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

  /// تحديد حجم قاعدة البيانات المقدر
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

  void dispose() {
    _driveApi = null;
    _backupFolderId = null;
  }
}