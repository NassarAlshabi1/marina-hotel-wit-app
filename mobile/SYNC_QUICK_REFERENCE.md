# ⚡ Optimized Sync - Quick Reference

Fast reference for developers working with the optimized sync system.

---

## 🚀 Quick Start

```dart
// Initialize (once at app startup)
final syncService = OptimizedSyncService.instance;
await syncService.initialize(GoogleDriveBackupService());

// Perform sync
final result = await syncService.performSync();

// Check result
if (result.success) {
  print('✅ ${result.totalRecords} records synced in ${result.durationMs}ms');
} else {
  print('❌ ${result.errorMessage}');
}
```

---

## 📊 Key Classes

### OptimizedSyncService

```dart
class OptimizedSyncService {
  // Main methods
  Future<SyncResult> performSync({
    bool forceFull = false,
    ConflictResolution conflictStrategy = ConflictResolution.newerWins,
  });
  
  Future<DeltaPackage?> prepareDelta({bool forceFull = false});
  Future<UploadResult> uploadDelta(DeltaPackage delta, ...);
  Future<DeltaPackage?> downloadDelta({required String deviceId});
  Future<MergeResult> mergeRecords(DeltaPackage remoteDelta, ...);
  Future<Map<String, dynamic>> resolveConflict(...);
  
  // Compression
  Future<Uint8List> compress(String jsonData);
  Future<String> decompress(Uint8List compressed);
}
```

### SyncResult

```dart
class SyncResult {
  final bool success;
  final int recordsUploaded;
  final int recordsDownloaded;
  final int conflictsResolved;
  final int durationMs;
  final double compressionRatio;
  final String? errorMessage;
  
  int get totalRecords;
  double get throughputRecordsPerSec;
}
```

### DeltaPackage

```dart
class DeltaPackage {
  final List<ChangeRecord> changes;
  final DateTime timestamp;
  final String deviceId;
}
```

### ChangeRecord

```dart
class ChangeRecord {
  final String tableName;
  final String recordUuid;
  final ChangeAction action; // insert, update, delete
  final Map<String, dynamic>? data;
  final DateTime timestamp;
  final String hash; // SHA-1
  final int version;
}
```

---

## 🎯 Common Tasks

### Trigger Manual Sync

```dart
final result = await OptimizedSyncService.instance.performSync();
```

### Force Full Sync

```dart
final result = await OptimizedSyncService.instance.performSync(
  forceFull: true,
);
```

### Change Conflict Strategy

```dart
final result = await OptimizedSyncService.instance.performSync(
  conflictStrategy: ConflictResolution.versionWins,
);
```

### Auto-Sync Every 5 Minutes

```dart
Timer.periodic(Duration(minutes: 5), (timer) async {
  await OptimizedSyncService.instance.performSync();
});
```

### Check if Sync in Progress

```dart
if (OptimizedSyncService.instance._isSyncing) {
  print('Sync already running');
}
```

---

## 📊 Database Queries

### Get Recent Syncs

```dart
final syncs = await (db.select(db.syncLog)
  ..orderBy([(t) => OrderingTerm.desc(t.startTimestamp)])
  ..limit(10)
).get();
```

### Get Sync Success Rate

```dart
final total = await db.select(db.syncLog).get();
final successful = total.where((s) => s.status == 'completed').length;
final successRate = successful / total.length;
```

### Get Average Duration

```dart
final completed = await (db.select(db.syncLog)
  ..where((t) => t.status.equals('completed'))
).get();

final avgDuration = completed.fold<int>(0, (sum, s) => sum + (s.durationMs ?? 0)) 
                    / completed.length;
```

### Get Unresolved Conflicts

```dart
final conflicts = await (db.select(db.syncConflictLog)
  ..where((t) => t.status.equals('pending'))
).get();
```

### Get Cached Hash

```dart
final cachedHash = await (db.select(db.syncRowHash)
  ..where((t) => 
    t.tableName.equals('bookings') & 
    t.recordUuid.equals('uuid-123')
  )
).getSingleOrNull();
```

---

## 🔧 Configuration

### Default Settings

```dart
static const int _maxChunkSize = 1000; // Records per chunk
static const int _gzipCompressionLevel = 6; // 1-9, balance at 6
static const int _conflictTimeThresholdMs = 60000; // 60 seconds
```

### Tuning Parameters

```dart
// For slow networks: reduce chunk size
static const int _maxChunkSize = 500;

// For faster compression: lower level
static const int _gzipCompressionLevel = 3;

// For stricter conflict detection: lower threshold
static const int _conflictTimeThresholdMs = 30000; // 30 seconds
```

---

## 🐛 Debugging

### Enable Verbose Logging

```dart
// In optimized_sync_service.dart
debugPrint('🔍 Step-by-step logs appear here');
```

### Force Full Re-sync

```dart
// Clear cache
final prefs = await SharedPreferences.getInstance();
await prefs.remove('optimized_sync_last_timestamp');
await prefs.remove('optimized_sync_last_remote_timestamp');

// Clear hashes
await db.delete(db.syncRowHash).go();

// Sync
await OptimizedSyncService.instance.performSync(forceFull: true);
```

### Check Drive Connection

```dart
final driveService = GoogleDriveBackupService();
print('Signed in: ${driveService.isSignedIn}');
print('User: ${driveService.currentUser?.email}');
```

---

## ⚠️ Error Codes

| Error | Cause | Solution |
|-------|-------|----------|
| "Drive service not available" | Not signed in | Call `signInForDrive()` first |
| "Sync already in progress" | Concurrent sync | Wait for current sync to complete |
| "No changes detected" | Nothing to sync | Normal, no action needed |
| "Conflict detected" | Same record edited on 2 devices | Auto-resolved or manual UI |
| "Network timeout" | Poor connection | Automatic retry with backoff |

---

## 📈 Performance Tips

### 1. Batch Updates

```dart
// Don't sync after every change
for (final booking in bookings) {
  await createBooking(booking); // No sync here
}
// Sync once at the end
await OptimizedSyncService.instance.performSync();
```

### 2. Use Debouncing

```dart
Timer? _syncTimer;

void debouncedSync() {
  _syncTimer?.cancel();
  _syncTimer = Timer(Duration(seconds: 5), () {
    OptimizedSyncService.instance.performSync();
  });
}
```

### 3. Check Network Before Sync

```dart
final connectivity = await Connectivity().checkConnectivity();
if (connectivity == ConnectivityResult.mobile) {
  // Ask user or skip on mobile data
}
```

### 4. Monitor Battery

```dart
final battery = Battery();
final level = await battery.batteryLevel;
if (level < 20) {
  // Reduce sync frequency or skip
}
```

---

## 🎨 UI Snippets

### Sync Button

```dart
FloatingActionButton.extended(
  onPressed: () async {
    final result = await OptimizedSyncService.instance.performSync();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result.success ? '✅ تمت المزامنة' : '❌ فشلت')),
    );
  },
  icon: Icon(Icons.sync),
  label: Text('مزامنة'),
)
```

### Sync Progress

```dart
Consumer(
  builder: (context, ref, child) {
    final status = ref.watch(syncStatusProvider);
    if (status == SyncStatus.idle) return SizedBox();
    
    return LinearProgressIndicator();
  },
)
```

### Metrics Card

```dart
Card(
  child: ListTile(
    leading: Icon(Icons.analytics),
    title: Text('آخر مزامنة'),
    subtitle: FutureBuilder<SyncLogData?>(
      future: _getLastSync(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return Text('...');
        final sync = snapshot.data!;
        return Text(
          '${sync.recordsUploaded + sync.recordsDownloaded} سجل في ${sync.durationMs}ms',
        );
      },
    ),
  ),
)
```

---

## 🔐 Security Notes

- ✅ All data encrypted in transit (HTTPS)
- ✅ Google OAuth 2.0 authentication
- ✅ No plaintext passwords
- ✅ Audit trail in sync_log
- ✅ Conflict logs for debugging

---

## 📞 Cheat Sheet

```dart
// Initialize
await OptimizedSyncService.instance.initialize(driveService);

// Sync
await OptimizedSyncService.instance.performSync();

// Full sync
await OptimizedSyncService.instance.performSync(forceFull: true);

// Custom conflict resolution
await OptimizedSyncService.instance.performSync(
  conflictStrategy: ConflictResolution.versionWins,
);

// Get last sync time
final lastSync = await syncService._getLastSyncTimestamp();

// Check device ID
final deviceId = await syncService._getOrCreateDeviceId();

// Compress data
final compressed = await syncService.compress(jsonString);

// Decompress data
final decompressed = await syncService.decompress(compressedBytes);
```

---

**Version:** 1.0  
**Quick Ref ID:** SYNC-QR-001  
**Last Updated:** 2024
