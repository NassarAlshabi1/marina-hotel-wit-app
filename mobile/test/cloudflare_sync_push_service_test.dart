import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;

import '../lib/services/cloudflare_sync_push_service.dart';
import '../lib/services/local_db.dart';
import '../lib/services/vector_clock_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockVectorClockService extends Mock implements VectorClockService {}

void main() {
  group('CloudflareSyncPushService', () {
    late CloudflareSyncPushService service;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;
    late MockVectorClockService mockVectorClockService;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();
      mockVectorClockService = MockVectorClockService();

      service = CloudflareSyncPushService(
        httpClient: mockHttpClient,
        database: mockDatabase,
        vectorClockService: mockVectorClockService,
      );
    });

    test('setCredentials stores token and deviceId', () {
      service.setCredentials('test-token', 'device-123');
      expect(service.token, 'test-token');
      expect(service.deviceId, 'device-123');
    });

    test('pushOutbox returns 0 when not initialized', () async {
      final result = await service.pushOutbox();
      expect(result, 0);
    });

    test('pushOutbox handles empty batch gracefully', () async {
      service.setCredentials('test-token', 'device-123');
      final result = await service.pushOutbox();
      expect(result, isA<int>());
    });

    test('_rowVectorClock returns valid JSON clock', () async {
      service.setCredentials('test-token', 'device-123');

      when(mockVectorClockService.getVectorClock(any, any))
          .thenAnswer((_) async => {'device-123': 1});

      final clock = await service._rowVectorClock('bookings', 'uuid-123');
      expect(clock, isNotEmpty);
      expect(clock.contains('device-123'), true);
    });

    test('_rowVectorClock returns minimal clock on error', () async {
      service.setCredentials('test-token', 'device-123');

      when(mockVectorClockService.getVectorClock(any, any))
          .thenThrow(Exception('Test error'));

      final clock = await service._rowVectorClock('bookings', 'uuid-123');
      expect(clock, isNotEmpty);
    });

    test('pushAllLocalData returns empty map when not initialized', () async {
      final result = await service.pushAllLocalData();
      expect(result, isEmpty);
    });
  });

  group('OutboxRecord', () {
    test('creates instance with all fields', () {
      final record = OutboxRecord(
        id: 1,
        entity: 'bookings',
        op: 'create',
        localUuid: 'uuid-123',
        payload: {'name': 'Test'},
        clientTs: 1000000,
        idempotencyKey: 'key-123',
      );

      expect(record.id, 1);
      expect(record.entity, 'bookings');
      expect(record.op, 'create');
      expect(record.localUuid, 'uuid-123');
      expect(record.payload, {'name': 'Test'});
      expect(record.clientTs, 1000000);
      expect(record.idempotencyKey, 'key-123');
    });

    test('payload can be null', () {
      final record = OutboxRecord(
        id: 1,
        entity: 'bookings',
        op: 'delete',
        localUuid: 'uuid-123',
        payload: null,
        clientTs: 1000000,
        idempotencyKey: 'key-123',
      );

      expect(record.payload, isNull);
    });
  });
}

// Extension to expose private methods for testing
extension TestHelper on CloudflareSyncPushService {
  Future<String> _rowVectorClock(String entity, String localUuid) =>
      super._rowVectorClock(entity, localUuid);
}
