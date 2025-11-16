import 'dart:convert';
import 'dart:io';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'local_db.dart';
import 'daos/bookings_dao.dart';
import 'daos/rooms_dao.dart';
import 'daos/payments_dao.dart';
import 'daos/outbox_dao.dart';
import '../utils/time.dart';
import '../utils/status_utils.dart';
import '../utils/id.dart';

/// نموذج لتخزين معلومات اللقطة الاحتياطية
class RestoreSnapshot {
  final String filePath;
  final DateTime createdAt;
  final Map<String, int> recordCounts;
  final int totalSizeBytes;
  
  RestoreSnapshot({
    required this.filePath,
    required this.createdAt,
    required this.recordCounts,
    required this.totalSizeBytes,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'createdAt': createdAt.toIso8601String(),
    'recordCounts': recordCounts,
    'totalSizeBytes': totalSizeBytes,
  };

  factory RestoreSnapshot.fromJson(Map<String, dynamic> json) => RestoreSnapshot(
    filePath: json['filePath'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
    recordCounts: Map<String, int>.from(json['recordCounts'] as Map),
    totalSizeBytes: json['totalSizeBytes'] as int,
  );
}

/// تقرير شامل عن عملية الإصلاح التلقائي
class RestoreFixReport {
  final bool success;
  final int bookingsFixed;
  final int roomsUpdated;
  final int paymentsRecalculated;
  final List<String> changes;
  final String? error;
  final DateTime executedAt;
  final int durationMs;
  
  RestoreFixReport({
    required this.success,
    required this.bookingsFixed,
    required this.roomsUpdated,
    required this.paymentsRecalculated,
    required this.changes,
    this.error,
    required this.executedAt,
    required this.durationMs,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'bookingsFixed': bookingsFixed,
    'roomsUpdated': roomsUpdated,
    'paymentsRecalculated': paymentsRecalculated,
    'changes': changes,
    'error': error,
    'executedAt': executedAt.toIso8601String(),
    'durationMs': durationMs,
  };

  factory RestoreFixReport.fromJson(Map<String, dynamic> json) => RestoreFixReport(
    success: json['success'] as bool,
    bookingsFixed: json['bookingsFixed'] as int,
    roomsUpdated: json['roomsUpdated'] as int,
    paymentsRecalculated: json['paymentsRecalculated'] as int,
    changes: List<String>.from(json['changes'] as List),
    error: json['error'] as String?,
    executedAt: DateTime.parse(json['executedAt'] as String),
    durationMs: json['durationMs'] as int,
  );
}

/// خدمة الإصلاح التلقائي للنسخة الاحتياطية
/// تقوم بإعادة حساب الليالي، حالات الغرف، والمدفوعات بعد استعادة النسخة الاحتياطية
class RestoreFixService {
  final AppDatabase db;
  final BookingsDao bookingsDao;
  final RoomsDao roomsDao;
  final PaymentsDao paymentsDao;
  
  RestoreFixService(this.db) : 
    bookingsDao = BookingsDao(db, OutboxDao(db)),
    roomsDao = RoomsDao(db, OutboxDao(db)),
    paymentsDao = PaymentsDao(db, OutboxDao(db));

  /// إنشاء لقطة احتياطية محلية قبل بدء عملية الإصلاح
  Future<RestoreSnapshot> createLocalSnapshot(String prefix) async {
    debugPrint('📸 إنشاء لقطة احتياطية أمان: ${prefix}_restore_snapshot_${Time.nowEpoch()}.json');
    
    final directory = await getApplicationCacheDirectory();
    final timestamp = Time.nowEpoch();
    final filename = '${prefix}_restore_snapshot_$timestamp.json';
    final filePath = '${directory.path}/$filename';
    
    try {
      // تصدير البيانات الحالية
      final bookingsData = await bookingsDao.exportToJson();
      final roomsData = await roomsDao.exportToJson();
      final paymentsData = await paymentsDao.exportToJson();
      
      final snapshotData = {
        'metadata': {
          'timestamp': timestamp,
          'createdAt': DateTime.now().toIso8601String(),
          'deviceId': 'local_device',
          'version': '1.0',
        },
        'bookings': bookingsData,
        'rooms': roomsData,
        'payments': paymentsData,
      };

      final jsonString = jsonEncode(snapshotData);
      final file = File(filePath);
      await file.writeAsString(jsonString);
      
      final recordCounts = {
        'bookings': (bookingsData as List).length,
        'rooms': (roomsData as List).length,
        'payments': (paymentsData as List).length,
      };

      return RestoreSnapshot(
        filePath: filePath,
        createdAt: DateTime.now(),
        recordCounts: recordCounts,
        totalSizeBytes: await file.length(),
      );
      
    } catch (e) {
      debugPrint('❌ خطأ في إنشاء اللقطة الاحتياطية: $e');
      rethrow;
    }
  }

  /// الدالة الرئيسية لتشغيل الإصلاح التلقائي
  Future<RestoreFixReport> runAutoFixAfterRestore({DateTime? backupTimestamp}) async {
    debugPrint('🔄 بدء عملية الإصلاح التلقائي للنسخة الاحتياطية...');
    
    final startTime = DateTime.now();
    int bookingsFixed = 0;
    int roomsUpdated = 0;
    int paymentsChecked = 0;
    List<String> changes = [];
    RestoreSnapshot? snapshot;

    try {
      // إنشاء لقطة احتياطية للأمان
      snapshot = await createLocalSnapshot('auto_fix');
      
      // تنفيذ الإصلاح داخل معاملة واحدة
      await db.transaction(() async {
        final now = DateTime.now();
        final fixId = IdGen.uuid();
        
        // البحث عن الحجوزات التي تحتاج إصلاح
        final bookingsToFix = await _getBookingsNeedingFix(backupTimestamp, now);
        debugPrint('🔍 العثور على ${bookingsToFix.length} حجز يحتاج إلى إصلاح');
        
        for (final booking in bookingsToFix) {
          final bookingChanges = await _fixBookingDatesAndNights(booking, now, fixId);
          if (bookingChanges.isNotEmpty) {
            bookingsFixed++;
            changes.addAll(bookingChanges);
          }
          
          final paymentChanges = await _recalculateBookingFinancials(booking, fixId);
          if (paymentChanges.isNotEmpty) {
            paymentsChecked++;
            changes.addAll(paymentChanges);
          }
        }
        
        // تحديث حالات الغرف
        final roomChanges = await _updateRoomStatusesFromBookings(fixId);
        roomsUpdated = roomChanges.length;
        changes.addAll(roomChanges);
      });
      
      // حذف اللقطة الاحتياطية عند النجاح
      await _deleteSnapshot(snapshot.filePath);
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      
      debugPrint('✅ اكتمل الإصلاح التلقائي بنجاح');
      debugPrint('📊 الإحصائيات:');
      debugPrint('   - الحجوزات المصلحة: $bookingsFixed');
      debugPrint('   - الغرف المحدثة: $roomsUpdated');
      debugPrint('   - الدفعات المتحقق منها: $paymentsChecked');
      debugPrint('   - المدة: ${(duration / 1000).toStringAsFixed(1)} ثانية');
      
      return RestoreFixReport(
        success: true,
        bookingsFixed: bookingsFixed,
        roomsUpdated: roomsUpdated,
        paymentsRecalculated: paymentsChecked,
        changes: changes,
        executedAt: startTime,
        durationMs: duration,
      );
      
    } catch (e, stackTrace) {
      debugPrint('❌ فشل الإصلاح التلقائي: $e');
      debugPrint('Stack trace: $stackTrace');
      
      // استعادة اللقطة الاحتياطية في حالة الفشل
      if (snapshot != null) {
        try {
          await _restoreFromSnapshot(snapshot.filePath);
          debugPrint('✅ تم استعادة البيانات من اللقطة الاحتياطية');
        } catch (restoreError) {
          debugPrint('❌ فشل في استعادة اللقطة الاحتياطية: $restoreError');
        }
      }
      
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      
      return RestoreFixReport(
        success: false,
        bookingsFixed: 0,
        roomsUpdated: 0,
        paymentsRecalculated: 0,
        changes: [],
        error: e.toString(),
        executedAt: startTime,
        durationMs: duration,
      );
    }
  }

  /// البحث عن الحجوزات التي تحتاج إصلاح
  Future<List<Booking>> _getBookingsNeedingFix(DateTime? backupDate, DateTime now) async {
    final query = db.select(db.bookings);
    
    // استثناء الحجوزات المحذوفة
    query.where((b) => b.deletedAt.isNull());
    
    // البحث عن الحجوزات النشطة أو المكتملة حديثاً
    query.where((b) => 
      b.status.equals('محجوزة') |
      b.status.equals('active') |
      b.status.equals('confirmed') |
      b.status.equals('checked_in')
    );
    
    // التأكد من وجود تواريخ الدخول والخروج
    query.where((b) => b.checkinDate.isNotNull() & b.checkoutDate.isNotNull());
    
    return await query.get();
  }

  /// إصلاح تواريخ وليالي الحجز
  Future<List<String>> _fixBookingDatesAndNights(Booking booking, DateTime now, String fixId) async {
    List<String> changes = [];
    
    try {
      // تحليل تواريخ الدخول والخروج
      final checkinDate = DateTime.parse(booking.checkinDate);
      final checkoutDate = booking.actualCheckout != null 
          ? DateTime.parse(booking.actualCheckout!)
          : DateTime.parse(booking.checkoutDate!);
      
      // حساب الليالي باستخدام قاعدة الساعة 14:00
      final calculatedNights = Time.nightsWithCutoff(checkinDate, checkout: checkoutDate);
      
      // مقارنة مع القيم الحالية
      if (calculatedNights != booking.calculatedNights || calculatedNights != booking.expectedNights) {
        
        // تسجيل التغيير
        await _logChange(
          fixId: fixId,
          targetTable: 'bookings',
          targetRecordId: booking.id,
          fieldName: 'calculatedNights',
          oldValue: booking.calculatedNights.toString(),
          newValue: calculatedNights.toString(),
          reason: 'إعادة حساب الليالي بناءً على تاريخ الدخول والخروج مع قاعدة 14:00',
          fixType: 'nights_recalc',
        );
        
        // تحديث الحجز
        await bookingsDao.updateById(
          booking.id,
          BookingsCompanion(
            calculatedNights: Value(calculatedNights),
            expectedNights: Value(calculatedNights),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ),
          originIsServer: false,
        );
        
        final changeMsg = 'إصلاح الحجز #${booking.id}: تحديث الليالي من ${booking.calculatedNights} إلى $calculatedNights';
        changes.add(changeMsg);
        debugPrint('✏️ $changeMsg');
      }
      
    } catch (e) {
      debugPrint('⚠️ خطأ في إصلاح الحجز #${booking.id}: $e');
    }
    
    return changes;
  }

  /// إعادة حساب المعاملات المالية للحجز
  Future<List<String>> _recalculateBookingFinancials(Booking booking, String fixId) async {
    List<String> changes = [];
    
    try {
      // استعلام المدفوعات المرتبطة بالحجز
      final payments = await (db.select(db.payments)
        ..where((p) => p.bookingLocalId.equals(booking.id))
        ..where((p) => p.deletedAt.isNull()))
        .get();
      
      final totalPaid = payments.fold<double>(0.0, (sum, payment) => sum + payment.amount);
      
      // الحصول على سعر الغرفة
      final room = await (db.select(db.rooms)
        ..where((r) => r.roomNumber.equals(booking.roomNumber)))
        .getSingleOrNull();
      
      if (room != null) {
        final expectedTotal = booking.calculatedNights * room.price;
        
        // التحقق من التطابق
        if ((totalPaid - expectedTotal).abs() > 0.01) {
          // تسجيل التحذير
          await _logChange(
            fixId: fixId,
            targetTable: 'payments',
            targetRecordId: booking.id,
            fieldName: 'amount_check',
            oldValue: totalPaid.toString(),
            newValue: expectedTotal.toString(),
            reason: 'مبلغ الدفع لا يتطابق مع المبلغ المتوقع (${booking.calculatedNights} × ${room.price})',
            fixType: 'payment_check',
          );
          
          final warningMsg = 'تنبيه: الحجز #${booking.id} - إجمالي المدفوعات (${totalPaid.toStringAsFixed(2)}) لا يتطابق مع المتوقع (${expectedTotal.toStringAsFixed(2)})';
          changes.add(warningMsg);
          debugPrint('⚠️ $warningMsg');
        }
      }
      
    } catch (e) {
      debugPrint('⚠️ خطأ في فحص المدفوعات للحجز #${booking.id}: $e');
    }
    
    return changes;
  }

  /// تحديث حالات الغرف بناءً على الحجوزات النشطة
  Future<List<String>> _updateRoomStatusesFromBookings(String fixId) async {
    List<String> changes = [];
    
    try {
      // الحصول على الحجوزات النشطة
      final activeBookings = await (db.select(db.bookings)
        ..where((b) => b.deletedAt.isNull())
        ..where((b) => b.status.equals('محجوزة') | b.status.equals('active')))
        .get();
      
      final occupiedRooms = activeBookings.map((b) => b.roomNumber).toSet();
      
      // الحصول على جميع الغرف
      final rooms = await (db.select(db.rooms)
        ..where((r) => r.deletedAt.isNull()))
        .get();
      
      for (final room in rooms) {
        final shouldBeOccupied = occupiedRooms.contains(room.roomNumber);
        final currentlyOccupied = StatusUtils.isRoomOccupied(room.status);
        
        if (shouldBeOccupied != currentlyOccupied) {
          final newStatus = StatusUtils.roomStatusForOccupancy(shouldBeOccupied);
          
          // تسجيل التغيير
          await _logChange(
            fixId: fixId,
            targetTable: 'rooms',
            targetRecordId: room.id,
            fieldName: 'status',
            oldValue: room.status,
            newValue: newStatus,
            reason: 'تحديث الحالة بناءً على الحجوزات النشطة',
            fixType: 'room_status',
          );
          
          // تحديث الغرفة
          await roomsDao.updateByNumber(
            room.roomNumber,
            RoomsCompanion(status: Value(newStatus)),
          );
          
          final changeMsg = 'إصلاح الغرفة ${room.roomNumber}: تحديث الحالة من \'${room.status}\' إلى \'$newStatus\'';
          changes.add(changeMsg);
          debugPrint('✏️ $changeMsg');
        }
      }
      
    } catch (e) {
      debugPrint('⚠️ خطأ في تحديث حالات الغرف: $e');
    }
    
    return changes;
  }

  /// تسجيل التغيير في جدول RestoreFixLog
  Future<void> _logChange({
    required String fixId,
    required String targetTable,
    required int targetRecordId,
    required String fieldName,
    required String oldValue,
    required String newValue,
    required String reason,
    required String fixType,
  }) async {
    await db.into(db.restoreFixLog).insert(
      RestoreFixLogCompanion(
        fixId: Value(fixId),
        executedAt: Value(Time.nowEpoch()),
        targetTable: Value(targetTable),
        targetRecordId: Value(targetRecordId),
        fieldName: Value(fieldName),
        oldValue: Value(oldValue),
        newValue: Value(newValue),
        reason: Value(reason),
        fixType: Value(fixType),
      ),
    );
  }

  /// استعادة البيانات من اللقطة الاحتياطية
  Future<void> _restoreFromSnapshot(String snapshotPath) async {
    try {
      final file = File(snapshotPath);
      if (!await file.exists()) {
        throw Exception('ملف اللقطة الاحتياطية غير موجود: $snapshotPath');
      }
      
      final jsonString = await file.readAsString();
      final snapshotData = jsonDecode(jsonString) as Map<String, dynamic>;
      
      await db.transaction(() async {
        // مسح الجداول المتأثرة
        await db.delete(db.bookings).go();
        await db.delete(db.rooms).go();
        await db.delete(db.payments).go();
        
        // استعادة البيانات
        if (snapshotData.containsKey('bookings')) {
          await bookingsDao.importFromJson(snapshotData['bookings'], clearExisting: false);
        }
        if (snapshotData.containsKey('rooms')) {
          await roomsDao.importFromJson(snapshotData['rooms'], clearExisting: false);
        }
        if (snapshotData.containsKey('payments')) {
          await paymentsDao.importFromJson(snapshotData['payments'], clearExisting: false);
        }
      });
      
    } catch (e) {
      debugPrint('❌ فشل في استعادة اللقطة الاحتياطية: $e');
      rethrow;
    }
  }

  /// حذف ملف اللقطة الاحتياطية
  Future<void> _deleteSnapshot(String filePath) async {
    try {
      final file = File(filePath);
      if (await file.exists()) {
        await file.delete();
        debugPrint('🗑️ تم حذف اللقطة الاحتياطية: $filePath');
      }
    } catch (e) {
      debugPrint('⚠️ تحذير: لا يمكن حذف اللقطة الاحتياطية: $e');
    }
  }

  /// الحصول على سجلات الإصلاح
  Future<List<RestoreFixLogData>> getFixLogs({String? fixId, int? limit}) async {
    final query = db.select(db.restoreFixLog);
    
    if (fixId != null) {
      query.where((log) => log.fixId.equals(fixId));
    }
    
    query.orderBy([(log) => OrderingTerm(expression: log.executedAt, mode: OrderingMode.desc)]);
    
    if (limit != null) {
      query.limit(limit);
    }
    
    return await query.get();
  }

  /// تصدير سجلات الإصلاح كـ JSON
  Future<Map<String, dynamic>> exportFixLogsAsJson({String? fixId}) async {
    final logs = await getFixLogs(fixId: fixId);
    
    return {
      'fix_id': fixId ?? 'all',
      'exported_at': DateTime.now().toIso8601String(),
      'total_logs': logs.length,
      'logs': logs.map((log) => {
        'id': log.id,
        'fix_id': log.fixId,
        'executed_at': log.executedAt,
        'executed_at_iso': DateTime.fromMillisecondsSinceEpoch(log.executedAt * 1000).toIso8601String(),
        'target_table': log.targetTable,
        'target_record_id': log.targetRecordId,
        'field_name': log.fieldName,
        'old_value': log.oldValue,
        'new_value': log.newValue,
        'reason': log.reason,
        'fix_type': log.fixType,
      }).toList(),
    };
  }
}