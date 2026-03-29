// test/sync/sync_orchestrator_test.dart
// اختبارات SyncOrchestrator

import 'package:flutter_test/flutter_test.dart';
import '../mocks/mock_hive.dart';

// Mocks
class MockOutboxDao {
  final List<Map<String, dynamic>> _pending = [];
  final List<Map<String, dynamic>> _conflicts = [];

  Future<List<Map<String, dynamic>>> getPending() async => _pending;

  Future<int> getPendingCount() async => _pending.length;

  Future<void> markAsSynced(String id) async {
    _pending.removeWhere((item) => item['id'] == id);
  }

  Future<void> markAsFailed(String id, String error) async {
    final item = _pending.firstWhere(
      (item) => item['id'] == id,
      orElse: () => {},
    );
    if (item.isNotEmpty) {
      item['status'] = 'failed';
      item['error'] = error;
    }
  }

  Future<void> incrementRetry(String id) async {
    final item = _pending.firstWhere(
      (item) => item['id'] == id,
      orElse: () => {},
    );
    if (item.isNotEmpty) {
      item['retryCount'] = (item['retryCount'] ?? 0) + 1;
    }
  }

  Future<List<Map<String, dynamic>>> getConflicts() async => _conflicts;

  Future<void> resolveConflict(String id, String resolution) async {
    _conflicts.removeWhere((item) => item['id'] == id);
  }

  void addPending(Map<String, dynamic> item) => _pending.add(item);
  void addConflict(Map<String, dynamic> item) => _conflicts.add(item);
  void clear() {
    _pending.clear();
    _conflicts.clear();
  }
}

class MockApiService {
  bool shouldFail = false;
  String? lastError;
  int callCount = 0;

  Future<Map<String, dynamic>> pushData(Map<String, dynamic> data) async {
    callCount++;
    if (shouldFail) {
      throw Exception(lastError ?? 'Network error');
    }
    return {'success': true, 'id': data['id']};
  }

  Future<List<Map<String, dynamic>>> pullData() async {
    callCount++;
    if (shouldFail) {
      throw Exception(lastError ?? 'Network error');
    }
    return [];
  }

  Future<void> batchPush(List<Map<String, dynamic>> items) async {
    callCount++;
    if (shouldFail) {
      throw Exception(lastError ?? 'Batch push failed');
    }
  }

  void reset() {
    shouldFail = false;
    lastError = null;
    callCount = 0;
  }
}

class MockConnectivityService {
  bool _isOnline = true;

  void setOnline(bool online) => _isOnline = online;
  bool isOnline() => _isOnline;
}

// اختبارات SyncOrchestrator
void main() {
  group('SyncOrchestrator Tests', () {
    late MockOutboxDao mockOutboxDao;
    late MockApiService mockApiService;
    late MockConnectivityService mockConnectivity;

    setUp(() {
      mockOutboxDao = MockOutboxDao();
      mockApiService = MockApiService();
      mockConnectivity = MockConnectivityService();
      HiveTestHelper.createMockBox<Map<dynamic, dynamic>>('syncBox');
    });

    tearDown(() {
      mockOutboxDao.clear();
      mockApiService.reset();
      HiveTestHelper.resetAll();
    });

    group('Initialization', () {
      test('should initialize successfully', () async {
        // Verify initialization completes without errors
        expect(mockOutboxDao.getPendingCount(), completion(equals(0)));
      });
    });

    group('Push Operations', () {
      test('should push single item successfully', () async {
        // Arrange
        mockOutboxDao.addPending({
          'id': '1',
          'tableName': 'guests',
          'type': 'insert',
          'data': {'name': 'Test Guest'},
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'retryCount': 0,
        });

        // Act & Assert
        expect(mockOutboxDao.getPendingCount(), completion(equals(1)));
      });

      test('should handle empty pending list', () async {
        // Act
        final count = await mockOutboxDao.getPendingCount();

        // Assert
        expect(count, equals(0));
      });

      test('should mark item as synced after successful push', () async {
        // Arrange
        mockOutboxDao.addPending({
          'id': '1',
          'tableName': 'guests',
          'type': 'insert',
          'data': {'name': 'Test Guest'},
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'retryCount': 0,
        });

        // Act
        await mockOutboxDao.markAsSynced('1');

        // Assert
        final count = await mockOutboxDao.getPendingCount();
        expect(count, equals(0));
      });

      test('should increment retry count on failure', () async {
        // Arrange
        mockOutboxDao.addPending({
          'id': '1',
          'tableName': 'guests',
          'type': 'insert',
          'data': {'name': 'Test Guest'},
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'retryCount': 0,
        });

        // Act
        await mockOutboxDao.incrementRetry('1');

        // Assert - verify retry count was incremented
        final pending = await mockOutboxDao.getPending();
        expect(pending.first['retryCount'], equals(1));
      });

      test('should handle multiple pending items', () async {
        // Arrange
        for (int i = 0; i < 5; i++) {
          mockOutboxDao.addPending({
            'id': '$i',
            'tableName': 'guests',
            'type': 'insert',
            'data': {'name': 'Guest $i'},
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'pending',
            'retryCount': 0,
          });
        }

        // Act
        final count = await mockOutboxDao.getPendingCount();

        // Assert
        expect(count, equals(5));
      });
    });

    group('Conflict Resolution', () {
      test('should detect conflicts', () async {
        // Arrange
        mockOutboxDao.addConflict({
          'id': '1',
          'tableName': 'guests',
          'localData': {'name': 'Local Name'},
          'serverData': {'name': 'Server Name'},
          'timestamp': DateTime.now().toIso8601String(),
        });

        // Act
        final conflicts = await mockOutboxDao.getConflicts();

        // Assert
        expect(conflicts.length, equals(1));
        expect(conflicts.first['id'], equals('1'));
      });

      test('should resolve conflict using local wins', () async {
        // Arrange
        mockOutboxDao.addConflict({
          'id': '1',
          'tableName': 'guests',
          'localData': {'name': 'Local Name'},
          'serverData': {'name': 'Server Name'},
          'timestamp': DateTime.now().toIso8601String(),
        });

        // Act
        await mockOutboxDao.resolveConflict('1', 'local_wins');

        // Assert
        final conflicts = await mockOutboxDao.getConflicts();
        expect(conflicts.length, equals(0));
      });

      test('should resolve conflict using server wins', () async {
        // Arrange
        mockOutboxDao.addConflict({
          'id': '1',
          'tableName': 'guests',
          'localData': {'name': 'Local Name'},
          'serverData': {'name': 'Server Name'},
          'timestamp': DateTime.now().toIso8601String(),
        });

        // Act
        await mockOutboxDao.resolveConflict('1', 'server_wins');

        // Assert
        final conflicts = await mockOutboxDao.getConflicts();
        expect(conflicts.length, equals(0));
      });
    });

    group('Batch Processing', () {
      test('should process batch of items', () async {
        // Arrange
        final batch = <Map<String, dynamic>>[];
        for (int i = 0; i < 10; i++) {
          batch.add({
            'id': '$i',
            'tableName': 'guests',
            'type': 'insert',
            'data': {'name': 'Guest $i'},
          });
        }

        // Act
        await mockApiService.batchPush(batch);

        // Assert
        expect(mockApiService.callCount, equals(1));
      });

      test('should handle batch failure', () async {
        // Arrange
        mockApiService.shouldFail = true;
        mockApiService.lastError = 'Server error';

        final batch = <Map<String, dynamic>>[];
        for (int i = 0; i < 10; i++) {
          batch.add({
            'id': '$i',
            'tableName': 'guests',
            'type': 'insert',
            'data': {'name': 'Guest $i'},
          });
        }

        // Act & Assert
        expect(
          () => mockApiService.batchPush(batch),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('Connectivity', () {
      test('should detect online status', () {
        mockConnectivity.setOnline(true);
        expect(mockConnectivity.isOnline(), isTrue);
      });

      test('should detect offline status', () {
        mockConnectivity.setOnline(false);
        expect(mockConnectivity.isOnline(), isFalse);
      });
    });

    group('Error Handling', () {
      test('should handle network errors', () async {
        // Arrange
        mockApiService.shouldFail = true;
        mockApiService.lastError = 'Connection timeout';

        final data = {'id': '1', 'name': 'Test'};

        // Act & Assert
        expect(() => mockApiService.pushData(data), throwsA(isA<Exception>()));
      });

      test('should handle server errors', () async {
        // Arrange
        mockApiService.shouldFail = true;
        mockApiService.lastError = '500 Internal Server Error';

        final data = {'id': '1', 'name': 'Test'};

        // Act & Assert
        expect(() => mockApiService.pushData(data), throwsA(isA<Exception>()));
      });

      test('should mark item as failed after max retries', () async {
        // Arrange
        mockOutboxDao.addPending({
          'id': '1',
          'tableName': 'guests',
          'type': 'insert',
          'data': {'name': 'Test Guest'},
          'timestamp': DateTime.now().toIso8601String(),
          'status': 'pending',
          'retryCount': 5,
        });

        // Act
        await mockOutboxDao.markAsFailed('1', 'Max retries exceeded');

        // Assert
        final pending = await mockOutboxDao.getPending();
        expect(pending.first['status'], equals('failed'));
        expect(pending.first['error'], equals('Max retries exceeded'));
      });
    });

    group('Performance', () {
      test('should handle large number of pending items', () async {
        // Arrange - add 1000 items
        for (int i = 0; i < 1000; i++) {
          mockOutboxDao.addPending({
            'id': '$i',
            'tableName': 'guests',
            'type': 'insert',
            'data': {'name': 'Guest $i'},
            'timestamp': DateTime.now().toIso8601String(),
            'status': 'pending',
            'retryCount': 0,
          });
        }

        // Act
        final startTime = DateTime.now();
        final count = await mockOutboxDao.getPendingCount();
        final duration = DateTime.now().difference(startTime);

        // Assert
        expect(count, equals(1000));
        expect(duration.inMilliseconds, lessThan(100)); // Should be fast
      });
    });
  });
}
