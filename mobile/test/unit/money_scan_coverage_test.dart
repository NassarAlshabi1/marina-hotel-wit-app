// test/unit/money_scan_coverage_test.dart
//
// ✅ (G-8 / 2026-10-06): إثبات **تغطية** فحص الكسور العشرية — لا ثغرات صامتة.
//
// **الحالة التي كشفها هذا التقرير (دليل من الكود):** كان فحص الكسور في
// `MoneyIntegrityService.scan()` يستعلم عن عمود `amount` في جدول
// `price_adjustments` — والجدول لا يملك هذا العمود إطلاقاً (يخزّن
// `previous_value`/`new_value`، انظر local_db.dart) ⇒ كان الاستعلام يفشل
// ويُلتقط كتحذير فقط، فيظنّ التقرير أن الجدول «نظيف» بينما هو **خارج
// الفحص بالكامل**. وبفحص كل الأعمدة المالية من نوع REAL ظهرت أعمدة أخرى
// خارج الفحص (debts.amount/paid_amount/remaining_amount،
// booking_nights.base_rate/final_rate، hotel_day_ledger.pending_balances،
// payment_voids.original_amount، bookings.total_paid_cached،
// employees.basic_salary).
//
// هذا الاختبار يزرع كسراً واحداً في **كل** عمود من تلك الأعمدة ويتأكد أن
// كل واحد منها يُبلَّغ صراحةً للمراجعة البشرية بلا أي إصلاح تلقائي.
import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/money_integrity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  const now = 1700000000;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('كل عمود مالي من نوع REAL كان خارج التغطية أصبح مُبلَّغاً', () async {
    // 1) employees.basic_salary
    await db
        .into(db.employees)
        .insert(
          EmployeesCompanion.insert(
            localUuid: 'emp-cov',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            name: 'موظف تغطية',
            basicSalary: 1000.75,
            status: 'active',
          ),
        );

    // 2) debts: amount / paid_amount / remaining_amount
    await db.customStatement(
      'INSERT INTO debts (local_uuid, created_at, updated_at, last_modified, '
      'guest_name, checkin_date, checkout_date, total_amount, paid_amount, '
      "remaining_amount, payment_date, amount) VALUES ('debt-cov', ?, ?, ?, "
      "'نزيل', '2026-01-01', '2026-01-02', 100.25, 50.5, 49.75, "
      "'2026-01-02', 0.5)",
      [now, now, now],
    );

    // 3) hotel_day_ledger.pending_balances
    await db.customStatement(
      'INSERT INTO hotel_day_ledger (local_uuid, created_at, updated_at, '
      "last_modified, hotel_day_key, pending_balances) VALUES ('hdl-cov', ?, "
      "?, ?, '2026-01-01', 12.5)",
      [now, now, now],
    );

    // 4) payment_voids.original_amount
    await db.customStatement(
      'INSERT INTO payment_voids (local_uuid, created_at, updated_at, '
      'last_modified, original_payment_uuid, original_payment_id, booking_uuid, '
      'voided_amount, void_reason, voided_by, voided_at, voided_at_iso, '
      "hotel_day_key, original_amount) VALUES ('pv-cov', ?, ?, ?, 'pay-1', 1, "
      "'bk-1', 500, 'سبب', 'مستخدم', ?, '2026-01-01T00:00:00Z', "
      "'2026-01-01', 500.25)",
      [now, now, now, now],
    );

    // 5) price_adjustments.previous_value + new_value
    await db.customStatement(
      'INSERT INTO price_adjustments (local_uuid, created_at, updated_at, '
      'last_modified, target_type, target_uuid, adjustment_type, '
      'previous_value, new_value, effective_date, applied_by) VALUES '
      "('pa-cov', ?, ?, ?, 'room', 'room-1', 'price', 100.5, 120.75, "
      "'2026-01-01', 'مدير')",
      [now, now, now],
    );

    // 6) bookings.total_paid_cached + booking_nights.base_rate/final_rate
    await db
        .into(db.rooms)
        .insert(
          RoomsCompanion.insert(
            localUuid: 'room-cov',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            roomNumber: 'C1',
            type: 'std',
            price: 100,
            status: 'available',
          ),
        );
    final bookingId = await db
        .into(db.bookings)
        .insert(
          BookingsCompanion.insert(
            localUuid: 'bk-cov',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            roomNumber: 'C1',
            guestName: 'نزيل',
            guestPhone: '1',
            guestNationality: 'يمني',
            checkinDate: '2026-01-01',
            status: 'active',
            totalPaidCached: const d.Value(1500.5),
          ),
        );
    await db
        .into(db.bookingNights)
        .insert(
          BookingNightsCompanion.insert(
            localUuid: 'bn-cov',
            createdAt: now,
            updatedAt: now,
            lastModified: now,
            bookingLocalId: bookingId,
            hotelDayKey: '2026-01-01',
            nightStart: '2026-01-01',
            nightEnd: '2026-01-02',
            baseRate: const d.Value(100.5),
            finalRate: const d.Value(200.25),
          ),
        );

    // ── الفحص ────────────────────────────────────────────────────────────
    final report = await MoneyIntegrityService(db).scan();

    const expectedTables = [
      'employees.basic_salary',
      'debts.amount',
      'debts.paid_amount',
      'debts.remaining_amount',
      'hotel_day_ledger.pending_balances',
      'payment_voids.original_amount',
      'price_adjustments.previous_value',
      'price_adjustments.new_value',
      'bookings.total_paid_cached',
      'booking_nights.base_rate',
      'booking_nights.final_rate',
    ];

    for (final table in expectedTables) {
      expect(
        report.countByTable[table],
        1,
        reason:
            'العمود $table يجب أن يُفحص فعلاً ويُبلَّغ — أي قيمة null هنا '
            'تعني أنه خارج التغطية بصمت',
      );
      expect(
        report.scannedTables,
        contains(table),
        reason: 'الجدول $table يجب أن يُعلن فحصه',
      );
    }

    // ولا صفّ يُعدَّل: القيم التاريخية باقية كما زُرعت.
    final employee = (await (db.select(
      db.employees,
    )..where((t) => t.localUuid.equals('emp-cov'))).getSingle()).basicSalary;
    expect(employee, 1000.75);
    final debt = await db
        .customSelect(
          "SELECT amount, paid_amount, remaining_amount FROM debts "
          "WHERE local_uuid = 'debt-cov'",
        )
        .getSingle();
    expect(debt.read<double>('amount'), 0.5);
    expect(debt.read<double>('paid_amount'), 50.5);
    expect(debt.read<double>('remaining_amount'), 49.75);
    final priceAdjustment = await db
        .customSelect(
          'SELECT previous_value, new_value FROM price_adjustments '
          "WHERE local_uuid = 'pa-cov'",
        )
        .getSingle();
    expect(priceAdjustment.read<double>('previous_value'), 100.5);
    expect(priceAdjustment.read<double>('new_value'), 120.75);
  });

  test('تحذير فشل الاستعلام لا يُخفى: الجداول المفحوصة كلها موجودة', () async {
    // قاعدة نظيفة: لا كسور، ومع ذلك يجب أن تكون كل الأعمدة المفحوصة قابلة
    // للاستعلام فعلاً (غياب العمود = فشل الاستعلام = ثغرة صامتة).
    final report = await MoneyIntegrityService(db).scan();
    expect(report.isClean, isTrue);
    // 29 استعلاماً بعد إصلاح التغطية + استعلاما الحجوزات الإضافيان.
    expect(report.scannedTables.length, greaterThanOrEqualTo(29));
    expect(report.scannedTables, contains('price_adjustments.previous_value'));
    expect(report.scannedTables, contains('price_adjustments.new_value'));
  });
}
