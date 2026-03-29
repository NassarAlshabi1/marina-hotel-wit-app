import '../local_db.dart';
import 'source.dart';

class IdResolver {
  IdResolver(this.db);
  final AppDatabase db;

  Future<int?> resolveBooking({
    int? localId,
    int? serverId,
    String? uuid,
  }) async {
    if (uuid != null && uuid.isNotEmpty) {
      final row =
          await (db.select(db.bookings)
                ..where((b) => b.localUuid.equals(uuid))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) return row.id;
    }
    if (serverId != null) {
      final row =
          await (db.select(db.bookings)
                ..where((b) => b.serverBookingId.equals(serverId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) return row.id;
    }
    if (localId != null) {
      final row =
          await (db.select(db.bookings)
                ..where((b) => b.id.equals(localId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) return row.id;
    }
    return null;
  }

  /// ✅ Resolve employee by local ID, server ID, or UUID
  Future<int?> resolveEmployee(dynamic id, {required Source src}) async {
    if (id == null) return null;

    int? localId;
    String? uuid;

    if (id is int) {
      localId = id;
    } else if (id is String) {
      if (int.tryParse(id) != null) {
        localId = int.parse(id);
      } else {
        uuid = id;
      }
    } else {
      return null;
    }

    // Try by UUID first
    if (uuid != null) {
      final uuidValue = uuid;
      final row =
          await (db.select(db.employees)
                ..where((e) => e.localUuid.equals(uuidValue))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) return row.id;
    }

    // Try by local ID
    if (localId != null) {
      final localIdValue = localId;
      final row =
          await (db.select(db.employees)
                ..where((e) => e.id.equals(localIdValue))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) return row.id;
    }

    return null;
  }

  /// ✅ Resolve expense by local ID, server ID, or UUID
  Future<int?> resolveExpense(dynamic id, {required Source src}) async {
    if (id == null) return null;

    int? localId;
    String? uuid;

    if (id is int) {
      localId = id;
    } else if (id is String) {
      if (int.tryParse(id) != null) {
        localId = int.parse(id);
      } else {
        uuid = id;
      }
    } else {
      return null;
    }

    // Try by UUID first
    if (uuid != null) {
      final uuidValue = uuid;
      final row =
          await (db.select(db.expenses)
                ..where((e) => e.localUuid.equals(uuidValue))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) return row.id;
    }

    // Try by local ID
    if (localId != null) {
      final localIdValue = localId;
      final row =
          await (db.select(db.expenses)
                ..where((e) => e.id.equals(localIdValue))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) return row.id;
    }

    return null;
  }
}
