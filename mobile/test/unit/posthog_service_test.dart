import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/posthog_service.dart';

void main() {
  group('PostHogService', () {
    test('should be a singleton', () {
      expect(PostHogService.instance, same(PostHogService.instance));
    });

    test('isInitialized should be false before initialize', () {
      // PostHogService is a fresh instance in tests
      expect(PostHogService.instance.isInitialized, isFalse);
    });

    test('isEnabled should be false before initialization', () {
      expect(PostHogService.instance.isEnabled, isFalse);
    });

    test('track should not throw when not initialized', () async {
      // Should silently skip when not initialized
      await PostHogService.instance.track('test_event');
      expect(true, isTrue); // No exception thrown
    });

    test('screen should not throw when not initialized', () async {
      await PostHogService.instance.screen('test_screen');
      expect(true, isTrue);
    });

    test('identify should not throw when not initialized', () async {
      await PostHogService.instance.identify('user-123');
      expect(true, isTrue);
    });

    test('isFeatureEnabled should return false when not initialized', () async {
      final result = await PostHogService.instance.isFeatureEnabled('test_flag');
      expect(result, isFalse);
    });

    test('getFeatureFlag should return null when not initialized', () async {
      final result = await PostHogService.instance.getFeatureFlag('test_flag');
      expect(result, isNull);
    });

    test('captureError should not throw when not initialized', () async {
      await PostHogService.instance.captureError(
        Exception('test error'),
        StackTrace.current,
      );
      expect(true, isTrue);
    });

    test('trackBookingCreated should not throw', () async {
      await PostHogService.instance.trackBookingCreated(
        roomNumber: '101',
        guestName: 'Test Guest',
        amount: 15000,
        nights: 3,
      );
      expect(true, isTrue);
    });

    test('trackPaymentProcessed should not throw', () async {
      await PostHogService.instance.trackPaymentProcessed(
        method: 'cash',
        amount: 50000,
      );
      expect(true, isTrue);
    });

    test('trackSyncCompleted should not throw', () async {
      await PostHogService.instance.trackSyncCompleted(
        itemsPushed: 10,
        itemsPulled: 5,
        duration: const Duration(seconds: 30),
      );
      expect(true, isTrue);
    });

    test('trackSyncFailed should not throw', () async {
      await PostHogService.instance.trackSyncFailed(
        error: 'Network error',
        operation: 'push',
      );
      expect(true, isTrue);
    });

    test('trackLogin should not throw', () async {
      await PostHogService.instance.trackLogin(
        userId: 'user-123',
        role: 'admin',
      );
      expect(true, isTrue);
    });

    test('trackLogout should not throw', () async {
      await PostHogService.instance.trackLogout();
      expect(true, isTrue);
    });

    test('setEnabled should not throw', () async {
      await PostHogService.instance.setEnabled(false);
      expect(true, isTrue);
    });
  });
}
