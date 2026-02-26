import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../services/local_db.dart';
import '../services/daos/outbox_dao.dart';
import '../services/appwrite_service.dart';
import '../services/appwrite_delta_sync.dart';

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
// 2. PROVIDERS
// ═══════════════════════════════════════════════════════════════

final databaseProvider = Provider<AppDatabase>((ref) => AppDatabase());
final appwriteServiceProvider = Provider<AppwriteService>((ref) => AppwriteService());
final deltaSyncProvider = Provider<AppwriteDeltaSync>((ref) {
  final deltaSync = AppwriteDeltaSync.instance;
  // Initialize on provider creation
  WidgetsBinding.instance.addPostFrameCallback((_) {
    deltaSync.initialize(
      ref.read(appwriteServiceProvider),
      ref.read(databaseProvider),
    );
  });
  return deltaSync;
});

final pendingChangesCountProvider = FutureProvider<int>((ref) async {
  final db = ref.watch(databaseProvider);
  final outboxDao = OutboxDao(db);
  return outboxDao.count();
});

// ═══════════════════════════════════════════════════════════════
// 3. MAIN WIDGET - DashboardSyncButton
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
  Timer? _pendingChangesTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    
    _rotationAnimation = Tween<double>(begin: 0, end: 2 * pi).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.linear),
    );

    // مؤقت للتحديث الدوري
    _pendingChangesTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && _syncStatus == SyncStatus.idle) {
        ref.invalidate(pendingChangesCountProvider);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _animationController.dispose();
    _pendingChangesTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleSync() async {
    if (_syncStatus != SyncStatus.idle) return;

    setState(() {
      _syncStatus = SyncStatus.pushing;
      _animationController.repeat();
    });

    try {
      final deltaSync = ref.read(deltaSyncProvider);
      
      if (!deltaSync.isInitialized) {
        await deltaSync.initialize(
          ref.read(appwriteServiceProvider),
          ref.read(databaseProvider),
        );
      }

      final result = await deltaSync.pushDeltaChanges();

      if (mounted) {
        setState(() {
          _lastSyncTime = DateTime.now();
          _syncStatus = SyncStatus.idle;
          _animationController.stop();
          _animationController.reset();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  result.success ? Icons.check_circle : Icons.warning,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    result.success 
                      ? '✅ تم رفع ${result.recordsPushed} تغيير بنجاح!'
                      : '⚠️ ${result.message}',
                  ),
                ),
              ],
            ),
            backgroundColor: result.success ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 3),
          ),
        );
        
        ref.invalidate(pendingChangesCountProvider);
      }
    } catch (e) {
      debugPrint('❌ خطأ في المزامنة: $e');
      if (mounted) {
        setState(() {
          _syncStatus = SyncStatus.idle;
          _animationController.stop();
          _animationController.reset();
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ فشل المزامنة: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  String _formatLastSyncTime(DateTime? time) {
    if (time == null) return 'لم يتم المزامنة بعد';
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'الآن';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  @override
  Widget build(BuildContext context) {
    final pendingCountAsync = ref.watch(pendingChangesCountProvider);
    final pendingCount = pendingCountAsync.value ?? 0;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _handleSync,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: _syncStatus == SyncStatus.pushing 
                  ? Colors.blue.shade100 
                  : (pendingCount > 0 ? Colors.orange.shade100 : Colors.green.shade100),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _syncStatus == SyncStatus.pushing 
                    ? Colors.blue 
                    : (pendingCount > 0 ? Colors.orange : Colors.green),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedBuilder(
                  animation: _rotationAnimation,
                  builder: (context, child) {
                    return Transform.rotate(
                      angle: _syncStatus == SyncStatus.pushing ? _rotationAnimation.value : 0,
                      child: Icon(
                        _syncStatus == SyncStatus.pushing ? Icons.sync : Icons.cloud_upload,
                        size: 20,
                        color: _syncStatus == SyncStatus.pushing 
                            ? Colors.blue 
                            : (pendingCount > 0 ? Colors.orange : Colors.green),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 8),
                Text(
                  _syncStatus == SyncStatus.pushing 
                      ? 'جاري المزامنة...' 
                      : (pendingCount > 0 ? '$pendingCount تغيير معلق' : 'محدّث'),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: _syncStatus == SyncStatus.pushing 
                        ? Colors.blue.shade900 
                        : (pendingCount > 0 ? Colors.orange.shade900 : Colors.green.shade900),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _formatLastSyncTime(_lastSyncTime),
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
      ],
    );
  }
}
