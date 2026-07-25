import 'package:drift/drift.dart' as d;

import '../crashlytics_service.dart';
import '../daos/cash_transactions_dao.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';

class CashRepository {
  CashRepository(this.db) : outbox = OutboxDao(db), dao = CashTransactionsDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final CashTransactionsDao dao;

  Stream<List<CashTransaction>> watchAll() => dao.watchList();
  Stream<CashTransaction?> watchOne(int id) => dao.watchById(id);

  Future<List<CashTransaction>> listByReference({
    required String referenceType,
    required int referenceId,
    bool includeDeleted = false,
  }) => dao.listByReference(referenceType: referenceType, referenceId: referenceId, includeDeleted: includeDeleted);

  Future<int> create({      required String type,
      required double amount,
      required String transactionTime,
      int? registerId,
      String? referenceType,
      int? referenceId,
      String? description,
      int? createdBy,
  }) async {
    try {
      return await dao.insertOne(
        CashTransactionsCompanion(
          registerId: d.Value(registerId),
          transactionType: d.Value(type),
          amount: d.Value(amount),
          referenceType: d.Value(referenceType),
          referenceId: d.Value(referenceId),
          description: d.Value(description),
          transactionTime: d.Value(transactionTime),
          createdBy: d.Value(createdBy),
        ),
      );
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'CashRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {'type': type, 'amount': '$amount'},
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    int? registerId,
    String? type,
    double? amount,
    String? referenceType,
    int? referenceId,
    String? description,
    String? transactionTime,
    int? createdBy,
  }) async {
    try {
      return await dao.updateById(
        id,
        CashTransactionsCompanion(
          // ✅ استخدام Value.absent() بدلاً من Value(null) لمنع مسح الحقول
          registerId: registerId != null ? d.Value(registerId) : const d.Value.absent(),
          transactionType: type != null ? d.Value(type) : const d.Value.absent(),
          amount: amount != null ? d.Value(amount) : const d.Value.absent(),
          referenceType: referenceType != null ? d.Value(referenceType) : const d.Value.absent(),
          referenceId: referenceId != null ? d.Value(referenceId) : const d.Value.absent(),
          description: description != null ? d.Value(description) : const d.Value.absent(),
          transactionTime: transactionTime != null ? d.Value(transactionTime) : const d.Value.absent(),
          createdBy: createdBy != null ? d.Value(createdBy) : const d.Value.absent(),
        ),
      );
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'CashRepository',
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
      return await dao.softDelete(id);
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'CashRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المعاملات النقدية
  Future<Map<String, dynamic>> exportData() async {
    final transactionsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': transactionsData, 'count': recordCount, 'entity': 'cash_transactions'};
  }

  /// استيراد بيانات المعاملات النقدية
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(List<Map<String, dynamic>>.from(data['data'] as List));
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
}
