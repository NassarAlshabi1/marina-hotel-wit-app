// test/unit/sync_health_monitor_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/sync_health_monitor.dart';

// مساعد لإنشاء تقرير للاختبار
SyncHealthReport _makeReport({Duration? oldestPendingAge, SyncHealthStatus status = SyncHealthStatus.healthy}) {
  return SyncHealthReport(
    pendingCount: 0,
    processingCount: 0,
    failedCount: 0,
    completedCount: 0,
    oldestPendingAge: oldestPendingAge,
    stuckProcessingCount: 0,
    entityBreakdown: const {},
    tableSizes: const {},
    fkViolations: 0,
    status: status,
    timestamp: DateTime(2026, 1, 1),
  );
}

void main() {
  group('SyncHealthStatus', () {
    test('label returns correct Arabic label', () {
      expect(SyncHealthStatus.healthy.label, equals('صحي'));
      expect(SyncHealthStatus.ok.label, equals('جيد'));
      expect(SyncHealthStatus.warning.label, equals('تحذير'));
      expect(SyncHealthStatus.error.label, equals('خطأ'));
      expect(SyncHealthStatus.critical.label, equals('حرج'));
      expect(SyncHealthStatus.unknown.label, equals('غير معروف'));
    });

    test('emoji returns correct emoji', () {
      expect(SyncHealthStatus.healthy.emoji, equals('✅'));
      expect(SyncHealthStatus.ok.emoji, equals('🟢'));
      expect(SyncHealthStatus.warning.emoji, equals('🟡'));
      expect(SyncHealthStatus.error.emoji, equals('🔴'));
      expect(SyncHealthStatus.critical.emoji, equals('🚨'));
      expect(SyncHealthStatus.unknown.emoji, equals('❓'));
    });
  });

  group('SyncHealthReport', () {
    test('oldestPendingAgeFormatted returns "—" when null', () {
      final report = _makeReport(oldestPendingAge: null);
      expect(report.oldestPendingAgeFormatted, equals('—'));
    });

    test('oldestPendingAgeFormatted formats minutes correctly', () {
      final report = _makeReport(oldestPendingAge: const Duration(minutes: 5), status: SyncHealthStatus.ok);
      expect(report.oldestPendingAgeFormatted, equals('5 دقيقة'));
    });

    test('oldestPendingAgeFormatted formats hours correctly', () {
      final report = _makeReport(oldestPendingAge: const Duration(minutes: 90), status: SyncHealthStatus.warning);
      expect(report.oldestPendingAgeFormatted, contains('ساعة'));
    });

    test('oldestPendingAgeFormatted formats days correctly', () {
      final report = _makeReport(
        oldestPendingAge: const Duration(minutes: 1500), // 25 ساعة
        status: SyncHealthStatus.error,
      );
      final formatted = report.oldestPendingAgeFormatted;
      expect(formatted, contains('يوم'));
    });
  });
}
