import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/weak_device_optimizer.dart';

void main() {
  group('WeakDeviceOptimizer low-RAM profile', () {
    test('يصنّف جهاز 1GB رباعي النوى ضمن المستوى الحرج', () async {
      final optimizer = WeakDeviceOptimizer.instance;

      await optimizer.initialize(processorCount: 4, memoryMB: 1024);

      expect(optimizer.isWeakDevice, isTrue);
      expect(optimizer.isCriticalLowMemoryDevice, isTrue);
      expect(optimizer.optimizationLevel, 3);
      expect(optimizer.maxListItemsBeforePagination, 15);
      expect(optimizer.syncBatchSize, 10);
      expect(optimizer.syncConcurrency, 1);
      expect(optimizer.maxDataCacheSizeMB, 2);
    });

    test('يصنّف جهاز 4GB سداسي النوى ضمن المستوى المتوسط', () async {
      final optimizer = WeakDeviceOptimizer.instance;

      await optimizer.initialize(processorCount: 6, memoryMB: 4096);

      expect(optimizer.isWeakDevice, isFalse);
      expect(optimizer.optimizationLevel, 0);
      expect(optimizer.maxListItemsBeforePagination, 100);
    });
  });
}
