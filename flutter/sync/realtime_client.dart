// ═══════════════════════════════════════════════════════════════
//  realtime_client.dart — WebSocket Realtime Client
//  Connects to Cloudflare Durable Object for live sync notifications
// ═══════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';

/// Realtime event from the server
class RealtimeEvent {
  const RealtimeEvent({
    required this.type,
    required this.entity,
    required this.entityId,
    this.operation,
    this.deviceId,
    required this.timestamp,
    this.data,
  });

  /// 'change', 'lock', 'unlock', 'presence'
  final String type;
  final String entity;
  final String entityId;
  final String? operation;
  final String? deviceId;
  final int timestamp;
  final Map<String, dynamic>? data;

  factory RealtimeEvent.fromJson(Map<String, dynamic> json) => RealtimeEvent(
        type: json['type'] as String? ?? 'unknown',
        entity: json['entity'] as String? ?? '',
        entityId: json['entityId'] as String? ?? '',
        operation: json['operation'] as String?,
        deviceId: json['deviceId'] as String?,
        timestamp: json['timestamp'] as int? ?? 0,
        data: json['data'] as Map<String, dynamic>?,
      );
}

/// Lock response from the server
class LockResponse {
  const LockResponse({
    required this.granted,
    this.lockId,
    this.heldBy,
    this.expiresAt,
  });

  final bool granted;
  final String? lockId;
  final String? heldBy;
  final int? expiresAt;

  factory LockResponse.fromJson(Map<String, dynamic> json) => LockResponse(
        granted: json['granted'] as bool? ?? false,
        lockId: json['lockId'] as String?,
        heldBy: json['heldBy'] as String?,
        expiresAt: json['expiresAt'] as int?,
      );
}

/// ═══ Realtime Client ════════════════════════════════════════

class RealtimeClient {
  RealtimeClient({required this.baseUrl});

  final String baseUrl;
  WebSocketChannel? _channel;
  bool _isConnected = false;
  String? _token;
  String? _deviceId;
  String? _entity;

  final _eventController = StreamController<RealtimeEvent>.broadcast();
  final _connectionController = StreamController<bool>.broadcast();

  /// Stream of realtime events
  Stream<RealtimeEvent> get events => _eventController.stream;

  /// Stream of connection state changes (true = connected)
  Stream<bool> get connectionState => _connectionController.stream;

  /// Is the WebSocket connected?
  bool get isConnected => _isConnected;

  /// Connect to the realtime WebSocket
  Future<void> connect({
    required String token,
    required String deviceId,
    String entity = '*',
  }) async {
    _token = token;
    _deviceId = deviceId;
    _entity = entity;

    final wsUrl = baseUrl
        .replaceFirst('https://', 'wss://')
        .replaceFirst('http://', 'ws://');

    final uri = Uri.parse('$wsUrl/api/realtime?deviceId=$deviceId&entity=$entity');

    try {
      _channel = WebSocketChannel.connect(uri);
      _isConnected = true;
      _connectionController.add(true);

      _channel!.stream.listen(
        (data) {
          try {
            final json = jsonDecode(data as String) as Map<String, dynamic>;
            _eventController.add(RealtimeEvent.fromJson(json));
          } catch (_) {
            // Ignore malformed messages
          }
        },
        onError: (error) {
          _isConnected = false;
          _connectionController.add(false);
          _scheduleReconnect();
        },
        onDone: () {
          _isConnected = false;
          _connectionController.add(false);
          _scheduleReconnect();
        },
      );
    } catch (e) {
      _isConnected = false;
      _connectionController.add(false);
      _scheduleReconnect();
    }
  }

  /// Disconnect from the WebSocket
  void disconnect() {
    _channel?.sink.close();
    _channel = null;
    _isConnected = false;
    _connectionController.add(false);
  }

  /// Send a message to the server
  void send(RealtimeEvent event) {
    if (_channel != null && _isConnected) {
      _channel!.sink.add(jsonEncode({
        'type': event.type,
        'entity': event.entity,
        'entityId': event.entityId,
        'operation': event.operation,
        'deviceId': event.deviceId,
        'timestamp': event.timestamp,
        'data': event.data,
      }));
    }
  }

  /// Notify the server of a local change (triggers pull on other devices)
  void notifyChange({
    required String entity,
    required String entityId,
    required String operation,
  }) {
    send(RealtimeEvent(
      type: 'change',
      entity: entity,
      entityId: entityId,
      operation: operation,
      deviceId: _deviceId,
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }

  // ─── Auto-reconnect ────────────────────────────────────────

  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  static const _maxReconnectAttempts = 5;
  static const _baseDelay = Duration(seconds: 2);

  void _scheduleReconnect() {
    if (_reconnectAttempts >= _maxReconnectAttempts) return;
    if (_token == null || _deviceId == null) return;

    _reconnectAttempts++;
    final delay = _baseDelay * _reconnectAttempts;

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(delay, () {
      connect(
        token: _token!,
        deviceId: _deviceId!,
        entity: _entity ?? '*',
      );
    });
  }

  /// Dispose all resources
  void dispose() {
    _reconnectTimer?.cancel();
    disconnect();
    _eventController.close();
    _connectionController.close();
  }
}
