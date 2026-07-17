import 'dart:convert';
import 'package:drift/drift.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import '../sync_guardian.dart';
import 'outbox_dao.dart';

part 'guest_info_dao.g.dart';

@DriftAccessor(tables: [GuestInfos])
class GuestInfoDao extends DatabaseAccessor<AppDatabase>
    with _$GuestInfoDaoMixin {
  GuestInfoDao(super.db, this.outboxDao);
  final OutboxDao outboxDao;

  Future<List<GuestInfo>> list({String? search, bool includeDeleted = false}) {
    final query = select(guestInfos);
    if (!includeDeleted) {
      query.where((tbl) => tbl.deletedAt.isNull());
    }
    if (search != null && search.trim().isNotEmpty) {
      final pattern = '%${search.trim()}%';
      query.where(
        (tbl) =>
            tbl.roomNumber.like(pattern) |
            tbl.guestName.like(pattern) |
            tbl.nationality.like(pattern) |
            tbl.idNumber.like(pattern) |
            tbl.governorate.like(pattern),
      );
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]);
    return query.get();
  }

  Stream<List<GuestInfo>> watchList({
    String? search,
    bool includeDeleted = false,
  }) {
    final query = select(guestInfos);
    if (!includeDeleted) {
      query.where((tbl) => tbl.deletedAt.isNull());
    }
    if (search != null && search.trim().isNotEmpty) {
      final pattern = '%${search.trim()}%';
      query.where(
        (tbl) =>
            tbl.roomNumber.like(pattern) |
            tbl.guestName.like(pattern) |
            tbl.nationality.like(pattern) |
            tbl.idNumber.like(pattern) |
            tbl.governorate.like(pattern),
      );
    }
    query.orderBy([(tbl) => OrderingTerm.desc(tbl.updatedAt)]);
    return query.watch();
  }

  Future<GuestInfo?> getById(int id) =>
      (select(guestInfos)..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<int> insertOne(
    GuestInfosCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final uuid =
          data.localUuid.present ? data.localUuid.value : IdGen.uuid();
      final companion = data.copyWith(
        localUuid: Value(uuid),
        createdAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
        createdAtEpoch: Value(now),
        lastModifiedEpoch: Value(now),
        origin: Value(originIsServer ? 'server' : 'local'),
      );
      final id = await into(guestInfos).insert(companion);
      if (!originIsServer) {
        await outboxDao.merge(
          entity: 'guest_infos',
          op: 'create',
          localUuid: uuid,
          serverId: null,
          payload: _payloadFromCompanion(companion),
          clientTs: now,
        );
        await SyncGuardian.instance.notifyLocalChange(
          table: 'guest_infos',
          operation: 'create',
        );
      }
      return id;
    });
  }

  Future<int> updateById(
    int id,
    GuestInfosCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) return 0;
      final now = Time.nowEpoch();
      final companion = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
        lastModifiedEpoch: Value(now),
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        guestInfos,
      )..where((tbl) => tbl.id.equals(id))).write(companion);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'guest_infos',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: _payloadFromCompanion(companion),
          clientTs: now,
        );
        await SyncGuardian.instance.notifyLocalChange(
          table: 'guest_infos',
          operation: 'update',
        );
      }
      return rows;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) return 0;
      final now = Time.nowEpoch();
      final rows = await (update(guestInfos)..where((tbl) => tbl.id.equals(id)))
          .write(
            GuestInfosCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
              lastModifiedEpoch: Value(now),
              version: Value(existing.version + 1),
            ),
          );
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'guest_infos',
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'localUuid': existing.localUuid},
          clientTs: now,
        );
        await SyncGuardian.instance.notifyLocalChange(
          table: 'guest_infos',
          operation: 'delete',
        );
      }
      return rows;
    });
  }

  Future<int> hardDelete(int id) async {
    return (delete(guestInfos)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> clearAllData() => delete(guestInfos).go();

  /// تحويل Companion إلى payload للـ outbox
  Map<String, dynamic> _payloadFromCompanion(GuestInfosCompanion comp) {
    final map = <String, dynamic>{};
    if (comp.roomNumber.present) map['roomNumber'] = comp.roomNumber.value;
    if (comp.guestName.present) map['guestName'] = comp.guestName.value;
    if (comp.nationality.present) map['nationality'] = comp.nationality.value;
    if (comp.idNumber.present) map['idNumber'] = comp.idNumber.value;
    if (comp.idType.present) map['idType'] = comp.idType.value;
    if (comp.issueDate.present) map['issueDate'] = comp.issueDate.value;
    if (comp.issuePlace.present) map['issuePlace'] = comp.issuePlace.value;
    if (comp.governorate.present) map['governorate'] = comp.governorate.value;
    if (comp.notes.present) map['notes'] = comp.notes.value;
    if (comp.localUuid.present) map['localUuid'] = comp.localUuid.value;
    if (comp.serverId.present) map['serverId'] = comp.serverId.value;
    if (comp.createdAt.present) map['createdAt'] = comp.createdAt.value;
    if (comp.updatedAt.present) map['updatedAt'] = comp.updatedAt.value;
    if (comp.deletedAt.present) map['deletedAt'] = comp.deletedAt.value;
    if (comp.lastModified.present) map['lastModified'] = comp.lastModified.value;
    if (comp.version.present) map['version'] = comp.version.value;
    if (comp.origin.present) map['origin'] = comp.origin.value;
    if (comp.vectorClock.present) {
      final vc = comp.vectorClock.value;
      map['vectorClock'] = vc is String ? vc : jsonEncode(vc);
    }
    return map;
  }
}
