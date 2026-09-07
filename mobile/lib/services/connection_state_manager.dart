import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'appwrite_logger.dart';
import 'cloudflare_config.dart';

/// حالة الاتصال
enum ConnectionStatus { online, offline, checking, unknown }

/// مدير حالة الاتصال مع Appwrite
///
/// يتتبع حالة الاتصال بالإنترنت و Appwrite Server
/// ويوفر stream للاستماع للتغييرات
class ConnectionStateManager extends ChangeNotifier {
  factory ConnectionStateManager() => _instance;

  ConnectionStateManager._internal({
    required Connectivity connectivity,
    required Future<void> Function() appwriteProbe,
  }) : _connectivity = connectivity,
       _appwriteProbe = appwriteProbe;

  /// Constructor محدود للاختبارات: يسمح بمحاكاة offline/online وعدّ الطلبات.
  ConnectionStateManager.forTesting({
    required Connectivity connectivity,
    required Future<void> Function() appwriteProbe,
  }) : this._internal(connectivity: connectivity, appwriteProbe: appwriteProbe);

  static final ConnectionStateManager _instance =
      ConnectionStateManager._internal(
        connectivity: Connectivity(),
        // ✅ (2026-09-05) Cloudflare-only: الفحص يصيب /health على الـ worker
        appwriteProbe: () async {
          final res = await http
              .get(Uri.parse('${CloudflareConfig.workerUrl}/health'))
              .timeout(const Duration(seconds: 8));
          if (res.statusCode != 200) {
            throw Exception('Worker health ${res.statusCode}');
          }
        },
      );

  final _logger = AppwriteLogger();
  final Connectivity _connectivity;
  final Future<void> Function() _appwriteProbe;

  ConnectionStatus _status = ConnectionStatus.unknown;
  DateTime? _lastCheckTime;
  bool _hasNetworkTransport = false;
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
      _logger.debug(
        'ConnectionStateManager already initialized',
        tag: 'CONNECTION',
      );
      return;
    }

    _logger.info('Initializing ConnectionStateManager', tag: 'CONNECTION');

    // الاستماع لتغييرات الشبكة
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
      _onConnectivityChanged,
      onError: (Object error) {
        _logger.error(
          'Connectivity stream error',
          error: error,
          tag: 'CONNECTION',
        );
      },
    );

    // فحص دوري كل 30 ثانية، لكن لا نرسل أي طلب عند offline.
    _periodicCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_hasNetworkTransport) {
        unawaited(checkConnection());
      }
    });

    // فحص أولي: نقرأ حالة الشبكة أولاً حتى لا نبدأ loop طلبات Appwrite
    // على جهاز غير متصل.
    final initialResults = await _connectivity.checkConnectivity();
    _hasNetworkTransport = initialResults.any(
      (result) => result != ConnectivityResult.none,
    );
    if (_hasNetworkTransport) {
      await checkConnection();
    } else {
      _updateStatus(ConnectionStatus.offline);
    }
  }

  /// معالج تغييرات الاتصال
  void _onConnectivityChanged(List<ConnectivityResult> results) {
    _logger.debug('Connectivity changed: $results', tag: 'CONNECTION');

    final wasNetworkAvailable = _hasNetworkTransport;
    _hasNetworkTransport = results.any(
      (result) => result != ConnectivityResult.none,
    );

    // إذا لا يوجد اتصال على الإطلاق: حدّث الحالة فقط ولا تفحص Appwrite.
    if (!_hasNetworkTransport) {
      _updateStatus(ConnectionStatus.offline);
      return;
    }

    // نفّذ فحصاً واحداً فقط عند انتقال الحالة من offline إلى online.
    // تغيّر Wi-Fi إلى Mobile أو العكس لا يعيد probe بلا حاجة.
    if (!wasNetworkAvailable) {
      unawaited(checkConnection());
    }
  }

  /// فحص حالة الاتصال
  Future<void> checkConnection() async {
    // لا توجد فائدة من تكرار طلبات الشبكة عندما أكد Connectivity أن الجهاز
    // offline. سيُستأنف الفحص من _onConnectivityChanged عند عودة الاتصال.
    if (!_hasNetworkTransport) {
      _updateStatus(ConnectionStatus.offline);
      return;
    }

    if (_status == ConnectionStatus.checking) {
      _logger.debug('Connection check already in progress', tag: 'CONNECTION');
      return;
    }

    _updateStatus(ConnectionStatus.checking);

    try {
      // محاولة طلب بسيط للتحقق من Appwrite.
      await _appwriteProbe();

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
    unawaited(_connectivitySubscription?.cancel());
    _periodicCheckTimer?.cancel();
    unawaited(_statusController.close());
    super.dispose();
  }
}
