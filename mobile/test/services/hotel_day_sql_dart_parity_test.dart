// ============================================================================
//  Marina Hotel — تطابق تصنيف اليوم الفندقي بين SQL وDart (بند 3.5 + 8.3)
// ============================================================================
//  سجل بطابع UTC منتهٍ بـ Z مثل 2026-06-28T14:00:00.000Z (= 17:00 بتوقيت
//  عدن) يجب أن يُصنَّف اليوم الفندقي نفسه في تقرير SQL اليومي والمحرك
//  (كان الـ SQL الساذج يقارن توقيت UTC الخام بحدود 14:01 الجدارية
//  فيصنفه اليوم السابق — 10 سجلات إنتاج مؤثرة).
//  لا mock — قاعدة SQLite حقيقية في الذاكرة.
// ============================================================================

import 'package:drift/drift.dart' as d;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';
import 'package:marina_hotel_mobile/services/repositories/payments_repository.dart';
import 'package:marina_hotel_mobile/services/repositories/rooms_repository.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';
import 'package:marina_hotel_mobile/utils/hotel_timezone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase db;
  late PaymentsRepository paymentsRepo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    paymentsRepo = PaymentsRepository(db);
    await RoomsRepository(db).create(
      roomNumber: '101',
      type: 'عادية',
      price: 100.0,
      status: 'شاغرة',
    );
  });

  tearDown(() => db.close());

  Future<void> insertPaymentWithDate(
    String localUuid,
    String paymentDate,
    double amount,
  ) async {
    final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await db
        .into(db.payments)
        .insert(
          PaymentsCompanion.insert(
            localUuid: localUuid,
            createdAt: nowEpoch,
            updatedAt: nowEpoch,
            lastModified: nowEpoch,
            amount: amount,
            paymentDate: paymentDate,
            paymentMethod: 'نقدي',
            revenueType: 'room',
            roomNumber: const d.Value('101'),
            // بلا hotelDayKey — نفرض مسار التصنيف الاحتياطي في SQL
          ),
        );
  }

  Future<double> totalForDay(String hotelDay) =>
      paymentsRepo.watchTotalByHotelDayKey(hotelDay).first;

  test('طابع UTC (Z) يُصنَّف في SQL كما يصنفه Dart — نفس اليوم الفندقي',
      () async {
    // 14:00:00Z = 17:00 عدن → بعد حد 14:01 → اليوم الفندقي نفسه 2026-06-28
    const zStamp = '2026-06-28T14:00:00.000Z';
    await insertPaymentWithDate('pay-z-parity', zStamp, 100);

    // تصنيف Dart (المرجع): تحويل اللحظة المطلقة إلى توقيت الفندق
    final dartDay = HotelTimeEngine.getHotelDayKey(
      dateTime: HotelTimezone.parseHotelDateTime(zStamp),
    );
    expect(dartDay, '2026-06-28',
        reason: '17:00 عدن بعد حد 14:01 → نفس اليوم');

    // تصنيف SQL (المُصلَّح): يجب أن يطابق Dart
    expect(await totalForDay('2026-06-28'), 100.0,
        reason: 'الـ SQL بعد الإصلاح يحول Z إلى +3 ساعات قبل المقارنة');
    expect(await totalForDay('2026-06-27'), 0.0,
        reason: 'لم يعد يُصنف خطأً في اليوم السابق');
  });

  test('طابع جداري خام (بلا منطقة) يقارن كما هو — قبل الحد يقع بالأمس',
      () async {
    // 14:00 جدارية (قبل حد 14:01) → اليوم الفندقي السابق 2026-06-27
    await insertPaymentWithDate('pay-naive-1400', '2026-06-28 14:00:00', 50);
    await insertPaymentWithDate('pay-naive-1500', '2026-06-28 15:00:00', 70);

    expect(await totalForDay('2026-06-27'), 50.0,
        reason: '14:00 قبل الحد → أمس (كما في Dart)');
    expect(await totalForDay('2026-06-28'), 70.0,
        reason: '15:00 بعد الحد → نفس اليوم');
  });

  test('حد العتبة بالضبط 14:01Z (= 17:01 عدن) → نفس اليوم، لا اليوم التالي',
      () async {
    const zStamp = '2026-06-28T11:01:00.000Z'; // = 14:01 عدن بالضبط
    await insertPaymentWithDate('pay-z-threshold', zStamp, 30);

    final dartDay = HotelTimeEngine.getHotelDayKey(
      dateTime: HotelTimezone.parseHotelDateTime(zStamp),
    );
    expect(dartDay, '2026-06-28');
    expect(await totalForDay('2026-06-28'), 30.0);
    expect(await totalForDay('2026-06-29'), 0.0);
  });
}
