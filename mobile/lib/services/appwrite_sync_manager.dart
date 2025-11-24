import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'appwrite_service.dart';
import 'appwrite_logger.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_models.dart';
import 'appwrite_config.dart';

/// حالة المزامنة
enum SyncStatus {
  idle,
  syncing,
  success,
  failed,
  partial,
}

/// نتيجة المزامنة
class SyncResult {
  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;

  SyncResult({
    required this.status,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
    required this.timestamp,
    required this.duration,
  });

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
}

/// مدير المزامنة الثنائية
class AppwriteSyncManager {
  final AppwriteService appwriteService;
  
  AppwriteSyncManager({required this.appwriteService});

  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();
  
  Timer? _syncTimer;
  SyncStatus _currentStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _currentDeviceId;
  
  final _syncController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncController.stream;

  /// تهيئة المزامنة
  Future<void> initialize() async {
    try {
      await appwriteService.initialize();
      await _loadSettings();
      _logger.info('Sync manager initialized', tag: 'SYNC');
    } catch (e, stackTrace) {
      _logger.error('Failed to initialize sync manager', 
        error: e, 
        stackTrace: stackTrace, 
        tag: 'SYNC'
      );
    }
  }

  /// تحميل الإعدادات
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentDeviceId = prefs.getString('appwrite_device_id');
    _lastSyncTime = prefs.getInt('appwrite_last_sync_time') != null
        ? DateTime.fromMillisecondsSinceEpoch(prefs.getInt('appwrite_last_sync_time')!)
        : null;
  }

  /// حفظ الإعدادات
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentDeviceId != null) {
      await prefs.setString('appwrite_device_id', _currentDeviceId!);
    }
    if (_lastSyncTime != null) {
      await prefs.setInt('appwrite_last_sync_time', _lastSyncTime!.millisecondsSinceEpoch);
    }
  }

  /// تسجيل الجهاز
  Future<String> registerDevice({
    required String deviceName,
    required String deviceModel,
    required String osVersion,
  }) async {
    try {
      _logger.info('Registering device: $deviceName', tag: 'SYNC');

      if (_currentDeviceId != null) {
        // تحديث معلومات الجهاز الحالي
        await appwriteService.updateDocument(
          collectionId: AppwriteConfig.devicesCollectionId,
          documentId: _currentDeviceId!,
          data: {
            'deviceName': deviceName,
            'deviceModel': deviceModel,
            'osVersion': osVersion,
            'lastSeen': DateTime.now().toIso8601String(),
            'status': 'active',
          },
        );
        _logger.info('Device updated: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      } else {
        // إنشاء جهاز جديد
        final device = await appwriteService.createDevice({
          'deviceName': deviceName,
          'deviceModel': deviceModel,
          'osVersion': osVersion,
          'lastSeen': DateTime.now().toIso8601String(),
          'status': 'active',
          'createdAt': DateTime.now().toIso8601String(),
        });
        
        _currentDeviceId = device.$id;
        await _saveSettings();
        
        _logger.info('Device registered: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      }
    } catch (e, stackTrace) {
      _logger.error('Failed to register device', 
        error: e, 
        stackTrace: stackTrace, 
        tag: 'SYNC'
      );
      rethrow;
    }
  }

  /// بدء المزامنة التلقائية
  void startAutoSync({Duration interval = const Duration(minutes: 15)}) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (timer) async {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool('appwrite_sync_enabled') ?? false;
      
      if (enabled) {
        await sync();
      }
    });
    _logger.info('Auto sync started (interval: ${interval.inMinutes} min)', tag: 'SYNC');
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _logger.info('Auto sync stopped', tag: 'SYNC');
  }

  /// تنفيذ المزامنة
  Future<SyncResult> sync() async {
    if (_currentStatus == SyncStatus.syncing) {
      _logger.warning('Sync already in progress', tag: 'SYNC');
      return SyncResult(
        status: SyncStatus.failed,
        errorMessage: 'Sync already in progress',
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
    }

    _currentStatus = SyncStatus.syncing;
    _syncController.add(_currentStatus);
    
    final startTime = DateTime.now();
    int recordsPushed = 0;
    int recordsPulled = 0;
    int conflicts = 0;
    String? errorMessage;
    SyncStatus finalStatus = SyncStatus.success;

    try {
      _logger.info('Starting sync...', tag: 'SYNC');

      // التحقق من الاتصال
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        throw Exception('No internet connection');
      }

      // إنشاء سجل مزامنة
      final syncLog = await appwriteService.createSyncLog({
        'deviceId': _currentDeviceId ?? 'unknown',
        'syncType': 'full',
        'startTime': startTime.toIso8601String(),
        'status': 'in_progress',
        'recordsPushed': 0,
        'recordsPulled': 0,
        'conflicts': 0,
      });

      // محاكاة عمليات المزامنة (يمكن تطويرها لاحقاً)
      // TODO: دمج مع قاعدة البيانات المحلية (Drift)
      
      // مزامنة الغرف
      final rooms = await appwriteService.listRooms(useCache: false);
      recordsPulled += rooms.length;
      _logger.debug('Synced ${rooms.length} rooms', tag: 'SYNC');

      // مزامنة الحجوزات
      final bookings = await appwriteService.listBookings(useCache: false);
      recordsPulled += bookings.length;
      _logger.debug('Synced ${bookings.length} bookings', tag: 'SYNC');

      // تحديث سجل المزامنة
      await appwriteService.updateDocument(
        collectionId: AppwriteConfig.syncLogsCollectionId,
        documentId: syncLog.$id,
        data: {
          'endTime': DateTime.now().toIso8601String(),
          'status': 'completed',
          'recordsPushed': recordsPushed,
          'recordsPulled': recordsPulled,
          'conflicts': conflicts,
        },
      );

      _lastSyncTime = DateTime.now();
      await _saveSettings();

      _logger.info('Sync completed successfully (pushed: $recordsPushed, pulled: $recordsPulled)', 
        tag: 'SYNC'
      );

    } catch (e, stackTrace) {
      errorMessage = e.toString();
      finalStatus = SyncStatus.failed;
      
      _errorHandler.handleError(e, 
        context: 'sync()', 
        stackTrace: stackTrace
      );
      
      _logger.error('Sync failed', error: e, stackTrace: stackTrace, tag: 'SYNC');
    }

    _currentStatus = finalStatus;
    _syncController.add(_currentStatus);

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    return SyncResult(
      status: finalStatus,
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      conflicts: conflicts,
      errorMessage: errorMessage,
      timestamp: endTime,
      duration: duration,
    );
  }

  /// الحصول على إحصائيات المزامنة
  Future<Map<String, dynamic>> getSyncStatistics() async {
    try {
      final syncLogs = await appwriteService.listSyncLogs(useCache: false);
      
      int totalSyncs = syncLogs.length;
      int successfulSyncs = syncLogs.where((log) => 
        log.data['status'] == 'completed'
      ).length;
      int failedSyncs = syncLogs.where((log) => 
        log.data['status'] == 'failed'
      ).length;
      
      int totalRecordsPushed = syncLogs.fold<int>(0, (sum, log) => 
        sum + (log.data['recordsPushed'] ?? 0) as int
      );
      int totalRecordsPulled = syncLogs.fold<int>(0, (sum, log) => 
        sum + (log.data['recordsPulled'] ?? 0) as int
      );
      int totalConflicts = syncLogs.fold<int>(0, (sum, log) => 
        sum + (log.data['conflicts'] ?? 0) as int
      );

      return {
        'totalSyncs': totalSyncs,
        'successfulSyncs': successfulSyncs,
        'failedSyncs': failedSyncs,
        'successRate': totalSyncs > 0 ? (successfulSyncs / totalSyncs * 100) : 0.0,
        'totalRecordsPushed': totalRecordsPushed,
        'totalRecordsPulled': totalRecordsPulled,
        'totalConflicts': totalConflicts,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
      };
    } catch (e) {
      _logger.error('Failed to get sync statistics', error: e, tag: 'SYNC');
      return {
        'totalSyncs': 0,
        'successfulSyncs': 0,
        'failedSyncs': 0,
        'successRate': 0.0,
        'totalRecordsPushed': 0,
        'totalRecordsPulled': 0,
        'totalConflicts': 0,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
      };
    }
  }

  /// الحصول على قائمة الأجهزة المسجلة
  Future<List<AppwriteDevice>> getRegisteredDevices() async {
    try {
      final devices = await appwriteService.listDevices(useCache: false);
      return devices.map((doc) => AppwriteDevice.fromJson(doc.data)).toList();
    } catch (e) {
      _logger.error('Failed to get registered devices', error: e, tag: 'SYNC');
      return [];
    }
  }

  /// رفع جميع البيانات المحلية
  Future<void> pushAllLocalData() async {
    _logger.info('Pushing all local data...', tag: 'SYNC');
    // TODO: تنفيذ رفع البيانات من قاعدة البيانات المحلية
    throw UnimplementedError('Push all local data not implemented yet');
  }

  /// تحميل جميع البيانات من الخادم
  Future<void> pullAllRemoteData() async {
    _logger.info('Pulling all remote data...', tag: 'SYNC');
    // TODO: تنفيذ تحميل البيانات وحفظها في قاعدة البيانات المحلية
    throw UnimplementedError('Pull all remote data not implemented yet');
  }

  /// إعادة تعيين حالة المزامنة
  Future<void> resetSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('appwrite_last_sync_time');
    _lastSyncTime = null;
    _logger.info('Sync state reset', tag: 'SYNC');
  }

  // Getters
  SyncStatus get currentStatus => _currentStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get currentDeviceId => _currentDeviceId;
  bool get isSyncing => _currentStatus == SyncStatus.syncing;

  /// التخلص من الموارد
  void dispose() {
    stopAutoSync();
    _syncController.close();
  }
}
