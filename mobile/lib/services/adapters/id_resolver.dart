import '../local_db.dart';

class IdResolver {
  IdResolver(this.db);
  final AppDatabase db;

  /// يحوّل UUID إلى الصيغة القياسية (بالشرطات).
  /// إذا كان 32 حرف بدون شرطات، يضيف الشرطات.
  /// إذا كان بالشرطات بالفعل، يُرجعه كما هو.
  static String normalizeUuid(String uuid) {
    final trimmed = uuid.trim();
    if (trimmed.length == 32 && !trimmed.contains('-')) {
      // 32 حرف بدون شرطات → أضف الشرطات: 8-4-4-4-12
      return '${trimmed.substring(0, 8)}-${trimmed.substring(8, 12)}-'
          '${trimmed.substring(12, 16)}-${trimmed.substring(16, 20)}-'
          '${trimmed.substring(20)}';
    }
    return trimmed;
  }

  /// يحوّل UUID إلى الصيغة بدون شرطات (32 حرف متصل).
  static String stripDashes(String uuid) {
    return uuid.replaceAll('-', '');
  }

  Future<int?> resolveBooking({
    int? localId,
    int? serverId,
    String? uuid,
    bool fromRemote = false,
  }) async {
    if (uuid != null && uuid.isNotEmpty) {
      // ✅ إصلاح حرج: محاولة كلا صيغتي UUID (بالشرطات وبدون)
      // المشكلة: بعض السجلات على Appwrite Cloud مخزّنة بـ UUID بدون شرطات
      // (legacy من Google Drive sync أو backup قديم). عند السحب،
      // bookingUuidCache في المدفوعات قد يكون بصيغة مختلفة عن localUuid
      // في الحجوزات المحلية → المطابقة تفشل → المدفوعات تصبح يتيمة.

      // 1) ابحث بالـ UUID كما هو (مطابقة تامة)
      var row =
          await (db.select(db.bookings)
                ..where((b) => b.localUuid.equals(uuid))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }

      // 2) ابحث بالصيغة المقابلة (إذا كان بالشرطات → بدون، والعكس)
      final normalized = normalizeUuid(uuid);
      if (normalized != uuid) {
        row =
            await (db.select(db.bookings)
                  ..where((b) => b.localUuid.equals(normalized))
                  ..limit(1))
                .getSingleOrNull();
        if (row != null) {
          return row.id;
        }
      }

      final stripped = stripDashes(uuid);
      if (stripped != uuid && stripped.length == 32) {
        row =
            await (db.select(db.bookings)
                  ..where((b) => b.localUuid.equals(stripped))
                  ..limit(1))
                .getSingleOrNull();
        if (row != null) {
          return row.id;
        }
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
    // ✅ إصلاح حرج: لا نستخدم localId من جهاز بعيد كـ fallback!
    // المشكلة: bookingLocalId=27 على جهاز A ≠ bookingLocalId=27 على جهاز B
    // (autoIncrement محلي مستقل). استخدام localId من السيرفر يربط الدفعة
    // بحجز خاطئ (حجز آخر له نفس id المحلي لكنه شخص مختلف تماماً).
    //
    // localId يُستخدم فقط للمسار المحلي (fromRemote=false) حيث id محلي صحيح.
    if (localId != null && !fromRemote) {
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
  ///
  /// ✅ إصلاح: يجرّب كلا صيغتي UUID (بالشرطات وبدون) — مثل resolveBooking.
  /// المشكلة: بعض السجلات على Appwrite Cloud مخزّنة بـ UUID بدون شرطات
  /// (legacy). عند السحب، employeeUuid في salary_withdrawals قد يكون بصيغة
  /// مختلفة عن localUuid في الموظفين المحليين → المطابقة تفشل → سجل يتيم.
  Future<int?> resolveEmployee({
    int? localId,
    String? uuid,
    int? serverId,
    int? employeeId,
  }) async {
    // 1. البحث بالـ UUID أولاً (الأكثر دقة للمزامنة)
    if (uuid != null && uuid.isNotEmpty) {
      // 1a) ابحث بالـ UUID كما هو (مطابقة تامة)
      var row =
          await (db.select(db.employees)
                ..where((e) => e.localUuid.equals(uuid))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }

      // 1b) ابحث بالصيغة المقابلة (إذا كان بدون شرطات → أضف شرطات)
      final normalized = normalizeUuid(uuid);
      if (normalized != uuid) {
        row =
            await (db.select(db.employees)
                  ..where((e) => e.localUuid.equals(normalized))
                  ..limit(1))
                .getSingleOrNull();
        if (row != null) {
          return row.id;
        }
      }

      // 1c) ابحث بالصيغة بدون شرطات (إذا كان بالشرطات → أزل الشرطات)
      final stripped = stripDashes(uuid);
      if (stripped != uuid && stripped.length == 32) {
        row =
            await (db.select(db.employees)
                  ..where((e) => e.localUuid.equals(stripped))
                  ..limit(1))
                .getSingleOrNull();
        if (row != null) {
          return row.id;
        }
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
  ///
  /// ✅ إصلاح: يجرّب كلا صيغتي UUID (بالشرطات وبدون) — مثل resolveBooking/resolveEmployee.
  Future<int?> resolveSalaryCycle({int? localId, String? uuid}) async {
    // البحث بالـ UUID أولاً
    if (uuid != null && uuid.isNotEmpty) {
      // 1a) مطابقة تامة
      var row =
          await (db.select(db.salaryCycles)
                ..where((c) => c.localUuid.equals(uuid))
                ..limit(1))
              .getSingleOrNull();
      if (row != null) {
        return row.id;
      }
      // 1b) صيغة بالشرطات
      final normalized = normalizeUuid(uuid);
      if (normalized != uuid) {
        row =
            await (db.select(db.salaryCycles)
                  ..where((c) => c.localUuid.equals(normalized))
                  ..limit(1))
                .getSingleOrNull();
        if (row != null) {
          return row.id;
        }
      }
      // 1c) صيغة بدون شرطات
      final stripped = stripDashes(uuid);
      if (stripped != uuid && stripped.length == 32) {
        row =
            await (db.select(db.salaryCycles)
                  ..where((c) => c.localUuid.equals(stripped))
                  ..limit(1))
                .getSingleOrNull();
        if (row != null) {
          return row.id;
        }
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
