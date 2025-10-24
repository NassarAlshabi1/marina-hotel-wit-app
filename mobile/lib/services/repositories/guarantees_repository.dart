import 'dart:async';

import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/guarantees_dao.dart';
import '../backup_sync_service.dart';

class GuaranteesRepository {
  GuaranteesRepository(this.db, {BackupSyncService? backupSyncService})
      : dao = GuaranteesDao(db),
        _backupSyncService = backupSyncService;
  final AppDatabase db;
  final GuaranteesDao dao;
  final BackupSyncService? _backupSyncService;

  void _scheduleAutoBackup() {
    unawaited(_backupSyncService?.triggerAutoBackup());
  }

  Stream<List<Guarantee>> watchByDebt(int debtLocalId) => dao.watchList(debtLocalId: debtLocalId);
  Stream<List<Guarantee>> watchByBooking(int bookingLocalId) => dao.watchList(bookingLocalId: bookingLocalId);

  Future<List<Guarantee>> listByDebt(int debtLocalId, {bool onlyUnreturned = false}) => dao.list(debtLocalId: debtLocalId, onlyUnreturned: onlyUnreturned);
  Future<List<Guarantee>> listByBooking(int bookingLocalId, {bool onlyUnreturned = false}) => dao.list(bookingLocalId: bookingLocalId, onlyUnreturned: onlyUnreturned);

  Future<int> create({int? bookingLocalId, int? debtLocalId, String? bookingRef, required String guestName, required String itemType, bool isReturned = false, String? dateReturned}) async {
    final id = await dao.insertOne(
      GuaranteesCompanion(
        bookingLocalId: d.Value(bookingLocalId),
        debtLocalId: d.Value(debtLocalId),
        bookingRef: d.Value(bookingRef),
        guestName: d.Value(guestName),
        itemType: d.Value(itemType),
        isReturned: d.Value(isReturned),
        dateReturned: d.Value(dateReturned),
      ),
    );
    _scheduleAutoBackup();
    return id;
  }

  Future<int> update(int id, {bool? isReturned, String? dateReturned}) async {
    final rows = await dao.updateById(
      id,
      GuaranteesCompanion(
        isReturned: isReturned != null ? d.Value(isReturned) : const d.Value.absent(),
        dateReturned: dateReturned != null ? d.Value(dateReturned) : const d.Value.absent(),
      ),
    );
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  Future<int> markAllReturnedForDebt(int debtLocalId, {String? dateReturnedIso}) async {
    final rows = await dao.markAllReturnedForDebt(debtLocalId, dateReturnedIso: dateReturnedIso);
    if (rows > 0) {
      _scheduleAutoBackup();
    }
    return rows;
  }

  Future<Map<int, int>> unreturnedCountsByDebt() => dao.unreturnedCountsByDebt();
}
