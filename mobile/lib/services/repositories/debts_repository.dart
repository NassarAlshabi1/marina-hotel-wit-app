import 'dart:async';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/debts_dao.dart';
import '../daos/bookings_dao.dart';
import '../daos/rooms_dao.dart';
import '../daos/outbox_dao.dart';
import '../repositories/payments_repository.dart';
import '../repositories/guarantees_repository.dart';
import '../backup_sync_service.dart';
import '../../utils/time.dart';

class DebtsRepository {
  DebtsRepository(this.db, {BackupSyncService? backupSyncService})
      : dao = DebtsDao(db),
        _backupSyncService = backupSyncService;

  final AppDatabase db;
  final DebtsDao dao;
  final BackupSyncService? _backupSyncService;

  void _scheduleAutoBackup() {
    unawaited(_backupSyncService?.triggerAutoBackup());
  }

  Stream<List<Debt>> watchAll({bool includeDeleted = false}) => dao.watchList(includeDeleted: includeDeleted);

  Stream<Debt?> watchOne(int id) => dao.watchById(id);

  Future<Debt?> getOne(int id) => dao.getById(id);

  Future<int> create({
    int? bookingLocalId,
    String? bookingRef,
    required String guestName,
    required String checkinDate,
    required String checkoutDate,
    required double totalAmount,
    required double paidAmount,
    required String paymentDate,
    String? pledge,
    String? pledgeType,
    String? note,
    String? debtReason,
    double? amountDue,
    String? dateRecorded,
  }) async {
    final remaining = (totalAmount - paidAmount).clamp(0, double.infinity).toDouble();
    final id = await dao.insertOne(
      DebtsCompanion(
        bookingLocalId: d.Value(bookingLocalId),
        bookingRef: d.Value(bookingRef),
        guestName: d.Value(guestName),
        checkinDate: d.Value(checkinDate),
        checkoutDate: d.Value(checkoutDate),
        totalAmount: d.Value(totalAmount),
        paidAmount: d.Value(paidAmount),
        remainingAmount: d.Value(remaining),
        amountDue: d.Value((amountDue ?? remaining).toDouble()),
        paymentDate: d.Value(paymentDate),
        debtReason: d.Value(debtReason ?? ''),
        dateRecorded: d.Value(dateRecorded ?? paymentDate),
        pledge: d.Value(pledge),
        pledgeType: d.Value(pledgeType),
        note: d.Value(note),
      ),
    );
    _scheduleAutoBackup();
    return id;
  }

  Future<int> update({
    required int id,
    int? bookingLocalId,
    String? bookingRef,
    String? guestName,
    String? checkinDate,
    String? checkoutDate,
    double? totalAmount,
    double? paidAmount,
    double? amountDue,
    String? paymentDate,
    String? pledge,
    String? pledgeType,
    String? note,
    String? debtReason,
    String? dateRecorded,
    String? dateSettled,
    bool? isSettled,
  }) async {
    final existing = await dao.getById(id);
    if (existing == null) {
      return 0;
    }
    final newTotal = totalAmount ?? existing.totalAmount;
    final newPaid = paidAmount ?? existing.paidAmount;
    final remaining = (newTotal - newPaid).clamp(0, double.infinity).toDouble();
    final rows = await dao.updateById(
      id,
      DebtsCompanion(
        bookingLocalId: bookingLocalId != null ? d.Value(bookingLocalId) : const d.Value.absent(),
        bookingRef: bookingRef != null ? d.Value(bookingRef) : const d.Value.absent(),
        guestName: guestName != null ? d.Value(guestName) : const d.Value.absent(),
        checkinDate: checkinDate != null ? d.Value(checkinDate) : const d.Value.absent(),
        checkoutDate: checkoutDate != null ? d.Value(checkoutDate) : const d.Value.absent(),
        totalAmount: totalAmount != null ? d.Value(totalAmount) : const d.Value.absent(),
        paidAmount: paidAmount != null ? d.Value(paidAmount) : const d.Value.absent(),
        remainingAmount: d.Value(remaining),
        amountDue: amountDue != null ? d.Value(amountDue) : const d.Value.absent(),
        paymentDate: paymentDate != null ? d.Value(paymentDate) : const d.Value.absent(),
        pledge: pledge != null ? d.Value(pledge) : const d.Value.absent(),
        pledgeType: pledgeType != null ? d.Value(pledgeType) : const d.Value.absent(),
        note: note != null ? d.Value(note) : const d.Value.absent(),
        debtReason: debtReason != null ? d.Value(debtReason) : const d.Value.absent(),
        dateRecorded: dateRecorded != null ? d.Value(dateRecorded) : const d.Value.absent(),
        dateSettled: dateSettled != null ? d.Value(dateSettled) : const d.Value.absent(),
        isSettled: isSettled != null ? d.Value(isSettled) : const d.Value.absent(),
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

  Future<void> clearAll() async {
    await dao.clearAllData();
    _scheduleAutoBackup();
  }

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
    _scheduleAutoBackup();
  }

  Future<int> processEvasiveGuestDebt({
    required int bookingLocalId,
    required double amountDue,
    required List<String> guaranteeItems,
    String reason = 'Evasive Guest Debt',
  }) async {
    return await db.transaction(() async {
      final bookingsDao = BookingsDao(db, OutboxDao(db));
      final roomsDao = RoomsDao(db, OutboxDao(db));
      final paymentsRepo = PaymentsRepository(db, backupSyncService: _backupSyncService);
      final guaranteesRepo = GuaranteesRepository(db, backupSyncService: _backupSyncService);

      final booking = await bookingsDao.getById(bookingLocalId);
      if (booking == null) {
        throw Exception('Booking not found');
      }

      final nowIso = Time.nowIso();
      final checkin = DateTime.tryParse(booking.checkinDate) ?? DateTime.now();
      final nowDate = DateTime.parse(nowIso);
      final actualNights = Time.nightsWithCutoff(checkin, checkout: nowDate);

      await bookingsDao.updateById(bookingLocalId, BookingsCompanion(
        status: d.Value('هروب'),
        actualCheckout: d.Value(nowIso),
        calculatedNights: d.Value(actualNights),
      ));

      final room = await roomsDao.getByNumber(booking.roomNumber);
      if (room != null) {
        await roomsDao.updateByNumber(booking.roomNumber, RoomsCompanion(status: d.Value('شاغرة')));
      }

      final debtId = await dao.insertOne(DebtsCompanion(
        bookingLocalId: d.Value(booking.id),
        bookingRef: d.Value(booking.serverBookingId?.toString()),
        guestName: d.Value(booking.guestName),
        checkinDate: d.Value(booking.checkinDate),
        checkoutDate: d.Value(booking.checkoutDate ?? nowIso),
        totalAmount: d.Value(amountDue),
        paidAmount: const d.Value(0),
        remainingAmount: d.Value(amountDue),
        amountDue: d.Value(amountDue),
        paymentDate: d.Value(nowIso),
        debtReason: d.Value(reason),
        dateRecorded: d.Value(nowIso),
        isSettled: const d.Value(false),
        note: const d.Value(''),
      ));

      for (final item in guaranteeItems) {
        await guaranteesRepo.create(
          bookingLocalId: booking.id,
          debtLocalId: debtId,
          bookingRef: booking.serverBookingId?.toString(),
          guestName: booking.guestName,
          itemType: item,
          isReturned: false,
        );
      }

      _scheduleAutoBackup();
      return debtId;
    });
  }

  Future<void> settleDebtAndReturnGuarantees({
    required int debtLocalId,
    required String paymentMethod,
    String revenueType = 'debt_settlement',
  }) async {
    await db.transaction(() async {
      final guaranteesRepo = GuaranteesRepository(db, backupSyncService: _backupSyncService);
      final paymentsRepo = PaymentsRepository(db, backupSyncService: _backupSyncService);

      final debt = await dao.getById(debtLocalId);
      if (debt == null) throw Exception('Debt not found');

      final amount = debt.amountDue > 0 ? debt.amountDue : (debt.remainingAmount);
      final nowIso = Time.nowIso();

      final paymentId = await paymentsRepo.create(
        bookingLocalId: debt.bookingLocalId,
        roomNumber: null,
        amount: amount,
        paymentDate: nowIso,
        notes: 'تسوية دين: ${debt.debtReason.isNotEmpty ? debt.debtReason : ''}',
        paymentMethod: paymentMethod,
        revenueType: revenueType,
      );

      if (paymentId <= 0) {
        throw Exception('فشل تسجيل عملية الدفع');
      }

      await dao.updateById(debtLocalId, DebtsCompanion(
        isSettled: const d.Value(true),
        dateSettled: d.Value(nowIso),
        paidAmount: d.Value(debt.paidAmount + amount),
        remainingAmount: const d.Value(0),
        amountDue: const d.Value(0),
      ));

      await guaranteesRepo.markAllReturnedForDebt(debtLocalId, dateReturnedIso: nowIso);
      _scheduleAutoBackup();
    });
  }
}

