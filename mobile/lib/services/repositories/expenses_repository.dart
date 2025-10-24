import 'dart:async';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/expenses_dao.dart';
import '../daos/employees_dao.dart';
import '../backup_sync_service.dart';
import '../whatsapp_service.dart';

class ExpensesRepository {
  ExpensesRepository(this.db, {WhatsAppService? whatsAppService, BackupSyncService? backupSyncService})
      : outbox = OutboxDao(db),
        dao = ExpensesDao(db, OutboxDao(db)),
        _employeesDao = EmployeesDao(db, OutboxDao(db)),
        _whatsAppService = whatsAppService ?? WhatsAppService(
          baseUrl: 'https://7103.api.greenapi.com',
          instanceId: 'waInstance7103894450',
          token: 'a8856c55173047d6b2d3078380a16f5f5d088c1e146b4903b1',
        ),
        _backupSyncService = backupSyncService;
  final AppDatabase db;
  final OutboxDao outbox;
  final ExpensesDao dao;
  final EmployeesDao _employeesDao;
  final WhatsAppService _whatsAppService;
  final BackupSyncService? _backupSyncService;

  static const String _salaryWithdrawalType = 'سحب من الراتب';

  void _scheduleAutoBackup() {
    unawaited(_backupSyncService?.triggerAutoBackup());
  }

  Stream<List<Expense>> watchAll() => dao.watchList();
  Stream<Expense?> watchOne(int id) => dao.watchById(id);

  Future<int> create({required String expenseType, int? relatedId, required String description, required double amount, required String date}) async {
    return db.transaction(() async {
      final expenseId = await dao.insertOne(
        ExpensesCompanion(
          expenseType: d.Value(expenseType),
          relatedId: d.Value(relatedId),
          description: d.Value(description),
          amount: d.Value(amount),
          date: d.Value(date),
        ),
      );
      if (_isSalaryWithdrawal(expenseType) && relatedId != null) {
        await _applySalaryDelta(relatedId, -amount);
        await _sendSalaryWithdrawalNotification(
          employeeId: relatedId,
          amount: amount,
          description: description,
          date: date,
        );
      }
      _scheduleAutoBackup();
      return expenseId;
    });
  }

  Future<int> update(int id, {String? expenseType, int? relatedId, String? description, double? amount, String? date}) async {
    return db.transaction(() async {
      final before = await dao.getById(id);
      if (before == null) {
        return 0;
      }
      final rows = await dao.updateById(
        id,
        ExpensesCompanion(
          expenseType: expenseType != null ? d.Value(expenseType) : const d.Value.absent(),
          relatedId: d.Value(relatedId),
          description: description != null ? d.Value(description) : const d.Value.absent(),
          amount: amount != null ? d.Value(amount) : const d.Value.absent(),
          date: date != null ? d.Value(date) : const d.Value.absent(),
        ),
      );
      if (rows > 0) {
        final after = await dao.getById(id);
        if (after != null) {
          await _reconcileSalaryWithdrawal(before, after);
        }
        _scheduleAutoBackup();
      }
      return rows;
    });
  }

  Future<int> delete(int id) async {
    return db.transaction(() async {
      final existing = await dao.getById(id);
      if (existing == null) {
        return 0;
      }
      final rows = await dao.softDelete(id);
      if (rows > 0 && _isSalaryWithdrawal(existing.expenseType) && existing.relatedId != null) {
        await _applySalaryDelta(existing.relatedId!, existing.amount);
        await _sendSalaryWithdrawalNotification(
          employeeId: existing.relatedId!,
          amount: -existing.amount,
          description: existing.description,
          date: existing.date,
        );
      }
      if (rows > 0) {
        _scheduleAutoBackup();
      }
      return rows;
    });
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المصروفات
  Future<Map<String, dynamic>> exportData() async {
    final expensesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();
    
    return {
      'data': expensesData,
      'count': recordCount,
      'entity': 'expenses',
    };
  }

  /// استيراد بيانات المصروفات
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

  bool _isSalaryWithdrawal(String type) => type.trim() == _salaryWithdrawalType;

  Future<void> _applySalaryDelta(int employeeId, double delta) async {
    final employee = await _employeesDao.getById(employeeId);
    if (employee == null) {
      return;
    }
    final updatedSalary = (employee.basicSalary + delta).clamp(0, double.infinity);
    await _employeesDao.updateById(
      employeeId,
      EmployeesCompanion(basicSalary: d.Value(updatedSalary.toDouble())),
    );
  }

  Future<void> _reconcileSalaryWithdrawal(Expense before, Expense after) async {
    if (_isSalaryWithdrawal(before.expenseType) && before.relatedId != null) {
      await _applySalaryDelta(before.relatedId!, before.amount);
    }
    if (_isSalaryWithdrawal(after.expenseType) && after.relatedId != null) {
      await _applySalaryDelta(after.relatedId!, -after.amount);
      await _sendSalaryWithdrawalNotification(
        employeeId: after.relatedId!,
        amount: after.amount,
        description: after.description,
        date: after.date,
      );
    }
  }

  Future<void> _sendSalaryWithdrawalNotification({
    required int employeeId,
    required double amount,
    required String description,
    required String date,
  }) async {
    final employee = await _employeesDao.getById(employeeId);
    if (employee == null) {
      return;
    }
    final phone = employee.phone?.trim() ?? '';
    if (phone.isEmpty) {
      return;
    }
    final message = StringBuffer()
      ..writeln('مرحباً ${employee.name},')
      ..writeln('تم تسجيل خصم من راتبك الأساسي بمبلغ ${amount.abs().toStringAsFixed(2)} ر.س بتاريخ $date.')
      ..writeln('الوصف: ${description.isEmpty ? 'بدون وصف' : description}.')
      ..writeln('الراتب الأساسي الحالي: ${(employee.basicSalary).toStringAsFixed(2)} ر.س.');
    await _whatsAppService.sendMessage(phoneE164: phone.startsWith('+') ? phone : '+$phone', message: message.toString());
  }
}
