import 'package:drift/drift.dart' as d;
import '../local_db.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';

class PaymentsRepository {
  PaymentsRepository(this.db)
      : outbox = OutboxDao(db),
        dao = PaymentsDao(db, OutboxDao(db));
  final AppDatabase db;
  final OutboxDao outbox;
  final PaymentsDao dao;

  Stream<List<Payment>> paymentsByBooking(int bookingLocalId) => dao.watchList(bookingLocalId: bookingLocalId);
  Stream<Payment?> watchOne(int id) => dao.watchById(id);

  Future<int> create({int? bookingLocalId, int? serverBookingId, String? roomNumber, required double amount, required String paymentDate, String? notes, required String paymentMethod, required String revenueType}) => dao.insertOne(
        PaymentsCompanion(
          bookingLocalId: d.Value(bookingLocalId),
          serverBookingId: d.Value(serverBookingId),
          roomNumber: d.Value(roomNumber),
          amount: d.Value(amount),
          paymentDate: d.Value(paymentDate),
          notes: d.Value(notes),
          paymentMethod: d.Value(paymentMethod),
          revenueType: d.Value(revenueType),
        ),
      );

  Future<int> update(int id, {int? bookingLocalId, int? serverBookingId, String? roomNumber, double? amount, String? paymentDate, String? notes, String? paymentMethod, String? revenueType}) => dao.updateById(
        id,
        PaymentsCompanion(
          bookingLocalId: d.Value(bookingLocalId),
          serverBookingId: d.Value(serverBookingId),
          roomNumber: d.Value(roomNumber),
          amount: amount != null ? d.Value(amount) : const d.Value.absent(),
          paymentDate: paymentDate != null ? d.Value(paymentDate) : const d.Value.absent(),
          notes: notes != null ? d.Value(notes) : const d.Value.absent(),
          paymentMethod: paymentMethod != null ? d.Value(paymentMethod) : const d.Value.absent(),
          revenueType: revenueType != null ? d.Value(revenueType) : const d.Value.absent(),
        ),
      );

  Future<int> delete(int id) => dao.softDelete(id);
}
