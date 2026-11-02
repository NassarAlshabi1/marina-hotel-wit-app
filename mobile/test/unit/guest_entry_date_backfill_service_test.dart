import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/guest_entry_date_backfill_service.dart';

void main() {
  group('GuestEntryDateBackfillService', () {
    test('treats only null and blank strings as missing entryDate', () {
      expect(GuestEntryDateBackfillService.isEntryDateMissing(null), isTrue);
      expect(GuestEntryDateBackfillService.isEntryDateMissing(''), isTrue);
      expect(GuestEntryDateBackfillService.isEntryDateMissing('  '), isTrue);
      expect(
        GuestEntryDateBackfillService.isEntryDateMissing('2026-07-02'),
        isFalse,
      );
      expect(GuestEntryDateBackfillService.isEntryDateMissing(0), isFalse);
    });

    test('recognizes current and legacy soft-delete markers', () {
      expect(
        GuestEntryDateBackfillService.isSoftDeleted({'deletedAt': 123}),
        isTrue,
      );
      expect(
        GuestEntryDateBackfillService.isSoftDeleted({'deleted_at': '123'}),
        isTrue,
      );
      expect(
        GuestEntryDateBackfillService.isSoftDeleted({
          'deletedAtIso': '2026-07-02T10:00:00Z',
        }),
        isTrue,
      );
      expect(
        GuestEntryDateBackfillService.isSoftDeleted({
          'deletedAt': 0,
          'deletedAtIso': '',
        }),
        isFalse,
      );
    });

    test('formats Appwrite createdAt without timezone conversion', () {
      expect(
        GuestEntryDateBackfillService.entryDateFromCreatedAt(
          '2026-07-02T23:55:00.000Z',
        ),
        '2026-07-02',
      );
    });

    test('rejects invalid or missing createdAt values', () {
      expect(
        GuestEntryDateBackfillService.entryDateFromCreatedAt(null),
        isNull,
      );
      expect(
        GuestEntryDateBackfillService.entryDateFromCreatedAt('not-a-date'),
        isNull,
      );
      expect(
        GuestEntryDateBackfillService.entryDateFromCreatedAt(
          '2026-02-31T00:00:00Z',
        ),
        isNull,
      );
    });
  });
}
