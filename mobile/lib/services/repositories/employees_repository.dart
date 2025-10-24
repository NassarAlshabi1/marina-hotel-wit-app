import 'dart:async';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/employees_dao.dart';
import '../backup_sync_service.dart';

class EmployeesRepository {
  EmployeesRepository(this.db, {BackupSyncService? backupSyncService})
      : outbox = OutboxDao(db),
        dao = EmployeesDao(db, OutboxDao(db)),
        _backupSyncService = backupSyncService;
  final AppDatabase db;
  final OutboxDao outbox;
  final EmployeesDao dao;
  final BackupSyncService? _backupSyncService;

  void _scheduleAutoBackup() {
    unawaited(_backupSyncService?.triggerAutoBackup());
  }

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
    _scheduleAutoBackup();
    return id;
  }

  Future<int> update(int id, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) async {
    final rows = await dao.updateById(
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
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  Future<int> updateByLocalUuid(String localUuid, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) async {
    final rows = await dao.updateByLocalUuid(
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
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  Future<int> delete(int id) async {
    final rows = await dao.softDelete(id);
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات الموظفين
  Future<Map<String, dynamic>> exportData() async {
    final employeesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();
    
    return {
      'data': employeesData,
      'count': recordCount,
      'entity': 'employees',
    };
  }

  /// استيراد بيانات الموظفين
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data']), 
        clearExisting: false,
      );
      _scheduleAutoBackup();
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
    _scheduleAutoBackup();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return await dao.getRecordCount();
  }
}
