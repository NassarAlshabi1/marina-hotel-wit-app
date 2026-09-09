/// Push operations (outbox) for Cloudflare sync.
///
/// Extracted from cloudflare_sync_manager.dart (3,370 LOC)
/// Handles pushing local changes to Cloudflare D1

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../screens/settings/error_tracker_screen.dart' show logHttpError;
import 'cloudflare_config.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'vector_clock_service.dart';

/// Push operations (outbox) for Cloudflare sync.
class CloudflareSyncPushService {
  CloudflareSyncPushService({
    required this.httpClient,
    required this.database,
    VectorClockService? vectorClockService,
  }) : vectorClockService = vectorClockService ?? VectorClockService(database);

  final http.Client httpClient;
  final AppDatabase database;
  final VectorClockService vectorClockService;

  String? _token;
  String? _deviceId;

  String? get token => _token;
  String? get deviceId => _deviceId;

  void setCredentials(String token, String deviceId) {
    _token = token;
    _deviceId = deviceId;
  }

  /// Push local changes (outbox) to Cloudflare
  /// Returns number of records pushed
  Future<int> pushOutbox() async {
    if (_token == null || _deviceId == null) return 0;

    try {
      int totalPushed = 0;
      const batchSize = 50;
      final outboxDao = OutboxDao(database);

      while (true) {
        // Claim the next pending batch (takeBatch atomically marks it
        // as processing so concurrent workers don't double-push)
        final batch = await outboxDao.takeBatch(batchSize);

        if (batch.isEmpty) break;

        final result = await _pushBatch(batch);
        totalPushed += result.pushed;

        if (result.failedIds.isNotEmpty) {
          // Mark failed records for retry (status='failed' — يُعاد
          // التقاطها في الجلسة التالية عبر retryFailed)
          await outboxDao.markFailed(result.failedIds.toList());
        }

        // Small delay between batches
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }

      return totalPushed;
    } catch (e) {
      debugPrint('⚠️ Push error: $e');
      return 0;
    }
  }

  /// Push a batch of outbox records
  Future<({int pushed, Set<int> failedIds})> _pushBatch(
    List<OutboxData> batch,
  ) async {
    if (_token == null) {
      return (pushed: 0, failedIds: batch.map((r) => r.id).toSet());
    }

    int pushed = 0;
    final failedIds = <int>{};
    final outboxDao = OutboxDao(database);

    for (final record in batch) {
      try {
        final vectorClock = await rowVectorClock(
          record.entity,
          record.localUuid,
        );
        final decodedPayload = jsonDecode(record.payload);
        final payload = <String, dynamic>{
          'vector_clock': vectorClock,
          if (decodedPayload is Map<String, dynamic>) ...decodedPayload,
        };

        final response = await httpClient
            .post(
              Uri.parse(
                '${CloudflareConfig.workerUrl}/api/sync/'
                '${record.entity}',
              ),
              headers: {
                'Authorization': 'Bearer $_token',
                'Content-Type': 'application/json',
              },
              body: jsonEncode({
                'op': record.op,
                'local_uuid': record.localUuid,
                'payload': payload,
                'client_ts': record.clientTs,
                'idempotency_key': record.idempotencyKey,
              }),
            )
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200 || response.statusCode == 201) {
          await outboxDao.removeById(record.id);
          pushed++;
        } else {
          logHttpError(
            title: 'فشل رفع ${record.entity}',
            statusCode: response.statusCode,
            responseBody: response.body,
            source: 'sync:push_batch',
          );
          failedIds.add(record.id);
        }
      } catch (e) {
        debugPrint('⚠️ Push record error: $e');
        failedIds.add(record.id);
      }
    }

    return (pushed: pushed, failedIds: failedIds);
  }

  /// Get vector clock for a record.
  ///
  /// يقرأ ساعة التوجيه من الجدول المحلي عبر [VectorClockService] —
  /// وإذا لم يجدها يعيد ساعة دنيا لهذا الجهاز.
  Future<String> rowVectorClock(String entity, String localUuid) async {
    try {
      final clock = await vectorClockService.getVectorClock(entity, localUuid);
      if (clock.isNotEmpty) return jsonEncode(clock);
    } catch (_) {
      // سقوط إلى الساعة الدنيا أدناه
    }
    // Return minimal clock for this device
    return jsonEncode(<String, dynamic>{_deviceId ?? 'unknown': 1});
  }

  /// Push all local data to server
  Future<Map<String, int>> pushAllLocalData() async {
    if (_token == null) return {};

    final result = <String, int>{};

    // Push each entity type
    final entities = [
      'devices',
      'rooms',
      'bookings',
      'booking_nights',
      'guests',
      'payments',
      'payment_methods',
      'expenses',
      'salary_cycles',
      'salary_payments',
      'salary_withdrawals',
    ];

    for (final entity in entities) {
      try {
        final count = await pushOutbox();
        result[entity] = count;
      } catch (e) {
        debugPrint('⚠️ Push $entity error: $e');
        result[entity] = 0;
      }
    }

    return result;
  }
}

/// Outbox record model — نموذج نقل مستقل عن Drift لطلبات الـ push.
class OutboxRecord {
  OutboxRecord({
    required this.id,
    required this.entity,
    required this.op,
    required this.localUuid,
    required this.payload,
    required this.clientTs,
    required this.idempotencyKey,
  });

  final int id;
  final String entity;
  final String op;
  final String localUuid;
  final Map<String, dynamic>? payload;
  final int clientTs;
  final String idempotencyKey;
}
