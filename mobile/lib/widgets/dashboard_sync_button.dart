// ═══════════════════════════════════════════════════════════════
// 🔄 DASHBOARD SYNC BUTTON - الكود الكامل مع تنظيف Outbox
// Flutter + Riverpod + Drift + Appwrite
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

// ═══════════════════════════════════════════════════════════════
// 1. ENUMS & MODELS
// ═══════════════════════════════════════════════════════════════

enum SyncStatus { idle, pushing, syncing }

class SyncResult {
  final int recordsPushed;
  final int recordsCleaned;
  final List<String> syncedIds;
  
  SyncResult({
    required this.recordsPushed,
    required this.recordsCleaned,
    required this.syncedIds,
  });
}

// ═══════════════════════════════════════════════════════════════
// 2. DATABASE TABLES
// ═══════════════════════════════════════════════════════════════

@DataClassName('OutboxRecord')
class OutboxTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get recordId => text()();
  TextColumn get tableName => text()();
  TextColumn get operation => text()(); // create, update, delete
  TextColumn get payload => text()();
  BoolColumn get synced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get retryAt => dateTime().nullable()();
  
  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('SyncLog')
class SyncLogTable extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get syncId => text()();
  TextColumn get direction => text()();
  TextColumn get deviceId => text()();
  TextColumn get target => text()();
  TextColumn get status => text()();
  IntColumn? get recordsPushed => integer().nullable()();
  IntColumn? get recordsCleaned => integer().nullable()();
  IntColumn? get durationMs => integer().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  
  @override
  Set<Column> get primaryKey => {id};
}

// ═══════════════════════════════════════════════════════════════
// 3. DATABASE CLASS
// ═══════════════════════════════════════════════════════════════

@DriftDatabase(tables: [OutboxTable, SyncLogTable])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  
  @override
  int get schemaVersion => 1;
  
  static QueryExecutor _openConnection() {
    return LazyDatabase(() async {
      final dbFolder = await getApplicationDocumentsDirectory();
      final file = File(p.join(dbFolder.path, 'app.db'));
      return NativeDatabase(file);
    });
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. DAOs
// ═══════════════════════════════════════════════════════════════

@DriftAccessor(tables: [OutboxTable])
class OutboxDao extends DatabaseAccessor<AppDatabase> with _$OutboxDaoMixin {
  OutboxDao(AppDatabase db) : super(db);
  
  Future<List<OutboxTableData>> getPendingRecords() async {
    return (select(outboxTable)
          ..where((tbl) => tbl.synced.equals(false))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }
  
  Future<int> getPendingCount() async {
    final result = await (selectOnly(outboxTable)
        ..addColumns([outboxTable.id.count()])
        ..where(outboxTable.synced.equals(false)))
        .map((row) => row.read(outboxTable.id.count())!)
        .getSingle();
    return result ?? 0;
  }
  
  Future<int> clearSyncedRecords(List<String> syncedRecordIds) async {
    if (syncedRecordIds.isEmpty) return 0;
    
    await customStatement('''
      DELETE FROM outbox_table 
      WHERE record_id IN (${syncedRecordIds.map((_) => '?').join(',')})
      AND synced = 0
    ''', syncedRecordIds);
    
    return syncedRecordIds.length;
  }
  
  Future<void> markAsSynced(List<String> recordIds) async {
    await (update(outboxTable)..where((tbl) => outboxTable.recordId.isInValues(recordIds)))
        .write(const OutboxTableCompanion(synced: Value(true)));
  }
}

@DriftAccessor(tables: [SyncLogTable])
class SyncLogDao extends DatabaseAccessor<AppDatabase> with _$SyncLogDaoMixin {
  SyncLogDao(AppDatabase db) : super(db);
  
  Future<void> logSync({
    required String syncId,
    required String direction,
    required String deviceId,
    required String target,
    required String status,
    int? recordsPushed,
    int? recordsCleaned,
    int? durationMs,
  }) async {
    await into(syncLogTable).insertOnConflictUpdate(SyncLogTableCompanion.insert(
      syncId: syncId,
      direction: direction,
      deviceId: deviceId,
      target: target,
      status: status,
      recordsPushed: Value(recordsPushed),
      recordsCleaned: Value(recordsCleaned),
      durationMs: Value(durationMs),
      createdAt: DateTime.now(),
    ));
  }
}

// ═══════════════════════════════════════════════════════════════
// 5. APPWRITE SERVICE (Mock)
class AppwriteService {
  static final AppwriteService _instance = AppwriteService._internal();
  factory AppwriteService() => _instance;
  AppwriteService._internal();
  
  Future<bool> sendRecord(OutboxTableData record) async {
    await Future.delayed(Duration(milliseconds: 500 + Random().nextInt(1000)));
    
    // Simulate network issues 5% of the time
    if (Random().nextDouble() < 0.05) {
      throw Exception('Network timeout');
    }
    
    debugPrint('✅ Synced record ${record.recordId} to Appwrite');
    return true;
  }
}

// ═══════════════════════════════════════════════════════════════
// 6. DELTA SYNC MANAGER
// ═══════════════════════════════════════════════════════════════

class AppwriteDeltaSync {
  static final AppwriteDeltaSync _instance = AppwriteDeltaSync._internal();
  factory AppwriteDeltaSync() => _instance;
  AppwriteDeltaSync._internal();

  AppwriteService? _appwriteService;
  AppDatabase? _database;
  bool _isInitialized = false;

  Future<void> initialize({
    required AppwriteService appwriteService,
    required AppDatabase database,
  }) async {
    _appwriteService = appwriteService;
    _database = database;
    _isInitialized = true;
  }

  Future<SyncResult> pushDeltaChanges() async {
    if (!_isInitialized) throw Exception('DeltaSync غير مُهيأ');
    
    final stopwatch = Stopwatch()..start();
    final outboxDao = OutboxDao(_database!);
    final syncLogDao = SyncLogDao(_database!);
    
    final pendingRecords = await outboxDao.getPendingRecords();
    List<String> syncedIds = [];

    for (final record in pendingRecords) {
      try {
        final success = await _appwriteService!.sendRecord(record);
        if (success) {
          syncedIds.add(record.recordId);
        }
      } catch (e) {
        debugPrint('❌ Failed to sync ${record.recordId}: $e');
        // Keep failed records for retry
        continue;
      }
    }

    final recordsCleaned = await outboxDao.clearSyncedRecords(syncedIds);
    
    stopwatch.stop();
    
    // Log sync operation
    final syncId = 'push_${DateTime.now().millisecondsSinceEpoch}';
    final deviceId = 'device_${Random().nextInt(10000)}';
    
    await syncLogDao.logSync(
      syncId: syncId,
      direction: 'push',
      deviceId: deviceId,
      target: 'Appwrite',
      status: 'success',
      recordsPushed: syncedIds.length,
      recordsCleaned: recordsCleaned,
      durationMs: stopwatch.elapsedMilliseconds,
    );

    return SyncResult(
      recordsPushed: syncedIds.length,
      recordsCleaned: recordsCleaned,
      syncedIds: syncedIds,
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 7. RIVERPOD PROVIDERS
// ═══════════════════════════════════════════════════════════════

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
final appwriteServiceProvider = Provider<AppwriteService>((ref) => AppwriteService());
final deltaSyncProvider = Provider<AppwriteDeltaSync>((ref) {
  final deltaSync = AppwriteDeltaSync();
  // Initialize on provider creation
  WidgetsBinding.instance.addPostFrameCallback((_) {
    deltaSync.initialize(
      appwriteService: ref.read(appwriteServiceProvider),
      database: ref.read(databaseProvider),
    );
  });
  return deltaSync;
});

final pendingChangesCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final outboxDao = OutboxDao(db);
  return outboxDao.getPendingCount();
});

// ═══════════════════════════════════════════════════════════════
// 8. MAIN WIDGET - DashboardSyncButton
// ═══════════════════════════════════════════════════════════════

class DashboardSyncButton extends ConsumerStatefulWidget {
  const DashboardSyncButton({super.key});

  @override
  ConsumerState<DashboardSyncButton> createState() => _DashboardSyncButtonState();
}

class _DashboardSyncButtonState extends ConsumerState<DashboardSyncButton>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  
  SyncStatus _syncStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  late AnimationController _animationController;
  late Animation<double> _rotationAnimation;
  Timer? _retryTimer;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    );
    _rotationAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    
    WidgetsBinding.instance.addObserver(this);
    _startAutoRetry();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _animationController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.refresh(pendingChangesCountProvider);
    }
  }

  void _startAutoRetry() {
    _retryTimer = Timer.periodic(Duration(minutes: 5), (timer) {
      if (_syncStatus == SyncStatus.idle) {
        _checkNetworkAndSync();
      }
    });
  }

  Future<void> _checkNetworkAndSync() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi)) {
      final pendingCount = ref.read(pendingChangesCountProvider).value ?? 0;
      if (pendingCount > 0) {
        _handlePush();
      }
    }
  }

  Future<void> _handlePush() async {
    final pendingCountAsync = ref.read(pendingChangesCountProvider);
    final pendingCount = pendingCountAsync.value ?? 0;
    
    if (pendingCount == 0 || _syncStatus != SyncStatus.idle) return;

    setState(() {
      _syncStatus = SyncStatus.pushing;
      _animationController.repeat();
    });

    try {
      final deltaSync = ref.read(deltaSyncProvider);
      final result = await deltaSync.pushDeltaChanges();

      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
          _syncStatus = SyncStatus.idle;
        });

        if (mounted) {
          _showSuccessSnackBar(result);
        }
      }
    } catch (e, stackTrace) {
      debugPrint('Sync failed: $e
$stackTrace');
      if (mounted) {
        _showErrorSnackBar(e.toString());
      }
      setState(() => _syncStatus = SyncStatus.idle);
    } finally {
      _animationController.stop();
      _animationController.reset();
    }
  }

  void _showSuccessSnackBar(SyncResult result) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.cloud_done, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Text(
                  '✅ تم المزامنة بنجاح!',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            SizedBox(height: 4),
            Text(
              '⬆️ ${result.recordsPushed} مرفوع | 🧹 ${result.recordsCleaned} محذوفة',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
        duration: Duration(seconds: 4),
      ),
    );
  }

  void _showErrorSnackBar(String error) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.white),
            SizedBox(width: 8),
            Expanded(child: Text('❌ خطأ: $error')),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        margin: EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pendingCountAsync = ref.watch(pendingChangesCountProvider);

    return Container(
      padding: EdgeInsets.all(16),
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 20,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 📊 Pending Count Badge
          pendingCountAsync.when(
            data: (count) => AnimatedContainer(
              duration: Duration(milliseconds: 400),
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: count > 0 
                    ? Color.lerp(Colors.orange.shade100, Colors.red.shade100, count / 50)
                    : Colors.green.shade100,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(
                  color: count > 0 ? Colors.orange.shade400 : Colors.green.shade400,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: (count > 0 ? Colors.orange : Colors.green).withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    count > 0 ? Icons.pending_outlined : Icons.verified,
                    color: count > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                    size: 20,
                  ),
                  SizedBox(width: 8),
                  Text(
                    count > 0 ? '$count قيد الانتظار' : '✅ محدّث',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: count > 0 ? Colors.orange.shade800 : Colors.green.shade800,
                    ),
                  ),
                  if (count > 0)
                    Container(
                      margin: EdgeInsets.only(left: 8),
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade200,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${(count / 1000).toStringAsFixed(1)}KB',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            loading: () => Container(
              height: 40,
              width: 140,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(25),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.grey),
                  ),
                  SizedBox(width: 12),
                  SizedBox(
                    width: 80,
                    height: 16,
                    child: LinearProgressIndicator(
                      backgroundColor: Colors.grey.shade300,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.grey),
                    ),
                  ),
                ],
              ),
            ),
            error: (error, stack) => Container(
              height: 40,
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.red.shade100,
                borderRadius: BorderRadius.circular(25),
                border: Border.all(color: Colors.red.shade400, width: 2),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: Colors.red.shade700, size: 20),
                  SizedBox(width: 8),
                  Text('خطأ في العداد', style: TextStyle(color: Colors.red.shade700)),
                ],
              ),
            ),
          ),
          
          SizedBox(height: 16),
          
          // 🔄 Sync Button
          GestureDetector(
            onTap: _syncStatus == SyncStatus.idle ? _handlePush : null,
            child: AnimatedBuilder(
              animation: Listenable.merge([_animationController, pendingCountAsync]),
              builder: (context, child) {
                final pendingCountAsyncValue = pendingCountAsync.valueOrNull ?? 0;
                return Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    gradient: _getButtonGradient(pendingCountAsyncValue),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _getButtonColor(pendingCountAsyncValue).withOpacity(0.4),
                        blurRadius: 25,
                        spreadRadius: 3,
                      ),
                      BoxShadow(
                        color: _getButtonColor(pendingCountAsyncValue).withOpacity(0.2),
                        blurRadius: 40,
                        spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      // Pulsing ring for pending items
                      if (pendingCountAsyncValue > 0)
                        AnimatedContainer(
                          duration: Duration(milliseconds: 1500),
                          width: _syncStatus == SyncStatus.pushing ? 0 : 76,
                          height: _syncStatus == SyncStatus.pushing ? 0 : 76,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.orange.withOpacity(0.6),
                              width: 3,
                            ),
                          ),
                        ),
                      
                      // Main icon
                      Transform.rotate(
                        angle: _syncStatus == SyncStatus.pushing 
                            ? _rotationAnimation.value * 2 * pi 
                            : 0,
                        child: Icon(
                          _syncStatus == SyncStatus.pushing 
                              ? Icons.sync 
                              : Icons.cloud_upload,
                          size: 32,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              color: Colors.black26,
                              blurRadius: 4,
                              offset: Offset(0, 2),
                            ),
                          ],
                        ),
                      ),
                      
                      // Success dot
                      if (_syncStatus == SyncStatus.pushing)
                        Positioned(
                          bottom: 6,
                          child: Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.white.withOpacity(0.5),
                                  blurRadius: 4,
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
          ),
          
          SizedBox(height: 12),
          
          // ⏰ Last Sync Time
          if (_lastSyncTime != null) ...[
            Text(
              'آخر تحديث: ${_formatRelativeTime(_lastSyncTime!)}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 4),
            Container(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.green.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _formatExactTime(_lastSyncTime!),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.green.shade800,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
          
          SizedBox(height: 8),
          
          // 📱 Auto-sync indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.autorenew, size: 14, color: Colors.grey.shade500),
              SizedBox(width: 4),
              Text(
                'مزامنة تلقائية كل 5د',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ],
          ),
        ],
      ),
    );
  }

  LinearGradient _getButtonGradient(int pendingCount) {
    if (_syncStatus == SyncStatus.pushing) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.blue.shade400,
          Colors.blue.shade600,
          Colors.indigo.shade700,
        ],
      );
    }
    
    if (pendingCount > 0) {
      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          Colors.orange.shade400,
          Colors.orange.shade500,
          Colors.deepOrange.shade600,
        ],
      );
    }
    
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Colors.green.shade400,
        Colors.green.shade500,
        Colors.teal.shade600,
      ],
    );
  }

  Color _getButtonColor(int pendingCount) {
    if (_syncStatus == SyncStatus.pushing) return Colors.blue.shade500;
    if (pendingCount > 0) return Colors.orange.shade500;
    return Colors.green.shade500;
  }

  String _formatRelativeTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inHours < 1) return 'منذ ${diff.inMinutes}د';
    if (diff.inDays < 1) return 'منذ ${diff.inHours}س';
    return 'منذ ${diff.inDays}ي';
  }

  String _formatExactTime(DateTime time) {
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }
}

// ═══════════════════════════════════════════════════════════════
// 9. USAGE EXAMPLE
// ═══════════════════════════════════════════════════════════════

class DashboardScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Your dashboard content...
            SizedBox(height: 24),
            
            // 🔥 The Sync Button
            DashboardSyncButton(),
            
            Spacer(),
          ],
        ),
      ),
    );
  }
}
