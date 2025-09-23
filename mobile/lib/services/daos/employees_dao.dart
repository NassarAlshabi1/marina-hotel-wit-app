import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'employees_dao.g.dart';

@DriftAccessor(tables: [Employees])
class EmployeesDao extends DatabaseAccessor<AppDatabase> with _$EmployeesDaoMixin {
  EmployeesDao(AppDatabase db, this.outboxDao) : super(db);
  final OutboxDao outboxDao;

  Future<List<Employee>> list({String? search, bool includeDeleted = false}) async {
    final q = select(employees);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.name.like(s) | t.status.like(s));
    }
    return q.get();
  }

  Stream<List<Employee>> watchList({String? search, bool includeDeleted = false}) {
    final q = select(employees);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.name.like(s) | t.status.like(s));
    }
    return q.watch();
  }

  Future<Employee?> getById(int id) => (select(employees)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Employee?> watchById(int id) => (select(employees)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(EmployeesCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
    );
    final id = await into(employees).insert(comp);
    if (!originIsServer) {
      await outboxDao.merge(entity: 'employees', op: 'create', localUuid: uu, serverId: comp.serverId.present ? comp.serverId.value : null, payload: _payloadFrom(comp), clientTs: now);
    }
    return id;
  }

  Future<int> updateById(int id, EmployeesCompanion data, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final comp = data.copyWith(updatedAt: Value(now), lastModified: Value(now));
    final rows = await (update(employees)..where((t) => t.id.equals(id))).write(comp);
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'employees', op: 'update', localUuid: existing.localUuid, serverId: existing.serverId, payload: _payloadFrom(comp, base: existing), clientTs: now);
    }
    return rows;
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    final now = Time.nowEpoch();
    final existing = await getById(id);
    if (existing == null) return 0;
    final rows = await (update(employees)..where((t) => t.id.equals(id))).write(EmployeesCompanion(
      deletedAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
    ));
    if (rows > 0 && !originIsServer) {
      await outboxDao.merge(entity: 'employees', op: 'delete', localUuid: existing.localUuid, serverId: existing.serverId, payload: {'id': id}, clientTs: now);
    }
    return rows;
  }

  Map<String, dynamic> _payloadFrom(EmployeesCompanion comp, {Employee? base}) {
    final m = <String, dynamic>{};
    if (comp.name.present) m['name'] = comp.name.value;
    if (comp.basicSalary.present) m['basic_salary'] = comp.basicSalary.value;
    if (comp.status.present) m['status'] = comp.status.value;
    return m;
  }
}
