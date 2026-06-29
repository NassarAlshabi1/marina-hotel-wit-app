// ignore_for_file: unused_element, prefer_final_locals, unnecessary_lambdas, curly_braces_in_flow_control_structures
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_network_helper.dart';
import 'appwrite_sync_utils.dart';
import 'local_db.dart';
import 'secondary_appwrite_config.dart';

/// خدمة Appwrite الثانوية — تستخدم Appwrite SDK الرسمي (مثل Primary)
///
/// توفّر واجهة upsert للوجهة الثانوية. تُستخدم من SecondarySyncManager
/// فقط لتسليم سجلات outbox إلى خادم Appwrite الثانوي.
///
/// ❗ هذه الخدمة للكتابة فقط (push). السحب (pull) غير مُدعوم في هذه النسخة.
///
/// ✅ إصلاح (2026-06-28): استخدام AppwriteNetworkHelper لـ retry/timeout
/// مثل Primary. كتم أخطاء 404 المتوقعة في upsert probe.
class SecondaryAppwriteService {
  /// Factory singleton — يُرجع نفس الكائن دائماً.
  factory SecondaryAppwriteService() =>
      _instance ??= SecondaryAppwriteService._();

  SecondaryAppwriteService._();
  static SecondaryAppwriteService? _instance;

  // ignore: prefer_constructors_over_static_methods
  static SecondaryAppwriteService get instance => SecondaryAppwriteService();

  final _networkHelper = AppwriteNetworkHelper();
  // ignore: unused_field
  final _logger = AppwriteLogger();

  Client? _client;
  Databases? _databases;

  /// تهيئة الاتصال بـ Secondary (lazy)
  Future<void> _ensureInitialized() async {
    if (_databases != null) return;

    if (!SecondaryAppwriteConfig.isConfigured) {
      throw StateError(
        'Secondary Appwrite is not configured. '
        'Call SecondaryAppwriteConfig.saveConfig() first.',
      );
    }

    final apiKey = SecondaryAppwriteConfig.apiKey;
    _client = Client()
        .setEndpoint(SecondaryAppwriteConfig.endpoint)
        .setProject(SecondaryAppwriteConfig.projectId);
    if (apiKey.isNotEmpty) {
      _client!.addHeader('X-Appwrite-Key', apiKey);
    }

    _databases = Databases(_client!);
  }

  /// إبطال الكاش (عند تغيير الإعدادات)
  void invalidate() {
    _client = null;
    _databases = null;
  }

  /// نتيجة اختبار الاتصال
  Future<ConnectionTestResult> testConnection() async {
    final stopwatch = Stopwatch()..start();
    try {
      await _ensureInitialized();
      // ignore: deprecated_member_use
      await _databases!.listDocuments(
        databaseId: SecondaryAppwriteConfig.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      stopwatch.stop();
      return ConnectionTestResult(
        success: true,
        message: '✅ تم الاتصال بنجاح',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    } catch (e) {
      stopwatch.stop();
      debugPrint('❌ [Secondary] testConnection failed: $e');
      return ConnectionTestResult(
        success: false,
        message: '❌ فشل: $e',
        latencyMs: stopwatch.elapsedMilliseconds,
      );
    }
  }

  /// رفع نسخة شاملة من كل البيانات المحلية إلى Secondary
  Future<FullBackupStats> uploadFullBackup({
    required void Function(String collection, int current, int total) onProgress,
    required void Function(String collectionName, int successCount, int failureCount) onCollectionComplete,
  }) async {
    await _ensureInitialized();
    final db = DatabaseManager.instance;
    final stats = FullBackupStats();
    final collectionList = await _getAllCollections(db);

    stats.totalCollections = collectionList.length;
for (final coll in collectionList) {
      int successCount = 0;
      int failureCount = 0;
      int total = coll.records.length;
      int current = 0;

      for (final record in coll.records) {
        current++;
        onProgress(coll.name, current, total);

        // ✅ المعرّف يجب أن يأتي من localUuid حقيقي.
        // لا نرفع بمعرّف فارغ (يفسد النسخة ويُضلّل المستخدم) — بدل ذلك
        // نتخطّى السجل ونسجّله كخطأ صريح في الإحصائيات (fail fast / skip).
        final documentId = (record['localUuid'] as String?)?.trim();
        if (documentId == null || documentId.isEmpty) {
          failureCount++;
          const reason = 'تخطّي سجل بلا localUuid صالح (معرّف فارغ)';
          stats.failuresByCollection.putIfAbsent(coll.name, () => []).add(
            FullBackupFailure(documentId: null, reason: reason, collectionName: coll.name),
          );
          stats.errorsByReason[reason] = (stats.errorsByReason[reason] ?? 0) + 1;
          continue;
        }

        try {
          final filteredData = AppwriteSyncUtils.filterPayloadForCollection(
            coll.collectionId,
            record,
          );
          await upsertDocument(
            collectionId: coll.collectionId,
            documentId: documentId,
            data: filteredData,
          );
          successCount++;
        } catch (e) {
          failureCount++;
          final reason = e.toString();
          stats.failuresByCollection.putIfAbsent(coll.name, () => []).add(
            FullBackupFailure(documentId: documentId, reason: reason, collectionName: coll.name),
          );
          // ✅ إحصائيات الأخطاء حسب السبب
          final reasonShort = reason.length > 100 ? reason.substring(0, 100) : reason;
          stats.errorsByReason[reasonShort] = (stats.errorsByReason[reasonShort] ?? 0) + 1;
        }
      }

      onCollectionComplete(coll.name, successCount, failureCount);
      stats.collectionDetails.add({
        'name': coll.name,
        'total': total,
        'success': successCount,
        'failure': failureCount,
        'isFullySuccessful': failureCount == 0,
      });
      stats.successCount += successCount;
      stats.failureCount += failureCount;
      if (failureCount == 0) {
        stats.fullySuccessfulCollections++;
      } else {
        stats.failedCollections++;
      }
      stats.collectionNames.add(coll.name);
    }

    return stats;
  }

  /// Upsert مستند في Secondary — معالجة ID بدون شرطات (مثل Primary)
  Future<models.Document> upsertDocument({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> data,
  }) async {
    await _ensureInitialized();
    final dbId = SecondaryAppwriteConfig.databaseId;

    bool isNotFound(AppwriteException e) =>
        e.code == 404 ||
        (e.type ?? '').contains('document_not_found') ||
        e.toString().contains('document_not_found');

    bool isAlreadyExists(AppwriteException e) =>
        e.code == 409 ||
        (e.type ?? '').contains('document_already_exists') ||
        (e.type ?? '').contains('conflict') ||
        e.toString().contains('document_already_exists');

    // ✅ معالجة ID بدون شرطات (نفس Primary)
    final altDocumentId = documentId.contains('-')
        ? documentId.replaceAll('-', '')
        : '';

    Future<models.Document> doUpdate(
      String id, {
      bool suppressErrorLog = false,
    }) async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.updateDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: id,
          data: data,
        ),
        operationName: 'secondary_updateDocument',
        suppressErrorLog: suppressErrorLog,
      );
    }

    Future<models.Document> doCreate() async {
      return _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.createDocument(
          databaseId: dbId,
          collectionId: collectionId,
          documentId: documentId,
          data: data,
        ),
        operationName: 'secondary_createDocument',
        suppressErrorLog: true,
      );
    }

    // الخطوة 1: updateDocument بالـ ID الأصلي
    try {
      return await doUpdate(documentId, suppressErrorLog: true);
    } on AppwriteException catch (updateError) {
      if (!isNotFound(updateError)) {
        if (isAlreadyExists(updateError)) {
          try { return await doCreate(); }
          on AppwriteException catch (e2) {
            if (isAlreadyExists(e2)) {
              try { return await doUpdate(documentId); }
              catch (e3) { rethrow; }
            }
            rethrow;
          }
        }
        rethrow;
      }
    }

    // الخطوة 2: createDocument
    try {
      return await doCreate();
    } on AppwriteException catch (createError) {
      if (isAlreadyExists(createError)) {
        // ✅ تجربة ID البديل فقط — بلا حذف/ترحيل (نفس Primary)
        if (altDocumentId.isNotEmpty) {
          try {
            return await doUpdate(altDocumentId, suppressErrorLog: true);
          } on AppwriteException catch (altError) {
            if (!isNotFound(altError)) { rethrow; }
          }
        }
        // محاولة أخيرة
        try { return doUpdate(documentId, suppressErrorLog: true); }
        catch (_) { rethrow; }
      }
      rethrow;
    }
  }

  /// حذف مستند من Secondary
  Future<void> deleteDocument({
    required String collectionId,
    required String documentId,
  }) async {
    await _ensureInitialized();
    try {
      await _networkHelper.withRetryAndTimeout(
        // ignore: deprecated_member_use
        operation: () => _databases!.deleteDocument(
          databaseId: SecondaryAppwriteConfig.databaseId,
          collectionId: collectionId,
          documentId: documentId,
        ),
        operationName: 'secondary_deleteDocument',
      );
    } on AppwriteException catch (e) {
      // 404 = المستند غير موجود أصلاً، نتجاهله
      if (e.code == 404) return;
      rethrow;
    }
  }

  /// الحصول على collection ID لكل كيان
  /// نعيد نفس أسماء collections المستخدمة في Primary لضمان التوافق
  String? getCollectionId(String entity) {
    return AppwriteConfig.collectionIdFor(entity);
  }

  /// مصدر الحقيقة الوحيد لجداول الرفع الشامل.
  ///
  /// كل مدخلة تربط اسم الكيان بدالة تجلب صفوفه من Drift وتحوّلها إلى خرائط.
  /// إضافة/إزالة جدول من النسخة الشاملة = تعديل سطر واحد هنا فقط.
  /// (سابقاً كانت قائمة `entities` و`switch` منفصلين يتباعدان مع الوقت،
  /// مما أدى لإسقاط `salary_carry_over_logs` صامتاً من النسخة "الشاملة".)
  Map<String, Future<List<Map<String, dynamic>>> Function()> _backupFetchers(
    AppDatabase db,
  ) {
    return {
      'rooms': () async =>
          (await db.select(db.rooms).get()).map(_roomToMap).toList(),
      'bookings': () async =>
          (await db.select(db.bookings).get()).map(_bookingToMap).toList(),
      'payments': () async =>
          (await db.select(db.payments).get()).map(_paymentToMap).toList(),
      'expenses': () async =>
          (await db.select(db.expenses).get()).map(_expenseToMap).toList(),
      'debts': () async =>
          (await db.select(db.debts).get()).map(_debtToMap).toList(),
      'employees': () async =>
          (await db.select(db.employees).get()).map(_employeeToMap).toList(),
      'booking_notes': () async =>
          (await db.select(db.bookingNotes).get()).map(_bookingNoteToMap).toList(),
      'booking_nights': () async =>
          (await db.select(db.bookingNights).get()).map(_nightToMap).toList(),
      'cash_transactions': () async => (await db.select(db.cashTransactions).get())
          .map(_cashTransactionToMap)
          .toList(),
      'salary_cycles': () async =>
          (await db.select(db.salaryCycles).get()).map(_salaryCycleToMap).toList(),
      'salary_payments': () async => (await db.select(db.salaryPayments).get())
          .map(_salaryPaymentToMap)
          .toList(),
      'salary_withdrawals': () async =>
          (await db.select(db.salaryWithdrawals).get())
              .map(_salaryWithdrawalToMap)
              .toList(),
      'salary_carry_over_logs': () async =>
          (await db.select(db.salaryCarryOverLogs).get())
              .map(_salaryCarryOverLogToMap)
              .toList(),
      'shift_notes': () async =>
          (await db.select(db.shiftNotes).get()).map(_shiftNoteToMap).toList(),
      'price_adjustments': () async => (await db.select(db.priceAdjustments).get())
          .map(_priceAdjustmentToMap)
          .toList(),
      'booking_price_adjustments': () async =>
          (await db.select(db.bookingPriceAdjustments).get())
              .map(_bookingPriceAdjustmentToMap)
              .toList(),
      'audit_logs': () async =>
          (await db.select(db.auditLogs).get()).map(_auditLogToMap).toList(),
      'payment_voids': () async =>
          (await db.select(db.paymentVoids).get()).map(_paymentVoidToMap).toList(),
      'guest_infos': () async =>
          (await db.select(db.guestInfos).get()).map(_guestInfoToMap).toList(),
    };
  }

  /// تجميع كل بيانات الجداول المحلية للرفع الشامل
  /// ✅ P0-3 إصلاح: استخدام اجراءات Drift الفعلية بدلاً من قائمة ثابتة فارغة
  /// ✅ يُبنى من `_backupFetchers` (مصدر حقيقة واحد) بدل قائمة + switch منفصلين.
  Future<List<_CollectionData>> _getAllCollections(AppDatabase db) async {
    final fetchers = _backupFetchers(db);
    final result = <_CollectionData>[];

    for (final entry in fetchers.entries) {
      final entity = entry.key;
      final collectionId = AppwriteConfig.collectionIdFor(entity);
      if (collectionId == null) {
        // كيان بلا collectionId مُعرّف — لا يمكن رفعه؛ نتخطّاه صراحةً مع تنبيه.
        debugPrint('⚠️ [Secondary] تخطّي "$entity": لا يوجد collectionId مطابق');
        continue;
      }

      final records = await entry.value();
      result.add(_CollectionData(
        name: entity,
        collectionId: collectionId,
        records: records,
      ));
    }

    return result;
  }

  // ── Entity to Map converters ──
  Map<String, dynamic> _roomToMap(Room r) => {
        'localUuid': r.localUuid,
        'roomNumber': r.roomNumber,
        'type': r.type,
        'price': r.price,
        'status': r.status,
        'imageUrl': r.imageUrl,
        'cleaningStatus': r.cleaningStatus,
        'lastCleanedHotelDay': r.lastCleanedHotelDay,
        'lastOccupiedHotelDay': r.lastOccupiedHotelDay,
        'requiresMaintenance': r.requiresMaintenance ? 1 : 0,
        'createdAt': r.createdAt,
        'updatedAt': r.updatedAt,
        'deletedAt': r.deletedAt,
        'lastModified': r.lastModified,
        'createdAtIso': r.createdAtIso,
        'updatedAtIso': r.updatedAtIso,
        'deletedAtIso': r.deletedAtIso,
        'version': r.version,
        'origin': r.origin,
        'deviceId': r.deviceId,
        'vectorClock': r.vectorClock,
      };

  Map<String, dynamic> _bookingToMap(Booking b) => {
        'localUuid': b.localUuid,
        'roomNumber': b.roomNumber,
        'guestName': b.guestName,
        'guestPhone': b.guestPhone,
        'status': b.status,
        'createdAt': b.createdAt,
        'updatedAt': b.updatedAt,
        'deletedAt': b.deletedAt,
        'lastModified': b.lastModified,
        'createdAtIso': b.createdAtIso,
        'updatedAtIso': b.updatedAtIso,
        'deletedAtIso': b.deletedAtIso,
        'version': b.version,
        'origin': b.origin,
        'deviceId': b.deviceId,
        'vectorClock': b.vectorClock,
        'actualCheckout': b.actualCheckout,
        'checkinDate': b.checkinDate,
        'checkoutDate': b.checkoutDate,
      };

  Map<String, dynamic> _paymentToMap(Payment p) => {
        'localUuid': p.localUuid,
        'amount': p.amount,
        'paymentDate': p.paymentDate,
        'paymentMethod': p.paymentMethod,
        'revenueType': p.revenueType,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'deletedAt': p.deletedAt,
        'lastModified': p.lastModified,
        'createdAtIso': p.createdAtIso,
        'updatedAtIso': p.updatedAtIso,
        'deletedAtIso': p.deletedAtIso,
        'version': p.version,
        'origin': p.origin,
        'deviceId': p.deviceId,
        'vectorClock': p.vectorClock,
      };

  Map<String, dynamic> _expenseToMap(Expense e) => {
        'localUuid': e.localUuid,
        'expenseType': e.expenseType,
        'amount': e.amount,
        'date': e.date,
        'description': e.description,
        'createdAt': e.createdAt,
        'updatedAt': e.updatedAt,
        'deletedAt': e.deletedAt,
        'lastModified': e.lastModified,
        'createdAtIso': e.createdAtIso,
        'updatedAtIso': e.updatedAtIso,
        'deletedAtIso': e.deletedAtIso,
        'version': e.version,
        'origin': e.origin,
        'deviceId': e.deviceId,
        'vectorClock': e.vectorClock,
      };

  Map<String, dynamic> _debtToMap(Debt d) => {
        'localUuid': d.localUuid,
        'guestName': d.guestName,
        'totalAmount': d.totalAmount,
        'remainingAmount': d.remainingAmount,
        'createdAt': d.createdAt,
        'updatedAt': d.updatedAt,
        'deletedAt': d.deletedAt,
        'lastModified': d.lastModified,
        'createdAtIso': d.createdAtIso,
        'updatedAtIso': d.updatedAtIso,
        'deletedAtIso': d.deletedAtIso,
        'version': d.version,
        'origin': d.origin,
        'deviceId': d.deviceId,
        'vectorClock': d.vectorClock,
      };

  Map<String, dynamic> _employeeToMap(Employee e) => {
        'localUuid': e.localUuid,
        'name': e.name,
        'basicSalary': e.basicSalary,
        'position': e.position,
        'phone': e.phone,
        'createdAt': e.createdAt,
        'updatedAt': e.updatedAt,
        'deletedAt': e.deletedAt,
        'lastModified': e.lastModified,
        'createdAtIso': e.createdAtIso,
        'updatedAtIso': e.updatedAtIso,
        'deletedAtIso': e.deletedAtIso,
        'version': e.version,
        'origin': e.origin,
        'deviceId': e.deviceId,
        'vectorClock': e.vectorClock,
      };

  Map<String, dynamic> _bookingNoteToMap(BookingNote n) => {
        'localUuid': n.localUuid,
        'noteText': n.noteText,
        'bookingId': n.bookingId,
        'createdAt': n.createdAt,
        'updatedAt': n.updatedAt,
        'deletedAt': n.deletedAt,
        'lastModified': n.lastModified,
        'createdAtIso': n.createdAtIso,
        'updatedAtIso': n.updatedAtIso,
        'deletedAtIso': n.deletedAtIso,
        'version': n.version,
        'origin': n.origin,
        'deviceId': n.deviceId,
        'vectorClock': n.vectorClock,
      };

  Map<String, dynamic> _nightToMap(BookingNight n) => {
        'localUuid': n.localUuid,
        'nightStart': n.nightStart,
        'nightEnd': n.nightEnd,
        'nightlyRate': n.nightlyRate,
        'bookingLocalId': n.bookingLocalId,
        'hotelDayKey': n.hotelDayKey,
        'createdAt': n.createdAt,
        'updatedAt': n.updatedAt,
        'deletedAt': n.deletedAt,
        'lastModified': n.lastModified,
        'createdAtIso': n.createdAtIso,
        'updatedAtIso': n.updatedAtIso,
        'deletedAtIso': n.deletedAtIso,
        'version': n.version,
        'origin': n.origin,
        'deviceId': n.deviceId,
        'vectorClock': n.vectorClock,
      };

  Map<String, dynamic> _cashTransactionToMap(CashTransaction c) => {
        'localUuid': c.localUuid,
        'amount': c.amount,
        'transactionType': c.transactionType,
        'createdAt': c.createdAt,
        'updatedAt': c.updatedAt,
        'deletedAt': c.deletedAt,
        'lastModified': c.lastModified,
        'createdAtIso': c.createdAtIso,
        'updatedAtIso': c.updatedAtIso,
        'deletedAtIso': c.deletedAtIso,
        'version': c.version,
        'origin': c.origin,
        'deviceId': c.deviceId,
        'vectorClock': c.vectorClock,
      };

  Map<String, dynamic> _salaryCycleToMap(SalaryCycle s) => {
        'localUuid': s.localUuid,
        'cycleKey': s.cycleKey,
        'hotelDayStart': s.hotelDayStart,
        'hotelDayEnd': s.hotelDayEnd,
        'expectedAmount': s.expectedAmount,
        'actualPaid': s.actualPaid,
        'remainingAmount': s.remainingAmount,
        'status': s.status,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'version': s.version,
        'origin': s.origin,
        'deviceId': s.deviceId,
        'vectorClock': s.vectorClock,
      };

  Map<String, dynamic> _salaryPaymentToMap(SalaryPayment s) => {
        'localUuid': s.localUuid,
        'paymentDateIso': s.paymentDateIso,
        'amount': s.amount,
        'cycleId': s.cycleId,
        'method': s.method,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'version': s.version,
        'origin': s.origin,
        'deviceId': s.deviceId,
        'vectorClock': s.vectorClock,
      };

  Map<String, dynamic> _salaryWithdrawalToMap(SalaryWithdrawal s) => {
        'localUuid': s.localUuid,
        'amount': s.amount,
        'withdrawDate': s.withdrawDate,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'version': s.version,
        'origin': s.origin,
        'deviceId': s.deviceId,
        'vectorClock': s.vectorClock,
      };

  Map<String, dynamic> _salaryCarryOverLogToMap(SalaryCarryOverLog s) => {
        'localUuid': s.localUuid,
        'employeeId': s.employeeId,
        'amount': s.amount,
        'previousCycleStart': s.previousCycleStart,
        'previousCycleEnd': s.previousCycleEnd,
        'newCycleStart': s.newCycleStart,
        'newCycleEnd': s.newCycleEnd,
        'reason': s.reason,
        'carriedAt': s.carriedAt,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'version': s.version,
        'origin': s.origin,
        'deviceId': s.deviceId,
        'vectorClock': s.vectorClock,
      };

  Map<String, dynamic> _shiftNoteToMap(ShiftNote s) => {
        'localUuid': s.localUuid,
        'title': s.title,
        'content': s.content,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'version': s.version,
        'origin': s.origin,
        'deviceId': s.deviceId,
        'vectorClock': s.vectorClock,
      };

  Map<String, dynamic> _priceAdjustmentToMap(PriceAdjustment p) => {
        'localUuid': p.localUuid,
        'targetType': p.targetType,
        'targetUuid': p.targetUuid,
        'adjustmentType': p.adjustmentType,
        'previousValue': p.previousValue,
        'newValue': p.newValue,
        'effectiveDate': p.effectiveDate,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'deletedAt': p.deletedAt,
        'lastModified': p.lastModified,
        'createdAtIso': p.createdAtIso,
        'updatedAtIso': p.updatedAtIso,
        'deletedAtIso': p.deletedAtIso,
        'version': p.version,
        'origin': p.origin,
        'deviceId': p.deviceId,
        'vectorClock': p.vectorClock,
      };

  Map<String, dynamic> _bookingPriceAdjustmentToMap(BookingPriceAdjustment b) => {
        'localUuid': b.localUuid,
        'amount': b.amount,
        'reason': b.reason,
        'createdAt': b.createdAt,
        'updatedAt': b.updatedAt,
        'deletedAt': b.deletedAt,
        'lastModified': b.lastModified,
        'createdAtIso': b.createdAtIso,
        'updatedAtIso': b.updatedAtIso,
        'deletedAtIso': b.deletedAtIso,
        'version': b.version,
        'origin': b.origin,
        'deviceId': b.deviceId,
        'vectorClock': b.vectorClock,
      };

  Map<String, dynamic> _auditLogToMap(AuditLog a) => {
        'localUuid': a.localUuid,
        'operationType': a.operationType,
        'entityType': a.entityType,
        'performedBy': a.performedBy,
        'timestamp': a.timestamp,
        'createdAt': a.createdAt,
        'deviceId': a.deviceId,
      };

  Map<String, dynamic> _paymentVoidToMap(PaymentVoid p) => {
        'localUuid': p.localUuid,
        'voidReason': p.voidReason,
        'voidedAt': p.voidedAt,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'deletedAt': p.deletedAt,
        'lastModified': p.lastModified,
        'createdAtIso': p.createdAtIso,
        'updatedAtIso': p.updatedAtIso,
        'deletedAtIso': p.deletedAtIso,
        'version': p.version,
        'origin': p.origin,
        'deviceId': p.deviceId,
        'vectorClock': p.vectorClock,
      };

  Map<String, dynamic> _guestInfoToMap(GuestInfo g) => {
        'localUuid': g.localUuid,
        'guestName': g.guestName,
        'roomNumber': g.roomNumber,
        'nationality': g.nationality,
        'idNumber': g.idNumber,
        'createdAt': g.createdAt,
        'updatedAt': g.updatedAt,
        'deletedAt': g.deletedAt,
        'lastModified': g.lastModified,
        'createdAtIso': g.createdAtIso,
        'updatedAtIso': g.updatedAtIso,
        'deletedAtIso': g.deletedAtIso,
        'version': g.version,
        'origin': g.origin,
        'deviceId': g.deviceId,
        'vectorClock': g.vectorClock,
      };
}

/// نتيجة اختبار الاتصال
class ConnectionTestResult {
  ConnectionTestResult({required this.success, required this.message, this.latencyMs});
  final bool success;
  final String message;
  final int? latencyMs;
}

/// إحصائيات رفع نسخة شاملة
class FullBackupStats {
  int totalCollections = 0;
  int fullySuccessfulCollections = 0;
  int failedCollections = 0;
  int successCount = 0;
  int failureCount = 0;
  String? error;
  final List<String> collectionNames = [];
  final List<Map<String, dynamic>> collectionDetails = [];
  final Map<String, List<FullBackupFailure>> failuresByCollection = {};
  final List<FullBackupFailure> failedRecords = [];
  final Map<String, int> errorsByReason = {};
}

/// خطأ في رفع سجل واحد
class FullBackupFailure {
  FullBackupFailure({this.documentId, required this.reason, this.collectionName});
  final String? documentId;
  final String reason;
  final String? collectionName;
}

/// بيانات جدول للرفع الشامل
class _CollectionData {
  _CollectionData({required this.name, required this.collectionId, required this.records});
  final String name;
  final String collectionId;
  final List<Map<String, dynamic>> records;
}

/// خطأ في رفع سجل واحد (للإحصائيات)
final class FullBackupRecordError {
  FullBackupRecordError({required this.documentId, required this.reason, required this.collectionName});
  final String? documentId;
  final String reason;
  final String collectionName;
}
