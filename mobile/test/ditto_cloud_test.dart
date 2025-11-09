import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/ditto_config.dart';
import 'package:marina_hotel_mobile/services/ditto_cloud_sync_service.dart';

void main() {
  group('Ditto Cloud Configuration Tests', () {
    
    test('Config should be properly configured with real values', () {
      // التحقق من أن الإعدادات محددة
      expect(DittoConfig.isConfigured, isTrue);
      
      // التحقق من App ID
      expect(DittoConfig.appId, equals('1507d904-d3ed-4ac3-824c-249c18170eee'));
      expect(DittoConfig.appId.isNotEmpty, isTrue);
      
      // التحقق من Playground Token
      expect(DittoConfig.playgroundToken, equals('dbae5191-2cb5-4fb5-8aca-9f9d85e0409a'));
      expect(DittoConfig.playgroundToken.isNotEmpty, isTrue);
      
      // التحقق من API Token
      expect(DittoConfig.apiToken, equals('Vc4wt9ruMMtlf9zS1wh8RSoqT8HN9aB8CYfeDY95KC4kKSEtkfmgHOupZBkO'));
      expect(DittoConfig.apiToken.isNotEmpty, isTrue);
      
      // التحقق من WebSocket URL
      expect(DittoConfig.webSocketUrl, equals('wss://i83inp.cloud.dittolive.app'));
      expect(DittoConfig.webSocketUrl.startsWith('wss://'), isTrue);
      
      // التحقق من Cloud Webhook
      expect(DittoConfig.cloudWebhookUrl, equals('i83inp.cloud.dittolive.app/1507d904-d3ed-4ac3-824c-249c18170eee'));
    });
    
    test('Cloud sync should be enabled and P2P disabled', () {
      expect(DittoConfig.enableCloudSync, isTrue);
      expect(DittoConfig.enableP2PSync, isFalse);
    });
    
    test('Debug info should mask sensitive data', () {
      final debugInfo = DittoConfig.debugInfo;
      
      // التحقق من أن البيانات الحساسة مخفية جزئياً
      expect(debugInfo['app_id'], contains('***'));
      expect(debugInfo['playground_token'], contains('***'));
      expect(debugInfo['api_token'], contains('***'));
      
      // التحقق من أن WebSocket URL غير مخفي
      expect(debugInfo['websocket_url'], equals(DittoConfig.webSocketUrl));
      
      // التحقق من الحالة
      expect(debugInfo['configured'], isTrue);
      expect(debugInfo['cloud_sync'], isTrue);
      expect(debugInfo['p2p_sync'], isFalse);
    });
    
    test('Performance settings should be reasonable', () {
      expect(DittoConfig.syncTimeoutSeconds, greaterThan(0));
      expect(DittoConfig.syncTimeoutSeconds, lessThan(120)); // لا يزيد عن دقيقتين
      
      expect(DittoConfig.maxRetryAttempts, greaterThan(0));
      expect(DittoConfig.maxRetryAttempts, lessThan(10)); // محاولات معقولة
      
      expect(DittoConfig.heartbeatIntervalSeconds, greaterThan(0));
      expect(DittoConfig.heartbeatIntervalSeconds, lessThan(300)); // لا يزيد عن 5 دقائق
    });
  });
  
  group('Ditto Service Integration Tests', () {
    late DittoCloudSyncService dittoService;
    
    setUp(() {
      dittoService = DittoCloudSyncService.instance;
    });
    
    test('Service should initialize without errors', () async {
      // هذا اختبار أساسي - قد يحتاج إعدادات إضافية للتشغيل الفعلي
      expect(dittoService, isNotNull);
      
      // التحقق من حالة المزامنة الأولية
      final status = await dittoService.getSyncStatus();
      expect(status, isA<Map<String, dynamic>>());
      expect(status.containsKey('initialized'), isTrue);
      expect(status.containsKey('device_id'), isTrue);
      expect(status.containsKey('cloud_sync_enabled'), isTrue);
      expect(status['p2p_enabled'], isFalse);
    });
    
    test('Device ID should be generated and persistent', () async {
      final status1 = await dittoService.getSyncStatus();
      final status2 = await dittoService.getSyncStatus();
      
      final deviceId1 = status1['device_id'];
      final deviceId2 = status2['device_id'];
      
      expect(deviceId1, isNotNull);
      expect(deviceId1, isNotEmpty);
      expect(deviceId1, equals(deviceId2)); // يجب أن يكون ثابتاً
      expect(deviceId1.toString().startsWith('marina_hotel_'), isTrue);
    });
  });
}