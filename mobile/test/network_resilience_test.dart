import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../lib/services/endpoint_manager.dart';
import '../lib/services/offline_cache.dart';

void main() {
  group('EndpointManager', () {
    setUp(() {
      EndpointManager.reset();
    });

    test('initial endpoint is primary', () {
      expect(
        EndpointManager.current,
        'https://marina-hotel-api.adenmarina2.workers.dev',
      );
    });

    test('recordSuccess sticks endpoint', () {
      const fallback = 'https://api.adenmarina.com';
      EndpointManager.recordSuccess(fallback);
      expect(EndpointManager.current, fallback);
    });

    test('recordFailure moves to next endpoint', () {
      const primary = 'https://marina-hotel-api.adenmarina2.workers.dev';
      const fallback = 'https://api.adenmarina.com';

      EndpointManager.recordFailure(primary);
      expect(EndpointManager.current, fallback);
    });

    test('candidates list includes working endpoints first', () {
      const primary = 'https://marina-hotel-api.adenmarina2.workers.dev';
      const fallback = 'https://api.adenmarina.com';

      EndpointManager.recordFailure(primary);
      EndpointManager.recordSuccess(fallback);

      final candidates = EndpointManager.candidates;
      expect(candidates[0], fallback); // Sticky comes first
      expect(candidates.contains(primary), true);
    });

    test('all endpoints rotate correctly', () {
      const primary = 'https://marina-hotel-api.adenmarina2.workers.dev';
      const fallback1 = 'https://api.adenmarina.com';
      const fallback2 = 'https://104.16.132.229';

      // Primary fails
      EndpointManager.recordFailure(primary);
      expect(EndpointManager.current, fallback1);

      // Fallback1 fails
      EndpointManager.recordFailure(fallback1);
      expect(EndpointManager.current, fallback2);
    });
  });

  group('OfflineCache', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
    });

    setUp(() async {
      await OfflineCache.clear();
    });

    tearDown(() async {
      await OfflineCache.clear();
    });

    test('save and retrieve data', () async {
      const key = 'test_data';
      final data = {'id': 1, 'name': 'Test'};

      await OfflineCache.save(key: key, data: data);
      final cached = await OfflineCache.get(key: key);

      expect(cached, isNotNull);
      expect(cached, data);
    });

    test('get returns null for missing key', () async {
      const key = 'missing';

      final cached = await OfflineCache.get(key: key);
      expect(cached, isNull);
    });

    test('delete removes cache entry', () async {
      const key = 'test_delete';
      final data = {'id': 1};

      await OfflineCache.save(key: key, data: data);
      var cached = await OfflineCache.get(key: key);
      expect(cached, isNotNull);

      await OfflineCache.delete(key);
      cached = await OfflineCache.get(key: key);
      expect(cached, isNull);
    });

    test('clear removes all cache entries', () async {
      const key1 = 'test1';
      const key2 = 'test2';

      await OfflineCache.save(key: key1, data: {'id': 1});
      await OfflineCache.save(key: key2, data: {'id': 2});

      var cached1 = await OfflineCache.get(key: key1);
      var cached2 = await OfflineCache.get(key: key2);
      expect(cached1, isNotNull);
      expect(cached2, isNotNull);

      await OfflineCache.clear();

      cached1 = await OfflineCache.get(key: key1);
      cached2 = await OfflineCache.get(key: key2);
      expect(cached1, isNull);
      expect(cached2, isNull);
    });
  });

  group('Network Resilience Integration', () {
    setUpAll(() {
      SharedPreferences.setMockInitialValues({});
    });

    setUp(() async {
      EndpointManager.reset();
      await OfflineCache.clear();
    });

    test('endpoint failure triggers fallback', () {
      const primary = 'https://marina-hotel-api.adenmarina2.workers.dev';
      const fallback = 'https://api.adenmarina.com';

      EndpointManager.recordFailure(primary);

      final candidates = EndpointManager.candidates;
      expect(candidates[0], fallback);
    });

    test('offline cache bridges network gaps', () async {
      const key = 'users_list';
      final userData = [
        {'id': 1, 'name': 'User 1'},
        {'id': 2, 'name': 'User 2'},
      ];

      // First successful fetch
      await OfflineCache.save(key: key, data: userData);
      var cached = await OfflineCache.get(key: key);
      expect(cached, userData);

      // Network fails, but user still sees data
      final staleData = await OfflineCache.get(key: key);
      expect(staleData, userData);
    });

    test('combined strategy: endpoint rotation + cache', () async {
      const key = 'critical_data';
      final data = {'status': 'critical'};

      // 1. Save to cache
      await OfflineCache.save(key: key, data: data);

      // 2. Endpoint fails
      const primary = 'https://marina-hotel-api.adenmarina2.workers.dev';
      EndpointManager.recordFailure(primary);

      // 3. Verify fallback is used
      final fallback = EndpointManager.current;
      expect(fallback, isNot(primary));

      // 4. Verify cache is still available
      final cached = await OfflineCache.get(key: key);
      expect(cached, data);
    });
  });
}
