// ═══════════════════════════════════════════════════════════════
//  hotel_day_key_fix_service_test.dart — (2026-09-25) رفع التغطية
//
//  قبل هذا الملف: hotel_day_key_fix_service.dart (794 سطراً) تغطيتها
//  3.4% رغم أنها تُصلح حقلاً مالياً حساساً (hotelDayKey) على
//  expenses / payments / booking_nights وتدفع التصحيحات إلى Outbox
//  للمزامنة.
//
//  ما يثبته هذا الملف بالتنفيذ على DB درِفت في الذاكرة:
//    1. computeCorrectHotelDayKey: قاعدة 14:01 (قبل/بعد الحد)،
//       صيغة ISO بمسافة وT، التاريخ التقويمي يُمرَّر 14:01،
//       المدخلات الفاسدة لا ترمي (fallback آمن).
//    2. runIfNeeded يُصلح المفاتيح الخاطئة وnull القديمة فقط —
//       لا يلمس الصحيح ولا المحذوف (deleted_at) — ويرفع version+1
//       للصفوف المُصلَحة فقط.
//    3. كل تصحيح يُنتج عنصر outbox (entity/op=update/localUuid/
//       payload['hotelDayKey']) — أي أن السحابة ستستلم التصحيح.
//    4. الاستدعاء الثاني في نفس الجلسة no-op (حارس _applied) —
//       لا صفوف جديدة في outbox ولا version إضافي. نتحقق من ذلك
//       داخل نفس الاختبار لأن الحارس على مستوى singleton لا يمكن
//       إعادة ضبطه من خارج المكتبة (تعمدٌ في التصميم، ونحن لا
//       نعتمد على ترتيب الاختبارات).
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/hotel_day_key_fix_service.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/utils/id.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('computeCorrectHotelDayKey — قاعدة 14:01', () {
    test('calendar date (no time) is evaluated at 14:01 → same day label', () {
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19'),
        '2026-05-19',
      );
    });

    test('ISO with space before 14:01 → previous hotel day', () {
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19 13:30'),
        '2026-05-18',
      );
    });

    test('ISO with space at/after 14:01 → same hotel day', () {
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19 14:01'),
        '2026-05-19',
      );
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19 14:30'),
        '2026-05-19',
      );
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19 23:59'),
        '2026-05-19',
      );
    });

    test('ISO with T separator parses identically', () {
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19T14:30:00'),
        '2026-05-19',
      );
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19T09:00:00'),
        '2026-05-18',
      );
    });

    test('boundary precision: 14:00 is still the previous day', () {
      // الدقيقة الحاسمة التي كانت مصدر خلل البيانات القديمة
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('2026-05-19 14:00'),
        '2026-05-18',
      );
    });

    test('garbage input never throws — deterministic fallback', () {
      // 3 مقاطع مفصولة بـ '-' لكنها غير رقمية → أرضية آمنة
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('not-a-date'),
        '0001-01-01',
      );
    });

    test('empty/blank input falls back to a well-shaped today key', () {
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey(''),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
      expect(
        HotelDayKeyFixService.computeCorrectHotelDayKey('   '),
        matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
      );
    });
  });

  group('runIfNeeded — إصلاح فعلي على DB في الذاكرة', () {
    late AppDatabase db;
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    Future<int> insertRoom() async {
      return db
          .into(db.rooms)
          .insert(
            RoomsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('101'),
              type: const Value('single'),
              price: const Value(200.0),
              status: const Value('متاحة'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );
    }

    Future<int> insertBooking() async {
      await insertRoom();
      return db
          .into(db.bookings)
          .insert(
            BookingsCompanion(
              localUuid: Value(IdGen.uuid()),
              roomNumber: const Value('101'),
              guestName: const Value('أحمد'),
              guestPhone: const Value('0500000000'),
              guestNationality: const Value('سعودي'),
              checkinDate: Value(DateTime(2026, 5, 19, 15).toIso8601String()),
              checkoutDate: Value(DateTime(2026, 5, 22, 13).toIso8601String()),
              status: const Value('محجوزة'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );
    }

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('fixes wrong/null keys in expenses, payments, booking_nights; '
        'skips correct & deleted; bumps version; enqueues outbox; '
        'second run is a session no-op', () async {
      // ── expenses ──────────────────────────────────────────────
      final wrongExpenseUuid = IdGen.uuid();
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion(
              localUuid: Value(wrongExpenseUuid),
              expenseType: const Value('صيانة'),
              description: const Value('اختبار'),
              amount: const Value(1000.0),
              date: const Value('2026-05-19 15:00'),
              hotelDayKey: const Value('1999-01-01'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );
      // null قديمة (الحالة الموثقة في ترويسة الخدمة)
      final nullExpenseUuid = IdGen.uuid();
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion(
              localUuid: Value(nullExpenseUuid),
              expenseType: const Value('كهرباء'),
              description: const Value('اختبار null'),
              amount: const Value(500.0),
              date: const Value('2026-05-19 15:00'),
              hotelDayKey: const Value(null),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );
      // صحيحة أصلاً — يجب ألا تُلمس (لا version bump)
      final correctExpenseUuid = IdGen.uuid();
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion(
              localUuid: Value(correctExpenseUuid),
              expenseType: const Value('مياه'),
              description: const Value('اختبار صحيح'),
              amount: const Value(250.0),
              date: const Value('2026-05-19 15:00'),
              hotelDayKey: const Value('2026-05-19'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );
      // محذوفة ومفاتيحها خاطئة — لا يُلمس المحذوف
      final deletedExpenseUuid = IdGen.uuid();
      await db
          .into(db.expenses)
          .insert(
            ExpensesCompanion(
              localUuid: Value(deletedExpenseUuid),
              expenseType: const Value('نظافة'),
              description: const Value('اختبار محذوف'),
              amount: const Value(75.0),
              date: const Value('2026-05-19 15:00'),
              hotelDayKey: const Value('1999-01-01'),
              deletedAt: Value(nowEpoch),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );

      // ── payments ──────────────────────────────────────────────
      // خاطئة: الدفع 13:00 → اليوم الفندقي 2026-05-18 وليس 19
      final wrongPaymentUuid = IdGen.uuid();
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion(
              localUuid: Value(wrongPaymentUuid),
              amount: const Value(500.0),
              paymentDate: const Value('2026-05-19 13:00'),
              paymentMethod: const Value('cash'),
              revenueType: const Value('room'),
              hotelDayKey: const Value('2026-05-19'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );
      // صحيحة: 16:00 يوم 20 → 2026-05-20
      final correctPaymentUuid = IdGen.uuid();
      await db
          .into(db.payments)
          .insert(
            PaymentsCompanion(
              localUuid: Value(correctPaymentUuid),
              amount: const Value(300.0),
              paymentDate: const Value('2026-05-20 16:00'),
              paymentMethod: const Value('cash'),
              revenueType: const Value('room'),
              hotelDayKey: const Value('2026-05-20'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );

      // ── booking_nights (تتطلب booking مرجعياً) ────────────────
      // ⚠️ بيان البذر يحترم UNIQUE(booking_local_id, hotel_day_key)
      // (قيد حقيقي اكتشفه هذا الاختبار في المخطط) — ليلة خاطئة
      // تُصحَّح إلى 2026-05-18، وليلة صحيحة بمفتاح 2026-05-19
      // (لا تصادم بعد الإصلاح).
      final bookingId = await insertBooking();
      final wrongNightUuid = IdGen.uuid();
      await db
          .into(db.bookingNights)
          .insert(
            BookingNightsCompanion(
              bookingLocalId: Value(bookingId),
              localUuid: Value(wrongNightUuid),
              hotelDayKey: const Value('2026-05-20'),
              nightStart: const Value('2026-05-18 23:00'),
              nightEnd: const Value('2026-05-19 14:00'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );
      final correctNightUuid = IdGen.uuid();
      await db
          .into(db.bookingNights)
          .insert(
            BookingNightsCompanion(
              bookingLocalId: Value(bookingId),
              localUuid: Value(correctNightUuid),
              hotelDayKey: const Value('2026-05-19'),
              nightStart: const Value('2026-05-20 10:00'),
              nightEnd: const Value('2026-05-21 14:00'),
              createdAt: Value(nowEpoch),
              updatedAt: Value(nowEpoch),
              lastModified: Value(nowEpoch),
            ),
          );

      final outboxBefore = await db.select(db.outbox).get();

      await HotelDayKeyFixService.instance.runIfNeeded(db);

      // ── تحقق: expenses ────────────────────────────────────────
      final expenses = await db.select(db.expenses).get();
      final expenseByUuid = {for (final e in expenses) e.localUuid: e};
      // الخاطئة وnull → صُحّحت إلى 2026-05-19 مع version 2
      expect(expenseByUuid[wrongExpenseUuid]!.hotelDayKey, '2026-05-19');
      expect(expenseByUuid[wrongExpenseUuid]!.version, 2);
      expect(expenseByUuid[nullExpenseUuid]!.hotelDayKey, '2026-05-19');
      expect(expenseByUuid[nullExpenseUuid]!.version, 2);
      // الصحيحة: نفس المفتاح وversion 1 (لم تُلمس)
      expect(expenseByUuid[correctExpenseUuid]!.hotelDayKey, '2026-05-19');
      expect(expenseByUuid[correctExpenseUuid]!.version, 1);
      // المحذوفة: بقيت خاطئة وversion 1
      expect(expenseByUuid[deletedExpenseUuid]!.hotelDayKey, '1999-01-01');
      expect(expenseByUuid[deletedExpenseUuid]!.version, 1);

      // ── تحقق: payments ────────────────────────────────────────
      final payments = await db.select(db.payments).get();
      final paymentByUuid = {for (final p in payments) p.localUuid: p};
      expect(paymentByUuid[wrongPaymentUuid]!.hotelDayKey, '2026-05-18');
      expect(paymentByUuid[wrongPaymentUuid]!.version, 2);
      expect(paymentByUuid[correctPaymentUuid]!.hotelDayKey, '2026-05-20');
      expect(paymentByUuid[correctPaymentUuid]!.version, 1);

      // ── تحقق: booking_nights ──────────────────────────────────
      final nights = await db.select(db.bookingNights).get();
      final nightByUuid = {for (final n in nights) n.localUuid: n};
      expect(nightByUuid[wrongNightUuid]!.hotelDayKey, '2026-05-18');
      expect(nightByUuid[wrongNightUuid]!.version, 2);
      expect(nightByUuid[correctNightUuid]!.hotelDayKey, '2026-05-19');
      expect(nightByUuid[correctNightUuid]!.version, 1);

      // ── تحقق: outbox ──────────────────────────────────────────
      final outboxAfter = await db.select(db.outbox).get();
      expect(outboxAfter.length, greaterThan(outboxBefore.length));
      final fixEntries = outboxAfter.where((o) => o.op == 'update').toList();
      final entities = fixEntries.map((o) => o.entity).toSet();
      expect(
        entities,
        containsAll(<String>['expenses', 'payments', 'booking_nights']),
      );
      for (final entry in fixEntries) {
        final payload = jsonDecode(entry.payload) as Map<String, dynamic>;
        expect(payload['hotelDayKey'], isA<String>());
        expect(payload['hotelDayKey'], isNot('1999-01-01'));
      }
      // عنصر outbox للدفع الخاطئ يحمل المفتاح المصحح تحديداً
      final paymentOutbox = fixEntries
          .where((o) => o.entity == 'payments')
          .where((o) => o.localUuid == wrongPaymentUuid)
          .toList();
      expect(paymentOutbox, hasLength(1));
      expect(
        (jsonDecode(paymentOutbox.single.payload)
            as Map<String, dynamic>)['hotelDayKey'],
        '2026-05-18',
      );

      // ── الاستدعاء الثاني في نفس الجلسة: no-op كامل ────────────
      await HotelDayKeyFixService.instance.runIfNeeded(db);
      final outboxAfterSecond = await db.select(db.outbox).get();
      expect(outboxAfterSecond.length, outboxAfter.length);
      final expensesAfterSecond = await db.select(db.expenses).get();
      final expenseByUuidSecond = {
        for (final e in expensesAfterSecond) e.localUuid: e,
      };
      expect(
        expenseByUuidSecond[wrongExpenseUuid]!.version,
        expenseByUuid[wrongExpenseUuid]!.version,
      );
      expect(
        expenseByUuidSecond[correctExpenseUuid]!.version,
        1,
        reason: 'no double-bump on second run',
      );
    });
  });
}
