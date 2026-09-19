import 'dart:async';
import 'dart:io' show HandshakeException, HttpException, SocketException;

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

    // ═══════════════════════════════════════════════════════════
    // ✅ (2026-09-19) بلاغ الإنتاج: SocketException (errno 103) إلى
    // Worker سُجّل Fatal Exception — المصنّف يخفض العابر الشبكي
    // إلى non-fatal في كل مسارات الالتقاط العامة.
    // ═══════════════════════════════════════════════════════════
    group('isTransientNetworkError', () {
      test('بلاغ الإنتاج الحرفي (errno 103) → عابر', () {
        const productionReport =
            'SocketException: Software caused '
            'connection abort (OS Error: Software caused connection abort, '
            'errno = 103), address = 104.21.41.137, port = 48010';
        expect(
          CrashlyticsService.isTransientNetworkError(productionReport),
          isTrue,
        );
      });

      test('الأنواع الأصلية من dart:io وdart:async → عابرة', () {
        expect(
          CrashlyticsService.isTransientNetworkError(
            SocketException('Software caused connection abort'),
          ),
          isTrue,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            const HandshakeException(),
          ),
          isTrue,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            HttpException('Connection closed', uri: Uri.parse('https://x')),
          ),
          isTrue,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            TimeoutException('Fast path timeout after 6s'),
          ),
          isTrue,
        );
      });

      test('أخطاء مكدس المزامنة المغلّفة نصاً → عابرة', () {
        // _pushBatch يغلّف: Exception('Push network error: $e')
        expect(
          CrashlyticsService.isTransientNetworkError(
            Exception(
              'Push network error: SocketException: Connection reset '
              'by peer',
            ),
          ),
          isTrue,
        );
        // رسائل الدخول القابلة للتنفيذ
        expect(
          CrashlyticsService.isTransientNetworkError(
            'Failed host lookup: marina-hotel-api.adenmarina2.workers.dev',
          ),
          isTrue,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            'No address associated with hostname',
          ),
          isTrue,
        );
        // إطار WebSocket (realtime) وpackage:http
        expect(
          CrashlyticsService.isTransientNetworkError(
            'WebSocketChannelException: SocketException: Connection '
            'aborted',
          ),
          isTrue,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            'ClientException: Connection closed while receiving data',
          ),
          isTrue,
        );
      });

      test('أخطاء منطقية/برمجية → ليست شبكية (تبقى fatal)', () {
        expect(
          CrashlyticsService.isTransientNetworkError(
            StateError('Not initialized'),
          ),
          isFalse,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            Exception('Null check operator used on null value'),
          ),
          isFalse,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            ArgumentError('invalid idempotency key'),
          ),
          isFalse,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(
            const FormatException('Unexpected end of DER at offset 0'),
          ),
          isFalse,
        );
        expect(
          CrashlyticsService.isTransientNetworkError(null),
          isFalse,
        );
      });
    });
  });
}
