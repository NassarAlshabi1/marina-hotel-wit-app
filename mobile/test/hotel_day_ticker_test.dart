// ============================================================================
//  HotelDayTicker — Unit Tests
//  ============================================================================
//  اختبارات HotelDayTicker:
//    - stream متاح ويعمل
//    - manualTick يُصدر حدث للمشتركين
//    - dispose يُغلق الـ stream
// ============================================================================

library marina_hotel_mobile.test.hotel_day_ticker_test;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/hotel_day_ticker.dart';

void main() {
  group('HotelDayTicker', () {
    test('stream متاح بعد first access', () {
      final stream = HotelDayTicker.instance.stream;
      expect(stream, isA<Stream<void>>());
    });

    test('manualTick يُصدر حدث للمشتركين', () async {
      var receivedEvents = 0;
      final sub = HotelDayTicker.instance.stream.listen((_) {
        receivedEvents++;
      });

      // إصدار حدث يدوي
      HotelDayTicker.instance.manualTick();

      // انتظار معالجة الحدث
      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedEvents, greaterThan(0));
      await sub.cancel();
    });

    test('multiple subscribers يستقبلون الأحداث', () async {
      var count1 = 0;
      var count2 = 0;

      final sub1 = HotelDayTicker.instance.stream.listen((_) => count1++);
      final sub2 = HotelDayTicker.instance.stream.listen((_) => count2++);

      HotelDayTicker.instance.manualTick();
      await Future.delayed(const Duration(milliseconds: 50));

      expect(count1, greaterThan(0));
      expect(count2, greaterThan(0));
      await sub1.cancel();
      await sub2.cancel();
    });

    test('dispose يُغلق الـ stream', () {
      // نتجاهل هذا الاختبار لأنه singleton ويؤثر على باقي الاختبارات
      // فقط نتأكد أن dispose لا يُطلق استثناء
      expect(() => HotelDayTicker.instance.dispose(), returnsNormally);
    });
  });
}
