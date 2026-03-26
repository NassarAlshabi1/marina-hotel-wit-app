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

  /// ✅ Resolve employee by local ID, server ID, or UUID
  Future<int?> resolveEmployee(
    dynamic id, {
    required Source src,
  }) async {
    if (id == null) return null;
    
    final int? localId;
    final int? serverId;
    final String? uuid;
    
    if (id is int) {
      localId = id;
      serverId = null;
      uuid = null;
    } else if (id is String) {
      if (int.tryParse(id) != null) {
        localId = int.parse(id);
        serverId = null;
        uuid = null;
      } else {
        localId = null;
        serverId = null;
        uuid = id;
      }
    } else {
      return null;
    }
    
    // Try by UUID first
    if (uuid != null && uuid.isNotEmpty) {
      final row = await (db.select(db.employees)
            ..where((e) => e.localUuid.equals(uuid))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    
    // Try by server ID
    if (serverId != null) {
      final row = await (db.select(db.employees)
            ..where((e) => e.serverId.equals(serverId))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    
    // Try by local ID
    if (localId != null) {
      final row = await (db.select(db.employees)
            ..where((e) => e.id.equals(localId))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    
    return null;
  }

  /// ✅ Resolve expense by local ID, server ID, or UUID
  Future<int?> resolveExpense(
    dynamic id, {
    required Source src,
  }) async {
    if (id == null) return null;
    
    final int? localId;
    final int? serverId;
    final String? uuid;
    
    if (id is int) {
      localId = id;
      serverId = null;
      uuid = null;
    } else if (id is String) {
      if (int.tryParse(id) != null) {
        localId = int.parse(id);
        serverId = null;
        uuid = null;
      } else {
        localId = null;
        serverId = null;
        uuid = id;
      }
    } else {
      return null;
    }
    
    // Try by UUID first
    if (uuid != null && uuid.isNotEmpty) {
      final row = await (db.select(db.expenses)
            ..where((e) => e.localUuid.equals(uuid))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    
    // Try by server ID
    if (serverId != null) {
      final row = await (db.select(db.expenses)
            ..where((e) => e.serverId.equals(serverId))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    
    // Try by local ID
    if (localId != null) {
      final row = await (db.select(db.expenses)
            ..where((e) => e.id.equals(localId))
            ..limit(1))
          .getSingleOrNull();
      if (row != null) return row.id;
    }
    
    return null;
  }
}
