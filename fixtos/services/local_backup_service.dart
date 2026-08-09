import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../providers/repository_providers.dart';
import '../utils/app_logger.dart';
import '../utils/debug_log.dart';
import '../utils/json_isolate.dart';
import 'backup_serializers.dart';
import 'google_drive_backup_service.dart';
import 'local_db.dart';
import 'sqlite_backup_restore.dart';

export 'google_drive_backup_service.dart' show BackupFormat;

class LocalBackupFile {
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
  final String fileName;
  final String filePath;
  final DateTime createdTime;
  final int sizeBytes;
  final BackupMetadata? metadata;
  final BackupFormat format;
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
      dlog(() => '❌ خطأ في التحقق من الأذونات: $e');
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

      if (!selectedDir.existsSync()) {
        await selectedDir.create(recursive: true);
        dlog(() => '✅ تم إنشاء مجلد النسخ الاحتياطي: ${selectedDir.path}');
      }

      _backupDirectory = selectedDir;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsLocalBackupPathKey, _backupDirectory!.path);

      return _backupDirectory!;
    } catch (e) {
      dlog(() => '❌ خطأ في إنشاء مجلد النسخ الاحتياطي: $e');
      rethrow;
    }
  }

  /// إنشاء نسخة احتياطية محلية
  Future<String> createLocalBackup({
    BackupFormat format = BackupFormat.json,
  }) async {
    try {
      dlog(() => '🔄 بدء إنشاء نسخة احتياطية محلية (${format.name})...');

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
        final bookingPriceAdjData = await db
            .select(db.bookingPriceAdjustments)
            .get();
        final auditLogsData = await db.select(db.auditLogs).get();
        final paymentVoidsData = await db.select(db.paymentVoids).get();
        final guestInfosData = await db.select(db.guestInfos).get();
        final salaryWithdrawalsData = await db
            .select(db.salaryWithdrawals)
            .get();
        final salaryCarryOverLogsData = await db
            .select(db.salaryCarryOverLogs)
            .get();

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

        final totalRecords = tableData.totalRecords;

        final metadata = BackupMetadata(
          appVersion: '1.2.0+3',
          databaseVersion: db.schemaVersion,
          backupTimestamp: timestamp,
          totalRecords: totalRecords,
          deviceInfo: deviceLabel,
        );

        final backupData = tableData.toBackupDataMap(
          metadata: metadata.toJson(),
          syncStateData: syncStateData.isNotEmpty
              ? syncStateData.first.toJson()
              : <String, dynamic>{},
        );

        final filePath = '${backupDir.path}/$baseName.json.gz';
        final file = File(filePath);

        // JSON مضغوط بدون مسافات + gzip level 6
        final jsonBytes = utf8.encode(jsonEncode(backupData));
        final compressedBytes = GZipCodec().encode(jsonBytes);
        await file.writeAsBytes(compressedBytes);

        dlog(
          () =>
              '✅ نسخة محلية مضغوطة: '
              '${(jsonBytes.length / 1024).toStringAsFixed(1)} KB → '
              '${(compressedBytes.length / 1024).toStringAsFixed(1)} KB',
        );

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsLastLocalBackupKey,
          timestamp.toIso8601String(),
        );

        dlog(() => '✅ تم إنشاء النسخة الاحتياطية المحلية (JSON): $filePath');
        dlog(() => '📊 السجلات المحفوظة: $totalRecords');
        // ✅ Pre-existing fix: استخدام lengthSync() بدلاً من await داخل lambda
        dlog(() => '📁 حجم الملف: ${file.lengthSync()} بايت');

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
        } catch (e, st) {
          AppLogger.error(
            'فشل تنفيذ WAL checkpoint',
            tag: 'BACKUP',
            error: e,
            stackTrace: st,
          );
        }
        try {
          await db.customStatement('VACUUM');
        } catch (e, st) {
          AppLogger.error(
            'فشل تنفيذ VACUUM',
            tag: 'BACKUP',
            error: e,
            stackTrace: st,
          );
        }

        await File(dbPath).copy(destinationPath);
        final metadataFile = File(_metadataFilePath(destinationPath));
        await metadataFile.writeAsString(jsonEncode(metadata.toJson()));

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          _prefsLastLocalBackupKey,
          timestamp.toIso8601String(),
        );

        dlog(
          () =>
              '✅ تم إنشاء النسخة الاحتياطية المحلية (SQLite): $destinationPath',
        );
        return destinationPath;
      }

      throw UnsupportedError(
        'تنسيق النسخة الاحتياطية غير مدعوم: ${format.name}',
      );
    } catch (e) {
      dlog(() => '❌ خطأ في إنشاء النسخة الاحتياطية المحلية: $e');
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

      if (!backupDir.existsSync()) {
        return [];
      }

      final files = backupDir
          .listSync()
          .where(
            (entity) =>
                entity is File &&
                (entity.path.endsWith('.json.gz') ||
                    entity.path.endsWith('.json') ||
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
        // ignore: unused_local_variable
        final isGz = extension == '.gz';

        try {
          BackupMetadata? metadata;

          if (format == BackupFormat.json) {
            // قراءة مع دعم فك ضغط gzip
            final List<int> rawBytes = await file.readAsBytes();
            String content;
            if (rawBytes.length >= 2 &&
                rawBytes[0] == 0x1f &&
                rawBytes[1] == 0x8b) {
              content = utf8.decode(gzip.decode(rawBytes));
            } else {
              content = utf8.decode(rawBytes);
            }
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
            if (metadataFile.existsSync()) {
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
          dlog(() => '⚠️ خطأ في قراءة ملف النسخة الاحتياطية ${file.path}: $e');
          backupFiles.add(LocalBackupFile.fromFile(file, format: format));
        }
      }

      // ترتيب حسب تاريخ الإنشاء (الأحدث أولاً)
      backupFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));

      dlog(() => '✅ تم جلب ${backupFiles.length} نسخة احتياطية محلية');
      return backupFiles;
    } catch (e) {
      dlog(() => '❌ خطأ في جلب قائمة النسخ الاحتياطية المحلية: $e');
      return [];
    }
  }

  String _metadataFilePath(String sqliteFilePath) =>
      p.setExtension(sqliteFilePath, '.metadata.json');

  /// استعادة من نسخة احتياطية محلية
  Future<void> restoreFromLocalBackup(String filePath) async {
    try {
      dlog(() => '🔄 بدء استعادة النسخة الاحتياطية من: $filePath');

      final extension = p.extension(filePath).toLowerCase();
      if (extension == '.sqlite') {
        await _restoreFromSqliteBackup(filePath);
        return;
      }

      if (extension == '.json' || extension == '.gz') {
        await _restoreFromJsonBackup(filePath);
        return;
      }

      throw UnsupportedError(
        'تنسيق النسخة الاحتياطية غير مدعوم للاستعادة: $extension',
      );
    } catch (e) {
      dlog(() => '❌ خطأ في استعادة البيانات من النسخة المحلية: $e');
      rethrow;
    }
  }

  Future<void> _restoreFromJsonBackup(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }

    // فك الضغط تلقائياً مع دعم النسخ القديمة غير المضغوطة
    final List<int> rawBytes = await file.readAsBytes();
    List<int> decodedBytes;
    if (rawBytes.length >= 2 && rawBytes[0] == 0x1f && rawBytes[1] == 0x8b) {
      decodedBytes = gzip.decode(rawBytes);
      dlog(
        () =>
            '📦 فك ضغط gzip: ${(rawBytes.length / 1024).toStringAsFixed(1)} KB → ${(decodedBytes.length / 1024).toStringAsFixed(1)} KB',
      );
    } else {
      decodedBytes = rawBytes;
    }
    final jsonString = utf8.decode(decodedBytes);
    // ✅ Performance: استخدم Isolate لـ JSON parsing للأحمال الكبيرة
    // (backup files can be 10+ MB → causes ANR on weak devices)
    final backupData = await JsonIsolate.decodeAsMap(jsonString);

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

    dlog('🔄 بدء استعادة البيانات من نسخة JSON...');
    final db = getDatabase();

    // تعطيل FOREIGN KEYS أثناء الحذف والاستعادة بالكامل
    // (يجب أن يكون خارج transaction لأن SQLite يتجاهل PRAGMA داخل transaction)
    await db.customStatement('PRAGMA foreign_keys = OFF');
    try {
      // ✅ إصلاح حرج (audit agent-7 F.4 + engineer recommendation):
      // لف كل عمليات الحذف والإدراج في transaction واحد لضمان atomicity.
      // إذا فشل أي جزء → rollback تلقائي → لا قاعدة بيانات ناقصة.
      await db.transaction(() async {
        // ✅ إصلاح حرج (audit agent-7, agent-10):
        // كانت الاستعادة تحذف وتُدرج فقط 8 جداول، مما يُسبب فقدان صامت
        // لـ 12 جدولاً آخر (booking_nights, shift_notes, salary_cycles, ...).
        // الآن نحذف كل الجداول الـ20 بالترتيب الصحيح (children قبل parents):
        // Level 2 (FK→ Level 0/1)
        await db.delete(db.salaryPayments).go(); // FK→ salary_cycles
        await db.delete(db.salaryWithdrawals).go(); // FK→ employees
        await db.delete(db.salaryCarryOverLogs).go(); // FK→ employees
        await db.delete(db.integrityViolations).go(); // FK→ auto_fix_runs
        await db.delete(db.bookingPriceAdjustments).go(); // FK→ bookings
        await db.delete(db.bookingNights).go(); // FK→ bookings
        await db.delete(db.bookingNotes).go(); // FK→ bookings
        await db.delete(db.debts).go(); // FK→ bookings
        await db.delete(db.payments).go(); // FK→ bookings, cash_transactions
        // Level 1
        await db.delete(db.bookings).go(); // FK→ rooms
        await db.delete(db.salaryCycles).go(); // FK→ employees
        await db.delete(db.syncConflicts).go(); // FK→ sync_log
        // Level 0
        await db.delete(db.expenses).go();
        await db.delete(db.cashTransactions).go();
        await db.delete(db.employees).go();
        await db.delete(db.rooms).go();
        await db.delete(db.hotelDayLedger).go();
        await db.delete(db.shiftNotes).go();
        await db.delete(db.priceAdjustments).go();
        await db.delete(db.auditLogs).go();
        await db.delete(db.paymentVoids).go();
        await db.delete(db.guestInfos).go();
        await db.delete(db.autoFixRuns).go();
        await db.delete(db.appSessions).go();
        await db.delete(db.outbox).go();
        await db.delete(db.syncQueue).go();
        await db.delete(db.syncLog).go();
        await db.delete(db.restoreFixLog).go();
        await db.delete(db.syncState).go();

        Future<void> insertList<T>(
          String key,
          Future<void> Function(Map<String, dynamic> json) insert,
        ) async {
          if (!backupData.containsKey(key)) {
            dlog(
              () =>
                  '⚠️ النسخة الاحتياطية لا تحتوي على الجدول "$key" — تم التخطي',
            );
            return;
          }
          final list = backupData[key] as List<dynamic>;
          for (final json in list) {
            await insert(Map<String, dynamic>.from(json as Map));
          }
        }

        // ✅ الاستعادة بالترتيب الصحيح (parents قبل children):
        // Level 0
        await insertList<dynamic>('rooms', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = Room.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.rooms).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('employees', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = Employee.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.employees).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('cash_transactions', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = CashTransaction.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.cashTransactions).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('shift_notes', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = ShiftNote.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.shiftNotes).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('hotel_day_ledger', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = HotelDayLedgerEntry.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.hotelDayLedger).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('price_adjustments', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = PriceAdjustment.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.priceAdjustments).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('audit_logs', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = AuditLog.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.auditLogs).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('payment_voids', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = PaymentVoid.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.paymentVoids).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('guest_infos', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = GuestInfo.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.guestInfos).insertOnConflictUpdate(data);
        });
        // Level 1
        await insertList<dynamic>('bookings', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = Booking.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.bookings).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('expenses', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = Expense.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.expenses).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('salary_cycles', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = SalaryCycle.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.salaryCycles).insertOnConflictUpdate(data);
        });
        // Level 2
        await insertList<dynamic>('booking_notes', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = BookingNote.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.bookingNotes).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('booking_nights', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = BookingNight.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.bookingNights).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('booking_price_adjustments', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = BookingPriceAdjustment.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db
              .into(db.bookingPriceAdjustments)
              .insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('payments', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = Payment.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.payments).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('debts', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = Debt.fromJson(map, serializer: lenientValueSerializer);
          await db.into(db.debts).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('salary_payments', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = SalaryPayment.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.salaryPayments).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('salary_withdrawals', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = SalaryWithdrawal.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.salaryWithdrawals).insertOnConflictUpdate(data);
        });
        await insertList<dynamic>('salary_carry_over_logs', (json) async {
          final map = Map<String, dynamic>.from(json as Map);
          final data = SalaryCarryOverLog.fromJson(
            map,
            serializer: lenientValueSerializer,
          );
          await db.into(db.salaryCarryOverLogs).insertOnConflictUpdate(data);
        });

        // BUG-3 FIX: Don't restore sync_state - let new device sync from scratch
        // sync_state contains lastPullTs/deviceId from source device
        if (backupData.containsKey('sync_state')) {
          await db.delete(db.syncState).go();
          dlog('🔄 تم مسح sync_state — الجهاز الجديد سيبدأ مزامنة كاملة');
        }
      }); // ✅ نهاية transaction — atomic: إما كل العمليات تنجح أو تفشل معاً

      dlog(
        () =>
            '✅ تم استعادة ${metadata.totalRecords} سجل بنجاح من نسخة JSON '
            '(جميع الجداول الـ20) — atomic transaction',
      );
    } finally {
      // إعادة تشغيل FOREIGN KEYS بعد الانتهاء من الاستعادة بالكامل
      await db.customStatement('PRAGMA foreign_keys = ON');
      dlog('🔓 تم إعادة تشغيل FOREIGN KEYS');

      // ✅ تحقق من سلامة المفاتيح الأجنبية بعد إعادة التفعيل
      try {
        final violations = await db
            .customSelect(
              'PRAGMA foreign_key_check',
              readsFrom: Set.unmodifiable({}),
            )
            .get();
        if (violations.isNotEmpty) {
          developer.log(
            '⚠️ FK violations after sync: ${violations.length} rows',
            name: 'SyncSafety',
          );
        }
      } catch (_) {}
    }
  }

  Future<void> _restoreFromSqliteBackup(String filePath) async {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw Exception('ملف النسخة الاحتياطية غير موجود');
    }

    BackupMetadata? metadata;
    final metadataFile = File(_metadataFilePath(filePath));
    if (metadataFile.existsSync()) {
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

    // ✅ إصلاح (2026-06-28): استخدام SqliteBackupRestore.restoreDatabase
    // بدلاً من deleteDatabase + copy المباشر.
    // الأسباب:
    //   1. restoreDatabase يُغلق اتصال Drift أولاً (يمنع file locks)
    //   2. يستبدل ذرياً عبر temp file + rename
    //   3. يحتفظ بنسخة .pre_restore للأمان
    //   4. يُعيد فتح DB بعد الاستعادة
    // المنطق القديم كان يُسبب فقدان بيانات إذا فشل copy بعد deleteDatabase.
    dlog('🗃️ استعادة نسخة SQLite عبر SqliteBackupRestore...');

    // التحقق من سلامة الملف قبل الاستعادة (basic integrity check)
    try {
      final bytes = await file.readAsBytes();
      // SQLite header: "SQLite format 3\0" (16 bytes)
      if (bytes.length < 16 ||
          bytes[0] != 0x53 || // 'S'
          bytes[1] != 0x51 || // 'Q'
          bytes[2] != 0x4c || // 'L'
          bytes[3] != 0x69) {
        // 'i'
        throw Exception(
          'الملف ليس قاعدة بيانات SQLite صالحة (header غير مطابق)',
        );
      }
      dlog(() => '✅ تم التحقق من header SQLite (${bytes.length} بايت)');
    } catch (e) {
      dlog(() => '❌ فشل التحقق من سلامة ملف SQLite: $e');
      rethrow;
    }

    await SqliteBackupRestore.restoreDatabase(filePath);

    if (metadata != null) {
      final ts = metadata.backupTimestamp;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _prefsLastLocalBackupKey,
        ts.toIso8601String(),
      );
      dlog(() => '✅ تم استعادة النسخة الاحتياطية (SQLite) بتاريخ $ts');
    } else {
      dlog('✅ تم استعادة النسخة الاحتياطية (SQLite) بدون بيانات وصفية إضافية');
    }
  }

  // ✅ تمت إزالة _deleteSidecarFiles (2026-06-28) — غير مستخدم بعد
  // التحويل إلى SqliteBackupRestore.restoreDatabase الذي يتعامل مع
  // الملفات المساعدة (-wal, -shm) داخلياً.

  /// مشاركة نسخة احتياطية
  Future<void> shareBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (!file.existsSync()) {
        throw Exception('ملف النسخة الاحتياطية غير موجود');
      }

      final fileName = filePath.split('/').last;

      await Share.shareXFiles(
        [XFile(filePath)],
        subject: 'نسخة احتياطية - تطبيق مارينا هوتيل',
        text:
            'نسخة احتياطية من بيانات تطبيق مارينا هوتيل\nاسم الملف: $fileName',
      );

      dlog(() => '✅ تم مشاركة النسخة الاحتياطية: $fileName');
    } catch (e) {
      dlog(() => '❌ خطأ في مشاركة النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// استيراد نسخة احتياطية من ملف خارجي
  Future<String> importBackupFromFile() async {
    try {
      dlog('🔄 بدء استيراد نسخة احتياطية من ملف خارجي...');

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'sqlite', 'gz'],
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

      if (extension == '.json' || extension == '.gz') {
        // فك الضغط تلقائياً إن كان مضغوطاً
        final rawBytes = await sourceFile.readAsBytes();
        String content;
        List<int> copyBytes;
        if (rawBytes.length >= 2 &&
            rawBytes[0] == 0x1f &&
            rawBytes[1] == 0x8b) {
          copyBytes = rawBytes;
          content = utf8.decode(gzip.decode(rawBytes));
        } else {
          copyBytes = rawBytes;
          content = utf8.decode(rawBytes);
        }
        final jsonData = jsonDecode(content) as Map<String, dynamic>;
        if (!jsonData.containsKey('metadata')) {
          throw Exception('الملف المختار ليس نسخة احتياطية صالحة');
        }

        final ext = extension == '.gz' ? '.json.gz' : '.json';
        final newFilePath = '${backupDir.path}/$baseName$ext';
        await File(newFilePath).writeAsBytes(copyBytes);
        dlog(() => '✅ تم استيراد النسخة الاحتياطية (JSON): $newFilePath');
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
          dlog(() => '✅ تم استيراد النسخة الاحتياطية (SQLite): $newFilePath');
          return newFilePath;
        } catch (e) {
          try {
            await File(newFilePath).delete();
          } catch (e, st) {
            // تجاهل مقصود — تنظيف أفضل جهد
            AppLogger.warning(
              'فشل حذف ملف مؤقت أثناء الاستعادة',
              tag: 'BACKUP',
              error: e,
              stackTrace: st,
            );
          }
          rethrow;
        } finally {
          await tempDb?.close();
        }
      }

      throw UnsupportedError('تنسيق الملف غير مدعوم للاستيراد: $extension');
    } catch (e) {
      dlog(() => '❌ خطأ في استيراد النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// حذف نسخة احتياطية محلية
  Future<void> deleteLocalBackup(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        dlog(() => '✅ تم حذف النسخة الاحتياطية: $filePath');
      }
      // ✅ إصلاح: حذف ملف .metadata.json المرافق لنسخ SQLite
      // نسخ SQLite تُخزَّن مع ملف .metadata.json بجانبها (انظر _metadataFilePath).
      // بدون هذا، تتراكم ملفات metadata يتيمة على القرص بعد حذف النسخة الأصلية.
      final metadataPath = _metadataFilePath(filePath);
      final metadataFile = File(metadataPath);
      if (metadataFile.existsSync()) {
        await metadataFile.delete();
        dlog(() => '🧹 تم حذف ملف metadata المرافق: $metadataPath');
      }
    } catch (e) {
      dlog(() => '❌ خطأ في حذف النسخة الاحتياطية: $e');
      rethrow;
    }
  }

  /// تصدير نسخة احتياطية إلى مجلد Downloads
  Future<String> exportToDownloads() async {
    try {
      dlog('🔄 تصدير نسخة احتياطية إلى مجلد Downloads...');

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

      dlog(() => '✅ تم تصدير النسخة الاحتياطية إلى: $exportPath');
      return exportPath;
    } catch (e) {
      dlog(() => '❌ خطأ في تصدير النسخة الاحتياطية: $e');
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

      dlog(() => '✅ تم تنظيف ${backupsToDelete.length} نسخة احتياطية قديمة');
    } catch (e) {
      dlog(() => '❌ خطأ في تنظيف النسخ القديمة: $e');
    }
  }

  /// تقدير حجم جميع النسخ المحلية
  Future<int> getTotalBackupsSize() async {
    try {
      final backups = await listLocalBackups();
      return backups.fold<int>(0, (total, backup) => total + backup.sizeBytes);
    } catch (e) {
      dlog(() => '❌ خطأ في حساب حجم النسخ: $e');
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
        'exists': backupDir.existsSync(),
        'backups_count': backups.length,
        'total_size_bytes': totalSize,
        'total_size_mb': (totalSize / (1024 * 1024)).toStringAsFixed(2),
      };
    } catch (e) {
      dlog(() => '❌ خطأ في الحصول على معلومات مجلد النسخ: $e');
      return {};
    }
  }
}
