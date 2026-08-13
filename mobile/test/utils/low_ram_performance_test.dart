import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/appwrite_cache_manager.dart';
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

  group('AppwriteCacheManager LRU', () {
    final cache = AppwriteCacheManager.instance;

    setUp(() {
      cache.clear();
      cache.setEnabled(true);
      cache.setMaxEntries(2);
      cache.setMaxSizeMB(1);
    });

    tearDown(() {
      cache.clear();
      cache.setMaxEntries(500);
      cache.setMaxSizeMB(20);
    });

    test('يُخلي أقل عنصر استخدامًا عند تجاوز حد الإدخالات', () {
      cache.set<String>('oldest', 'a');
      cache.set<String>('recent', 'b');
      expect(cache.get<String>('oldest'), 'a');

      cache.set<String>('newest', 'c');

      expect(cache.get<String>('oldest'), 'a');
      expect(cache.get<String>('recent'), isNull);
      expect(cache.get<String>('newest'), 'c');
      expect(cache.getStatistics().totalEntries, 2);
    });

    test('يمسح الذاكرة القابلة لإعادة التحميل عند ضغط الذاكرة', () {
      cache.set<String>('key', 'value');

      cache.handleMemoryPressure();

      expect(cache.getStatistics().totalEntries, 0);
    });
  });
}
