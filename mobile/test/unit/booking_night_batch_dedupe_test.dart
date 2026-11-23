import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync/booking_night_batch_dedupe.dart';

// ══════════════════════════════════════════════════════════════════
//  عقد 2026-11-23: صفحة السحب قد تحمل الليلة الواحدة بهويتين.
//  يجب أن تُطبَّق مرة واحدة فقط، والفائز هو الأحدث زمنياً — بترتيب
//  حتمي يتفق عليه كل الأجهزة (updated_at ← version ← last_modified
//  ← local_uuid) — كي لا يختلف محتوى الليالي بين الأجهزة.
// ══════════════════════════════════════════════════════════════════

PullRecord _night(
  String uuid, {
  required String bookingUuid,
  required String day,
  int updatedAt = 100,
  int version = 1,
  int lastModified = 100,
}) => (
  entity: 'booking_nights',
  record: <String, dynamic>{
    'local_uuid': uuid,
    'booking_uuid_cache': bookingUuid,
    'hotel_day_key': day,
    'updated_at': updatedAt,
    'version': version,
    'last_modified': lastModified,
  },
);

void main() {
  const booking = 'AAAAAAAA-1111-4111-8111-AAAAAAAAAAAA';

  group('BookingNightBatchDedupe.collapse', () {
    test('same (booking, day) with two identities → newest updated_at wins', () {
      final collapsed = BookingNightBatchDedupe.collapse([
        _night('uuid-old', bookingUuid: booking, day: '2026-11-20', updatedAt: 100),
        _night('uuid-new', bookingUuid: booking, day: '2026-11-20', updatedAt: 200),
      ]);

      expect(collapsed, hasLength(1));
      expect(collapsed.single.record['local_uuid'], 'uuid-new');
    });

    test('version breaks ties when updated_at is equal', () {
      final collapsed = BookingNightBatchDedupe.collapse([
        _night('uuid-a', bookingUuid: booking, day: '2026-11-20', version: 1),
        _night('uuid-b', bookingUuid: booking, day: '2026-11-20', version: 4),
      ]);

      expect(collapsed.single.record['local_uuid'], 'uuid-b');
    });

    test('local_uuid is the deterministic final tie-break', () {
      final first = BookingNightBatchDedupe.collapse([
        _night('uuid-a', bookingUuid: booking, day: '2026-11-20'),
        _night('uuid-b', bookingUuid: booking, day: '2026-11-20'),
      ]);
      final reversed = BookingNightBatchDedupe.collapse([
        _night('uuid-b', bookingUuid: booking, day: '2026-11-20'),
        _night('uuid-a', bookingUuid: booking, day: '2026-11-20'),
      ]);

      // نفس الفائز مهما كان ترتيب الصفحة — لا يتغير محتوى الجهاز بتغير الترتيب.
      expect(first.single.record['local_uuid'], 'uuid-b');
      expect(reversed.single.record['local_uuid'], 'uuid-b');
    });

    test('same booking, different days and different bookings are kept', () {
      final collapsed = BookingNightBatchDedupe.collapse([
        _night('n1', bookingUuid: booking, day: '2026-11-20'),
        _night('n2', bookingUuid: booking, day: '2026-11-21'),
        _night(
          'n3',
          bookingUuid: 'BBBBBBBB-2222-4222-8222-BBBBBBBBBBBB',
          day: '2026-11-20',
        ),
      ]);

      expect(collapsed, hasLength(3));
    });

    test('uuid formatting/case does not split a slot', () {
      final collapsed = BookingNightBatchDedupe.collapse([
        _night('n1', bookingUuid: booking, day: '2026-11-20'),
        _night(
          'n2',
          bookingUuid: 'aaaaaaaa111141118111aaaaaaaaaaaa',
          day: '2026-11-20',
          updatedAt: 999,
        ),
      ]);

      expect(collapsed, hasLength(1));
      expect(collapsed.single.record['local_uuid'], 'n2');
    });

    test('records without a booking identity pass through untouched', () {
      final collapsed = BookingNightBatchDedupe.collapse([
        (
          entity: 'booking_nights',
          record: <String, dynamic>{
            'local_uuid': 'orphan-1',
            'hotel_day_key': '2026-11-20',
          },
        ),
        (
          entity: 'booking_nights',
          record: <String, dynamic>{
            'local_uuid': 'orphan-2',
            'hotel_day_key': '2026-11-20',
          },
        ),
      ]);

      expect(collapsed, hasLength(2));
    });

    test('other entities are never deduped against nights', () {
      final collapsed = BookingNightBatchDedupe.collapse([
        (
          entity: 'payments',
          record: <String, dynamic>{
            'local_uuid': 'p1',
            'booking_uuid_cache': booking,
            'hotel_day_key': '2026-11-20',
          },
        ),
        _night('n1', bookingUuid: booking, day: '2026-11-20'),
        _night('n2', bookingUuid: booking, day: '2026-11-20', updatedAt: 500),
      ]);

      expect(collapsed, hasLength(2));
      expect(
        collapsed.where((r) => r.entity == 'payments'),
        hasLength(1),
      );
      expect(
        collapsed.singleWhere((r) => r.entity == 'booking_nights').record['local_uuid'],
        'n2',
      );
    });
  });

  group('BookingNightBatchDedupe.slotKey', () {
    test('null when the day is missing', () {
      expect(
        BookingNightBatchDedupe.slotKey({'booking_uuid': booking}),
        isNull,
      );
    });

    test('null when the booking identity is missing', () {
      expect(
        BookingNightBatchDedupe.slotKey({'hotel_day_key': '2026-11-20'}),
        isNull,
      );
    });
  });
}
