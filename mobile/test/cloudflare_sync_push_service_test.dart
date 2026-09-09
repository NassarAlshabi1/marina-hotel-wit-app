import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;

import '../lib/services/cloudflare_sync_push_service.dart';
import '../lib/services/local_db.dart';
import '../lib/services/vector_clock_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAppDatabase extends Mock implements AppDatabase {}

/// Fake يدوي بدلاً من mockito Mock — لأن getVectorClock يعيد نوعاً
/// غير قابل للـ null ولا يمكن stubbingه عبر when() بدون code generation.
class FakeVectorClockService implements VectorClockService {
  FakeVectorClockService({this.clock, this.shouldThrow = false});

  Map<String, dynamic>? clock;
  bool shouldThrow;

  @override
  Future<Map<String, dynamic>> getVectorClock(
    String entity,
    String localUuid,
  ) async {
    if (shouldThrow) throw Exception('Test error');
    return clock ?? <String, dynamic>{};
  }
}

void main() {
  group('CloudflareSyncPushService', () {
    late CloudflareSyncPushService service;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;
    late FakeVectorClockService fakeVectorClockService;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();
      fakeVectorClockService = FakeVectorClockService();

      service = CloudflareSyncPushService(
        httpClient: mockHttpClient,
        database: mockDatabase,
        vectorClockService: fakeVectorClockService,
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

    test('rowVectorClock returns valid JSON clock', () async {
      service.setCredentials('test-token', 'device-123');
      fakeVectorClockService.clock = {'device-123': 1};

      final clock = await service.rowVectorClock('bookings', 'uuid-123');
      expect(clock, isNotEmpty);
      expect(clock.contains('device-123'), true);
    });

    test('rowVectorClock returns minimal clock on error', () async {
      service.setCredentials('test-token', 'device-123');
      fakeVectorClockService.shouldThrow = true;

      final clock = await service.rowVectorClock('bookings', 'uuid-123');
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
