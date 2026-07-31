// ═══════════════════════════════════════════════════════════════
//  api_client.dart — HTTP Client for Cloudflare Worker API
//  Handles auth, sync, and file operations
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'realtime_client.dart';

/// API response wrapper
class ApiResponse<T> {
  const ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.statusCode = 0,
  });

  final bool success;
  final T? data;
  final String? error;
  final int statusCode;

  factory ApiResponse.ok(T data, {int statusCode = 200}) =>
      ApiResponse(success: true, data: data, statusCode: statusCode);

  factory ApiResponse.fail(String error, {int statusCode = 0}) =>
      ApiResponse(success: false, error: error, statusCode: statusCode);
}

/// Push operation structure
class PushOperation {
  const PushOperation({
    required this.idempotencyKey,
    required this.entity,
    required this.operation,
    required this.data,
    required this.vectorClock,
    required this.updatedAt,
    this.deviceId,
  });

  final String idempotencyKey;
  final String entity;
  final String operation; // 'create', 'update', 'delete'
  final Map<String, dynamic> data;
  final String vectorClock;
  final int updatedAt;
  final String? deviceId;

  Map<String, dynamic> toJson() => {
        'idempotencyKey': idempotencyKey,
        'entity': entity,
        'operation': operation,
        'data': data,
        'vectorClock': vectorClock,
        'updatedAt': updatedAt,
        if (deviceId != null) 'deviceId': deviceId,
      };
}

/// Pull result structure
class PullResult {
  const PullResult({
    required this.changes,
    required this.cursor,
    required this.hasMore,
    required this.serverTime,
  });

  final List<Map<String, dynamic>> changes;
  final int cursor;
  final bool hasMore;
  final int serverTime;

  factory PullResult.fromJson(Map<String, dynamic> json) => PullResult(
        changes: (json['changes'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        cursor: int.tryParse(json['cursor']?.toString() ?? '0') ?? 0,
        hasMore: json['has_more'] as bool? ?? false,
        serverTime: json['server_time'] as int? ?? 0,
      );
}

/// Push result structure
class PushResult {
  const PushResult({
    required this.results,
    required this.summary,
    required this.serverTime,
  });

  final List<PushResultItem> results;
  final PushSummary summary;
  final int serverTime;

  factory PushResult.fromJson(Map<String, dynamic> json) => PushResult(
        results: (json['results'] as List? ?? [])
            .map((e) => PushResultItem.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList(),
        summary: PushSummary.fromJson(
            Map<String, dynamic>.from(json['summary'] as Map? ?? {})),
        serverTime: json['server_time'] as int? ?? 0,
      );
}

class PushResultItem {
  const PushResultItem({
    required this.idempotencyKey,
    required this.success,
    this.entity,
    this.entityId,
    this.error,
    this.skipped,
  });

  final String idempotencyKey;
  final bool success;
  final String? entity;
  final String? entityId;
  final String? error;
  final bool? skipped;

  factory PushResultItem.fromJson(Map<String, dynamic> json) => PushResultItem(
        idempotencyKey: json['idempotencyKey'] as String? ?? '',
        success: json['success'] as bool? ?? false,
        entity: json['entity'] as String?,
        entityId: json['entityId'] as String?,
        error: json['error'] as String?,
        skipped: json['skipped'] as bool?,
      );
}

class PushSummary {
  const PushSummary({
    required this.total,
    required this.success,
    required this.failed,
    required this.skipped,
  });

  final int total;
  final int success;
  final int failed;
  final int skipped;

  factory PushSummary.fromJson(Map<String, dynamic> json) => PushSummary(
        total: json['total'] as int? ?? 0,
        success: json['success'] as int? ?? 0,
        failed: json['failed'] as int? ?? 0,
        skipped: json['skipped'] as int? ?? 0,
      );
}

/// ═══ API Client ═════════════════════════════════════════════

class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;
  String? _token;
  String? _deviceId;

  static const _tokenKey = 'cf_api_token';
  static const _deviceKey = 'cf_device_id';

  /// Initialize — load token from SharedPreferences
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(_tokenKey);
    _deviceId = prefs.getString(_deviceKey) ?? _generateDeviceId();
    await prefs.setString(_deviceKey, _deviceId!);
  }

  /// Login and store token
  Future<ApiResponse<Map<String, dynamic>>> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/login'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'username': username,
          'password': password,
          'device_id': _deviceId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        _token = data['token'] as String?;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, _token!);

        return ApiResponse.ok(data);
      }

      final error = jsonDecode(response.body)['error'] as String? ?? 'Login failed';
      return ApiResponse.fail(error, statusCode: response.statusCode);
    } catch (e) {
      return ApiResponse.fail('Network error: $e');
    }
  }

  /// Logout
  Future<void> logout() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
  }

  /// Check if authenticated
  bool get isAuthenticated => _token != null;

  /// Get device ID
  String? get deviceId => _deviceId;

  // ═══ Sync Lock (Durable Object) ═══════════════════════════

  /// Acquire a sync lock on an entity (prevents concurrent writes)
  Future<ApiResponse<LockResponse>> acquireLock({
    required String entity,
    required String entityId,
    required String operation,
  }) async {
    if (_token == null) {
      return ApiResponse.fail('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/lock'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'X-Device-Id': _deviceId ?? '',
        },
        body: jsonEncode({
          'deviceId': _deviceId,
          'entity': entity,
          'entityId': entityId,
          'operation': operation,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.ok(LockResponse.fromJson(data));
      }

      final error = jsonDecode(response.body)['error'] as String? ?? 'Lock failed';
      return ApiResponse.fail(error, statusCode: response.statusCode);
    } catch (e) {
      return ApiResponse.fail('Lock error: $e');
    }
  }

  /// Release a sync lock
  Future<ApiResponse<bool>> releaseLock({
    required String entity,
    required String entityId,
  }) async {
    if (_token == null) {
      return ApiResponse.fail('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/unlock'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'X-Device-Id': _deviceId ?? '',
        },
        body: jsonEncode({
          'deviceId': _deviceId,
          'entity': entity,
          'entityId': entityId,
        }),
      );

      if (response.statusCode == 200) {
        return ApiResponse.ok(true);
      }

      return ApiResponse.fail('Unlock failed', statusCode: response.statusCode);
    } catch (e) {
      return ApiResponse.fail('Unlock error: $e');
    }
  }

  /// List active sync locks
  Future<ApiResponse<List<Map<String, dynamic>>>> getActiveLocks() async {
    if (_token == null) {
      return ApiResponse.fail('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/locks'),
        headers: {
          'Authorization': 'Bearer $_token',
          'X-Device-Id': _deviceId ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final locks = (data['locks'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return ApiResponse.ok(locks);
      }

      return ApiResponse.fail('Failed to fetch locks');
    } catch (e) {
      return ApiResponse.fail('Network error: $e');
    }
  }

  /// Pull changes (Delta Sync)
  Future<ApiResponse<PullResult>> pullChanges({
    int cursor = 0,
    String? entity,
    int limit = 200,
  }) async {
    if (_token == null) {
      return ApiResponse.fail('Not authenticated');
    }

    try {
      final params = <String, String>{
        'cursor': cursor.toString(),
        'limit': limit.toString(),
      };
      if (entity != null) params['entity'] = entity;

      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/pull').replace(queryParameters: params),
        headers: {
          'Authorization': 'Bearer $_token',
          'X-Device-Id': _deviceId ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.ok(PullResult.fromJson(data));
      }

      final error = jsonDecode(response.body)['error'] as String? ?? 'Pull failed';
      return ApiResponse.fail(error, statusCode: response.statusCode);
    } catch (e) {
      return ApiResponse.fail('Network error: $e');
    }
  }

  /// Push changes (Outbox processing)
  Future<ApiResponse<PushResult>> pushChanges({
    required List<PushOperation> operations,
  }) async {
    if (_token == null) {
      return ApiResponse.fail('Not authenticated');
    }

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/sync/push'),
        headers: {
          'Authorization': 'Bearer $_token',
          'Content-Type': 'application/json',
          'X-Device-Id': _deviceId ?? '',
        },
        body: jsonEncode({
          'operations': operations.map((op) => op.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return ApiResponse.ok(PushResult.fromJson(data));
      }

      final error = jsonDecode(response.body)['error'] as String? ?? 'Push failed';
      return ApiResponse.fail(error, statusCode: response.statusCode);
    } catch (e) {
      return ApiResponse.fail('Network error: $e');
    }
  }

  /// Get sync log
  Future<ApiResponse<List<Map<String, dynamic>>>> getSyncLog({
    int limit = 50,
    int offset = 0,
  }) async {
    if (_token == null) {
      return ApiResponse.fail('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/log')
            .replace(queryParameters: {'limit': limit.toString(), 'offset': offset.toString()}),
        headers: {
          'Authorization': 'Bearer $_token',
          'X-Device-Id': _deviceId ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final logs = (data['logs'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return ApiResponse.ok(logs);
      }

      return ApiResponse.fail('Failed to fetch sync log');
    } catch (e) {
      return ApiResponse.fail('Network error: $e');
    }
  }

  /// Get sync conflicts
  Future<ApiResponse<List<Map<String, dynamic>>>> getConflicts({
    int limit = 50,
  }) async {
    if (_token == null) {
      return ApiResponse.fail('Not authenticated');
    }

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/sync/conflicts')
            .replace(queryParameters: {'limit': limit.toString()}),
        headers: {
          'Authorization': 'Bearer $_token',
          'X-Device-Id': _deviceId ?? '',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final conflicts = (data['conflicts'] as List? ?? [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        return ApiResponse.ok(conflicts);
      }

      return ApiResponse.fail('Failed to fetch conflicts');
    } catch (e) {
      return ApiResponse.fail('Network error: $e');
    }
  }

  /// Generate unique device ID
  String _generateDeviceId() {
    final now = DateTime.now().millisecondsSinceEpoch;
    final random = now.hashCode.toRadixString(36);
    return 'dev_${now}_$random';
  }
}
