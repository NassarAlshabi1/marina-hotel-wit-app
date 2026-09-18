// ============================================================================
//  AppLogger — Unit Tests
//  ============================================================================
//  اختبارات AppLogger (نظام التسجيل الموحد):
//    - debug/info/warning/error تُسجل الرسائل بشكل صحيح
//    - LevelFilter يُصفّي المستويات حسب mode
//    - في release mode، debug و info لا تُطبع
// ============================================================================

library marina_hotel_mobile.test.app_logger_test;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

void main() {
  group('AppLogger.debug', () {
    test('لا يُطلق استثناء عند تسجيل رسالة debug', () {
      expect(
        () => AppLogger.debug('test debug message', tag: 'TEST'),
        returnsNormally,
      );
    });

    test('يدعم tag و error و stackTrace', () {
      expect(
        () => AppLogger.debug(
          'test with details',
          tag: 'TEST',
          error: Exception('test error'),
          stackTrace: StackTrace.current,
        ),
        returnsNormally,
      );
    });
  });

  group('AppLogger.info', () {
    test('لا يُطلق استثناء', () {
      expect(
        () => AppLogger.info('test info message', tag: 'TEST'),
        returnsNormally,
      );
    });
  });

  group('AppLogger.warning', () {
    test('لا يُطلق استثناء', () {
      expect(
        () => AppLogger.warning('test warning message', tag: 'TEST'),
        returnsNormally,
      );
    });

    test('يدعم error parameter', () {
      expect(
        () => AppLogger.warning(
          'test warning with error',
          tag: 'TEST',
          error: 'some error',
        ),
        returnsNormally,
      );
    });
  });

  group('AppLogger.error', () {
    test('لا يُطلق استثناء', () {
      expect(
        () => AppLogger.error('test error message', tag: 'TEST'),
        returnsNormally,
      );
    });

    test('يدعم error و stackTrace parameters', () {
      expect(
        () => AppLogger.error(
          'test error with details',
          tag: 'TEST',
          error: Exception('boom'),
          stackTrace: StackTrace.current,
        ),
        returnsNormally,
      );
    });
  });

  group('LevelFilter', () {
    test('debug filter يُفعّل كل المستويات', () {
      const filter = LevelFilter.debug;
      expect(filter.showDebug, isTrue);
      expect(filter.showInfo, isTrue);
      expect(filter.showWarning, isTrue);
      expect(filter.showError, isTrue);
    });

    test('production filter يُعطّل debug و info فقط', () {
      const filter = LevelFilter.production;
      expect(filter.showDebug, isFalse);
      expect(filter.showInfo, isFalse);
      expect(filter.showWarning, isTrue);
      expect(filter.showError, isTrue);
    });
  });

  group('AppLogger.filter', () {
    test('في debug mode، showDebug يجب أن يكون true', () {
      // هذه ستعتمد على kReleaseMode وقت التشغيل
      if (!kReleaseMode) {
        expect(AppLogger.filter.showDebug, isTrue);
      }
    });
  });
}
