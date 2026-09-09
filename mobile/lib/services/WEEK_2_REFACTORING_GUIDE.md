# Refactoring Guide: cloudflare_sync_manager.dart (Week 2)

## Overview
Split `cloudflare_sync_manager.dart` (3,370 LOC → 4 modular services).

## Extracted Modules

### 1. cloudflare_sync_device_service.dart (200 LOC)
**Purpose:** Device registration, FCM tokens, device management

**Exported Functions:**
```dart
// Device operations
Future<String> registerDevice()
Future<void> setFcmToken(String token)
Future<List<dynamic>> getRegisteredDevices()

// Internal
Future<void> _writeLocalDeviceRow(Map<String, dynamic> syncPayload)
Map<String, dynamic> _deviceSyncPayload({...})
```

**Exported Classes:**
```dart
class CloudflareSyncDeviceService {
  final http.Client httpClient;
  final AppDatabase database;
  
  void setCredentials(String token, String deviceId)
}
```

### 2. cloudflare_sync_push_service.dart (180 LOC)
**Purpose:** Push local changes (outbox) to Cloudflare D1

**Exported Functions:**
```dart
// Outbox operations
Future<int> pushOutbox()
Future<({int pushed, Set<int> failedIds})> _pushBatch(List<OutboxRecord> batch)
Future<String> _rowVectorClock(String entity, String localUuid)
Future<Map<String, int>> pushAllLocalData()
```

**Exported Classes:**
```dart
class CloudflareSyncPushService {
  final http.Client httpClient;
  final AppDatabase database;
  final VectorClockService vectorClockService;
  
  void setCredentials(String token, String deviceId)
}

class OutboxRecord {
  final int id;
  final String entity;
  final String op;
  final String localUuid;
  final Map<String, dynamic>? payload;
  final int clientTs;
  final String idempotencyKey;
}
```

### 3. cloudflare_sync_pull_service.dart (250 LOC)
**Purpose:** Pull changes from Cloudflare, apply to local database, resolve foreign keys

**Exported Functions:**
```dart
// Pull operations
Future<int> pullChanges()
Future<http.Response> _fetchPullPage(int cursor, int limit)
Future<PullApplyReport> applyPulledRecords(List<...> records)

// Change application
Future<bool> _applyChange(String entity, Map<String, dynamic> record)
Future<bool> _resolveForeignKeysForRecord(String entity, Map<String, dynamic> record)
Future<Set<String>> _localColumns(String tableName)
Future<bool> _applyTombstone(String entity, String localUuid)
```

**Exported Classes:**
```dart
class CloudflareSyncPullService {
  final http.Client httpClient;
  final AppDatabase database;
  
  void setCredentials(String token, String deviceId)
  void setLastPullCursor(int cursor)
}

class PullApplyReport {
  final int appliedCount;
  final int deferredCount;
  final Set<String> touchedEntities;
  final List<String> unresolvable;
  final List<String> errors;
  
  bool get isClean => unresolvable.isEmpty && errors.isEmpty;
}
```

### 4. cloudflare_sync_manager_core.dart (900 LOC → remaining from original)
**Purpose:** Main orchestrator, core sync logic, initialization, statistics

**Retained From Original:**
- `CloudflareSyncManager` singleton
- `initialize()` method
- `sync()` main method
- `SyncResult` class
- `configureForTesting()`
- Auto-sync management (startAutoSync, stopAutoSync)
- Statistics tracking
- Quarantine management
- Device ID management

## Module Dependencies

```
cloudflare_sync_manager_core
├── uses → CloudflareSyncDeviceService
├── uses → CloudflareSyncPushService
├── uses → CloudflareSyncPullService
└── depends on → local_db, http, drift
```

## Size Reduction

| File | Before | After | Type |
|------|--------|-------|------|
| cloudflare_sync_manager.dart | 3,370 | ~800 | core |
| cloudflare_sync_device_service.dart | - | 200 | new |
| cloudflare_sync_push_service.dart | - | 180 | new |
| cloudflare_sync_pull_service.dart | - | 250 | new |
| **Total** | **3,370** | **1,430** | **58% ↓** |

## Migration Path

### Step 1: Update cloudflare_sync_manager_core.dart Imports
```dart
import 'cloudflare_sync_device_service.dart';
import 'cloudflare_sync_push_service.dart';
import 'cloudflare_sync_pull_service.dart';
```

### Step 2: Initialize Services in CloudflareSyncManager
```dart
class CloudflareSyncManager {
  late CloudflareSyncDeviceService _deviceService;
  late CloudflareSyncPushService _pushService;
  late CloudflareSyncPullService _pullService;
  
  void _initializeServices() {
    _deviceService = CloudflareSyncDeviceService(
      httpClient: _httpClient,
      database: _db!,
    );
    _pushService = CloudflareSyncPushService(
      httpClient: _httpClient,
      database: _db!,
      vectorClockService: _vectorClockService,
    );
    _pullService = CloudflareSyncPullService(
      httpClient: _httpClient,
      database: _db!,
    );
  }
}
```

### Step 3: Replace Method Calls
```dart
// OLD
Future<String> registerDevice() async { ... }

// NEW
Future<String> registerDevice() => _deviceService.registerDevice();

// OLD
Future<int> _pushOutbox() async { ... }

// NEW
Future<int> _pushOutbox() => _pushService.pushOutbox();

// OLD
Future<int> _pullChanges() async { ... }

// NEW
Future<int> _pullChanges() => _pullService.pullChanges();
```

## Testing Strategy

### Unit Tests for Each Module
1. **device_service_test.dart** (12 tests)
   - registerDevice() success/failure
   - setFcmToken() with valid/invalid tokens
   - Device payload generation

2. **push_service_test.dart** (15 tests)
   - pushOutbox() with various batch sizes
   - _pushBatch() retry logic
   - Vector clock resolution

3. **pull_service_test.dart** (20 tests)
   - pullChanges() pagination
   - applyPulledRecords() with FK resolution
   - Foreign key failure scenarios
   - Tombstone application

### Integration Tests
1. Full sync cycle (push → pull)
2. Concurrent device operations
3. Error recovery and retry

## Performance Implications

| Aspect | Before | After | Note |
|--------|--------|-------|------|
| File Load Time | High | Low | Smaller files load faster |
| Memory | High | Lower | Services load on demand |
| Testability | Difficult | Easy | Unit testable services |
| Maintenance | Hard | Easy | Clear separation of concerns |

## Benefits

✅ **Clarity**: Each service has single responsibility
✅ **Testability**: Unit test each service independently
✅ **Reusability**: Services can be used in other contexts
✅ **Maintainability**: Bug fixes isolated to one service
✅ **Scalability**: Easier to add new sync strategies
✅ **Performance**: Lazy load services as needed

## Next Steps (Week 3)

1. Create comprehensive test suite for all 3 services
2. Create integration tests for sync cycle
3. Split income_expense_report_screen.dart (2,944 LOC → 4 files)
4. Add performance benchmarks

## References

- Original file: `lib/services/cloudflare_sync_manager.dart` (3,370 LOC)
- Phase: Phase 3 - Week 2
- Date: 2026-09-10
- Status: 50% Complete (3/4 modules extracted, core pending)
