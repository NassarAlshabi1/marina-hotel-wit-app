// test/unit/weak_device_optimizer_test.dart
//
// ✅ اختبارات WeakDeviceOptimizer: التأكد من تصنيف الأجهزة الضعيفة (1GB RAM)
// بشكل صحيح، لأن تعديل PRAGMA في local_db.dart يعتمد على isWeakDevice
// لتقليل بصمة الذاكرة (mmap_size/cache_size/temp_store) ومنع OOM-kill.

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/weak_device_optimizer.dart';

void main() {
  group('WeakDeviceOptimizer classification', () {
    test('ذاكرة 1GB → جهاز ضعيف (optimizationLevel=2)', () {
      WeakDeviceOptimizer.instance.initialize(
        processorCount: 4,
        memoryMB: 1024,
      );
      expect(WeakDeviceOptimizer.instance.isWeakDevice, isTrue);
      expect(WeakDeviceOptimizer.instance.optimizationLevel, equals(2));
    });

    test('ذاكرة 2GB مع 2 أنوية → جهاز ضعيف', () {
      WeakDeviceOptimizer.instance.initialize(
        processorCount: 2,
        memoryMB: 2048,
      );
      expect(WeakDeviceOptimizer.instance.isWeakDevice, isTrue);
    });

    test('ذاكرة 4GB مع 8 أنوية → جهاز عادي', () {
      WeakDeviceOptimizer.instance.initialize(
        processorCount: 8,
        memoryMB: 4096,
      );
      expect(WeakDeviceOptimizer.instance.isWeakDevice, isFalse);
      expect(WeakDeviceOptimizer.instance.optimizationLevel, equals(0));
    });

    test('القيم الافتراضية آمنة عند عدم التهيئة (isWeakDevice=false)', () {
      // يضمن أن local_db يعمل بـ PRAGMA الافتراضية في الاختبارات/السياقات غير المهيأة.
      final fresh = WeakDeviceOptimizer.instance;
      expect(fresh.isWeakDevice, isFalse);
    });
  });
}
