import 'package:drift/drift.dart' as d;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';
import '../utils/time.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

/// Other devices resolve pulled booking nights and notes by booking UUID only.
/// Rows created before that rule were pushed without `bookingUuidCache`, so
/// they are skipped on pull. This stamps the UUID on local nights and queues
/// the affected nights (in small batches) and notes for a one-off re-push.
class BookingChildUuidBackfillService {
  BookingChildUuidBackfillService._();
  static final BookingChildUuidBackfillService instance =
      BookingChildUuidBackfillService._();

  static const notesRepushPrefKey = 'booking_notes_uuid_repush_v1';

  /// Legacy nights queued per step. The next step waits until the queued
  /// nights have been pushed, so a large history drains gradually instead of
  /// flooding the outbox on low-memory devices.
  static const nightsBatchSize = 200;
  static const _notesChunkSize = 500;

  bool _nightsDone = false;
  bool _running = false;

  /// Called at session start and after each successful sync. Each step is
  /// idempotent and cheap once the backlog is gone.
  Future<void> runPending(AppDatabase db) async {
    if (_running) return;
    _running = true;
    try {
      final notes = await repushNotesOnce(db);
      var nights = 0;
      if (!_nightsDone) {
        final step = await backfillNights(db);
        nights = step.queued;
        _nightsDone = step.done;
      }
      if (nights > 0 || notes > 0) {
        dlog(
          () =>
              '✅ BookingChildUuidBackfill: ليالي=$nights، ملاحظات=$notes '
              'أُضيفت إلى طابور الرفع',
        );
      }
    } catch (e) {
      dwarn(() => '⚠️ BookingChildUuidBackfill: $e');
    } finally {
      _running = false;
    }
  }

  /// Stamps `bookingUuidCache` on up to [batchSize] legacy nights and queues
  /// them for push, unless earlier queued nights are still waiting.
  /// `lastModified` is left untouched: the content is unchanged and the
  /// remote copy must not look older than the local one.
  Future<({int queued, bool done})> backfillNights(
    AppDatabase db, {
    int batchSize = nightsBatchSize,
  }) async {
    final waiting = await db
        .customSelect(
          'SELECT COUNT(*) AS c FROM outbox '
          "WHERE entity = 'booking_nights' "
          "AND processing_status IN ('pending', 'processing', 'failed')",
          readsFrom: {db.outbox},
        )
        .getSingle();
    if (waiting.read<int>('c') >= batchSize) {
      return (queued: 0, done: false);
    }

    final rows = await db
        .customSelect(
          'SELECT n.id AS id, n.local_uuid AS night_uuid, '
          'b.local_uuid AS booking_uuid '
          'FROM booking_nights n '
          'JOIN bookings b ON b.id = n.booking_local_id '
          "WHERE (n.booking_uuid_cache IS NULL OR n.booking_uuid_cache = '') "
          'AND n.deleted_at IS NULL '
          "AND b.local_uuid IS NOT NULL AND b.local_uuid <> '' "
          'ORDER BY n.id LIMIT ?',
          variables: [d.Variable<int>(batchSize + 1)],
          readsFrom: {db.bookingNights, db.bookings},
        )
        .get();
    if (rows.isEmpty) return (queued: 0, done: true);

    final batch = rows.length > batchSize ? rows.sublist(0, batchSize) : rows;
    final clientTs = Time.nowEpoch();
    await db.transaction(() async {
      for (final row in batch) {
        await (db.update(
          db.bookingNights,
        )..where((n) => n.id.equals(row.read<int>('id')))).write(
          BookingNightsCompanion(
            bookingUuidCache: d.Value(row.read<String>('booking_uuid')),
          ),
        );
      }
      await OutboxDao(db).mergeBatch([
        for (final row in batch)
          _outboxItem(
            'booking_nights',
            row.read<String>('night_uuid'),
            clientTs,
          ),
      ]);
    });
    return (queued: batch.length, done: rows.length <= batchSize);
  }

  /// Notes have no local UUID column; the push path adds the booking UUID, so
  /// every live note is queued once to replace the remote copies without it.
  Future<int> repushNotesOnce(AppDatabase db) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(notesRepushPrefKey) ?? false) return 0;

    final rows = await db
        .customSelect(
          'SELECT n.local_uuid AS note_uuid FROM booking_notes n '
          'JOIN bookings b ON b.id = n.booking_id '
          'WHERE n.deleted_at IS NULL '
          "AND b.local_uuid IS NOT NULL AND b.local_uuid <> ''",
          readsFrom: {db.bookingNotes, db.bookings},
        )
        .get();

    final outboxDao = OutboxDao(db);
    final clientTs = Time.nowEpoch();
    for (var i = 0; i < rows.length; i += _notesChunkSize) {
      final chunk = rows.sublist(
        i,
        i + _notesChunkSize < rows.length ? i + _notesChunkSize : rows.length,
      );
      await outboxDao.mergeBatch([
        for (final row in chunk)
          _outboxItem('booking_notes', row.read<String>('note_uuid'), clientTs),
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
