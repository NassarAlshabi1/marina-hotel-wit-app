// ══════════════════════════════════════════════════════════════════
//  booking_nights_integrity_service.dart — ضمان «لا ليالٍ مكررة»
//
//  المشكلة (تقرير 2026-11-23):
//   1) D1 بلا قيد فريد على هوية الليلة العالمية، فالصفوف تتكرر هناك،
//      ثم تُسحب إلى SQLite وتُدمج/تتضاعف بحسب المفتاح المحلي الجهازي.
//   2) الاستعادة وإعادة البناء كانت تحذف الصفوف حذفاً صلباً وتُعيد
//      إدراجها بمفاتيح جديدة، فتتحول النسخ القديمة على D1 إلى أشباح
//      تعود بالسحب.
//   3) الليالي التي تحمل `booking_uuid_cache` صالحاً بينما
//      `booking_local_id` يشير لحجز آخر تبقى «معلّقة» على الهوية الخطأ.
//
//  هذه الخدمة تُطبّق ثلاث خطوات متكررة (idempotent) على الجهاز:
//   أ) تعبئة `booking_uuid_cache` الناقص من الحجز الأب (بلا تغيير الهوية).
//   ب) طيّ المجموعات المكررة لنفس (هوية الحجز، اليوم) إلى صف واحد حيّ،
//      وإخفاء الباقي بـ deleted_at (حذف ناعم) — لا حذف صلب أبداً.
//   ج) إعادة ربط الصفوف بهوية الحجز المطابقة للـ UUID حين تكون خانة
//      (الحجز، اليوم) فارغة (تفادي كسر UNIQUE المحلي).
//
//  كل إخفاء/إصلاح يُسجَّل في outbox بلقطة صف كاملة (إن طُلب) كي يصل
//  التصحيح إلى D1 وبقية الأجهزة ولا يعود الصف المكرر بالسحب التالي.
// ══════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart' as d;

import '../utils/id.dart';
import '../utils/time.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'sync/booking_night_payload.dart';

/// نتيجة فحص سلامة الليالي على هذا الجهاز.
class BookingNightsAudit {
  const BookingNightsAudit({
    required this.liveRows,
    required this.duplicateGroups,
    required this.duplicateRows,
    required this.mislinkedRows,
    required this.missingBookingUuidCache,
    required this.malformedRows,
  });

  final int liveRows;
  final int duplicateGroups;
  final int duplicateRows;
  final int mislinkedRows;
  final int missingBookingUuidCache;
  final int malformedRows;

  bool get hasDuplicates => duplicateGroups > 0;

  bool get isClean =>
      duplicateGroups == 0 &&
      mislinkedRows == 0 &&
      missingBookingUuidCache == 0 &&
      malformedRows == 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'live_rows': liveRows,
    'duplicate_groups': duplicateGroups,
    'duplicate_rows': duplicateRows,
    'mislinked_rows': mislinkedRows,
    'missing_booking_uuid_cache': missingBookingUuidCache,
    'malformed_rows': malformedRows,
  };

  @override
  String toString() =>
      'BookingNightsAudit(live=$liveRows, dupGroups=$duplicateGroups, '
      'dupRows=$duplicateRows, mislinked=$mislinkedRows, '
      'missingCache=$missingBookingUuidCache, malformed=$malformedRows)';
}

/// ما نفّذته المصالحة فعلاً (كل الأرقام قابلة للتكرار بأمان).
class BookingNightsRepairReport {
  const BookingNightsRepairReport({
    required this.filledUuidCache,
    required this.tombstonedDuplicates,
    required this.relinked,
    required this.conflictsSkipped,
    required this.remainingDuplicateGroups,
  });

  final int filledUuidCache;
  final int tombstonedDuplicates;
  final int relinked;
  final int conflictsSkipped;
  final int remainingDuplicateGroups;

  bool get isClean => remainingDuplicateGroups == 0;

  Map<String, Object?> toJson() => <String, Object?>{
    'filled_uuid_cache': filledUuidCache,
    'tombstoned_duplicates': tombstonedDuplicates,
    'relinked': relinked,
    'conflicts_skipped': conflictsSkipped,
    'remaining_duplicate_groups': remainingDuplicateGroups,
  };

  @override
  String toString() =>
      'BookingNightsRepairReport(filled=$filledUuidCache, '
      'tombstoned=$tombstonedDuplicates, relinked=$relinked, '
      'conflictsSkipped=$conflictsSkipped, '
      'remainingDupGroups=$remainingDuplicateGroups)';
}

class BookingNightsIntegrityService {
  BookingNightsIntegrityService(this.db, [OutboxDao? outboxDao])
    : _outboxDao = outboxDao ?? OutboxDao(db),
      _payload = BookingNightPayloadBuilder(db);

  final AppDatabase db;
  final OutboxDao _outboxDao;
  final BookingNightPayloadBuilder _payload;

  /// فحص قراءة فقط — لا يكتب شيئاً. يُستخدم في الاختبارات وبوابة المزامنة.
  Future<BookingNightsAudit> audit({int? bookingLocalId}) async {
    final where = bookingLocalId == null
        ? ''
        : ' AND n.booking_local_id = ${bookingLocalId.toString()}';

    final liveRows = await _count(
      'SELECT COUNT(*) AS c FROM booking_nights n '
      'WHERE n.deleted_at IS NULL$where',
    );

    final duplicateGroups = await _count(
      'SELECT COUNT(*) AS c FROM ('
      '  SELECT 1 FROM booking_nights n'
      '  WHERE n.deleted_at IS NULL'
      "    AND TRIM(COALESCE(n.booking_uuid_cache, '')) <> ''$where"
      "  GROUP BY lower(replace(trim(n.booking_uuid_cache), '-', '')),"
      '           n.hotel_day_key'
      '  HAVING COUNT(*) > 1'
      ') t',
    );

    final duplicateRows = await _count(
      'SELECT COALESCE(SUM(c - 1), 0) AS c FROM ('
      '  SELECT COUNT(*) AS c FROM booking_nights n'
      '  WHERE n.deleted_at IS NULL'
      "    AND TRIM(COALESCE(n.booking_uuid_cache, '')) <> ''$where"
      "  GROUP BY lower(replace(trim(n.booking_uuid_cache), '-', '')),"
      '           n.hotel_day_key'
      ') t',
    );

    final mislinkedRows = await _count(
      'SELECT COUNT(*) AS c FROM booking_nights n '
      'JOIN bookings b ON lower(replace(trim(b.local_uuid), \'-\', \'\')) = '
      "                   lower(replace(trim(n.booking_uuid_cache), '-', '')) "
      'WHERE n.deleted_at IS NULL '
      "  AND TRIM(COALESCE(n.booking_uuid_cache, '')) <> '' "
      '  AND n.booking_local_id <> b.id$where',
    );

    final missingCache = await _count(
      'SELECT COUNT(*) AS c FROM booking_nights n '
      'JOIN bookings b ON b.id = n.booking_local_id '
      'WHERE n.deleted_at IS NULL '
      "  AND (n.booking_uuid_cache IS NULL OR TRIM(n.booking_uuid_cache) = '')"
      "  AND TRIM(COALESCE(b.local_uuid, '')) <> ''$where",
    );

    final malformed = await _count(
      'SELECT COUNT(*) AS c FROM booking_nights n '
      'WHERE n.deleted_at IS NULL '
      "  AND (TRIM(n.hotel_day_key) = '' OR TRIM(n.night_start) = '')$where",
    );

    return BookingNightsAudit(
      liveRows: liveRows,
      duplicateGroups: duplicateGroups,
      duplicateRows: duplicateRows,
      mislinkedRows: mislinkedRows,
      missingBookingUuidCache: missingCache,
      malformedRows: malformed,
    );
  }

  /// التنفيذ الكامل: تعبئة الهوية → طيّ التكرار → إعادة الربط → طيّ أخير.
  ///
  /// [enqueueOutbox] = true يعني أن كل إصلاح يُرفع إلى D1 (لقطة كاملة)
  /// كي لا يعود الصف المكرر بالسحب التالي. في الإقلاع يُستدعى بعد
  /// BookingChildUuidBackfillService (الذي يتولى الرفع) فيمكن تمرير false.
  Future<BookingNightsRepairReport> ensureNoDuplicates({
    bool enqueueOutbox = true,
    int? bookingLocalId,
  }) async {
    final stamp = Time.nowEpoch();
    final stampIso = DateTime.now().toUtc().toIso8601String();

    var filled = 0;
    var tombstoned = 0;
    var relinked = 0;
    var conflicts = 0;

    await db.transaction(() async {
      filled = await _fillMissingBookingUuidCache(
        stamp: stamp,
        stampIso: stampIso,
        enqueueOutbox: enqueueOutbox,
        bookingLocalId: bookingLocalId,
      );
      tombstoned += await _tombstoneDuplicateGroups(
        stamp: stamp,
        stampIso: stampIso,
        enqueueOutbox: enqueueOutbox,
        bookingLocalId: bookingLocalId,
      );
      final relinkResult = await _relinkFreeSlots(
        stamp: stamp,
        stampIso: stampIso,
        enqueueOutbox: enqueueOutbox,
        bookingLocalId: bookingLocalId,
      );
      relinked = relinkResult.relinked;
      conflicts = relinkResult.conflicts;
      // إعادة ربط قد تُظهر تكراراً جديداً في هوية نفس الحجز — طيّة أخيرة.
      tombstoned += await _tombstoneDuplicateGroups(
        stamp: stamp,
        stampIso: stampIso,
        enqueueOutbox: enqueueOutbox,
        bookingLocalId: bookingLocalId,
      );
    });

    final after = await audit(bookingLocalId: bookingLocalId);
    return BookingNightsRepairReport(
      filledUuidCache: filled,
      tombstonedDuplicates: tombstoned,
      relinked: relinked,
      conflictsSkipped: conflicts,
      remainingDuplicateGroups: after.duplicateGroups,
    );
  }

  // ─── خطوات الإصلاح ────────────────────────────────────────────

  Future<int> _fillMissingBookingUuidCache({
    required int stamp,
    required String stampIso,
    required bool enqueueOutbox,
    required int? bookingLocalId,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT n.id AS id, b.local_uuid AS owner_uuid, '
          '       n.version AS version '
          'FROM booking_nights n '
          'JOIN bookings b ON b.id = n.booking_local_id '
          'WHERE n.deleted_at IS NULL '
          "  AND (n.booking_uuid_cache IS NULL OR TRIM(n.booking_uuid_cache) = '') "
          "  AND TRIM(COALESCE(b.local_uuid, '')) <> ''"
          '${bookingLocalId == null ? '' : ' AND n.booking_local_id = ?'}',
          variables: [
            if (bookingLocalId != null) d.Variable<int>(bookingLocalId),
          ],
          readsFrom: {db.bookingNights, db.bookings},
        )
        .get();

    var changed = 0;
    for (final row in rows) {
      final id = row.read<int>('id');
      final ownerUuid = (row.read<String?>('owner_uuid') ?? '').trim();
      if (ownerUuid.isEmpty) continue;
      await _writeNight(
        id: id,
        version: row.read<int?>('version') ?? 1,
        stamp: stamp,
        stampIso: stampIso,
        enqueueOutbox: enqueueOutbox,
        companion: BookingNightsCompanion(
          bookingUuidCache: d.Value(ownerUuid),
          updatedAt: d.Value(stamp),
          updatedAtIso: d.Value(stampIso),
          lastModified: enqueueOutbox
              ? d.Value(stamp)
              : const d.Value.absent(),
          lastModifiedEpoch: enqueueOutbox
              ? d.Value(stamp)
              : const d.Value.absent(),
        ),
      );
      changed++;
    }
    return changed;
  }

  /// يطوي كل مجموعة مكررة لنفس (هوية الحجز العالمية، اليوم) إلى صف واحد
  /// حيّ. الفائز: الصف ذو المفتاح الحتمي، ثم الأحدث تحديثاً، ثم الأعلى id.
  Future<int> _tombstoneDuplicateGroups({
    required int stamp,
    required String stampIso,
    required bool enqueueOutbox,
    required int? bookingLocalId,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT n.id AS id, n.local_uuid AS local_uuid, '
          '       n.hotel_day_key AS hotel_day_key, '
          '       n.updated_at AS updated_at, '
          "       lower(replace(trim(n.booking_uuid_cache), '-', '')) AS cache_key, "
          '       b.local_uuid AS owner_uuid, b.id AS owner_id, '
          '       n.booking_local_id AS link_id, n.version AS version '
          'FROM booking_nights n '
          'LEFT JOIN bookings b ON '
          "  lower(replace(trim(b.local_uuid), '-', '')) = "
          "  lower(replace(trim(n.booking_uuid_cache), '-', '')) "
          'WHERE n.deleted_at IS NULL '
          "  AND TRIM(COALESCE(n.booking_uuid_cache, '')) <> ''"
          "${bookingLocalId == null ? '' : ' AND n.booking_local_id = ?'}",
          variables: [
            if (bookingLocalId != null) d.Variable<int>(bookingLocalId),
          ],
          readsFrom: {db.bookingNights, db.bookings},
        )
        .get();

    // تجميع في الذاكرة: مفتاح = هوية الحجز المطبّعة + اليوم.
    final groups = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final cacheKey = (row.read<String?>('cache_key') ?? '').trim();
      final day = (row.read<String?>('hotel_day_key') ?? '').trim();
      if (cacheKey.isEmpty) continue;
      final key = '$cacheKey|$day';
      (groups[key] ??= <Map<String, Object?>>[]).add(<String, Object?>{
        'id': row.read<int>('id'),
        'local_uuid': row.read<String?>('local_uuid') ?? '',
        'day': day,
        'updated_at': row.read<int?>('updated_at') ?? 0,
        'version': row.read<int?>('version') ?? 1,
        'owner_uuid': (row.read<String?>('owner_uuid') ?? '').trim(),
        'owner_id': row.read<int?>('owner_id'),
        'link_id': row.read<int?>('link_id'),
      });
    }

    var tombstoned = 0;
    for (final entry in groups.entries) {
      final members = entry.value;
      if (members.length < 2) continue;

      // الفائز أولاً: الصف المرتبط فعلاً بحجز هويته (لا «معلّق» على حجز
      // آخر بسبب تصادم المعرّفات المحلية) — ثم المفتاح الحتمي — ثم الأحدث.
      members.sort((a, b) {
        final aLinked =
            a['owner_id'] != null && a['owner_id'] == a['link_id'];
        final bLinked =
            b['owner_id'] != null && b['owner_id'] == b['link_id'];
        if (aLinked != bLinked) return aLinked ? -1 : 1;
        final aDeterministic = _isDeterministic(a);
        final bDeterministic = _isDeterministic(b);
        if (aDeterministic != bDeterministic) return aDeterministic ? -1 : 1;
        final byTime = (b['updated_at'] as int).compareTo(a['updated_at'] as int);
        if (byTime != 0) return byTime;
        return (b['id'] as int).compareTo(a['id'] as int);
      });

      final winnerId = members.first['id'] as int;
      for (final member in members) {
        final id = member['id'] as int;
        if (id == winnerId) continue;
        final retired = await _retireNight(
          id: id,
          stamp: stamp,
          stampIso: stampIso,
          enqueueOutbox: enqueueOutbox,
        );
        if (retired) tombstoned++;
      }
    }
    return tombstoned;
  }

  /// يعيد ربط الليالي التي يحمل UUIDها حجزاً موجوداً بينما رابطها الرقمي
  /// يشير إلى حجز آخر — **فقط** إذا كانت خانة (الحجز، اليوم) فارغة،
  /// وإلا يُترك الصف للفحص البشري (كسر UNIQUE المحلي ممنوع).
  Future<({int relinked, int conflicts})> _relinkFreeSlots({
    required int stamp,
    required String stampIso,
    required bool enqueueOutbox,
    required int? bookingLocalId,
  }) async {
    final rows = await db
        .customSelect(
          'SELECT n.id AS id, n.hotel_day_key AS hotel_day_key, '
          '       n.booking_local_id AS current_booking_id, '
          '       b.id AS owner_id, b.local_uuid AS owner_uuid, '
          '       n.version AS version '
          'FROM booking_nights n '
          'JOIN bookings b ON '
          "  lower(replace(trim(b.local_uuid), '-', '')) = "
          "  lower(replace(trim(n.booking_uuid_cache), '-', '')) "
          'WHERE n.deleted_at IS NULL '
          "  AND TRIM(COALESCE(n.booking_uuid_cache, '')) <> '' "
          '  AND n.booking_local_id <> b.id'
          '${bookingLocalId == null ? '' : ' AND b.id = ?'}',
          variables: [
            if (bookingLocalId != null) d.Variable<int>(bookingLocalId),
          ],
          readsFrom: {db.bookingNights, db.bookings},
        )
        .get();

    var relinked = 0;
    var conflicts = 0;
    for (final row in rows) {
      final id = row.read<int>('id');
      final day = (row.read<String?>('hotel_day_key') ?? '').trim();
      final ownerId = row.read<int>('owner_id');
      final ownerUuid = (row.read<String?>('owner_uuid') ?? '').trim();

      final occupied = await _count(
        'SELECT COUNT(*) AS c FROM booking_nights '
        'WHERE booking_local_id = ? AND hotel_day_key = ?',
        variables: [
          d.Variable<int>(ownerId),
          d.Variable<String>(day),
        ],
      );
      if (occupied > 0) {
        conflicts++;
        continue;
      }

      await _writeNight(
        id: id,
        version: row.read<int?>('version') ?? 1,
        stamp: stamp,
        stampIso: stampIso,
        enqueueOutbox: enqueueOutbox,
        companion: BookingNightsCompanion(
          bookingLocalId: d.Value(ownerId),
          bookingUuidCache: d.Value(ownerUuid),
          updatedAt: d.Value(stamp),
          updatedAtIso: d.Value(stampIso),
          lastModified: enqueueOutbox
              ? d.Value(stamp)
              : const d.Value.absent(),
          lastModifiedEpoch: enqueueOutbox
              ? d.Value(stamp)
              : const d.Value.absent(),
        ),
      );
      relinked++;
    }
    return (relinked: relinked, conflicts: conflicts);
  }

  // ─── أدوات داخلية ────────────────────────────────────────────

  bool _isDeterministic(Map<String, Object?> member) {
    final ownerUuid = (member['owner_uuid'] as String? ?? '').trim();
    final day = (member['day'] as String? ?? '').trim();
    final localUuid = (member['local_uuid'] as String? ?? '').trim();
    if (ownerUuid.isEmpty || day.isEmpty || localUuid.isEmpty) return false;
    final expected = IdGen.bookingNightUuid(
      bookingUuid: ownerUuid,
      hotelDayKey: day,
    );
    return localUuid.toLowerCase() == expected.toLowerCase();
  }

  Future<void> _writeNight({
    required int id,
    required int version,
    required int stamp,
    required String stampIso,
    required bool enqueueOutbox,
    required BookingNightsCompanion companion,
  }) async {
    await (db.update(db.bookingNights)..where((n) => n.id.equals(id))).write(
      companion.copyWith(version: d.Value(version + 1)),
    );
    if (!enqueueOutbox) return;
    final fresh =
        await (db.select(db.bookingNights)..where((n) => n.id.equals(id)))
            .getSingleOrNull();
    if (fresh == null) return;
    await _payload.enqueue(
      outboxDao: _outboxDao,
      row: fresh,
      op: 'update',
      clientTs: stamp,
    );
  }

  /// «أعلِن الموت ثم أزِل الصف محلياً».
  ///
  /// لا نترك الصف المكرر كشاهد قبر محلي: الفهرس الفريد المحلي
  /// (`booking_nights(booking_local_id, hotel_day_key)` — local_db.dart:518)
  /// يشمل الصفوف المخفية أيضاً، فالشاهد يحجز خانة (حجز، يوم) شرعية
  /// ويمنع إدراج ليلة صحيحة فيها لاحقاً. الإعلان يُرسَل للخادم أولاً
  /// بلقطة كاملة، ثم يُحذف الصف — فالنسخة الشبكية تنتهي ولا تعود بالسحب.
  Future<bool> _retireNight({
    required int id,
    required int stamp,
    required String stampIso,
    required bool enqueueOutbox,
  }) async {
    final row = await (db.select(
      db.bookingNights,
    )..where((n) => n.id.equals(id))).getSingleOrNull();
    if (row == null) return false;
    if (enqueueOutbox) {
      await _payload.enqueue(
        outboxDao: _outboxDao,
        row: row,
        op: 'update',
        clientTs: stamp,
        tombstonedAt: stamp,
        tombstonedAtIso: stampIso,
      );
    }
    await (db.delete(db.bookingNights)..where((n) => n.id.equals(id))).go();
    return true;
  }

  Future<int> _count(
    String sql, {
    List<d.Variable<Object>> variables = const <d.Variable<Object>>[],
  }) async {
    final row = await db
        .customSelect(sql, variables: variables)
        .getSingleOrNull();
    if (row == null) return 0;
    final value = row.data.values.isEmpty ? null : row.data.values.first;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
