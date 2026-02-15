import 'package:marina_hotel_mobile/services/sync/adapters/sync_adapter.dart';
import 'package:marina_hotel_mobile/services/sync/models/sync_result.dart';

/// محول مزامنة وهمي للاختبارات
class MockSyncAdapter implements SyncAdapter {
  @override
  final String name;
  
  bool isInitialized = false;
  bool isEnabled = true;
  bool shouldFail = false;
  int failCount = 0;
  int syncCallCount = 0;
  bool isConnected = true;
  
  MockSyncAdapter({required this.name});

  @override
  Future<void> initialize() async {
    isInitialized = true;
  }

  @override
  Future<SyncResult> sync({required bool push, required bool pull}) async {
    syncCallCount++;
    
    if (!isConnected) {
      return SyncResult.offline();
    }
    
    if (shouldFail && syncCallCount <= failCount) {
      throw Exception('Sync failed (attempt $syncCallCount)');
    }
    
    return SyncResult.success(
      pushed: push ? 5 : 0,
      pulled: pull ? 3 : 0,
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    isEnabled = enabled;
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    return {
      'name': name,
      'calls': syncCallCount,
    };
  }

  @override
  Future<bool> checkConnection() async {
    return isConnected;
  }

  @override
  void dispose() {
    // Cleanup
  }
}
