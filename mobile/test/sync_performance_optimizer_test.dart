import 'package:flutter_test/flutter_test.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:marina_hotel_mobile/services/sync_performance_optimizer.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SyncPerformanceOptimizer Tests', () {
    late SyncPerformanceOptimizer optimizer;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      optimizer = SyncPerformanceOptimizer();
    });

    tearDown(() {
      optimizer.dispose();
    });

    test('should be singleton', () {
      final optimizer1 = SyncPerformanceOptimizer();
      final optimizer2 = SyncPerformanceOptimizer();
      expect(optimizer1, equals(optimizer2));
    });

    test('shouldSkipSync should return Future<bool>', () async {
      // اختبار أن الدالة أصبحت async وترجع Future<bool>
      final result = optimizer.shouldSkipSync();
      expect(result, isA<Future<bool>>());

      final actualResult = await result;
      expect(actualResult, isA<bool>());
    });

    test('should handle empty connectivity results', () {
      // اختبار معالجة قائمة فارغة من نتائج الاتصال
      const List<ConnectivityResult> emptyResults = [];

      // يجب ألا ترمي خطأ عند تمرير قائمة فارغة
      expect(() => optimizer.updateConnectivityStatusForTest(emptyResults),
          returnsNormally);

      // بعد معالجة قائمة فارغة، يجب أن يكون isOnWiFi = false
      expect(optimizer.isOnWiFi, false);
    });

    test('should prioritize WiFi over mobile connection', () {
      // اختبار ترتيب الأولوية: WiFi أولاً ثم Mobile
      const List<ConnectivityResult> mixedResults = [
        ConnectivityResult.mobile,
        ConnectivityResult.wifi,
        ConnectivityResult.bluetooth,
      ];

      optimizer.updateConnectivityStatusForTest(mixedResults);

      // يجب أن يفضل WiFi على Mobile
      expect(optimizer.isOnWiFi, true);
    });

    test('should handle single mobile connection', () {
      const List<ConnectivityResult> mobileResults = [
        ConnectivityResult.mobile
      ];

      optimizer.updateConnectivityStatusForTest(mobileResults);

      expect(optimizer.isOnWiFi, false);
    });

    test('should handle multiple connection types', () {
      // اختبار التعامل مع أنواع اتصال متعددة
      const testCases = [
        // WiFi موجود - يجب أن يكون true
        ([ConnectivityResult.wifi], true),
        ([ConnectivityResult.wifi, ConnectivityResult.mobile], true),

        // Ethernet موجود (نعامله مثل WiFi) - يجب أن يكون true
        ([ConnectivityResult.ethernet], true),
        ([ConnectivityResult.ethernet, ConnectivityResult.mobile], true),

        // Mobile فقط - يجب أن يكون false
        ([ConnectivityResult.mobile], false),

        // VPN فقط - يجب أن يكون false (قد يكون بطيء)
        ([ConnectivityResult.vpn], false),

        // Bluetooth فقط - يجب أن يكون false (بطيء)
        ([ConnectivityResult.bluetooth], false),

        // Other فقط - يجب أن يكون false (غير محدد)
        ([ConnectivityResult.other], false),

        // None - يجب أن يكون false (لا يوجد اتصال)
        ([ConnectivityResult.none], false),
      ];

      for (final testCase in testCases) {
        final results = testCase.$1;
        final expectedIsOnWiFi = testCase.$2;

        optimizer.updateConnectivityStatusForTest(results);
        expect(
          optimizer.isOnWiFi,
          expectedIsOnWiFi,
          reason: 'Failed for connectivity results: $results',
        );
      }
    });

    test('should get correct performance settings based on connection', () {
      // اختبار إعدادات الأداء لـ WiFi
      const List<ConnectivityResult> wifiResults = [ConnectivityResult.wifi];
      optimizer.updateConnectivityStatusForTest(wifiResults);

      final wifiSettings = optimizer.getCurrentPerformanceSettings();
      expect(wifiSettings['batchSize'], 100);
      expect(wifiSettings['timeout'], 30);
      expect(wifiSettings['retryAttempts'], 3);
      expect(wifiSettings['syncInterval'], 60);

      // اختبار إعدادات الأداء للـ Mobile Data
      const List<ConnectivityResult> mobileResults = [
        ConnectivityResult.mobile
      ];
      optimizer.updateConnectivityStatusForTest(mobileResults);

      final mobileSettings = optimizer.getCurrentPerformanceSettings();
      expect(mobileSettings['batchSize'], 50);
      expect(mobileSettings['timeout'], 15);
      expect(mobileSettings['retryAttempts'], 2);
      expect(mobileSettings['syncInterval'], 120);
    });

    test('should record sync attempts correctly', () {
      // اختبار تسجيل المحاولات الناجحة
      optimizer.recordSyncAttempt(success: true);
      expect(optimizer.syncAttempts, 0); // يجب إعادة تعيين العداد
      expect(optimizer.lastSyncTime, isNotNull);

      // اختبار تسجيل المحاولات الفاشلة
      optimizer.recordSyncAttempt(success: false);
      expect(optimizer.syncAttempts, 1);

      optimizer.recordSyncAttempt(success: false);
      expect(optimizer.syncAttempts, 2);

      // اختبار إعادة تعيين العداد بعد نجاح
      optimizer.recordSyncAttempt(success: true);
      expect(optimizer.syncAttempts, 0);
    });

    test('should reset sync attempts', () {
      // زيادة عداد المحاولات
      optimizer.recordSyncAttempt(success: false);
      optimizer.recordSyncAttempt(success: false);
      expect(optimizer.syncAttempts, 2);

      // إعادة تعيين العداد
      optimizer.resetSyncAttempts();
      expect(optimizer.syncAttempts, 0);
    });

    test('should provide performance stats', () {
      const List<ConnectivityResult> wifiResults = [ConnectivityResult.wifi];
      optimizer.updateConnectivityStatusForTest(wifiResults);
      optimizer.recordSyncAttempt(success: false);

      final stats = optimizer.getPerformanceStats();

      expect(stats, isA<Map<String, dynamic>>());
      expect(stats['isOnWiFi'], true);
      expect(stats['syncAttempts'], 1);
      expect(stats['currentSettings'], isA<Map<String, dynamic>>());
      expect(stats.containsKey('lastSyncTime'), true);
    });
  });
}
