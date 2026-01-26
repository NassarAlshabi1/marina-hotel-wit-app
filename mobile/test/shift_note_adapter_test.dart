import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/models/shift_note_adapter.dart';
import 'package:marina_hotel_mobile/services/local_db.dart';

void main() {
  test('toBookingNoteData encodes shift note for booking storage', () {
    final note = ShiftNote(
      id: '1',
      title: 'Title',
      content: 'Body',
      priority: NotePriority.high,
      shiftType: ShiftType.night,
      createdAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
      expiresAt: DateTime.utc(2024, 1, 3, 4, 5, 6),
      isRead: false,
      status: NoteStatus.active,
      createdBy: 'user',
    );

    final data = ShiftNoteAdapter.toBookingNoteData(note);

    expect(data['booking_id'], ShiftNoteAdapter.GENERAL_NOTES_BOOKING_ID);
    expect(data['note_text'], 'Title|||Body');
    expect(data['alert_type'], 'H-NIG');
    expect(data['alert_until'], '2024-01-03T04:05:06.000Z');
    expect(data['is_active'], 1);
  });

  test('fromBookingNote decodes booking note into shift note model', () {
    final booking = BookingNote(
      localUuid: 'u1',
      serverId: null,
      createdAt: 1,
      updatedAt: 2,
      deletedAt: null,
      lastModified: 3,
      createdAtIso: null,
      updatedAtIso: null,
      deletedAtIso: null,
      createdAtEpoch: 1,
      lastModifiedEpoch: 3,
      version: 1,
      origin: 'app',
      id: 7,
      bookingId: 1,
      noteText: 'عنوان|||محتوى',
      alertType: 'M-MOR',
      alertUntil: '2024-01-02T03:00:00Z',
      isActive: 1,
    );

    final shift = ShiftNoteAdapter.fromBookingNote(booking);

    expect(shift.id, '7');
    expect(shift.title, 'عنوان');
    expect(shift.content, 'محتوى');
    expect(shift.priority, NotePriority.medium);
    expect(shift.shiftType, ShiftType.morning);
    expect(shift.createdAt.millisecondsSinceEpoch, 1);
    expect(shift.expiresAt?.toIso8601String(), '2024-01-02T03:00:00.000Z');
    expect(shift.isRead, isFalse);
    expect(shift.status, NoteStatus.active);
  });

  test('fromBookingNote falls back when delimiter or alertType missing', () {
    final booking = BookingNote(
      localUuid: 'u2',
      serverId: null,
      createdAt: 1000,
      updatedAt: 1000,
      deletedAt: null,
      lastModified: 1000,
      createdAtIso: null,
      updatedAtIso: null,
      deletedAtIso: null,
      createdAtEpoch: 1000,
      lastModifiedEpoch: 1000,
      version: 1,
      origin: 'app',
      id: 9,
      bookingId: 2,
      noteText: 'SoloNote',
      alertType: 'L-ALL',
      alertUntil: null,
      isActive: 0,
    );

    final shift = ShiftNoteAdapter.fromBookingNote(booking);

    expect(shift.title, 'SoloNote');
    expect(shift.content, 'SoloNote');
    expect(shift.priority, NotePriority.low);
    expect(shift.shiftType, ShiftType.all);
    expect(shift.expiresAt, isNull);
    expect(shift.isRead, isTrue);
    expect(shift.status, NoteStatus.completed);
  });
}
