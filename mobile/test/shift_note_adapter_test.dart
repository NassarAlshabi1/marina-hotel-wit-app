import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/models/shift_note_adapter.dart' as adapter;
import 'package:marina_hotel_mobile/services/local_db.dart';

BookingNote _bookingNote({
  required String localUuid,
  required int id,
  required int bookingId,
  required String noteText,
  required String alertType,
  int isActive = 1,
  String? alertUntil,
}) {
  return BookingNote(
    localUuid: localUuid,
    serverId: null,
    createdAt: 1,
    updatedAt: 1,
    deletedAt: null,
    lastModified: 1,
    syncTimestamp: 1,
    createdAtIso: null,
    updatedAtIso: null,
    deletedAtIso: null,
    createdAtEpoch: 1,
    lastModifiedEpoch: 1,
    version: 1,
    origin: 'app',
    id: id,
    bookingId: bookingId,
    noteText: noteText,
    alertType: alertType,
    alertUntil: alertUntil,
    isActive: isActive,
    vectorClock: '{}',
    deviceId: 'test',
  );
}

void main() {
  test('toBookingNoteData encodes shift note for booking storage', () {
    final note = adapter.ShiftNote(
      id: '1',
      title: 'Title',
      content: 'Body',
      priority: adapter.NotePriority.high,
      shiftType: adapter.ShiftType.night,
      createdAt: DateTime.utc(2024, 1, 2, 3, 4, 5),
      expiresAt: DateTime.utc(2024, 1, 3, 4, 5, 6),
      isRead: false,
      status: adapter.NoteStatus.active,
      createdBy: 'user',
    );

    final data = adapter.ShiftNoteAdapter.toBookingNoteData(note);

    expect(data['booking_id'], adapter.ShiftNoteAdapter.generalNotesBookingId);
    expect(data['note_text'], 'Title|||Body');
    expect(data['alert_type'], 'H-NIG');
    expect(data['alert_until'], '2024-01-03T04:05:06.000Z');
    expect(data['is_active'], 1);
  });

  test('fromBookingNote decodes booking note into shift note model', () {
    final booking = _bookingNote(
      localUuid: 'u1',
      id: 7,
      bookingId: 1,
      noteText: 'عنوان|||محتوى',
      alertType: 'M-MOR',
      alertUntil: '2024-01-02T03:00:00Z',
    );

    final shift = adapter.ShiftNoteAdapter.fromBookingNote(booking);

    expect(shift.id, '7');
    expect(shift.title, 'عنوان');
    expect(shift.content, 'محتوى');
    expect(shift.priority, adapter.NotePriority.medium);
    expect(shift.shiftType, adapter.ShiftType.morning);
    expect(shift.createdAt.millisecondsSinceEpoch, 1);
    expect(shift.expiresAt?.toIso8601String(), '2024-01-02T03:00:00.000Z');
    expect(shift.isRead, isFalse);
    expect(shift.status, adapter.NoteStatus.active);
  });

  test('fromBookingNote falls back when delimiter or alertType missing', () {
    final booking = _bookingNote(
      localUuid: 'u2',
      id: 9,
      bookingId: 2,
      noteText: 'SoloNote',
      alertType: 'L-ALL',
      isActive: 0,
    );

    final shift = adapter.ShiftNoteAdapter.fromBookingNote(booking);

    expect(shift.title, 'SoloNote');
    expect(shift.content, 'SoloNote');
    expect(shift.priority, adapter.NotePriority.low);
    expect(shift.shiftType, adapter.ShiftType.all);
    expect(shift.expiresAt, isNull);
    expect(shift.isRead, isTrue);
    expect(shift.status, adapter.NoteStatus.completed);
  });
}
