import 'dart:async';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';

import 'appwrite_backup_endpoint.dart';
import 'appwrite_backup_endpoints_manager.dart';
import 'appwrite_config.dart';
import 'local_db.dart';
import 'appwrite_logger.dart';

/// خدمة المزامنة الاحتياطية (Slave Push Only)
///
/// تقوم بدفع البيانات إلى نقاط النهاية الثانوية بعد نجاح المزامنة الرئيسية.
/// هذه الخدمة لا تسحب بيانات (pull) — فقط إرسال (push).
class AppwriteBackupSyncService {
  AppwriteBackupSyncService._internal();
  static final AppwriteBackupSyncService _instance =
      AppwriteBackupSyncService._internal();
  factory AppwriteBackupSyncService() => _instance;

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
        await databases.createDocument(
          databaseId: dbId,
          collectionId: tableName,
          documentId: documentId,
          data: data,
        );
        break;
      case 'update':
        try {
          await databases.updateDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
            data: data,
          );
        } catch (_) {
          // إذا فشل التحديث (المستند غير موجود)، نقوم بإنشائه
          await databases.createDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
            data: data,
          );
        }
        break;
      case 'delete':
        try {
          await databases.deleteDocument(
            databaseId: dbId,
            collectionId: tableName,
            documentId: documentId,
          );
        } catch (_) {
          // تجاهل خطأ الحذف إذا كان المستند غير موجود أصلاً
        }
        break;
    }
  }

  /// رفع جميع البيانات المحلية إلى نقطة نهاية احتياطية (Full Push)
  ///
  /// هذه العملية تقرأ جميع السجلات من قاعدة البيانات المحلية
  /// وترفعها إلى نقطة النهاية المحددة بالترتيب الصحيح (FK order).
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

    /// دالة مساعدة لرفع مستند
    Future<bool> _upsert(String collection, String docId, Map<String, dynamic> data) async {
      try {
        await databases.createDocument(
          databaseId: dbId,
          collectionId: collection,
          documentId: docId,
          data: data,
        );
        return true;
      } catch (_) {
        // إذا كان موجوداً مسبقاً → نحدّث
        try {
          await databases.updateDocument(
            databaseId: dbId,
            collectionId: collection,
            documentId: docId,
            data: data,
          );
          return true;
        } catch (e) {
          _logger.warning(
            '⚠️ فشل رفع $docId إلى $collection: $e',
            tag: 'BACKUP_SYNC',
          );
          return false;
        }
      }
    }

    _logger.info('🚀 بدء الرفع الشامل إلى ${endpoint.name}...', tag: 'BACKUP_SYNC');

    // 1. رفع الغرف
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
      if (await _upsert('rooms', room.localUuid, data)) {
        stats['rooms'] = stats['rooms']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // 2. رفع الموظفين
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
      if (await _upsert('employees', emp.localUuid, data)) {
        stats['employees'] = stats['employees']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // 3. رفع الحجوزات
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
      if (await _upsert('bookings', b.localUuid, data)) {
        stats['bookings'] = stats['bookings']! + 1;
      } else {
        stats['errors'] = stats['errors']! + 1;
      }
    }

    // 4. رفع المدفوعات
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
      if (await _upsert('payments', p.localUuid, data)) {
        stats['payments'] = stats['payments']! + 1;
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
      await databases.listDocuments(
        databaseId: endpoint.databaseId,
        collectionId: AppwriteConfig.roomsCollectionId,
        queries: [Query.limit(1)],
      );
      return true;
    } catch (e) {
      debugPrint('❌ Backup endpoint test failed: $e');
      return false;
    }
  }
}

/// عملية احتياطية — تستخدم لإرسال دفعة

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
class BackupOperation {
  final String tableName;
  final String documentId;
  final Map<String, dynamic> data;
  final String operation;

  BackupOperation({
    required this.tableName,
    required this.documentId,
    required this.data,
    required this.operation,
  });
}
