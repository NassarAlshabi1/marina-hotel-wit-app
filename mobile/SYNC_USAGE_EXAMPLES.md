# 💡 Optimized Sync Service - Usage Examples

Practical code examples for integrating the optimized sync system.

---

## 🚀 Quick Start

### Basic Sync Operation

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'services/optimized_sync_service.dart';
import 'services/google_drive_backup_service.dart';

// In your widget or service
Future<void> performSync() async {
  final syncService = OptimizedSyncService.instance;
  final driveService = GoogleDriveBackupService();
  
  // Initialize (once)
  await syncService.initialize(driveService);
  
  // Perform sync
  final result = await syncService.performSync();
  
  if (result.success) {
    print('✅ Sync successful!');
    print('   Uploaded: ${result.recordsUploaded} records');
    print('   Downloaded: ${result.recordsDownloaded} records');
    print('   Duration: ${result.durationMs}ms');
    print('   Bandwidth saved: ${result.compressionRatio.toStringAsFixed(1)}%');
  } else {
    print('❌ Sync failed: ${result.errorMessage}');
  }
}
```

---

## 🔄 Automatic Background Sync

### Using Timer for Periodic Sync

```dart
import 'dart:async';

class AutoSyncManager {
  Timer? _syncTimer;
  final OptimizedSyncService _syncService = OptimizedSyncService.instance;
  
  void startAutoSync({int intervalMinutes = 5}) {
    _syncTimer?.cancel();
    
    _syncTimer = Timer.periodic(
      Duration(minutes: intervalMinutes),
      (timer) async {
        print('🔄 Auto-sync triggered');
        await _syncService.performSync();
      },
    );
    
    // Immediate first sync
    Future.microtask(() => _syncService.performSync());
  }
  
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
}
```

### Integration with Riverpod

```dart
// Provider
final autoSyncManagerProvider = Provider<AutoSyncManager>((ref) {
  final manager = AutoSyncManager();
  
  // Start auto-sync when Google Drive is signed in
  final backupState = ref.watch(backupStatusProvider);
  if (backupState.isSignedIn) {
    manager.startAutoSync(intervalMinutes: 5);
  } else {
    manager.stopAutoSync();
  }
  
  ref.onDispose(() {
    manager.stopAutoSync();
  });
  
  return manager;
});

// In your UI
class SettingsScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final autoSyncManager = ref.watch(autoSyncManagerProvider);
    
    return SwitchListTile(
      title: Text('Auto-Sync'),
      value: autoSyncManager.isEnabled,
      onChanged: (enabled) {
        if (enabled) {
          autoSyncManager.startAutoSync();
        } else {
          autoSyncManager.stopAutoSync();
        }
      },
    );
  }
}
```

---

## ⚙️ Configuration Options

### Conflict Resolution Strategies

```dart
// Strategy 1: Newer Wins (Default - Recommended)
final result = await syncService.performSync(
  conflictStrategy: ConflictResolution.newerWins,
);
// Most recent change wins, with version as tie-breaker

// Strategy 2: Version Wins
final result = await syncService.performSync(
  conflictStrategy: ConflictResolution.versionWins,
);
// Higher version number always wins

// Strategy 3: Manual Resolution
final result = await syncService.performSync(
  conflictStrategy: ConflictResolution.manualResolve,
);
// Saves conflicts to database for user review
```

### Full vs Delta Sync

```dart
// Normal delta sync (default)
await syncService.performSync();

// Force full sync (all records)
await syncService.performSync(forceFull: true);
// Use for:
// - Initial sync of new device
// - After database corruption
// - Manual user request
```

---

## 📊 Monitoring & Metrics

### Displaying Sync Metrics

```dart
class SyncMetricsWidget extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = getDatabase();
    
    return FutureBuilder<List<SyncLogData>>(
      future: _getRecentSyncs(db),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        
        final syncs = snapshot.data!;
        final successRate = syncs.where((s) => s.status == 'completed').length / syncs.length;
        final avgDuration = syncs.fold<int>(0, (sum, s) => sum + (s.durationMs ?? 0)) / syncs.length;
        
        return Column(
          children: [
            MetricCard(
              label: 'Success Rate',
              value: '${(successRate * 100).toStringAsFixed(1)}%',
              icon: Icons.check_circle,
              color: Colors.green,
            ),
            MetricCard(
              label: 'Avg Duration',
              value: '${(avgDuration / 1000).toStringAsFixed(1)}s',
              icon: Icons.timer,
              color: Colors.blue,
            ),
            // More metrics...
          ],
        );
      },
    );
  }
  
  Future<List<SyncLogData>> _getRecentSyncs(AppDatabase db) async {
    return (db.select(db.syncLog)
      ..orderBy([(t) => OrderingTerm.desc(t.startTimestamp)])
      ..limit(10)
    ).get();
  }
}
```

### Live Sync Progress

```dart
class SyncProgressIndicator extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    
    if (syncStatus == SyncStatus.idle) {
      return SizedBox.shrink(); // Hidden when not syncing
    }
    
    return Container(
      padding: EdgeInsets.all(12),
      color: Colors.blue.shade50,
      child: Row(
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          SizedBox(width: 12),
          Text(_getSyncStatusText(syncStatus)),
        ],
      ),
    );
  }
  
  String _getSyncStatusText(SyncStatus status) {
    switch (status) {
      case SyncStatus.preparingDelta:
        return 'جارٍ كشف التغييرات...';
      case SyncStatus.uploading:
        return 'جارٍ رفع البيانات...';
      case SyncStatus.downloading:
        return 'جارٍ تحميل التحديثات...';
      case SyncStatus.merging:
        return 'جارٍ دمج البيانات...';
      default:
        return 'جارٍ المزامنة...';
    }
  }
}
```

---

## 🤝 Conflict Resolution UI

### Manual Conflict Resolution Screen

```dart
class ConflictResolutionScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = getDatabase();
    
    return FutureBuilder<List<SyncConflictLogData>>(
      future: _getUnresolvedConflicts(db),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return CircularProgressIndicator();
        
        final conflicts = snapshot.data!;
        
        if (conflicts.isEmpty) {
          return Center(
            child: Text('لا توجد تضاربات تحتاج حل يدوي'),
          );
        }
        
        return ListView.builder(
          itemCount: conflicts.length,
          itemBuilder: (context, index) {
            final conflict = conflicts[index];
            final localData = jsonDecode(conflict.localData);
            final remoteData = jsonDecode(conflict.remoteData);
            
            return ConflictCard(
              tableName: conflict.tableName,
              recordUuid: conflict.recordUuid,
              localData: localData,
              remoteData: remoteData,
              localTimestamp: DateTime.fromMillisecondsSinceEpoch(
                conflict.localTimestamp,
              ),
              remoteTimestamp: DateTime.fromMillisecondsSinceEpoch(
                conflict.remoteTimestamp,
              ),
              onResolve: (chosenData) async {
                await _resolveConflict(db, conflict.conflictId, chosenData);
                setState(() {}); // Refresh
              },
            );
          },
        );
      },
    );
  }
  
  Future<List<SyncConflictLogData>> _getUnresolvedConflicts(AppDatabase db) async {
    return (db.select(db.syncConflictLog)
      ..where((t) => t.status.equals('pending'))
      ..orderBy([(t) => OrderingTerm.desc(t.detectedAt)]))
      .get();
  }
  
  Future<void> _resolveConflict(
    AppDatabase db,
    String conflictId,
    Map<String, dynamic> chosenData,
  ) async {
    await (db.update(db.syncConflictLog)
      ..where((t) => t.conflictId.equals(conflictId)))
      .write(SyncConflictLogCompanion(
        resolvedData: Value(jsonEncode(chosenData)),
        resolvedAt: Value(DateTime.now().millisecondsSinceEpoch),
        resolvedBy: Value('manual'),
        status: const Value('resolved'),
      ));
  }
}

class ConflictCard extends StatelessWidget {
  final String tableName;
  final String recordUuid;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime localTimestamp;
  final DateTime remoteTimestamp;
  final Function(Map<String, dynamic>) onResolve;
  
  const ConflictCard({
    required this.tableName,
    required this.recordUuid,
    required this.localData,
    required this.remoteData,
    required this.localTimestamp,
    required this.remoteTimestamp,
    required this.onResolve,
    super.key,
  });
  
  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.warning, color: Colors.orange),
                SizedBox(width: 8),
                Text(
                  'تضارب في $tableName',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 16),
            
            // Local version
            _buildDataPreview(
              'النسخة المحلية',
              localData,
              localTimestamp,
              Colors.blue,
            ),
            
            SizedBox(height: 16),
            
            // Remote version
            _buildDataPreview(
              'النسخة من جهاز آخر',
              remoteData,
              remoteTimestamp,
              Colors.green,
            ),
            
            SizedBox(height: 16),
            
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onResolve(localData),
                    child: Text('اختيار المحلية'),
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => onResolve(remoteData),
                    child: Text('اختيار الأخرى'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDataPreview(
    String title,
    Map<String, dynamic> data,
    DateTime timestamp,
    Color color,
  ) {
    return Container(
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(fontWeight: FontWeight.bold, color: color),
          ),
          SizedBox(height: 8),
          Text('الوقت: ${timestamp.toString()}'),
          SizedBox(height: 4),
          // Show key fields based on table type
          if (tableName == 'bookings') ...[
            Text('الضيف: ${data['guest_name']}'),
            Text('الغرفة: ${data['room_number']}'),
            Text('الحالة: ${data['status']}'),
          ],
          // Add more table-specific fields
        ],
      ),
    );
  }
}
```

---

## 🎨 UI Components

### Sync Button with Status

```dart
class SyncButton extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final isSyncing = syncStatus != SyncStatus.idle;
    
    return FloatingActionButton.extended(
      onPressed: isSyncing ? null : () => _performManualSync(ref),
      icon: isSyncing 
        ? SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
          )
        : Icon(Icons.sync),
      label: Text(isSyncing ? 'جارٍ المزامنة...' : 'مزامنة'),
    );
  }
  
  Future<void> _performManualSync(WidgetRef ref) async {
    ref.read(syncStatusProvider.notifier).state = SyncStatus.preparingDelta;
    
    try {
      final syncService = ref.read(optimizedSyncServiceProvider);
      
      ref.read(syncStatusProvider.notifier).state = SyncStatus.uploading;
      final result = await syncService.performSync();
      
      ref.read(syncStatusProvider.notifier).state = SyncStatus.completed;
      
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'تمت المزامنة بنجاح: ${result.totalRecords} سجل',
            ),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('فشلت المزامنة: ${result.errorMessage}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      await Future.delayed(Duration(seconds: 2));
      ref.read(syncStatusProvider.notifier).state = SyncStatus.idle;
    }
  }
}
```

### Sync History List

```dart
class SyncHistoryScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final db = getDatabase();
    
    return Scaffold(
      appBar: AppBar(title: Text('سجل المزامنة')),
      body: FutureBuilder<List<SyncLogData>>(
        future: _getRecentSyncs(db),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator());
          }
          
          final syncs = snapshot.data!;
          
          return ListView.builder(
            itemCount: syncs.length,
            itemBuilder: (context, index) {
              final sync = syncs[index];
              final timestamp = DateTime.fromMillisecondsSinceEpoch(
                sync.startTimestamp,
              );
              final isSuccess = sync.status == 'completed';
              
              return ListTile(
                leading: Icon(
                  isSuccess ? Icons.check_circle : Icons.error,
                  color: isSuccess ? Colors.green : Colors.red,
                ),
                title: Text(
                  '${sync.syncType.toUpperCase()} - ${sync.direction}',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('الوقت: ${timestamp.toString()}'),
                    Text(
                      'السجلات: ↑${sync.recordsUploaded} ↓${sync.recordsDownloaded}',
                    ),
                    if (sync.durationMs != null)
                      Text('المدة: ${sync.durationMs}ms'),
                    if (sync.compressionRatio != null)
                      Text(
                        'الضغط: ${sync.compressionRatio!.toStringAsFixed(1)}%',
                      ),
                    if (sync.conflictsResolved > 0)
                      Text(
                        'التضاربات: ${sync.conflictsResolved}',
                        style: TextStyle(color: Colors.orange),
                      ),
                  ],
                ),
                trailing: sync.status == 'failed'
                  ? IconButton(
                      icon: Icon(Icons.info_outline),
                      onPressed: () => _showErrorDetails(context, sync),
                    )
                  : null,
              );
            },
          );
        },
      ),
    );
  }
  
  Future<List<SyncLogData>> _getRecentSyncs(AppDatabase db) async {
    return (db.select(db.syncLog)
      ..orderBy([(t) => OrderingTerm.desc(t.startTimestamp)])
      ..limit(50)
    ).get();
  }
  
  void _showErrorDetails(BuildContext context, SyncLogData sync) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('تفاصيل الخطأ'),
        content: Text(sync.errorMessage ?? 'خطأ غير معروف'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('حسناً'),
          ),
        ],
      ),
    );
  }
}
```

---

## 🧪 Testing Examples

### Unit Test: Delta Detection

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

void main() {
  group('OptimizedSyncService', () {
    late OptimizedSyncService syncService;
    late MockGoogleDriveBackupService mockDriveService;
    
    setUp(() {
      syncService = OptimizedSyncService.instance;
      mockDriveService = MockGoogleDriveBackupService();
      syncService.initialize(mockDriveService);
    });
    
    test('prepareDelta returns null when no changes', () async {
      // Setup: No records modified since last sync
      // ...
      
      final delta = await syncService.prepareDelta();
      
      expect(delta, isNull);
    });
    
    test('prepareDelta detects modified records', () async {
      // Setup: Insert test records with recent timestamps
      // ...
      
      final delta = await syncService.prepareDelta();
      
      expect(delta, isNotNull);
      expect(delta!.changes.length, greaterThan(0));
      expect(delta.changes.first.hash, isNotEmpty);
    });
    
    test('compression reduces size by >70%', () async {
      final testData = jsonEncode({
        'changes': List.generate(100, (i) => {
          'table': 'bookings',
          'uuid': 'uuid-$i',
          'data': {'field': 'value'},
        }),
      });
      
      final compressed = await syncService.compress(testData);
      final compressionRatio = 1 - (compressed.length / testData.length);
      
      expect(compressionRatio, greaterThan(0.7)); // >70% compression
    });
  });
}
```

### Integration Test: Full Sync Flow

```dart
void main() {
  testWidgets('Full sync flow works end-to-end', (tester) async {
    // Setup two mock devices
    final deviceA = TestDevice('deviceA');
    final deviceB = TestDevice('deviceB');
    
    // Device A: Create data
    await deviceA.createBooking('Booking 1');
    await deviceA.createPayment(amount: 100.0);
    
    // Device A: Sync
    final syncResultA = await deviceA.sync();
    expect(syncResultA.success, isTrue);
    expect(syncResultA.recordsUploaded, equals(2));
    
    // Device B: Sync (should download changes)
    final syncResultB = await deviceB.sync();
    expect(syncResultB.success, isTrue);
    expect(syncResultB.recordsDownloaded, equals(2));
    
    // Verify data consistency
    final deviceBBookings = await deviceB.getBookings();
    expect(deviceBBookings.length, equals(1));
    expect(deviceBBookings.first.guestName, equals('Booking 1'));
  });
  
  testWidgets('Conflict resolution works correctly', (tester) async {
    final deviceA = TestDevice('deviceA');
    final deviceB = TestDevice('deviceB');
    
    // Both devices modify same booking
    await deviceA.updateBooking('uuid-1', guestName: 'Ahmed Ali');
    await Future.delayed(Duration(seconds: 2));
    await deviceB.updateBooking('uuid-1', guestName: 'Ahmad Ali');
    
    // Device A syncs first
    await deviceA.sync();
    
    // Device B syncs (should detect conflict and resolve)
    final syncResultB = await deviceB.sync(
      conflictStrategy: ConflictResolution.newerWins,
    );
    
    expect(syncResultB.success, isTrue);
    expect(syncResultB.conflictsResolved, equals(1));
    
    // Device B's newer version should win
    final booking = await deviceB.getBooking('uuid-1');
    expect(booking.guestName, equals('Ahmad Ali'));
  });
}
```

---

## 🔧 Advanced Usage

### Custom Sync Triggers

```dart
// Trigger sync after specific operations
class BookingService {
  final OptimizedSyncService _syncService = OptimizedSyncService.instance;
  
  Future<void> createBooking(Booking booking) async {
    final db = getDatabase();
    
    // Insert booking
    await db.into(db.bookings).insert(booking);
    
    // Trigger sync immediately (critical data)
    await _syncService.performSync();
  }
  
  Future<void> updateBookingStatus(String uuid, String status) async {
    final db = getDatabase();
    
    // Update status
    await (db.update(db.bookings)
      ..where((t) => t.localUuid.equals(uuid)))
      .write(BookingsCompanion(
        status: Value(status),
        lastModified: Value(DateTime.now().millisecondsSinceEpoch),
      ));
    
    // Debounced sync (wait 5 seconds for more changes)
    _debouncedSync();
  }
  
  Timer? _syncTimer;
  void _debouncedSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer(Duration(seconds: 5), () {
      _syncService.performSync();
    });
  }
}
```

### Offline Queue Management

```dart
class OfflineSyncQueue {
  static const _queueKey = 'offline_sync_queue';
  
  // Add change to offline queue
  static Future<void> queueChange(ChangeRecord change) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getString(_queueKey);
    
    List<Map<String, dynamic>> queue = [];
    if (queueJson != null) {
      queue = (jsonDecode(queueJson) as List).cast<Map<String, dynamic>>();
    }
    
    queue.add(change.toJson());
    await prefs.setString(_queueKey, jsonEncode(queue));
    
    print('📝 Queued change for offline sync: ${change.tableName}/${change.recordUuid}');
  }
  
  // Process queue when back online
  static Future<void> processQueue() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getString(_queueKey);
    
    if (queueJson == null) return;
    
    final queue = (jsonDecode(queueJson) as List)
      .map((json) => ChangeRecord.fromJson(json))
      .toList();
    
    if (queue.isEmpty) return;
    
    print('🔄 Processing offline queue: ${queue.length} changes');
    
    final syncService = OptimizedSyncService.instance;
    final result = await syncService.performSync();
    
    if (result.success) {
      // Clear queue
      await prefs.remove(_queueKey);
      print('✅ Offline queue processed successfully');
    }
  }
}

// Usage with connectivity monitoring
import 'package:connectivity_plus/connectivity_plus.dart';

class ConnectivitySyncManager {
  final Connectivity _connectivity = Connectivity();
  StreamSubscription? _subscription;
  
  void startMonitoring() {
    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      if (result != ConnectivityResult.none) {
        print('📡 Network available - processing offline queue');
        OfflineSyncQueue.processQueue();
      }
    });
  }
  
  void stopMonitoring() {
    _subscription?.cancel();
  }
}
```

---

## 📈 Performance Tuning

### Adaptive Sync Intervals

```dart
class AdaptiveSyncScheduler {
  static const _baseIntervalMinutes = 5;
  
  static Future<int> calculateOptimalInterval() async {
    final connectivity = await Connectivity().checkConnectivity();
    final batteryLevel = await _getBatteryLevel();
    final recentChangeFrequency = await _getRecentChangeFrequency();
    
    // On WiFi with good battery
    if (connectivity == ConnectivityResult.wifi && batteryLevel > 50) {
      // High frequency if lots of recent changes
      if (recentChangeFrequency > 10) {
        return 2; // Every 2 minutes
      }
      return _baseIntervalMinutes; // Every 5 minutes
    }
    
    // On mobile data or low battery
    if (connectivity == ConnectivityResult.mobile || batteryLevel < 20) {
      return 15; // Every 15 minutes
    }
    
    // Default
    return _baseIntervalMinutes;
  }
  
  static Future<int> _getBatteryLevel() async {
    // Use battery_plus package
    // final battery = Battery();
    // return await battery.batteryLevel;
    return 100; // Placeholder
  }
  
  static Future<int> _getRecentChangeFrequency() async {
    // Count changes in last hour
    final db = getDatabase();
    final oneHourAgo = DateTime.now()
      .subtract(Duration(hours: 1))
      .millisecondsSinceEpoch;
    
    int totalChanges = 0;
    
    // Count from each table
    totalChanges += await (db.selectOnly(db.bookings)
      ..where(db.bookings.lastModified.isBiggerThanValue(oneHourAgo))
      ..addColumns([db.bookings.id.count()]))
      .getSingle()
      .then((row) => row.read(db.bookings.id.count()) ?? 0);
    
    // ... count other tables
    
    return totalChanges;
  }
}
```

### Smart Retry Logic

```dart
class SyncRetryManager {
  static const _maxRetries = 3;
  static const _baseDelaySeconds = 2;
  
  static Future<SyncResult> performSyncWithRetry({
    required OptimizedSyncService syncService,
    int maxRetries = _maxRetries,
  }) async {
    int attempt = 0;
    
    while (attempt < maxRetries) {
      attempt++;
      
      print('🔄 Sync attempt $attempt/$maxRetries');
      
      try {
        final result = await syncService.performSync();
        
        if (result.success) {
          print('✅ Sync successful on attempt $attempt');
          return result;
        }
        
        // Failed, but might be temporary
        if (attempt < maxRetries) {
          final delay = _calculateBackoffDelay(attempt);
          print('⏳ Retrying in ${delay}s...');
          await Future.delayed(Duration(seconds: delay));
        }
        
      } catch (e) {
        print('❌ Sync attempt $attempt failed: $e');
        
        if (attempt >= maxRetries) {
          return SyncResult.error('Max retries exceeded: $e');
        }
        
        final delay = _calculateBackoffDelay(attempt);
        print('⏳ Retrying in ${delay}s...');
        await Future.delayed(Duration(seconds: delay));
      }
    }
    
    return SyncResult.error('All retry attempts failed');
  }
  
  // Exponential backoff: 2s, 4s, 8s
  static int _calculateBackoffDelay(int attempt) {
    return _baseDelaySeconds * (1 << (attempt - 1));
  }
}
```

---

## 🎯 Best Practices

### 1. **Sync on Critical Operations**

```dart
// Always sync after critical data changes
Future<void> confirmBooking(String bookingId) async {
  await updateBookingStatus(bookingId, 'confirmed');
  
  // Immediate sync for critical operation
  await OptimizedSyncService.instance.performSync();
}
```

### 2. **Debounce for Bulk Operations**

```dart
// Don't sync after every change during bulk import
Future<void> importBookings(List<Booking> bookings) async {
  final db = getDatabase();
  
  // Batch insert
  await db.batch((batch) {
    batch.insertAll(db.bookings, bookings);
  });
  
  // Single sync after all imports
  await OptimizedSyncService.instance.performSync();
}
```

### 3. **Monitor Data Usage**

```dart
class DataUsageMonitor {
  static Future<void> checkUsageBeforeSync() async {
    final connectivity = await Connectivity().checkConnectivity();
    
    if (connectivity == ConnectivityResult.mobile) {
      // On mobile data - check if user allows
      final allowMobileSync = await _getUserPreference('allow_mobile_sync');
      
      if (!allowMobileSync) {
        print('⏸️ Skipping sync on mobile data (user preference)');
        return;
      }
      
      // Warn if large sync expected
      final pendingChanges = await _estimatePendingChanges();
      if (pendingChanges > 1024 * 1024) { // > 1 MB
        print('⚠️ Large sync pending: ${_formatBytes(pendingChanges)}');
        // Show user warning
      }
    }
    
    // Proceed with sync
    await OptimizedSyncService.instance.performSync();
  }
}
```

---

## 🐛 Debugging & Troubleshooting

### Enable Verbose Logging

```dart
class SyncDebugger {
  static bool enableVerboseLogging = false;
  
  static Future<void> performDebugSync() async {
    enableVerboseLogging = true;
    
    final syncService = OptimizedSyncService.instance;
    
    print('');
    print('🐛 DEBUG SYNC STARTED');
    print('═══════════════════════════════════════════════════════');
    
    // Check prerequisites
    print('1. Checking Google Drive connection...');
    final driveService = GoogleDriveBackupService();
    print('   Signed in: ${driveService.isSignedIn}');
    print('   User: ${driveService.currentUser?.email}');
    
    print('');
    print('2. Checking last sync timestamp...');
    final lastSync = await syncService._getLastSyncTimestamp();
    print('   Last sync: ${lastSync?.toString() ?? "Never"}');
    
    print('');
    print('3. Performing sync with detailed logging...');
    final result = await syncService.performSync();
    
    print('');
    print('4. Sync Result:');
    print('   Success: ${result.success}');
    print('   Records Up: ${result.recordsUploaded}');
    print('   Records Down: ${result.recordsDownloaded}');
    print('   Conflicts: ${result.conflictsResolved}');
    print('   Duration: ${result.durationMs}ms');
    if (!result.success) {
      print('   Error: ${result.errorMessage}');
    }
    
    print('═══════════════════════════════════════════════════════');
    print('🐛 DEBUG SYNC COMPLETED');
    print('');
    
    enableVerboseLogging = false;
  }
}
```

### Force Full Sync (Debug)

```dart
// Force a complete re-sync (use for testing or corruption recovery)
Future<void> forceCompleteResync() async {
  print('⚠️ FORCING COMPLETE RESYNC - ALL DATA WILL BE PROCESSED');
  
  // Clear all cached hashes
  final db = getDatabase();
  await db.delete(db.syncRowHash).go();
  print('   ✓ Cleared hash cache');
  
  // Clear last sync timestamp
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('optimized_sync_last_timestamp');
  print('   ✓ Cleared sync timestamp');
  
  // Perform full sync
  final syncService = OptimizedSyncService.instance;
  final result = await syncService.performSync(forceFull: true);
  
  print('');
  print('✅ Complete resync finished');
  print('   Records synced: ${result.totalRecords}');
  print('   Duration: ${result.durationMs}ms');
}
```

---

**Documentation Version:** 1.0  
**Last Updated:** 2024  
**For:** Marina Hotel Management App
