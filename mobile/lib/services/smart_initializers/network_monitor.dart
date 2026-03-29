import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// مراقب الشبكة — يُغلف connectivity_plus ويُوفر واجهة نظيفة.
///
/// لا يعتمد على أي Service آخر. يُطلق حدثاً عند كل انتقال
/// من offline → online فقط (onNetworkRestored).
class NetworkMonitor {
  NetworkMonitor._();
  static final NetworkMonitor instance = NetworkMonitor._();

  final Connectivity _connectivity = Connectivity();

  /// آخر نتيجة معروفة.
  List<ConnectivityResult> _lastResult = const [];

  /// يُطلق حدثاً فقط عند الانتقال من offline → online.
  final StreamController<void> _restoredController =
      StreamController<void>.broadcast();

  StreamSubscription<List<ConnectivityResult>>? _subscription;

  // ─── Public API ─────────────────────────────────────────────

  /// Stream يُطلق void عند كل انتقال offline → online.
  Stream<void> get onNetworkRestored => _restoredController.stream;

  /// فحص فوري للحالة الحالية.
  Future<bool> checkNow() async {
    final result = await _connectivity.checkConnectivity();
    _lastResult = result;
    return _isOnline(result);
  }

  /// حالة الشبكة الحالية (مخزّنة مؤقتاً).
  NetworkState get currentState {
    if (_lastResult.isEmpty) return NetworkState.unknown;
    return _isOnline(_lastResult) ? NetworkState.online : NetworkState.offline;
  }

  /// بدء مراقبة الشبكة (idempotent).
  void start() {
    if (_subscription != null) return;

    _subscription = _connectivity.onConnectivityChanged.listen((result) {
      final wasOffline = _lastResult.isNotEmpty && !_isOnline(_lastResult);
      _lastResult = result;
      final isNowOnline = _isOnline(result);

      if (wasOffline && isNowOnline) {
        _restoredController.add(null);
      }
    });
  }

  /// إيقاف المراقبة وتنظيف الموارد.
  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  // ─── Private ────────────────────────────────────────────────

  /// هل النتيجة تشير لوجود اتصال فعّال؟
  bool _isOnline(List<ConnectivityResult> result) {
    return result.isNotEmpty &&
        !result.every((r) => r == ConnectivityResult.none);
  }
}

/// حالات الشبكة الممكنة.
enum NetworkState {
  /// غير معروف بعد (لم يُجرَ فحص بعد).
  unknown,

  /// يوجد اتصال (WiFi / Mobile / Ethernet …).
  online,

  /// لا يوجد اتصال.
  offline,
}
