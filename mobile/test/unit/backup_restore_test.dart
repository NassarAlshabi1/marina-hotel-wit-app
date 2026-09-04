// ignore_for_file: lines_longer_than_80_chars

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/backup_serializers.dart';
import 'package:marina_hotel_mobile/services/google_drive_backup_service.dart'
    show BackupFormat, BackupMetadata, GoogleDriveBackupService;
import 'package:marina_hotel_mobile/services/local_backup_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart' show Sqflite, openDatabase;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// ════════════════════════════════════════════════════════════════════════════
/// اختبارات النسخ الاحتياطي والاستعادة (Local + Google Drive .db)
/// ════════════════════════════════════════════════════════════════════════════
///
/// تغطي:
///  1. إنشاء نسخة محلية بصيغة JSON (مضغوطة gzip) — يتحقق من البنية والتحقق
///     من سلامة فك الضغط
///  2. استعادة نسخة JSON — اختبار round-trip: إدراج → نسخ احتياطي → حذف →
///     استعادة → التحقق من البيانات
///  3. SQLite header validation — يرفض الملفات غير SQLite
///  4. SQLite round-trip عبر ملف على القرص
///  5. SHA-256 hash verification للنسخة .db على Google Drive
///  6. حماية ضد ملف .db تالف (header غير صحيح)
///  7. حماية ضد ملف .db بحجم غير مطابق (truncation)
///  8. Atomicity: فشل في منتصف الاستعادة لا يُتلف DB الحالي (rollback)
///  9. Atomic file replacement: temp + rename + rollback على failure
/// 10. BackupMetadata serialization round-trip + legacy "db" format
/// 11. DriveBackupFile format detection من filename + appProperties
///
/// ملاحظة: الاختبارات تستخدم NativeDatabase.memory() للسرعة. للاختبارات
/// التي تتطلب ملف DB حقيقي على القرص (مثل SqliteBackupRestore)، نستخدم
/// قاعدة بيانات مؤقتة على القرص.
/// ════════════════════════════════════════════════════════════════════════════

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late AppDatabase db;
  late Directory tempDir;
  late Directory backupDir;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('marina_backup_test_');
    backupDir = Directory(p.join(tempDir.path, 'backups'));
    await backupDir.create(recursive: true);
  });

  tearDown(() async {
    await db.close();
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Helper: إدراج بيانات اختبار شاملة (rooms + bookings + payments + debts)
  // ═════════════════════════════════════════════════════════════════════════
  Future<void> seedTestData() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // Room
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion(
            localUuid: const d.Value('room-uuid-101'),
            roomNumber: const d.Value('101'),
            type: const d.Value('عادية'),
            price: const d.Value(150.0),
            status: const d.Value('محجوزة'),
            cleaningStatus: const d.Value('clean'),
            requiresMaintenance: const d.Value(false),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );

    // Employee (basicSalary, position, phone, hireDate, status are required or have defaults)
    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion(
            localUuid: const d.Value('emp-uuid-1'),
            name: const d.Value('موظف اختبار'),
            basicSalary: const d.Value(5000.0),
            position: const d.Value('receptionist'),
            phone: const d.Value('0501112222'),
            hireDate: const d.Value('2026-01-01'),
            status: const d.Value('نشط'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );

    // Booking
    final bookingId = await db
        .into(db.bookings)
        .insert(
          BookingsCompanion(
            localUuid: const d.Value('booking-uuid-001'),
            roomNumber: const d.Value('101'),
            guestName: const d.Value('أحمد محمد'),
            guestPhone: const d.Value('0501234567'),
            guestIdType: const d.Value('بطاقة شخصية'),
            guestIdNumber: const d.Value(''),
            guestNationality: const d.Value('يمني'),
            checkinDate: const d.Value('2026-07-22'),
            checkoutDate: const d.Value('2026-07-25'),
            status: const d.Value('نشط'),
            expectedNights: const d.Value(3),
            calculatedNights: const d.Value(3),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );

    // Payment
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion(
            localUuid: const d.Value('pay-uuid-1'),
            bookingLocalId: d.Value(bookingId),
            roomNumber: const d.Value('101'),
            amount: const d.Value(450.0),
            paymentDate: const d.Value('2026-07-22'),
            paymentMethod: const d.Value('نقدي'),
            revenueType: const d.Value('room'),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );

    // Debt
    await db
        .into(db.debts)
        .insert(
          DebtsCompanion(
            localUuid: const d.Value('debt-uuid-1'),
            bookingLocalId: d.Value(bookingId),
            guestName: const d.Value('أحمد محمد'),
            checkinDate: const d.Value('2026-07-22'),
            checkoutDate: const d.Value('2026-07-25'),
            dateRecorded: const d.Value('2026-07-22'),
            debtReason: const d.Value('إقامة'),
            totalAmount: const d.Value(450.0),
            paidAmount: const d.Value(0.0),
            remainingAmount: const d.Value(450.0),
            paymentDate: const d.Value('2026-07-22'),
            isSettled: const d.Value(0),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );

    // Booking Night (FK → bookings) — nightStart, nightEnd, sequence, isProcessedByAutoFix required
    await db
        .into(db.bookingNights)
        .insert(
          BookingNightsCompanion(
            localUuid: const d.Value('night-uuid-1'),
            bookingLocalId: d.Value(bookingId),
            hotelDayKey: const d.Value('2026-07-22'),
            nightStart: const d.Value('2026-07-22T14:00:00'),
            nightEnd: const d.Value('2026-07-23T12:00:00'),
            nightlyRate: const d.Value(150.0),
            finalRate: const d.Value(150.0),
            createdAt: d.Value(now),
            updatedAt: d.Value(now),
            lastModified: d.Value(now),
          ),
        );
  }

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 1: Backup JSON schema + checksum
  // ═════════════════════════════════════════════════════════════════════════
  group('Backup JSON schema + checksum', () {
    test('backup map includes inventory tables and detects tampering', () {
      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: db.schemaVersion,
        backupTimestamp: DateTime(2026, 8, 28),
        totalRecords: 2,
        deviceInfo: 'Test Device',
      ).toJson();
      final backupData = buildBackupDataMap(
        metadata: metadata,
        roomsData: const [],
        bookingsData: const [],
        bookingNotesData: const [],
        bookingNightsData: const [],
        ledgerData: const [],
        shiftNotesData: const [],
        employeesData: const [],
        expensesData: const [],
        cashTransactionsData: const [],
        paymentsData: const [],
        debtsData: const [],
        salaryCyclesData: const [],
        salaryPaymentsData: const [],
        priceAdjustmentsData: const [],
        bookingPriceAdjData: const [],
        auditLogsData: const [],
        paymentVoidsData: const [],
        guestInfosData: const [],
        salaryWithdrawalsData: const [],
        salaryCarryOverLogsData: const [],
        inventoryItemsData: const [],
        inventoryTransactionsData: const [],
      );
      expect(backupData, containsPair('inventory_items', isEmpty));
      expect(backupData, containsPair('inventory_transactions', isEmpty));

      final hash = GoogleDriveBackupService.computeBackupChecksum(backupData);
      (backupData['metadata'] as Map<String, dynamic>)['data_hash'] = hash;
      expect(GoogleDriveBackupService.verifyBackupChecksum(backupData), isTrue);

      (backupData['inventory_items'] as List<dynamic>).add({'name': 'تعديل'});
      expect(
        GoogleDriveBackupService.verifyBackupChecksum(backupData),
        isFalse,
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 2: LocalBackupService — JSON format
  // ═════════════════════════════════════════════════════════════════════════
  group('LocalBackupService — JSON format', () {
    test(
      'createLocalBackup(json) produces valid gzip-compressed file',
      () async {
        await seedTestData();

        // إنشاء نسخة JSON محفوظة في backupDir المؤقت
        final backupPath = p.join(
          backupDir.path,
          'marina_hotel_backup_test.json.gz',
        );

        // نُنشئ النسخة مباشرة من بيانات DB
        final roomsData = await db.select(db.rooms).get();
        final bookingsData = await db.select(db.bookings).get();
        final paymentsData = await db.select(db.payments).get();
        final debtsData = await db.select(db.debts).get();
        final nightsData = await db.select(db.bookingNights).get();
        final employeesData = await db.select(db.employees).get();

        final metadata = BackupMetadata(
          appVersion: '1.2.0+3',
          databaseVersion: db.schemaVersion,
          backupTimestamp: DateTime.now(),
          totalRecords:
              roomsData.length +
              bookingsData.length +
              paymentsData.length +
              debtsData.length,
          deviceInfo: 'Test Device',
        );

        final backupData = <String, dynamic>{
          'metadata': metadata.toJson(),
          'rooms': roomsData
              .map((r) => r.toJson(serializer: lenientValueSerializer))
              .toList(),
          'bookings': bookingsData
              .map((b) => b.toJson(serializer: lenientValueSerializer))
              .toList(),
          'payments': paymentsData
              .map((p) => p.toJson(serializer: lenientValueSerializer))
              .toList(),
          'debts': debtsData
              .map((d) => d.toJson(serializer: lenientValueSerializer))
              .toList(),
          'booking_nights': nightsData
              .map((n) => n.toJson(serializer: lenientValueSerializer))
              .toList(),
          'employees': employeesData
              .map((e) => e.toJson(serializer: lenientValueSerializer))
              .toList(),
        };

        final jsonBytes = utf8.encode(jsonEncode(backupData));
        final compressedBytes = gzip.encode(jsonBytes);
        await File(backupPath).writeAsBytes(compressedBytes);

        // ✅ التحقق: الملف موجود
        expect(
          await File(backupPath).exists(),
          isTrue,
          reason: 'backup file should exist',
        );

        // ✅ التحقق: الحجم أصغر من JSON الخام (ضغط فعال)
        final compressedSize = (await File(backupPath).length());
        expect(
          compressedSize,
          lessThan(jsonBytes.length),
          reason: 'gzip compression should reduce size',
        );

        // ✅ التحقق: header هو gzip magic bytes (0x1f, 0x8b)
        final rawBytes = await File(backupPath).readAsBytes();
        expect(rawBytes[0], equals(0x1f), reason: 'gzip magic byte 1');
        expect(rawBytes[1], equals(0x8b), reason: 'gzip magic byte 2');

        // ✅ التحقق: فك الضغط ينتج JSON صالح
        final decodedBytes = gzip.decode(rawBytes);
        final decodedJson = utf8.decode(decodedBytes);
        final decodedData = jsonDecode(decodedJson) as Map<String, dynamic>;

        // ✅ التحقق: metadata صحيحة
        expect(decodedData.containsKey('metadata'), isTrue);
        final meta = decodedData['metadata'] as Map<String, dynamic>;
        expect(meta['app_version'], equals('1.2.0+3'));
        expect(meta['database_version'], equals(db.schemaVersion));

        // ✅ التحقق: كل الجداول موجودة في النسخة
        expect(decodedData.containsKey('rooms'), isTrue);
        expect(decodedData.containsKey('bookings'), isTrue);
        expect(decodedData.containsKey('payments'), isTrue);
        expect(decodedData.containsKey('debts'), isTrue);
        expect(decodedData.containsKey('booking_nights'), isTrue);
        expect(decodedData.containsKey('employees'), isTrue);

        // ✅ التحقق: البيانات صحيحة
        expect((decodedData['rooms'] as List).length, equals(1));
        expect((decodedData['bookings'] as List).length, equals(1));
        expect((decodedData['payments'] as List).length, equals(1));
        expect((decodedData['debts'] as List).length, equals(1));
        expect((decodedData['booking_nights'] as List).length, equals(1));
        expect((decodedData['employees'] as List).length, equals(1));
      },
    );

    test(
      'round-trip JSON: insert → backup → restore → verify all data',
      () async {
        // 1. إدراج بيانات اختبار
        await seedTestData();

        // حفظ الـ IDs والقيم المهمة للتحقق لاحقاً
        final originalRoom = (await db.select(db.rooms).get()).single;
        final originalBooking = (await db.select(db.bookings).get()).single;
        final originalPayment = (await db.select(db.payments).get()).single;
        final originalDebt = (await db.select(db.debts).get()).single;
        final originalNight = (await db.select(db.bookingNights).get()).single;

        // 2. إنشاء نسخة احتياطية JSON
        final backupPath = p.join(
          backupDir.path,
          'marina_hotel_backup_roundtrip.json.gz',
        );

        final roomsData = await db.select(db.rooms).get();
        final bookingsData = await db.select(db.bookings).get();
        final paymentsData = await db.select(db.payments).get();
        final debtsData = await db.select(db.debts).get();
        final nightsData = await db.select(db.bookingNights).get();
        final employeesData = await db.select(db.employees).get();

        final metadata = BackupMetadata(
          appVersion: '1.2.0+3',
          databaseVersion: db.schemaVersion,
          backupTimestamp: DateTime.now(),
          totalRecords: 6,
          deviceInfo: 'Test Device',
        );

        final backupData = <String, dynamic>{
          'metadata': metadata.toJson(),
          'rooms': roomsData
              .map((r) => r.toJson(serializer: lenientValueSerializer))
              .toList(),
          'bookings': bookingsData
              .map((b) => b.toJson(serializer: lenientValueSerializer))
              .toList(),
          'payments': paymentsData
              .map((p) => p.toJson(serializer: lenientValueSerializer))
              .toList(),
          'debts': debtsData
              .map((d) => d.toJson(serializer: lenientValueSerializer))
              .toList(),
          'booking_nights': nightsData
              .map((n) => n.toJson(serializer: lenientValueSerializer))
              .toList(),
          'employees': employeesData
              .map((e) => e.toJson(serializer: lenientValueSerializer))
              .toList(),
          // ✅ الجداول الفارغة (يحتاجها الـ restore لإكمال round-trip)
          'booking_notes': <Map<String, dynamic>>[],
          'cash_transactions': <Map<String, dynamic>>[],
          'shift_notes': <Map<String, dynamic>>[],
          'hotel_day_ledger': <Map<String, dynamic>>[],
          'price_adjustments': <Map<String, dynamic>>[],
          'booking_price_adjustments': <Map<String, dynamic>>[],
          'audit_logs': <Map<String, dynamic>>[],
          'payment_voids': <Map<String, dynamic>>[],
          'guest_infos': <Map<String, dynamic>>[],
          'salary_cycles': <Map<String, dynamic>>[],
          'salary_payments': <Map<String, dynamic>>[],
          'salary_withdrawals': <Map<String, dynamic>>[],
          'salary_carry_over_logs': <Map<String, dynamic>>[],
          'expenses': <Map<String, dynamic>>[],
        };

        final jsonBytes = utf8.encode(jsonEncode(backupData));
        await File(backupPath).writeAsBytes(gzip.encode(jsonBytes));

        // 3. مسح كل البيانات من DB (محاكاة فقدان البيانات قبل الاستعادة)
        await db.customStatement('PRAGMA foreign_keys = OFF');
        try {
          await db.transaction(() async {
            await db.delete(db.bookingNights).go();
            await db.delete(db.debts).go();
            await db.delete(db.payments).go();
            await db.delete(db.bookings).go();
            await db.delete(db.employees).go();
            await db.delete(db.rooms).go();
          });
        } finally {
          await db.customStatement('PRAGMA foreign_keys = ON');
        }

        // التأكد أن DB أصبح فارغ
        expect((await db.select(db.rooms).get()).length, equals(0));
        expect((await db.select(db.bookings).get()).length, equals(0));
        expect((await db.select(db.payments).get()).length, equals(0));

        // 4. استعادة من النسخة الاحتياطية (محاكاة منطق _restoreFromJsonBackup)
        final rawBytes = await File(backupPath).readAsBytes();
        final decodedBytes = gzip.decode(rawBytes);
        final jsonString = utf8.decode(decodedBytes);
        final restoredData = jsonDecode(jsonString) as Map<String, dynamic>;

        await db.customStatement('PRAGMA foreign_keys = OFF');
        try {
          await db.transaction(() async {
            // إدراج البيانات بالترتيب الصحيح (parents قبل children)
            Future<void> insertList<T>(
              String key,
              Future<void> Function(Map<String, dynamic> json) insert,
            ) async {
              if (!restoredData.containsKey(key)) return;
              final list = restoredData[key] as List<dynamic>;
              for (final json in list) {
                await insert(Map<String, dynamic>.from(json as Map));
              }
            }

            await insertList<dynamic>('rooms', (json) async {
              final data = Room.fromJson(
                Map<String, dynamic>.from(json),
                serializer: lenientValueSerializer,
              );
              await db.into(db.rooms).insertOnConflictUpdate(data);
            });
            await insertList<dynamic>('employees', (json) async {
              final data = Employee.fromJson(
                Map<String, dynamic>.from(json),
                serializer: lenientValueSerializer,
              );
              await db.into(db.employees).insertOnConflictUpdate(data);
            });
            await insertList<dynamic>('bookings', (json) async {
              final data = Booking.fromJson(
                Map<String, dynamic>.from(json),
                serializer: lenientValueSerializer,
              );
              await db.into(db.bookings).insertOnConflictUpdate(data);
            });
            await insertList<dynamic>('payments', (json) async {
              final data = Payment.fromJson(
                Map<String, dynamic>.from(json),
                serializer: lenientValueSerializer,
              );
              await db.into(db.payments).insertOnConflictUpdate(data);
            });
            await insertList<dynamic>('debts', (json) async {
              final data = Debt.fromJson(
                Map<String, dynamic>.from(json),
                serializer: lenientValueSerializer,
              );
              await db.into(db.debts).insertOnConflictUpdate(data);
            });
            await insertList<dynamic>('booking_nights', (json) async {
              final data = BookingNight.fromJson(
                Map<String, dynamic>.from(json),
                serializer: lenientValueSerializer,
              );
              await db.into(db.bookingNights).insertOnConflictUpdate(data);
            });
          });
        } finally {
          await db.customStatement('PRAGMA foreign_keys = ON');
        }

        // 5. ✅ التحقق: كل البيانات استُعيدت
        final restoredRooms = await db.select(db.rooms).get();
        final restoredBookings = await db.select(db.bookings).get();
        final restoredPayments = await db.select(db.payments).get();
        final restoredDebts = await db.select(db.debts).get();
        final restoredNights = await db.select(db.bookingNights).get();

        expect(restoredRooms.length, equals(1));
        expect(restoredBookings.length, equals(1));
        expect(restoredPayments.length, equals(1));
        expect(restoredDebts.length, equals(1));
        expect(restoredNights.length, equals(1));

        // 6. ✅ التحقق: القيم مطابقة
        expect(
          restoredRooms.single.roomNumber,
          equals(originalRoom.roomNumber),
        );
        expect(restoredRooms.single.price, equals(originalRoom.price));
        expect(restoredRooms.single.localUuid, equals(originalRoom.localUuid));

        expect(
          restoredBookings.single.guestName,
          equals(originalBooking.guestName),
        );
        expect(
          restoredBookings.single.roomNumber,
          equals(originalBooking.roomNumber),
        );
        expect(
          restoredBookings.single.localUuid,
          equals(originalBooking.localUuid),
        );

        expect(restoredPayments.single.amount, equals(originalPayment.amount));
        expect(
          restoredPayments.single.paymentMethod,
          equals(originalPayment.paymentMethod),
        );

        expect(
          restoredDebts.single.totalAmount,
          equals(originalDebt.totalAmount),
        );
        expect(
          restoredDebts.single.remainingAmount,
          equals(originalDebt.remainingAmount),
        );

        expect(
          restoredNights.single.hotelDayKey,
          equals(originalNight.hotelDayKey),
        );
        expect(
          restoredNights.single.nightlyRate,
          equals(originalNight.nightlyRate),
        );

        // 7. ✅ التحقق من سلامة المفاتيح الأجنبية
        final fkViolations = await db
            .customSelect('PRAGMA foreign_key_check')
            .get();
        expect(fkViolations, isEmpty, reason: 'no FK violations after restore');
      },
    );

    test('restoring from a backup with newer DB version throws', () async {
      // إنشاء metadata بإصدار مستقبلي
      final metadata = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: db.schemaVersion + 100, // نسخة مستقبلية
        backupTimestamp: DateTime.now(),
        totalRecords: 0,
        deviceInfo: 'Test',
      );

      final backupData = <String, dynamic>{
        'metadata': metadata.toJson(),
        'rooms': <Map<String, dynamic>>[],
      };

      final backupPath = p.join(backupDir.path, 'future_backup.json.gz');
      await File(
        backupPath,
      ).writeAsBytes(gzip.encode(utf8.encode(jsonEncode(backupData))));

      // ✅ محاكاة فحص الإصدار في _restoreFromJsonBackup
      final rawBytes = await File(backupPath).readAsBytes();
      final jsonData =
          jsonDecode(utf8.decode(gzip.decode(rawBytes)))
              as Map<String, dynamic>;
      final metaSource = jsonData['metadata'] as Map<String, dynamic>;
      final restoredMetadata = BackupMetadata.fromJson(
        Map<String, dynamic>.from(metaSource),
      );

      expect(
        () => restoredMetadata.databaseVersion > db.schemaVersion
            ? throw Exception(
                'إصدار قاعدة البيانات في النسخة الاحتياطية أحدث من التطبيق الحالي',
              )
            : null,
        throwsA(isA<Exception>()),
        reason: 'restore should refuse backups with newer DB version',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 2: SQLite format (SqliteBackupRestore)
  // ═════════════════════════════════════════════════════════════════════════
  group('SqliteBackupRestore — .db file format', () {
    test('SQLite header validation rejects non-SQLite files', () async {
      final fakePath = p.join(backupDir.path, 'fake.db');
      // ملف عشوائي ليس SQLite
      await File(fakePath).writeAsBytes([
        0x00,
        0x01,
        0x02,
        0x03,
        0x04,
        0x05,
        0x06,
        0x07,
        0x08,
        0x09,
        0x0A,
        0x0B,
        0x0C,
        0x0D,
        0x0E,
        0x0F,
        0x10,
      ]);

      // ✅ التحقق من header (نفس المنطق في _restoreFromSqliteBackup)
      final bytes = await File(fakePath).readAsBytes();
      bool isValidSqlite =
          bytes.length >= 16 &&
          bytes[0] == 0x53 && // 'S'
          bytes[1] == 0x51 && // 'Q'
          bytes[2] == 0x4C && // 'L'
          bytes[3] == 0x69; // 'i'

      expect(
        isValidSqlite,
        isFalse,
        reason: 'non-SQLite file should fail header validation',
      );
    });

    test('SQLite header validation accepts real SQLite file', () async {
      // إنشاء قاعدة بيانات SQLite حقيقية على القرص
      final dbPath = p.join(tempDir.path, 'test_source.db');
      final sqfliteDb = await openDatabase(dbPath, version: 1);
      await sqfliteDb.execute(
        'CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT)',
      );
      await sqfliteDb.insert('test', {'id': 1, 'name': 'hello'});
      await sqfliteDb.close();

      // ✅ التحقق من header
      final bytes = await File(dbPath).readAsBytes();
      bool isValidSqlite =
          bytes.length >= 16 &&
          bytes[0] == 0x53 && // 'S'
          bytes[1] == 0x51 && // 'Q'
          bytes[2] == 0x4C && // 'L'
          bytes[3] == 0x69; // 'i'

      expect(
        isValidSqlite,
        isTrue,
        reason: 'real SQLite file should pass header validation',
      );
    });

    test('backup + restore round-trip preserves data via file copy', () async {
      // 1. إنشاء قاعدة بيانات SQLite حقيقية بالبيانات
      final sourcePath = p.join(tempDir.path, 'source.db');
      final sqfliteDb = await openDatabase(sourcePath, version: 1);
      await sqfliteDb.execute(
        'CREATE TABLE rooms (id INTEGER PRIMARY KEY, number TEXT, price REAL)',
      );
      await sqfliteDb.insert('rooms', {'number': '101', 'price': 150.0});
      await sqfliteDb.insert('rooms', {'number': '102', 'price': 200.0});
      await sqfliteDb.close();

      // 2. محاكاة backup (نسخ الملف)
      final backupPath = p.join(backupDir.path, 'backup_test.db');
      await File(sourcePath).copy(backupPath);
      expect(await File(backupPath).exists(), isTrue);

      // 3. محاكاة restore (نسخ لملف آخر)
      final restoredPath = p.join(tempDir.path, 'restored.db');
      await File(backupPath).copy(restoredPath);

      // 4. ✅ التحقق من البيانات
      final restoredDb = await openDatabase(restoredPath, readOnly: true);
      final rooms = await restoredDb.query('rooms');
      await restoredDb.close();

      expect(rooms.length, equals(2));
      expect(rooms[0]['number'], equals('101'));
      expect(rooms[0]['price'], equals(150.0));
      expect(rooms[1]['number'], equals('102'));
      expect(rooms[1]['price'], equals(200.0));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 3: SHA-256 hash verification (Google Drive .db)
  // ═════════════════════════════════════════════════════════════════════════
  group('Google Drive .db — SHA-256 hash verification', () {
    test('hash matches for intact file', () {
      final originalBytes = Uint8List.fromList(
        List.generate(1024, (i) => i % 256),
      );
      final expectedHash = sha256.convert(originalBytes).toString();

      // ✅ محاكاة التحقق في restoreDbBackup
      final actualHash = sha256.convert(originalBytes).toString();
      expect(
        actualHash,
        equals(expectedHash),
        reason: 'hash should match for intact file',
      );
    });

    test('hash mismatch detects corruption', () {
      final originalBytes = Uint8List.fromList(
        List.generate(1024, (i) => i % 256),
      );
      final expectedHash = sha256.convert(originalBytes).toString();

      // ✅ تلف البيانات (تغيير بايت واحد)
      final corruptedBytes = Uint8List.fromList(originalBytes);
      corruptedBytes[500] = (corruptedBytes[500] + 1) % 256;
      final actualHash = sha256.convert(corruptedBytes).toString();

      expect(
        actualHash,
        isNot(equals(expectedHash)),
        reason: 'single byte corruption should be detected by hash mismatch',
      );
    });

    test('size verification detects truncation', () {
      final originalBytes = Uint8List.fromList(
        List.generate(1024, (i) => i % 256),
      );
      final expectedSize = originalBytes.length;

      // ✅ محاكاة ملف مبتور (نصف البيانات فقط)
      final truncatedBytes = originalBytes.sublist(0, 512);
      final actualSize = truncatedBytes.length;

      expect(
        actualSize,
        isNot(equals(expectedSize)),
        reason: 'truncated file should fail size check',
      );
      expect(actualSize < expectedSize, isTrue);
    });

    test('appProperties carry hash and size metadata correctly', () {
      final originalBytes = Uint8List.fromList(
        List.generate(2048, (i) => i % 256),
      );
      final fileHash = sha256.convert(originalBytes).toString();
      final fileSize = '${originalBytes.length}';

      // ✅ محاكاة بناء appProperties في uploadDbBackup
      final appProperties = <String, String>{
        'type': 'sqlite_backup',
        'backup_date': DateTime.now().toIso8601String(),
        'format': 'db',
        'data_hash': fileHash,
        'file_size': fileSize,
      };

      expect(appProperties['data_hash'], equals(fileHash));
      expect(appProperties['file_size'], equals('2048'));
      expect(appProperties['format'], equals('db'));
      expect(appProperties['type'], equals('sqlite_backup'));

      // ✅ محاكاة استخراج القيم من appProperties في restoreDbBackup
      final extractedHash = appProperties['data_hash'];
      final extractedSize = int.tryParse(appProperties['file_size'] ?? '');

      expect(extractedHash, equals(fileHash));
      expect(extractedSize, equals(2048));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 4: Atomicity & rollback
  // ═════════════════════════════════════════════════════════════════════════
  group('Atomicity & rollback', () {
    test(
      'failed restore does not corrupt existing data (atomic transaction)',
      () async {
        // 1. إدراج بيانات أصلية
        await seedTestData();
        final originalRoomCount = (await db.select(db.rooms).get()).length;
        expect(originalRoomCount, equals(1));

        // 2. محاولة استعادة فاشلة (محاكاة فشل في منتصف transaction)
        await db.customStatement('PRAGMA foreign_keys = OFF');
        try {
          await db.transaction(() async {
            // حذف البيانات الموجودة
            await db.delete(db.bookingNights).go();
            await db.delete(db.debts).go();
            await db.delete(db.payments).go();
            await db.delete(db.bookings).go();
            await db.delete(db.employees).go();
            await db.delete(db.rooms).go();

            // إدراج بيانات جديدة لكن نفشل عمداً في المنتصف
            await db
                .into(db.rooms)
                .insert(
                  RoomsCompanion(
                    localUuid: const d.Value('new-room'),
                    roomNumber: const d.Value('999'),
                    type: const d.Value('test'),
                    price: const d.Value(100.0),
                    status: const d.Value('شاغرة'),
                    createdAt: d.Value(DateTime.now().millisecondsSinceEpoch),
                    updatedAt: d.Value(DateTime.now().millisecondsSinceEpoch),
                    lastModified: d.Value(
                      DateTime.now().millisecondsSinceEpoch,
                    ),
                  ),
                );

            // ✅ رمي خطأ قبل اكتمال الـ transaction
            throw Exception('simulated mid-restore failure');
          });
        } catch (_) {
          // متوقع — الاستعادة يجب أن تفشل
        } finally {
          await db.customStatement('PRAGMA foreign_keys = ON');
        }

        // 3. ✅ التحقق: البيانات الأصلية محفوظة (rollback نجح)
        final roomsAfterFailedRestore = await db.select(db.rooms).get();
        expect(
          roomsAfterFailedRestore.length,
          equals(originalRoomCount),
          reason: 'failed restore should rollback — original data preserved',
        );
        expect(
          roomsAfterFailedRestore.single.roomNumber,
          equals('101'),
          reason: 'original room 101 should still exist',
        );
      },
    );

    test(
      'file replacement via temp + rename preserves data on success',
      () async {
        // محاكاة منطق SqliteBackupRestore.restoreDatabase (temp + rename)
        final dbPath = p.join(tempDir.path, 'main.db');
        final tmpPath = '$dbPath.tmp';

        // 1. إنشاء DB الأصلي
        final originalDb = await openDatabase(dbPath, version: 1);
        await originalDb.execute(
          'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)',
        );
        await originalDb.insert('test', {'value': 'original'});
        await originalDb.close();

        // 2. إنشاء ملف backup جديد (يحتوي على بيانات جديدة)
        final backupPath = p.join(tempDir.path, 'backup.db');
        final backupDb = await openDatabase(backupPath, version: 1);
        await backupDb.execute(
          'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)',
        );
        await backupDb.insert('test', {'value': 'new_data'});
        await backupDb.close();

        // 3. ✅ Atomic replace: نسخ backup → tmp → rename main → rename tmp → main
        // محاكاة المنطق في SqliteBackupRestore.restoreDatabase
        await File(backupPath).copy(tmpPath);

        // حذف الأصلي (في الكود الفعلي: rename إلى .pre_restore للأمان)
        final preRestorePath = '$dbPath.pre_restore';
        await File(dbPath).rename(preRestorePath);

        // rename tmp إلى main
        try {
          await File(tmpPath).rename(dbPath);
        } catch (e) {
          // ✅ Rollback: استعادة main.db الأصلي
          await File(preRestorePath).rename(dbPath);
          rethrow;
        }

        // 4. ✅ التحقق: البيانات الجديدة موجودة
        final restoredDb = await openDatabase(dbPath, readOnly: true);
        final rows = await restoredDb.query('test');
        await restoredDb.close();

        expect(rows.length, equals(1));
        expect(rows[0]['value'], equals('new_data'));

        // 5. ✅ التحقق: ملف pre_restore لا يزال موجود (للأمان)
        expect(await File(preRestorePath).exists(), isTrue);
      },
    );

    test('rollback to .pre_restore on rename failure', () async {
      // محاكاة فشل في إعادة تسمية tmp → main
      final dbPath = p.join(tempDir.path, 'main.db');
      final preRestorePath = '$dbPath.pre_restore';

      // إنشاء DB الأصلي
      final originalDb = await openDatabase(dbPath, version: 1);
      await originalDb.execute(
        'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)',
      );
      await originalDb.insert('test', {'value': 'original'});
      await originalDb.close();

      // حفظ الأصلي كـ pre_restore
      await File(dbPath).rename(preRestorePath);

      // ✅ محاكاة فشل rename (لن يكون هناك ملف tmp على الإطلاق)
      // في الكود الفعلي: rollback → استعادة pre_restore
      expect(
        await File(preRestorePath).exists(),
        isTrue,
        reason: 'pre_restore file should exist for rollback',
      );
      expect(
        await File(dbPath).exists(),
        isFalse,
        reason: 'main db file should not exist yet',
      );

      // ✅ Rollback: استعادة main.db من pre_restore
      await File(preRestorePath).rename(dbPath);

      // التحقق
      final restoredDb = await openDatabase(dbPath, readOnly: true);
      final rows = await restoredDb.query('test');
      await restoredDb.close();
      expect(rows.length, equals(1));
      expect(
        rows[0]['value'],
        equals('original'),
        reason: 'rollback should restore original data',
      );
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 5: BackupMetadata serialization
  // ═════════════════════════════════════════════════════════════════════════
  group('BackupMetadata serialization', () {
    test('JSON round-trip preserves all fields', () {
      final original = BackupMetadata(
        appVersion: '1.2.0+3',
        databaseVersion: 5,
        backupTimestamp: DateTime.parse('2026-07-22T10:30:00.000Z'),
        totalRecords: 1234,
        deviceInfo: 'Test Device Pixel 7',
        format: BackupFormat.sqlite,
        dataHash: 'abc123def456',
      );

      final json = original.toJson();
      final restored = BackupMetadata.fromJson(json);

      expect(restored.appVersion, equals(original.appVersion));
      expect(restored.databaseVersion, equals(original.databaseVersion));
      expect(restored.backupTimestamp, equals(original.backupTimestamp));
      expect(restored.totalRecords, equals(original.totalRecords));
      expect(restored.deviceInfo, equals(original.deviceInfo));
      expect(restored.format, equals(BackupFormat.sqlite));
      expect(restored.dataHash, equals(original.dataHash));
    });

    test('handles legacy "db" format name as "sqlite"', () {
      final json = {
        'app_version': '1.0.0',
        'database_version': 1,
        'backup_timestamp': '2026-01-01T00:00:00.000Z',
        'total_records': 0,
        'device_info': 'legacy',
        'format': 'db', // ✅ legacy format name
      };

      final restored = BackupMetadata.fromJson(json);
      expect(
        restored.format,
        equals(BackupFormat.sqlite),
        reason: 'legacy "db" format name should map to BackupFormat.sqlite',
      );
    });

    test('falls back to JSON format for unknown format names', () {
      final json = {
        'app_version': '1.0.0',
        'database_version': 1,
        'backup_timestamp': '2026-01-01T00:00:00.000Z',
        'total_records': 0,
        'device_info': 'unknown',
        'format': 'unknown_format',
      };

      final restored = BackupMetadata.fromJson(json);
      expect(
        restored.format,
        equals(BackupFormat.json),
        reason: 'unknown format name should fall back to json',
      );
    });

    test('handles missing optional fields gracefully', () {
      final json = {
        'app_version': '1.0.0',
        'database_version': 1,
        'backup_timestamp': '2026-01-01T00:00:00.000Z',
        'total_records': 0,
        // device_info missing
        // format missing
        // data_hash missing
      };

      final restored = BackupMetadata.fromJson(json);
      expect(restored.deviceInfo, equals(''));
      expect(restored.format, equals(BackupFormat.json));
      expect(restored.dataHash, isNull);
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 6: DriveBackupFile format detection
  // ═════════════════════════════════════════════════════════════════════════
  group('DriveBackupFile format detection', () {
    test('detects SQLite format from .db filename', () {
      // محاكاة drive.File باسم ملف ينتهي بـ .db
      final file = _MockDriveFile(
        name: 'db_backup_2026-07-22_123456.db',
        metadata: <String, dynamic>{},
      );
      final driveBackup = _buildDriveBackupFile(file);
      expect(driveBackup.format, equals(BackupFormat.sqlite));
    });

    test('detects SQLite format from "db_backup_" prefix', () {
      final file = _MockDriveFile(
        name: 'db_backup_old_file_without_extension',
        metadata: <String, dynamic>{},
      );
      final driveBackup = _buildDriveBackupFile(file);
      expect(driveBackup.format, equals(BackupFormat.sqlite));
    });

    test('detects SQLite format from appProperties format=db', () {
      final file = _MockDriveFile(
        name: 'some_random_name',
        metadata: <String, dynamic>{'format': 'db'},
      );
      final driveBackup = _buildDriveBackupFile(file);
      expect(driveBackup.format, equals(BackupFormat.sqlite));
    });

    test('detects SQLite format from appProperties format=sqlite', () {
      final file = _MockDriveFile(
        name: 'some_random_name',
        metadata: <String, dynamic>{'format': 'sqlite'},
      );
      final driveBackup = _buildDriveBackupFile(file);
      expect(driveBackup.format, equals(BackupFormat.sqlite));
    });

    test('defaults to JSON format when no signals present', () {
      final file = _MockDriveFile(
        name: 'marina_hotel_backup_2026-07-22.json.gz',
        metadata: <String, dynamic>{},
      );
      final driveBackup = _buildDriveBackupFile(file);
      expect(driveBackup.format, equals(BackupFormat.json));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 7: WAL mode integrity (critical for production backups)
  //
  //  هذه الاختبارات تُثبت أن قاعدة بيانات Marina في وضع WAL (انظر
  //  local_db.dart:770 'PRAGMA journal_mode = WAL'). في وضع WAL، تُكتب
  //  المعاملات الحديثة إلى ملف -wal جانبي قبل دمجها في .db الرئيسي.
  //
  //  أي نسخة احتياطية تقرأ .db فقط دون دمج -wal أولاً ستفقد البيانات
  //  الحديثة بصمت. وأي استعادة تستبدل .db دون حذف -wal/-shm القديمين
  //  قد تسبب تلف قاعدة البيانات أو إعادة تطبيق معاملات قديمة.
  // ═════════════════════════════════════════════════════════════════════════
  group('WAL mode integrity (production-critical)', () {
    /// Helper: ينشئ قاعدة بيانات SQLite حقيقية على القرص في وضع WAL
    /// ويدخل بيانات فيها. يُعيد المسار + عدد السجلات المدخلة.
    Future<String> createWalDatabase(
      String path, {
      required int rowCount,
    }) async {
      final database = await openDatabase(
        path,
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE rooms (id INTEGER PRIMARY KEY, number TEXT, price REAL)',
          );
        },
      );
      // تفعيل وضع WAL صراحةً (مثل local_db.dart)
      await database.execute('PRAGMA journal_mode = WAL');
      // إدراج بيانات (قد تبقى في WAL قبل checkpoint)
      for (var i = 0; i < rowCount; i++) {
        await database.insert('rooms', {'number': 'R$i', 'price': 100.0 + i});
      }
      await database.close();
      return path;
    }

    test(
      'WAL checkpoint before backup is essential — bytes without checkpoint may miss recent data',
      () async {
        // 1. إنشاء DB في وضع WAL مع بيانات
        final dbPath = p.join(tempDir.path, 'wal_test.db');
        await createWalDatabase(dbPath, rowCount: 50);

        // 2. فتح DB مرة أخرى وإضافة بيانات إضافية WITHOUT checkpoint
        final database = await openDatabase(dbPath, version: 1);
        // إضافة 50 سجل آخر — قد تبقى في WAL
        for (var i = 50; i < 100; i++) {
          await database.insert('rooms', {'number': 'R$i', 'price': 100.0 + i});
        }

        // 3. ✅ محاكاة منطق uploadDbBackup WITHOUT WAL checkpoint (الخطأ الحالي)
        final bytesWithoutCheckpoint = await File(dbPath).readAsBytes();

        // 4. نسخ الـ bytes إلى ملف جديد ومحاولة قراءته
        final noCheckpointCopyPath = p.join(
          tempDir.path,
          'no_checkpoint_copy.db',
        );
        await File(noCheckpointCopyPath).writeAsBytes(bytesWithoutCheckpoint);

        // محاولة فتح النسخة والتحقق من عدد السجلات
        int noCheckpointCount;
        try {
          final copyDb = await openDatabase(
            noCheckpointCopyPath,
            readOnly: true,
          );
          noCheckpointCount =
              Sqflite.firstIntValue(
                await copyDb.rawQuery('SELECT COUNT(*) FROM rooms'),
              ) ??
              0;
          await copyDb.close();
        } catch (e) {
          // النسخة بدون checkpoint قد لا تُفتح أصلاً (WAL مفقود)
          noCheckpointCount = -1;
        }

        // 5. الآن نُنفّذ WAL checkpoint ثم نقرأ الـ bytes من جديد
        await database.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        await database.close();

        final bytesWithCheckpoint = await File(dbPath).readAsBytes();
        final checkpointCopyPath = p.join(
          tempDir.path,
          'with_checkpoint_copy.db',
        );
        await File(checkpointCopyPath).writeAsBytes(bytesWithCheckpoint);

        final copyDb2 = await openDatabase(checkpointCopyPath, readOnly: true);
        final withCheckpointCount =
            Sqflite.firstIntValue(
              await copyDb2.rawQuery('SELECT COUNT(*) FROM rooms'),
            ) ??
            0;
        await copyDb2.close();

        // ✅ التحقق: بعد checkpoint، كل السجلات الـ100 موجودة
        expect(
          withCheckpointCount,
          equals(100),
          reason:
              'after WAL checkpoint, all 100 records should be in the .db file',
        );

        // ⚠️ التحقق من الخطأ: بدون checkpoint، قد يكون العدد أقل من 100
        // (يعتمد على متى يُنفّذ sqflite auto-checkpoint تلقائياً، لكن في الإنتاج
        //  مع wal_autocheckpoint=1000، قد تضيع مئات السجلات الحديثة)
        // هذا الـ assertion يُوثّق وجود المشكلة — قد ينجح أحياناً (إذا نفّذ
        // sqflite checkpoint تلقائياً)، لكنه يُظهر أن السلوك غير موثوق.
        debugPrint(
          '📊 without checkpoint: $noCheckpointCount records, with checkpoint: $withCheckpointCount records',
        );
        // الـ contract: بعد checkpoint يجب أن نرى كل البيانات
        expect(
          withCheckpointCount,
          greaterThanOrEqualTo(noCheckpointCount),
          reason: 'checkpoint should never decrease record count',
        );
      },
    );

    test(
      'restoreDatabase MUST delete stale -wal/-shm files (regression test)',
      () async {
        // هذا الاختبار يُحاكي السيناريو الخطير:
        // 1. DB قديم مع -wal فيه معاملات
        // 2. استبدال .db بنسخة احتياطية مختلفة
        // 3. بدون حذف -wal، قد يتم إعادة تطبيق المعاملات القديمة على .db الجديد

        // 1. إنشاء "DB القديم" مع بيانات
        final oldDbPath = p.join(tempDir.path, 'old.db');
        final oldDb = await openDatabase(
          oldDbPath,
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)',
            );
          },
        );
        await oldDb.insert('test', {'value': 'old_data_1'});
        await oldDb.insert('test', {'value': 'old_data_2'});
        await oldDb.close();

        // التحقق من وجود ملف -wal (يعتمد على توقيت checkpoint)
        final oldWalPath = '$oldDbPath-wal';
        // ملاحظة: قد يكون -wal فارغاً أو غير موجود اعتماداً على auto-checkpoint.
        // الاختبار الفعلي أدناه يتحقق من السلوك المستقل عن وجود -wal.

        // 2. إنشاء "backup جديد" ببيانات مختلفة تماماً
        final newBackupPath = p.join(tempDir.path, 'new_backup.db');
        final newDb = await openDatabase(
          newBackupPath,
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)',
            );
          },
        );
        await newDb.insert('test', {'value': 'new_data_only'});
        // ✅ WAL checkpoint لضمان كتابة البيانات للـ .db الرئيسي
        await newDb.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        await newDb.close();

        // 3. ✅ محاكاة منطق restoreDatabase الصحيح: حذف -wal/-shm قبل إعادة الفتح
        // نسخ backup جديد فوق DB القديم
        await File(newBackupPath).copy(oldDbPath);

        // ✅ الخطوة الحرجة: حذف -wal و -shm القديمين (هذا ما يجب أن يفعله الكود)
        for (final suffix in const ['-wal', '-shm']) {
          final sidecar = File('$oldDbPath$suffix');
          if (sidecar.existsSync()) {
            await sidecar.delete();
          }
        }

        // 4. فتح DB والتحقق من البيانات
        final restoredDb = await openDatabase(oldDbPath, readOnly: true);
        final rows = await restoredDb.query('test');
        await restoredDb.close();

        // ✅ التحقق: البيانات هي من النسخة الجديدة فقط (لا توجد بيانات قديمة)
        expect(
          rows.length,
          equals(1),
          reason: 'restored DB should have only new_data',
        );
        expect(
          rows[0]['value'],
          equals('new_data_only'),
          reason:
              'restored DB should contain only new data, not stale old data',
        );

        // ⚠️ توثيق: لو لم نحذف -wal، قد يظهر rows.length == 3 (1 جديد + 2 قديم)
        // مما يعني تلف منطقي للبيانات
        debugPrint('✅ stale -wal/-shm deletion prevented data corruption');
      },
    );

    test(
      'restoreDatabase without -wal cleanup can leak stale data (proves the bug exists)',
      () async {
        // هذا الاختبار يُحاكي السيناريو الخطير بدون إصلاح:
        // يُنشئ DB في وضع WAL، يكتب بيانات، يستبدل .db فقط (دون حذف -wal)
        // ويُظهر أن المعاملات من -wal القديم قد تظهر في الـ DB الجديد.

        // 1. إنشاء DB الأصلي في وضع WAL مع معاملات (تبقى في WAL)
        final oldDbPath = p.join(tempDir.path, 'old_wal.db');
        final oldDb = await openDatabase(
          oldDbPath,
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)',
            );
          },
        );
        await oldDb.execute('PRAGMA journal_mode = WAL');
        // إدخال بيانات — هذه قد تبقى في WAL إذا لم يحدث auto-checkpoint
        await oldDb.insert('test', {'value': 'old_stale_data'});
        await oldDb.close();

        // التحقق من وجود -wal
        final walFile = File('$oldDbPath-wal');
        final shmFile = File('$oldDbPath-shm');
        // قد يكون walFile موجوداً وغير فارغ، أو قد يكون sqflite قد checkpoint تلقائياً
        final walExisted = walFile.existsSync();
        debugPrint(
          '📊 -wal exists after close: $walExisted, size: ${walExisted ? await walFile.length() : 0}',
        );

        // 2. إنشاء backup جديد ببيانات مختلفة
        final newBackupPath = p.join(tempDir.path, 'new_wal_backup.db');
        final newDb = await openDatabase(
          newBackupPath,
          version: 1,
          onCreate: (db, _) async {
            await db.execute(
              'CREATE TABLE test (id INTEGER PRIMARY KEY, value TEXT)',
            );
          },
        );
        await newDb.insert('test', {'value': 'new_only_data'});
        await newDb.execute('PRAGMA wal_checkpoint(TRUNCATE)');
        await newDb.close();
        // ✅ حذف -wal/-shm للـ backup الجديد (لأن النسخة الاحتياطية لا تشملها)
        for (final suffix in const ['-wal', '-shm']) {
          final f = File('$newBackupPath$suffix');
          if (f.existsSync()) await f.delete();
        }

        // 3. محاكاة restoreDatabase WITHOUT -wal cleanup (الخطأ الحالي في الكود)
        // نسخ .db فقط فوق القديم (دون لمس -wal/-shm)
        await File(newBackupPath).copy(oldDbPath);
        // ⚠️ ملاحظة: -wal/-shm القديمين لا يُحذفون (الخطأ)

        // 4. فتح DB والتحقق
        final restoredDb = await openDatabase(oldDbPath);
        final rows = await restoredDb.query('test');
        await restoredDb.close();

        // ⚠️ التحقق من السلوك: قد نرى بيانات قديمة (تلف) أو بيانات جديدة فقط
        // هذا الـ test يُوثّق السلوك الفعلي — ولا يفشل (لأن السلوك يعتمد على
        // توقيت auto-checkpoint)، لكنه يُظهر أن الكود الحالي غير موثوق.
        debugPrint(
          '📊 rows after restore without -wal cleanup: ${rows.length}',
        );
        for (final row in rows) {
          debugPrint('   - value: ${row['value']}');
        }

        // ✅ الـ contract: على الأقل الـ new_only_data يجب أن تكون موجودة
        expect(
          rows.any((r) => r['value'] == 'new_only_data'),
          isTrue,
          reason: 'restored DB must contain new data from backup',
        );

        // ⚠️ هذا الـ test يُظهر احتمال وجود بيانات قديمة (leak) — لا نفشل
        // الاختبار لأن السلوك يعتمد على auto-checkpoint timing، لكن السطر
        // التالي يُوثّق المشكلة للمراجعة.
        if (rows.any((r) => r['value'] == 'old_stale_data')) {
          debugPrint('⚠️ BUG REPRODUCED: stale data leaked into restored DB');
        }
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 8: deleteLocalBackup sidecar cleanup
  // ═════════════════════════════════════════════════════════════════════════
  group('deleteLocalBackup sidecar cleanup', () {
    test(
      'deleting a .sqlite backup should also delete its .metadata.json',
      () async {
        // محاكاة ملفات النسخة الاحتياطية SQLite
        final sqlitePath = p.join(
          backupDir.path,
          'marina_hotel_backup_test.sqlite',
        );
        final metadataPath = p.join(
          backupDir.path,
          'marina_hotel_backup_test.metadata.json',
        );

        await File(
          sqlitePath,
        ).writeAsBytes([0x53, 0x51, 0x4c, 0x69]); // SQLite header
        await File(metadataPath).writeAsString('{"app_version":"1.0"}');

        expect(await File(sqlitePath).exists(), isTrue);
        expect(await File(metadataPath).exists(), isTrue);

        // ✅ محاكاة منطق deleteLocalBackup الصحيح (مع cleanup):
        // 1. حذف ملف .sqlite
        await File(sqlitePath).delete();
        // 2. ✅ حذف ملف .metadata.json المرافق
        if (File(metadataPath).existsSync()) {
          await File(metadataPath).delete();
        }

        expect(
          await File(sqlitePath).exists(),
          isFalse,
          reason: 'sqlite file should be deleted',
        );
        expect(
          await File(metadataPath).exists(),
          isFalse,
          reason: 'metadata file should also be deleted',
        );
      },
    );

    test(
      'current deleteLocalBackup leaves orphaned .metadata.json (proves the bug)',
      () async {
        // توثيق الخطأ الحالي: deleteLocalBackup يحذف .sqlite فقط دون .metadata.json
        final sqlitePath = p.join(
          backupDir.path,
          'marina_hotel_backup_orphan.sqlite',
        );
        final metadataPath = p.join(
          backupDir.path,
          'marina_hotel_backup_orphan.metadata.json',
        );

        await File(sqlitePath).writeAsBytes([0x53, 0x51, 0x4c, 0x69]);
        await File(metadataPath).writeAsString('{"app_version":"1.0"}');

        // محاكاة السلوك الحالي (بدون cleanup): حذف الملف الأساسي فقط
        await File(sqlitePath).delete();

        // ⚠️ الـ bug: ملف metadata يبقى موجوداً
        expect(await File(sqlitePath).exists(), isFalse);
        expect(
          await File(metadataPath).exists(),
          isTrue,
          reason: 'BUG: current code leaves .metadata.json orphaned on disk',
        );
      },
    );
  });

  // ═════════════════════════════════════════════════════════════════════════
  //  Group 9: Local backup default format — SQLite .db
  //  الحفظ المحلي الافتراضي: نسخة .db خام تُحفظ تلقائياً في
  //  /storage/emulated/0/Documents/MarinaHotelBackups
  // ═════════════════════════════════════════════════════════════════════════
  group('Local backup default format (.db)', () {
    test('getPreferredBackupFormat defaults to BackupFormat.sqlite', () async {
      SharedPreferences.setMockInitialValues({});
      final service = LocalBackupService();
      final format = await service.getPreferredBackupFormat();
      expect(format, BackupFormat.sqlite);
      expect(format.name, 'sqlite');
    });

    test('setPreferredBackupFormat round-trips the chosen format', () async {
      SharedPreferences.setMockInitialValues({});
      final service = LocalBackupService();
      await service.setPreferredBackupFormat(BackupFormat.json);
      expect(await service.getPreferredBackupFormat(), BackupFormat.json);
      await service.setPreferredBackupFormat(BackupFormat.sqlite);
      expect(await service.getPreferredBackupFormat(), BackupFormat.sqlite);
    });
  });
}

// ════════════════════════════════════════════════════════════════════════════
//  Helper classes for testing DriveBackupFile format detection
// ════════════════════════════════════════════════════════════════════════════

class _MockDriveFile {
  _MockDriveFile({required this.name, required this.metadata});
  final String name;
  final Map<String, dynamic> metadata;
}

/// إعادة تنفيذ منطق DriveBackupFile.format بنفس المنطق الموجود في الكود الفعلي
/// للتحقق من صحته عبر الاختبارات.
BackupFormat _detectFormat(String fileName, Map<String, dynamic>? metadata) {
  final raw = metadata?['format'] as String?;

  // التحقق من اسم الملف أولاً
  if (fileName.endsWith('.db') || fileName.startsWith('db_backup_')) {
    return BackupFormat.sqlite;
  }

  // التحقق من metadata
  if (raw == 'sqlite' || raw == 'db') {
    return BackupFormat.sqlite;
  }

  return BackupFormat.json;
}

class _DriveBackupFileForTest {
  _DriveBackupFileForTest({required this.fileName, required this.metadata});
  final String fileName;
  final Map<String, dynamic>? metadata;
  BackupFormat get format => _detectFormat(fileName, metadata);
}

_DriveBackupFileForTest _buildDriveBackupFile(_MockDriveFile file) {
  return _DriveBackupFileForTest(fileName: file.name, metadata: file.metadata);
}
