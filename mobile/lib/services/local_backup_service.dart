import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'local_db.dart';
import '../providers/repository_providers.dart';
import 'google_drive_backup_service.dart';
import 'backup_serializers.dart';

class LocalBackupFile {
  final String fileName;
  final String filePath;
  final DateTime createdTime;
  final int sizeBytes;
  final BackupMetadata? metadata;
  final BackupFormat format;

  LocalBackupFile({
    required this.fileName,
    required this.filePath,
    required this.createdTime,
    required this.sizeBytes,
    this.metadata,
    this.format = BackupFormat.json,
  });

  factory LocalBackupFile.fromFile(
    File file, {
    BackupMetadata? metadata,
    BackupFormat format = BackupFormat.json,
  }) {
    final stat = file.statSync();
    return LocalBackupFile(
      fileName: file.path.split('/').last,
      filePath: file.path,
      createdTime: stat.modified,
      sizeBytes: stat.size,
      metadata: metadata,
      format: format,
    );
  }
}

class LocalBackupService {
  static const String _backupFolderName = 'MarinaHotelBackups';
  static const String _backupFilePrefix = 'marina_hotel_backup_';
  static const String _prefsLastLocalBackupKey = 'last_local_backup_timestamp';
  static const String _prefsAutoLocalBackupKey = 'auto_local_backup_enabled';
  static const String _prefsAutoLocalBackupFrequencyKey =
      'auto_local_backup_frequency';
  static const String _prefsLocalBackupPathKey = 'local_backup_path';
  static const String _prefsBackupFormatKey = 'local_backup_format';
  static const String _backupFilePrefixImported = 'imported_backup_';

  Directory? _backupDirectory;

  /// التحقق من الأذونات المطلوبة
  Future<bool> checkPermissions() async {
    try {
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;

        // Android 13+ يتطلب أذونات مختلفة
        if (androidInfo.version.sdkInt >= 33) {
          // للـ Android 13+، نستخدم MANAGE_EXTERNAL_STORAGE أو تطبيق scoped storage
          return await Permission.manageExternalStorage.request().isGranted;
        } else if (androidInfo.version.sdkInt >= 30) {
          // Android 11-12
          return await Permission.manageExternalStorage.request().isGranted;
        } else {
          // Android < 11
          final storagePermission = await Permission.storage.request();
          return storagePermission.isGranted;
        }
      }
      return true; // على iOS أو منصات أخرى
    } catch (e) {
      debugPrint('❌ خطأ في التحقق من الأذونات: $e');
      return false;
    }
  }

  /// الحصول على مجلد النسخ الاحتياطي المحلي
  Future<Directory> getBackupDirectory() async {
    if (_backupDirectory != null) {
      return _backupDirectory!;
    }

    try {
      final Directory selectedDir;

      if (Platform.isAndroid) {
        selectedDir = Directory(
          '/storage/emulated/0/Documents/$_backupFolderName',
        );
      } else {
        selectedDir = await getApplicationDocumentsDirectory();
      }

      if (!await selectedDir.exists()) {
        await selectedDir.create(recursive: true);
        debugPrint('✅ تم إنشاء مجلد النسخ الاحتياطي: ${selectedDir.path}');
      }

      _backupDirectory = selectedDir;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLocalBackupPathKey, _backupDirectory!.path);

      return _backupDirectory!;
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء مجلد النسخ الاحتياطي: $e');
      rethrow;
    }
  }

  /// إنشاء نسخة احتياطية محلية
  Future<String> createLocalBackup({
    BackupFormat format = BackupFormat.json,
  }) async {
    try {
      debugPrint('🔄 بدء إنشاء نسخة احتياطية محلية (${format.name})...');

      final hasPermission = await checkPermissions();
      if (!hasPermission) {
        throw Exception('لا توجد أذونات للوصول للتخزين المحلي');
      }

      final backupDir = await getBackupDirectory();
      final db = getDatabase();
      final timestamp = DateTime.now();
      final baseName =
          '$_backupFilePrefix${timestamp.toIso8601String().split('T')[0]}_${timestamp.millisecondsSinceEpoch}';
      final deviceLabel = Platform.isAndroid ? 'Android Local' : 'iOS Local';

      if (format == BackupFormat.json) {
        final roomsData = await db.select(db.rooms).get();
        final bookingsData = await db.select(db.bookings).get();
        final bookingNotesData = await db.select(db.bookingNotes).get();
        final employeesData = await db.select(db.employees).get();
        final expensesData = await db.select(db.expenses).get();
        final cashTransactionsData = await db.select(db.cashTransactions).get();
        final paymentsData = await db.select(db.payments).get();
        final syncStateData = await db.select(db.syncState).get();
        final debtsData = await db.select(db.debts).get();
        final bookingNightsData = await db.select(db.bookingNights).get();
        final ledgerData = await db.select(db.hotelDayLedger).get();
        final shiftNotesData = await db.select(db.shiftNotes).get();
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
            employeesData.length +
            expensesData.length +
            cashTransactionsData.length +
            paymentsData.length +
            debtsData.length +
            bookingNightsData.length +
            ledgerData.length +
            shiftNotesData.length +
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
          databaseVersion: db.schemaVersion,
          backupTimestamp: timestamp,
          totalRecords: totalRecords,
          deviceInfo: deviceLabel,
          format: BackupFormat.json,
        );

        final backupData = {
          'metadata': metadata.toJson(),
          'rooms': roomsData.map((room) => room.toJson()).toList(),
          'bookings': bookingsData.map((booking) => booking.toJson()).toList(),
          'booking_notes': bookingNotesData
              .map((note) => note.toJson())
              .toList(),
          'employees': employeesData
              .map((employee) => employee.toJson())
              .toList(),
          'expenses': expensesData.map((expense) => expense.toJson()).toList(),
          'cash_transactions': cashTransactionsData
              .map((transaction) => transaction.toJson())
              .toList(),
          'payments': paymentsData.map((payment) => payment.toJson()).toList(),
          'debts': debtsData.map((debt) => debt.toJson()).toList(),
          'booking_nights': bookingNightsData
              .map((night) => night.toJson())
              .toList(),
          'hotel_day_ledger': ledgerData
              .map((entry) => entry.toJson())
              .toList(),
          'shift_notes': shiftNotesData
              .map((note) => note.toJson())
              .toList(),
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
          'sync_state': syncStateData.isNotEmpty
              ? syncStateData.first.toJson()
              : {},
        };

        final filePath = '${backupDir.path}/$baseName.json';
        final file = File(filePath);
        final jsonString = const JsonEncoder.withIndent(
          '  ',
        ).convert(backupData);
        await file.writeAsString(jsonString);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsLastLocalBackupKey,
          timestamp.toIso8601String(),
        );

        debugPrint('✅ تم إنشاء النسخة الاحتياطية المحلية (JSON): $filePath');
        debugPrint('📊 السجلات المحفوظة: $totalRecords');
        debugPrint('📁 حجم الملف: ${await file.length()} بايت');

        return filePath;
      }

      if (format == BackupFormat.sqlite) {
        final counts = await _collectRecordCounts(db);
        final totalRecords = counts.values.fold<int>(
          0,
          (prev, element) => prev + element,
        );
        final metadata = BackupMetadata(
          appVersion: '1.2.0+3',
          databaseVersion: db.schemaVersion,
          backupTimestamp: timestamp,
          totalRecords: totalRecords,
          deviceInfo: deviceLabel,
          format: BackupFormat.sqlite,
        );

        final dbPath = await _getDatabaseFilePath();
        final destinationPath = '${backupDir.path}/$baseName.sqlite';

        try {
          await db.customSelect('PRAGMA wal_checkpoint(FULL)').get();
        } catch (_) {}
        try {
          await db.customStatement('VACUUM');
        } catch (_) {}

        await File(dbPath).copy(destinationPath);
        final metadataFile = File(_metadataFilePath(destinationPath));
        await metadataFile.writeAsString(jsonEncode(metadata.toJson()));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsLastLocalBackupKey,
          timestamp.toIso8601String(),
        );

        debugPrint(
          '✅ تم إنشاء النسخة الاحتياطية المحلية (SQLite): $destinationPath',
        );
        return destinationPath;
      }

      throw UnsupportedError(
        'تنسيق النسخة الاحتياطية غير مدعوم: ${format.name}',
      );
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء النسخة الاحتياطية المحلية: $e');
      rethrow;
    }
  }

  Future<Map<String, int>> _collectRecordCounts(AppDatabase db) async {
    Future<int> count(String table) async {
      final row = await db
          .customSelect('SELECT COUNT(*) AS count FROM $table')
          .getSingle();
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

  Future<Map<String, int>> _collectRecordCountsFromRawDb(Database db) async {
    Future<int> count(String table) async {
      final result = await db.rawQuery('SELECT COUNT(*) AS count FROM $table');
      if (result.isEmpty) {
        return 0;
      }
      final value = result.first['count'];
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

  Future<String> _getDatabaseFilePath() async {
    final databasesPath = await getDatabasesPath();
    return p.join(databasesPath, 'marina_hotel.db');
  }

  /// عرض قائمة النسخ الاحتياطية المحلية
  Future<List<LocalBackupFile>> listLocalBackups() async {
    try {
      final backupDir = await getBackupDirectory();

      if (!await backupDir.exists()) {
        return [];
      }

      final files = backupDir
          .listSync()
          .where(
            (entity) =>
                entity is File &&
                (entity.path.endsWith('.json') ||
                    entity.path.endsWith('.sqlite')) &&
                entity.path.contains(_backupFilePrefix),
          )
          .map((entity) => entity as File)
          .toList();

      final backupFiles = <LocalBackupFile>[];

      for (final file in files) {
        final extension = p.extension(file.path).toLowerCase();
        final format = extension == '.sqlite'
            ? BackupFormat.sqlite
            : BackupFormat.json;

        try {
          BackupMetadata? metadata;

          if (format == BackupFormat.json) {
            final content = await file.readAsString();
            final jsonData = jsonDecode(content) as Map<String, dynamic>;
            if (jsonData.containsKey('metadata')) {
              final metadataSource = jsonData['metadata'];
              if (metadataSource is Map) {
                metadata = BackupMetadata.fromJson(
                  Map<String, dynamic>.from(metadataSource),
                );
              }
            }
          } else {
            final metadataFile = File(_metadataFilePath(file.path));
            if (await metadataFile.exists()) {
              final metaContent = await metadataFile.readAsString();
              metadata = BackupMetadata.fromJson(
                jsonDecode(metaContent) as Map<String, dynamic>,
              );
            }
          }

          backupFiles.add(
            LocalBackupFile.fromFile(file, metadata: metadata, format: format),
          );
        } catch (e) {
          debugPrint('⚠️ خطأ في قراءة ملف النسخة الاحتياطية ${file.path}: $e');
          backupFiles.add(LocalBackupFile.fromFile(file, format: format));
        }
      }

      // ترتيب حسب تاريخ الإنشاء (الأحدث أولاً)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      debugPrint('✅ تم جلب ${backupFiles.length} نسخة احتياطية محلية');
      return backupFiles;
    } catch (e) {
      debugPrint('❌ خطأ في جلب قائمة النسخ الاحتياطية المحلية: $e');
      return [];
    }
  }

  String _metadataFilePath(String sqliteFilePath) =>
      p.setExtension(sqliteFilePath, '.metadata.json');

  /// استعادة من نسخة احتياطية محلية
  Future<void> restoreFromLocalBackup(String filePath) async {
    try {
      debugPrint('🔄 بدء استعادة النسخة الاحتياطية من: $filePath');

      final extension = p.extension(filePath).toLowerCase();
      if (extension == '.sqlite') {
        await _restoreFromSqliteBackup(filePath);
        return;
      }

      if (extension == '.json') {
        await _restoreFromJsonBackup(filePath);
        return;
      }

      throw UnsupportedError(
        'تنسيق النسخة الاحتياطية غير مدعوم للاستعادة: $extension',
      );
    } catch (e) {
      debugPrint('❌ خطأ في استعادة البيانات من النسخة المحلية: $e');
      rethrow;
    }
  }

  Future<void> _restoreFromJsonBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }

    final jsonString = await file.readAsString();
    final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

    if (!backupData.containsKey('metadata')) {
      throw Exception('النسخة الاحتياطية لا تحتوي على بيانات وصفية');
    }

    final metadataSource = backupData['metadata'];
    if (metadataSource is! Map) {
      throw Exception('صيغة بيانات النسخة الاحتياطية غير صالحة');
    }
    final metadata = BackupMetadata.fromJson(
      Map<String, dynamic>.from(metadataSource),
    );
    if (metadata.databaseVersion > AppDatabase().schemaVersion) {
      throw Exception(
        'إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي',
      );
    }

    debugPrint('🔄 بدء استعادة البيانات من نسخة JSON...');
    final db = getDatabase();

    // تعطيل FOREIGN KEYS أثناء الحذف والاستعادة بالكامل
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      // حذف جميع الجداول بالترتيب الصحيح (من الأطفال إلى الآباء)
      // لتجنب FOREIGN KEY constraint errors
      await db.delete(db.payments).go(); // يعتمد على bookings
      await db.delete(db.debts).go(); // يعتمد على bookings
      await db.delete(db.bookingNotes).go(); // يعتمد على bookings
      await db.delete(db.cashTransactions).go(); // يعتمد على bookings
      await db.delete(db.bookings).go(); // يعتمد على rooms
      await db.delete(db.expenses).go(); // يعتمد على employees
      await db.delete(db.employees).go();
      await db.delete(db.rooms).go();
      await db.delete(db.syncState).go();

      Future<void> insertList<T>(
        String key,
        Future<void> Function(Map<String, dynamic> json) insert,
      ) async {
        if (!backupData.containsKey(key)) {
          return;
        }
        final list = backupData[key] as List<dynamic>;
        for (final json in list) {
          await insert(Map<String, dynamic>.from(json as Map));
        }
      }

      await insertList('rooms', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = Room.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.rooms).insertOnConflictUpdate(data);
      });
      await insertList('employees', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = Employee.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.employees).insertOnConflictUpdate(data);
      });
      await insertList('bookings', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = Booking.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.bookings).insertOnConflictUpdate(data);
      });
      await insertList('booking_notes', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = BookingNote.fromJson(
          map,
          serializer: lenientValueSerializer,
        );
        await db.into(db.bookingNotes).insertOnConflictUpdate(data);
      });
      await insertList('cash_transactions', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = CashTransaction.fromJson(
          map,
          serializer: lenientValueSerializer,
        );
        await db.into(db.cashTransactions).insertOnConflictUpdate(data);
      });
      await insertList('expenses', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = Expense.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.expenses).insertOnConflictUpdate(data);
      });
      await insertList('payments', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = Payment.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.payments).insertOnConflictUpdate(data);
      });
      await insertList('debts', (json) async {
        final map = Map<String, dynamic>.from(json as Map);
        final data = Debt.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.debts).insertOnConflictUpdate(data);
      });

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

      debugPrint(
        '✅ تم استعادة ${metadata.totalRecords} سجل بنجاح من نسخة JSON',
      );
    } finally {
      // إعادة تشغيل FOREIGN KEYS بعد الانتهاء من الاستعادة بالكامل
      await db.customStatement('PRAGMA foreign_keys = ON');
      debugPrint('🔓 تم إعادة تشغيل FOREIGN KEYS');
    }
  }

  Future<void> _restoreFromSqliteBackup(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }

    BackupMetadata? metadata;
    final metadataFile = File(_metadataFilePath(filePath));
    if (await metadataFile.exists()) {
      final metaContent = await metadataFile.readAsString();
      metadata = BackupMetadata.fromJson(
        jsonDecode(metaContent) as Map<String, dynamic>,
      );
      if (metadata.databaseVersion > AppDatabase().schemaVersion) {
        throw Exception(
          'إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي',
        );
      }
    }

    final dbPath = await _getDatabaseFilePath();
    debugPrint('🗃️ مسار قاعدة البيانات الحالي: $dbPath');

    try {
      await deleteDatabase(dbPath);
    } catch (e) {
      debugPrint('⚠️ تعذر حذف قاعدة البيانات الحالية: $e');
    }

    await _deleteSidecarFiles(dbPath);
    await File(filePath).copy(dbPath);
    await _deleteSidecarFiles(dbPath);

    if (metadata != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsLastLocalBackupKey,
        metadata.backupTimestamp.toIso8601String(),
      );
      debugPrint(
        '✅ تم استعادة النسخة الاحتياطية (SQLite) بتاريخ ${metadata.backupTimestamp}',
      );
    } else {
      debugPrint(
        '✅ تم استعادة النسخة الاحتياطية (SQLite) بدون بيانات وصفية إضافية',
      );
    }
  }

  Future<void> _deleteSidecarFiles(String dbPath) async {
    for (final suffix in ['-wal', '-shm']) {
      final file = File('$dbPath$suffix');
      if (await file.exists()) {
        try {
          await file.delete();
        } catch (e) {
          debugPrint('⚠️ تعذر حذف الملف المساعد $suffix: $e');
        }
      }
    }
  }

  /// مشاركة نسخة احتياطية
  Future<void> shareBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('ملف النسخة الاحتياطية غير موجود');
      }

      final fileName = filePath.split('/').last;

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'نسخة احتياطية - تطبيق مارينا هوتيل',
        text:
            'نسخة احتياطية من بيانات تطبيق مارينا هوتيل\nاسم الملف: $fileName',
      );

      debugPrint('✅ تم مشاركة النسخة الاحتياطية: $fileName');
    } catch (e) {
      debugPrint('❌ خطأ في مشاركة النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// استيراد نسخة احتياطية من ملف خارجي
  Future<String> importBackupFromFile() async {
    try {
      debugPrint('🔄 بدء استيراد نسخة احتياطية من ملف خارجي...');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'sqlite'],
        allowMultiple: false,
      );

      if (result == null || result.files.isEmpty) {
        throw Exception('لم يتم اختيار ملف');
      }

      final pickedFile = result.files.first;
      final pickedPath = pickedFile.path;
      if (pickedPath == null) {
        throw Exception('مسار الملف غير صحيح');
      }

      final extension = p.extension(pickedPath).toLowerCase();
      final sourceFile = File(pickedPath);
      final backupDir = await getBackupDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final baseName = '$_backupFilePrefixImported$timestamp';

      if (extension == '.json') {
        final content = await sourceFile.readAsString();
        final jsonData = jsonDecode(content) as Map<String, dynamic>;
        if (!jsonData.containsKey('metadata')) {
          throw Exception('الملف المختار ليس نسخة احتياطية صالحة');
        }

        final newFilePath = '${backupDir.path}/$baseName.json';
        await sourceFile.copy(newFilePath);
        debugPrint('✅ تم استيراد النسخة الاحتياطية (JSON): $newFilePath');
        return newFilePath;
      }

      if (extension == '.sqlite') {
        final newFilePath = '${backupDir.path}/$baseName.sqlite';
        await sourceFile.copy(newFilePath);

        Database? tempDb;
        try {
          tempDb = await openDatabase(newFilePath, readOnly: true);
          final pragma = await tempDb.rawQuery('PRAGMA user_version;');
          final rawVersion = pragma.isNotEmpty ? pragma.first.values.first : 0;
          final dbVersion = rawVersion is int
              ? rawVersion
              : rawVersion is num
              ? rawVersion.toInt()
              : 0;

          if (dbVersion > AppDatabase().schemaVersion) {
            throw Exception(
              'إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي',
            );
          }

          final counts = await _collectRecordCountsFromRawDb(tempDb);
          final totalRecords = counts.values.fold<int>(
            0,
            (prev, element) => prev + element,
          );
          final metadata = BackupMetadata(
            appVersion: '1.2.0+3',
            databaseVersion: dbVersion,
            backupTimestamp: DateTime.now(),
            totalRecords: totalRecords,
            deviceInfo: 'Imported Local',
            format: BackupFormat.sqlite,
          );

          final metadataFile = File(_metadataFilePath(newFilePath));
          await metadataFile.writeAsString(jsonEncode(metadata.toJson()));
          debugPrint('✅ تم استيراد النسخة الاحتياطية (SQLite): $newFilePath');
          return newFilePath;
        } catch (e) {
          try {
            await File(newFilePath).delete();
          } catch (_) {}
          rethrow;
        } finally {
          await tempDb?.close();
        }
      }

      throw UnsupportedError('تنسيق الملف غير مدعوم للاستيراد: $extension');
    } catch (e) {
      debugPrint('❌ خطأ في استيراد النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// حذف نسخة احتياطية محلية
  Future<void> deleteLocalBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('✅ تم حذف النسخة الاحتياطية: $filePath');
      }
    } catch (e) {
      debugPrint('❌ خطأ في حذف النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// تصدير نسخة احتياطية إلى مجلد Downloads
  Future<String> exportToDownloads() async {
    try {
      debugPrint('🔄 تصدير نسخة احتياطية إلى مجلد Downloads...');

      // إنشاء النسخة الاحتياطية أولاً
      await createLocalBackup();

      // البحث عن أحدث نسخة
      final backups = await listLocalBackups();
      if (backups.isEmpty) {
        throw Exception('لا توجد نسخ احتياطية متاحة');
      }

      final latestBackup = backups.first;

      // محاولة الحصول على مجلد Downloads
      Directory? downloadsDir;

      if (Platform.isAndroid) {
        // محاولة الوصول لـ Downloads directory
        final externalDirs = await getExternalStorageDirectories(
          type: StorageDirectory.downloads,
        );
        if (externalDirs != null && externalDirs.isNotEmpty) {
          downloadsDir = externalDirs.first;
        } else {
          // fallback إلى external storage
          final externalStorage = await getExternalStorageDirectories();
          if (externalStorage != null && externalStorage.isNotEmpty) {
            downloadsDir = Directory(
              '${externalStorage.first.parent.parent.parent.parent.path}/Download',
            );
          }
        }
      }

      downloadsDir ??= await getBackupDirectory();

      // نسخ الملف
      final sourceFile = File(latestBackup.filePath);
      final timestamp = DateTime.now();
      final exportFileName =
          'marina_hotel_export_${timestamp.toIso8601String().split('T')[0]}.json';
      final exportPath = '${downloadsDir.path}/$exportFileName';

      await sourceFile.copy(exportPath);

      debugPrint('✅ تم تصدير النسخة الاحتياطية إلى: $exportPath');
      return exportPath;
    } catch (e) {
      debugPrint('❌ خطأ في تصدير النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// إعدادات النسخ التلقائي المحلي
  Future<void> setAutoLocalBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsAutoLocalBackupKey, enabled);
  }

  Future<bool> isAutoLocalBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_prefsAutoLocalBackupKey)) {
      await prefs.setBool(_prefsAutoLocalBackupKey, true);
      return true;
    }
    return prefs.getBool(_prefsAutoLocalBackupKey) ?? true;
  }

  Future<void> setPreferredBackupFormat(BackupFormat format) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsBackupFormatKey, format.name);
  }

  Future<BackupFormat> getPreferredBackupFormat() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsBackupFormatKey);
    return BackupFormat.values.firstWhere(
      (format) => format.name == raw,
      orElse: () => BackupFormat.json,
    );
  }

  Future<void> setAutoLocalBackupFrequency(String frequency) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsAutoLocalBackupFrequencyKey, frequency);
  }

  Future<String> getAutoLocalBackupFrequency() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsAutoLocalBackupFrequencyKey) ?? 'daily';
  }

  /// الحصول على وقت آخر نسخة احتياطية محلية
  Future<DateTime?> getLastLocalBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    final timeString = prefs.getString(_prefsLastLocalBackupKey);
    return timeString != null ? DateTime.parse(timeString) : null;
  }

  /// تنظيف النسخ القديمة (الاحتفاظ بآخر 10 نسخ فقط)
  Future<void> cleanOldBackups({int keepCount = 10}) async {
    try {
      final backups = await listLocalBackups();

      if (backups.length <= keepCount) {
        return; // لا حاجة للتنظيف
      }

      // ترتيب حسب التاريخ (الأحدث أولاً) وحذف القديم
      backups.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      final backupsToDelete = backups.skip(keepCount).toList();

      for (final backup in backupsToDelete) {
        await deleteLocalBackup(backup.filePath);
      }

      debugPrint('✅ تم تنظيف ${backupsToDelete.length} نسخة احتياطية قديمة');
    } catch (e) {
      debugPrint('❌ خطأ في تنظيف النسخ القديمة: $e');
    }
  }

  /// تقدير حجم جميع النسخ المحلية
  Future<int> getTotalBackupsSize() async {
    try {
      final backups = await listLocalBackups();
      return backups.fold<int>(0, (total, backup) => total + backup.sizeBytes);
    } catch (e) {
      debugPrint('❌ خطأ في حساب حجم النسخ: $e');
      return 0;
    }
  }

  /// الحصول على معلومات مجلد النسخ الاحتياطي
  Future<Map<String, dynamic>> getBackupFolderInfo() async {
    try {
      final backupDir = await getBackupDirectory();
      final backups = await listLocalBackups();
      final totalSize = await getTotalBackupsSize();

      return {
        'path': backupDir.path,
        'exists': await backupDir.exists(),
        'backups_count': backups.length,
        'total_size_bytes': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      debugPrint('❌ خطأ في الحصول على معلومات مجلد النسخ: $e');
      return {};
    }
  }
}
