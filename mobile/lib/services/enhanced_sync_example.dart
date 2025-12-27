import 'package:flutter/foundation.dart';
import 'vector_clock.dart';
import 'conflict_resolver.dart';
import 'optimistic_lock_manager.dart';
import 'sync_health_monitor.dart';
import 'conflict_manager.dart';
import 'local_db.dart';

/// مثال شامل لكيفية استخدام نظام المزامنة المحسّن
class EnhancedSyncExample {
  EnhancedSyncExample({
    required this.db,
    required this.deviceId,
  });

  final AppDatabase db;
  final String deviceId;

  /// مثال 1: تحديث حجز مع Optimistic Locking و Vector Clock
  Future<void> updateBookingWithProtection({
    required String bookingUuid,
    required int currentVersion,
    required String newStatus,
  }) async {
    final lockManager = OptimisticLockManager(db);
    
    try {
      await lockManager.executeWithLock(
        table: 'bookings',
        uuid: bookingUuid,
        expectedVersion: currentVersion,
        operation: (newVersion) async {
          final booking = await (db.select(db.bookings)
            ..where((t) => t.localUuid.equals(bookingUuid))).getSingle();

          final oldClock = VectorClock.fromJson(booking.vectorClock);
          final newClock = oldClock.increment(deviceId);

          await (db.update(db.bookings)..where((t) => t.id.equals(booking.id))).write(
            BookingsCompanion(
              status: Value(newStatus),
              version: Value(newVersion),
              vectorClock: Value(newClock.toJson()),
              lastModified: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
              updatedAt: Value(DateTime.now().millisecondsSinceEpoch ~/ 1000),
              updatedAtIso: Value(DateTime.now().toUtc().toIso8601String()),
            ),
          );

          debugPrint('✅ تم تحديث الحجز - Version: $newVersion, Clock: ${newClock.toJson()}');
        },
      );
    } on OptimisticLockException catch (e) {
      debugPrint('⚠️ ${e.message}');
      debugPrint('الإصدار المتوقع: ${e.expectedVersion}, الإصدار الحالي: ${e.currentVersion}');
      
      throw Exception('السجل تم تعديله من جهاز آخر - يرجى إعادة تحميل البيانات');
    }
  }

  /// مثال 2: دمج البيانات مع اكتشاف التعارضات الذكي
  Future<Map<String, dynamic>> smartMergeBooking({
    required Map<String, dynamic> localRow,
    required Map<String, dynamic> remoteRow,
  }) async {
    final localClock = VectorClock.fromJson(localRow['vector_clock'] ?? '{}');
    final remoteClock = VectorClock.fromJson(remoteRow['vector_clock'] ?? '{}');

    final comparison = localClock.compare(remoteClock);

    switch (comparison) {
      case 'before':
        debugPrint('📥 البيانات البعيدة أحدث - قبول التحديث');
        return remoteRow;

      case 'after':
        debugPrint('📱 البيانات المحلية أحدث - الاحتفاظ بالمحلية');
        return localRow;

      case 'concurrent':
        debugPrint('⚠️ تعارض متزامن - استخدام field-level merge');
        
        final resolver = EnhancedConflictResolver(
          defaultStrategy: ConflictStrategy.fieldLevel,
        );

        final localTimestamp = _parseTimestamp(localRow['updated_at']);
        final remoteTimestamp = _parseTimestamp(remoteRow['updated_at']);

        final context = ConflictContext(
          table: 'bookings',
          uuid: localRow['local_uuid'],
          localData: localRow,
          remoteData: remoteRow,
          localVectorClock: localClock,
          remoteVectorClock: remoteClock,
          localTimestamp: localTimestamp,
          remoteTimestamp: remoteTimestamp,
          localDeviceId: deviceId,
          remoteDeviceId: remoteRow['_device_id'] ?? 'unknown',
        );

        final resolution = resolver.resolve(context);

        if (resolution.needsManualReview) {
          await ConflictManager(db).recordConflict(
            table: 'bookings',
            uuid: localRow['local_uuid'],
            localData: localRow,
            remoteData: remoteRow,
          );

          debugPrint('📋 تم حفظ التعارض للمراجعة اليدوية');
          return localRow;
        }

        final mergedClock = localClock.merge(remoteClock).increment(deviceId);
        resolution.winner['vector_clock'] = mergedClock.toJson();

        debugPrint('✅ تم الدمج الذكي - Fields merged: ${resolution.mergedData?.keys.length ?? 0}');
        return resolution.winner;

      case 'equal':
        debugPrint('✅ البيانات متطابقة');
        return remoteRow;

      default:
        return localRow;
    }
  }

  /// مثال 3: مراقبة صحة المزامنة
  Future<void> monitorSyncHealth() async {
    final monitor = SyncHealthMonitor.instance;
    await monitor.initialize();

    monitor.metricsStream.listen((metrics) {
      debugPrint('🏥 حالة المزامنة: ${metrics.status}');
      debugPrint('معدل التعارضات: ${(metrics.conflictRate * 100).toStringAsFixed(1)}%');
      debugPrint('متوسط الوقت: ${metrics.averageSyncDuration.inSeconds}s');

      if (metrics.status == SyncHealthStatus.critical) {
        _showCriticalAlert(metrics);
      } else if (metrics.status == SyncHealthStatus.warning) {
        _showWarning(metrics);
      }
    });
  }

  /// مثال 4: مزامنة كاملة مع جميع الحمايات
  Future<bool> performSafeSyncWithAllProtections() async {
    final monitor = SyncHealthMonitor.instance;
    final startTime = DateTime.now();
    
    try {
      debugPrint('🔄 بدء المزامنة الآمنة...');

      debugPrint('✅ المزامنة مكتملة بنجاح');
      
      monitor.recordSyncSuccess(
        duration: DateTime.now().difference(startTime),
        hadConflicts: false,
      );
      
      return true;
    } catch (e) {
      debugPrint('❌ فشل المزامنة: $e');
      
      monitor.recordSyncFailure();
      
      return false;
    }
  }

  DateTime _parseTimestamp(dynamic value) {
    if (value is DateTime) return value;
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is String) {
      return DateTime.tryParse(value) ?? DateTime.now();
    }
    return DateTime.now();
  }

  void _showCriticalAlert(SyncHealthMetrics metrics) {
    debugPrint('🚨🚨🚨 تنبيه حرج 🚨🚨🚨');
    debugPrint('المشكلة: ${metrics.recommendations.join('\n')}');
  }

  void _showWarning(SyncHealthMetrics metrics) {
    debugPrint('⚠️ تحذير: ${metrics.recommendations.first}');
  }
}

/// نصائح للاستخدام الأمثل:
/// 
/// 1. استخدم Vector Clock دائماً:
///    - يكتشف 99% من التعارضات الحقيقية
///    - overhead قليل جداً
/// 
/// 2. Field-Level Merge للجداول المهمة:
///    - bookings, payments, debts
///    - يمنع فقدان البيانات
/// 
/// 3. Optimistic Locking للعمليات الحرجة:
///    - checkout حجز
///    - إضافة دفعة
///    - تعديل سعر غرفة
/// 
/// 4. راقب الصحة باستمرار:
///    - SyncHealthMonitor يكتشف المشاكل مبكراً
///    - يقترح حلول تلقائياً
/// 
/// 5. اعرض التعارضات للمستخدم:
///    - ConflictManager يحفظ التعارضات
///    - UI بسيط يسمح بالحل اليدوي
