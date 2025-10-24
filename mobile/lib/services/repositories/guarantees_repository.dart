import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/guarantees_dao.dart';

class GuaranteesRepository {
  GuaranteesRepository(this.db) : dao = GuaranteesDao(db);
  final AppDatabase db;
  final GuaranteesDao dao;

  Stream<List<Guarantee>> watchByDebt(int debtLocalId) => dao.watchList(debtLocalId: debtLocalId);
  Stream<List<Guarantee>> watchByBooking(int bookingLocalId) => dao.watchList(bookingLocalId: bookingLocalId);

  Future<List<Guarantee>> listByDebt(int debtLocalId, {bool onlyUnreturned = false}) => dao.list(debtLocalId: debtLocalId, onlyUnreturned: onlyUnreturned);
  Future<List<Guarantee>> listByBooking(int bookingLocalId, {bool onlyUnreturned = false}) => dao.list(bookingLocalId: bookingLocalId, onlyUnreturned: onlyUnreturned);

  Future<int> create({int? bookingLocalId, int? debtLocalId, String? bookingRef, required String guestName, required String itemType, bool isReturned = false, String? dateReturned}) {
    return dao.insertOne(
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
  }

  Future<int> update(int id, {bool? isReturned, String? dateReturned}) {
    return dao.updateById(
      id,
      GuaranteesCompanion(
        isReturned: isReturned != null ? d.Value(isReturned) : const d.Value.absent(),
        dateReturned: dateReturned != null ? d.Value(dateReturned) : const d.Value.absent(),
      ),
    );
  }

  Future<int> markAllReturnedForDebt(int debtLocalId, {String? dateReturnedIso}) => dao.markAllReturnedForDebt(debtLocalId, dateReturnedIso: dateReturnedIso);

  Future<Map<int, int>> unreturnedCountsByDebt() => dao.unreturnedCountsByDebt();
}
