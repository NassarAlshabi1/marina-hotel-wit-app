import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../auto_backup_manager.dart';
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
  }) async {
    final s = salary ?? basicSalary ?? 0.0;
    final employeeId = await dao.insertOne(
      EmployeesCompanion(
        name: d.Value(name),
        basicSalary: d.Value(s),
        position: d.Value(position ?? 'موظف'),
        phone: d.Value(phone ?? ''),
        hireDate: d.Value(hireDate ?? ''),
        status: d.Value(status),
      ),
    );

    // تسجيل التغيير للنسخ التلقائي
    AutoBackupManager.instance.onDataChange(
      'employees',
      'CREATE',
      recordData: {
        'id': employeeId,
        'name': name,
        'position': position ?? 'موظف',
        'status': status,
      },
    );

    return employeeId;
  }

  Future<int> update(int id, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) async {
    final updatedRows = await dao.updateById(
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

    if (updatedRows > 0) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'employees',
        'UPDATE',
        recordData: {
          'id': id,
          'name': name,
          'position': position,
          'status': status,
        },
      );
    }

    return updatedRows;
  }

  Future<int> updateByLocalUuid(String localUuid, {String? name, double? basicSalary, double? salary, String? position, String? phone, String? hireDate, String? status}) async {
    final updatedRows = await dao.updateByLocalUuid(
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

    if (updatedRows > 0) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'employees',
        'UPDATE',
        recordData: {
          'local_uuid': localUuid,
          'name': name,
          'position': position,
          'status': status,
        },
      );
    }

    return updatedRows;
  }

  Future<int> delete(int id) async {
    // الحصول على بيانات الموظف قبل الحذف
    final employee = await (db.select(db.employees)..where((e) => e.id.equals(id))).getSingleOrNull();
    
    final deletedRows = await dao.softDelete(id);

    if (deletedRows > 0 && employee != null) {
      // تسجيل التغيير للنسخ التلقائي
      AutoBackupManager.instance.onDataChange(
        'employees',
        'DELETE',
        recordData: {
          'id': id,
          'name': employee.name,
          'position': employee.position,
        },
      );
    }

    return deletedRows;
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
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return await dao.getRecordCount();
  }
}
