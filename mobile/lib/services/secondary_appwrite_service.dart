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
import 'package:shared_preferences/shared_preferences.dart';

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
            FullBackupFailure(reason: reason, collectionName: coll.name),
          );
          stats.errorsByReason[reason] = (stats.errorsByReason[reason] ?? 0) + 1;
          continue;
        }

        try {
          // ✅ P0: استخدام sanitizePayload بدلاً من filterPayloadForCollection
          // لضمان تحويل الأنواع (double→int), تحويل camelCase, إزالة الحقول الداخلية.
          final sanitized = AppwriteSyncUtils.sanitizePayload(
            coll.name,
            record,
            collectionId: coll.collectionId,
          );
          // ✅ P1: إضافة syncTimestamp + idempotencyKey—حقول كانت مفقودة من ToMaps
          final enhancedData = Map<String, dynamic>.from(sanitized);
          final now = DateTime.now().millisecondsSinceEpoch;
          enhancedData['syncTimestamp'] ??= now;
          enhancedData['idempotencyKey'] ??=
              'backup_${coll.name}_${documentId}_$now';
          enhancedData['sync_origin'] ??= 'secondary_backup';
          await upsertDocument(
            collectionId: coll.collectionId,
            documentId: documentId,
            data: enhancedData,
          );
          successCount++;
        } catch (e) {
          failureCount++;
          final reason = e.toString();
          final failure = FullBackupFailure(
            documentId: documentId,
            reason: reason,
            collectionName: coll.name,
            timestamp: DateTime.now(),
          );
          stats.failuresByCollection.putIfAbsent(coll.name, () => []).add(failure);
          // ✅ P3: failedRecords كانت تبقى فارغة—الآن تُملأ بكل فشل
          stats.failedRecords.add(failure);
          // ✅ توسيع error truncation من 100→500 حرف لتحليل أفضل
          final reasonShort = reason.length > 500 ? reason.substring(0, 500) : reason;
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

    // ✅ الخطوة 1.5: قبل الإنشاء، جرّب تحديث الـ ID البديل (بدون شرطات)
    // لسدّ مسار التكرار: update(بشرطات)=404 ثم create(بشرطات) ينجح رغم وجود
    // نسخة بدون شرطات. نحدّث في مكانه بدل إنشاء نسخة مكررة.
    if (altDocumentId.isNotEmpty) {
      try {
        return await doUpdate(altDocumentId, suppressErrorLog: true);
      } on AppwriteException catch (altError) {
        if (!isNotFound(altError)) { rethrow; }
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
        // ✅ P1-4 fix: إضافة await هنا — بدونه يُعاد الـ Future فوراً ولا
        // يلتقط catch أي فشل async (النظام الأساسي يستخدم return await).
        try { return await doUpdate(documentId, suppressErrorLog: true); }
        catch (_) { rethrow; }
      }
      rethrow;
    }
  }

  /// حذف مستند من Secondary
  ///
  /// ✅ P1-2 fix: الحذف idempotent — استخدام نفس `isNotFound()` المستخدم
  /// في upsertDocument بدل فحص `code == 404` فقط. الثانوي يُملأ كسولاً
  /// (سجلات كثيرة لم تُدفَع إليه بعد)، فحذف سجل غير موجود شائع جداً
  /// ولا يجب أن يُعامل كخطأ.
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
      // ✅ P1-2: نفس منطق isNotFound في upsert — 404 أو document_not_found
      // بأي صيغة (code أو type أو toString).
      if (e.code == 404 ||
          (e.type ?? '').contains('document_not_found') ||
          e.toString().contains('document_not_found')) {
        return; // المستند غير موجود أصلاً — الحذف idempotent ✓
      }
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
      'app_settings': () async => [
            await _appSettingsToMap(),
          ],
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
        'serverId': r.serverId,
        'createdAt': r.createdAt,
        'updatedAt': r.updatedAt,
        'deletedAt': r.deletedAt,
        'lastModified': r.lastModified,
        'createdAtIso': r.createdAtIso,
        'updatedAtIso': r.updatedAtIso,
        'deletedAtIso': r.deletedAtIso,
        'createdAtEpoch': r.createdAtEpoch,
        'lastModifiedEpoch': r.lastModifiedEpoch,
        'version': r.version,
        'origin': r.origin,
        'vectorClock': r.vectorClock,
        'deviceId': r.deviceId,
        'roomNumber': r.roomNumber,
        'type': r.type,
        'price': r.price,
        'status': r.status,
        'imageUrl': r.imageUrl,
        'cleaningStatus': r.cleaningStatus,
        'lastCleanedHotelDay': r.lastCleanedHotelDay,
        'lastOccupiedHotelDay': r.lastOccupiedHotelDay,
        'requiresMaintenance': r.requiresMaintenance,
      };

    Map<String, dynamic> _bookingToMap(Booking b) => {
        'localUuid': b.localUuid,
        'serverId': b.serverId,
        'createdAt': b.createdAt,
        'updatedAt': b.updatedAt,
        'deletedAt': b.deletedAt,
        'lastModified': b.lastModified,
        'createdAtIso': b.createdAtIso,
        'updatedAtIso': b.updatedAtIso,
        'deletedAtIso': b.deletedAtIso,
        'createdAtEpoch': b.createdAtEpoch,
        'lastModifiedEpoch': b.lastModifiedEpoch,
        'version': b.version,
        'origin': b.origin,
        'vectorClock': b.vectorClock,
        'deviceId': b.deviceId,
        'serverBookingId': b.serverBookingId,
        'roomNumber': b.roomNumber,
        'guestName': b.guestName,
        'guestPhone': b.guestPhone,
        'guestIdType': b.guestIdType,
        'guestIdNumber': b.guestIdNumber,
        'guestIdIssueDate': b.guestIdIssueDate,
        'guestIdIssuePlace': b.guestIdIssuePlace,
        'guestNationality': b.guestNationality,
        'guestEmail': b.guestEmail,
        'guestAddress': b.guestAddress,
        'checkinDate': b.checkinDate,
        'checkoutDate': b.checkoutDate,
        'actualCheckout': b.actualCheckout,
        'status': b.status,
        'notes': b.notes,
        'discount': b.discount,
        'discountType': b.discountType,
        'discountStartDate': b.discountStartDate,
        'expectedNights': b.expectedNights,
        'calculatedNights': b.calculatedNights,
        'totalNightsCached': b.totalNightsCached,
        'stayDurationIso': b.stayDurationIso,
        'lastNightEpoch': b.lastNightEpoch,
        'isOverdue': b.isOverdue,
        'needsCheckoutReview': b.needsCheckoutReview,
        'totalDueCached': b.totalDueCached,
        'totalPaidCached': b.totalPaidCached,
        'remainingBalanceCached': b.remainingBalanceCached,
        'isFullyPaid': b.isFullyPaid,
        'hotelDayCheckin': b.hotelDayCheckin,
        'hotelDayCheckout': b.hotelDayCheckout,
      };

    Map<String, dynamic> _paymentToMap(Payment p) => {
        'localUuid': p.localUuid,
        'serverId': p.serverId,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'deletedAt': p.deletedAt,
        'lastModified': p.lastModified,
        'createdAtIso': p.createdAtIso,
        'updatedAtIso': p.updatedAtIso,
        'deletedAtIso': p.deletedAtIso,
        'createdAtEpoch': p.createdAtEpoch,
        'lastModifiedEpoch': p.lastModifiedEpoch,
        'version': p.version,
        'origin': p.origin,
        'vectorClock': p.vectorClock,
        'deviceId': p.deviceId,
        'serverPaymentId': p.serverPaymentId,
        'bookingLocalId': p.bookingLocalId,
        'serverBookingId': p.serverBookingId,
        'roomNumber': p.roomNumber,
        'amount': p.amount,
        'paymentDate': p.paymentDate,
        'notes': p.notes,
        'paymentMethod': p.paymentMethod,
        'revenueType': p.revenueType,
        'cashTransactionLocalId': p.cashTransactionLocalId,
        'cashTransactionServerId': p.cashTransactionServerId,
        'referenceNumber': p.referenceNumber,
        'hotelDayKey': p.hotelDayKey,
        'isPendingBalance': p.isPendingBalance,
        'linkedDebtUuid': p.linkedDebtUuid,
        'bookingUuidCache': p.bookingUuidCache,
        'discountAmount': p.discountAmount,
        'discountStartDate': p.discountStartDate,
        'isVoided': p.isVoided,
        'voidedAt': p.voidedAt,
        'voidedBy': p.voidedBy,
      };

    Map<String, dynamic> _expenseToMap(Expense e) => {
        'localUuid': e.localUuid,
        'serverId': e.serverId,
        'createdAt': e.createdAt,
        'updatedAt': e.updatedAt,
        'deletedAt': e.deletedAt,
        'lastModified': e.lastModified,
        'createdAtIso': e.createdAtIso,
        'updatedAtIso': e.updatedAtIso,
        'deletedAtIso': e.deletedAtIso,
        'createdAtEpoch': e.createdAtEpoch,
        'lastModifiedEpoch': e.lastModifiedEpoch,
        'version': e.version,
        'origin': e.origin,
        'vectorClock': e.vectorClock,
        'deviceId': e.deviceId,
        'expenseType': e.expenseType,
        'relatedId': e.relatedId,
        'description': e.description,
        'amount': e.amount,
        'date': e.date,
        'cashTransactionId': e.cashTransactionId,
        'hotelDayKey': e.hotelDayKey,
        'categoryUuid': e.categoryUuid,
        'cashFlowUuid': e.cashFlowUuid,
        'isAutoGenerated': e.isAutoGenerated,
        'employeeUuid': e.employeeUuid,
      };

    Map<String, dynamic> _debtToMap(Debt d) => {
        'localUuid': d.localUuid,
        'serverId': d.serverId,
        'createdAt': d.createdAt,
        'updatedAt': d.updatedAt,
        'deletedAt': d.deletedAt,
        'lastModified': d.lastModified,
        'createdAtIso': d.createdAtIso,
        'updatedAtIso': d.updatedAtIso,
        'deletedAtIso': d.deletedAtIso,
        'createdAtEpoch': d.createdAtEpoch,
        'lastModifiedEpoch': d.lastModifiedEpoch,
        'version': d.version,
        'origin': d.origin,
        'vectorClock': d.vectorClock,
        'deviceId': d.deviceId,
        'bookingLocalId': d.bookingLocalId,
        'guestName': d.guestName,
        'checkinDate': d.checkinDate,
        'checkoutDate': d.checkoutDate,
        'dateRecorded': d.dateRecorded,
        'debtReason': d.debtReason,
        'totalAmount': d.totalAmount,
        'paidAmount': d.paidAmount,
        'remainingAmount': d.remainingAmount,
        'paymentDate': d.paymentDate,
        'isSettled': d.isSettled,
        'pledge': d.pledge,
        'pledgeType': d.pledgeType,
        'amount': d.totalAmount,
        'note': d.note,
        'debtUuid': d.debtUuid,
        'hotelDayOpened': d.hotelDayOpened,
        'hotelDayClosed': d.hotelDayClosed,
        'isFromAutoFix': d.isFromAutoFix,
        'settlementConfirmed': d.settlementConfirmed,
      };

    Map<String, dynamic> _employeeToMap(Employee e) => {
        'localUuid': e.localUuid,
        'serverId': e.serverId,
        'createdAt': e.createdAt,
        'updatedAt': e.updatedAt,
        'deletedAt': e.deletedAt,
        'lastModified': e.lastModified,
        'createdAtIso': e.createdAtIso,
        'updatedAtIso': e.updatedAtIso,
        'deletedAtIso': e.deletedAtIso,
        'createdAtEpoch': e.createdAtEpoch,
        'lastModifiedEpoch': e.lastModifiedEpoch,
        'version': e.version,
        'origin': e.origin,
        'vectorClock': e.vectorClock,
        'deviceId': e.deviceId,
        'name': e.name,
        'basicSalary': e.basicSalary,
        'position': e.position,
        'phone': e.phone,
        'hireDate': e.hireDate,
        'status': e.status,
        'terminationDate': e.terminationDate,
        'terminationReason': e.terminationReason,
        'EmployeeID': e.employeeID,
      };

    Map<String, dynamic> _bookingNoteToMap(BookingNote b) => {
        'localUuid': b.localUuid,
        'serverId': b.serverId,
        'createdAt': b.createdAt,
        'updatedAt': b.updatedAt,
        'deletedAt': b.deletedAt,
        'lastModified': b.lastModified,
        'createdAtIso': b.createdAtIso,
        'updatedAtIso': b.updatedAtIso,
        'deletedAtIso': b.deletedAtIso,
        'createdAtEpoch': b.createdAtEpoch,
        'lastModifiedEpoch': b.lastModifiedEpoch,
        'version': b.version,
        'origin': b.origin,
        'vectorClock': b.vectorClock,
        'deviceId': b.deviceId,
        'bookingId': b.bookingId,
        'noteText': b.noteText,
        'alertType': b.alertType,
        'alertUntil': b.alertUntil,
        'isActive': b.isActive,
      };

    Map<String, dynamic> _nightToMap(BookingNight n) => {
        'localUuid': n.localUuid,
        'serverId': n.serverId,
        'createdAt': n.createdAt,
        'updatedAt': n.updatedAt,
        'deletedAt': n.deletedAt,
        'lastModified': n.lastModified,
        'createdAtIso': n.createdAtIso,
        'updatedAtIso': n.updatedAtIso,
        'deletedAtIso': n.deletedAtIso,
        'createdAtEpoch': n.createdAtEpoch,
        'lastModifiedEpoch': n.lastModifiedEpoch,
        'version': n.version,
        'origin': n.origin,
        'vectorClock': n.vectorClock,
        'deviceId': n.deviceId,
        'bookingLocalId': n.bookingLocalId,
        'hotelDayKey': n.hotelDayKey,
        'nightStart': n.nightStart,
        'nightEnd': n.nightEnd,
        'nightlyRate': n.nightlyRate,
        'sequence': n.sequence,
        'isProcessedByAutoFix': n.isProcessedByAutoFix,
        'baseRate': n.baseRate,
        'adjustment': n.adjustment,
        'finalRate': n.finalRate,
        'appliedAdjustmentUuid': n.appliedAdjustmentUuid,
        'appliedAdjustmentsJson': n.appliedAdjustmentsJson,
      };

    Map<String, dynamic> _cashTransactionToMap(CashTransaction c) => {
        'localUuid': c.localUuid,
        'serverId': c.serverId,
        'createdAt': c.createdAt,
        'updatedAt': c.updatedAt,
        'deletedAt': c.deletedAt,
        'lastModified': c.lastModified,
        'createdAtIso': c.createdAtIso,
        'updatedAtIso': c.updatedAtIso,
        'deletedAtIso': c.deletedAtIso,
        'createdAtEpoch': c.createdAtEpoch,
        'lastModifiedEpoch': c.lastModifiedEpoch,
        'version': c.version,
        'origin': c.origin,
        'vectorClock': c.vectorClock,
        'deviceId': c.deviceId,
        'registerId': c.registerId,
        'transactionType': c.transactionType,
        'amount': c.amount,
        'referenceType': c.referenceType,
        'referenceId': c.referenceId,
        'description': c.description,
        'transactionTime': c.transactionTime,
        'createdBy': c.createdBy,
      };

    Map<String, dynamic> _salaryCycleToMap(SalaryCycle s) => {
        'localUuid': s.localUuid,
        'serverId': s.serverId,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'createdAtEpoch': s.createdAtEpoch,
        'lastModifiedEpoch': s.lastModifiedEpoch,
        'version': s.version,
        'origin': s.origin,
        'vectorClock': s.vectorClock,
        'deviceId': s.deviceId,
        'employeeId': s.employeeId,
        'cycleKey': s.cycleKey,
        'hotelDayStart': s.hotelDayStart,
        'hotelDayEnd': s.hotelDayEnd,
        'expectedAmount': s.expectedAmount,
        'actualPaid': s.actualPaid,
        'remainingAmount': s.remainingAmount,
        'status': s.status,
      };

    Map<String, dynamic> _salaryPaymentToMap(SalaryPayment s) => {
        'localUuid': s.localUuid,
        'serverId': s.serverId,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'createdAtEpoch': s.createdAtEpoch,
        'lastModifiedEpoch': s.lastModifiedEpoch,
        'version': s.version,
        'origin': s.origin,
        'vectorClock': s.vectorClock,
        'deviceId': s.deviceId,
        'cycleId': s.cycleId,
        'amount': s.amount,
        'hotelDayKey': s.hotelDayKey,
        'paymentDateIso': s.paymentDateIso,
        'method': s.method,
        'isAutoGenerated': s.isAutoGenerated,
      };

    Map<String, dynamic> _salaryWithdrawalToMap(SalaryWithdrawal s) => {
        'localUuid': s.localUuid,
        'serverId': s.serverId,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'createdAtEpoch': s.createdAtEpoch,
        'lastModifiedEpoch': s.lastModifiedEpoch,
        'version': s.version,
        'origin': s.origin,
        'vectorClock': s.vectorClock,
        'deviceId': s.deviceId,
        'employeeId': s.employeeId,
        'amount': s.amount,
        'withdrawDate': s.withdrawDate,
        'reason': s.reason,
        'hotelDayKey': s.hotelDayKey,
        'withdrawalType': s.withdrawalType,
        'description': s.description,
        'expenseId': s.expenseId,
      };

    Map<String, dynamic> _salaryCarryOverLogToMap(SalaryCarryOverLog s) => {
        'localUuid': s.localUuid,
        'serverId': s.serverId,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'createdAtEpoch': s.createdAtEpoch,
        'lastModifiedEpoch': s.lastModifiedEpoch,
        'version': s.version,
        'origin': s.origin,
        'vectorClock': s.vectorClock,
        'deviceId': s.deviceId,
        'employeeId': s.employeeId,
        'amount': s.amount,
        'previousCycleStart': s.previousCycleStart,
        'previousCycleEnd': s.previousCycleEnd,
        'newCycleStart': s.newCycleStart,
        'newCycleEnd': s.newCycleEnd,
        'reason': s.reason,
        'carriedAt': s.carriedAt,
      };

    Map<String, dynamic> _shiftNoteToMap(ShiftNote s) => {
        'localUuid': s.localUuid,
        'serverId': s.serverId,
        'createdAt': s.createdAt,
        'updatedAt': s.updatedAt,
        'deletedAt': s.deletedAt,
        'lastModified': s.lastModified,
        'createdAtIso': s.createdAtIso,
        'updatedAtIso': s.updatedAtIso,
        'deletedAtIso': s.deletedAtIso,
        'createdAtEpoch': s.createdAtEpoch,
        'lastModifiedEpoch': s.lastModifiedEpoch,
        'version': s.version,
        'origin': s.origin,
        'vectorClock': s.vectorClock,
        'deviceId': s.deviceId,
        'title': s.title,
        'content': s.content,
        'priority': s.priority,
        'shiftType': s.shiftType,
        'isRead': s.isRead,
        'expiresAt': s.expiresAt,
        'createdBy': s.createdBy,
      };

    Map<String, dynamic> _priceAdjustmentToMap(PriceAdjustment p) => {
        'localUuid': p.localUuid,
        'serverId': p.serverId,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'deletedAt': p.deletedAt,
        'lastModified': p.lastModified,
        'createdAtIso': p.createdAtIso,
        'updatedAtIso': p.updatedAtIso,
        'deletedAtIso': p.deletedAtIso,
        'createdAtEpoch': p.createdAtEpoch,
        'lastModifiedEpoch': p.lastModifiedEpoch,
        'version': p.version,
        'origin': p.origin,
        'vectorClock': p.vectorClock,
        'deviceId': p.deviceId,
        'targetType': p.targetType,
        'targetUuid': p.targetUuid,
        'adjustmentType': p.adjustmentType,
        'previousValue': p.previousValue,
        'newValue': p.newValue,
        'reason': p.reason,
        'effectiveDate': p.effectiveDate,
        'appliedBy': p.appliedBy,
        'hotelDayKey': p.hotelDayKey,
        'isReversed': p.isReversed,
        'reversedAt': p.reversedAt,
        'reversedBy': p.reversedBy,
      };

    Map<String, dynamic> _bookingPriceAdjustmentToMap(BookingPriceAdjustment b) => {
        'localUuid': b.localUuid,
        'serverId': b.serverId,
        'createdAt': b.createdAt,
        'updatedAt': b.updatedAt,
        'deletedAt': b.deletedAt,
        'lastModified': b.lastModified,
        'createdAtIso': b.createdAtIso,
        'updatedAtIso': b.updatedAtIso,
        'deletedAtIso': b.deletedAtIso,
        'createdAtEpoch': b.createdAtEpoch,
        'lastModifiedEpoch': b.lastModifiedEpoch,
        'version': b.version,
        'origin': b.origin,
        'vectorClock': b.vectorClock,
        'deviceId': b.deviceId,
        'bookingLocalUuid': b.bookingLocalUuid,
        'bookingUuid': b.bookingLocalUuid,
        'bookingLocalId': b.bookingLocalId,
        'appliedAt': b.createdAt,
        'roomNumber': b.roomNumber,
        'adjustmentType': b.adjustmentType,
        'adjustmentMode': b.adjustmentMode,
        'amount': b.amount,
        'effectiveHotelDay': b.effectiveHotelDay,
        'endHotelDay': b.endHotelDay,
        'isActive': b.isActive,
        'reason': b.reason,
        'appliedBy': b.appliedBy,
        'cancelledAt': b.cancelledAt,
        'cancelledBy': b.cancelledBy,
      };

    Map<String, dynamic> _auditLogToMap(AuditLog a) => {
        'localUuid': a.localUuid,
        'serverId': a.serverId,
        'createdAt': a.createdAt,
        'updatedAt': a.updatedAt,
        'deletedAt': a.deletedAt,
        'lastModified': a.lastModified,
        'createdAtIso': a.createdAtIso,
        'updatedAtIso': a.updatedAtIso,
        'deletedAtIso': a.deletedAtIso,
        'createdAtEpoch': a.createdAtEpoch,
        'lastModifiedEpoch': a.lastModifiedEpoch,
        'version': a.version,
        'origin': a.origin,
        'vectorClock': a.vectorClock,
        'deviceId': a.deviceId,
        'idempotencyKey': a.idempotencyKey,
        'operationType': a.operationType,
        'entityType': a.entityType,
        'entityUuid': a.entityUuid,
        'entityId': a.entityId,
        'previousState': a.previousState,
        'newState': a.newState,
        'changedFields': a.changedFields,
        'performedBy': a.performedBy,
        'ipAddress': a.ipAddress,
        'hotelDayKey': a.hotelDayKey,
        'timestamp': a.timestamp,
        'timestampIso': a.timestampIso,
        'isFinancial': a.isFinancial,
        'amountImpact': a.amountImpact,
        // ✅ حقول إضافية للتوافق مع مخطط Appwrite
        'action': a.operationType,
        'sync_origin': 'audit',
      };

    Map<String, dynamic> _paymentVoidToMap(PaymentVoid p) => {
        'localUuid': p.localUuid,
        'serverId': p.serverId,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'deletedAt': p.deletedAt,
        'lastModified': p.lastModified,
        'createdAtIso': p.createdAtIso,
        'updatedAtIso': p.updatedAtIso,
        'deletedAtIso': p.deletedAtIso,
        'createdAtEpoch': p.createdAtEpoch,
        'lastModifiedEpoch': p.lastModifiedEpoch,
        'version': p.version,
        'origin': p.origin,
        'vectorClock': p.vectorClock,
        'deviceId': p.deviceId,
        'originalPaymentUuid': p.originalPaymentUuid,
        'originalPaymentId': p.originalPaymentId,
        'bookingUuid': p.bookingUuid,
        'voidedAmount': p.voidedAmount,
        'voidReason': p.voidReason,
        'voidedBy': p.voidedBy,
        'voidedAt': p.voidedAt,
        'voidedAtIso': p.voidedAtIso,
        'hotelDayKey': p.hotelDayKey,
        'reversalPaymentUuid': p.reversalPaymentUuid,
        'approvedBy': p.approvedBy,
        'note': p.note,
        'originalAmount': p.originalAmount,
        'paymentUuid': p.paymentUuid,
      };

    /// تحويل إعدادات التطبيق من SharedPreferences إلى خريطة للرفع
    /// app_settings مخزّن في SharedPreferences (ليس Drift) كمستند واحد
    /// بمعرّف ثابت 'whatsapp_settings' — نفس النمط المستخدم في Primary sync.
    Future<Map<String, dynamic>> _appSettingsToMap() async {
      final prefs = await SharedPreferences.getInstance();
      final now = DateTime.now().millisecondsSinceEpoch;
      final deviceId = prefs.getString('appwrite_delta_device_id') ?? 'default';

      return {
        'localUuid': 'whatsapp_settings',
        'key': 'whatsapp_settings',
        'value': '',
        'hotel_name': prefs.getString('hotel_name') ?? 'فندق مارينا بلازا',
        'hotel_cutoff_hour': prefs.getInt('hotel_cutoff_hour') ?? 14,
        'dark_mode': prefs.getBool('dark_mode') ?? false,
        'wa_api_type': prefs.getString('wa_api_type') ?? 'greenapi',
        'wa_api_base_url': prefs.getString('wa_api_base_url') ?? '',
        'wa_api_instance_id': prefs.getString('wa_api_instance_id') ?? '',
        'wa_custom_url_template': prefs.getString('wa_custom_url_template') ?? '',
        'wa_sendzen_api_key': prefs.getString('wa_sendzen_api_key') ?? '',
        'wa_sendzen_from_number': prefs.getString('wa_sendzen_from_number') ?? '',
        'telegram_enabled': prefs.getBool('telegram_enabled') ?? false,
        'telegram_chat_id': prefs.getString('telegram_chat_id') ?? '',
        'telegram_notifications_enabled': prefs.getBool('telegram_notifications_enabled') ?? false,
        'telegram_daily_report_enabled': prefs.getBool('telegram_daily_report_enabled') ?? false,
        'telegram_daily_report_time': prefs.getString('telegram_daily_report_time') ?? '',
        'lark_enabled': prefs.getBool('lark_enabled') ?? false,
        'lark_app_id': prefs.getString('lark_app_id') ?? '',
        'lark_webhook_url': prefs.getString('lark_webhook_url') ?? '',
        'lark_daily_report_enabled': prefs.getBool('lark_daily_report_enabled') ?? false,
        'lark_daily_report_time': prefs.getString('lark_daily_report_time') ?? '08:00',
        'lark_daily_report_chat_id': prefs.getString('lark_daily_report_chat_id') ?? '',
        'appwrite_sync_interval': prefs.getInt('appwrite_sync_interval') ?? 15,
        // حقول المزامنة الأساسية (SyncFields)
        'deviceId': deviceId,
        'serverId': null,
        'createdAt': now,
        'updatedAt': now,
        'deletedAt': null,
        'lastModified': now,
        'lastModifiedEpoch': now,
        'createdAtEpoch': now,
        'createdAtIso': DateTime.now().toIso8601String(),
        'updatedAtIso': DateTime.now().toIso8601String(),
        'deletedAtIso': null,
        'version': 1,
        'origin': 'local',
        'vectorClock': '{}',
        'idempotencyKey': null,
        'syncTimestamp': now,
        'sync_origin': 'secondary_backup',
      };
    }

    Map<String, dynamic> _guestInfoToMap(GuestInfo g) => {
        'localUuid': g.localUuid,
        'serverId': g.serverId,
        'createdAt': g.createdAt,
        'updatedAt': g.updatedAt,
        'deletedAt': g.deletedAt,
        'lastModified': g.lastModified,
        'createdAtIso': g.createdAtIso,
        'updatedAtIso': g.updatedAtIso,
        'deletedAtIso': g.deletedAtIso,
        'createdAtEpoch': g.createdAtEpoch,
        'lastModifiedEpoch': g.lastModifiedEpoch,
        'version': g.version,
        'origin': g.origin,
        'vectorClock': g.vectorClock,
        'deviceId': g.deviceId,
        'roomNumber': g.roomNumber,
        'guestName': g.guestName,
        'nationality': g.nationality,
        'idNumber': g.idNumber,
        'idType': g.idType,
        'issueDate': g.issueDate,
        'issuePlace': g.issuePlace,
        'governorate': g.governorate,
        'notes': g.notes,
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
  FullBackupFailure({
    this.documentId,
    required this.reason,
    this.collectionName,
    this.timestamp,
  });
  final String? documentId;
  final String reason;
  final String? collectionName;
  final DateTime? timestamp;
}

/// بيانات جدول للرفع الشامل
class _CollectionData {
  _CollectionData({required this.name, required this.collectionId, required this.records});
  final String name;
  final String collectionId;
  final List<Map<String, dynamic>> records;
}

