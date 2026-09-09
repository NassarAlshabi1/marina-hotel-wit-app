import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;

import '../lib/services/cloudflare_sync_pull_service.dart';
import '../lib/services/local_db.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockResponse extends Mock implements http.Response {
  final int statusCodeValue;
  final String bodyValue;

  MockResponse({
    this.statusCodeValue = 200,
    this.bodyValue = '{"records":[]}',
  });

  @override
  int get statusCode => statusCodeValue;

  @override
  String get body => bodyValue;
}

void main() {
  group('CloudflareSyncPullService', () {
    late CloudflareSyncPullService service;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();

      service = CloudflareSyncPullService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );
    });

    test('setCredentials stores token and deviceId', () {
      service.setCredentials('test-token', 'device-123');
      expect(service.token, 'test-token');
      expect(service.deviceId, 'device-123');
    });

    test('setLastPullCursor stores cursor', () {
      service.setLastPullCursor(12345);
      expect(service.lastPullCursor, 12345);
    });

    test('pullChanges returns 0 when not initialized', () async {
      final result = await service.pullChanges();
      expect(result, 0);
    });

    test('pullChanges handles uninitialized fetch error gracefully', () async {
      // بدون setCredentials تُعيد _fetchPullPage مستقبلاً خاطئاً —
      // يلتقطه pullChanges داخلياً ويعيد 0 دون رمي استثناء
      final result = await service.pullChanges();
      expect(result, 0);
    });

    test('applyPulledRecords with empty list returns clean report', () async {
      final report = await service.applyPulledRecords([]);
      expect(report.appliedCount, 0);
      expect(report.deferredCount, 0);
      expect(report.isClean, true);
    });
  });

  group('PullApplyReport', () {
    test('creates instance with all fields', () {
      final report = PullApplyReport(
        appliedCount: 10,
        deferredCount: 2,
        touchedEntities: {'bookings', 'payments'},
        unresolvable: ['bookings/uuid-1', 'payments/uuid-2'],
        errors: [],
      );

      expect(report.appliedCount, 10);
      expect(report.deferredCount, 2);
      expect(report.touchedEntities, contains('bookings'));
      expect(report.unresolvable, hasLength(2));
      expect(report.isClean, false);
    });

    test('isClean returns true when no errors', () {
      final report = PullApplyReport(
        appliedCount: 10,
        deferredCount: 0,
        touchedEntities: {'bookings'},
        unresolvable: [],
        errors: [],
      );

      expect(report.isClean, true);
    });

    test('isClean returns false with errors', () {
      final report = PullApplyReport(
        appliedCount: 10,
        deferredCount: 0,
        touchedEntities: {'bookings'},
        unresolvable: ['bookings/uuid-1'],
        errors: [],
      );

      expect(report.isClean, false);
    });

    test('isClean returns false with unresolvable records', () {
      final report = PullApplyReport(
        appliedCount: 10,
        deferredCount: 2,
        touchedEntities: {'bookings'},
        unresolvable: [],
        errors: ['Foreign key error'],
      );

      expect(report.isClean, false);
    });
  });

  group('Priority ordering', () {
    test('pull apply priority map contains all expected entities', () {
      expect(
        CloudflareSyncPullService.pullApplyPriority,
        containsPair('devices', 1),
      );
      expect(
        CloudflareSyncPullService.pullApplyPriority,
        containsPair('bookings', 3),
      );
      expect(
        CloudflareSyncPullService.pullApplyPriority,
        containsPair('booking_nights', 4),
      );
    });

    test('parent entities have lower priority numbers than children', () {
      final priorities = CloudflareSyncPullService.pullApplyPriority;
      expect(
        priorities['rooms']! < priorities['bookings']!,
        true,
      );
      expect(
        priorities['bookings']! < priorities['booking_nights']!,
        true,
      );
    });
  });
}
