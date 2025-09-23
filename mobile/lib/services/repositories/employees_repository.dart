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

  Future<int> create({required String name, required double basicSalary, required String status}) =>
      dao.insertOne(EmployeesCompanion(name: d.Value(name), basicSalary: d.Value(basicSalary), status: d.Value(status)));

  Future<int> update(int id, {String? name, double? basicSalary, String? status}) => dao.updateById(
        id,
        EmployeesCompanion(
          name: name != null ? d.Value(name) : const d.Value.absent(),
          basicSalary: basicSalary != null ? d.Value(basicSalary) : const d.Value.absent(),
          status: status != null ? d.Value(status) : const d.Value.absent(),
        ),
      );

  Future<int> delete(int id) => dao.softDelete(id);
}
