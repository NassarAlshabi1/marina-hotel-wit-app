import 'dart:async';

import 'package:drift/drift.dart' as d;
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/hotel_time_engine.dart';
import '../../utils/time.dart';
import '../auth_local_store.dart';
import '../auto_backup_manager.dart';
import '../booking_derived_fields_service.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';
import '../local_db.dart';
import '../payment_session_context.dart';
import '../payment_void_service.dart';
import '../telegram/telegram_notification_service.dart';
import '../telegram/whatsapp_notification_service.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

class LatestRoomReceipt {
  const LatestRoomReceipt({
    required this.roomNumber,
    required this.amount,
    required this.paymentDate,
  });

  factory LatestRoomReceipt.fromRow(Map<String, dynamic> row) {
    return LatestRoomReceipt(
      roomNumber: row['room_number']?.toString() ?? '',
      amount: (row['amount'] as num?)?.toDouble() ?? 0,
      paymentDate: row['payment_date']?.toString() ?? '',
    );
  }

  final String roomNumber;
  final double amount;
  final String paymentDate;
}

class PaymentShiftSummary {
  const PaymentShiftSummary({
    required this.userId,
    required this.userName,
    required this.totalAmount,
    required this.paymentCount,
  });

  factory PaymentShiftSummary.fromRow(Map<String, dynamic> row) {
    return PaymentShiftSummary(
      userId: (row['user_id'] as num?)?.toInt() ?? 0,
      userName: row['user_name']?.toString() ?? 'مستخدم غير معروف',
      totalAmount: (row['total_amount'] as num?)?.toDouble() ?? 0,
      paymentCount: (row['payment_count'] as num?)?.toInt() ?? 0,
    );
  }

  final int userId;
  final String userName;
  final double totalAmount;
  final int paymentCount;
}

class PaymentsRepository {
  PaymentsRepository(this.db) {
    outbox = OutboxDao(db);
    dao = PaymentsDao(db, outbox);
    derivedFields = BookingDerivedFieldsService(db);
  }
  final AppDatabase db;
  late final OutboxDao outbox;
  late final PaymentsDao dao;
  late final BookingDerivedFieldsService derivedFields;

  /// أحدث دفعة فعلية لكل غرفة ضمن اليوم الفندقي المحدد، مرتبة بالأحدث أولاً.
  /// تُستثنى الدفعات المحذوفة والملغاة والمعلّقة، وتُراقَب تغييرات payments.
  /// يُرجع صفاً واحداً لكل غرفة بدلاً من تحميل سجل المدفوعات بالكامل إلى الذاكرة.
  Stream<List<LatestRoomReceipt>> watchLatestRoomReceiptsByRoom(
    String hotelDayKey,
  ) {
    return db
        .customSelect(
          'WITH ranked_room_receipts AS ('
          ' SELECT room_number, amount, payment_date,'
          ' ROW_NUMBER() OVER ('
          ' PARTITION BY room_number ORDER BY payment_date DESC, id DESC'
          ' ) AS room_rank'
          ' FROM payments'
          ' WHERE deleted_at IS NULL AND is_voided = 0 AND is_pending_balance = 0'
          " AND room_number IS NOT NULL AND TRIM(room_number) <> ''"
          " AND revenue_type = 'room'"
          ' AND ${_hotelDayPaymentPredicate()}'
          ') '
          'SELECT room_number, amount, payment_date '
          'FROM ranked_room_receipts WHERE room_rank = 1 '
          'ORDER BY payment_date DESC, room_number ASC',
          variables: _hotelDayPaymentVariables(hotelDayKey),
          readsFrom: {db.payments},
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => LatestRoomReceipt.fromRow(row.data))
              .toList(growable: false),
        );
  }

  String _hotelDayPaymentPredicate() =>
      "(hotel_day_key = ? OR ((hotel_day_key IS NULL OR TRIM(hotel_day_key) = '') "
      "AND ((LENGTH(TRIM(payment_date)) <= 10 "
      "AND SUBSTR(TRIM(payment_date), 1, 10) = ?) "
      "OR (LENGTH(TRIM(payment_date)) > 10 "
      "AND datetime(replace(TRIM(payment_date), ' ', 'T')) >= datetime(?) "
      "AND datetime(replace(TRIM(payment_date), ' ', 'T')) < datetime(?)))))";

  List<d.Variable<Object>> _hotelDayPaymentVariables(String hotelDayKey) => [
    d.Variable.withString(hotelDayKey),
    d.Variable.withString(hotelDayKey),
    d.Variable.withString(Time.hotelDayStartIso(hotelDayKey)),
    d.Variable.withString(Time.hotelDayEndIso(hotelDayKey)),
  ];

  /// يحلّ هوية من نفّذ الحذف: مفتاح الجهاز المخزن عند تسجيل الجهاز
  /// (`appwrite_device_id` مع رجوع لـ `device_id`) واسم المستخدم الحالي
  /// (`full_name` ثم `username` من جلسة AuthLocalStore).
  Future<
    ({String? device, String? name, String? userType, List<String> permissions})
  >
  _resolveDeleter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final device =
          prefs.getString('appwrite_device_id') ?? prefs.getString('device_id');
      final user = await AuthLocalStore().loadCurrentUser();
      final name = (user?['full_name'] ?? user?['name'] ?? user?['username'])
          ?.toString();
      final rawPerms = user?['permissions'];
      final permissions = rawPerms is List
          ? rawPerms.map((e) => e.toString()).toList()
          : const <String>[];
      return (
        device: device,
        name: name,
        userType: user?['user_type']?.toString(),
        permissions: permissions,
      );
    } catch (_) {
      return (
        device: null,
        name: null,
        userType: null,
        permissions: const <String>[],
      );
    }
  }

  /// إلغاء الدفعة (void) متاح للمدير والمشرف فقط — دفاع عميق حتى لو
  /// وصل الاستدعاء من مسار لم تخفِ فيه الواجهة الزر.
  bool _canVoid({String? userType, List<String> permissions = const []}) =>
      AuthLocalStore.isManagerialRole(userType) || permissions.contains('all');

  Stream<List<Payment>> paymentsByBooking(int bookingLocalId) {
    final bookingStream = (db.select(
      db.bookings,
    )..where((b) => b.id.equals(bookingLocalId))).watchSingleOrNull();

    return bookingStream.asyncExpand((booking) {
      final q = db.select(db.payments);
      q.where((p) => p.deletedAt.isNull());

      if (booking == null) {
        q.where((p) => p.bookingLocalId.equals(bookingLocalId));
      } else {
        final byLocalId = db.payments.bookingLocalId.equals(bookingLocalId);
        final byUuid = db.payments.bookingUuidCache.equals(booking.localUuid);
        q.where((p) => byLocalId | byUuid);
      }

      q.orderBy([(p) => d.OrderingTerm.desc(p.paymentDate)]);
      return q.watch();
    });
  }

  Stream<List<Payment>> watchAll({bool includeDeleted = false}) =>
      dao.watchList(includeDeleted: includeDeleted);
  Stream<Payment?> watchOne(int id) => dao.watchById(id);

  /// مراقبة إجمالي المدفوعات ليوم فندقي محدد عبر SQL SUM() — أداء أفضل
  /// من تحميل جميع صفوف المدفوعات (38 عمود لكل صف) ثم جمعها في Dart.
  /// يُحدَّث تلقائياً عند أي تغيير في جدول المدفوعات بفضل Stream من Drift.
  /// السجلات التاريخية بلا مفتاح تُحسب ضمن النطاق الحصري 14:01→14:01.
  Stream<double> watchTotalByHotelDayKey(String hotelDayKey) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 '
          'AND is_pending_balance = 0 AND ${_hotelDayPaymentPredicate()}',
          variables: _hotelDayPaymentVariables(hotelDayKey),
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  /// إجمالي المدفوعات التي سجلها المستخدم في جلسة دخوله الحالية.
  /// يعتمد على session UUID، لذلك لا يخلط دفعات المستخدم من جلسة سابقة
  /// أو دفعات موظف آخر على الجهاز نفسه.
  Stream<double> watchTotalByCurrentPaymentSession(String hotelDayKey) {
    final sessionUuid = PaymentSessionContext.sessionUuid;
    final userId = PaymentSessionContext.userId;
    if (sessionUuid == null || userId == null) {
      return Stream<double>.value(0);
    }

    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 '
          'AND is_pending_balance = 0 '
          'AND received_by_user_id = ? AND received_session_uuid = ? '
          'AND ${_hotelDayPaymentPredicate()}',
          variables: [
            d.Variable.withInt(userId),
            d.Variable.withString(sessionUuid),
            ..._hotelDayPaymentVariables(hotelDayKey),
          ],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  /// إجماليات استلامات كل مستخدم عبر كل جلساته ضمن اليوم الفندقي —
  /// سطر واحد لكل مستخدم بغضّ النظر عن عدد جلسات تسجيل الدخول/النوبات.
  ///
  /// ✅ لا نشترط وجود جلسة: الدفعات القديمة/المستعادة من نسخ احتياطية
  /// التي فقدت received_session_uuid تُحسب ضمن مستلمها طالما الاسم أو
  /// المعرّف السحابي موجود (التطبيق أصلاً لا يسمح بتسجيل دفعة دون
  /// جلسة مستخدم نشطة). الوحيدة المستثناة: صف بلا أي مستلم معروف.
  /// التجميع يتم في SQLite حتى لا تُحمّل جميع صفوف المدفوعات إلى Dart.
  Stream<List<PaymentShiftSummary>> watchPaymentShiftSummaries(
    String hotelDayKey, {
    int? excludedUserId,
    String? excludedUserName,
    String? excludedUserCloudId,
  }) {
    final excludedNameFilter = excludedUserName == null
        ? ''
        : "AND COALESCE(NULLIF(TRIM(received_by_name), ''), 'مستخدم غير معروف') != ? ";
    final excludedCloudIdFilter = excludedUserCloudId == null
        ? ''
        : 'AND (received_by_cloud_id IS NULL OR received_by_cloud_id != ?) ';
    return db
        .customSelect(
          'SELECT received_by_user_id AS user_id, '
          "COALESCE(NULLIF(TRIM(received_by_name), ''), 'مستخدم غير معروف') AS user_name, "
          'COALESCE(SUM(amount), 0.0) AS total_amount, '
          'COUNT(*) AS payment_count '
          'FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 '
          'AND is_pending_balance = 0 '
          'AND (received_by_cloud_id IS NOT NULL OR received_by_name IS NOT NULL) '
          '${excludedUserId == null ? '' : 'AND received_by_user_id != ? '} '
          '$excludedNameFilter'
          '$excludedCloudIdFilter'
          'AND ${_hotelDayPaymentPredicate()} '
          'GROUP BY received_by_user_id, received_by_name '
          'ORDER BY total_amount DESC',
          variables: [
            if (excludedUserId != null) d.Variable.withInt(excludedUserId),
            if (excludedUserName != null)
              d.Variable.withString(excludedUserName),
            if (excludedUserCloudId != null)
              d.Variable.withString(excludedUserCloudId),
            ..._hotelDayPaymentVariables(hotelDayKey),
          ],
          readsFrom: {db.payments},
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => PaymentShiftSummary.fromRow(row.data))
              .toList(growable: false),
        );
  }

  /// قائمة المدفوعات حسب نطاق اليوم الفندقي، بما فيها السجلات التاريخية.
  Future<List<Payment>> listFilteredByHotelDay({
    String? fromHotelDay,
    String? toHotelDay,
    String? roomNumber,
    String? revenueType,
    bool excludeVoided = false,
    bool excludePendingBalance = false,
    bool includeDeleted = false,
  }) => dao.listFilteredByHotelDay(
    fromHotelDay: fromHotelDay,
    toHotelDay: toHotelDay,
    roomNumber: roomNumber,
    revenueType: revenueType,
    excludeVoided: excludeVoided,
    excludePendingBalance: excludePendingBalance,
    includeDeleted: includeDeleted,
  );

  /// مراقبة إجمالي المدفوعات لحجز محدد عبر SQL SUM() — بديل خفيف الوزن
  /// لـ [paymentsByBooking] عندما يحتاج المستهلك فقط للمجموع (مثل قائمة الحجوزات).
  /// يتجنب تحميل جميع صفوف المدفوعات (38 عمود) وفك تشفيرها فقط لجمع `amount`.
  /// الرصيد الفعلي المدفوع للحجز (للعرض في قائمة الحجوزات) — نفس قاعدة
  /// المحرك الموحد: غير المحذوفة/الملغاة/المعلّقة، بدون فلتر نوع الإيراد.
  Stream<double> watchTotalPaidForBooking(int bookingLocalId) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 '
          'AND is_pending_balance = 0 AND booking_local_id = ?',
          variables: [d.Variable.withInt(bookingLocalId)],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  Future<int> create({
    required double amount,
    required String paymentDate,
    required String paymentMethod,
    required String revenueType,
    int? bookingLocalId,
    int? serverBookingId,
    String? roomNumber,
    String? notes,
    bool isPendingBalance = false,
    // ✅ رابط دفعة بدين مسدَّد من شاشة الديون (Debts.localUuid) — يجعل
    // تسديد الدين دفعة حقيقية في جدول payments فتظهر في مدفوعات اليوم
    // الفندقي وفي الداشبورد تلقائياً (نفس الاستعلام الموحّد SUM(amount)
    // WHERE hotel_day_key = ...)، بدل أن تبقى تحديثاً معزولاً داخل جدول
    // debts فقط. العمود موجود أصلاً في الجدول والمزامنة (migration قديم)
    // لكنه لم يكن يُملأ من أي مسار إنشاء دفعة قبل هذا الإصلاح.
    String? linkedDebtUuid,
  }) async {
    try {
      if (!PaymentSessionContext.isActive) {
        throw StateError('لا يمكن تسجيل دفعة دون جلسة مستخدم نشطة');
      }
      final hotelDayKey =
          HotelTimeEngine.resolvePaymentHotelDayKey(
            storedHotelDayKey: null,
            paymentDate: paymentDate,
          ) ??
          HotelTimeEngine.getHotelDayKey();

      String? bookingUuidCache;
      if (bookingLocalId != null) {
        final booking = await (db.select(
          db.bookings,
        )..where((b) => b.id.equals(bookingLocalId))).getSingleOrNull();
        bookingUuidCache = booking?.localUuid;
      }

      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final id = await dao.insertOne(
          PaymentsCompanion(
            bookingLocalId: d.Value(bookingLocalId),
            serverBookingId: d.Value(serverBookingId),
            roomNumber: d.Value(roomNumber),
            amount: d.Value(amount),
            paymentDate: d.Value(paymentDate),
            notes: d.Value(notes),
            paymentMethod: d.Value(paymentMethod),
            revenueType: d.Value(revenueType),
            hotelDayKey: d.Value(hotelDayKey),
            bookingUuidCache: d.Value(bookingUuidCache),
            isPendingBalance: d.Value(isPendingBalance),
            linkedDebtUuid: d.Value(linkedDebtUuid),
            receivedByUserId: d.Value(PaymentSessionContext.userId),
            receivedByName: d.Value(PaymentSessionContext.userName),
            receivedSessionUuid: d.Value(PaymentSessionContext.sessionUuid),
            receivedByCloudId: d.Value(PaymentSessionContext.cloudUserId),
          ),
        );
        if (bookingLocalId != null) {
          await derivedFields.refreshForBookingId(bookingLocalId);
        }
        return id;
      });

      unawaited(
        AutoBackupManager.instance.onDataChange(
          'payments',
          'INSERT',
          recordData: {'amount': amount},
        ),
      );
      // إشعارات فورية (fire-and-forget)
      unawaited(_notifyPaymentReceived(result));
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'PaymentsRepository',
        action: 'create',
        error: e,
        stackTrace: stack,
        severity: CrashlyticsSeverity.fatal,
        extra: {
          'amount': '$amount',
          'method': paymentMethod,
          'bookingId': '$bookingLocalId',
        },
      );
      rethrow;
    }
  }

  Future<int> update(
    int id, {
    int? bookingLocalId,
    int? serverBookingId,
    String? roomNumber,
    double? amount,
    String? paymentDate,
    String? notes,
    String? paymentMethod,
    String? revenueType,
    bool? isPendingBalance,
  }) async {
    try {
      final before = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      final oldBookingId = before?.bookingLocalId;

      final hotelDayKey = paymentDate != null
          ? HotelTimeEngine.resolvePaymentHotelDayKey(
              storedHotelDayKey: null,
              paymentDate: paymentDate,
            )
          : null;

      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final updated = await dao.updateById(
          id,
          PaymentsCompanion(
            bookingLocalId: bookingLocalId != null
                ? d.Value(bookingLocalId)
                : const d.Value.absent(),
            serverBookingId: serverBookingId != null
                ? d.Value(serverBookingId)
                : const d.Value.absent(),
            roomNumber: roomNumber != null
                ? d.Value(roomNumber)
                : const d.Value.absent(),
            amount: amount != null ? d.Value(amount) : const d.Value.absent(),
            paymentDate: paymentDate != null
                ? d.Value(paymentDate)
                : const d.Value.absent(),
            notes: notes != null ? d.Value(notes) : const d.Value.absent(),
            paymentMethod: paymentMethod != null
                ? d.Value(paymentMethod)
                : const d.Value.absent(),
            revenueType: revenueType != null
                ? d.Value(revenueType)
                : const d.Value.absent(),
            hotelDayKey: hotelDayKey != null
                ? d.Value(hotelDayKey)
                : const d.Value.absent(),
            isPendingBalance: isPendingBalance != null
                ? d.Value(isPendingBalance)
                : const d.Value.absent(),
          ),
        );
        if (updated > 0) {
          final newBookingId = bookingLocalId ?? oldBookingId;
          final bookingIds = <int>{};
          if (oldBookingId != null) {
            bookingIds.add(oldBookingId);
          }
          if (newBookingId != null) {
            bookingIds.add(newBookingId);
          }
          for (final bId in bookingIds) {
            await derivedFields.refreshForBookingId(bId);
          }
        }
        return updated;
      });

      if (result > 0) {
        unawaited(
          AutoBackupManager.instance.onDataChange(
            'payments',
            'UPDATE',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'PaymentsRepository',
        action: 'update',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  /// لا حذف للمدفوعات: «الحذف» في هذا التطبيق هو إلغاء (void).
  /// يُعلّم الدفعة isVoided=true مع voidedBy/voidReason بدل tombstone،
  /// فيبقى أثرها المالي قابلاً للتدقيق وتُستثنى من الأرصدة والقوائم.
  /// [voidReason] سبب الإلغاء — من cascade حذف الحجز مرّر سبباً أوضح.
  Future<int> delete(int id, {String? voidReason}) async {
    try {
      final payment = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      if (payment == null) return 0;
      final bookingId = payment.bookingLocalId;

      // هوية الملغي: المستخدم الحالي في جلسة التطبيق.
      final deleter = await _resolveDeleter();

      // إلغاء الدفعة متاح للمدير والمشرف فقط.
      if (!_canVoid(
        userType: deleter.userType,
        permissions: deleter.permissions,
      )) {
        throw StateError('إلغاء الدفعات متاح للمدير والمشرف فقط');
      }

      final voided = await PaymentVoidService(db).voidPayment(
        paymentUuid: payment.localUuid,
        voidReason: voidReason ?? 'إلغاء من واجهة التطبيق',
        voidedBy: deleter.name ?? 'مستخدم غير معروف',
      );
      final result = voided ? 1 : 0;

      if (result > 0) {
        if (bookingId != null) {
          await derivedFields.refreshForBookingId(bookingId);
        }
        unawaited(
          AutoBackupManager.instance.onDataChange(
            'payments',
            'VOID',
            recordData: {'id': id},
          ),
        );
      }
      return result;
    } catch (e, stack) {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'PaymentsRepository',
        action: 'delete',
        error: e,
        stackTrace: stack,
        extra: {'id': '$id'},
      );
      rethrow;
    }
  }

  // دوال النسخ الاحتياطي

  /// تصدير بيانات المدفوعات
  Future<Map<String, dynamic>> exportData() async {
    final paymentsData = await dao.exportToJson();
    final recordCount = await dao.getRecordCount();

    return {'data': paymentsData, 'count': recordCount, 'entity': 'payments'};
  }

  /// استيراد بيانات المدفوعات
  Future<void> importData(Map<String, dynamic> data) async {
    if (data.containsKey('data') && data['data'] is List) {
      await dao.importFromJson(
        List<Map<String, dynamic>>.from(data['data'] as List),
      );
    }
  }

  /// مسح جميع البيانات
  Future<void> clearAllData() async {
    await dao.clearAllData();
  }

  /// الحصول على إجمالي عدد السجلات
  Future<int> getRecordCount() async {
    return dao.getRecordCount();
  }

  /// الحصول على إجمالي المدفوعات لتاريخ محدد
  Future<double> getTotalByDate(String date) async {
    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE payment_date LIKE ? AND deleted_at IS NULL AND is_voided = 0',
          variables: [d.Variable.withString('$date%')],
          readsFrom: {db.payments},
        )
        .getSingle();
    return (result.data['total'] as num).toDouble();
  }

  Future<double> getTotalByHotelDayKey(
    String hotelDayKey, {
    String? revenueType,
  }) async {
    final variables = _hotelDayPaymentVariables(hotelDayKey);
    var revenueFilter = '';
    if (revenueType != null && revenueType.isNotEmpty) {
      revenueFilter = ' AND revenue_type = ?';
      variables.add(d.Variable.withString(revenueType));
    }
    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 '
          'AND is_pending_balance = 0 AND ${_hotelDayPaymentPredicate()}'
          '$revenueFilter',
          variables: variables,
          readsFrom: {db.payments},
        )
        .getSingle();
    return (result.data['total'] as num).toDouble();
  }

  /// إرسال إشعارات (WhatsApp + Telegram) عند استلام دفعة
  Future<void> _notifyPaymentReceived(int paymentId) async {
    try {
      final payment = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(paymentId))).getSingleOrNull();
      if (payment == null) return;

      // الحصول على معلومات الحجز إن وجد
      String roomNumber = payment.roomNumber ?? '-';
      String guestName = '-';
      if (payment.bookingLocalId != null) {
        try {
          final booking =
              await (db.select(db.bookings)
                    ..where((b) => b.id.equals(payment.bookingLocalId!)))
                  .getSingleOrNull();
          if (booking != null) {
            roomNumber = booking.roomNumber;
            guestName = booking.guestName;
          }
        } catch (_) {}
      }

      unawaited(
        WhatsAppNotificationService.instance.notifyPayment(
          roomNumber: roomNumber,
          guestName: guestName,
          amount: payment.amount,
          paymentMethod: payment.paymentMethod,
        ),
      );
      unawaited(
        TelegramNotificationService.instance.notifyPayment(
          roomNumber: roomNumber,
          guestName: guestName,
          amount: payment.amount,
          paymentMethod: payment.paymentMethod,
        ),
      );
    } catch (e) {
      dlog(() => '⚠️ فشل إرسال إشعار الدفعة: $e');
    }
  }
}
