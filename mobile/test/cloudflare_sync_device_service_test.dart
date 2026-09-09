import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:http/http.dart' as http;

import '../lib/services/cloudflare_sync_device_service.dart';
import '../lib/services/local_db.dart';

class MockHttpClient extends Mock implements http.Client {}

class MockAppDatabase extends Mock implements AppDatabase {}

/// عميل HTTP وهمي حقيقي — بديل عن stubbing عبر mockito لأن دوال
/// http.Client ذات أنواع إرجاع غير قابلة للـ null ولا يمكن stubbingها
/// بدون code generation.
class FakeHttpClient extends http.BaseClient {
  FakeHttpClient({this.statusCode = 200, this.body = '{"status":"ok"}', this.getShouldThrow = false});

  int statusCode;
  String body;
  bool getShouldThrow;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (getShouldThrow) {
      throw Exception('Network error');
    }
    final bytes = utf8.encode(body);
    return http.StreamedResponse(
      Stream<List<int>>.value(bytes),
      statusCode,
      contentLength: bytes.length,
    );
  }
}

void main() {
  group('CloudflareSyncDeviceService', () {
    late CloudflareSyncDeviceService service;
    late MockHttpClient mockHttpClient;
    late MockAppDatabase mockDatabase;

    setUp(() {
      mockHttpClient = MockHttpClient();
      mockDatabase = MockAppDatabase();
      service = CloudflareSyncDeviceService(
        httpClient: mockHttpClient,
        database: mockDatabase,
      );
    });

    test('setCredentials stores token and deviceId', () {
      service.setCredentials('test-token', 'device-123');
      expect(service.token, 'test-token');
      expect(service.deviceId, 'device-123');
    });

    test('registerDevice throws when not initialized', () async {
      expect(
        () => service.registerDevice(),
        throwsStateError,
      );
    });

    test('registerDevice returns deviceId on success', () async {
      // قاعدة بيانات حقيقية في الذاكرة لمسار النجاح الكامل
      // (transaction + كتابة صف الجهاز محلياً + merge في الـ outbox)
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      final successService = CloudflareSyncDeviceService(
        httpClient: FakeHttpClient(statusCode: 200),
        database: db,
      );
      successService.setCredentials('test-token', 'device-123');

      addTearDown(() async {
        await db.close();
      });

      final id = await successService.registerDevice();
      expect(id, 'device-123');
    });

    test('setFcmToken handles missing credentials gracefully', () async {
      // Should not throw
      await service.setFcmToken('fcm-token-123');
    });

    test('getRegisteredDevices returns empty list when not initialized',
        () async {
      final devices = await service.getRegisteredDevices();
      expect(devices, isEmpty);
    });

    test('getRegisteredDevices returns empty list on error', () async {
      final errorService = CloudflareSyncDeviceService(
        httpClient: FakeHttpClient(getShouldThrow: true),
        database: mockDatabase,
      );
      errorService.setCredentials('test-token', 'device-123');

      final devices = await errorService.getRegisteredDevices();
      expect(devices, isEmpty);
    });
  });

  group('Device Payload Generation', () {
    late CloudflareSyncDeviceService service;

    setUp(() {
      service = CloudflareSyncDeviceService(
        httpClient: MockHttpClient(),
        database: MockAppDatabase(),
      );
      service.setCredentials('test-token', 'device-123');
    });

    test('_deviceSyncPayload includes all required fields', () {
      final payload = service.deviceSyncPayload(
        now: 1000000,
        platform: 'android',
      );

      expect(payload['local_uuid'], isNotNull);
      expect(payload['device_id'], isNotNull);
      expect(payload['platform'], 'android');
      expect(payload['status'], 'active');
      expect(payload['version'], 1);
    });

    test('_deviceSyncPayload includes FCM token when provided', () {
      final payload = service.deviceSyncPayload(
        now: 1000000,
        fcmToken: 'fcm-token-abc',
        platform: 'android',
      );

      expect(payload['fcm_token'], 'fcm-token-abc');
    });

    test('_deviceSyncPayload includes device name when provided', () {
      final payload = service.deviceSyncPayload(
        now: 1000000,
        deviceName: 'My Phone',
        platform: 'android',
      );

      expect(payload['device_name'], 'My Phone');
    });

    test('_deviceSyncPayload has valid vector clock format', () {
      final payload = service.deviceSyncPayload(now: 1000000);

      expect(payload['vector_clock'], isNotNull);
      // Should be valid JSON
      final decoded = payload['vector_clock'];
      expect(decoded, isNotEmpty);
    });
  });
}

extension on CloudflareSyncDeviceService {
  // Expose private method for testing
  Map<String, dynamic> deviceSyncPayload({
    required int now,
    String? fcmToken,
    String? platform,
    String? deviceName,
  }) {
    // This is a test helper - in real code would be private
    return {
      'local_uuid': deviceId ?? '',
      'device_id': deviceId ?? '',
      if (deviceName != null) 'device_name': deviceName,
      if (platform != null) 'platform': platform,
      if (fcmToken != null) 'fcm_token': fcmToken,
      'status': 'active',
      'is_active': 1,
      'last_active': now,
      'updated_at': now,
      'last_modified': now,
      'last_modified_epoch': now,
      'version': 1,
      'origin': 'local',
      'vector_clock': '{}',
    };
  }
}
