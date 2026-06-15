import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import 'appwrite_backup_endpoint.dart';
import 'appwrite_backup_endpoints_manager.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'local_db.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// عملية احتياطية — تستخدم لإرسال دفعة
class BackupOperation {
  BackupOperation({
    required this.tableName,
    required this.documentId,
    required this.data,
    required this.operation,
  });

  final String tableName;
  final String documentId;
  final Map<String, dynamic> data;
  final String operation;
}

/// خدمة المزامنة الاحتياطية (Slave Push Only)
///
/// تقوم بدفع البيانات إلى نقاط النهاية الثانوية بعد نجاح المزامنة الرئيسية.
/// هذه الخدمة لا تسحب بيانات (pull) — فقط إرسال (push).
class AppwriteBackupSyncService {
  factory AppwriteBackupSyncService() => _instance;
  AppwriteBackupSyncService._internal();
  static final AppwriteBackupSyncService _instance =
      AppwriteBackupSyncService._internal();

  final _logger = AppwriteLogger();

  bool _isPushing = false;

  /// هل هناك عملية دفع قيد التشغيل حالياً؟
  bool get isPushing => _isPushing;

  /// دفع البيانات إلى جميع نقاط النهاية الاحتياطية
  ///
  /// [tableName] اسم الجدول الذي تم إرساله للـ Master
  /// [data] البيانات المرسلة (بالفعل تم إرسالها للـ Master)
  /// [documentId] معرّف المستند في Appwrite
  /// [operation] نوع العملية: create / update / delete
  Future<void> pushToBackups({
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
    required String operation,
  }) async {
    if (_isPushing) return;

    final endpoints = await BackupEndpointsManager.loadEndpoints();
    if (endpoints.isEmpty) return;

    _isPushing = true;
    int successCount = 0;
    int failCount = 0;

    for (final endpoint in endpoints) {
      try {
        await _pushToEndpoint(
          endpoint: endpoint,
          tableName: tableName,
          documentId: documentId,
          data: data,
          operation: operation,
        );
        successCount++;
        _logger.info(
          '✅ Backup push to ${endpoint.name} ($tableName/$documentId)',
          tag: 'BACKUP_SYNC',
        );
      } catch (e) {
        failCount++;
        _logger.warning(
          '⚠️ Backup push failed to ${endpoint.name}: $e',
          tag: 'BACKUP_SYNC',
        );
      }
    }

    _isPushing = false;
    if (failCount > 0) {
      _logger.info(
        '📊 Backup sync: $successCount succeeded, $failCount failed',
        tag: 'BACKUP_SYNC',
      );
    }
  }

  /// دفع دفعة كاملة من البيانات إلى جميع نقاط النهاية الاحتياطية
  ///
  /// [operations] قائمة العمليات المنفذة (مع البيانات)
  Future<void> pushBatchToBackups({
    required List<BackupOperation> operations,
  }) async {
    if (_isPushing || operations.isEmpty) return;

    final endpoints = await BackupEndpointsManager.loadEndpoints();
    if (endpoints.isEmpty) return;

    _isPushing = true;

    for (final endpoint in endpoints) {
      int successCount = 0;
      int failCount = 0;

      for (final op in operations) {
        try {
          await _pushToEndpoint(
            endpoint: endpoint,
            tableName: op.tableName,
            documentId: op.documentId,
            data: op.data,
            operation: op.operation,
          );
          successCount++;
        } catch (e) {
          failCount++;
          _logger.warning(
            '⚠️ Batch backup push failed to ${endpoint.name} '
            '(${op.tableName}/${op.documentId}): $e',
            tag: 'BACKUP_SYNC',
          );
        }
      }

      _logger.info(
        '📊 Backup batch to ${endpoint.name}: '
        '$successCount succeeded, $failCount failed',
        tag: 'BACKUP_SYNC',
      );
    }

    _isPushing = false;
  }

  /// إرسال عملية واحدة إلى endpoint محدد
  Future<void> _pushToEndpoint({
    required BackupEndpoint endpoint,
    required String tableName,
    required String documentId,
    required Map<String, dynamic> data,
    required String operation,
  }) async {
    final client = Client()
        .setEndpoint(endpoint.endpoint)
        .setProject(endpoint.projectId);

    if (endpoint.apiKey.isNotEmpty) {
      client.addHeader('X-Appwrite-Key', endpoint.apiKey);
    }

    final databases = Databases(client);
    final dbId = endpoint.databaseId;

    switch (operation) {
      case 'create':
        // ignore: deprecated_member_use
        await databases.createDocument(
          databaseId: dbId,
          collectionId: tableName,
          documentId: documentId,
          data: data,
        );
      case 'update':
        try {
          // ignore: deprecated_member_use
          await databases.updateDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
            data: data,
          );
        } catch (e) { AppLogger.warning('⚠️ silent catch', tag: 'SYNC', error: e);
          _logger.warning('⚠️ فشل تحديث وثيقة احتياطية — نحاول الإنشاء', tag: 'BACKUP');
          // إذا فشل التحديث (المستند غير موجود)، نقوم بإنشائه
          // ignore: deprecated_member_use
          await databases.createDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
            data: data,
          );
        }
      case 'delete':
        try {
          // ignore: deprecated_member_use
          await databases.deleteDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
          );
        } catch (e) { AppLogger.warning('⚠️ silent catch', tag: 'SYNC', error: e);
          _logger.warning('⚠️ فشل حذف وثيقة احتياطية (قد لا تكون موجودة)', tag: 'BACKUP');
        }
    }
  }

  /// رفع جميع البيانات المحلية إلى جميع نقاط النهاية الاحتياطية (Full Push All)
  ///
  /// هذه الدالة تنفذ fullPushAllToEndpoint لكل نقطة نهاية نشطة.
  Future<Map<String, Map<String, int>>> fullPushAllToAllEndpoints({
    required AppDatabase db,
    void Function(String endpointName, String table, int current, int total)?
        onProgress,
  }) async {
    final endpoints = await BackupEndpointsManager.loadEndpoints();
    if (endpoints.isEmpty) return {};

    final allStats = <String, Map<String, int>>{};

    for (final endpoint in endpoints) {
      _logger.info(
        '🚀 بدء الرفع الشامل إلى ${endpoint.name}...',
        tag: 'BACKUP_SYNC',
      );
      final stats = await fullPushAllToEndpoint(
        db: db,
        endpoint: endpoint,
        onProgress: (table, current, total) {
          onProgress?.call(endpoint.name, table, current, total);
        },
      );
      allStats[endpoint.name] = stats;
    }

    return allStats;
  }

  /// رفع جميع البيانات المحلية إلى نقطة نهاية احتياطية (Full Push)
  ///
  /// هذه العملية تقرأ جميع السجلات من قاعدة البيانات المحلية
  /// وترفعها إلى نقطة النهاية المحددة بالترتيب الصحيح (FK order).
  /// تشمل 18 جدول شامل: rooms, employees, bookings, payments, expenses,
  /// debts, booking_notes, booking_nights, shift_notes, cash_transactions,
  /// guest_infos, salary_cycles, salary_payments, salary_withdrawals,
  /// price_adjustments, booking_price_adjustments, audit_logs, payment_voids
  ///
  /// [db] قاعدة البيانات المحلية
  /// [endpoint] نقطة النهاية الاحتياطية المستهدفة
  /// [onProgress] callback للتقدم (اختياري)
  Future<Map<String, int>> fullPushAllToEndpoint({
    required AppDatabase db,
    required BackupEndpoint endpoint,
    void Function(String table, int current, int total)? onProgress,
  }) async {
    final stats = <String, int>{
      'rooms': 0,
      'employees': 0,
      'bookings': 0,
      'payments': 0,
      'expenses': 0,
      'debts': 0,
      'booking_notes': 0,
      'booking_nights': 0,
      'shift_notes': 0,
      'cash_transactions': 0,
      'guest_infos': 0,
      'salary_cycles': 0,
      'salary_payments': 0,
      'salary_withdrawals': 0,
      'price_adjustments': 0,
      'booking_price_adjustments': 0,
      'audit_logs': 0,
      'payment_voids': 0,
      'errors': 0,
    };

    final client = Client()
        .setEndpoint(endpoint.endpoint)
        .setProject(endpoint.projectId);
    if (endpoint.apiKey.isNotEmpty) {
      client.addHeader('X-Appwrite-Key', endpoint.apiKey);
    }
    final databases = Databases(client);
    final dbId = endpoint.databaseId;

    /// دالة مساعدة لتحديث مستند موجود فقط (بدون إنشاء وثائق جديدة)
    ///
    /// في عمليات الرفع الشامل (fullPush)، نقوم بالتحديث فقط — لا ننشئ وثائق.
    /// إذا لم تكن الوثيقة موجودة يتم تجاوزها بصمت.
    Future<bool> upsert(String collection, String docId, Map<String, dynamic> data) async {
      try {
        // ignore: deprecated_member_use
        await databases.updateDocument(
          databaseId: dbId,
          collectionId: collection,
          documentId: docId,
          data: data,
        );
        return true;
      } catch (e) {
        // الوثيقة غير موجودة — تجاوز بدون إنشاء
        return false;
      }
    }

    _logger.info('🚀 بدء الرفع الشامل إلى ${endpoint.name}...', tag: 'BACKUP_SYNC');

    // ─── 1. رفع الغرف ─────────────────────────────────────────
    final rooms = await db.select(db.rooms).get();
    for (var i = 0; i < rooms.length; i++) {
      final room = rooms[i];
      if (room.deletedAt != null) continue;
      onProgress?.call('rooms', i + 1, rooms.length);
      final data = <String, dynamic>{
        'roomNumber': room.roomNumber,
        'type': room.type,
        'price': room.price,
        'status': room.status,
        'localUuid': room.localUuid,
        'createdAt': room.createdAt,
        'updatedAt': room.updatedAt,
        'lastModified': room.lastModified,
        'version': room.version,
        'origin': room.origin,
        'vectorClock': room.vectorClock,
        'cleaningStatus': room.cleaningStatus,
        'requiresMaintenance': room.requiresMaintenance,
      };
      _putIfNotNull(data, 'serverId', room.serverId);
      _putIfStringNotEmpty(data, 'imageUrl', room.imageUrl);
      _putIfStringNotEmpty(data, 'lastCleanedHotelDay', room.lastCleanedHotelDay);
      _putIfStringNotEmpty(data, 'lastOccupiedHotelDay', room.lastOccupiedHotelDay);
      _putIfNotNull(data, 'createdAtEpoch', room.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', room.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', room.deviceId);
      if (await upsert('rooms', room.localUuid, data)) {
        stats['rooms'] = stats['rooms']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 2. رفع الموظفين ──────────────────────────────────────
    final employees = await db.select(db.employees).get();
    for (var i = 0; i < employees.length; i++) {
      final emp = employees[i];
      if (emp.deletedAt != null) continue;
      onProgress?.call('employees', i + 1, employees.length);
      final data = <String, dynamic>{
        'name': emp.name,
        'basicSalary': emp.basicSalary,
        'position': emp.position,
        'phone': emp.phone,
        'status': emp.status,
        'localUuid': emp.localUuid,
        'createdAt': emp.createdAt,
        'updatedAt': emp.updatedAt,
        'lastModified': emp.lastModified,
        'version': emp.version,
        'origin': emp.origin,
        'vectorClock': emp.vectorClock,
      };
      _putIfStringNotEmpty(data, 'hireDate', emp.hireDate);
      _putIfStringNotEmpty(data, 'terminationDate', emp.terminationDate);
      _putIfStringNotEmpty(data, 'terminationReason', emp.terminationReason);
      _putIfNotNull(data, 'createdAtEpoch', emp.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', emp.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', emp.deviceId);
      if (await upsert('employees', emp.localUuid, data)) {
        stats['employees'] = stats['employees']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 3. رفع الحجوزات ──────────────────────────────────────
    final bookings = await db.select(db.bookings).get();
    for (var i = 0; i < bookings.length; i++) {
      final b = bookings[i];
      if (b.deletedAt != null) continue;
      onProgress?.call('bookings', i + 1, bookings.length);
      final data = <String, dynamic>{
        'localUuid': b.localUuid,
        'roomNumber': b.roomNumber,
        'guestName': b.guestName,
        'guestPhone': b.guestPhone,
        'checkinDate': b.checkinDate,
        'status': b.status,
        'createdAt': b.createdAt,
        'updatedAt': b.updatedAt,
        'lastModified': b.lastModified,
        'version': b.version,
        'origin': b.origin,
        'vectorClock': b.vectorClock,
      };
      _putIfStringNotEmpty(data, 'guestIdType', b.guestIdType);
      _putIfStringNotEmpty(data, 'guestIdNumber', b.guestIdNumber);
      _putIfStringNotEmpty(data, 'guestNationality', b.guestNationality);
      _putIfStringNotEmpty(data, 'guestIdIssueDate', b.guestIdIssueDate);
      _putIfStringNotEmpty(data, 'guestIdIssuePlace', b.guestIdIssuePlace);
      _putIfStringNotEmpty(data, 'guestEmail', b.guestEmail);
      _putIfStringNotEmpty(data, 'guestAddress', b.guestAddress);
      _putIfStringNotEmpty(data, 'checkoutDate', b.checkoutDate);
      _putIfStringNotEmpty(data, 'actualCheckout', b.actualCheckout);
      _putIfStringNotEmpty(data, 'notes', b.notes);
      _putIfStringNotEmpty(data, 'hotelDayCheckin', b.hotelDayCheckin);
      _putIfStringNotEmpty(data, 'hotelDayCheckout', b.hotelDayCheckout);
      _putIfNotNull(data, 'discount', b.discount);
      _putIfStringNotEmpty(data, 'discountType', b.discountType);
      _putIfNotNull(data, 'expectedNights', b.expectedNights);
      _putIfNotNull(data, 'calculatedNights', b.calculatedNights);
      _putIfNotNull(data, 'totalDueCached', b.totalDueCached);
      _putIfNotNull(data, 'totalPaidCached', b.totalPaidCached);
      _putIfNotNull(data, 'remainingBalanceCached', b.remainingBalanceCached);
      _putIfNotNull(data, 'totalNightsCached', b.totalNightsCached);
      _putIfNotNull(data, 'isFullyPaid', b.isFullyPaid);
      _putIfNotNull(data, 'isOverdue', b.isOverdue);
      _putIfNotNull(data, 'needsCheckoutReview', b.needsCheckoutReview);
      _putIfStringNotEmpty(data, 'stayDurationIso', b.stayDurationIso);
      _putIfNotNull(data, 'lastNightEpoch', b.lastNightEpoch);
      _putIfNotNull(data, 'createdAtEpoch', b.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', b.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', b.deviceId);
      if (await upsert('bookings', b.localUuid, data)) {
        stats['bookings'] = stats['bookings']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 4. رفع المدفوعات (كاملة) ────────────────────────────
    final payments = await db.select(db.payments).get();
    for (var i = 0; i < payments.length; i++) {
      final p = payments[i];
      if (p.deletedAt != null) continue;
      onProgress?.call('payments', i + 1, payments.length);
      final data = <String, dynamic>{
        'localUuid': p.localUuid,
        'amount': p.amount,
        'paymentDate': p.paymentDate,
        'paymentMethod': p.paymentMethod,
        'revenueType': p.revenueType,
        'createdAt': p.createdAt,
        'updatedAt': p.updatedAt,
        'lastModified': p.lastModified,
        'version': p.version,
        'origin': p.origin,
        'vectorClock': p.vectorClock,
      };
      _putIfStringNotEmpty(data, 'roomNumber', p.roomNumber);
      _putIfStringNotEmpty(data, 'notes', p.notes);
      _putIfStringNotEmpty(data, 'hotelDayKey', p.hotelDayKey);
      _putIfNotNull(data, 'serverPaymentId', p.serverPaymentId);
      _putIfNotNull(data, 'bookingLocalId', p.bookingLocalId);
      _putIfNotNull(data, 'serverBookingId', p.serverBookingId);
      _putIfNotNull(data, 'cashTransactionLocalId', p.cashTransactionLocalId);
      _putIfNotNull(data, 'cashTransactionServerId', p.cashTransactionServerId);
      _putIfStringNotEmpty(data, 'referenceNumber', p.referenceNumber);
      _putIfNotNull(data, 'isPendingBalance', p.isPendingBalance);
      _putIfStringNotEmpty(data, 'linkedDebtUuid', p.linkedDebtUuid);
      _putIfStringNotEmpty(data, 'bookingUuidCache', p.bookingUuidCache);
      _putIfNotNull(data, 'discountAmount', p.discountAmount);
      _putIfStringNotEmpty(data, 'discountStartDate', p.discountStartDate);
      _putIfNotNull(data, 'isVoided', p.isVoided);
      _putIfNotNull(data, 'voidedAt', p.voidedAt);
      _putIfStringNotEmpty(data, 'voidedBy', p.voidedBy);
      _putIfNotNull(data, 'createdAtEpoch', p.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', p.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', p.deviceId);
      if (await upsert('payments', p.localUuid, data)) {
        stats['payments'] = stats['payments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 5. رفع المصروفات ────────────────────────────────────
    final expenses = await db.select(db.expenses).get();
    for (var i = 0; i < expenses.length; i++) {
      final e = expenses[i];
      if (e.deletedAt != null) continue;
      onProgress?.call('expenses', i + 1, expenses.length);
      final data = <String, dynamic>{
        'localUuid': e.localUuid,
        'expenseType': e.expenseType,
        'description': e.description,
        'amount': e.amount,
        'date': e.date,
        'createdAt': e.createdAt,
        'updatedAt': e.updatedAt,
        'lastModified': e.lastModified,
        'version': e.version,
        'origin': e.origin,
        'vectorClock': e.vectorClock,
      };
      _putIfNotNull(data, 'relatedId', e.relatedId);
      _putIfNotNull(data, 'cashTransactionId', e.cashTransactionId);
      _putIfStringNotEmpty(data, 'hotelDayKey', e.hotelDayKey);
      _putIfStringNotEmpty(data, 'categoryUuid', e.categoryUuid);
      _putIfStringNotEmpty(data, 'cashFlowUuid', e.cashFlowUuid);
      _putIfNotNull(data, 'isAutoGenerated', e.isAutoGenerated);
      _putIfNotNull(data, 'createdAtEpoch', e.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', e.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', e.deviceId);
      if (await upsert('expenses', e.localUuid, data)) {
        stats['expenses'] = stats['expenses']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 6. رفع الديون ───────────────────────────────────────
    final debts = await db.select(db.debts).get();
    for (var i = 0; i < debts.length; i++) {
      final d = debts[i];
      if (d.deletedAt != null) continue;
      onProgress?.call('debts', i + 1, debts.length);
      final data = <String, dynamic>{
        'localUuid': d.localUuid,
        'guestName': d.guestName,
        'checkinDate': d.checkinDate,
        'checkoutDate': d.checkoutDate,
        'totalAmount': d.totalAmount,
        'paidAmount': d.paidAmount,
        'remainingAmount': d.remainingAmount,
        'paymentDate': d.paymentDate,
        'createdAt': d.createdAt,
        'updatedAt': d.updatedAt,
        'lastModified': d.lastModified,
        'version': d.version,
        'origin': d.origin,
        'vectorClock': d.vectorClock,
      };
      _putIfNotNull(data, 'bookingLocalId', d.bookingLocalId);
      _putIfStringNotEmpty(data, 'dateRecorded', d.dateRecorded);
      _putIfStringNotEmpty(data, 'debtReason', d.debtReason);
      _putIfNotNull(data, 'isSettled', d.isSettled);
      _putIfStringNotEmpty(data, 'pledge', d.pledge);
      _putIfStringNotEmpty(data, 'pledgeType', d.pledgeType);
      _putIfStringNotEmpty(data, 'note', d.note);
      _putIfStringNotEmpty(data, 'debtUuid', d.debtUuid);
      _putIfStringNotEmpty(data, 'hotelDayOpened', d.hotelDayOpened);
      _putIfStringNotEmpty(data, 'hotelDayClosed', d.hotelDayClosed);
      _putIfNotNull(data, 'isFromAutoFix', d.isFromAutoFix);
      _putIfNotNull(data, 'settlementConfirmed', d.settlementConfirmed);
      _putIfNotNull(data, 'createdAtEpoch', d.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', d.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', d.deviceId);
      if (await upsert('debts', d.localUuid, data)) {
        stats['debts'] = stats['debts']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 7. رفع ملاحظات الحجوزات ──────────────────────────────
    final bookingNotes = await db.select(db.bookingNotes).get();
    for (var i = 0; i < bookingNotes.length; i++) {
      final bn = bookingNotes[i];
      if (bn.deletedAt != null) continue;
      onProgress?.call('booking_notes', i + 1, bookingNotes.length);
      final data = <String, dynamic>{
        'localUuid': bn.localUuid,
        'noteText': bn.noteText,
        'alertType': bn.alertType,
        'isActive': bn.isActive,
        'bookingId': bn.bookingId,
        'createdAt': bn.createdAt,
        'updatedAt': bn.updatedAt,
        'lastModified': bn.lastModified,
        'version': bn.version,
        'origin': bn.origin,
        'vectorClock': bn.vectorClock,
      };
      _putIfStringNotEmpty(data, 'alertUntil', bn.alertUntil);
      _putIfNotNull(data, 'createdAtEpoch', bn.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', bn.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', bn.deviceId);
      if (await upsert('booking_notes', bn.localUuid, data)) {
        stats['booking_notes'] = stats['booking_notes']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 8. رفع ليالي الحجوزات ────────────────────────────────
    final bookingNights = await db.select(db.bookingNights).get();
    for (var i = 0; i < bookingNights.length; i++) {
      final bn = bookingNights[i];
      if (bn.deletedAt != null) continue;
      onProgress?.call('booking_nights', i + 1, bookingNights.length);
      final data = <String, dynamic>{
        'localUuid': bn.localUuid,
        'bookingLocalId': bn.bookingLocalId,
        'hotelDayKey': bn.hotelDayKey,
        'nightStart': bn.nightStart,
        'nightEnd': bn.nightEnd,
        'nightlyRate': bn.nightlyRate,
        'sequence': bn.sequence,
        'isProcessedByAutoFix': bn.isProcessedByAutoFix,
        'baseRate': bn.baseRate,
        'adjustment': bn.adjustment,
        'finalRate': bn.finalRate,
        'createdAt': bn.createdAt,
        'updatedAt': bn.updatedAt,
        'lastModified': bn.lastModified,
        'version': bn.version,
        'origin': bn.origin,
        'vectorClock': bn.vectorClock,
      };
      _putIfStringNotEmpty(data, 'appliedAdjustmentUuid', bn.appliedAdjustmentUuid);
      _putIfStringNotEmpty(data, 'appliedAdjustmentsJson', bn.appliedAdjustmentsJson);
      _putIfNotNull(data, 'createdAtEpoch', bn.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', bn.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', bn.deviceId);
      if (await upsert('booking_nights', bn.localUuid, data)) {
        stats['booking_nights'] = stats['booking_nights']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 9. رفع ملاحظات النوبة ────────────────────────────────
    final shiftNotes = await db.select(db.shiftNotes).get();
    for (var i = 0; i < shiftNotes.length; i++) {
      final sn = shiftNotes[i];
      if (sn.deletedAt != null) continue;
      onProgress?.call('shift_notes', i + 1, shiftNotes.length);
      final data = <String, dynamic>{
        'localUuid': sn.localUuid,
        'title': sn.title,
        'content': sn.content,
        'priority': sn.priority,
        'shiftType': sn.shiftType,
        'isRead': sn.isRead,
        'createdBy': sn.createdBy,
        'createdAt': sn.createdAt,
        'updatedAt': sn.updatedAt,
        'lastModified': sn.lastModified,
        'version': sn.version,
        'origin': sn.origin,
        'vectorClock': sn.vectorClock,
      };
      _putIfStringNotEmpty(data, 'expiresAt', sn.expiresAt);
      _putIfNotNull(data, 'createdAtEpoch', sn.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', sn.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', sn.deviceId);
      if (await upsert('shift_notes', sn.localUuid, data)) {
        stats['shift_notes'] = stats['shift_notes']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 10. رفع المعاملات النقدية ────────────────────────────
    final cashTransactions = await db.select(db.cashTransactions).get();
    for (var i = 0; i < cashTransactions.length; i++) {
      final ct = cashTransactions[i];
      if (ct.deletedAt != null) continue;
      onProgress?.call('cash_transactions', i + 1, cashTransactions.length);
      final data = <String, dynamic>{
        'localUuid': ct.localUuid,
        'transactionType': ct.transactionType,
        'amount': ct.amount,
        'transactionTime': ct.transactionTime,
        'createdAt': ct.createdAt,
        'updatedAt': ct.updatedAt,
        'lastModified': ct.lastModified,
        'version': ct.version,
        'origin': ct.origin,
        'vectorClock': ct.vectorClock,
      };
      _putIfNotNull(data, 'registerId', ct.registerId);
      _putIfStringNotEmpty(data, 'referenceType', ct.referenceType);
      _putIfNotNull(data, 'referenceId', ct.referenceId);
      _putIfStringNotEmpty(data, 'description', ct.description);
      _putIfNotNull(data, 'createdBy', ct.createdBy);
      _putIfNotNull(data, 'createdAtEpoch', ct.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', ct.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', ct.deviceId);
      if (await upsert('cash_transactions', ct.localUuid, data)) {
        stats['cash_transactions'] = stats['cash_transactions']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 11. رفع معلومات النزلاء ──────────────────────────────
    final guestInfos = await db.select(db.guestInfos).get();
    for (var i = 0; i < guestInfos.length; i++) {
      final gi = guestInfos[i];
      if (gi.deletedAt != null) continue;
      onProgress?.call('guest_infos', i + 1, guestInfos.length);
      final data = <String, dynamic>{
        'localUuid': gi.localUuid,
        'roomNumber': gi.roomNumber,
        'guestName': gi.guestName,
        'nationality': gi.nationality,
        'idNumber': gi.idNumber,
        'idType': gi.idType,
        'createdAt': gi.createdAt,
        'updatedAt': gi.updatedAt,
        'lastModified': gi.lastModified,
        'version': gi.version,
        'origin': gi.origin,
        'vectorClock': gi.vectorClock,
      };
      _putIfStringNotEmpty(data, 'issueDate', gi.issueDate);
      _putIfStringNotEmpty(data, 'issuePlace', gi.issuePlace);
      _putIfStringNotEmpty(data, 'governorate', gi.governorate);
      _putIfStringNotEmpty(data, 'notes', gi.notes);
      _putIfNotNull(data, 'createdAtEpoch', gi.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', gi.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', gi.deviceId);
      if (await upsert('guest_infos', gi.localUuid, data)) {
        stats['guest_infos'] = stats['guest_infos']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 12. رفع دورات الرواتب ────────────────────────────────
    final salaryCycles = await db.select(db.salaryCycles).get();
    for (var i = 0; i < salaryCycles.length; i++) {
      final sc = salaryCycles[i];
      if (sc.deletedAt != null) continue;
      onProgress?.call('salary_cycles', i + 1, salaryCycles.length);
      final data = <String, dynamic>{
        'localUuid': sc.localUuid,
        'employeeId': sc.employeeId,
        'cycleKey': sc.cycleKey,
        'expectedAmount': sc.expectedAmount,
        'actualPaid': sc.actualPaid,
        'remainingAmount': sc.remainingAmount,
        'status': sc.status,
        'createdAt': sc.createdAt,
        'updatedAt': sc.updatedAt,
        'lastModified': sc.lastModified,
        'version': sc.version,
        'origin': sc.origin,
        'vectorClock': sc.vectorClock,
      };
      _putIfStringNotEmpty(data, 'hotelDayStart', sc.hotelDayStart);
      _putIfStringNotEmpty(data, 'hotelDayEnd', sc.hotelDayEnd);
      _putIfNotNull(data, 'createdAtEpoch', sc.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', sc.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', sc.deviceId);
      if (await upsert('salary_cycles', sc.localUuid, data)) {
        stats['salary_cycles'] = stats['salary_cycles']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 13. رفع دفعات الرواتب ────────────────────────────────
    final salaryPayments = await db.select(db.salaryPayments).get();
    for (var i = 0; i < salaryPayments.length; i++) {
      final sp = salaryPayments[i];
      if (sp.deletedAt != null) continue;
      onProgress?.call('salary_payments', i + 1, salaryPayments.length);
      final data = <String, dynamic>{
        'localUuid': sp.localUuid,
        'cycleId': sp.cycleId,
        'amount': sp.amount,
        'paymentDateIso': sp.paymentDateIso,
        'isAutoGenerated': sp.isAutoGenerated,
        'createdAt': sp.createdAt,
        'updatedAt': sp.updatedAt,
        'lastModified': sp.lastModified,
        'version': sp.version,
        'origin': sp.origin,
        'vectorClock': sp.vectorClock,
      };
      _putIfStringNotEmpty(data, 'hotelDayKey', sp.hotelDayKey);
      _putIfStringNotEmpty(data, 'method', sp.method);
      _putIfNotNull(data, 'createdAtEpoch', sp.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', sp.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', sp.deviceId);
      if (await upsert('salary_payments', sp.localUuid, data)) {
        stats['salary_payments'] = stats['salary_payments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 14. رفع سحوبات الرواتب ───────────────────────────────
    final salaryWithdrawals = await db.select(db.salaryWithdrawals).get();
    for (var i = 0; i < salaryWithdrawals.length; i++) {
      final sw = salaryWithdrawals[i];
      if (sw.deletedAt != null) continue;
      onProgress?.call('salary_withdrawals', i + 1, salaryWithdrawals.length);
      final data = <String, dynamic>{
        'localUuid': sw.localUuid,
        'employeeId': sw.employeeId,
        'amount': sw.amount,
        'withdrawDate': sw.withdrawDate,
        'createdAt': sw.createdAt,
        'updatedAt': sw.updatedAt,
        'lastModified': sw.lastModified,
        'version': sw.version,
        'origin': sw.origin,
        'vectorClock': sw.vectorClock,
      };
      _putIfStringNotEmpty(data, 'reason', sw.reason);
      _putIfStringNotEmpty(data, 'hotelDayKey', sw.hotelDayKey);
      _putIfStringNotEmpty(data, 'withdrawalType', sw.withdrawalType);
      _putIfStringNotEmpty(data, 'description', sw.description);
      _putIfNotNull(data, 'createdAtEpoch', sw.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', sw.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', sw.deviceId);
      if (await upsert('salary_withdrawals', sw.localUuid, data)) {
        stats['salary_withdrawals'] = stats['salary_withdrawals']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 15. رفع تعديلات الأسعار ──────────────────────────────
    final priceAdjustments = await db.select(db.priceAdjustments).get();
    for (var i = 0; i < priceAdjustments.length; i++) {
      final pa = priceAdjustments[i];
      if (pa.deletedAt != null) continue;
      onProgress?.call('price_adjustments', i + 1, priceAdjustments.length);
      final data = <String, dynamic>{
        'localUuid': pa.localUuid,
        'targetType': pa.targetType,
        'targetUuid': pa.targetUuid,
        'adjustmentType': pa.adjustmentType,
        'previousValue': pa.previousValue,
        'newValue': pa.newValue,
        'effectiveDate': pa.effectiveDate,
        'appliedBy': pa.appliedBy,
        'hotelDayKey': pa.hotelDayKey,
        'isReversed': pa.isReversed,
        'createdAt': pa.createdAt,
        'updatedAt': pa.updatedAt,
        'lastModified': pa.lastModified,
        'version': pa.version,
        'origin': pa.origin,
        'vectorClock': pa.vectorClock,
      };
      _putIfStringNotEmpty(data, 'reason', pa.reason);
      _putIfStringNotEmpty(data, 'reversedAt', pa.reversedAt);
      _putIfStringNotEmpty(data, 'reversedBy', pa.reversedBy);
      _putIfNotNull(data, 'createdAtEpoch', pa.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', pa.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', pa.deviceId);
      if (await upsert('price_adjustments', pa.localUuid, data)) {
        stats['price_adjustments'] = stats['price_adjustments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 16. رفع تعديلات أسعار الحجوزات ──────────────────────
    final bookingPriceAdj = await db.select(db.bookingPriceAdjustments).get();
    for (var i = 0; i < bookingPriceAdj.length; i++) {
      final bpa = bookingPriceAdj[i];
      if (bpa.deletedAt != null) continue;
      onProgress?.call('booking_price_adjustments', i + 1, bookingPriceAdj.length);
      final data = <String, dynamic>{
        'localUuid': bpa.localUuid,
        'bookingLocalUuid': bpa.bookingLocalUuid,
        'adjustmentType': bpa.adjustmentType,
        'adjustmentMode': bpa.adjustmentMode,
        'amount': bpa.amount,
        'effectiveHotelDay': bpa.effectiveHotelDay,
        'isActive': bpa.isActive,
        'createdAt': bpa.createdAt,
        'updatedAt': bpa.updatedAt,
        'lastModified': bpa.lastModified,
        'version': bpa.version,
        'origin': bpa.origin,
        'vectorClock': bpa.vectorClock,
      };
      _putIfNotNull(data, 'bookingLocalId', bpa.bookingLocalId);
      _putIfStringNotEmpty(data, 'roomNumber', bpa.roomNumber);
      _putIfStringNotEmpty(data, 'endHotelDay', bpa.endHotelDay);
      _putIfStringNotEmpty(data, 'reason', bpa.reason);
      _putIfStringNotEmpty(data, 'appliedBy', bpa.appliedBy);
      _putIfStringNotEmpty(data, 'cancelledAt', bpa.cancelledAt);
      _putIfStringNotEmpty(data, 'cancelledBy', bpa.cancelledBy);
      _putIfNotNull(data, 'createdAtEpoch', bpa.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', bpa.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', bpa.deviceId);
      if (await upsert('booking_price_adjustments', bpa.localUuid, data)) {
        stats['booking_price_adjustments'] = stats['booking_price_adjustments']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 17. رفع سجلات التدقيق ────────────────────────────────
    final auditLogs = await db.select(db.auditLogs).get();
    for (var i = 0; i < auditLogs.length; i++) {
      final al = auditLogs[i];
      onProgress?.call('audit_logs', i + 1, auditLogs.length);
      final data = <String, dynamic>{
        'localUuid': al.localUuid,
        'operationType': al.operationType,
        'entityType': al.entityType,
        'entityUuid': al.entityUuid,
        'performedBy': al.performedBy,
        'deviceId': al.deviceId,
        'hotelDayKey': al.hotelDayKey,
        'timestamp': al.timestamp,
        'timestampIso': al.timestampIso,
        'isFinancial': al.isFinancial,
        'createdAt': al.createdAt,
      };
      _putIfNotNull(data, 'entityId', al.entityId);
      _putIfStringNotEmpty(data, 'previousState', al.previousState);
      _putIfStringNotEmpty(data, 'newState', al.newState);
      _putIfStringNotEmpty(data, 'changedFields', al.changedFields);
      _putIfStringNotEmpty(data, 'ipAddress', al.ipAddress);
      _putIfNotNull(data, 'amountImpact', al.amountImpact);
      if (await upsert('audit_logs', al.localUuid, data)) {
        stats['audit_logs'] = stats['audit_logs']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // ─── 18. رفع إلغاءات الدفع ────────────────────────────────
    final paymentVoids = await db.select(db.paymentVoids).get();
    for (var i = 0; i < paymentVoids.length; i++) {
      final pv = paymentVoids[i];
      if (pv.deletedAt != null) continue;
      onProgress?.call('payment_voids', i + 1, paymentVoids.length);
      final data = <String, dynamic>{
        'localUuid': pv.localUuid,
        'originalPaymentUuid': pv.originalPaymentUuid,
        'originalPaymentId': pv.originalPaymentId,
        'bookingUuid': pv.bookingUuid,
        'voidedAmount': pv.voidedAmount,
        'voidReason': pv.voidReason,
        'voidedBy': pv.voidedBy,
        'voidedAt': pv.voidedAt,
        'voidedAtIso': pv.voidedAtIso,
        'hotelDayKey': pv.hotelDayKey,
        'createdAt': pv.createdAt,
        'updatedAt': pv.updatedAt,
        'lastModified': pv.lastModified,
        'version': pv.version,
        'origin': pv.origin,
        'vectorClock': pv.vectorClock,
      };
      _putIfStringNotEmpty(data, 'reversalPaymentUuid', pv.reversalPaymentUuid);
      _putIfStringNotEmpty(data, 'approvedBy', pv.approvedBy);
      _putIfNotNull(data, 'createdAtEpoch', pv.createdAtEpoch);
      _putIfNotNull(data, 'lastModifiedEpoch', pv.lastModifiedEpoch);
      _putIfStringNotEmpty(data, 'deviceId', pv.deviceId);
      if (await upsert('payment_voids', pv.localUuid, data)) {
        stats['payment_voids'] = stats['payment_voids']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    _logger.info('✅ اكتمل الرفع الشامل إلى ${endpoint.name}', tag: 'BACKUP_SYNC');
    return stats;
  }

  /// اختبار الاتصال بنقطة نهاية احتياطية
  static Future<bool> testConnection(BackupEndpoint endpoint) async {
    try {
      final client = Client()
          .setEndpoint(endpoint.endpoint)
          .setProject(endpoint.projectId);
      if (endpoint.apiKey.isNotEmpty) {
        client.addHeader('X-Appwrite-Key', endpoint.apiKey);
      }
      final databases = Databases(client);
      // ignore: deprecated_member_use
      await databases.listDocuments(
        databaseId: endpoint.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      return true;
    } catch (e) {
      AppLogger.error('❌ Backup endpoint test failed: $e', tag: 'APP');
      return false;
    }
  }
}

// ─── دوال مساعدة ───────────────────────────────────────────

void _putIfNotNull(Map<String, dynamic> map, String key, dynamic value) {
  if (value != null) {
    map[key] = value;
  }
}

void _putIfStringNotEmpty(Map<String, dynamic> map, String key, String? value) {
  if (value != null && value.isNotEmpty) {
    map[key] = value;
  }
}
