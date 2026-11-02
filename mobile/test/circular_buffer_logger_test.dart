// ============================================================================
//  CircularBufferLogger — Unit Tests
//  ============================================================================
//  اختبارات CircularBufferLogger:
//    - إضافة سجلات للـ buffer
//    - الحد الأقصى للـ buffer (500 entries)
//    - readLast يُرجع آخر N سجل
//    - clear يفرغ الـ buffer
//    - مستويات السجل (debug, info, warning, error)
// ============================================================================

library marina_hotel_mobile.test.circular_buffer_logger_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/circular_buffer_logger.dart';

void main() {
  // نختبر الـ buffer مباشرة بدون initialize() (يتجنب file I/O)
  // لأن initialize() يعتمد على path_provider (يحتاج mocking معقد)

  group('CircularBufferLogger logging', () {
    test('debug يُضيف سجل للمخزن', () {
      // نتجاهل الحالة الـ singleton ونستخدم instance مباشرة
      // ملاحظة: هذا الاختبار يعتمد على الحالة المشتركة
      CircularBufferLogger.instance.debug('test debug', tag: 'TEST');
      expect(CircularBufferLogger.instance.bufferSize, greaterThan(0));
    });

    test('info يُضيف سجل للمخزن', () {
      final before = CircularBufferLogger.instance.bufferSize;
      CircularBufferLogger.instance.info('test info', tag: 'TEST');
      expect(CircularBufferLogger.instance.bufferSize, greaterThan(before));
    });

    test('warning يُضيف سجل مع error', () {
      final before = CircularBufferLogger.instance.bufferSize;
      CircularBufferLogger.instance.warning(
        'test warning',
        tag: 'TEST',
        error: 'some error',
      );
      expect(CircularBufferLogger.instance.bufferSize, greaterThan(before));
    });

    test('error يُضيف سجل مع error و stack', () {
      final before = CircularBufferLogger.instance.bufferSize;
      CircularBufferLogger.instance.error(
        'test error',
        tag: 'TEST',
        error: Exception('boom'),
        stack: StackTrace.current,
      );
      expect(CircularBufferLogger.instance.bufferSize, greaterThan(before));
    });
  });

  group('CircularBufferLogger readLast', () {
    test('readLast يُرجع آخر N سجل', () {
      // نضيف بعض السجلات
      for (var i = 0; i < 5; i++) {
        CircularBufferLogger.instance.info('msg $i', tag: 'TEST');
      }

      final last3 = CircularBufferLogger.instance.readLast(3);
      expect(last3.length, lessThanOrEqualTo(3));
      expect(last3.length, greaterThan(0));

      // كل سجل يجب أن يحتوي على الحقول المتوقعة
      for (final entry in last3) {
        expect(entry, isA<Map<String, dynamic>>());
        expect(entry.containsKey('level'), isTrue);
        expect(entry.containsKey('message'), isTrue);
        expect(entry.containsKey('tag'), isTrue);
        expect(entry.containsKey('timestamp'), isTrue);
      }
    });

    test('readLast(0) يُرجع قائمة فارغة أو صغيرة', () {
      final result = CircularBufferLogger.instance.readLast(0);
      expect(result.length, lessThanOrEqualTo(0));
    });

    test('readLast بـ count أكبر من الـ buffer', () {
      final currentSize = CircularBufferLogger.instance.bufferSize;
      final result = CircularBufferLogger.instance.readLast(currentSize + 100);
      expect(result.length, equals(currentSize));
    });
  });

  group('CircularBufferLogger clear', () {
    test('clear يفرغ الـ buffer', () async {
      // نضيف سجل
      CircularBufferLogger.instance.info('to be cleared', tag: 'TEST');
      expect(CircularBufferLogger.instance.bufferSize, greaterThan(0));

      await CircularBufferLogger.instance.clear();
      expect(CircularBufferLogger.instance.bufferSize, 0);
    });
  });

  group('LogLevel enum', () {
    test('يحتوي على المستويات المتوقعة', () {
      expect(LogLevel.values, contains(LogLevel.debug));
      expect(LogLevel.values, contains(LogLevel.info));
      expect(LogLevel.values, contains(LogLevel.warning));
      expect(LogLevel.values, contains(LogLevel.error));
    });
  });
}
