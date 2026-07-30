// ignore_for_file: comment_references
import 'dart:async';

import 'package:drift/drift.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../appwrite_sync_manager.dart';
import '../fcm_sender.dart';
import '../local_db.dart';
import '../local_notification_service.dart';
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
    // حالة 1: hotelDayKey يطابق اليوم
    q.where(
      (t) =>
          t.hotelDayKey.equals(hotelDayKey) |
          // حالة 2: hotelDayKey فارغ وتاريخ الدفعة ضمن نطاق اليوم
          (t.hotelDayKey.isNull() & t.paymentDate.like('$hotelDayKey%')),
    );
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
    q.where((t) => t.paymentDate.like('$date%'));
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
    if (fromHotelDay != null) {
      // hotelDayKey >= fromHotelDay، مع fallback لحقل paymentDate عند كون hotelDayKey فارغاً
      q.where(
        (t) =>
            (t.hotelDayKey.isNotNull() &
                t.hotelDayKey.isBiggerOrEqualValue(fromHotelDay)) |
            (t.hotelDayKey.isNull() &
                t.paymentDate.isBiggerOrEqualValue(fromHotelDay)),
      );
    }
    if (toHotelDay != null) {
      q.where(
        (t) =>
            (t.hotelDayKey.isNotNull() &
                t.hotelDayKey.isSmallerOrEqualValue(toHotelDay)) |
            (t.hotelDayKey.isNull() &
                t.paymentDate.isSmallerOrEqualValue(toHotelDay)),
      );
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
    return q.get();
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

    final byKey = payments.hotelDayKey.equals(hotelDayKey);
    final byDateFallback =
        payments.hotelDayKey.isNull() &
        payments.paymentDate.like('$hotelDayKey%');

    q.where((t) => byKey | byDateFallback);

    if (revenueType != null && revenueType.isNotEmpty) {
      q.where((t) => t.revenueType.equals(revenueType));
    }

    return q.get();
  }

  Future<Payment?> getById(int id) =>
      (select(payments)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Payment?> watchById(int id) =>
      (select(payments)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(
    PaymentsCompanion data, {
    bool originIsServer = false,
  }) async {
    final now = Time.nowEpoch();
    final nowIso = DateTime.now().toIso8601String();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      createdAtIso: Value(nowIso),
      createdAtEpoch: Value(now),
      updatedAt: Value(now),
      updatedAtIso: Value(nowIso),
      lastModified: Value(now),
      lastModifiedEpoch: Value(now),
      version: const Value(1),
      origin: Value(originIsServer ? 'server' : 'local'),
      deviceId: originIsServer
          ? const Value.absent()
          : Value(AppwriteSyncManager.currentDeviceIdStatic ?? ''),
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
      // قراءة roomNumber + guestName من booking المرتبط (اختياري، best-effort)
      String? roomNumber;
      String? guestName;
      if (comp.bookingLocalId.present && comp.bookingLocalId.value != null) {
        try {
          final booking =
              await (db.select(
                    db.bookings,
                  )..where((b) => b.id.equals(comp.bookingLocalId.value!)))
                  .getSingleOrNull();
          roomNumber = booking?.roomNumber;
          guestName = booking?.guestName;
        } catch (_) {
          // تجاهل — roomNumber/guestName اختياريان في الإشعار
        }
      }
      unawaited(
        FcmSender().notifyPaymentAdded(
          amount: comp.amount.value,
          roomNumber: roomNumber ?? 'غير محدد',
        ),
      );
      // ✅ إشعار محلي على نفس الجهاز
      unawaited(
        LocalNotificationService.instance.notifyPaymentAdded(
          amount: comp.amount.value,
          roomNumber: roomNumber ?? 'غير محدد',
          method: comp.paymentMethod.present ? comp.paymentMethod.value : null,
          guestName: guestName,
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
      final nowIso = DateTime.now().toIso8601String();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      // ✅ إصلاح: عند originIsServer=true، نستخدم lastModified من البيانات الواردة
      // بدلاً من تعيين now، لمنع إعادة رفع البيانات المسحوبة من السيرفر
      final effectiveLastModified = originIsServer && data.lastModified.present
          ? data.lastModified
          : Value(now);
      final effectiveLastModifiedEpoch =
          originIsServer && data.lastModifiedEpoch.present
          ? data.lastModifiedEpoch
          : Value(now);
      final comp = data.copyWith(
        updatedAt: Value(now),
        updatedAtIso: Value(nowIso),
        lastModified: effectiveLastModified,
        lastModifiedEpoch: effectiveLastModifiedEpoch,
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
      final nowIso = DateTime.now().toIso8601String();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      final rows = await (update(payments)..where((t) => t.id.equals(id)))
          .write(
            PaymentsCompanion(
              deletedAt: Value(now),
              deletedAtIso: Value(nowIso),
              updatedAt: Value(now),
              updatedAtIso: Value(nowIso),
              lastModified: Value(now),
              lastModifiedEpoch: Value(now),
              version: Value(existing.version + 1),
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
        await into(payments).insertOnConflictUpdate(
          PaymentsCompanion(
            serverPaymentId: Value(payment.serverPaymentId),
            bookingLocalId: Value(payment.bookingLocalId),
            serverBookingId: Value(payment.serverBookingId),
            roomNumber: Value(payment.roomNumber),
            amount: Value(payment.amount),
            paymentDate: Value(payment.paymentDate),
            notes: Value(payment.notes),
            paymentMethod: Value(payment.paymentMethod),
            revenueType: Value(payment.revenueType),
            hotelDayKey: Value(payment.hotelDayKey),
            linkedDebtUuid: Value(payment.linkedDebtUuid),
            bookingUuidCache: Value(payment.bookingUuidCache),
            cashTransactionLocalId: Value(payment.cashTransactionLocalId),
            cashTransactionServerId: Value(payment.cashTransactionServerId),
            localUuid: Value(payment.localUuid),
            serverId: Value(payment.serverId),
            createdAt: Value(payment.createdAt),
            updatedAt: Value(payment.updatedAt),
            deletedAt: Value(payment.deletedAt),
            lastModified: Value(payment.lastModified),
            version: Value(payment.version),
            origin: Value(payment.origin),
          ),
        );
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
