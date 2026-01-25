import 'package:drift/drift.dart';
import '../../utils/id.dart';
import '../../utils/time.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'employees_dao.g.dart';

@DriftAccessor(tables: [Employees])
class EmployeesDao extends DatabaseAccessor<AppDatabase>
    with _$EmployeesDaoMixin {
  EmployeesDao(super.db, this.outboxDao);
  final OutboxDao outboxDao;

  Future<List<Employee>> list(
      {String? search, bool includeDeleted = false}) async {
    final q = select(employees);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.name.like(s) | t.status.like(s));
    }
    return q.get();
  }

  Stream<List<Employee>> watchList(
      {String? search, bool includeDeleted = false}) {
    final q = select(employees);
    if (!includeDeleted) q.where((t) => t.deletedAt.isNull());
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.name.like(s) | t.status.like(s));
    }
    return q.watch();
  }

  Future<Employee?> getById(int id) =>
      (select(employees)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Employee?> watchById(int id) =>
      (select(employees)..where((t) => t.id.equals(id))).watchSingleOrNull();
  Future<Employee?> getByLocalUuid(String localUuid) =>
      (select(employees)..where((t) => t.localUuid.equals(localUuid)))
          .getSingleOrNull();
  Stream<Employee?> watchByLocalUuid(String localUuid) =>
      (select(employees)..where((t) => t.localUuid.equals(localUuid)))
          .watchSingleOrNull();

  Future<int> insertOne(EmployeesCompanion data,
      {bool originIsServer = false}) async {
    return db.transaction(() async {
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
        await outboxDao.merge(
          entity: 'employees',
          op: 'create',
          localUuid: uu,
          serverId: comp.serverId.present ? comp.serverId.value : null,
          payload: _payloadFrom(comp),
          clientTs: now,
        );
      }
      return id;
    });
  }

  Future<int> updateById(int id, EmployeesCompanion data,
      {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
        version: Value(existing.version + 1),
      );
      final rows =
          await (update(employees)..where((t) => t.id.equals(id))).write(comp);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'employees',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: _payloadFrom(comp, base: existing),
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> updateByLocalUuid(String localUuid, EmployeesCompanion data,
      {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getByLocalUuid(localUuid);
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
        version: Value(existing.version + 1),
      );
      final rows = await (update(employees)
            ..where((t) => t.localUuid.equals(localUuid)))
          .write(comp);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'employees',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: _payloadFrom(comp, base: existing),
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) return 0;
      final rows = await (update(employees)..where((t) => t.id.equals(id)))
          .write(EmployeesCompanion(
        deletedAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
      ));
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'employees',
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: {'id': id},
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> updateByServerId(String? serverId, EmployeesCompanion data,
      {bool originIsServer = false}) async {
    return db.transaction(() async {
      final parsedServerId = _parseServerId(serverId);
      if (parsedServerId == null) return 0;
      final now = Time.nowEpoch();
      final existing = await (select(employees)
            ..where((t) => t.serverId.equals(parsedServerId)))
          .getSingleOrNull();
      if (existing == null) return 0;
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: Value(now),
        version: Value(existing.version + 1),
      );
      final rows = await (update(employees)
            ..where((t) => t.serverId.equals(parsedServerId)))
          .write(comp);
      if (rows > 0 && !originIsServer) {
        await outboxDao.merge(
          entity: 'employees',
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          payload: _payloadFrom(comp, base: existing),
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> hardDelete(int id) async {
    return (delete(employees)..where((t) => t.id.equals(id))).go();
  }

  Future<Employee?> getByServerId(String serverId) {
    final parsedServerId = _parseServerId(serverId);
    if (parsedServerId == null) return Future.value(null);
    return (select(employees)..where((t) => t.serverId.equals(parsedServerId)))
        .getSingleOrNull();
  }

  int? _parseServerId(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return int.tryParse(trimmed);
  }

  Map<String, dynamic> _payloadFrom(EmployeesCompanion comp, {Employee? base}) {
    final m = <String, dynamic>{};

    if (comp.name.present) {
      m['name'] = comp.name.value;
    } else if (base != null) {
      m['name'] = base.name;
    }

    if (comp.basicSalary.present) {
      m['basic_salary'] = comp.basicSalary.value;
    } else if (base != null) {
      m['basic_salary'] = base.basicSalary;
    }

    if (comp.position.present) {
      m['position'] = comp.position.value;
    } else if (base != null) {
      m['position'] = base.position;
    }

    if (comp.phone.present) {
      m['phone'] = comp.phone.value;
    } else if (base != null) {
      m['phone'] = base.phone;
    }

    if (comp.hireDate.present) {
      m['hire_date'] = comp.hireDate.value;
    } else if (base != null) {
      m['hire_date'] = base.hireDate;
    }

    if (comp.status.present) {
      m['status'] = comp.status.value;
    } else if (base != null) {
      m['status'] = base.status;
    }

    if (base != null) {
      m['local_uuid'] = base.localUuid;
      m['server_id'] = base.serverId;
      m['version'] = base.version + 1;
    }

    return m;
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع الموظفين إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final employeesList = await list(includeDeleted: false);
    return employeesList.map((employee) => employee.toJson()).toList();
  }

  /// استيراد الموظفين من JSON
  Future<void> importFromJson(List<Map<String, dynamic>> data,
      {bool clearExisting = false}) async {
    if (clearExisting) {
      await delete(employees).go();
    }

    for (final employeeJson in data) {
      final employee = Employee.fromJson(employeeJson);
      await into(employees).insertOnConflictUpdate(EmployeesCompanion(
        name: Value(employee.name),
        basicSalary: Value(employee.basicSalary),
        position: Value(employee.position),
        phone: Value(employee.phone),
        hireDate: Value(employee.hireDate),
        status: Value(employee.status),
        localUuid: Value(employee.localUuid),
        serverId: Value(employee.serverId),
        createdAt: Value(employee.createdAt),
        updatedAt: Value(employee.updatedAt),
        deletedAt: Value(employee.deletedAt),
        lastModified: Value(employee.lastModified),
        version: Value(employee.version),
        origin: Value(employee.origin),
      ));
    }
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(employees)..addColumns([employees.id.count()]);
    final result = await query.getSingle();
    return result.read(employees.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(employees).go();
  }
}
