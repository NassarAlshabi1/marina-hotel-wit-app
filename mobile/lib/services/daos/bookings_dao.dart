import 'dart:async';

import 'package:drift/drift.dart';

import '../../utils/id.dart';
import '../../utils/time.dart';
import '../adapters/adapter_registry.dart';
import '../adapters/source.dart';
import '../appwrite_sync_manager.dart';
import '../fcm_sender.dart';
import '../local_db.dart';
import '../sync_core/optimistic_lock_helper.dart';
import 'outbox_dao.dart';

part 'bookings_dao.g.dart';

@DriftAccessor(tables: [Bookings])
class BookingsDao extends DatabaseAccessor<AppDatabase>
    with _$BookingsDaoMixin, OptimisticLockDaoMixin<Bookings, Booking> {
  BookingsDao(super.db, this.outboxDao, [AdapterRegistry? a])
    : adapters = a ?? AdapterRegistry.instance;
  final OutboxDao outboxDao;
  final AdapterRegistry adapters;

  Future<List<Booking>> list({
    String? search,
    String? roomNumber,
    String? status,
    String? from,
    String? to,
    bool includeDeleted = false,
    int? limit,
    int? offset,
  }) async {
    final q = select(bookings);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (roomNumber != null && roomNumber.isNotEmpty) {
      q.where((t) => t.roomNumber.equals(roomNumber));
    }
    if (status != null && status.isNotEmpty) {
      q.where((t) => t.status.equals(status));
    }
    if (from != null && to != null) {
      q.where(
        (t) =>
            t.checkinDate.isBiggerOrEqualValue(from) &
            t.checkinDate.isSmallerOrEqualValue(to),
      );
    }
    if (search != null && search.trim().isNotEmpty) {
      final s = '%${search.trim()}%';
      q.where((t) => t.guestName.like(s) | t.guestPhone.like(s));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.checkinDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      q.limit(limit, offset: offset ?? 0);
    }
    return q.get();
  }

  Stream<List<Booking>> watchList({
    String? roomNumber,
    String? status,
    bool includeDeleted = false,
    int? limit,
    int offset = 0,
  }) {
    final q = select(bookings);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (roomNumber != null && roomNumber.isNotEmpty) {
      q.where((t) => t.roomNumber.equals(roomNumber));
    }
    if (status != null && status.isNotEmpty) {
      q.where((t) => t.status.equals(status));
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.checkinDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      q.limit(limit, offset: offset);
    }
    return q.watch();
  }

  Future<Booking?> getById(int id) =>
      (select(bookings)..where((t) => t.id.equals(id))).getSingleOrNull();
  Stream<Booking?> watchById(int id) =>
      (select(bookings)..where((t) => t.id.equals(id))).watchSingleOrNull();

  Future<int> insertOne(
    BookingsCompanion data, {
    bool originIsServer = false,
  }) async {
    final now = Time.nowEpoch();
    final uu = data.localUuid.present ? data.localUuid.value : IdGen.uuid();
    final comp = data.copyWith(
      localUuid: Value(uu),
      createdAt: Value(now),
      updatedAt: Value(now),
      lastModified: Value(now),
      origin: Value(originIsServer ? 'server' : 'local'),
      deviceId: originIsServer
          ? const Value.absent()
          : Value(AppwriteSyncManager.currentDeviceIdStatic ?? ''),
    );

    // ✅ إصلاح PR review: إخراج FCM خارج transaction لمنع إشعارات كاذبة
    // عند rollback، ولمنع إطالة مدة الـ transaction.
    // الـ transaction يُنفّذ insert + outbox فقط (atomic)، ثم نُرسل FCM بعدها.
    final id = await db.transaction(() async {
      final insertedId = await into(bookings).insert(comp);
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

    // ✅ FCM: إشعار الأجهزة الأخرى بإنشاء حجز جديد (fire-and-forget)
    // يتم بعد نجاح الـ transaction — لن يُرسل إشعار لحجز لم يُحفظ.
    if (!originIsServer && comp.roomNumber.present && comp.guestName.present) {
      unawaited(
        FcmSender().notifyBookingCreated(
          roomNumber: comp.roomNumber.value,
          guestName: comp.guestName.value,
        ),
      );
    }
    return id;
  }

  Future<int> updateById(
    int id,
    BookingsCompanion data, {
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

      // ✅ إصلاح حرج: استبدال replace بـ write لتجنب InvalidDataException.
      //
      // السبب الجذري (مشخّص بالدليل من drift-2.31.0/lib/.../update.dart:124-130):
      // replace() يستدعي validateIntegrity(entity, isInserting: true) — أي
      // يفحص السلامة كأنها INSERT (يحذف الصف ويعيد إدراجه). هذا يتطلب أن تكون
      // كل required columns بلا default حاضرة في Companion (مثل localUuid،
      // createdAt، roomNumber، guestName، guestPhone).
      //
      // لكن BookingsRepository.update و sync_service.dart يستدعيان updateById
      // بـ Companion جزئي (فقط الحقول التي تحتاج تحديثاً فعلياً)، فتكون
      // required columns المذكورة Value.absent() → InvalidDataException عند
      // checkout أو عند مزامنة حجز موجود من السيرفر.
      //
      // write() مع where(id.equals(id)) يتجاهل Value.absent() ويحدّث فقط
      // الحقول الحاضرة — وهو السلوك المطلوب لتحديث جزئي. هذا يتوافق مع
      // الأسلوب المعتمد في كل DAOs الأخرى (employees، cash_transactions،
      // outbox، debts) ومع softDelete/restore في نفس bookings_dao.dart.
      final rows = await (update(
        bookings,
      )..where((t) => t.id.equals(id))).write(comp);
      if (rows == 0) {
        return 0;
      }
      if (!originIsServer) {
        await _mergeOutbox(
          op: 'update',
          localUuid: existing.localUuid,
          serverId: comp.serverId.present
              ? comp.serverId.value
              : existing.serverId,
          clientTs: now,
        );
      }
      return 1;
    });
  }

  Future<int> softDelete(int id, {bool originIsServer = false}) async {
    return db.transaction(() async {
      final now = Time.nowEpoch();
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      await (update(bookings)..where((t) => t.id.equals(id))).write(
        BookingsCompanion(
          deletedAt: Value(now),
          updatedAt: Value(now),
          lastModified: Value(now),
          version: Value(existing.version + 1),
        ),
      );
      if (!originIsServer) {
        await _mergeOutbox(
          op: 'delete',
          localUuid: existing.localUuid,
          serverId: existing.serverId,
          clientTs: now,
        );
      }
      return 1;
    });
  }

  Future<int> restore(int id) async {
    return db.transaction(() async {
      final existing = await getById(id);
      if (existing == null) {
        return 0;
      }
      await (update(bookings)..where((t) => t.id.equals(id))).write(
        BookingsCompanion(
          deletedAt: const d.Value.absent(),
          updatedAt: Value(Time.nowEpoch()),
          lastModified: Value(Time.nowEpoch()),
          version: Value(existing.version + 1),
        ),
      );
      await _mergeOutbox(
        op: 'update',
        localUuid: existing.localUuid,
        clientTs: Time.nowEpoch(),
      );
      return 1;
    });
  }

  Future<void> deletePermanently(int id) async {
    await (delete(bookings)..where((t) => t.id.equals(id))).go();
  }

  /// الحصول على حجز حسب localUuid
  Future<Booking?> getByLocalUuid(String localUuid) async {
    return (select(bookings)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
  }

  /// الحصول على حجز حسب serverBookingId
  Future<Booking?> getByServerId(int serverId) async {
    return (select(bookings)
          ..where((t) => t.serverBookingId.equals(serverId))
          ..limit(1))
        .getSingleOrNull();
  }

  /// تحديث serverBookingId لحجز موجود
  Future<int> updateServerBookingId(
    String localUuid,
    int serverBookingId,
  ) async {
    return (update(
      bookings,
    )..where((t) => t.localUuid.equals(localUuid))).write(
      BookingsCompanion(serverBookingId: Value(serverBookingId)),
    );
  }

  /// عدد الحجوزات حسب الحالة
  Future<int> countByStatus(
    String status, {
    bool includeDeleted = false,
  }) async {
    final query = selectOnly(bookings)
      ..addColumns([bookings.id.count()])
      ..where(bookings.status.equals(status));
    if (!includeDeleted) {
      query.where(bookings.deletedAt.isNull());
    }
    final result = await query.getSingle();
    return result.read(bookings.id.count()) ?? 0;
  }

  /// حجوزات نشطة لغرفة معينة
  Future<List<Booking>> getActiveBookingsForRoom(String roomNumber) async {
    return (select(bookings)
          ..where(
            (t) =>
                t.roomNumber.equals(roomNumber) &
                t.deletedAt.isNull() &
                t.status.equals('نشط'),
          )
          ..orderBy([
            (t) => OrderingTerm(
              expression: t.checkinDate,
              mode: OrderingMode.desc,
            ),
          ]))
        .get();
  }

  /// حجوزات قادمة (checkinDate >= today)
  Future<List<Booking>> getUpcomingBookings({int? limit}) async {
    final today = DateTime.now().toIso8601String().split('T').first;
    final query = select(bookings)
      ..where(
        (t) =>
            t.deletedAt.isNull() &
            t.checkinDate.isBiggerOrEqualValue(today) &
            t.status.equals('نشط'),
      )
      ..orderBy([(t) => OrderingTerm(expression: t.checkinDate)]);
    if (limit != null) {
      query.limit(limit);
    }
    return query.get();
  }

  /// البحث عن حجوزات حسب نص (اسم الضيف، رقم الهاتف، رقم الغرفة)
  Future<List<Booking>> search(
    String query, {
    bool includeDeleted = false,
    int? limit,
  }) async {
    final q = select(bookings);
    if (!includeDeleted) {
      q.where((t) => t.deletedAt.isNull());
    }
    if (query.trim().isNotEmpty) {
      final s = '%${query.trim()}%';
      q.where(
        (t) =>
            t.guestName.like(s) | t.guestPhone.like(s) | t.roomNumber.like(s),
      );
    }
    q.orderBy([
      (t) => OrderingTerm(expression: t.checkinDate, mode: OrderingMode.desc),
    ]);
    if (limit != null) {
      q.limit(limit);
    }
    return q.get();
  }

  /// جميع الحجوزات المحذوفة
  Future<List<Booking>> getDeletedBookings({int? limit}) async {
    final q = select(bookings)
      ..where((t) => t.deletedAt.isNotNull())
      ..orderBy([
        (t) => OrderingTerm(expression: t.deletedAt, mode: OrderingMode.desc),
      ]);
    if (limit != null) {
      q.limit(limit);
    }
    return q.get();
  }

  /// الحصول على bookingWithNights (للنسخ الاحتياطي/المزامنة)
  Future<Map<String, dynamic>?> payloadForLocalUuid(String localUuid) async {
    final row =
        await (select(bookings)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return adapters.bookings.toJsonForSource(row, src: Source.appwrite);
  }

  Future<void> _mergeOutbox({
    required String op,
    required String localUuid,
    required int clientTs,
    int? serverId,
  }) async {
    final payload = await payloadForLocalUuid(localUuid);
    if (payload == null) {
      return;
    }
    await outboxDao.merge(
      entity: 'bookings',
      op: op,
      localUuid: localUuid,
      serverId: serverId,
      payload: payload,
      clientTs: clientTs,
    );
  }

  // دوال النسخ الاحتياطي

  /// تصدير جميع الحجوزات إلى JSON
  Future<List<Map<String, dynamic>>> exportToJson() async {
    final bookingsList = await list();
    return bookingsList.map((booking) => booking.toJson()).toList();
  }

  /// استيراد الحجوزات من JSON
  Future<void> importFromJson(
    List<Map<String, dynamic>> data, {
    bool clearExisting = false,
  }) async {
    await transaction(() async {
      if (clearExisting) {
        await delete(bookings).go();
      }

      for (final bookingJson in data) {
        final booking = Booking.fromJson(bookingJson);
        await into(bookings).insertOnConflictUpdate(
          BookingsCompanion(
            id: Value(booking.id),
            serverBookingId: Value(booking.serverBookingId),
            roomNumber: Value(booking.roomNumber),
            guestName: Value(booking.guestName),
            guestPhone: Value(booking.guestPhone),
            guestIdType: Value(booking.guestIdType),
            guestIdNumber: Value(booking.guestIdNumber),
            guestIdIssueDate: Value(booking.guestIdIssueDate),
            guestIdIssuePlace: Value(booking.guestIdIssuePlace),
            guestNationality: Value(booking.guestNationality),
            guestEmail: Value(booking.guestEmail),
            guestAddress: Value(booking.guestAddress),
            checkinDate: Value(booking.checkinDate),
            checkoutDate: Value(booking.checkoutDate),
            actualCheckout: Value(booking.actualCheckout),
            status: Value(booking.status),
            notes: Value(booking.notes),
            expectedNights: Value(booking.expectedNights),
            calculatedNights: Value(booking.calculatedNights),
            localUuid: Value(booking.localUuid),
            serverId: Value(booking.serverId),
            createdAt: Value(booking.createdAt),
            updatedAt: Value(booking.updatedAt),
            deletedAt: Value(booking.deletedAt),
            lastModified: Value(booking.lastModified),
            version: Value(booking.version),
            origin: Value(booking.origin),
            discount: Value(booking.discount),
            discountType: Value(booking.discountType),
            discountStartDate: Value(booking.discountStartDate),
            totalNightsCached: Value(booking.totalNightsCached),
            totalDueCached: Value(booking.totalDueCached),
            totalPaidCached: Value(booking.totalPaidCached),
            remainingBalanceCached: Value(booking.remainingBalanceCached),
            isFullyPaid: Value(booking.isFullyPaid),
            hotelDayCheckin: Value(booking.hotelDayCheckin),
            hotelDayCheckout: Value(booking.hotelDayCheckout),
            stayDurationIso: Value(booking.stayDurationIso),
            lastNightEpoch: Value(booking.lastNightEpoch),
            isOverdue: Value(booking.isOverdue),
            needsCheckoutReview: Value(booking.needsCheckoutReview),
            createdAtIso: Value(booking.createdAtIso),
            updatedAtIso: Value(booking.updatedAtIso),
            deletedAtIso: Value(booking.deletedAtIso),
            createdAtEpoch: Value(booking.createdAtEpoch),
            lastModifiedEpoch: Value(booking.lastModifiedEpoch),
            vectorClock: Value(booking.vectorClock),
          ),
        );
      }
    });
  }

  /// الحصول على عدد السجلات
  Future<int> getRecordCount() async {
    final query = selectOnly(bookings)..addColumns([bookings.id.count()]);
    final result = await query.getSingle();
    return result.read(bookings.id.count()) ?? 0;
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await delete(bookings).go();
  }

  @override
  TableInfo<Bookings, Booking> get optimisticTable => bookings;

  @override
  String get optimisticTableName => 'bookings';

  @override
  GeneratedColumn<String> get optimisticLocalUuid => bookings.localUuid;

  @override
  GeneratedColumn<int> get optimisticVersion => bookings.version;
}
