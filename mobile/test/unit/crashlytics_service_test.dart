import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/crashlytics_service.dart';

void main() {
  group('CrashlyticsService', () {
    test('should be a singleton', () {
      expect(CrashlyticsService.instance, same(CrashlyticsService.instance));
    });

    test('isInitialized should be a bool', () {
      expect(CrashlyticsService.instance.isInitialized, isA<bool>());
    });

    test('isFirebaseConnected should be a bool', () {
      expect(CrashlyticsService.instance.isFirebaseConnected, isA<bool>());
    });

    test('setRoomNumber should not throw', () async {
      await CrashlyticsService.instance.setRoomNumber('101');
      expect(true, isTrue);
    });

    test('setSyncStatus should not throw', () async {
      await CrashlyticsService.instance.setSyncStatus('pushing');
      expect(true, isTrue);
    });

    test('setUserRole should not throw', () async {
      await CrashlyticsService.instance.setUserRole('admin');
      expect(true, isTrue);
    });

    test('setHotelDayKey should not throw', () async {
      await CrashlyticsService.instance.setHotelDayKey('2026-07-27');
      expect(true, isTrue);
    });

    test('setSyncEngine should not throw', () async {
      await CrashlyticsService.instance.setSyncEngine('appwrite');
      expect(true, isTrue);
    });

    test('setNetworkType should not throw', () async {
      await CrashlyticsService.instance.setNetworkType('wifi');
      expect(true, isTrue);
    });

    test('setDeviceId should not throw', () async {
      await CrashlyticsService.instance.setDeviceId('device-123');
      expect(true, isTrue);
    });

    test('setContext should update all keys without throwing', () async {
      await CrashlyticsService.instance.setContext(
        roomNumber: '101',
        syncStatus: 'idle',
        userRole: 'admin',
        hotelDayKey: '2026-07-27',
        syncEngine: 'appwrite',
        networkType: 'wifi',
        deviceId: 'device-123',
      );
      expect(true, isTrue);
    });

    test('recordScreenError should not throw when not initialized', () async {
      await CrashlyticsService.instance.recordScreenError(
        screen: 'TestScreen',
        action: 'testAction',
        error: Exception('test'),
        stackTrace: StackTrace.current,
      );
      expect(true, isTrue);
    });

    test('recordSyncError should not throw when not initialized', () async {
      await CrashlyticsService.instance.recordSyncError(
        operation: 'push',
        error: 'test error',
        severity: CrashlyticsSeverity.error,
      );
      expect(true, isTrue);
    });

    test('CrashlyticsSeverity should have all expected values', () {
      expect(CrashlyticsSeverity.values.length, 4);
      expect(CrashlyticsSeverity.values, contains(CrashlyticsSeverity.fatal));
      expect(CrashlyticsSeverity.values, contains(CrashlyticsSeverity.error));
      expect(CrashlyticsSeverity.values, contains(CrashlyticsSeverity.warning));
      expect(CrashlyticsSeverity.values, contains(CrashlyticsSeverity.info));
    });
  });
}
