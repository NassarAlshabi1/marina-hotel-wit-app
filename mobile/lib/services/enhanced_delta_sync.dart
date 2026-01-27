import 'package:flutter/foundation.dart';
import 'google_drive_delta_sync.dart';
import 'google_drive_backup_service.dart';
import 'local_db.dart';
import '../utils/debug_logs.dart';

/// تحسينات احترافية لـ Delta Sync لزيادة الموثوقية وتقليل الفشل
class EnhancedDeltaSync {
  final GoogleDriveDeltaSync _deltaSync;
  final GoogleDriveBackupService _driveService;
  final AppDatabase _db;

  EnhancedDeltaSync({
    required GoogleDriveDeltaSync deltaSync,
    required GoogleDriveBackupService driveService,
    required AppDatabase db,
  })  : _deltaSync = deltaSync,
        _driveService = driveService,
        _db = db;

  void _log(String message) {
    DebugLogs.add('EnhancedDelta', message);
    debugPrint(message);
  }

  /// محاولة Push مع إعادة المحاولة التلقائية
  Future<DeltaSyncResult> pushWithRetry({int maxRetries = 3}) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      attempts++;

      try {
        _log('📤 محاولة Push Delta ($attempts/$maxRetries)...');

        // التحقق من سلامة البيانات قبل الإرسال
        final integrityCheck = await _checkDataIntegrity();
        if (!integrityCheck.isValid) {
          _log(
              '⚠️ مشكلة في سلامة البيانات: ${integrityCheck.issues.join(", ")}');

          // محاولة إصلاح المشاكل البسيطة
          if (integrityCheck.isRepairable) {
            await _repairIntegrityIssues(integrityCheck);
          }
        }

        final result = await _deltaSync.pushDeltaChanges();

        if (result.success) {
          _log('✅ Delta Push نجح في المحاولة $attempts');
          return result;
        }

        // تحليل سبب الفشل
        final failureReason = _analyzeFailure(result.message ?? '');
        _log('⚠️ فشل Delta Push: $failureReason');

        // إذا كان الفشل دائم (permanent failure)، لا نعيد المحاولة
        if (failureReason == FailureReason.permanent) {
          return result;
        }

        // انتظار قبل إعادة المحاولة
        if (attempts < maxRetries) {
          final delaySeconds = _calculateBackoffDelay(attempts);
          _log('⏳ انتظار $delaySeconds ثانية قبل إعادة المحاولة...');
          await Future.delayed(Duration(seconds: delaySeconds));
        }
      } catch (e) {
        _log('❌ خطأ في Delta Push: $e');

        if (attempts >= maxRetries) {
          return DeltaSyncResult(
            success: false,
            message: 'فشل بعد $maxRetries محاولات: $e',
            changesCount: 0,
          );
        }
      }
    }

    return DeltaSyncResult(
      success: false,
      message: 'فشل Delta Push بعد $maxRetries محاولات',
      changesCount: 0,
    );
  }

  /// محاولة Pull مع إعادة المحاولة التلقائية
  Future<DeltaSyncResult> pullWithRetry({int maxRetries = 3}) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      attempts++;

      try {
        _log('📥 محاولة Pull Delta ($attempts/$maxRetries)...');

        final result = await _deltaSync.pullDeltaChanges();

        if (result.success) {
          _log('✅ Delta Pull نجح في المحاولة $attempts');

          // التحقق من سلامة البيانات بعد Pull
          final integrityCheck = await _checkDataIntegrity();
          if (!integrityCheck.isValid && integrityCheck.isRepairable) {
            _log('🔧 إصلاح مشاكل سلامة البيانات بعد Pull...');
            await _repairIntegrityIssues(integrityCheck);
          }

          return result;
        }

        // تحليل سبب الفشل
        final failureReason = _analyzeFailure(result.message ?? '');
        _log('⚠️ فشل Delta Pull: $failureReason');

        // إذا كان الفشل دائم، لا نعيد المحاولة
        if (failureReason == FailureReason.permanent) {
          return result;
        }

        // انتظار قبل إعادة المحاولة
        if (attempts < maxRetries) {
          final delaySeconds = _calculateBackoffDelay(attempts);
          _log('⏳ انتظار $delaySeconds ثانية قبل إعادة المحاولة...');
          await Future.delayed(Duration(seconds: delaySeconds));
        }
      } catch (e) {
        _log('❌ خطأ في Delta Pull: $e');

        if (attempts >= maxRetries) {
          return DeltaSyncResult(
            success: false,
            message: 'فشل بعد $maxRetries محاولات: $e',
            changesCount: 0,
          );
        }
      }
    }

    return DeltaSyncResult(
      success: false,
      message: 'فشل Delta Pull بعد $maxRetries محاولات',
      changesCount: 0,
    );
  }

  /// التحقق من سلامة البيانات
  Future<IntegrityCheckResult> _checkDataIntegrity() async {
    final result = IntegrityCheckResult();

    try {
      // التحقق من الحجوزات بدون غرف
      final orphanedBookingsQuery = await _db
          .customSelect(
            'SELECT COUNT(*) as count FROM bookings WHERE room_number NOT IN (SELECT room_number FROM rooms)',
          )
          .getSingle();
      final orphanedBookingsCount = orphanedBookingsQuery.data['count'] as int;

      if (orphanedBookingsCount > 0) {
        result.issues.add('$orphanedBookingsCount حجوزات بدون غرف');
        result.isRepairable = true;
      }

      // التحقق من الدفعات بدون حجوزات
      final orphanedPaymentsQuery = await _db
          .customSelect(
            'SELECT COUNT(*) as count FROM payments WHERE booking_local_id NOT IN (SELECT id FROM bookings)',
          )
          .getSingle();
      final orphanedPaymentsCount = orphanedPaymentsQuery.data['count'] as int;

      if (orphanedPaymentsCount > 0) {
        result.issues.add('$orphanedPaymentsCount دفعات بدون حجوزات');
        result.isRepairable = true;
      }

      // التحقق من تضارب الـ UUIDs
      final duplicateUuidsQuery = await _db
          .customSelect(
            'SELECT local_uuid, COUNT(*) as count FROM bookings GROUP BY local_uuid HAVING count > 1',
          )
          .get();

      if (duplicateUuidsQuery.isNotEmpty) {
        result.issues
            .add('${duplicateUuidsQuery.length} UUIDs مكررة في الحجوزات');
        result.isRepairable = false; // يحتاج تدخل يدوي
      }

      result.isValid = result.issues.isEmpty;
    } catch (e) {
      _log('❌ خطأ في فحص سلامة البيانات: $e');
      result.isValid = false;
      result.issues.add('فشل الفحص: $e');
    }

    return result;
  }

  /// إصلاح مشاكل سلامة البيانات
  Future<void> _repairIntegrityIssues(IntegrityCheckResult check) async {
    if (!check.isRepairable) {
      _log('⚠️ لا يمكن إصلاح المشاكل تلقائياً');
      return;
    }

    try {
      await _db.transaction(() async {
        // حذف الحجوزات اليتيمة
        await _db.customStatement(
          'DELETE FROM bookings WHERE room_number NOT IN (SELECT room_number FROM rooms)',
        );

        // حذف الدفعات اليتيمة
        await _db.customStatement(
          'DELETE FROM payments WHERE booking_id NOT IN (SELECT id FROM bookings)',
        );

        // حذف الملاحظات اليتيمة
        await _db.customStatement(
          'DELETE FROM booking_notes WHERE booking_id NOT IN (SELECT id FROM bookings)',
        );
      });

      _log('✅ تم إصلاح مشاكل سلامة البيانات');
    } catch (e) {
      _log('❌ فشل إصلاح مشاكل البيانات: $e');
    }
  }

  /// تحليل سبب فشل المزامنة
  FailureReason _analyzeFailure(String errorMessage) {
    final lowerMsg = errorMessage.toLowerCase();

    // أخطاء شبكة مؤقتة
    if (lowerMsg.contains('network') ||
        lowerMsg.contains('timeout') ||
        lowerMsg.contains('connection')) {
      return FailureReason.network;
    }

    // أخطاء صلاحيات
    if (lowerMsg.contains('auth') ||
        lowerMsg.contains('permission') ||
        lowerMsg.contains('unauthorized')) {
      return FailureReason.auth;
    }

    // أخطاء تضارب البيانات
    if (lowerMsg.contains('conflict') ||
        lowerMsg.contains('constraint') ||
        lowerMsg.contains('unique')) {
      return FailureReason.conflict;
    }

    // أخطاء دائمة
    if (lowerMsg.contains('not found') ||
        lowerMsg.contains('invalid format') ||
        lowerMsg.contains('corrupted')) {
      return FailureReason.permanent;
    }

    // افتراضياً: خطأ مؤقت
    return FailureReason.temporary;
  }

  /// حساب وقت الانتظار قبل إعادة المحاولة (exponential backoff)
  int _calculateBackoffDelay(int attemptNumber) {
    // 2 ثانية، 4 ثواني، 8 ثواني، ...
    return (2 * attemptNumber).clamp(2, 10);
  }

  /// Fallback إلى Full Sync إذا فشل Delta Sync بشكل متكرر
  Future<bool> shouldFallbackToFullSync() async {
    // يمكن تتبع عدد الفشل المتتالي وقرار Fallback
    // هذا مثال بسيط
    return false; // يمكن تحسينه لاحقاً
  }
}

/// نتيجة فحص سلامة البيانات
class IntegrityCheckResult {
  bool isValid = true;
  bool isRepairable = false;
  List<String> issues = [];
}

/// أسباب فشل المزامنة
enum FailureReason {
  network, // مشكلة شبكة مؤقتة
  auth, // مشكلة صلاحيات
  conflict, // تضارب بيانات
  temporary, // خطأ مؤقت
  permanent, // خطأ دائم (لا يمكن إعادة المحاولة)
}
