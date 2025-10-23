import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'rooms_dao.g.dart';

@DriftAccessor(tables: [Rooms])
class RoomsDao extends DatabaseAccessor<AppDatabase> with _$RoomsDaoMixin {
  RoomsDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<Room>> list({String? search, bool includeDeleted = false, int? limit, int? offset}) async {
    final q = select(rooms);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.roomNumber.like(s) | t.type.like(s) | t.status.like(s));
    }
    if (limit != null) q.limit(limit, offset: offset ?? 0);
    return q.get();
  }

  Stream<List<Room>> watchList({String? search, bool includeDeleted = false}) {
    final q = select(rooms);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.roomNumber.like(s) | t.type.like(s) | t.status.like(s));
    }
    return q.watch();
  }

  Future<Room?> getById(int id) => (select(rooms)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Room?> watchById(int id) => (select(rooms)..where((t) => t.id.equals(id))).watchSingleOrNull();
  Future<Room?> getByNumber(String roomNumber) => (select(rooms)..where((t) => t.roomNumber.equals(roomNumber))).getSingleOrNull();
  Stream<Room?> watchByNumber(String roomNumber) => (select(rooms)..where((t) => t.roomNumber.equals(roomNumber))).watchSingleOrNull();

  Future<String> insertOne(RoomsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
    );
    await into(rooms).insert(comp);
    if (!originIsServer) {
      await outboxDao.merge(entity: 'rooms', op: 'create', localUuid: uu, serverId: null, payload: _payloadFromRoom(comp), clientTs: now);
    }
    return comp.roomNumber.value;
  }

  Future<int> updateById(int id, RoomsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(rooms)..where((t) => t.id.equals(id))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'rooms', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFromRoom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> updateByNumber(String roomNumber, RoomsCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getByNumber(roomNumber);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(rooms)..where((t) => t.roomNumber.equals(roomNumber))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'rooms', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFromRoom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> softDelete(String roomNumber, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getByNumber(roomNumber);
    if (existing == null) return 0;
    final rows = await (update(rooms)..where((t) => t.roomNumber.equals(roomNumber))).write(RoomsCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'rooms', op: 'delete', localUuid: existing.localUuid, serverId: existing.serverId, payload: {'room_number': roomNumber}, clientTs: now);
    }
    return rows;
  }

  Map<String, dynamic> _payloadFromRoom(RoomsCompanion comp, {Room? base}) {
    final map = <String, dynamic>{};
    if (comp.roomNumber.present) map['room_number'] = comp.roomNumber.value;
    if (comp.type.present) map['type'] = comp.type.value;
    if (comp.price.present) map['price'] = comp.price.value;
    if (comp.status.present) map['status'] = comp.status.value;
    if (comp.imageUrl.present) map['image_url'] = comp.imageUrl.value;
    return map;
  }
}
