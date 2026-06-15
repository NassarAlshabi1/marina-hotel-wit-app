import 'package:drift/drift.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../local_db.dart';
import 'outbox_dao.dart';

part 'employees_dao.g.dart';

@DriftAccessor(tables: [Employees])
class EmployeesDao extends DatabaseAccessor<AppDatabase>
    with _$EmployeesDaoMixin {
  EmployeesDao(super.db, this.outboxDao) : adapters = AdapterRegistry(db);
  final OutboxDao outboxDao;
  final AdapterRegistry adapters;

  Future<List<Employee>> list({
    String? search,
    bool includeDeleted = false,
  }) async {
    final q = select(employees);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.name.like(s) | t.status.like(s));
    }
    return q.get();
  }

  Stream<List<Employee>> watchList({
    String? search,
    bool includeDeleted = false,
  }) {
    final q = select(employees);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
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
  Future<Employee?> getByLocalUuid(String localUuid) => (select(
    employees,
  )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  Stream<Employee?> watchByLocalUuid(String localUuid) => (select(
    employees,
  )..where((t) => t.localUuid.equals(localUuid))).watchSingleOrNull();

  Future<int> insertOne(
    EmployeesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
      final comp = data.copyWith(
        localUuid: Value(uu),
        createdAt: Value(now),
        updatedAt: Value(now),
        lastModified: Value(now),
        origin: Value(originIsServer ? 'server' : 'local'),
        deviceId: data.deviceId.present ? data.deviceId : Value(IdGen.deviceIdSync),
      );
      final id = await into(employees).insert(comp);
      if (!originIsServer) {
        await _mergeOutbox(
          op: 'create',
          localUuid: uu,
          serverId: comp.serverId.present ? comp.serverId.value : null,
          clientTs: now,
        );
      }
      return id;
    });
  }

  Future<int> updateById(
    int id,
    EmployeesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified =
          originIsServer && data.lastModified.present
              ? data.lastModified
              : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        employees,
      )..where((t) => t.id.equals(id))).write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> updateByLocalUuid(
    String localUuid,
    EmployeesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getByLocalUuid(localUuid);
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified =
          originIsServer && data.lastModified.present
              ? data.lastModified
              : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        employees,
      )..where((t) => t.localUuid.equals(localUuid))).write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
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
      if (existing == null) {
        return 0;
      }
      final rows = await (update(employees)..where((t) => t.id.equals(id)))
          .write(
            EmployeesCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
              version: Value(existing.version + 1),
            ),
          );
      if (rows > 0 && !originIsServer) {
        // ✅ نستخدم 'update' بدلاً من 'delete' لأن softDelete يحدّث deletedAt
        // ولا يحذف المستند من Appwrite — الجهاز الآخر يحتاج رؤية deletedAt
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> updateByServerId(
    String? serverId,
    EmployeesCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final parsedServerId = _parseServerId(serverId);
      if (parsedServerId == null) {
        return 0;
      }
      final now = Time.nowEpoch();
      final existing = await (select(
        employees,
      )..where((t) => t.serverId.equals(parsedServerId))).getSingleOrNull();
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      final effectiveLastModified =
          originIsServer && data.lastModified.present
              ? data.lastModified
              : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        employees,
      )..where((t) => t.serverId.equals(parsedServerId))).write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
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
    if (parsedServerId == null) {
      return Future.value();
    }
    return (select(
      employees,
    )..where((t) => t.serverId.equals(parsedServerId))).getSingleOrNull();
  }

  int? _parseServerId(String? value) {
    if (value == null) {
      return null;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }

  Future<Map<String, dynamic>?> _payloadForLocalUuid(String localUuid) async {
    final row =
        await (select(employees)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return adapters.employees.toJsonForSource(row, src: Source.appwrite);
  }

  Future<void> _mergeOutbox({
    required String op,
    required String localUuid,
    required int clientTs,
    int? serverId,
  }) async {
    final payload = await _payloadForLocalUuid(localUuid);
    if (payload == null) {
      return;
    }
    await outboxDao.merge(
      entity: 'employees',
      op: op,
      localUuid: localUuid,
      serverId: serverId,
      payload: payload,
      clientTs: clientTs,
    );
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع الموظفين إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final employeesList = await list();
    return employeesList.map((employee) => employee.toJson()).toList();
  }

  /// استيراد الموظفين من JSON
  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    if (clearExisting) {
      await delete(employees).go();
    }

    for (final employeeJson in data) {
      final employee = Employee.fromJson(employeeJson);
      await into(employees).insertOnConflictUpdate(
        EmployeesCompanion(
          name: Value(employee.name),
          basicSalary: Value(employee.basicSalary),
          position: Value(employee.position),
          phone: Value(employee.phone),
          hireDate: Value(employee.hireDate),
          status: Value(employee.status),
          terminationDate: Value(employee.terminationDate),
          terminationReason: Value(employee.terminationReason),
          localUuid: Value(employee.localUuid),
          serverId: Value(employee.serverId),
          createdAt: Value(employee.createdAt),
          updatedAt: Value(employee.updatedAt),
          deletedAt: Value(employee.deletedAt),
          lastModified: Value(employee.lastModified),
          version: Value(employee.version),
          origin: Value(employee.origin),
        ),
      );
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
