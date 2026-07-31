import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';

void main() {
  group('AppwriteSyncUtils', () {
    group('collectionSchema', () {
      test('booking_price_adjustments should have hotelDayKey', () {
        final schema = AppwriteSyncUtils.collectionSchema;
        final bpaSchema = schema['booking_price_adjustments'];
        expect(bpaSchema, isNotNull);
        expect(bpaSchema!.containsKey('hotelDayKey'), isTrue);
        expect(bpaSchema['hotelDayKey'], 'string');
      });

      test('booking_price_adjustments should have appliedDate', () {
        final schema = AppwriteSyncUtils.collectionSchema;
        final bpaSchema = schema['booking_price_adjustments'];
        expect(bpaSchema, isNotNull);
        expect(bpaSchema!.containsKey('appliedDate'), isTrue);
        expect(bpaSchema['appliedDate'], 'string');
      });

      test('booking_price_adjustments amount should be double', () {
        final schema = AppwriteSyncUtils.collectionSchema;
        final bpaSchema = schema['booking_price_adjustments'];
        expect(bpaSchema, isNotNull);
        expect(bpaSchema!['amount'], 'double');
      });

      test(
        'booking_price_adjustments should have all required sync fields',
        () {
          final schema = AppwriteSyncUtils.collectionSchema;
          final bpaSchema = schema['booking_price_adjustments']!;

          final requiredFields = [
            'localUuid',
            'adjustmentType',
            'createdAt',
            'updatedAt',
            'lastModified',
            'lastModifiedEpoch',
            'version',
            'syncTimestamp',
            'hotelDayKey',
            'effectiveHotelDay',
            'bookingLocalUuid',
          ];

          for (final field in requiredFields) {
            expect(
              bpaSchema.containsKey(field),
              isTrue,
              reason: '$field should be in schema',
            );
          }
        },
      );
    });

    group('validFieldsPerCollection', () {
      test('booking_price_adjustments should include hotelDayKey', () {
        final fields = AppwriteSyncUtils.validFieldsPerCollection;
        final bpaFields = fields['booking_price_adjustments'];
        expect(bpaFields, isNotNull);
        expect(bpaFields!.contains('hotelDayKey'), isTrue);
      });

      test('booking_price_adjustments should include appliedDate', () {
        final fields = AppwriteSyncUtils.validFieldsPerCollection;
        final bpaFields = fields['booking_price_adjustments'];
        expect(bpaFields, isNotNull);
        expect(bpaFields!.contains('appliedDate'), isTrue);
      });

      test('booking_price_adjustments should include amount', () {
        final fields = AppwriteSyncUtils.validFieldsPerCollection;
        final bpaFields = fields['booking_price_adjustments'];
        expect(bpaFields, isNotNull);
        expect(bpaFields!.contains('amount'), isTrue);
      });
    });

    group('filterPayloadForCollection', () {
      test('should keep hotelDayKey in booking_price_adjustments payload', () {
        final payload = <String, dynamic>{
          'localUuid': 'test-uuid',
          'hotelDayKey': '2026-07-26',
          'effectiveHotelDay': '2026-07-26',
          'amount': 50.5,
          'adjustmentType': 0,
          'unknownField': 'should be filtered',
        };

        final filtered = AppwriteSyncUtils.filterPayloadForCollection(
          'booking_price_adjustments',
          payload,
        );

        expect(filtered.containsKey('hotelDayKey'), isTrue);
        expect(filtered['hotelDayKey'], '2026-07-26');
        expect(filtered.containsKey('unknownField'), isFalse);
      });

      test('should keep appliedDate in booking_price_adjustments payload', () {
        final payload = <String, dynamic>{
          'appliedDate': '2026-07-26',
          'hotelDayKey': '2026-07-26',
        };

        final filtered = AppwriteSyncUtils.filterPayloadForCollection(
          'booking_price_adjustments',
          payload,
        );

        expect(filtered.containsKey('appliedDate'), isTrue);
        expect(filtered['appliedDate'], '2026-07-26');
      });

      test('should coerce amount to double', () {
        final payload = <String, dynamic>{
          'amount': 150, // int
        };

        final filtered = AppwriteSyncUtils.filterPayloadForCollection(
          'booking_price_adjustments',
          payload,
        );

        expect(filtered['amount'], isA<double>());
      });
    });
  });
}
