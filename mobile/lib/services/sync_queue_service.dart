import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'google_drive_auto_sync_engine.dart';
import 'smart_sync_manager.dart';
import 'sync_locks.dart';

class SyncQueueItem {
  final String id;
  final String screenId;
  final Map<String, dynamic> data;
  final DateTime createdAt;
  int attempts;
  
  SyncQueueItem({
    required this.id,
    required this.screenId,
    required this.data,
    required this.createdAt,
    this.attempts = 0,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'screenId': screenId,
    'data': data,
    'createdAt': createdAt.toIso8601String(),
    'attempts': attempts,
  };
  
  factory SyncQueueItem.fromJson(Map<String, dynamic> json) => SyncQueueItem(
    id: json['id'],
    screenId: json['screenId'],
    data: json['data'],
    createdAt: DateTime.parse(json['createdAt']),
    attempts: json['attempts'] ?? 0,
  );
}

class SyncQueueService {
  static SyncQueueService? _instance;
  static SyncQueueService get instance => _instance ??= SyncQueueService._();
  
  SyncQueueService._();
  
  static const String _queueKey = 'sync_queue_items';
  static const Duration _retryInterval = Duration(minutes: 2);
  
  Timer? _processingTimer;
  bool _isProcessing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  StreamSubscription<AutoSyncEngineState>? _driveStateSubscription;
  bool _driveOnline = false;
  bool _initialized = false;
  
  final _queueController = StreamController<int>.broadcast();
  Stream<int> get queueCountStream => _queueController.stream;
  
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        debugPrint('🌐 [SyncQueue] الإنترنت متصل - معالجة الطابور...');
        processQueue();
      }
    });
    
    _setupDriveStateListener();
    
    _processingTimer = Timer.periodic(_retryInterval, (_) => processQueue());
    
    await processQueue();
    
    debugPrint('✅ [SyncQueue] تم تهيئة خدمة طابور المزامنة');
  }
  
  Future<bool> hasInternetConnection() async {
    final results = await Connectivity().checkConnectivity();
    return results.any((r) => r != ConnectivityResult.none);
  }
  
  Future<void> addToQueue({
    required String screenId,
    required Map<String, dynamic> data,
  }) async {
    final item = SyncQueueItem(
      id: '${screenId}_${DateTime.now().millisecondsSinceEpoch}',
      screenId: screenId,
      data: data,
      createdAt: DateTime.now(),
    );
    
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    queueJson.add(jsonEncode(item.toJson()));
    await prefs.setStringList(_queueKey, queueJson);
    
    _emitQueueCount();
    debugPrint('📥 [SyncQueue] تمت إضافة عنصر من $screenId للطابور');
  }
  
  Future<List<SyncQueueItem>> getQueueItems() async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    return queueJson.map((json) => SyncQueueItem.fromJson(jsonDecode(json))).toList();
  }
  
  Future<void> removeFromQueue(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    queueJson.removeWhere((json) {
      final item = jsonDecode(json);
      return item['id'] == itemId;
    });
    await prefs.setStringList(_queueKey, queueJson);
    _emitQueueCount();
  }
  
  Future<void> updateQueueItem(SyncQueueItem item) async {
    final prefs = await SharedPreferences.getInstance();
    final queueJson = prefs.getStringList(_queueKey) ?? [];
    final index = queueJson.indexWhere((json) {
      final parsed = jsonDecode(json);
      return parsed['id'] == item.id;
    });
    if (index != -1) {
      queueJson[index] = jsonEncode(item.toJson());
      await prefs.setStringList(_queueKey, queueJson);
    }
  }
  
  Future<void> processQueue() async {
    final canStart = await SyncLocks.queueLock.synchronized(() async {
      if (_isProcessing) return false;
      _isProcessing = true;
      return true;
    });
    
    if (!canStart) return;
    
    final hasConnection = await hasInternetConnection();
    if (!hasConnection) {
      await SyncLocks.queueLock.synchronized(() async {
        _isProcessing = false;
      });
      debugPrint('📴 [SyncQueue] لا يوجد اتصال - تأجيل المعالجة');
      return;
    }

    final driveOnline = await _ensureDriveOnline();
    if (!driveOnline) {
      await SyncLocks.queueLock.synchronized(() async {
        _isProcessing = false;
      });
      debugPrint('🔒 [SyncQueue] Google Drive غير جاهز - الانتظار');
      return;
    }

    final items = await getQueueItems();
    if (items.isEmpty) {
      await SyncLocks.queueLock.synchronized(() async {
        _isProcessing = false;
      });
      debugPrint('✓ [SyncQueue] الطابور فارغ');
      return;
    }

    try {
      debugPrint('🔄 [SyncQueue] معالجة ${items.length} عنصر...');
      
      final itemsToProcess = List<SyncQueueItem>.from(items);
      
      try {
        final success = await SmartSyncManager.instance.pushLocalChanges();
        
        if (success) {
          for (final item in itemsToProcess) {
            await removeFromQueue(item.id);
          }
          debugPrint('✅ [SyncQueue] تم رفع جميع العناصر بنجاح (${itemsToProcess.length} عنصر)');
        } else {
          for (final item in itemsToProcess) {
            item.attempts++;
            await updateQueueItem(item);
          }
          debugPrint('⚠️ [SyncQueue] فشل الرفع - تحديث محاولات ${itemsToProcess.length} عنصر');
        }
      } catch (e) {
        for (final item in itemsToProcess) {
          item.attempts++;
          await updateQueueItem(item);
        }
        debugPrint('❌ [SyncQueue] خطأ في المزامنة: $e');
      }
    } finally {
      await SyncLocks.queueLock.synchronized(() async {
        _isProcessing = false;
      });
      _emitQueueCount();
    }
  }
  
  Future<int> getQueueCount() async {
    final items = await getQueueItems();
    return items.length;
  }
  
  void _emitQueueCount() async {
    final count = await getQueueCount();
    _queueController.add(count);
  }
  
  Future<bool> _ensureDriveOnline() async {
    if (_driveOnline) {
      return true;
    }
    
    final engine = AutoSyncEngine.instance;
    if (_isDriveStateOnline(engine.currentState)) {
      _driveOnline = true;
      return true;
    }
    
    if (!SmartSyncManager.instance.isDriveSignedIn) {
      debugPrint('🔓 [SyncQueue] Google Drive غير مسجل الدخول - لا يمكن رفع الطابور');
      return false;
    }
    
    // في حال كان المحرك لم يحدّث حالته بعد ولكن المستخدم مسجل والدخول متاح
    return true;
  }
  
  void _setupDriveStateListener() {
    _driveStateSubscription?.cancel();
    final engine = AutoSyncEngine.instance;
    _driveOnline = _isDriveStateOnline(engine.currentState);
    _driveStateSubscription = engine.stateStream.listen((state) {
      final online = _isDriveStateOnline(state);
      if (online && !_driveOnline) {
        _driveOnline = true;
        debugPrint('🌐 [SyncQueue] Google Drive متصل - تشغيل الطابور');
        processQueue();
      } else if (!online && _driveOnline) {
        _driveOnline = false;
        debugPrint('📴 [SyncQueue] Google Drive غير متصل - الانتظار');
      } else {
        _driveOnline = online;
      }
    });
  }
  
  bool _isDriveStateOnline(AutoSyncEngineState state) {
    return state.isSignedIn && state.hasNetworkConnection;
  }
  
  void dispose() {
    _processingTimer?.cancel();
    _connectivitySubscription?.cancel();
    _driveStateSubscription?.cancel();
    _queueController.close();
    _initialized = false;
  }
}
