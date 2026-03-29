// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'employees_dao.dart';

// ignore_for_file: type=lint
mixin _$EmployeesDaoMixin on DatabaseAccessor<AppDatabase> {
  $EmployeesTable get employees => attachedDatabase.employees;
  EmployeesDaoManager get managers => EmployeesDaoManager(this);
}

class EmployeesDaoManager {
  final _$EmployeesDaoMixin _db;
  EmployeesDaoManager(this._db);
  $$EmployeesTableTableManager get employees =>
      $$EmployeesTableTableManager(_db.attachedDatabase, _db.employees);
}
