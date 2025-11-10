import 'package:flutter/foundation.dart';
import '../utils/env.dart';
import '../utils/ditto_config.dart';

/// نسخة مبسطة من خدمة Ditto بعد إزالة التكامل الفعلي.
/// تحافظ هذه الخدمة على نفس الواجهة المطلوبة من بقية التطبيق
/// ولكنها لا تقوم بأي عمليات مزامنة حقيقية. الهدف هو إبقاء التطبيق
/// قابلاً للبناء والتشغيل بدون الاعتماد على حزمة Ditto SDK.
class DittoCloudSyncService {
  static final DittoCloudSyncService _instance = DittoCloudSyncService._internal();
  factory DittoCloudSyncService() => _instance;
  DittoCloudSyncService._internal();

  bool _isInitialized = false;
  bool _isSyncing = false;
  String _lastError = '';
  int _peersCount = 0;

  bool get isConnected => _isInitialized;
  bool get isSyncing => _isSyncing;
  String get lastError => _lastError;
  int get peersCount => _peersCount;

  Future<bool> initialize() async {
    debugPrint('⚠️ تم استبدال تكامل Ditto ببديل مبسط. لا تتم أي مزامنة فعلية.');
    _isInitialized = true;
    _isSyncing = false;
    _lastError = '';
    _peersCount = 0;
    return true;
  }

  Future<void> dispose() async {
    _isInitialized = false;
    _isSyncing = false;
    _peersCount = 0;
  }

  Future<bool> startSync() async {
    if (!_isInitialized) {
      _lastError = 'Ditto غير مهيء';
      return false;
    }
    _isSyncing = true;
    return true;
  }

  Future<void> stopSync() async {
    _isSyncing = false;
  }

  Future<Map<String, dynamic>> checkConnectionStatus() async {
    return {
      'isConnected': _isInitialized,
      'peersCount': _peersCount,
      'lastSyncTime': null,
      'syncEnabled': _isSyncing,
      'error': _lastError.isEmpty ? null : _lastError,
      'appId': Env.dittoAppId,
      'mode': Env.dittoUsePlayground ? 'Playground' : 'Production',
    };
  }

  Future<Map<String, int>> getBookingsStats() async => {};

  Future<List<Map<String, dynamic>>> getRoomsStatus() async => [];

  Future<List<Map<String, dynamic>>> getHighValueBookings({required double minAmount}) async => [];

  Stream<List<Map<String, dynamic>>> watchLiveBookings() async* {
    yield const [];
  }

  Future<bool> syncNow() async {
    if (!_isInitialized) {
      _lastError = 'Ditto غير مهيء';
      return false;
    }
    return true;
  }

  Future<Map<String, dynamic>> getDeviceInfo() async {
    return {
      'deviceName': 'Ditto Stub Device',
      'peersCount': _peersCount,
      'isSyncing': _isSyncing,
      'appId': Env.dittoAppId,
      'mode': Env.dittoUsePlayground ? 'Playground' : 'Production',
    };
  }

  Future<bool> clearAllData() async => _isInitialized;

  void clearError() {
    _lastError = '';
  }
}
