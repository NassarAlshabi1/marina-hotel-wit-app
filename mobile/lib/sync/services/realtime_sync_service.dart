/// Realtime Sync Service
/// خدمة المزامنة الفورية باستخدام WebSocket أو Server-Sent Events
/// تدفع التغييرات فور حدوثها على السيرفر

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

import '../orchestrator/sync_orchestrator.dart';

/// خدمة المزامنة الفورية
class RealtimeSyncService {
  final SyncOrchestrator _orchestrator;
  final RealtimeConfig _config;

  WebSocketChannel? _channel;
  StreamSubscription? _messageSubscription;
  StreamSubscription? _connectivitySubscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  final _eventController = StreamController<RealtimeEvent>.broadcast();
  final _connectionStateController = StreamController<ConnectionState>.broadcast();

  bool _isConnected = false;
  bool _isConnecting = false;
  int _reconnectAttempts = 0;
  DateTime? _lastPing;

  RealtimeSyncService({
    required SyncOrchestrator orchestrator,
    required RealtimeConfig config,
  })  : _orchestrator = orchestrator,
        _config = config;

  /// Stream للأحداث الفورية
  Stream<RealtimeEvent> get events => _eventController.stream;

  /// Stream لحالة الاتصال
  Stream<ConnectionState> get connectionState => _connectionStateController.stream;

  /// حالة الاتصال الحالية
  bool get isConnected => _isConnected;
  bool get isConnecting => _isConnecting;

  /// بدء الخدمة
  Future<void> start() async {
    if (!_config.enabled) return;

    // الاستماع لتغيرات الاتصال
    _connectivitySubscription = Connectivity()
        .onConnectivityChanged
        .listen((results) => _handleConnectivityChange(results));

    // محاولة الاتصال الأولى
    await _connect();
  }

  /// إيقاف الخدمة
  Future<void> stop() async {
    _reconnectTimer?.cancel();
    _pingTimer?.cancel();
    await _disconnect();
    await _connectivitySubscription?.cancel();
  }

  /// إعادة الاتصال
  Future<void> reconnect() async {
    await _disconnect();
    await _connect();
  }

  /// الاتصال بالخادم
  Future<void> _connect() async {
    if (_isConnected || _isConnecting) return;

    _isConnecting = true;
    _connectionStateController.add(ConnectionState.connecting);

    try {
      developer.log('Connecting to WebSocket: ${_config.wsUrl}', name: 'RealtimeSync');

      _channel = IOWebSocketChannel.connect(
        _config.wsUrl,
        headers: _config.headers,
        pingInterval: _config.pingInterval,
      );

      _messageSubscription = _channel!.stream.listen(
        _handleMessage,
        onError: _handleError,
        onDone: _handleDisconnect,
      );

      // إرسال رسالة المصادقة إذا لزم الأمر
      if (_config.authToken != null) {
        _sendAuth();
      }

      // الاشتراك في التغييرات
      _subscribeToChanges();

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _connectionStateController.add(ConnectionState.connected);

      // بدء مؤقت الـ ping
      _startPingTimer();

      developer.log('WebSocket connected', name: 'RealtimeSync');
    } catch (e, stackTrace) {
      _isConnecting = false;
      _connectionStateController.add(ConnectionState.error);

      developer.log(
        'WebSocket connection failed',
        name: 'RealtimeSync',
        error: e,
        stackTrace: stackTrace,
      );

      _scheduleReconnect();
    }
  }

  /// قطع الاتصال
  Future<void> _disconnect() async {
    _pingTimer?.cancel();
    await _messageSubscription?.cancel();
    _channel?.sink.close();

    _isConnected = false;
    _isConnecting = false;
    _connectionStateController.add(ConnectionState.disconnected);

    developer.log('WebSocket disconnected', name: 'RealtimeSync');
  }

  /// معالجة رسالة واردة
  void _handleMessage(dynamic message) {
    try {
      final data = jsonDecode(message as String) as Map<String, dynamic>;
      final event = RealtimeEvent.fromJson(data);

      developer.log('Received event: ${event.type}', name: 'RealtimeSync');

      _eventController.add(event);

      // معالجة حسب نوع الحدث
      switch (event.type) {
        case RealtimeEventType.change:
          _handleRemoteChange(event);
          break;
        case RealtimeEventType.ping:
          _lastPing = DateTime.now();
          _sendPong();
          break;
        case RealtimeEventType.pong:
          _lastPing = DateTime.now();
          break;
        case RealtimeEventType.authSuccess:
          developer.log('Authentication successful', name: 'RealtimeSync');
          break;
        case RealtimeEventType.authError:
          developer.log('Authentication failed', name: 'RealtimeSync');
          break;
        case RealtimeEventType.error:
          developer.log('Server error: ${event.payload}', name: 'RealtimeSync');
          break;
        case RealtimeEventType.unknown:
          developer.log('Unknown event type', name: 'RealtimeSync');
          break;
      }
    } catch (e, stackTrace) {
      developer.log(
        'Failed to handle message',
        name: 'RealtimeSync',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// معالجة تغيير بعيد
  Future<void> _handleRemoteChange(RealtimeEvent event) async {
    if (event.table == null || event.payload == null) return;

    // تشغيل مزامنة سريعة لسحب التغييرات
    // بدلاً من تطبيق التغيير مباشرة، نستخدم DeltaSyncEngine لضمان السلامة
    try {
      await _orchestrator.pullOnly();
    } catch (e) {
      developer.log(
        'Failed to sync on remote change',
        name: 'RealtimeSync',
        error: e,
      );
    }
  }

  /// معالجة خطأ
  void _handleError(error) {
    developer.log('WebSocket error: $error', name: 'RealtimeSync');
    _handleDisconnect();
  }

  /// معالجة قطع الاتصال
  void _handleDisconnect() {
    if (!_isConnected) return;

    _isConnected = false;
    _connectionStateController.add(ConnectionState.disconnected);

    _scheduleReconnect();
  }

  /// جدولة إعادة الاتصال
  void _scheduleReconnect() {
    if (_reconnectTimer?.isActive ?? false) return;

    _reconnectAttempts++;

    // Exponential backoff للإعادة
    final delaySeconds = _calculateReconnectDelay();

    developer.log(
      'Scheduling reconnect in ${delaySeconds}s (attempt $_reconnectAttempts)',
      name: 'RealtimeSync',
    );

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      _connect();
    });

    _connectionStateController.add(ConnectionState.reconnecting);
  }

  /// حساب تأخير إعادة الاتصال
  int _calculateReconnectDelay() {
    // Exponential backoff: 1, 2, 4, 8, 16, ... up to 60 seconds
    final baseDelay = 1 << (_reconnectAttempts - 1);
    return baseDelay.clamp(1, 60);
  }

  /// معالجة تغير الاتصال
  void _handleConnectivityChange(List<ConnectivityResult> results) {
    if (results.every((r) => r == ConnectivityResult.none)) {
      // فقدان الاتصال - قطع WebSocket
      _disconnect();
    } else if (!_isConnected && !_isConnecting) {
      // استعادة الاتصال - إعادة الاتصال
      _connect();
    }
  }

  /// إرسال رسالة المصادقة
  void _sendAuth() {
    _send({
      'type': 'auth',
      'token': _config.authToken,
    });
  }

  /// الاشتراك في التغييرات
  void _subscribeToChanges() {
    _send({
      'type': 'subscribe',
      'tables': _config.tablesToWatch,
    });
  }

  /// إلغاء الاشتراك
  // ignore: unused_element
  void _unsubscribe() {
    _send({
      'type': 'unsubscribe',
    });
  }

  /// إرسال ping
  void _sendPing() {
    _send({'type': 'ping'});
  }

  /// إرسال pong
  void _sendPong() {
    _send({'type': 'pong'});
  }

  /// إرسال رسالة
  void _send(Map<String, dynamic> message) {
    if (!_isConnected) return;

    try {
      _channel!.sink.add(jsonEncode(message));
    } catch (e) {
      developer.log('Failed to send message: $e', name: 'RealtimeSync');
    }
  }

  /// بدء مؤقت ping
  void _startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_config.pingInterval, (_) {
      _sendPing();

      // التحقق من آخر استجابة
      if (_lastPing != null) {
        final elapsed = DateTime.now().difference(_lastPing!);
        if (elapsed > _config.pingInterval * 2) {
          // لا استجابة لفترة طويلة - إعادة الاتصال
          developer.log('Ping timeout, reconnecting...', name: 'RealtimeSync');
          reconnect();
        }
      }
    });
  }

  /// التخلص من الموارد
  void dispose() {
    stop();
    _eventController.close();
    _connectionStateController.close();
  }
}

/// حالة الاتصال
enum ConnectionState {
  disconnected,
  connecting,
  connected,
  reconnecting,
  error,
}

/// إعدادات Realtime
class RealtimeConfig {
  final String wsUrl;
  final String? authToken;
  final Map<String, String>? headers;
  final List<String> tablesToWatch;
  final Duration pingInterval;
  final bool enabled;

  const RealtimeConfig({
    required this.wsUrl,
    this.authToken,
    this.headers,
    this.tablesToWatch = const [],
    this.pingInterval = const Duration(seconds: 30),
    this.enabled = true,
  });
}

/// حدث Realtime
class RealtimeEvent {
  final RealtimeEventType type;
  final String? table;
  final String? operation;
  final String? uuid;
  final Map<String, dynamic>? payload;
  final DateTime timestamp;

  RealtimeEvent({
    required this.type,
    this.table,
    this.operation,
    this.uuid,
    this.payload,
    required this.timestamp,
  });

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String? ?? 'unknown';

    return RealtimeEvent(
      type: RealtimeEventType.values.firstWhere(
        (e) => e.name == typeStr,
        orElse: () => RealtimeEventType.unknown,
      ),
      table: json['table'] as String?,
      operation: json['operation'] as String?,
      uuid: json['uuid'] as String?,
      payload: json['payload'] as Map<String, dynamic>?,
      timestamp: DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'table': table,
        'operation': operation,
        'uuid': uuid,
        'payload': payload,
        'timestamp': timestamp.toIso8601String(),
      };
}

/// أنواع أحداث Realtime
enum RealtimeEventType {
  change,
  ping,
  pong,
  authSuccess,
  authError,
  error,
  unknown,
}
