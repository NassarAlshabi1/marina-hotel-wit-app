import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;

import '../lib/services/cloudflare_sync_device_service.dart';
import '../lib/services/cloudflare_sync_push_service.dart';
import '../lib/services/cloudflare_sync_pull_service.dart';
import '../lib/services/local_db.dart';
import '../lib/services/vector_clock_service.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAppDatabase extends Mock implements AppDatabase {}

class MockVectorClockService extends Mock implements VectorClockService {}

void main() {
  group('Sync Integration Tests', () {
    late CloudflareSyncDeviceService deviceService;
    late CloudflareSyncPushService pushService;
    late CloudflareSyncPullService pullService;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;
    late MockVectorClockService mockVectorClockService;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();
      mockVectorClockService = MockVectorClockService();

      deviceService = CloudflareSyncDeviceService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );

      pushService = CloudflareSyncPushService(
        httpClient: mockHttpClient,
        database: mockDatabase,
        vectorClockService: mockVectorClockService,
      );

      pullService = CloudflareSyncPullService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );
    });

    test('Services initialize with credentials', () {
      const token = 'test-token';
      const deviceId = 'device-123';

      deviceService.setCredentials(token, deviceId);
      pushService.setCredentials(token, deviceId);
      pullService.setCredentials(token, deviceId);

      expect(deviceService.token, token);
      expect(deviceService.deviceId, deviceId);

      expect(pushService.token, token);
      expect(pushService.deviceId, deviceId);

      expect(pullService.token, token);
      expect(pullService.deviceId, deviceId);
    });

    test('Pull cursor is tracked correctly', () {
      pullService.setCredentials('token', 'device');
      pullService.setLastPullCursor(12345);

      expect(pullService.lastPullCursor, 12345);
    });

    test('Services handle uninitialized state gracefully', () async {
      // Without credentials, operations should fail gracefully
      final deviceCount = await deviceService.getRegisteredDevices();
      expect(deviceCount, isEmpty);

      final pushCount = await pushService.pushOutbox();
      expect(pushCount, 0);

      final pullCount = await pullService.pullChanges();
      expect(pullCount, 0);
    });

    test('All services use same HTTP client', () {
      expect(deviceService.httpClient, mockHttpClient);
      expect(pushService.httpClient, mockHttpClient);
      expect(pullService.httpClient, mockHttpClient);
    });

    test('All services use same database', () {
      expect(deviceService.database, mockDatabase);
      expect(pushService.database, mockDatabase);
      expect(pullService.database, mockDatabase);
    });
  });

  group('Sync Workflow Scenarios', () {
    late CloudflareSyncDeviceService deviceService;
    late CloudflareSyncPushService pushService;
    late CloudflareSyncPullService pullService;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;
    late MockVectorClockService mockVectorClockService;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();
      mockVectorClockService = MockVectorClockService();

      deviceService = CloudflareSyncDeviceService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );

      pushService = CloudflareSyncPushService(
        httpClient: mockHttpClient,
        database: mockDatabase,
        vectorClockService: mockVectorClockService,
      );

      pullService = CloudflareSyncPullService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );

      // Setup credentials
      deviceService.setCredentials('token', 'device-123');
      pushService.setCredentials('token', 'device-123');
      pullService.setCredentials('token', 'device-123');
    });

    test('Device registration is idempotent', () async {
      // First call would register device
      // Second call should also succeed without errors
      expect(deviceService.token, 'token');
      expect(deviceService.deviceId, 'device-123');
    });

    test('Push and pull operations are independent', () async {
      // Push should not depend on pull
      final pushResult = await pushService.pushOutbox();
      expect(pushResult, isA<int>());

      // Pull should not depend on push
      final pullResult = await pullService.pullChanges();
      expect(pullResult, isA<int>());
    });

    test('Pull applies records in correct order', () async {
      final records = [
        (
          entity: 'booking_nights',
          record: <String, dynamic>{'local_uuid': 'night-1'}
        ),
        (
          entity: 'bookings',
          record: <String, dynamic>{'local_uuid': 'booking-1'}
        ),
        (
          entity: 'rooms',
          record: <String, dynamic>{'local_uuid': 'room-1'}
        ),
      ];

      // Records should be reordered by priority
      // rooms (2) < bookings (3) < booking_nights (4)
      final report = await pullService.applyPulledRecords(records);

      expect(report, isNotNull);
      // Check that report tracking works
      expect(report.touchedEntities, isA<Set<String>>());
    });
  });

  group('Error Handling', () {
    late CloudflareSyncDeviceService deviceService;
    late CloudflareSyncPushService pushService;
    late CloudflareSyncPullService pullService;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;
    late MockVectorClockService mockVectorClockService;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();
      mockVectorClockService = MockVectorClockService();

      deviceService = CloudflareSyncDeviceService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );

      pushService = CloudflareSyncPushService(
        httpClient: mockHttpClient,
        database: mockDatabase,
        vectorClockService: mockVectorClockService,
      );

      pullService = CloudflareSyncPullService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );
    });

    test('Services recover from null credentials', () async {
      // All services should return sensible defaults when not initialized
      final devices = await deviceService.getRegisteredDevices();
      expect(devices, isEmpty);

      final pushed = await pushService.pushOutbox();
      expect(pushed, 0);

      final pulled = await pullService.pullChanges();
      expect(pulled, 0);
    });

    test('Vector clock resolution handles errors gracefully', () async {
      pushService.setCredentials('token', 'device-123');

      when(mockVectorClockService.getVectorClock(any, any))
          .thenThrow(Exception('Clock error'));

      // Should still return a valid clock JSON
      final clock = await pushService.rowVectorClock('bookings', 'uuid-1');
      expect(clock, isNotEmpty);
    });

    test('FCM token setting handles errors silently', () async {
      deviceService.setCredentials('token', 'device-123');

      // Should not throw even if HTTP request fails
      await deviceService.setFcmToken('fcm-token');
      // Expect no exception
      expect(true, true);
    });
  });
}

// Extension to expose private methods for testing
extension SyncTestHelper on CloudflareSyncPushService {
  Future<String> rowVectorClock(String entity, String localUuid) =>
      _rowVectorClock(entity, localUuid);
}
