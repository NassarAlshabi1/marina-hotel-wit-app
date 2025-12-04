import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'smart_sync_manager.dart';

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
  static const int _maxAttempts = 5;
  static const Duration _retryInterval = Duration(minutes: 2);
  
  Timer? _processingTimer;
  bool _isProcessing = false;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  
  final _queueController = StreamController<int>.broadcast();
  Stream<int> get queueCountStream => _queueController.stream;
  
  Future<void> initialize() async {
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (hasConnection) {
        debugPrint('🌐 [SyncQueue] الإنترنت متصل - معالجة الطابور...');
        processQueue();
      }
    });
    
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
    if (_isProcessing) return;
    
    final hasConnection = await hasInternetConnection();
    if (!hasConnection) {
      debugPrint('📴 [SyncQueue] لا يوجد اتصال - تأجيل المعالجة');
      return;
    }
    
    _isProcessing = true;
    
    try {
      final items = await getQueueItems();
      if (items.isEmpty) {
        debugPrint('✓ [SyncQueue] الطابور فارغ');
        return;
      }
      
      debugPrint('🔄 [SyncQueue] معالجة ${items.length} عنصر...');
      
      for (final item in items) {
        if (item.attempts >= _maxAttempts) {
          debugPrint('⚠️ [SyncQueue] تجاوز الحد الأقصى للمحاولات: ${item.id}');
          await removeFromQueue(item.id);
          continue;
        }
        
        try {
          final success = await SmartSyncManager.instance.pushLocalChanges();
          
          if (success) {
            await removeFromQueue(item.id);
            debugPrint('✅ [SyncQueue] تم رفع ${item.screenId} بنجاح');
          } else {
            item.attempts++;
            await updateQueueItem(item);
            debugPrint('⚠️ [SyncQueue] فشل رفع ${item.screenId} - المحاولة ${item.attempts}');
          }
        } catch (e) {
          item.attempts++;
          await updateQueueItem(item);
          debugPrint('❌ [SyncQueue] خطأ في رفع ${item.screenId}: $e');
        }
      }
    } finally {
      _isProcessing = false;
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
  
  void dispose() {
    _processingTimer?.cancel();
    _connectivitySubscription?.cancel();
    _queueController.close();
  }
}
