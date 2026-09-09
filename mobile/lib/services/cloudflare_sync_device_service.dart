/// Device registration and management for Cloudflare sync.
///
/// Extracted from cloudflare_sync_manager.dart (3,370 LOC)
/// Handles device registration, FCM tokens, device tracking

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../screens/settings/error_tracker_screen.dart'
    show logHttpError, logError, ErrorCategory;
import 'cloudflare_config.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';

/// Device registration and management for Cloudflare sync.
class CloudflareSyncDeviceService {
  CloudflareSyncDeviceService({
    required this.httpClient,
    required this.database,
  });

  final http.Client httpClient;
  final AppDatabase database;

  late final OutboxDao _outboxDao = OutboxDao(database);

  String? _token;
  String? _deviceId;

  String? get token => _token;
  String? get deviceId => _deviceId;

  void setCredentials(String token, String deviceId) {
    _token = token;
    _deviceId = deviceId;
  }

  /// Register device with Cloudflare server
  /// Returns device ID on success
  Future<String> registerDevice() async {
    if (_token == null || _deviceId == null) {
      throw StateError('Not initialized');
    }

    final response = await httpClient
        .post(
          Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
          headers: {
            'Authorization': 'Bearer $_token',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'deviceId': _deviceId,
            'platform': 'android',
            'localUuid': _deviceId,
          }),
        )
        .timeout(const Duration(seconds: 20));

    if (response.statusCode == 200) {
      // Device registered successfully
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = _deviceSyncPayload(platform: 'android', now: now);

      await database.transaction(() async {
        await _writeLocalDeviceRow(payload);
        final deviceRowUuid = payload['local_uuid'] as String?;
        if (deviceRowUuid != null && deviceRowUuid.isNotEmpty) {
          try {
            await _outboxDao.merge(
              entity: 'devices',
              op: 'create',
              localUuid: deviceRowUuid,
              payload: payload,
              clientTs: now,
            );
          } catch (e) {
            rethrow;
          }
        }
      });
      return _deviceId!;
    }

    logHttpError(
      title: 'فشل تسجيل الجهاز',
      statusCode: response.statusCode,
      responseBody: response.body,
      source: 'sync:device_register',
    );
    throw Exception('Device registration failed: ${response.statusCode}');
  }

  /// Set FCM token for push notifications
  Future<void> setFcmToken(String token) async {
    if (_token == null || _deviceId == null) return;

    try {
      await httpClient
          .post(
            Uri.parse('${CloudflareConfig.workerUrl}/api/devices/register'),
            headers: {
              'Authorization': 'Bearer $_token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'deviceId': _deviceId,
              'fcmToken': token,
              'platform': 'android',
            }),
          )
          .timeout(const Duration(seconds: 20));

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final payload = _deviceSyncPayload(
        fcmToken: token,
        platform: 'android',
        now: now,
      );

      await database.transaction(() async {
        await _writeLocalDeviceRow(payload);
        final deviceRowUuid = payload['local_uuid'] as String?;
        if (deviceRowUuid != null && deviceRowUuid.isNotEmpty) {
          try {
            await _outboxDao.merge(
              entity: 'devices',
              op: 'update',
              localUuid: deviceRowUuid,
              payload: payload,
              clientTs: now,
            );
          } catch (e) {
            rethrow;
          }
        }
      });
    } catch (e) {
      // Log but don't fail
      logError(
        title: 'خطأ في تعيين توكن FCM',
        message: e.toString(),
        category: ErrorCategory.sync,
        source: 'sync:fcm_token',
      );
    }
  }

  /// Generate device sync payload for D1 schema
  Map<String, dynamic> _deviceSyncPayload({
    required int now,
    String? fcmToken,
    String? platform,
    String? deviceName,
  }) {
    final deviceId = _deviceId ?? '';
    return <String, dynamic>{
      'local_uuid': deviceId,
      'device_id': deviceId,
      if (deviceName != null) 'device_name': deviceName,
      if (platform != null) 'platform': platform,
      if (fcmToken != null) 'fcm_token': fcmToken,
      'status': 'active',
      'is_active': 1,
      'last_active': now,
      'updated_at': now,
      'last_modified': now,
      'last_modified_epoch': now,
      'version': 1,
      'origin': 'local',
      'vector_clock': jsonEncode(<String, int>{
        if (deviceId.isNotEmpty) deviceId: 1,
      }),
    };
  }

  /// Write/update device row locally (landing zone)
  Future<void> _writeLocalDeviceRow(Map<String, dynamic> syncPayload) async {
    final localUuid = syncPayload['local_uuid'] as String?;
    if (localUuid == null || localUuid.isEmpty) return;

    final existingRows = await database
        .customSelect(
          'SELECT id, version FROM devices WHERE local_uuid = ? LIMIT 1',
          variables: [Variable.withString(localUuid)],
        )
        .get();

    if (existingRows.isNotEmpty) {
      final existingVersion = (existingRows.first.data['version'] as int?) ?? 0;
      final fields = Map<String, dynamic>.from(syncPayload)
        ..remove('local_uuid')
        ..remove('created_at')
        ..['version'] = existingVersion + 1;
      final setClauses = fields.keys.map((c) => '$c = ?').join(', ');
      await database.customStatement(
        'UPDATE devices SET $setClauses WHERE local_uuid = ?',
        [...fields.values, localUuid],
      );
    } else {
      final row = <String, dynamic>{
        ...syncPayload,
        'device_name': syncPayload['device_name'] ?? '',
        'status': syncPayload['status'] ?? 'active',
        'is_active': syncPayload['is_active'] ?? 1,
        'created_at':
            (syncPayload['created_at'] ?? syncPayload['updated_at']) as int,
        'created_at_epoch': 0,
      }..remove('id');
      final columns = row.keys.join(', ');
      final placeholders = row.keys.map((_) => '?').join(', ');
      await database.customStatement(
        'INSERT OR REPLACE INTO devices ($columns) VALUES ($placeholders)',
        row.values.toList(),
      );
    }
  }

  /// Fetch registered devices from server
  Future<List<dynamic>> getRegisteredDevices() async {
    if (_token == null) return [];

    try {
      final response = await httpClient.get(
        Uri.parse('${CloudflareConfig.workerUrl}/api/devices'),
        headers: {'Authorization': 'Bearer $_token'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        return (data['devices'] as List<dynamic>?) ?? [];
      }
      return [];
    } catch (e) {
      return [];
    }
  }
}
