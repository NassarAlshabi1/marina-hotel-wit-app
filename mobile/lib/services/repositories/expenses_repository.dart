import 'dart:async';

import 'package:drift/drift.dart' as d;

import '../../utils/time.dart';
import '../auto_backup_manager.dart';
import '../crashlytics_service.dart';
import '../daos/expenses_dao.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

class ExpensesRepository {
  ExpensesRepository(this.db) {
    outbox = OutboxDao(db);
    dao = ExpensesDao(db, outbox);
  }
  final AppDatabase db;
  late final OutboxDao outbox;
  late final ExpensesDao dao;

  Stream<List<Expense>> watchAll() => dao.watchList();
  Stream<List<Expense>> watchByHotelDayKey(String hotelDayKey) =>
      dao.watchByHotelDayKey(hotelDayKey);
  Stream<Expense?> watchOne(int id) => dao.watchById(id);
  Future<List<Expense>> listFiltered({
    String? from,
    String? to,
    String? expenseType,
  }) => dao.listFiltered(from: from, to: to, expenseType: expenseType);

  Future<int> create({
    required String expenseType,
    int? relatedId,
    required String description,
    required double amount,
    required String date,
  }) async {
    try {
      final normalizedDate = Time.safeIsoToDateString(date);
      final hotelDayKey = normalizedDate.isNotEmpty
          ? normalizedDate
          : Time.hotelDayKey();
      final result = await dao.insertOne(
        ExpensesCompanion(
          expenseType: d.Value(expenseType),
          relatedId: d.Value(relatedId),
          description: d.Value(description),
          amount: d.Value(amount),
          date: d.Value(normalizedDate),
          hotelDayKey: d.Value(hotelDayKey),
        ),
      );
      unawaited(AutoBackupManager.instance.onDataChange(
        'expenses',
        'INSERT',
        recordData: {'amount': amount},
      ),);
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ExpensesRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'expenseType': expenseType, 'amount': '$amount'},
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    String? expenseType,
    int? relatedId,
    String? description,
    double? amount,
    String? date,
  }) async {
    try {
      final normalizedDate = date != null ? Time.safeIsoToDateString(date) : null;
      final result = await dao.updateById(
        id,
        ExpensesCompanion(
          expenseType: expenseType != null
              ? d.Value(expenseType)
              : const d.Value.absent(),
          relatedId: relatedId != null
              ? d.Value(relatedId)
              : const d.Value.absent(),
          description: description != null
              ? d.Value(description)
              : const d.Value.absent(),
          amount: amount != null ? d.Value(amount) : const d.Value.absent(),
          date: normalizedDate != null
              ? d.Value(normalizedDate)
              : const d.Value.absent(),
          hotelDayKey: normalizedDate != null
              ? d.Value(normalizedDate)
              : const d.Value.absent(),
        ),
      );
      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange(
          'expenses',
          'UPDATE',
          recordData: {'id': id},
        ),);
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ExpensesRepository',
        action: 'update',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  Future<int> delete(int id) async {
    try {
      final result = await dao.softDelete(id);
      if (result > 0) {
        unawaited(AutoBackupManager.instance.onDataChange(
          'expenses',
          'DELETE',
          recordData: {'id': id},
        ),);
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'ExpensesRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المصروفات
  Future<Map<String, dynamic>> exportData() async {
    final expensesData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': expensesData, 'count': recordCount, 'entity': 'expenses'};
  }

  /// استيراد بيانات المصروفات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data'] as List),
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return dao.getRecordCount();
  }

  /// الحصول على إجمالي المصروفات لتاريخ محدد
  Future<double> getTotalByDate(String date) async {
    final result = await db.customSelect(
      'SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses WHERE date LIKE ? AND deleted_at IS NULL',
      variables: [d.Variable.withString('$date%')],
      readsFrom: {db.expenses},
    ).getSingle();
    return (result.data['total'] as num).toDouble();
  }

  Future<double> getTotalByHotelDayKey(String hotelDayKey) async {
    final result = await db.customSelect(
      'SELECT COALESCE(SUM(amount), 0.0) AS total FROM expenses '
      'WHERE deleted_at IS NULL AND (hotel_day_key = ? OR (hotel_day_key IS NULL AND date LIKE ?))',
      variables: [d.Variable.withString(hotelDayKey), d.Variable.withString('$hotelDayKey%')],
      readsFrom: {db.expenses},
    ).getSingle();
    return (result.data['total'] as num).toDouble();
  }
}
