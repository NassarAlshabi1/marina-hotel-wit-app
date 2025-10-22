import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/employees_dao.dart';

class EmployeesRepository {
  EmployeesRepository(this.db)
      : outbox = OutboxDao(db),
        dao = EmployeesDao(db, OutboxDao(db));
  final AppDatabase db;
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
  }) {
    final s = salary ?? basicSalary ?? 0.0;
    return dao.insertOne(
      EmployeesCompanion(
        name: d.Value(name),
        basicSalary: d.Value(s),
        position: d.Value(position ?? 'موظف'),
        phone: d.Value(phone ?? ''),
        hireDate: d.Value(hireDate ?? ''),
        status: d.Value(status),
      ),
    );
  }

  Future<int> update(int id, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) => dao.updateById(
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

  Future<int> updateByLocalUuid(String localUuid, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) => dao.updateByLocalUuid(
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

  Future<int> delete(int id) => dao.softDelete(id);
}
