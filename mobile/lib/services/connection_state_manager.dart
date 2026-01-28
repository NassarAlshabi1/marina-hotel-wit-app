import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'appwrite_service.dart';
import 'appwrite_logger.dart';

/// حالة الاتصال
enum ConnectionStatus {
  online,
  offline,
  checking,
  unknown,
}

/// مدير حالة الاتصال مع Appwrite
///
/// يتتبع حالة الاتصال بالإنترنت و Appwrite Server
/// ويوفر stream للاستماع للتغييرات
class ConnectionStateManager extends ChangeNotifier {
  static final ConnectionStateManager _instance = ConnectionStateManager._internal();
  factory ConnectionStateManager() => _instance;
  ConnectionStateManager._internal();

  final _logger = AppwriteLogger();
  final _connectivity = Connectivity();
  
  ConnectionStatus _status = ConnectionStatus.unknown;
  DateTime? _lastCheckTime;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  Timer? _periodicCheckTimer;
  
  // Stream controller للبث
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  
  /// الحالة الحالية للاتصال
  ConnectionStatus get status => _status;
  
  /// هل الجهاز متصل؟
  bool get isOnline => _status == ConnectionStatus.online;
  
  /// هل الجهاز غير متصل؟
  bool get isOffline => _status == ConnectionStatus.offline;
  
  /// هل يتم فحص الاتصال؟
  bool get isChecking => _status == ConnectionStatus.checking;
  
  /// آخر وقت تم فيه الفحص
  DateTime? get lastCheckTime => _lastCheckTime;
  
  /// Stream لحالة الاتصال
  Stream<ConnectionStatus> get statusStream => _statusController.stream;

  /// تهيئة المدير
  Future<void> init() async {
    if (_connectivitySubscription != null) {
      _logger.debug('ConnectionStateManager already initialized', tag: 'CONNECTION');
      return;
    }

    _logger.info('Initializing ConnectionStateManager', tag: 'CONNECTION');
    
    // الاستماع لتغييرات الشبكة
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (error) {
        _logger.error('Connectivity stream error', error: error, tag: 'CONNECTION');
      },
    );
    
    // فحص دوري كل 30 ثانية
    _periodicCheckTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => checkConnection(),
    );
    
    // فحص أولي
    await checkConnection();
  }

  /// معالج تغييرات الاتصال
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _logger.debug('Connectivity changed: $results', tag: 'CONNECTION');
    
    // إذا لا يوجد اتصال على الإطلاق
    if (results.isEmpty || results.every((r) => r == ConnectivityResult.none)) {
      _updateStatus(ConnectionStatus.offline);
      return;
    }
    
    // يوجد اتصال - فحص Appwrite
    checkConnection();
  }

  /// فحص حالة الاتصال
  Future<void> checkConnection() async {
    if (_status == ConnectionStatus.checking) {
      _logger.debug('Connection check already in progress', tag: 'CONNECTION');
      return;
    }
    
    _updateStatus(ConnectionStatus.checking);
    
    try {
      // محاولة طلب بسيط للتحقق من Appwrite
      final appwriteService = AppwriteService();
      await appwriteService.quickConnectionTest();
      
      _updateStatus(ConnectionStatus.online);
      _lastCheckTime = DateTime.now();
    } catch (e) {
      _logger.warning('Connection check failed', error: e, tag: 'CONNECTION');
      _updateStatus(ConnectionStatus.offline);
      _lastCheckTime = DateTime.now();
    }
  }

  /// تحديث حالة الاتصال
  void _updateStatus(ConnectionStatus newStatus) {
    if (_status != newStatus) {
      final oldStatus = _status;
      _status = newStatus;
      
      _logger.info(
        'Connection status changed: $oldStatus -> $newStatus',
        tag: 'CONNECTION',
      );
      
      // إشعار المستمعين
      notifyListeners();
      _statusController.add(newStatus);
    }
  }

  /// فرض تحديث الحالة (للاستخدام الداخلي)
  void forceStatus(ConnectionStatus status) {
    _updateStatus(status);
  }

  /// الحصول على رسالة حالة مناسبة للعرض
  String getStatusMessage() {
    switch (_status) {
      case ConnectionStatus.online:
        return 'متصل';
      case ConnectionStatus.offline:
        return 'غير متصل';
      case ConnectionStatus.checking:
        return 'جاري الفحص...';
      case ConnectionStatus.unknown:
        return 'غير معروف';
    }
  }

  /// الحصول على أيقونة حالة مناسبة
  String getStatusIcon() {
    switch (_status) {
      case ConnectionStatus.online:
        return '✓';
      case ConnectionStatus.offline:
        return '✗';
      case ConnectionStatus.checking:
        return '⟳';
      case ConnectionStatus.unknown:
        return '?';
    }
  }

  /// إحصائيات الاتصال
  Map<String, dynamic> getStatistics() {
    return {
      'current_status': _status.toString(),
      'is_online': isOnline,
      'last_check': _lastCheckTime?.toIso8601String(),
    };
  }

  /// إعادة تعيين المدير
  void reset() {
    _status = ConnectionStatus.unknown;
    _lastCheckTime = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _logger.info('Disposing ConnectionStateManager', tag: 'CONNECTION');
    _connectivitySubscription?.cancel();
    _periodicCheckTimer?.cancel();
    _statusController.close();
    super.dispose();
  }
}
