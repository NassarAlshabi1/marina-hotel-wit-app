// lib/services/performance_monitor.dart
// مراقبة الأداء — Firebase Performance Trace API للمزامنة والعمليات الحرجة
//
// يستخدم Firebase Performance Monitoring لتتبع:
// - مدة عمليات المزامنة (push, pull)
// - مدة إنشاء الحجوزات
// - مدة معالجة المدفوعات
// - مدة توليد PDF
// - مدة النسخ الاحتياطي

import 'dart:developer' as developer;
import 'package:firebase_performance/firebase_performance.dart';
import 'package:flutter/foundation.dart';

/// مراقب أداء يستخدم Firebase Performance Trace API
class PerformanceMonitor {
  factory PerformanceMonitor() => _instance;
  PerformanceMonitor._internal();
  static final PerformanceMonitor _instance = PerformanceMonitor._internal();
  static PerformanceMonitor get instance => _instance;

  bool _isInitialized = false;
  FirebasePerformance? _performance;

  bool get isInitialized => _isInitialized;

  /// تهيئة مراقب الأداء
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      _performance = FirebasePerformance.instance;
      await _performance!.setPerformanceCollectionEnabled(!kDebugMode);
      _isInitialized = true;
      developer.log('✅ PerformanceMonitor initialized', name: 'PerformanceMonitor');
    } catch (e) {
      developer.log('⚠️ PerformanceMonitor init failed: $e', name: 'PerformanceMonitor');
      // لا نوقف التطبيق
      _isInitialized = false;
    }
  }

  /// بدء تتبع عملية
  ///
  /// الاستخدام:
  /// ```dart
  /// final trace = PerformanceMonitor.instance.startTrace('sync_push');
  /// // ... عملية المزامنة ...
  /// await PerformanceMonitor.instance.stopTrace(trace, attributes: {
  ///   'items_pushed': '10',
  ///   'success': 'true',
  /// });
  /// ```
  Trace? startTrace(String name) {
    if (!_isInitialized || _performance == null) return null;

    try {
      final trace = _performance!.newTrace(name);
      trace.start();
      return trace;
    } catch (e) {
      return null;
    }
  }

  /// إيقاف تتبع عملية مع سمات إضافية
  Future<void> stopTrace(
    Trace? trace, {
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    if (trace == null) return;

    try {
      if (attributes != null) {
        for (final entry in attributes.entries) {
          trace.putAttribute(entry.key, entry.value);
        }
      }
      if (metrics != null) {
        for (final entry in metrics.entries) {
          trace.setMetric(entry.key, entry.value);
        }
      }
      await trace.stop();
    } catch (e) {
      // تجاهل
    }
  }

  /// تنفيذ عملية مع تتبع تلقائي
  ///
  /// الاستخدام:
  /// ```dart
  /// final result = await PerformanceMonitor.instance.traceOperation(
  ///   'booking_create',
  ///   operation: () => createBooking(data),
  ///   attributes: {'room_number': '101'},
  /// );
  /// ```
  Future<T> traceOperation<T>(
    String name, {
    required Future<T> Function() operation,
    Map<String, String>? attributes,
    Map<String, int>? metrics,
  }) async {
    final trace = startTrace(name);
    final stopwatch = Stopwatch()..start();

    try {
      final result = await operation();
      stopwatch.stop();

      await stopTrace(
        trace,
        attributes: {
          ...?attributes,
          'success': 'true',
        },
        metrics: {
          ...?metrics,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );

      return result;
    } catch (e) {
      stopwatch.stop();

      await stopTrace(
        trace,
        attributes: {
          ...?attributes,
          'success': 'false',
          'error': e.runtimeType.toString(),
        },
        metrics: {
          ...?metrics,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      );

      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  //  Traces predefined للمزامنة (أهم العمليات)
  // ═══════════════════════════════════════════════════════════════

  /// تتبع عملية push للمزامنة
  Future<T> traceSyncPush<T>({
    required Future<T> Function() operation,
    int? itemsCount,
  }) {
    return traceOperation(
      'sync_push',
      operation: operation,
      attributes: {
        'engine': 'appwrite',
        if (itemsCount != null) 'items_count': itemsCount.toString(),
      },
    );
  }

  /// تتبع عملية pull للمزامنة
  Future<T> traceSyncPull<T>({
    required Future<T> Function() operation,
    int? itemsCount,
  }) {
    return traceOperation(
      'sync_pull',
      operation: operation,
      attributes: {
        'engine': 'appwrite',
        if (itemsCount != null) 'items_count': itemsCount.toString(),
      },
    );
  }

  /// تتبع إنشاء حجز
  Future<T> traceBookingCreate<T>({
    required Future<T> Function() operation,
    String? roomNumber,
  }) {
    return traceOperation(
      'booking_create',
      operation: operation,
      attributes: {
        if (roomNumber != null) 'room_number': roomNumber,
      },
    );
  }

  /// تتبع معالجة دفعة
  Future<T> tracePaymentProcess<T>({
    required Future<T> Function() operation,
    String? method,
    double? amount,
  }) {
    return traceOperation(
      'payment_process',
      operation: operation,
      attributes: {
        if (method != null) 'method': method,
        if (amount != null) 'amount': amount.toStringAsFixed(0),
      },
    );
  }

  /// تتبع توليد PDF
  Future<T> tracePdfGeneration<T>({
    required Future<T> Function() operation,
    String? type,
  }) {
    return traceOperation(
      'pdf_generation',
      operation: operation,
      attributes: {
        if (type != null) 'type': type,
      },
    );
  }

  /// تتبع النسخ الاحتياطي
  Future<T> traceBackup<T>({
    required Future<T> Function() operation,
    String? destination,
  }) {
    return traceOperation(
      'backup',
      operation: operation,
      attributes: {
        if (destination != null) 'destination': destination,
      },
    );
  }
}
