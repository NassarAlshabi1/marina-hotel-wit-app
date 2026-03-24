import 'package:drift/drift.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';

part 'guest_info_dao.g.dart';

@DriftAccessor(tables: [GuestInfos])
class GuestInfoDao extends DatabaseAccessor<AppDatabase>
    with _$GuestInfoDaoMixin {
  GuestInfoDao(super.db);

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

  Future<int> insertOne(GuestInfosCompanion data) async {
    final now = Time.nowEpoch();
    final uuid = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final companion = data.copyWith(
      localUuid: Value(uuid),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      createdAtEpoch: Value(now),
      lastModifiedEpoch: Value(now),
      origin: const Value('local'),
    );
    return into(guestInfos).insert(companion);
  }

  Future<int> updateById(int id, GuestInfosCompanion data) async {
    final existing = await getById(id);
    if (existing == null) {
      return 0;
    }
    final now = Time.nowEpoch();
    final companion = data.copyWith(
      updatedAt: Value(now),
      lastModified: Value(now),
      lastModifiedEpoch: Value(now),
      version: Value(existing.version + 1),
    );
    return (update(
      guestInfos,
    )..where((tbl) => tbl.id.equals(id)))
        .write(companion);
  }

  Future<int> softDelete(int id) async {
    final existing = await getById(id);
    if (existing == null) {
      return 0;
    }
    final now = Time.nowEpoch();
    return (update(guestInfos)..where((tbl) => tbl.id.equals(id))).write(
      GuestInfosCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
        lastModifiedEpoch: Value(now),
        version: Value(existing.version + 1),
      ),
    );
  }

  Future<int> hardDelete(int id) async {
    return (delete(guestInfos)..where((tbl) => tbl.id.equals(id))).go();
  }

  Future<void> clearAllData() => delete(guestInfos).go();
}
