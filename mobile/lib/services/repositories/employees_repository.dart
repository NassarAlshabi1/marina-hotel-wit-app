import 'package:drift/drift.dart' as d;
import '../drive_backup_service.dart';
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/employees_dao.dart';

class EmployeesRepository {
  EmployeesRepository(this.db, this.backupService)
      : outbox = OutboxDao(db),
        dao = EmployeesDao(db, OutboxDao(db));
  final AppDatabase db;
  final GoogleDriveBackupService backupService;
  final OutboxDao outbox;
  final EmployeesDao dao;

  Stream<List<Employee>> watchAll({String? search}) => dao.watchList(search: search);
  Stream<Employee?> watchOne(int id) => dao.watchById(id);

  Future<int> create({
    required String name,
    double? basicSalary,
    double? salary,
    String? position,
    String? phone,
    String? hireDate,
    required String status,
  }) async {
    final s = salary ?? basicSalary ?? 0.0;
    final id = await dao.insertOne(
      EmployeesCompanion(
        name: d.Value(name),
        basicSalary: d.Value(s),
        position: d.Value(position ?? 'موظف'),
        phone: d.Value(phone ?? ''),
        hireDate: d.Value(hireDate ?? ''),
        status: d.Value(status),
      ),
    );
    backupService.scheduleAutoBackup('employees-create');
    return id;
  }

  Future<int> update(int id, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) async {
    final affected = await dao.updateById(
      id,
      EmployeesCompanion(
        name: name != null ? d.Value(name) : const d.Value.absent(),
        basicSalary: (salary ?? basicSalary) != null ? d.Value((salary ?? basicSalary)!) : const d.Value.absent(),
        position: position != null ? d.Value(position) : const d.Value.absent(),
        phone: phone != null ? d.Value(phone) : const d.Value.absent(),
        hireDate: hireDate != null ? d.Value(hireDate) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
      ),
    );
    if (affected > 0) {
      backupService.scheduleAutoBackup('employees-update');
    }
    return affected;
  }

  Future<int> updateByLocalUuid(String localUuid, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) async {
    final affected = await dao.updateByLocalUuid(
      localUuid,
      EmployeesCompanion(
        name: name != null ? d.Value(name) : const d.Value.absent(),
        basicSalary: (salary ?? basicSalary) != null ? d.Value((salary ?? basicSalary)!) : const d.Value.absent(),
        position: position != null ? d.Value(position) : const d.Value.absent(),
        phone: phone != null ? d.Value(phone) : const d.Value.absent(),
        hireDate: hireDate != null ? d.Value(hireDate) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
      ),
    );
    if (affected > 0) {
      backupService.scheduleAutoBackup('employees-update');
    }
    return affected;
  }

  Future<int> delete(int id) async {
    final affected = await dao.softDelete(id);
    if (affected > 0) {
      backupService.scheduleAutoBackup('employees-delete');
    }
    return affected;
  }
}
