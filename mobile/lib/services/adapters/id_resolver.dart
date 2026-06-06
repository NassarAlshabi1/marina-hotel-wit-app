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
      final row =
          await (db.select(db.bookings)
                ..where((b) => b.localUuid.equals(uuid))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    if (serverId != null) {
      final row =
          await (db.select(db.bookings)
                ..where((b) => b.serverBookingId.equals(serverId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    if (localId != null) {
      final row =
          await (db.select(db.bookings)
                ..where((b) => b.id.equals(localId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    return null;
  }

  /// حل مرجع الموظف - التحقق من وجود الموظف محلياً
  /// يُستخدم في salary_withdrawals و salary_cycles للتحقق من FK
  Future<int?> resolveEmployee({
    int? localId,
    String? uuid,
    int? serverId,
    int? employeeId,
  }) async {
    // 1. البحث بالـ UUID أولاً (الأكثر دقة للمزامنة)
    if (uuid != null && uuid.isNotEmpty) {
      final row =
          await (db.select(db.employees)
                ..where((e) => e.localUuid.equals(uuid))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    // 2. البحث بالـ id المحلي
    if (localId != null) {
      final row =
          await (db.select(db.employees)
                ..where((e) => e.id.equals(localId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    // 3. البحث بالـ serverId (المعرف الأصلي من السيرفر)
    if (serverId != null) {
      final row =
          await (db.select(db.employees)
                ..where((e) => e.serverId.equals(serverId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    // 4. البحث بالـ employeeId (كخيار أخير للتوافق)
    if (employeeId != null) {
      final row =
          await (db.select(db.employees)
                ..where((e) => e.id.equals(employeeId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    return null;
  }

  /// حل مرجع دورة الراتب - التحقق من وجود الدورة محلياً
  /// يُستخدم في salary_payments للتحقق من FK
  Future<int?> resolveSalaryCycle({
    int? localId,
    String? uuid,
  }) async {
    // البحث بالـ UUID أولاً
    if (uuid != null && uuid.isNotEmpty) {
      final row =
          await (db.select(db.salaryCycles)
                ..where((c) => c.localUuid.equals(uuid))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    // البحث بالـ id المحلي
    if (localId != null) {
      final row =
          await (db.select(db.salaryCycles)
                ..where((c) => c.id.equals(localId))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
    }
    return null;
  }
}
