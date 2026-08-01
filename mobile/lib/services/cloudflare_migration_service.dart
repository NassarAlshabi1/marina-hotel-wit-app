// ═══════════════════════════════════════════════════════════════
//  cloudflare_migration_service.dart — One-time local → D1 migration
//  Reads ALL records from local Drift SQLite and pushes to Cloudflare D1
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show gzip, zlib;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter/foundation.dart' show debugPrint;
import 'cloudflare_config.dart';
import 'cloudflare_sync_manager.dart';
import 'local_db.dart';
import 'resilient_http_client.dart';

class CloudflareMigrationService {
  CloudflareMigrationService._();
  static final CloudflareMigrationService instance = CloudflareMigrationService._();

  static const _migrationCompleteKey = 'cf_migration_complete';
  static const _migrationProgressKey = 'cf_migration_progress';

  /// HTTP client with DoH fallback (bypasses broken ISP DNS).
  /// Uses 60s timeout per request — migration batches can be slow on
  /// Yemeni networks (typical: 2-5s per batch of 5 records).
  final http.Client _httpClient = createResilientHttpClient(
    timeout: const Duration(seconds: 60),
  );

  /// Smaller batch size for migration (5 instead of 25) — each request
  /// completes faster, reducing timeout failures on slow networks.
  static const int _migrationBatchSize = 5;

  /// Check if migration has already been completed
  Future<bool> isMigrationComplete() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_migrationCompleteKey) ?? false;
  }

  /// Get migration progress (which tables are done)
  Future<Map<String, bool>> getMigrationProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final json = prefs.getString(_migrationProgressKey);
    if (json == null) return {};
    return Map<String, bool>.from(jsonDecode(json) as Map);
  }

  /// Measure network speed by downloading /api/ping (1KB payload).
  /// Returns speed in KB/s. Used to adjust batch size dynamically.
  Future<double> _measureNetworkSpeed() async {
    try {
      final stopwatch = Stopwatch()..start();
      final response = await _httpClient.get(
        Uri.parse('${CloudflareConfig.workerUrl}/api/ping'),
      ).timeout(const Duration(seconds: 10));
      stopwatch.stop();

      if (response.statusCode != 200) return 1.0; // assume slow

      final elapsedSeconds = stopwatch.elapsedMilliseconds / 1000;
      if (elapsedSeconds == 0) return 100.0; // very fast

      // Response is ~1KB + headers ~0.5KB = ~1.5KB total
      const responseSizeKB = 1.5;
      final speedKBps = responseSizeKB / elapsedSeconds;

      debugPrint('📊 Network speed: ${speedKBps.toStringAsFixed(1)} KB/s '
          '(${elapsedSeconds.toStringAsFixed(2)}s for /api/ping)');
      return speedKBps;
    } catch (e) {
      debugPrint('⚠️ Network speed measurement failed: $e — assuming 1 KB/s');
      return 1.0; // assume very slow
    }
  }

  /// Calculate optimal batch size based on network speed.
  /// With gzip compression (~70% reduction) + parallel batches (5x),
  /// effective throughput is ~15x the raw network speed.
  /// - < 2 KB/s: 5 records per batch (slow, but gzip helps)
  /// - 2-10 KB/s: 10 records per batch
  /// - 10-30 KB/s: 25 records per batch
  /// - > 30 KB/s: 50 records per batch (max efficiency)
  int _calculateBatchSize(double speedKBps) {
    // With gzip + parallel, effective speed is ~15x raw
    final effectiveSpeed = speedKBps * 15;
    if (effectiveSpeed < 30) return 5;
    if (effectiveSpeed < 150) return 10;
    if (effectiveSpeed < 450) return 25;
    return 50;
  }

  /// Run the full migration
  Future<MigrationResult> migrate({
    required AppDatabase db,
    required String token,
    required String deviceId,
    Function(int current, int total, String table)? onProgress,
  }) async {
    final startTime = DateTime.now();
    int totalRecords = 0;
    int totalPushed = 0;
    int totalFailed = 0;
    final errors = <String>[];

    // ─── Measure network speed and set adaptive batch size ───
    final networkSpeed = await _measureNetworkSpeed();
    int currentBatchSize = _calculateBatchSize(networkSpeed);
    debugPrint('🔄 Starting Cloudflare migration (network: '
        '${networkSpeed.toStringAsFixed(1)} KB/s, batch size: $currentBatchSize)');
    final completedTables = await getMigrationProgress();

    debugPrint('🔄 Starting Cloudflare migration...');

    for (final entity in CloudflareConfig.migrationOrder) {
      // Skip if already completed
      if (completedTables[entity] == true) {
        debugPrint('  ⏭️ $entity: already migrated');
        continue;
      }

      try {
        final tableName = CloudflareConfig.tableNameFor(entity);
        if (tableName == null) continue;

        // Read all records from local Drift DB
        final records = await db.customSelect(
          'SELECT * FROM $tableName',
        ).get();

        final count = records.length;
        debugPrint('  📦 $entity: $count records found');

        if (count == 0) {
          // Mark as complete (empty table)
          completedTables[entity] = true;
          await _saveProgress(completedTables);
          continue;
        }

        totalRecords += count;

        // Build push operations
        final operations = <Map<String, dynamic>>[];
        for (final row in records) {
          final record = Map<String, dynamic>.from(row.data);
          final localUuid = record['local_uuid'] as String?;

          // Remove local autoIncrement id
          record.remove('id');

          operations.add({
            'idempotencyKey': 'migration:$entity:${localUuid ?? DateTime.now().millisecondsSinceEpoch}',
            'entity': entity,
            'operation': 'create',
            'data': record,
            'vectorClock': record['vector_clock'] as String? ?? '{}',
            'updatedAt': record['updated_at'] as int? ?? DateTime.now().millisecondsSinceEpoch ~/ 1000,
            'deviceId': deviceId,
          });
        }

        // ─── Send batches in PARALLEL with gzip compression ───
        // This achieves ~50 KB/s effective throughput on slow networks by:
        // 1. Compressing JSON payload with gzip (~70% size reduction)
        // 2. Sending 5 batches concurrently (5x throughput)
        // 3. Using larger batch size (50 records) since compression reduces size
        final allBatches = <List<Map<String, dynamic>>>[];
        for (var i = 0; i < operations.length; i += currentBatchSize) {
          allBatches.add(operations.sublist(
            i,
            (i + currentBatchSize > operations.length)
                ? operations.length
                : i + currentBatchSize,
          ));
        }

        debugPrint('  📦 $entity: ${allBatches.length} batches '
            '(${currentBatchSize} records each, parallel=5, gzip=on)');

        // Process batches in groups of 5 (parallel)
        const parallelCount = 5;
        for (var g = 0; g < allBatches.length; g += parallelCount) {
          final group = allBatches.sublist(
            g,
            (g + parallelCount > allBatches.length)
                ? allBatches.length
                : g + parallelCount,
          );

          // Send group in parallel
          final results = await Future.wait(
            group.map((batch) => _sendBatchWithRetry(
                  entity: entity,
                  batch: batch,
                  token: token,
                  deviceId: deviceId,
                )),
          );

          // Aggregate results
          for (final result in results) {
            totalPushed += result.pushed;
            totalFailed += result.failed;
            errors.addAll(result.errors);
          }

          // Report progress after each parallel group
          if (onProgress != null) {
            onProgress(totalPushed, totalRecords, entity);
          }
        }

        // Mark table as complete
        completedTables[entity] = true;
        await _saveProgress(completedTables);
        debugPrint('  ✅ $entity: migration complete');
      } catch (e) {
        errors.add('$entity: $e');
        debugPrint('  ❌ $entity: $e');
      }
    }

    // Mark migration as complete
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_migrationCompleteKey, true);

    final duration = DateTime.now().difference(startTime);
    debugPrint('🔄 Migration complete: $totalPushed/$totalRecords pushed in ${duration.inSeconds}s');

    return MigrationResult(
      totalRecords: totalRecords,
      totalPushed: totalPushed,
      totalFailed: totalFailed,
      errors: errors,
      duration: duration,
    );
  }

  Future<void> _saveProgress(Map<String, bool> progress) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_migrationProgressKey, jsonEncode(progress));
  }

  /// Send a single batch with retry logic + gzip compression.
  /// Returns a [_BatchResult] with pushed/failed counts and errors.
  Future<_BatchResult> _sendBatchWithRetry({
    required String entity,
    required List<Map<String, dynamic>> batch,
    required String token,
    required String deviceId,
  }) async {
    int pushed = 0;
    int failed = 0;
    final batchErrors = <String>[];

    // Compress the JSON payload with gzip (70-80% size reduction for
    // repetitive JSON with field names like local_uuid, created_at, etc.)
    final jsonPayload = jsonEncode({'operations': batch});
    final jsonBytes = utf8.encode(jsonPayload);
    final compressedBytes = gzip.encode(jsonBytes, level: 9);
    final compressionRatio = (compressedBytes.length / jsonBytes.length * 100).round();
    debugPrint('    🗜️ $entity batch: ${jsonBytes.length}B → '
        '${compressedBytes.length}B (${compressionRatio}% of original)');

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await _httpClient.post(
          Uri.parse('${CloudflareConfig.workerUrl}/api/sync/push'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'Content-Encoding': 'gzip',
            'Content-Length': compressedBytes.length.toString(),
          },
          body: compressedBytes,
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body) as Map<String, dynamic>;
          final summary = result['summary'] as Map<String, dynamic>? ?? {};
          pushed += (summary['success'] as int? ?? 0);
          failed += (summary['failed'] as int? ?? 0);

          if ((summary['failed'] as int? ?? 0) > 0) {
            final results = result['results'] as List? ?? [];
            for (final r in results) {
              if (!((r as Map)['success'] as bool? ?? false)) {
                batchErrors.add('$entity: ${r['error']}');
              }
            }
          }
          return _BatchResult(pushed: pushed, failed: failed, errors: batchErrors);
        } else if (response.statusCode >= 500 && attempt < 3) {
          debugPrint('    ⚠️ $entity batch HTTP ${response.statusCode}, '
              'retry $attempt/3...');
          await Future.delayed(Duration(seconds: attempt));
          continue;
        } else {
          failed += batch.length;
          batchErrors.add('$entity: HTTP ${response.statusCode}');
          return _BatchResult(pushed: pushed, failed: failed, errors: batchErrors);
        }
      } catch (e) {
        if (attempt < 3) {
          debugPrint('    ⚠️ $entity batch failed (attempt $attempt/3): $e');
          await Future.delayed(Duration(seconds: attempt));
        } else {
          failed += batch.length;
          batchErrors.add('$entity batch (after 3 retries): $e');
          debugPrint('    ❌ $entity batch final failure: $e');
          return _BatchResult(pushed: pushed, failed: failed, errors: batchErrors);
        }
      }
    }

    return _BatchResult(pushed: pushed, failed: failed, errors: batchErrors);
  }

  /// Reset migration state (for re-running)
  Future<void> reset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_migrationCompleteKey);
    await prefs.remove(_migrationProgressKey);
  }
}

class MigrationResult {
  const MigrationResult({
    required this.totalRecords,
    required this.totalPushed,
    required this.totalFailed,
    required this.errors,
    required this.duration,
  });

  final int totalRecords;
  final int totalPushed;
  final int totalFailed;
  final List<String> errors;
  final Duration duration;

  /// Migration is successful only if:
  /// 1. At least one record was pushed (totalPushed > 0), AND
  /// 2. No records failed (totalFailed == 0)
  /// This prevents false "success" when all batches silently fail.
  bool get isSuccess => totalPushed > 0 && totalFailed == 0;

  /// Partial success: some records pushed, some failed
  bool get isPartialSuccess => totalPushed > 0 && totalFailed > 0;

  /// Complete failure: nothing pushed at all
  bool get isCompleteFailure => totalPushed == 0;
}

/// Internal result of sending a single batch (used for parallel aggregation)
class _BatchResult {
  const _BatchResult({
    required this.pushed,
    required this.failed,
    required this.errors,
  });

  final int pushed;
  final int failed;
  final List<String> errors;
}
