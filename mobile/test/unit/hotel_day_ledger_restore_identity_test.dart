// test/unit/hotel_day_ledger_restore_identity_test.dart
//
// ✅ (2026-10-07) قفل إصلاح دفتر اليوم الفندقي (hotel_day_ledger).
//
// الخلفية (دليل من الكود — تدقيق «جدول محلي لا يتم مزامنته»):
//   1) الهوية كانت غير حتمية: night_audit_service كان يكتب
//      `local_uuid = '${millis}-${hotelDayKeyHash}'`، وrestore_fix_service
//      كان يحذف الجدول كاملاً ثم يُدرج صفوفاً جديدة بـ IdGen.uuid ⇒ معرّف
//      جديد لنفس اليوم في كل إعادة بناء/استعادة.
//   2) إعادة البناء كانت تكتب status='finalized'/'draft' بينما منطق الإقفال
//      الوحيد يقرأ 'closed' ⇒ يوم مُقفل يظهر مفتوحاً بعد الاستعادة.
//   3) إعادة البناء كانت تكتب الإشغال كسراً (0..1) بينما NightAuditService
//      وقارئ GeminiService يستخدمان النسبة المئوية (0..100).
//   4) الصفوف المُشتقة كانت تُكتب بمجاميع كسرية دون المرور بسياسة
//      «بدون كسور عشرية» (اقتطاع نحو الصفر).
//
// هذا الاختبار يحرس: الهوية الحتمية (Dart ↔ SQL)، عدم المساس بالأيام
// المُقفلة، تحديث الصفوف المُشتقة في مكانها، حذف المُشتق بلا أثر فقط،
// اقتطاع الكسور، ونسبة الإشغال، وترحيل 70 على قاعدة حقيقية.
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/hotel_day_ledger_identity.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/restore_fix_service.dart';
import 'package:marina_hotel_mobile/utils/currency_formatter.dart';
import 'package:marina_hotel_mobile/utils/id.dart';
import 'package:marina_hotel_mobile/utils/time.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite3;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // ═══════════════════════════════════════════════════════════════════
  //  1) الهوية الحتمية + تطابق Dart ↔ SQL
  // ═══════════════════════════════════════════════════════════════════
  group('هوية دفتر اليوم الفندقي', () {
    test('deterministicUuid: حتمي وفريد ومشتق من المفتاح', () {
      expect(
        HotelDayLedgerIdentity.deterministicUuid('2026-10-07'),
        equals('ldg-20261007'),
      );
      expect(
        HotelDayLedgerIdentity.deterministicUuid('2026-10-07'),
        equals(HotelDayLedgerIdentity.deterministicUuid('2026-10-07')),
      );
      expect(
        HotelDayLedgerIdentity.deterministicUuid('2026-10-07'),
        isNot(equals(HotelDayLedgerIdentity.deterministicUuid('2026-10-08'))),
      );
    });

    test('isLegacyUuid يميّز الصيغة القديمة ولا يخمّن غيرها', () {
      expect(
        HotelDayLedgerIdentity.isLegacyUuid('1759795200000-20261007'),
        isTrue,
      );
      expect(HotelDayLedgerIdentity.isLegacyUuid('ldg-20261007'), isFalse);
      // uuid v4 عادي (إن وُجد يوماً) لا يُصنَّف قديماً ولا يُلمس.
      expect(
        HotelDayLedgerIdentity.isLegacyUuid(
          'a1b2c3d4-1111-2222-3333-444455556666',
        ),
        isFalse,
      );
    });

    test(
      'عبارة SQL تُنتج نفس قيمة deterministicUuid حرفياً (تطابق إلزامي)',
      () {
        final raw = sqlite3.sqlite3.openInMemory();
        addTearDown(raw.dispose);
        raw.execute(
          'CREATE TABLE hotel_day_ledger ('
          'local_uuid TEXT NOT NULL, hotel_day_key TEXT NOT NULL, status TEXT)',
        );
        raw.execute(
          "INSERT INTO hotel_day_ledger VALUES "
          "('1759795200000-20261007', '2026-10-07', 'closed')",
        );
        raw.execute(HotelDayLedgerIdentity.legacyUuidNormalizeSql);
        final row = raw.select('SELECT * FROM hotel_day_ledger').single;
        expect(
          row['local_uuid'],
          equals(HotelDayLedgerIdentity.deterministicUuid('2026-10-07')),
        );
        // ولا يُمَس عمود آخر إطلاقاً.
        expect(row['status'], equals('closed'));
      },
    );
  });

  // ═══════════════════════════════════════════════════════════════════
  //  2) إعادة البناء بعد الاستعادة — غير مُدمِّرة
  // ═══════════════════════════════════════════════════════════════════
  group('إعادة بناء الدفتر بعد الاستعادة', () {
    late AppDatabase database;
    late RestoreFixService service;

    setUp(() async {
      database = AppDatabase.forTesting(NativeDatabase.memory());
      service = RestoreFixService(database);
    });

    tearDown(() async {
      await database.close();
    });

    /// حجز نشط (مغادرته غداً) + دفعة + غرفة بسعر 200.
    Future<void> seedActiveBooking({double roomPrice = 200.0}) async {
      final now = Time.nowEpoch();
      await database
          .into(database.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('101'),
              type: const Value('single'),
              price: Value(roomPrice),
              status: const Value('محجوزة'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      final bookingId = await database
          .into(database.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('101'),
              guestName: const Value('ضيف الاختبار'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('يمني'),
              checkinDate: Value(
                DateTime.now()
                    .subtract(const Duration(days: 5))
                    .toIso8601String(),
              ),
              checkoutDate: Value(
                DateTime.now().add(const Duration(days: 1)).toIso8601String(),
              ),
              status: const Value('محجوزة'),
              expectedNights: const Value(1),
              calculatedNights: const Value(1),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      await database
          .into(database.payments)
          .insert(
            PaymentsCompanion(
              localUuid: Value(IdGen.uuid()),
              bookingLocalId: Value(bookingId),
              amount: const Value(400),
              paymentDate: Value(DateTime.now().toIso8601String()),
              paymentMethod: const Value('cash'),
              revenueType: const Value('room'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
    }

    test(
      'صف مُشتق جديد: هوية حتمية + حالة rebuilt + إشغال بالنسبة المئوية',
      () async {
        await seedActiveBooking();
        final report = await service.runAutoFixAfterRestore();
        expect(report.success, isTrue);

        final rows = await database.select(database.hotelDayLedger).get();
        expect(rows, isNotEmpty, reason: 'إعادة البناء يجب أن تُنتج صفوف دفتر');

        for (final row in rows) {
          expect(row.localUuid, startsWith('ldg-'));
          expect(
            HotelDayLedgerIdentity.isLegacyUuid(row.localUuid),
            isFalse,
            reason: 'لا يجوز إنتاج هوية الطابع الزمني القديمة',
          );
          expect(
            row.localUuid,
            equals(HotelDayLedgerIdentity.deterministicUuid(row.hotelDayKey)),
          );
          expect(row.status, equals(HotelDayLedgerIdentity.statusRebuilt));
        }

        // نسبة الإشغال: غرفة واحدة مشغولة ⇒ 100% (العيب القديم كان يكتب 1.0).
        final occupiedRows = rows
            .where((r) => r.occupancyRate > 0)
            .toList(growable: false);
        if (occupiedRows.isNotEmpty) {
          expect(
            occupiedRows.first.occupancyRate,
            greaterThan(1.0),
            reason: 'الإشغال يُخزَّن كنسبة مئوية (0..100) كما في NightAudit',
          );
        }
      },
    );

    test('إعادة البناء مرتين تُبقي نفس الهوية (لا معرّفات جديدة)', () async {
      await seedActiveBooking();
      await service.runAutoFixAfterRestore();
      final first = {
        for (final row in await database.select(database.hotelDayLedger).get())
          row.hotelDayKey: row.localUuid,
      };

      await service.runAutoFixAfterRestore();
      final second = {
        for (final row in await database.select(database.hotelDayLedger).get())
          row.hotelDayKey: row.localUuid,
      };

      expect(second, equals(first));
    });

    test('يوم مُقفل: لا تُكتب فوقه المجاميع ولا الحالة ولا الهوية', () async {
      await seedActiveBooking();
      await service.runAutoFixAfterRestore();

      final rows = await database.select(database.hotelDayLedger).get();
      final target = rows.first;
      await (database.update(
        database.hotelDayLedger,
      )..where((t) => t.id.equals(target.id))).write(
        HotelDayLedgerCompanion(
          status: const Value(HotelDayLedgerIdentity.statusClosed),
          totalIncome: const Value(7777777.0),
        ),
      );

      final report = await service.runAutoFixAfterRestore();
      expect(report.success, isTrue);

      final closed = await (database.select(
        database.hotelDayLedger,
      )..where((t) => t.id.equals(target.id))).getSingle();
      expect(closed.status, equals(HotelDayLedgerIdentity.statusClosed));
      expect(closed.totalIncome, equals(7777777.0));
      expect(closed.localUuid, equals(target.localUuid));
      expect(
        report.changes.any((c) => c.contains('حُفظ')),
        isTrue,
        reason: 'يجب أن يذكر تقرير الإصلاح أن الأيام المُقفلة حُفظت',
      );
    });

    test(
      'الصفوف المُشتقة بلا أثر تُحذف — والمُقفلة تبقى حتى بلا أثر',
      () async {
        final now = Time.nowEpoch();
        await database
            .into(database.hotelDayLedger)
            .insert(
              HotelDayLedgerCompanion(
                localUuid: const Value('ldg-19900101'),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
                hotelDayKey: const Value('1990-01-01'),
                status: const Value('finalized'),
              ),
            );
        await database
            .into(database.hotelDayLedger)
            .insert(
              HotelDayLedgerCompanion(
                localUuid: const Value('ldg-19900102'),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
                hotelDayKey: const Value('1990-01-02'),
                status: const Value(HotelDayLedgerIdentity.statusClosed),
                totalIncome: const Value(55.0),
              ),
            );

        await seedActiveBooking();
        await service.runAutoFixAfterRestore();

        final remaining = await database.select(database.hotelDayLedger).get();
        expect(
          remaining.where((r) => r.hotelDayKey == '1990-01-01'),
          isEmpty,
          reason: 'صف مُشتق بلا أثر يُحذف',
        );
        final closed = remaining
            .where((r) => r.hotelDayKey == '1990-01-02')
            .toList(growable: false);
        expect(closed, hasLength(1));
        expect(closed.single.totalIncome, equals(55.0));
        expect(closed.single.localUuid, equals('ldg-19900102'));
      },
    );

    test('بلا حجوزات: تُمسح الصفوف المُشتقة فقط ولا يُمحى يوم مُقفل', () async {
      final now = Time.nowEpoch();
      await database
          .into(database.hotelDayLedger)
          .insert(
            HotelDayLedgerCompanion(
              localUuid: const Value('ldg-19900201'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
              hotelDayKey: const Value('1990-02-01'),
              status: const Value('draft'),
            ),
          );
      await database
          .into(database.hotelDayLedger)
          .insert(
            HotelDayLedgerCompanion(
              localUuid: const Value('ldg-19900202'),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
              hotelDayKey: const Value('1990-02-02'),
              status: const Value(HotelDayLedgerIdentity.statusClosed),
              totalIncome: const Value(99.0),
            ),
          );

      final report = await service.runAutoFixAfterRestore();
      expect(report.success, isTrue);

      final remaining = await database.select(database.hotelDayLedger).get();
      expect(remaining.where((r) => r.hotelDayKey == '1990-02-01'), isEmpty);
      final closed = remaining
          .where((r) => r.hotelDayKey == '1990-02-02')
          .toList(growable: false);
      expect(closed, hasLength(1));
      expect(closed.single.totalIncome, equals(99.0));
    });

    test('مجاميع الدفتر المُشتق تُقتطع بلا كسور (اقتطاع نحو الصفر)', () async {
      await seedActiveBooking(roomPrice: 200.5);
      await service.runAutoFixAfterRestore();

      final before = await database.select(database.hotelDayLedger).get();
      expect(before, isNotEmpty);
      final target = before.first;

      // مصروف كسري بمفتاح يوم موجود ⇒ المجموع الخام = القديم + 150.5
      // والاقتطاع نحو الصفر يعني +150 (وليس +151 كما يفعل التقريب).
      final now = Time.nowEpoch();
      await database
          .into(database.expenses)
          .insert(
            ExpensesCompanion(
              localUuid: Value(IdGen.uuid()),
              expenseType: const Value('مصروفات عامة'),
              description: const Value('اختبار كسور عشرية'),
              amount: const Value(150.5),
              date: Value(DateTime.now().toIso8601String()),
              hotelDayKey: Value(target.hotelDayKey),
              createdAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );

      await service.runAutoFixAfterRestore();

      final rows = await database.select(database.hotelDayLedger).get();
      for (final row in rows) {
        expect(
          CurrencyFormatter.isWholeAmount(row.totalIncome),
          isTrue,
          reason: 'totalIncome بلا كسور (${row.hotelDayKey})',
        );
        expect(
          CurrencyFormatter.isWholeAmount(row.totalExpenses),
          isTrue,
          reason: 'totalExpenses بلا كسور (${row.hotelDayKey})',
        );
        expect(
          CurrencyFormatter.isWholeAmount(row.pendingBalances),
          isTrue,
          reason: 'pendingBalances بلا كسور (${row.hotelDayKey})',
        );
      }

      final updated = rows.firstWhere(
        (r) => r.hotelDayKey == target.hotelDayKey,
      );
      expect(
        updated.totalExpenses,
        equals(target.totalExpenses + 150),
        reason: '150.5 ⇒ 150 (اقتطاع) وليس 151 (تقريب)',
      );
    });
  });

  // ═══════════════════════════════════════════════════════════════════
  //  3) ترحيل 70 — توحيد الهوية على قاعدة حقيقية (idempotent)
  // ═══════════════════════════════════════════════════════════════════
  group('ترحيل 70: توحيد معرّفات الدفتر القديمة', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('m70_ledger_test');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test(
      'قاعدة تحمل معرّفاً قديمياً تُوحَّد عند الفتح ولا يُمَس غير المعرّف',
      () async {
        final path = '${tmpDir.path}/ledger.db';

        // 1) إنشاء القاعدة بالمخطط الحقيقي (v70) وإدخال صف اختباري.
        final created = AppDatabase.forTesting(NativeDatabase(File(path)));
        final now = Time.nowEpoch();
        await created
            .into(created.hotelDayLedger)
            .insert(
              HotelDayLedgerCompanion(
                localUuid: const Value('ldg-20261007'),
                createdAt: Value(now),
                updatedAt: Value(now),
                lastModified: Value(now),
                hotelDayKey: const Value('2026-10-07'),
                status: const Value(HotelDayLedgerIdentity.statusClosed),
                totalIncome: const Value(1234.0),
              ),
            );
        await created.close();

        // 2) محاكاة قاعدة أنتجها إصدار 69: معرّف الطابع الزمني القديم.
        final raw = sqlite3.sqlite3.open(path);
        raw.execute('PRAGMA user_version = 69');
        raw.execute(
          "UPDATE hotel_day_ledger SET local_uuid = '1759795200000-20261007'",
        );
        raw.dispose();

        // 3) الفتح الفعلي ⇒ onUpgrade(69 → 70) + beforeOpen.
        final migrated = AppDatabase.forTesting(NativeDatabase(File(path)));
        await migrated.customSelect('SELECT 1').get();
        final row = await migrated.select(migrated.hotelDayLedger).getSingle();
        expect(
          row.localUuid,
          equals(HotelDayLedgerIdentity.deterministicUuid('2026-10-07')),
        );
        expect(row.status, equals(HotelDayLedgerIdentity.statusClosed));
        expect(row.totalIncome, equals(1234.0));

        // 4) إعادة الفتح ⇒ لا تغيير (idempotent).
        await migrated.close();
        final reopened = AppDatabase.forTesting(NativeDatabase(File(path)));
        await reopened.customSelect('SELECT 1').get();
        final again = await reopened
            .select(reopened.hotelDayLedger)
            .getSingle();
        expect(again.localUuid, equals(row.localUuid));
        expect(again.totalIncome, equals(1234.0));
        expect(again.status, equals(HotelDayLedgerIdentity.statusClosed));
        await reopened.close();
      },
    );
  });
}
