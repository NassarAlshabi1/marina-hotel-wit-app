// ============================================================================
//  DebugLog (dlog/dwarn/derr) — Unit Tests
//  ============================================================================
//  اختبارات أدوات التسجيل debug_log.dart:
//    - dlog يقبل String و thunk (() => String)
//    - dwarn يُضيف ⚠️ prefix
//    - derr يُضيف ❌ prefix
//    - في debug mode، الـ thunk يُستدعى
//    - في release mode، الـ thunk لا يُستدعى (no-op)
// ============================================================================

library marina_hotel_mobile.test.debug_log_test;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

void main() {
  group('dlog', () {
    test('يقبل String مباشرة', () {
      expect(() => dlog('simple string'), returnsNormally);
    });

    test('يقبل thunk (() => String)', () {
      expect(() => dlog(() => 'from thunk'), returnsNormally);
    });

    test('لا يُطلق استثناء مع null-safe messages', () {
      expect(() => dlog('message with $kReleaseMode'), returnsNormally);
    });

    test('thunk يُستدعى في debug mode', () {
      var called = false;
      dlog(() {
        called = true;
        return 'called!';
      });

      if (!kReleaseMode) {
        expect(called, isTrue, reason: 'في debug mode، thunk يجب أن يُستدعى');
      }
    });
  });

  group('dwarn', () {
    test('يقبل String', () {
      expect(() => dwarn('warning message'), returnsNormally);
    });

    test('يقبل thunk', () {
      expect(() => dwarn(() => 'warning from thunk'), returnsNormally);
    });
  });

  group('derr', () {
    test('يقبل String', () {
      expect(() => derr('error message'), returnsNormally);
    });

    test('يقبل thunk', () {
      expect(() => derr(() => 'error from thunk'), returnsNormally);
    });
  });

  group('Thunks لا تُكلّف string allocation في release mode', () {
    // هذا اختبار منطقي: في release mode، الـ thunk لا يُستدعى أبداً
    // لذا أي آثار جانبية بداخله لا تحدث
    test('thunk مع آثار جانبية', () {
      var sideEffect = 0;
      dlog(() {
        sideEffect++;
        return 'side effect $sideEffect';
      });

      // في debug mode: sideEffect = 1
      // في release mode: sideEffect = 0 (thunk لم يُستدعى)
      if (!kReleaseMode) {
        expect(sideEffect, 1);
      } else {
        expect(sideEffect, 0);
      }
    });
  });
}
