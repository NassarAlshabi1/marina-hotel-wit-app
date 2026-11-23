// ignore_for_file: comment_references
import 'dart:async';

import 'package:drift/drift.dart';

import '../../utils/hotel_time_engine.dart';
import '../../utils/id.dart';
import '../../utils/sql_date_range.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../appwrite_sync_manager.dart';
import '../fcm_sender.dart';
import '../local_db.dart';
import '../sync_core/optimistic_lock_helper.dart';
import 'outbox_dao.dart';

part 'payments_dao.g.dart';

@DriftAccessor(tables: [Payments])
class PaymentsDao extends DatabaseAccessor<AppDatabase>
    with _$PaymentsDaoMixin, OptimisticLockDaoMixin<Payments, Payment> {
  PaymentsDao(super.db, this.outboxDao, [AdapterRegistry? a])
    : adapters = a ?? AdapterRegistry.instance;
  final OutboxDao outboxDao;
  final AdapterRegistry adapters;

  Future<List<Payment>> list({
    int? bookingLocalId,
    String? from,
    String? to,
    String? revenueType,
    bool includeDeleted = false,
    bool excludeVoided = false,
    bool excludePendingBalance = false,
    int? limit,
    int? offset,
  }) async {
    final q = select(payments);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (excludeVoided) {
      q.where((t) => t.isVoided.equals(false));
    }
    if (excludePendingBalance) {
      q.where((t) => t.isPendingBalance.equals(false));
    }
    if (bookingLocalId != null) {
      q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    }
    if (revenueType != null && revenueType.isNotEmpty) {
      q.where((t) => t.revenueType.equals(revenueType));
    }
    if (from != null && to != null) {
      q.where(
        (t) =>
            t.paymentDate.isBiggerOrEqualValue(from) &
            t.paymentDate.isSmallerOrEqualValue(to),
      );
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      q.limit(limit, offset: offset);
    }
    return q.get();
  }

  Future<List<Payment>> listForReport({
    String? from,
    String? to,
    String? roomNumber,
    bool includeDeleted = false,
    int? limit,
    int? offset,
  }) async {
    final q = select(payments);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    // استبعاد المدفوعات المُلغاة والمعلقة من التقارير المالية
    q.where((t) => t.isVoided.equals(false));
    q.where((t) => t.isPendingBalance.equals(false));

    if (from != null && to != null) {
      q.where(
        (t) =>
            t.paymentDate.isBiggerOrEqualValue(from) &
            t.paymentDate.isSmallerOrEqualValue(to),
      );
    }

    if (roomNumber != null && roomNumber.isNotEmpty) {
      q.where((t) => t.roomNumber.equals(roomNumber));
    }

    q.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      q.limit(limit, offset: offset);
    }
    return q.get();
  }

  Stream<List<Payment>> watchList({
    int? bookingLocalId,
    bool includeDeleted = false,
    int? limit,
    int offset = 0,
  }) {
    final q = select(payments);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (bookingLocalId != null) {
      q.where((t) => t.bookingLocalId.equals(bookingLocalId));
    }
    // ✅ إصلاح PR review: ترتيب deterministic قبل LIMIT لمنع تذبذب الصفحات
    // عبر التحديثات. id كـ tie-breaker يضمن استقرار الترتيب.
    q.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
      (t) => OrderingTerm(expression: t.id, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      q.limit(limit, offset: offset);
    }
    return q.watch();
  }

  /// مراقبة المدفوعات ليوم فندقي محدد (فلتر على مستوى قاعدة البيانات)
  ///
  /// ⚠️ **DEPRECATED** — استخدم `PaymentsRepository.watchTotalByHotelDayKey`
  /// الذي يستخدم SQL SUM() بدلاً من تحميل جميع صفوف المدفوعات (38 عمود)
  /// ثم جمعها في Dart. هذا الأسلوب القديم يستهلك ذاكرة و I/O مضاعف.
  @Deprecated(
    'استخدم PaymentsRepository.watchTotalByHotelDayKey (SQL SUM) بدلاً من ذلك',
  )
  Stream<List<Payment>> watchByHotelDayKey(
    String hotelDayKey, {
    bool includeVoided = false,
  }) {
    final q = select(payments);
    q.where((t) => t.deletedAt.isNull());
    if (!includeVoided) {
      q.where((t) => t.isVoided.equals(false));
    }
    final range = SqlDateRange.forDay(hotelDayKey);
    q.where((t) {
      final legacyDateMatch = range == null
          ? t.paymentDate.like('$hotelDayKey%')
          : (t.paymentDate.isBiggerOrEqualValue(range.start) &
                t.paymentDate.isSmallerThanValue(range.endExclusive));
      return t.hotelDayKey.equals(hotelDayKey) |
          (t.hotelDayKey.isNull() & legacyDateMatch);
    });
    return q.watch();
  }

  /// جلب المدفوعات لتاريخ محدد
  Future<List<Payment>> listByDate(
    String date, {
    bool includeDeleted = false,
    bool includeVoided = false,
  }) async {
    final q = select(payments);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (!includeVoided) {
      q.where((t) => t.isVoided.equals(false));
    }
    final range = SqlDateRange.forDay(date);
    q.where(
      (t) => range == null
          ? t.paymentDate.like('$date%')
          : (t.paymentDate.isBiggerOrEqualValue(range.start) &
                t.paymentDate.isSmallerThanValue(range.endExclusive)),
    );
    return q.get();
  }

  /// فلترة حسب نطاق الأيام الفندقية — الطريقة الصحيحة للتقارير
  ///
  /// على عكس [list] و [listForReport] التي تفلتر بحقل [paymentDate] الزمني
  /// (وتشمل مدفوعات الصباح التي تنتمي لليوم الفندقي السابق)،
  /// هذه الدالة تفلتر بحقل [hotelDayKey] وهو المفتاح الصحيح.
  ///
  /// مثال: إذا كان اليوم الفندقي "2026-05-18" والوقت 10:00 صباحاً
  /// فإن list(from:"2026-05-18") تجلب مدفوعات صباح 18 مايو
  /// التي تنتمي لليوم الفندقي 17 مايو — بينما هذه الدالة تجلب فقط
  /// المدفوعات التي hotelDayKey فيها بين fromHotelDay و toHotelDay.
  Future<List<Payment>> listFilteredByHotelDay({
    String? fromHotelDay,
    String? toHotelDay,
    String? roomNumber,
    String? revenueType,
    bool excludeVoided = false,
    bool excludePendingBalance = false,
    bool includeDeleted = false,
  }) async {
    final q = select(payments);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (excludeVoided) {
      q.where((t) => t.isVoided.equals(false));
    }
    if (excludePendingBalance) {
      q.where((t) => t.isPendingBalance.equals(false));
    }
    if (fromHotelDay != null || toHotelDay != null) {
      q.where((t) {
        Expression<bool> hotelDayKeyRange = const Constant(true);
        Expression<bool> legacyDateRange = const Constant(true);
        if (fromHotelDay != null) {
          hotelDayKeyRange =
              hotelDayKeyRange &
              t.hotelDayKey.isBiggerOrEqualValue(fromHotelDay);
          legacyDateRange =
              legacyDateRange &
              t.paymentDate.isBiggerOrEqualValue(fromHotelDay);
        }
        if (toHotelDay != null) {
          hotelDayKeyRange =
              hotelDayKeyRange &
              t.hotelDayKey.isSmallerOrEqualValue(toHotelDay);
          legacyDateRange =
              legacyDateRange &
              t.paymentDate.isSmallerThanValue(Time.hotelDayEndIso(toHotelDay));
        }
        final hasHotelDayKey =
            t.hotelDayKey.isNotNull() & t.hotelDayKey.equals('').not();
        final hasNoHotelDayKey =
            t.hotelDayKey.isNull() | t.hotelDayKey.equals('');
        return (hasHotelDayKey & hotelDayKeyRange) |
            (hasNoHotelDayKey & legacyDateRange);
      });
    }
    if (roomNumber != null && roomNumber.isNotEmpty) {
      q.where((t) => t.roomNumber.equals(roomNumber));
    }
    if (revenueType != null && revenueType.isNotEmpty) {
      q.where((t) => t.revenueType.equals(revenueType));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.paymentDate, mode: OrderingMode.desc),
    ]);
    final results = await q.get();
    if (fromHotelDay == null && toHotelDay == null) return results;
    return results
        .where((payment) {
          final hotelDayKey = HotelTimeEngine.resolvePaymentHotelDayKey(
            storedHotelDayKey: payment.hotelDayKey,
            paymentDate: payment.paymentDate,
          );
          if (hotelDayKey == null) return false;
          return (fromHotelDay == null ||
                  hotelDayKey.compareTo(fromHotelDay) >= 0) &&
              (toHotelDay == null || hotelDayKey.compareTo(toHotelDay) <= 0);
        })
        .toList(growable: false);
  }

  Future<List<Payment>> listByHotelDayKey(
    String hotelDayKey, {
    bool includeDeleted = false,
    bool includeVoided = false,
    String? revenueType,
  }) async {
    final q = select(payments);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (!includeVoided) {
      q.where((t) => t.isVoided.equals(false));
    }

    final range = SqlDateRange.forDay(hotelDayKey);
    q.where((t) {
      final legacyDateMatch = range == null
          ? t.paymentDate.like('$hotelDayKey%')
          : (t.paymentDate.isBiggerOrEqualValue(range.start) &
                t.paymentDate.isSmallerThanValue(range.endExclusive));
      return t.hotelDayKey.equals(hotelDayKey) |
          (t.hotelDayKey.isNull() & legacyDateMatch);
    });

    if (revenueType != null && revenueType.isNotEmpty) {
      q.where((t) => t.revenueType.equals(revenueType));
    }

    return q.get();
  }

  Future<Payment?> getById(int id) =>
      (select(payments)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Payment?> watchById(int id) =>
      (select(payments)..where((t) => t.id.equals(id))).watchSingleOrNull();

  /// يوحّد شكل UUID (بشرطات 8-4-4-4-12) كي تتطابق هويات المستندات
  /// البعيدة مع السجلات المحلية مهما كان مصدر التوليد.
  String _canonicalPaymentUuid(String value) {
    final trimmed = value.trim();
    if (trimmed.length == 32 && !trimmed.contains('-')) {
      return '${trimmed.substring(0, 8)}-${trimmed.substring(8, 12)}-'
          '${trimmed.substring(12, 16)}-${trimmed.substring(16, 20)}-'
          '${trimmed.substring(20)}';
    }
    return trimmed;
  }

  Future<int> insertOne(
    PaymentsCompanion data, {
    bool originIsServer = false,
  }) async {
    final now = Time.nowEpoch();
    final uu = _canonicalPaymentUuid(
      data.localUuid.present ? data.localUuid.value : IdGen.uuid(),
    );
    final deviceId = originIsServer
        ? null
        : await AppwriteSyncManager.ensureDeviceIdForLocalWrite();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
      deviceId: originIsServer ? const Value.absent() : Value(deviceId!),
      serverId: data.serverPaymentId.present
          ? Value(data.serverPaymentId.value)
          : const Value.absent(),
    );

    // ✅ إصلاح PR review: إخراج FCM خارج transaction
    final id = await db.transaction(() async {
      final insertedId = await into(payments).insert(comp);
      if (!originIsServer) {
        await _mergeOutbox(
          op: 'create',
          localUuid: uu,
          serverId: comp.serverId.present ? comp.serverId.value : null,
          clientTs: now,
        );
      }
      return insertedId;
    });

    // ✅ FCM: إشعار الأجهزة الأخرى بدفعة جديدة (fire-and-forget)
    // بعد نجاح الـ transaction — لن يُرسل لدفعة لم تُحفظ.
    if (!originIsServer && comp.amount.present) {
      // قراءة roomNumber من booking المرتبط (اختياري، best-effort)
      String? roomNumber;
      if (comp.bookingLocalId.present && comp.bookingLocalId.value != null) {
        try {
          final booking =
              await (db.select(db.bookings)
                    ..where((b) => b.id.equals(comp.bookingLocalId.value!)))
                  .getSingleOrNull();
          roomNumber = booking?.roomNumber;
        } catch (_) {
          // تجاهل — roomNumber اختياري في الإشعار
        }
      }
      unawaited(
        FcmSender().notifyPaymentAdded(
          amount: comp.amount.value,
          roomNumber: roomNumber ?? 'غير محدد',
        ),
      );
    }
    return id;
  }

  Future<int> updateById(
    int id,
    PaymentsCompanion data, {
    bool originIsServer = false,
  }) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified = originIsServer && data.lastModified.present
          ? data.lastModified
          : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        lastModified: effectiveLastModified,
        version: Value(existing.version + 1),
      );
      final rows = await (update(
        payments,
      )..where((t) => t.id.equals(id))).write(comp);
      if (rows > 0 && !originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      final rows = await (update(payments)..where((t) => t.id.equals(id)))
          .write(
            PaymentsCompanion(
              deletedAt: Value(now),
              updatedAt: Value(now),
              lastModified: Value(now),
            ),
          );
      if (rows > 0 && !originIsServer) {
        // ✅ نستخدم 'update' بدلاً من 'delete' لأن softDelete يحدّث deletedAt
        // ولا يحذف المستند من Appwrite — الجهاز الآخر يحتاج رؤية deletedAt
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return rows;
    });
  }

  Future<Map<String, dynamic>?> _payloadForLocalUuid(String localUuid) async {
    final row =
        await (select(payments)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return adapters.payments.toJsonForSource(row, src: Source.appwrite);
  }

  Future<void> _mergeOutbox({
    required String op,
    required String localUuid,
    required int clientTs,
    int? serverId,
  }) async {
    final payload = await _payloadForLocalUuid(localUuid);
    if (payload == null) {
      return;
    }
    await outboxDao.merge(
      entity: 'payments',
      op: op,
      localUuid: localUuid,
      serverId: serverId,
      payload: payload,
      clientTs: clientTs,
    );
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع المدفوعات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final paymentsList = await list();
    return paymentsList.map((payment) => payment.toJson()).toList();
  }

  /// استيراد المدفوعات من JSON
  /// ✅ إصلاح حرج: تغليف العملية بالكامل في transaction لمنع فقدان البيانات
  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    await transaction(() async {
      if (clearExisting) {
        await delete(payments).go();
      }

      for (final paymentJson in data) {
        final payment = Payment.fromJson(paymentJson);
        // ✅ (2026-11-23) استيراد كامل الحقول بدل قائمة مختارة:
        // القائمة اليدوية كانت تُسقط أعمدة حرجة (isVoided/voidReason في المدفوعات،
        // amount/status/dueDate/isSettled في الديون، id/cleaningStatus في الغرف…)
        // فتعود النسخة الاحتياطية منقوصة: دفعات ملغاة تُحتسب مدفوعة، ديون بمبلغ
        // صفر، وأبناء مربوطون بمعرّفات آباء أُعيد ترقيمها. toCompanion(false)
        // يكتب كل الأعمدة كما هي (بما فيها id) فلا يُسقَط عمود جديد لاحقاً.
        await into(payments).insertOnConflictUpdate(payment.toCompanion(false));
      }
    });
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(payments)..addColumns([payments.id.count()]);
    final result = await query.getSingle();
    return result.read(payments.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(payments).go();
  }

  @override
  TableInfo<Payments, Payment> get optimisticTable => payments;

  @override
  String get optimisticTableName => 'payments';

  @override
  GeneratedColumn<String> get optimisticLocalUuid => payments.localUuid;

  @override
  GeneratedColumn<int> get optimisticVersion => payments.version;
}
