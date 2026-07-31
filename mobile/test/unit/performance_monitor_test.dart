import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/performance_monitor.dart';

void main() {
  group('PerformanceMonitor', () {
    test('should be a singleton', () {
      expect(PerformanceMonitor.instance, same(PerformanceMonitor.instance));
    });

    test('isInitialized should be false before initialize', () {
      expect(PerformanceMonitor.instance.isInitialized, isFalse);
    });

    test('startTrace should return null when not initialized', () {
      final trace = PerformanceMonitor.instance.startTrace('test');
      expect(trace, isNull);
    });

    test('stopTrace should not throw with null trace', () async {
      await PerformanceMonitor.instance.stopTrace(null);
      expect(true, isTrue);
    });

    test(
      'traceOperation should execute operation even when not initialized',
      () async {
        final result = await PerformanceMonitor.instance.traceOperation(
          'test_operation',
          operation: () async => 42,
        );
        expect(result, 42);
      },
    );

    test('traceOperation should rethrow errors', () async {
      expect(
        () => PerformanceMonitor.instance.traceOperation(
          'failing_operation',
          operation: () async => throw Exception('test error'),
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('traceSyncPush should work when not initialized', () async {
      final result = await PerformanceMonitor.instance.traceSyncPush(
        operation: () async => 'pushed',
        itemsCount: 10,
      );
      expect(result, 'pushed');
    });

    test('traceSyncPull should work when not initialized', () async {
      final result = await PerformanceMonitor.instance.traceSyncPull(
        operation: () async => 'pulled',
        itemsCount: 5,
      );
      expect(result, 'pulled');
    });

    test('traceBookingCreate should work when not initialized', () async {
      final result = await PerformanceMonitor.instance.traceBookingCreate(
        operation: () async => 'booking-123',
        roomNumber: '101',
      );
      expect(result, 'booking-123');
    });

    test('tracePaymentProcess should work when not initialized', () async {
      final result = await PerformanceMonitor.instance.tracePaymentProcess(
        operation: () async => 'payment-456',
        method: 'cash',
        amount: 50000,
      );
      expect(result, 'payment-456');
    });

    test('tracePdfGeneration should work when not initialized', () async {
      final result = await PerformanceMonitor.instance.tracePdfGeneration(
        operation: () async => 'pdf-bytes',
        type: 'invoice',
      );
      expect(result, 'pdf-bytes');
    });

    test('traceBackup should work when not initialized', () async {
      final result = await PerformanceMonitor.instance.traceBackup(
        operation: () async => 'backup-done',
        destination: 'google_drive',
      );
      expect(result, 'backup-done');
    });
  });
}
