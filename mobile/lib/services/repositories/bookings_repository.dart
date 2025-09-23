import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/bookings_dao.dart';

class BookingsRepository {
  BookingsRepository(this.db)
      : outbox = OutboxDao(db),
        dao = BookingsDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final BookingsDao dao;

  Stream<List<Booking>> watch({String? roomNumber, String? status}) => dao.watchList(roomNumber: roomNumber, status: status);
  Stream<Booking?> watchOne(int id) => dao.watchById(id);

  Future<int> create({
    required String roomNumber,
    required String guestName,
    required String guestPhone,
    required String guestNationality,
    String? guestEmail,
    String? guestAddress,
    required String checkinDate,
    String? checkoutDate,
    required String status,
    String? notes,
  }) {
    return dao.insertOne(
      BookingsCompanion(
        roomNumber: d.Value(roomNumber),
        guestName: d.Value(guestName),
        guestPhone: d.Value(guestPhone),
        guestNationality: d.Value(guestNationality),
        guestEmail: d.Value(guestEmail),
        guestAddress: d.Value(guestAddress),
        checkinDate: d.Value(checkinDate),
        checkoutDate: d.Value(checkoutDate),
        status: d.Value(status),
        notes: d.Value(notes),
      ),
    );
  }

  Future<int> update(int id, {
    String? roomNumber,
    String? guestName,
    String? guestPhone,
    String? guestNationality,
    String? guestEmail,
    String? guestAddress,
    String? checkinDate,
    String? checkoutDate,
    String? status,
    String? notes,
  }) {
    return dao.updateById(
      id,
      BookingsCompanion(
        roomNumber: roomNumber != null ? d.Value(roomNumber) : const d.Value.absent(),
        guestName: guestName != null ? d.Value(guestName) : const d.Value.absent(),
        guestPhone: guestPhone != null ? d.Value(guestPhone) : const d.Value.absent(),
        guestNationality: guestNationality != null ? d.Value(guestNationality) : const d.Value.absent(),
        guestEmail: guestEmail != null ? d.Value(guestEmail) : const d.Value.absent(),
        guestAddress: guestAddress != null ? d.Value(guestAddress) : const d.Value.absent(),
        checkinDate: checkinDate != null ? d.Value(checkinDate) : const d.Value.absent(),
        checkoutDate: checkoutDate != null ? d.Value(checkoutDate) : const d.Value.absent(),
        status: status != null ? d.Value(status) : const d.Value.absent(),
        notes: notes != null ? d.Value(notes) : const d.Value.absent(),
      ),
    );
  }

  Future<int> delete(int id) => dao.softDelete(id);
}
