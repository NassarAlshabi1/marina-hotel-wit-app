import 'package:drift/drift.dart' as d;

import '../../utils/app_logger.dart';
import '../local_db.dart';

class IdResolver {
  IdResolver(this.db);
  final AppDatabase db;

  // ─────────────────────────────────────────────────────────────────────
  // ✅ Bulk Booking Index (2026-09-21) — إصلاح P0 لأداء سحب booking_nights.
  //
  // كان resolveBooking يستهلك حتى 4 استعلامات SELECT لكل ليلة مسحوبة
  // (exact uuid / normalized / stripped / serverId) — 5000 ليلة ≈ 10,000+
  // استعلام متسلسل على جهاز ضعيف. الفهرس يحمّل جدول bookings (صغير —
  // مئات إلى آلاف الصفوف) في الذاكرة استعلاماً واحداً ويجعل الحل O(1).
  //
  // دورة الحياة: يُبنى في بداية _syncBookingNights ويُمسح في finally —
  // المزامنة مُسلسلة عبر SyncLocks.appwriteSyncLock فلا سباق. عند غياب
  // الفهرس تعمل الدوال بمسار SQL الأصلي (توافق خلفي كامل).
  // ─────────────────────────────────────────────────────────────────────
  Map<String, int>? _bookingExactIndex;
  Map<String, int>? _bookingNormalizedIndex;
  Map<String, int>? _bookingStrippedIndex;
  Map<int, int>? _bookingServerIdIndex;

  /// هل الفهرس مبني حالياً؟ (تشخيص/اختبارات)
  bool get hasBookingIndex => _bookingExactIndex != null;

  /// يبني فهرس الحجوزات في الذاكرة (استعلام واحد).
  ///
  /// يُستدعى قبل حلقة معالجة دفعة ليالٍ كبيرة. خيارات المطابقة الثلاث
  /// للـ UUID (كما هو / بالشرطات / بدون شرطات) تُفهرس مسبقاً لأن بيانات
  /// الإنتاج تحوي الصيغتين (legacy بلا شرطات من Drive/backup قديم).
  Future<void> buildBookingIndex() async {
    // selectOnly + addColumns: نحمّل 3 أعمدة فقط (uuid/serverId/id) — لا
    // صفوف كاملة — استعلام واحد مهما كان حجم الدفعة اللاحقة.
    final query = db.selectOnly(db.bookings)
      ..addColumns(
        db.bookings.localUuid,
        db.bookings.serverBookingId,
        db.bookings.id,
      );
    final rows = await query.get();
    final exact = <String, int>{};
    final normalized = <String, int>{};
    final stripped = <String, int>{};
    final byServerId = <int, int>{};
    for (final row in rows) {
      final uuid = row.read(db.bookings.localUuid) ?? '';
      final id = row.read(db.bookings.id)!;
      if (uuid.isEmpty) continue;
      exact[uuid] = id;
      normalized.putIfAbsent(normalizeUuid(uuid), () => id);
      final strip = stripDashes(uuid);
      if (strip.length == 32) {
        stripped.putIfAbsent(strip, () => id);
      }
      final sid = row.read(db.bookings.serverBookingId);
      if (sid != null) {
        byServerId.putIfAbsent(sid, () => id);
      }
    }
    _bookingExactIndex = exact;
    _bookingNormalizedIndex = normalized;
    _bookingStrippedIndex = stripped;
    _bookingServerIdIndex = byServerId;
  }

  /// يمسح الفهرس (يُستدعى في finally بعد انتهاء الدفعة — يحرر الذاكرة
  /// على أجهزة 1GB).
  void clearBookingIndex() {
    _bookingExactIndex = null;
    _bookingNormalizedIndex = null;
    _bookingStrippedIndex = null;
    _bookingServerIdIndex = null;
  }

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
    // ✅ مسار الفهرس (O(1)): نفس ترتيب الأولويات كمسار SQL بالضبط —
    // exact uuid → normalized → stripped → serverId → (localId محلي فقط).
    // أولوية putIfAbsent أعلاه = أول مطابقة (id أصغر) — مطابق لسلوك
    // ..limit(1) بدون ORDER BY في المسار الأصلي (تكرارات نادرة).
    if (_bookingExactIndex != null) {
      if (uuid != null && uuid.isNotEmpty) {
        final exact = _bookingExactIndex![uuid];
        if (exact != null) return exact;
        final normalized = _bookingNormalizedIndex![normalizeUuid(uuid)];
        if (normalized != null) return normalized;
        final stripped = stripDashes(uuid);
        if (stripped.length == 32) {
          final hit = _bookingStrippedIndex![stripped];
          if (hit != null) return hit;
        }
      }
      if (serverId != null) {
        final hit = _bookingServerIdIndex![serverId];
        if (hit != null) return hit;
      }
      // localId من جهاز بعيد ممنوع (نفس قرار المسار الأصلي أدناه).
      if (localId != null && !fromRemote) {
        if (_bookingExactIndex!.values.contains(localId)) return localId;
      }
      return null;
    }

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
  ///
  /// ✅ إصلاح (2026-09-02) — الترتيب الآمن عبر الأجهزة: UUID → serverId →
  /// (id المحلي فقط للمصدر المحلي).
  /// سبب منع مطابقة `localId`/`employeeId` مع e.id للمصادر البعيدة:
  /// Employee.id هو autoIncrement محلي — يختلف بين الأجهزة (base_repository
  /// يزيل id للسجلات الجديدة فيُعيّن SQLite رقماً جديداً بترتيب عشوائي
  /// دلالياً). مطابقته مع employeeId البعيد (id جهاز المصدر) تربط السحوبة
  /// بموظف آخر يحمل نفس الرقم على الجهاز المستلم — ربط خاطئ صامت لسجلات
  /// مالية. هذا نفس القرار المعمول به في resolveBooking أعلاه وفي
  /// expenses_adapter.resolveRefs، ويتطابق مع توثيق _syncEmployees:
  /// "salary_withdrawals و salary_cycles يستخدمان employeeId البعيد الذي
  /// يساوي id الموظف على جهاز المصدر. بتخزينه في serverId يمكن حل FK بالبحث
  /// عن serverId = remoteEmployeeId".
  ///
  /// [serverId] للمصادر البعيدة يُمرَّر بقيمة employeeId من الـ payload
  /// (دلالة "id جهاز المصدر")، وليس serverId السجل الابن نفسه — خلط
  /// فضاءتي المعرفتين يربط الابن بموظف عشوائي إذا تصادفا رقمياً.
  ///
  /// ازدواج serverId في السحابة (خطأ بيانات — موظفان بـ serverId=1):
  /// المطابقة حتمية: النشط (deletedAt NULL/0) أولاً ثم الأصغر id، مع تحذير.
  Future<int?> resolveEmployee({
    int? localId,
    String? uuid,
    int? serverId,
    int? employeeId,
    bool fromRemote = false,
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
    // 2. البحث بالـ serverId (المعرف الأصلي من جهاز المصدر)
    if (serverId != null) {
      // حتمية الاختيار عند ازدواج serverId (خطأ بيانات): النشط أولاً
      // (NULL يرتّب أولاً ASC) ثم الأصغر id محلياً.
      final rows =
          await (db.select(db.employees)
                ..where((e) => e.serverId.equals(serverId))
                ..orderBy([
                  (e) => d.OrderingTerm(
                    expression: e.deletedAt,
                    mode: d.OrderingMode.asc,
                  ),
                  (e) => d.OrderingTerm(expression: e.id),
                ]))
              .get();
      if (rows.isNotEmpty) {
        if (rows.length > 1) {
          AppLogger.warning(
            'ازدواج serverId=$serverId في employees: '
            '${rows.map((r) => 'id=${r.id}(deletedAt=${r.deletedAt})').join(', ')} '
            '— اختيار id=${rows.first.id} (النشط ثم الأصغر)',
            tag: 'IdResolver',
          );
        }
        return rows.first.id;
      }
    }
    // 3. البحث بالـ id المحلي — فقط للمصدر المحلي (نفس الجهاز).
    // للمصادر البعيدة (appwrite/drive) لا يجوز مطابقة id جهاز آخر مع
    // الـ autoIncrement المحلي — ربط خاطئ صامت (انظر التوثيق أعلاه).
    if (!fromRemote) {
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
      // 4. employeeId كان مكرراً لـ localId (نفس الاستعلام) — للتوافق
      // المحلي فقط.
      if (employeeId != null && employeeId != localId) {
        final row =
            await (db.select(db.employees)
                  ..where((e) => e.id.equals(employeeId))
                  ..limit(1))
                .getSingleOrNull();
        if (row != null) {
          return row.id;
        }
      }
    }
    return null;
  }

  /// حل مرجع دورة الراتب - التحقق من وجود الدورة محلياً
  /// يُستخدم في salary_payments للتحقق من FK
  ///
  /// ✅ إصلاح: يجرّب كلا صيغتي UUID (بالشرطات وبدون) — مثل resolveBooking/resolveEmployee.
  ///
  /// ✅ إصلاح (2026-09-02) — نفس دلالات [resolveEmployee]: UUID → serverId →
  /// (id المحلي فقط للمصدر المحلي). salary_payments يخزّن في payload
  /// cycleId = id الدورة على جهاز المصدر = serverId للدورة بعد سحبها.
  Future<int?> resolveSalaryCycle({
    int? localId,
    int? serverId,
    String? uuid,
    bool fromRemote = false,
  }) async {
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
    // 2. البحث بالـ serverId (id جهاز المصدر)
    if (serverId != null) {
      final rows =
          await (db.select(db.salaryCycles)
                ..where((c) => c.serverId.equals(serverId))
                ..orderBy([
                  (c) => d.OrderingTerm(
                    expression: c.deletedAt,
                    mode: d.OrderingMode.asc,
                  ),
                  (c) => d.OrderingTerm(expression: c.id),
                ]))
              .get();
      if (rows.isNotEmpty) {
        if (rows.length > 1) {
          AppLogger.warning(
            'ازدواج serverId=$serverId في salary_cycles: '
            '${rows.map((r) => 'id=${r.id}(deletedAt=${r.deletedAt})').join(', ')} '
            '— اختيار id=${rows.first.id}',
            tag: 'IdResolver',
          );
        }
        return rows.first.id;
      }
    }
    // 3. البحث بالـ id المحلي — فقط للمصدر المحلي (انظر resolveEmployee).
    if (!fromRemote && localId != null) {
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
