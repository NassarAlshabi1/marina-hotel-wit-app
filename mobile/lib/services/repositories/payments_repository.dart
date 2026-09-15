import 'dart:async';

import 'package:drift/drift.dart' as d;

import '../../utils/debug_log.dart';
import '../../utils/hotel_time_engine.dart';
import '../auto_backup_manager.dart';
import '../booking_derived_fields_service.dart';
import '../crashlytics_service.dart';
import '../daos/outbox_dao.dart';
import '../daos/payments_dao.dart';
import '../local_db.dart';
import '../payment_session_context.dart';
import '../telegram/telegram_notification_service.dart';
import '../telegram/whatsapp_notification_service.dart';

/// ملخّص استلامات هوية مستخدم واحدة بحسب اليوم الفندقي — سطر واحد
/// في بطاقة «استلامات المستخدمين الآخرين بحسب اليوم الفندقي».
class PaymentUserHotelDaySummary {
  const PaymentUserHotelDaySummary({
    required this.userId,
    required this.userName,
    required this.totalAmount,
    required this.paymentCount,
  });

  factory PaymentUserHotelDaySummary.fromRow(Map<String, dynamic> row) {
    return PaymentUserHotelDaySummary(
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
  /// يطابق المنطق السابق: hotelDayKey مطابق OR (hotelDayKey فارغ AND paymentDate ضمن النطاق).
  Stream<double> watchTotalByHotelDayKey(String hotelDayKey) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 AND '
          '(hotel_day_key = ? OR (hotel_day_key IS NULL AND payment_date LIKE ?))',
          variables: [
            d.Variable.withString(hotelDayKey),
            d.Variable.withString('$hotelDayKey%'),
          ],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  /// ✅ (2026-09-05) إجمالي ما استلمه المستخدم في نوبته الحالية —
  /// يعتمد على session UUID حصراً بلا فلتر يوم فندقي: النوبة (جلسة
  /// الدخول — الخيار A) قد تعبر حد 14:01 فتتوزع استلاماتها على مفتاحي
  /// يوم فندقي، والإجمالي الهندسي الصحيح «أثناء النوبة» = كل ما
  /// استُلم في هذه الجلسة منذ بدايتها. لا يخلط دفعات جلسة سابقة
  /// ولا دفعات موظف آخر على الجهاز نفسه؛ السجلات القديمة بلا session
  /// UUID لا تُنسب بأثر رجعي (NULL != القيمة دائماً).
  Stream<double> watchTotalByCurrentPaymentSession() {
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
          'AND received_by_user_id = ? AND received_session_uuid = ?',
          variables: [
            d.Variable.withInt(userId),
            d.Variable.withString(sessionUuid),
          ],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  /// ✅ (2026-09-15) استلامات المستخدمين الآخرين بحسب اليوم الفندقي
  /// فقط — طلب المستخدم الحرفي. العقد:
  /// • النافذة = اليوم الفندقي [hotelDayKey] حصراً (لا نافذة يومين):
  ///   سطر واحد لكل مستخدم = إجمالي كل ما استلمه في هذا اليوم الفندقي
  ///   مهما كان عدد جلساته. النوبة العابرة لحد 14:01 تُقتطع عمداً عند
  ///   حدود اليوم الفندقي: جزء الأمس الفندقي يظهر في يومه هو.
  /// • لا شرط session UUID: «بحسب اليوم الفندقي فقط» يعني أن الجلسة
  ///   ليست بُعد تجميع هنا — حتى الإرث بلا جلسة يُحسب لمستلمه في يومه
  ///   (بطاقة «نوبتي الحالية» أعلاه هي وحدها المعتمدة على الجلسة).
  /// • التجميع بهوية ثابتة (2026-09-14): COALESCE(cloud_id,
  ///   'legacy:'+user_id) — نفس الشخص بأسماء مختلفة (أحمد/أحمد محمد)
  ///   أو بمعرفات محلية مختلفة عبر أجهزة = سطر واحد؛ ومعرف محلي
  ///   مشترك عبر جهازين بـ cloud_id مختلف = سطران (لا خلط إجماليات).
  /// • الاستبعاد بهوية ثابتة (2026-09-14): الاسم لا يستبعد صفاً
  ///   سحابياً أبداً — صفوف الإرث بلا cloud_id تُستبعد بالمعرّف
  ///   المحلي أولاً ثم بالاسم احتياطاً (هي وُلدت على هذا الجهاز
  ///   فمعرّفها موثوق).
  /// الاسم المعروض = MAX(received_by_name) اسم تمثيلي، وصفوف الإرث
  /// بلا hotel_day_key تُشمل بـ LIKE على مفتاح اليوم. التجميع في
  /// SQLite حتى لا تُحمّل صفوف المدفوعات إلى Dart.
  Stream<List<PaymentUserHotelDaySummary>> watchPaymentUserHotelDaySummaries(
    String hotelDayKey, {
    int? excludedUserId,
    String? excludedUserName,
    String? excludedUserCloudId,
  }) {
    final excludedUserIdFilter = excludedUserId == null
        ? ''
        : 'AND (received_by_cloud_id IS NOT NULL OR received_by_user_id != ?) ';
    final excludedNameFilter = excludedUserName == null
        ? ''
        : 'AND (received_by_cloud_id IS NOT NULL OR '
              "COALESCE(NULLIF(TRIM(received_by_name), ''), 'مستخدم غير معروف') != ?) ";
    final excludedCloudIdFilter = excludedUserCloudId == null
        ? ''
        : 'AND (received_by_cloud_id IS NULL OR received_by_cloud_id != ?) ';
    return db
        .customSelect(
          'SELECT MIN(received_by_user_id) AS user_id, '
          "COALESCE(NULLIF(TRIM(MAX(received_by_name)), ''), 'مستخدم غير معروف') AS user_name, "
          'COALESCE(SUM(amount), 0.0) AS total_amount, '
          'COUNT(*) AS payment_count '
          'FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 '
          'AND is_pending_balance = 0 '
          'AND received_by_user_id IS NOT NULL '
          'AND (received_by_cloud_id IS NOT NULL OR received_by_name IS NOT NULL) '
          '$excludedUserIdFilter'
          '$excludedNameFilter'
          '$excludedCloudIdFilter'
          'AND (hotel_day_key = ? '
          'OR (hotel_day_key IS NULL AND payment_date LIKE ?)) '
          "GROUP BY COALESCE(received_by_cloud_id, 'legacy:' || received_by_user_id) "
          'ORDER BY total_amount DESC',
          variables: [
            if (excludedUserId != null) d.Variable.withInt(excludedUserId),
            if (excludedUserName != null)
              d.Variable.withString(excludedUserName),
            if (excludedUserCloudId != null)
              d.Variable.withString(excludedUserCloudId),
            d.Variable.withString(hotelDayKey),
            d.Variable.withString('$hotelDayKey%'),
          ],
          readsFrom: {db.payments},
        )
        .watch()
        .map(
          (rows) => rows
              .map((row) => PaymentUserHotelDaySummary.fromRow(row.data))
              .toList(growable: false),
        );
  }

  /// مراقبة إجمالي المدفوعات لحجز محدد عبر SQL SUM() — بديل خفيف الوزن
  /// لـ [paymentsByBooking] عندما يحتاج المستهلك فقط للمجموع (مثل قائمة الحجوزات).
  /// يتجنب تحميل جميع صفوف المدفوعات (38 عمود) وفك تشفيرها فقط لجمع `amount`.
  Stream<double> watchTotalPaidForBooking(int bookingLocalId) {
    return db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0 AND booking_local_id = ?',
          variables: [d.Variable.withInt(bookingLocalId)],
          readsFrom: {db.payments},
        )
        .watchSingle()
        .map((result) => (result.data['total'] as num).toDouble());
  }

  /// ✅ (2026-09-16) هوية مستلم الدفعة السحابية الثابتة.
  ///
  /// المشكلة: cloud_user_id لا يُحفظ في جلسة الدخول الدائمة
  /// (AuthUser.toJson لا يضمّنه) — بعد إعادة تشغيل التطبيق تُستعاد
  /// الجلسة بلا هوية سحابية فتُسجّل الدفعة بـ received_by_cloud_id
  /// NULL، ويظهر صاحبها تحت هوية 'legacy:' زائفة في بطاقة الاستلامات
  /// (نفس الشخص بسطرين على جهازين، والاستبعاد بالمعرّف يفشل).
  ///
  /// ترتيب الحل (الأدق أولاً):
  /// 1. هوية الجلسة إن وُجدت — موثوقة دائماً وتُعاد كما هي.
  /// 2. مطابقة الاسم في مرآة app_users المحلية (landing zone للسحب
  ///    من D1): userName مصدره full_name ?? username — نفس مصدر
  ///    التجميع في البطاقة. القبول فقط عند تطابق صف حي واحد بالضبط
  ///    (DISTINCT local_uuid) — أي غموض (أكثر من هوية) أو لا مطابقة
  ///    يعيد NULL = السلوك السابق، لا إسناد خاطئ أبداً.
  ///
  /// ملاحظة أمان: لا مطابقة بـ app_users.id عمداً — معرّف الحساب
  /// المخصص المحلي تسلسل جهازي قد يصادف id صف مستخدم سحابي آخر
  /// فيُنسب الدفع للشخص الخطأ.
  Future<String?> _resolveReceiverCloudId() async {
    final sessionCloudId = PaymentSessionContext.cloudUserId?.trim();
    if (sessionCloudId != null && sessionCloudId.isNotEmpty) {
      return sessionCloudId;
    }
    final displayName = PaymentSessionContext.userName?.trim() ?? '';
    if (displayName.isEmpty) return null;
    try {
      final rows = await db
          .customSelect(
            'SELECT DISTINCT local_uuid FROM app_users '
            'WHERE deleted_at IS NULL '
            'AND (TRIM(full_name) = ? OR TRIM(username) = ?) '
            'LIMIT 2',
            variables: [
              d.Variable.withString(displayName),
              d.Variable.withString(displayName),
            ],
          )
          .get();
      if (rows.length != 1) return null;
      final cloudId = (rows.first.data['local_uuid'] ?? '').toString().trim();
      return cloudId.isEmpty ? null : cloudId;
    } catch (e) {
      dlog(() => '⚠️ تعذر تحديد هوية مستلم الدفعة السحابية: $e');
      return null;
    }
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
  }) async {
    try {
      if (!PaymentSessionContext.isActive) {
        throw StateError('لا يمكن تسجيل دفعة دون جلسة مستخدم نشطة');
      }
      final hotelDayKey = HotelTimeEngine.getHotelDayKeyFromIso(paymentDate);
      // ✅ (2026-09-16) الهوية السحابية تُحسم قبل المعاملة — انظر
      // [_resolveReceiverCloudId]: الجلسة أولاً، وإلا مطابقة الاسم
      // الفريدة في مرآة app_users (الجلسة المستعادة تفقد cloud_user_id).
      final receiverCloudId = await _resolveReceiverCloudId();

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
            receivedByUserId: d.Value(PaymentSessionContext.userId),
            receivedByName: d.Value(PaymentSessionContext.userName),
            receivedSessionUuid: d.Value(PaymentSessionContext.sessionUuid),
            receivedByCloudId: d.Value(receiverCloudId),
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
          ? HotelTimeEngine.getHotelDayKeyFromIso(paymentDate)
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

  Future<int> delete(int id) async {
    try {
      final payment = await (db.select(
        db.payments,
      )..where((p) => p.id.equals(id))).getSingleOrNull();
      final bookingId = payment?.bookingLocalId;

      // ✅ تغليف العملية في معاملة لضمان اتساق البيانات
      final result = await db.transaction(() async {
        final deleted = await dao.softDelete(id);
        if (deleted > 0 && bookingId != null) {
          await derivedFields.refreshForBookingId(bookingId);
        }
        return deleted;
      });

      if (result > 0) {
        unawaited(
          AutoBackupManager.instance.onDataChange(
            'payments',
            'DELETE',
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
    final variables = <d.Variable<Object>>[
      d.Variable.withString(hotelDayKey),
      d.Variable.withString('$hotelDayKey%'),
    ];
    var revenueFilter = '';
    if (revenueType != null && revenueType.isNotEmpty) {
      revenueFilter = ' AND revenue_type = ?';
      variables.add(d.Variable.withString(revenueType));
    }
    final result = await db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0.0) AS total FROM payments '
          'WHERE deleted_at IS NULL AND is_voided = 0'
          '  AND (hotel_day_key = ? OR (hotel_day_key IS NULL AND payment_date LIKE ?))'
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
