// lib/services/sync_health_monitor.dart
import 'dart:async';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter/foundation.dart';

import 'local_db.dart';

/// خدمة مراقبة صحة نظام المزامنة.
///
/// تجمع مؤشرات حيوية عن حالة المزامنة:
/// - عدد عناصر outbox المعلقة
/// - عمر أقدم عنصر في outbox
/// - عدد العناصر العالقة في 'processing'
/// - آخر مزامنة ناجحة
/// - معدل الفشل
/// - حجم البيانات المُزامنة
class SyncHealthMonitor {
  SyncHealthMonitor._();
  static final SyncHealthMonitor instance = SyncHealthMonitor._();

  /// الحد الأقصى لعمر عنصر معلق قبل اعتباره "عالقاً"
  static const Duration stuckThreshold = Duration(minutes: 10);

  /// الحد الأقصى لعنصر في 'processing' قبل اعتباره معلقاً
  static const Duration processingStuckThreshold = Duration(minutes: 5);

  /// الحصول على تقرير صحة المزامنة الشامل.
  ///
  /// يُرجع [SyncHealthReport] يحتوي على كل المؤشرات الحيوية.
  Future<SyncHealthReport> getHealthReport(AppDatabase db) async {
    try {
      // 1. عدد عناصر outbox حسب الحالة
      final pendingCount = await _countOutboxByStatus(db, 'pending');
      final processingCount = await _countOutboxByStatus(db, 'processing');
      final failedCount = await _countOutboxByStatus(db, 'failed');
      final completedCount = await _countOutboxByStatus(db, 'completed');

      // 2. عمر أقدم عنصر معلق
      final oldestPendingAge = await _getOldestPendingAge(db);

      // 3. عدد العناصر العالقة في processing
      final stuckProcessingCount = await _getStuckProcessingCount(db);

      // 4. إحصائيات حسب entity
      final entityBreakdown = await _getEntityBreakdown(db);

      // 5. حجم الجداول الرئيسية
      final tableSizes = await _getTableSizes(db);

      // 6. حالة FK
      final fkViolations = await _getFkViolations(db);

      // 7. حساب الحالة العامة
      final status = _computeOverallStatus(
        pendingCount: pendingCount,
        failedCount: failedCount,
        stuckProcessingCount: stuckProcessingCount,
        oldestPendingAge: oldestPendingAge,
        fkViolations: fkViolations,
      );

      return SyncHealthReport(
        pendingCount: pendingCount,
        processingCount: processingCount,
        failedCount: failedCount,
        completedCount: completedCount,
        oldestPendingAge: oldestPendingAge,
        stuckProcessingCount: stuckProcessingCount,
        entityBreakdown: entityBreakdown,
        tableSizes: tableSizes,
        fkViolations: fkViolations,
        status: status,
        timestamp: DateTime.now(),
      );
    } catch (e, st) {
      debugPrint('❌ SyncHealthMonitor.getHealthReport failed: $e\n$st');
      return SyncHealthReport(
        pendingCount: 0,
        processingCount: 0,
        failedCount: 0,
        completedCount: 0,
        oldestPendingAge: null,
        stuckProcessingCount: 0,
        entityBreakdown: {},
        tableSizes: {},
        fkViolations: 0,
        status: SyncHealthStatus.unknown,
        timestamp: DateTime.now(),
        error: e.toString(),
      );
    }
  }

  Future<int> _countOutboxByStatus(AppDatabase db, String status) async {
    try {
      final result = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM outbox WHERE processing_status = ?',
            variables: [Variable.withString(status)],
            readsFrom: {db.outbox},
          )
          .getSingle();
      return result.read<int>('cnt');
    } catch (e) {
      debugPrint('⚠️ Swallowed error in sync_health_monitor.dart: ');
      return 0;
    }
  }

  Future<Duration?> _getOldestPendingAge(AppDatabase db) async {
    try {
      final result = await db
          .customSelect(
            'SELECT MIN(client_ts) AS oldest FROM outbox WHERE processing_status = ?',
            variables: [Variable.withString('pending')],
            readsFrom: {db.outbox},
          )
          .getSingle();
      final oldest = result.data['oldest'];
      if (oldest == null) return null;
      final oldestEpoch = (oldest is int)
          ? oldest
          : (oldest is num)
          ? oldest.toInt()
          : int.tryParse(oldest.toString()) ?? 0;
      if (oldestEpoch == 0) return null;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return Duration(seconds: now - oldestEpoch);
    } catch (e) {
      debugPrint('⚠️ Swallowed error in sync_health_monitor.dart: ');
      return null;
    }
  }

  Future<int> _getStuckProcessingCount(AppDatabase db) async {
    try {
      final thresholdSec =
          DateTime.now()
              .subtract(processingStuckThreshold)
              .millisecondsSinceEpoch ~/
          1000;
      final result = await db
          .customSelect(
            'SELECT COUNT(*) AS cnt FROM outbox WHERE processing_status = ? '
            'AND processing_started_at < ?',
            variables: [
              Variable.withString('processing'),
              Variable.withInt(thresholdSec),
            ],
            readsFrom: {db.outbox},
          )
          .getSingle();
      return result.read<int>('cnt');
    } catch (e) {
      debugPrint('⚠️ Swallowed error in sync_health_monitor.dart: ');
      return 0;
    }
  }

  Future<Map<String, int>> _getEntityBreakdown(AppDatabase db) async {
    try {
      final result = await db
          .customSelect(
            'SELECT entity, COUNT(*) AS cnt FROM outbox '
            'WHERE processing_status IN (?, ?) GROUP BY entity',
            variables: [
              Variable.withString('pending'),
              Variable.withString('failed'),
            ],
            readsFrom: {db.outbox},
          )
          .get();
      return {
        for (final row in result)
          row.read<String>('entity'): row.read<int>('cnt'),
      };
    } catch (e) {
      debugPrint('⚠️ Swallowed error in sync_health_monitor.dart: ');
      return {};
    }
  }

  Future<Map<String, int>> _getTableSizes(AppDatabase db) async {
    final tables = [
      'rooms',
      'bookings',
      'payments',
      'debts',
      'expenses',
      'employees',
      'booking_nights',
      'booking_notes',
      'booking_price_adjustments',
      'cash_transactions',
      'shift_notes',
      'salary_cycles',
      'salary_payments',
      'salary_withdrawals',
      'price_adjustments',
      'audit_logs',
      'payment_voids',
      'guest_infos',
      'hotel_day_ledger',
      'outbox',
    ];
    final sizes = <String, int>{};
    for (final table in tables) {
      try {
        final result = await db
            .customSelect('SELECT COUNT(*) AS cnt FROM $table')
            .getSingle();
        sizes[table] = result.read<int>('cnt');
      } catch (e, st) {
      debugPrint('⚠️ Swallowed error in sync_health_monitor.dart: ');
        sizes[table] = -1; // خطأ
      }
    }
    return sizes;
  }

  Future<int> _getFkViolations(AppDatabase db) async {
    try {
      final result = await db.customSelect('PRAGMA foreign_key_check').get();
      return result.length;
    } catch (e) {
      debugPrint('⚠️ Swallowed error in sync_health_monitor.dart: ');
      return 0;
    }
  }

  SyncHealthStatus _computeOverallStatus({
    required int pendingCount,
    required int failedCount,
    required int stuckProcessingCount,
    required Duration? oldestPendingAge,
    required int fkViolations,
  }) {
    // critical: FK violations أو عناصر عالقة كثيرة
    if (fkViolations > 0 || stuckProcessingCount > 10) {
      return SyncHealthStatus.critical;
    }
    // error: فشل كثير أو عناصر معلقة قديمة جداً
    if (failedCount > 20 ||
        (oldestPendingAge != null && oldestPendingAge > stuckThreshold)) {
      return SyncHealthStatus.error;
    }
    // warning: فشل متوسط أو عناصر معلقة كثيرة
    if (failedCount > 5 || pendingCount > 100 || stuckProcessingCount > 0) {
      return SyncHealthStatus.warning;
    }
    // healthy: كل شيء طبيعي
    if (pendingCount == 0 && failedCount == 0) {
      return SyncHealthStatus.healthy;
    }
    return SyncHealthStatus.ok;
  }
}

/// تقرير صحة المزامنة
class SyncHealthReport {
  const SyncHealthReport({
    required this.pendingCount,
    required this.processingCount,
    required this.failedCount,
    required this.completedCount,
    required this.oldestPendingAge,
    required this.stuckProcessingCount,
    required this.entityBreakdown,
    required this.tableSizes,
    required this.fkViolations,
    required this.status,
    required this.timestamp,
    this.error,
  });

  final int pendingCount;
  final int processingCount;
  final int failedCount;
  final int completedCount;
  final Duration? oldestPendingAge;
  final int stuckProcessingCount;
  final Map<String, int> entityBreakdown;
  final Map<String, int> tableSizes;
  final int fkViolations;
  final SyncHealthStatus status;
  final DateTime timestamp;
  final String? error;

  /// تنسيق عمر أقدم عنصر كنص مقروء
  String get oldestPendingAgeFormatted {
    if (oldestPendingAge == null) return '—';
    final mins = oldestPendingAge!.inMinutes;
    if (mins < 60) return '$mins دقيقة';
    final hours = mins ~/ 60;
    final remMins = mins % 60;
    if (hours < 24) return '$hours ساعة $remMins دقيقة';
    final days = hours ~/ 24;
    return '$days يوم ${hours % 24} ساعة';
  }

  @override
  String toString() =>
      'SyncHealthReport(status: $status, '
      'pending: $pendingCount, failed: $failedCount, '
      'stuck: $stuckProcessingCount, fkViolations: $fkViolations)';
}

/// حالات صحة المزامنة
enum SyncHealthStatus {
  /// صحي — كل شيء طبيعي
  healthy,

  /// جيد — بعض العناصر المعلقة لكن لا مشاكل
  ok,

  /// تحذير — فشل متوسط أو عناصر عالقة
  warning,

  /// خطأ — فشل كثير أو عناصر قديمة جداً
  error,

  /// حرج — انتهاكات FK أو عناصر عالقة كثيرة
  critical,

  /// غير معروف — خطأ في القراءة
  unknown,
}

extension SyncHealthStatusX on SyncHealthStatus {
  String get label {
    switch (this) {
      case SyncHealthStatus.healthy:
        return 'صحي';
      case SyncHealthStatus.ok:
        return 'جيد';
      case SyncHealthStatus.warning:
        return 'تحذير';
      case SyncHealthStatus.error:
        return 'خطأ';
      case SyncHealthStatus.critical:
        return 'حرج';
      case SyncHealthStatus.unknown:
        return 'غير معروف';
    }
  }

  String get emoji {
    switch (this) {
      case SyncHealthStatus.healthy:
        return '✅';
      case SyncHealthStatus.ok:
        return '🟢';
      case SyncHealthStatus.warning:
        return '🟡';
      case SyncHealthStatus.error:
        return '🔴';
      case SyncHealthStatus.critical:
        return '🚨';
      case SyncHealthStatus.unknown:
        return '❓';
    }
  }
}
