import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/debts_dao.dart';
import '../daos/outbox_dao.dart';

class DebtsRepository {
  DebtsRepository(this.db) : dao = DebtsDao(db, OutboxDao(db));

  final AppDatabase db;
  final DebtsDao dao;

  Stream<List<Debt>> watchAll({bool includeDeleted = false}) => dao.watchList(includeDeleted: includeDeleted);

  Stream<Debt?> watchOne(int id) => dao.watchById(id);

  Future<Debt?> getOne(int id) => dao.getById(id);

  Future<int> create({
    int? bookingLocalId,
    required String guestName,
    required String checkinDate,
    required String checkoutDate,
    String? dateRecorded,
    String? debtReason,
    required double totalAmount,
    required double paidAmount,
    required String paymentDate,
    bool? isSettled,
    String? pledge,
    String? pledgeType,
    String? note,
  }) {
    final remaining = (totalAmount - paidAmount).clamp(0, double.infinity).toDouble();
    final settled = isSettled ?? (remaining <= 0 ? true : false);
    return dao.insertOne(
      DebtsCompanion(
        bookingLocalId: d.Value(bookingLocalId),
        guestName: d.Value(guestName),
        checkinDate: d.Value(checkinDate),
        checkoutDate: d.Value(checkoutDate),
        dateRecorded: d.Value(dateRecorded ?? checkinDate),
        debtReason: d.Value(debtReason ?? ''),
        totalAmount: d.Value(totalAmount),
        paidAmount: d.Value(paidAmount),
        remainingAmount: d.Value(remaining),
        paymentDate: d.Value(paymentDate),
        isSettled: d.Value(settled ? 1 : 0),
        pledge: d.Value(pledge),
        pledgeType: d.Value(pledgeType),
        note: d.Value(note),
      ),
    );
  }

  Future<int> update({
    required int id,
    int? bookingLocalId,
    String? guestName,
    String? checkinDate,
    String? checkoutDate,
    String? dateRecorded,
    String? debtReason,
    double? totalAmount,
    double? paidAmount,
    double? remainingAmount,
    String? paymentDate,
    int? isSettled,
    String? pledge,
    String? pledgeType,
    String? note,
  }) async {
    final existing = await dao.getById(id);
    if (existing == null) {
      return 0;
    }
    final newTotal = totalAmount ?? existing.totalAmount;
    final newPaid = paidAmount ?? existing.paidAmount;
    final remaining = remainingAmount ?? (newTotal - newPaid).clamp(0, double.infinity).toDouble();
    return dao.updateById(
      id,
      DebtsCompanion(
        bookingLocalId: bookingLocalId != null ? d.Value(bookingLocalId) : const d.Value.absent(),
        guestName: guestName != null ? d.Value(guestName) : const d.Value.absent(),
        checkinDate: checkinDate != null ? d.Value(checkinDate) : const d.Value.absent(),
        checkoutDate: checkoutDate != null ? d.Value(checkoutDate) : const d.Value.absent(),
        dateRecorded: dateRecorded != null ? d.Value(dateRecorded) : const d.Value.absent(),
        debtReason: debtReason != null ? d.Value(debtReason) : const d.Value.absent(),
        totalAmount: totalAmount != null ? d.Value(totalAmount) : const d.Value.absent(),
        paidAmount: paidAmount != null ? d.Value(paidAmount) : const d.Value.absent(),
        remainingAmount: d.Value(remaining),
        paymentDate: paymentDate != null ? d.Value(paymentDate) : const d.Value.absent(),
        isSettled: isSettled != null ? d.Value(isSettled) : const d.Value.absent(),
        pledge: pledge != null ? d.Value(pledge) : const d.Value.absent(),
        pledgeType: pledgeType != null ? d.Value(pledgeType) : const d.Value.absent(),
        note: note != null ? d.Value(note) : const d.Value.absent(),
      ),
    );
  }

  Future<int> delete(int id) => dao.softDelete(id);

  Future<void> clearAll() => dao.clearAllData();

  Future<Map<String, dynamic>> exportData({bool includeDeleted = false}) async {
    final data = await dao.exportToJson(includeDeleted: includeDeleted);
    final count = await dao.getRecordCount();
    return {
      'entity': 'debts',
      'count': count,
      'data': data,
    };
  }

  Future<void> importData(Map<String, dynamic> payload) async {
    if (!payload.containsKey('data')) {
      return;
    }
    final list = List<Map<String, dynamic>>.from(payload['data'] as List);
    await dao.importFromJson(list, clearExisting: false);
  }
}
