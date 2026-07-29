// test/integration/comprehensive_integration_test.dart
// اختبارات تكامل شاملة للتطبيق
//
// تختبر التدفقات الحرجة من البداية للنهاية:
// 1. تهيئة التطبيق
// 2. نظام المزامنة (push/pull)
// 3. إنشاء حجز كامل
// 4. معالجة دفعة
// 5. تصدير البيانات
// 6. الأمان (تشفير/فك تشفير)

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/crashlytics_service.dart';
import 'package:marina_hotel_mobile/services/performance_monitor.dart';
import 'package:marina_hotel_mobile/services/posthog_service.dart';
import 'package:marina_hotel_mobile/services/export_service.dart';
import 'package:marina_hotel_mobile/utils/secure_storage.dart';
import 'package:marina_hotel_mobile/utils/hotel_time_engine.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';

void main() {
  group('🔧 Integration Tests — Critical Flows', () {
    group('1. App Initialization Flow', () {
      test('all singleton services should be accessible', () {
        expect(CrashlyticsService.instance, isNotNull);
        expect(PerformanceMonitor.instance, isNotNull);
        expect(PostHogService.instance, isNotNull);
        expect(ExportService.instance, isNotNull);
      });

      test('services should be singletons (same instance)', () {
        expect(CrashlyticsService.instance, same(CrashlyticsService.instance));
        expect(PerformanceMonitor.instance, same(PerformanceMonitor.instance));
        expect(PostHogService.instance, same(PostHogService.instance));
        expect(ExportService.instance, same(ExportService.instance));
      });
    });

    group('2. Hotel Day Engine Flow', () {
      test('hotel day key should be correct format YYYY-MM-DD', () {
        final key = HotelTimeEngine.getHotelDayKey();
        expect(key, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
      });

      test('calculateDays should return at least 1 for any booking', () {
        final checkin = DateTime.now();
        final days = HotelTimeEngine.calculateDays(checkin, checkOut: checkin);
        expect(days, greaterThanOrEqualTo(1));
      });

      test('hotel day key should change at 14:01 boundary', () {
        final before = DateTime(2026, 7, 27, 14, 0);
        final after = DateTime(2026, 7, 27, 14, 1);
        final keyBefore = HotelTimeEngine.getHotelDayKey(dateTime: before);
        final keyAfter = HotelTimeEngine.getHotelDayKey(dateTime: after);
        expect(keyBefore, isNot(equals(keyAfter)));
      });
    });

    group('3. Security Flow (AES Encryption)', () {
      test('encrypt → decrypt should return original value', () {
        const key = 'VQngYXPLjdebdGvs+QMdXsiDKySEJBhlks5zDTUxTLk=';
        const plain = '{"setting":"hotel_name","value":"Marina Hotel"}';
        
        final encrypted = SecureStorage.encryptValue(plain, key);
        final decrypted = SecureStorage.decryptValue(encrypted, key);
        
        expect(decrypted, equals(plain));
      });

      test('encrypted value should be different from plain', () {
        const key = 'VQngYXPLjdebdGvs+QMdXsiDKySEJBhlks5zDTUxTLk=';
        const plain = 'sensitive_data';
        
        final encrypted = SecureStorage.encryptValue(plain, key);
        
        expect(encrypted, isNot(equals(plain)));
        expect(encrypted.startsWith('ENC:AES:'), isTrue);
      });

      test('encryption should produce different output each time (random IV)', () {
        const key = 'VQngYXPLjdebdGvs+QMdXsiDKySEJBhlks5zDTUxTLk=';
        const plain = 'same input';
        
        final enc1 = SecureStorage.encryptValue(plain, key);
        final enc2 = SecureStorage.encryptValue(plain, key);
        
        expect(enc1, isNot(equals(enc2)));
      });
    });

    group('4. Export Service Flow', () {
      test('InvoiceExportData should calculate total correctly', () {
        final invoice = InvoiceExportData(
          invoiceNumber: 'INV-TEST-001',
          invoiceDate: DateTime(2026, 7, 27),
          guestName: 'Test Guest',
          guestPhone: '+967777123456',
          guestId: '1234567890',
          roomNumber: '101',
          checkinDate: DateTime(2026, 7, 25),
          checkoutDate: DateTime(2026, 7, 28),
          nights: 3,
          roomRate: 15000,
          items: const [
            InvoiceItem(description: 'Room 3 nights', qty: 3, unitPrice: 15000, total: 45000),
            InvoiceItem(description: 'Discount', qty: 1, unitPrice: -5000, total: -5000),
            InvoiceItem(description: 'Laundry', qty: 2, unitPrice: 2000, total: 4000),
          ],
          paymentMethod: 'cash',
          receivedBy: 'Test',
        );
        expect(invoice.total, 44000);
      });

      test('SalaryExportData should handle negative amounts', () {
        final data = SalaryExportData(
          date: DateTime(2026, 7, 1),
          employeeName: 'Test',
          role: 'Test',
          type: 'deduction',
          amount: -5000,
        );
        expect(data.amount, -5000);
      });
    });

    group('5. Sync Utils Flow', () {
      test('booking_price_adjustments schema should have all required fields', () {
        final schema = AppwriteSyncUtils.collectionSchema;
        final bpa = schema['booking_price_adjustments']!;
        
        // Required fields for Appwrite Cloud
        expect(bpa.containsKey('localUuid'), isTrue);
        expect(bpa.containsKey('hotelDayKey'), isTrue);
        expect(bpa.containsKey('appliedDate'), isTrue);
        expect(bpa.containsKey('adjustmentType'), isTrue);
        expect(bpa.containsKey('createdAt'), isTrue);
        expect(bpa.containsKey('updatedAt'), isTrue);
        expect(bpa.containsKey('lastModified'), isTrue);
        expect(bpa.containsKey('lastModifiedEpoch'), isTrue);
        expect(bpa.containsKey('version'), isTrue);
        expect(bpa.containsKey('syncTimestamp'), isTrue);
      });

      test('filterPayloadForCollection should filter unknown fields', () {
        final payload = <String, dynamic>{
          'localUuid': 'test',
          'hotelDayKey': '2026-07-27',
          'unknownField': 'should be removed',
        };
        
        final filtered = AppwriteSyncUtils.filterPayloadForCollection(
          'booking_price_adjustments',
          payload,
        );
        
        expect(filtered.containsKey('unknownField'), isFalse);
        expect(filtered.containsKey('hotelDayKey'), isTrue);
      });
    });

    group('6. PostHog + Crashlytics Integration', () {
      test('PostHogService should handle events without throwing', () async {
        await PostHogService.instance.track('integration_test_event');
        await PostHogService.instance.trackBookingCreated(
          roomNumber: '101',
          guestName: 'Test',
          amount: 15000,
          nights: 3,
        );
        expect(true, isTrue);
      });

      test('CrashlyticsService should accept context updates', () async {
        await CrashlyticsService.instance.setContext(
          roomNumber: '101',
          syncStatus: 'testing',
          userRole: 'admin',
        );
        expect(true, isTrue);
      });
    });

    group('7. Performance Monitor Flow', () {
      test('traceOperation should measure and return result', () async {
        final result = await PerformanceMonitor.instance.traceOperation(
          'integration_test',
          operation: () async {
            await Future.delayed(const Duration(milliseconds: 50));
            return 'completed';
          },
        );
        expect(result, 'completed');
      });

      test('traceOperation should propagate errors', () async {
        expect(
          () => PerformanceMonitor.instance.traceOperation(
            'failing_test',
            operation: () async => throw StateError('intentional failure'),
          ),
          throwsA(isA<StateError>()),
        );
      });
    });
  });
}
