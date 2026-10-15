import 'package:drift/drift.dart' as d;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import '../utils/time.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

/// Other devices resolve pulled booking nights and notes by booking UUID only.
/// Rows created before that rule were pushed without `bookingUuidCache`, so
/// they are skipped on pull. This stamps the UUID on local nights and queues
/// the affected nights and notes for a one-off re-push.
class BookingChildUuidBackfillService {
  BookingChildUuidBackfillService._();
  static final BookingChildUuidBackfillService instance =
      BookingChildUuidBackfillService._();

  static const notesRepushPrefKey = 'booking_notes_uuid_repush_v1';
  static const _chunkSize = 500;

  bool _applied = false;

  /// Runs at most once per session; each step is idempotent.
  Future<void> runIfNeeded(AppDatabase db) async {
    if (_applied) return;
    _applied = true;
    try {
      final nights = await backfillNights(db);
      final notes = await repushNotesOnce(db);
      if (nights > 0 || notes > 0) {
        dlog(
          () =>
              '✅ BookingChildUuidBackfill: ليالي=$nights، ملاحظات=$notes '
              'أُضيفت إلى طابور الرفع',
        );
      }
    } catch (e) {
      dwarn(() => '⚠️ BookingChildUuidBackfill: $e');
    }
  }

  /// Fills `bookingUuidCache` on nights that lack it and queues them for push.
  /// `lastModified` is left untouched: the content is unchanged and the
  /// remote copy must not look older than the local one.
  Future<int> backfillNights(AppDatabase db) async {
    final rows = await db
        .customSelect(
          'SELECT n.id AS id, n.local_uuid AS night_uuid, '
          'b.local_uuid AS booking_uuid '
          'FROM booking_nights n '
          'JOIN bookings b ON b.id = n.booking_local_id '
          "WHERE (n.booking_uuid_cache IS NULL OR n.booking_uuid_cache = '') "
          'AND n.deleted_at IS NULL '
          "AND b.local_uuid IS NOT NULL AND b.local_uuid <> ''",
          readsFrom: {db.bookingNights, db.bookings},
        )
        .get();
    if (rows.isEmpty) return 0;

    final outboxDao = OutboxDao(db);
    final clientTs = Time.nowEpoch();
    for (var i = 0; i < rows.length; i += _chunkSize) {
      final chunk = rows.sublist(
        i,
        i + _chunkSize < rows.length ? i + _chunkSize : rows.length,
      );
      await db.transaction(() async {
        for (final row in chunk) {
          await (db.update(
            db.bookingNights,
          )..where((n) => n.id.equals(row.read<int>('id')))).write(
            BookingNightsCompanion(
              bookingUuidCache: d.Value(row.read<String>('booking_uuid')),
            ),
          );
        }
        await outboxDao.mergeBatch([
          for (final row in chunk)
            _outboxItem(
              'booking_nights',
              row.read<String>('night_uuid'),
              clientTs,
            ),
        ]);
      });
    }
    return rows.length;
  }

  /// Notes have no local UUID column; the push path adds the booking UUID, so
  /// every live note is queued once to replace the remote copies without it.
  Future<int> repushNotesOnce(AppDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(notesRepushPrefKey) ?? false) return 0;

    final rows = await db
        .customSelect(
          'SELECT n.local_uuid AS note_uuid, b.local_uuid AS booking_uuid '
          'FROM booking_notes n '
          'JOIN bookings b ON b.id = n.booking_id '
          'WHERE n.deleted_at IS NULL '
          "AND b.local_uuid IS NOT NULL AND b.local_uuid <> ''",
          readsFrom: {db.bookingNotes, db.bookings},
        )
        .get();

    final outboxDao = OutboxDao(db);
    final clientTs = Time.nowEpoch();
    for (var i = 0; i < rows.length; i += _chunkSize) {
      final chunk = rows.sublist(
        i,
        i + _chunkSize < rows.length ? i + _chunkSize : rows.length,
      );
      await outboxDao.mergeBatch([
        for (final row in chunk)
          <String, dynamic>{
            'entity': 'booking_notes',
            'op': 'update',
            'localUuid': row.read<String>('note_uuid'),
            'payload': <String, dynamic>{
              'localUuid': row.read<String>('note_uuid'),
              'booking_uuid_cache': row.read<String>('booking_uuid'),
            },
            'clientTs': clientTs,
          },
      ]);
    }
    await prefs.setBool(notesRepushPrefKey, true);
    return rows.length;
  }

  Map<String, dynamic> _outboxItem(
    String entity,
    String localUuid,
    int clientTs,
  ) => <String, dynamic>{
    'entity': entity,
    'op': 'update',
    'localUuid': localUuid,
    'payload': <String, dynamic>{'localUuid': localUuid},
    'clientTs': clientTs,
  };
}
