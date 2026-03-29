// lib/services/crashlytics_service.dart
// خدمة Crashlytics لتتبع الأخطاء
// crashlytics_service.dart - خدمة تتبع الأخطاء والتحطم

import 'dart:async';
import 'dart:developer' as developer;
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// مستويات الأهمية للأخطاء
enum CrashlyticsSeverity {
  fatal, // خطأ قاتل - يوقف المزامنة
  error, // خطأ خطير - يجب الإصلاح
  warning, // تحذير - يمكن الاستمرار
  info, // معلومة - للتتبع فقط
}

/// خدمة Crashlytics لتتبع أخطاء المزامنة
class CrashlyticsService {
  factory CrashlyticsService() => _instance;
  CrashlyticsService._internal();
  static final CrashlyticsService _instance = CrashlyticsService._internal();

  FirebaseCrashlytics? _crashlytics;
  bool _isEnabled = true;
  final List<Map<String, dynamic>> _errorHistory = [];
  static const int _maxHistorySize = 100;

  /// تهيئة الخدمة
  Future<void> initialize() async {
    if (!_isEnabled || kDebugMode) {
      // في وضع التطوير، لا نفعل Crashlytics
      developer.log(
        '⚠️ Crashlytics disabled (debug mode)',
        name: 'CrashlyticsService',
      );
      return;
    }

    try {
      _crashlytics = FirebaseCrashlytics.instance;
      await _crashlytics!.setCrashlyticsCollectionEnabled(true);

      // التقاط الأخطاء غير المعالجة
      FlutterError.onError = (errorDetails) {
        _crashlytics?.recordFlutterFatalError(errorDetails);
        // استدعاء المعالج الأصلي
        FlutterError.presentError(errorDetails);
      };

      // التقاط الأخطاء في Isolate
      PlatformDispatcher.instance.onError = (error, stack) {
        _crashlytics?.recordError(error, stack, fatal: true);
        return true;
      };

      developer.log(
        '✅ CrashlyticsService initialized',
        name: 'CrashlyticsService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Crashlytics initialization failed: $e',
        name: 'CrashlyticsService',
      );
    }
  }

  /// تمكين/تعطيل الخدمة
  void setEnabled(bool enabled) {
    _isEnabled = enabled;
    _crashlytics?.setCrashlyticsCollectionEnabled(enabled);
  }

  /// تسجيل خطأ مزامنة
  Future<void> recordSyncError({
    required String operation,
    required String error,
    StackTrace? stackTrace,
    CrashlyticsSeverity severity = CrashlyticsSeverity.error,
    Map<String, dynamic> context = const {},
  }) async {
    if (!_isEnabled) return;

    final errorData = {
      'operation': operation,
      'error': error,
      'severity': severity.name,
      'timestamp': DateTime.now().toIso8601String(),
      'context': context,
    };

    // حفظ في التاريخ
    _errorHistory.add(errorData);
    if (_errorHistory.length > _maxHistorySize) {
      _errorHistory.removeAt(0);
    }

    // تسجيل محلي
    developer.log(
      '💥 Sync Error [$severity]: $operation - $error',
      name: 'CrashlyticsService',
      error: error,
      stackTrace: stackTrace,
    );

    // إرسال إلى Crashlytics
    try {
      await _crashlytics?.setCustomKey('last_sync_operation', operation);
      await _crashlytics?.setCustomKey(
        'sync_error_count',
        _errorHistory.length,
      );

      // إضافة سياق إضافي
      for (final entry in context.entries) {
        await _crashlytics?.setCustomKey(
          'sync_ctx_${entry.key}',
          entry.value.toString(),
        );
      }

      // تسجيل الخطأ
      final isFatal = severity == CrashlyticsSeverity.fatal;
      await _crashlytics?.recordError(
        Exception('[$operation] $error'),
        stackTrace ?? StackTrace.current,
        reason: operation,
        fatal: isFatal,
        information: [...context.entries.map((e) => '${e.key}: ${e.value}')],
      );
    } catch (e) {
      // لا نوقف التطبيق بسبب فشل Crashlytics
    }
  }

  /// تسجيل خطأ قاتل في المزامنة
  Future<void> recordFatalSyncError({
    required String operation,
    required dynamic error,
    StackTrace? stackTrace,
    Map<String, dynamic> context = const {},
  }) async {
    await recordSyncError(
      operation: operation,
      error: error.toString(),
      stackTrace: stackTrace,
      severity: CrashlyticsSeverity.fatal,
      context: context,
    );
  }

  /// تسجيل خطأ غير متوقع
  Future<void> recordUnexpectedError({
    required dynamic error,
    StackTrace? stackTrace,
    String? context,
  }) async {
    if (!_isEnabled) return;

    try {
      await _crashlytics?.recordError(
        error,
        stackTrace ?? StackTrace.current,
        reason: context ?? 'unexpected_error',
        fatal: false,
      );
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  /// تسجيل رسالة سجل
  Future<void> log(String message) async {
    if (!_isEnabled) return;

    try {
      await _crashlytics?.log(message);
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  /// تسجيل معرف المستخدم
  Future<void> setUserIdentifier(String userId) async {
    if (!_isEnabled) return;

    try {
      await _crashlytics?.setUserIdentifier(userId);
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  /// تعيين مفتاح مخصص
  Future<void> setCustomKey(String key, dynamic value) async {
    if (!_isEnabled) return;

    try {
      await _crashlytics?.setCustomKey(key, value.toString());
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  /// الحصول على تاريخ الأخطاء
  List<Map<String, dynamic>> getErrorHistory() =>
      List.unmodifiable(_errorHistory);

  /// مسح تاريخ الأخطاء
  void clearErrorHistory() {
    _errorHistory.clear();
  }

  /// إجبار التقرير الفوري
  Future<void> sendUnsentReports() async {
    if (!_isEnabled) return;

    try {
      await _crashlytics?.sendUnsentReports();
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  /// التحقق من وجود تقارير غير مرسلة
  Future<bool> checkForUnsentReports() async {
    if (!_isEnabled) return false;

    try {
      return await _crashlytics?.checkForUnsentReports() ?? false;
    } catch (e) {
      return false;
    }
  }

  /// حذف التقارير غير المرسلة
  Future<void> deleteUnsentReports() async {
    if (!_isEnabled) return;

    try {
      await _crashlytics?.deleteUnsentReports();
    } catch (e) {
      // تجاهل الأخطاء
    }
  }

  /// تسجيل فشل في دفعة
  Future<void> recordBatchFailure({
    required String batchId,
    required String error,
    required int itemsCount,
    required int attempt,
    StackTrace? stackTrace,
  }) async {
    await recordSyncError(
      operation: 'batch_push',
      error: 'Batch $batchId failed: $error',
      stackTrace: stackTrace,
      severity: CrashlyticsSeverity.error,
      context: {
        'batch_id': batchId,
        'items_count': itemsCount,
        'attempt': attempt,
      },
    );
  }

  /// تسجيل فشل في conflict resolution
  Future<void> recordConflictResolutionFailure({
    required String operationId,
    required String resolution,
    required String error,
    StackTrace? stackTrace,
  }) async {
    await recordSyncError(
      operation: 'conflict_resolution',
      error: 'Failed to resolve $operationId with $resolution: $error',
      stackTrace: stackTrace,
      severity: CrashlyticsSeverity.error,
      context: {'operation_id': operationId, 'resolution': resolution},
    );
  }
}
