import '../local_db.dart';

class IdResolver {
  IdResolver(this.db);
  final AppDatabase db;

  Future<int?> resolveBooking({
    int? localId,
    int? serverId,
    String? uuid,
  }) async {
    if (uuid != null && uuid.isNotEmpty) {
      final row = await (db.select(db.bookings)
            ..where((b) => b.localUuid.equals(uuid))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    if (serverId != null) {
      final row = await (db.select(db.bookings)
            ..where((b) => b.serverBookingId.equals(serverId))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    if (localId != null) {
      final row = await (db.select(db.bookings)
            ..where((b) => b.id.equals(localId))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    return null;
  }
}
