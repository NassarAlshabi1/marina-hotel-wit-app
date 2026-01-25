import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

enum ConnectionType {
  none,
  wifi,
  mobile,
  ethernet,
  vpn,
  bluetooth,
  other,
}

class ConnectionStatus {
  final bool isOnline;
  final ConnectionType type;
  final DateTime timestamp;

  const ConnectionStatus({
    required this.isOnline,
    required this.type,
    required this.timestamp,
  });

  factory ConnectionStatus.offline() => ConnectionStatus(
        isOnline: false,
        type: ConnectionType.none,
        timestamp: DateTime.now(),
      );

  factory ConnectionStatus.fromConnectivityResult(
      List<ConnectivityResult> results) {
    final isOnline = results.any((r) => r != ConnectivityResult.none);
    ConnectionType type = ConnectionType.none;

    if (results.contains(ConnectivityResult.wifi)) {
      type = ConnectionType.wifi;
    } else if (results.contains(ConnectivityResult.ethernet)) {
      type = ConnectionType.ethernet;
    } else if (results.contains(ConnectivityResult.mobile)) {
      type = ConnectionType.mobile;
    } else if (results.contains(ConnectivityResult.vpn)) {
      type = ConnectionType.vpn;
    } else if (results.contains(ConnectivityResult.bluetooth)) {
      type = ConnectionType.bluetooth;
    } else if (results.contains(ConnectivityResult.other)) {
      type = ConnectionType.other;
    }

    return ConnectionStatus(
      isOnline: isOnline,
      type: type,
      timestamp: DateTime.now(),
    );
  }

  bool get isWifi => type == ConnectionType.wifi;
  bool get isMobile => type == ConnectionType.mobile;
  bool get isHighSpeed =>
      type == ConnectionType.wifi || type == ConnectionType.ethernet;

  @override
  String toString() => 'ConnectionStatus(isOnline: $isOnline, type: $type)';
}

class ConnectivityService {
  static ConnectivityService? _instance;
  static ConnectivityService get instance =>
      _instance ??= ConnectivityService._();

  ConnectivityService._();

  final Connectivity _connectivity = Connectivity();
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _statusController = StreamController<ConnectionStatus>.broadcast();
  ConnectionStatus _currentStatus = ConnectionStatus.offline();
  bool _initialized = false;
  bool _isDisposed = false;

  Stream<ConnectionStatus> get statusStream => _statusController.stream;
  ConnectionStatus get currentStatus => _currentStatus;
  bool get isOnline => _currentStatus.isOnline;
  bool get isWifi => _currentStatus.isWifi;
  bool get isHighSpeed => _currentStatus.isHighSpeed;

  Future<void> initialize() async {
    if (_initialized || _isDisposed) return;

    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);

      _subscription = _connectivity.onConnectivityChanged.listen(
        _updateStatus,
        onError: (error) {
          if (_isDisposed) return;
          debugPrint('❌ [Connectivity] خطأ في مراقبة الاتصال: $error');
          _currentStatus = ConnectionStatus.offline();
          if (!_statusController.isClosed) {
            _statusController.add(_currentStatus);
          }
        },
      );

      _initialized = true;
      debugPrint('✅ [Connectivity] تم تهيئة خدمة الاتصال: $_currentStatus');
    } catch (e) {
      debugPrint('❌ [Connectivity] فشل في تهيئة خدمة الاتصال: $e');
      _currentStatus = ConnectionStatus.offline();
    }
  }

  void _updateStatus(List<ConnectivityResult> results) {
    if (_isDisposed) return;

    final newStatus = ConnectionStatus.fromConnectivityResult(results);
    final wasOnline = _currentStatus.isOnline;
    _currentStatus = newStatus;
    if (!_statusController.isClosed) {
      _statusController.add(newStatus);
    }

    if (!wasOnline && newStatus.isOnline) {
      debugPrint('🌐 [Connectivity] الاتصال متاح: ${newStatus.type}');
    } else if (wasOnline && !newStatus.isOnline) {
      debugPrint('📴 [Connectivity] الاتصال مفقود');
    }
  }

  Future<bool> checkConnectivity() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _updateStatus(results);
      return _currentStatus.isOnline;
    } catch (e) {
      debugPrint('❌ [Connectivity] فشل في فحص الاتصال: $e');
      return false;
    }
  }

  Future<T?> executeWhenOnline<T>({
    required Future<T> Function() operation,
    Duration timeout = const Duration(seconds: 30),
    bool waitForConnection = true,
  }) async {
    if (isOnline) {
      return await operation();
    }

    if (!waitForConnection) {
      return null;
    }

    try {
      await statusStream
          .where((status) => status.isOnline)
          .first
          .timeout(timeout);
      return await operation();
    } on TimeoutException {
      debugPrint('⏱️ [Connectivity] انتهت مهلة انتظار الاتصال');
      return null;
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
    _instance = null;
    if (!_statusController.isClosed) {
      _statusController.close();
    }
    _isDisposed = true;
  }
}
