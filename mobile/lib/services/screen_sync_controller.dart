import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'smart_sync_manager.dart';
import 'sync_queue_service.dart';

class ScreenSyncController {
  final String screenId;
  final Duration debounceDelay;
  
  ScreenSyncController({
    required this.screenId,
    this.debounceDelay = const Duration(seconds: 15),
  });
  
  bool _hasChanges = false;
  Timer? _debounceTimer;
  bool _isSyncing = false;
  
  final _syncStatusController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncStatusController.stream;
  
  bool get hasChanges => _hasChanges;
  bool get isSyncing => _isSyncing;
  
  void markChanged() {
    _hasChanges = true;
    _emitStatus(SyncStatus.pending);
    _resetDebounceTimer();
    debugPrint('📝 [$screenId] تم تسجيل تغيير - إعادة ضبط المؤقت');
  }
  
  void _resetDebounceTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounceDelay, () {
      debugPrint('⏰ [$screenId] انتهى المؤقت - بدء المزامنة التلقائية');
      syncNow();
    });
  }
  
  void cancelTimer() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
  }
  
  Future<bool> syncNow() async {
    if (!_hasChanges) {
      debugPrint('✓ [$screenId] لا توجد تغييرات للمزامنة');
      return true;
    }
    
    if (_isSyncing) {
      debugPrint('⏳ [$screenId] المزامنة جارية بالفعل');
      return false;
    }
    
    cancelTimer();
    _isSyncing = true;
    _emitStatus(SyncStatus.syncing);
    
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      final hasConnection = connectivityResults.any((r) => r != ConnectivityResult.none);
      
      if (hasConnection) {
        debugPrint('🌐 [$screenId] الإنترنت متصل - رفع مباشر...');
        final success = await SmartSyncManager.instance.pushLocalChanges();
        
        if (success) {
          _hasChanges = false;
          _emitStatus(SyncStatus.synced);
          debugPrint('✅ [$screenId] تمت المزامنة بنجاح');
          return true;
        } else {
          debugPrint('⚠️ [$screenId] فشل الرفع - إضافة للطابور');
          await _addToQueue();
          return false;
        }
      } else {
        debugPrint('📴 [$screenId] لا يوجد اتصال - إضافة للطابور');
        await _addToQueue();
        return false;
      }
    } catch (e) {
      debugPrint('❌ [$screenId] خطأ في المزامنة: $e');
      await _addToQueue();
      return false;
    } finally {
      _isSyncing = false;
    }
  }
  
  Future<void> _addToQueue() async {
    await SyncQueueService.instance.addToQueue(
      screenId: screenId,
      data: {'timestamp': DateTime.now().toIso8601String()},
    );
    _hasChanges = false;
    _emitStatus(SyncStatus.queued);
  }
  
  void _emitStatus(SyncStatus status) {
    _syncStatusController.add(status);
  }
  
  Future<bool> syncOnExit() async {
    debugPrint('🚪 [$screenId] الخروج من الشاشة...');
    cancelTimer();
    return await syncNow();
  }
  
  void dispose() {
    cancelTimer();
    syncOnExit().whenComplete(() {
      if (!_syncStatusController.isClosed) {
        _syncStatusController.close();
      }
    });
  }
}

enum SyncStatus {
  idle,
  pending,
  syncing,
  synced,
  queued,
  error,
}
