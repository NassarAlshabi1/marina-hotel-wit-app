import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'sync_orchestrator.dart';

/// مستمع حالة الشبكة - يراقب تغيرات الاتصال ويقوم بتشغيل المزامنة تلقائياً
class NetworkConnectivityListener {
  static NetworkConnectivityListener? _instance;
  static NetworkConnectivityListener get instance => _instance ??= NetworkConnectivityListener._();

  NetworkConnectivityListener._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _isInitialized = false;

  /// بدء مراقبة حالة الشبكة
  void startMonitoring() {
    if (_isInitialized) return;

    _subscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      _handleConnectivityChange(results);
    });

    _isInitialized = true;
  }

  /// معالجة تغير حالة الاتصال
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    // التحقق مما إذا كان هناك أي نوع من الاتصال المتاح (WiFi, Mobile, Ethernet)
    final hasConnection = results.any((result) => 
      result == ConnectivityResult.mobile || 
      result == ConnectivityResult.wifi || 
      result == ConnectivityResult.ethernet ||
      result == ConnectivityResult.vpn
    );

    if (hasConnection) {
      // تشغيل المزامنة تلقائياً عند توفر الاتصال
      SyncOrchestrator.instance.syncNow(
        priority: SyncPriority.high,
        reason: 'Network restored',
      );
    }
  }

  /// إيقاف المراقبة
  void stopMonitoring() {
    _subscription?.cancel();
    _subscription = null;
    _isInitialized = false;
  }
}
