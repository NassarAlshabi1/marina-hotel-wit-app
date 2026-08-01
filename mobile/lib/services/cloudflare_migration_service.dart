// ═══════════════════════════════════════════════════════════════
//  cloudflare_migration_service.dart — One-time local → D1 migration
//  Reads ALL records from local Drift SQLite and pushes to Cloudflare D1
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';

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

        // Send in batches (smaller batch size for slow networks)
        for (var i = 0; i < operations.length; i += _migrationBatchSize) {
          final batch = operations.sublist(
            i,
            (i + _migrationBatchSize > operations.length)
                ? operations.length
                : i + _migrationBatchSize,
          );

          // Retry each batch up to 3 times for transient failures
          // (timeouts, network blips). On final failure, record errors.
          bool batchSucceeded = false;
          for (var attempt = 1; attempt <= 3 && !batchSucceeded; attempt++) {
            try {
              final response = await _httpClient.post(
                Uri.parse('${CloudflareConfig.workerUrl}/api/sync/push'),
                headers: {
                  'Authorization': 'Bearer $token',
                  'Content-Type': 'application/json',
                },
                body: jsonEncode({'operations': batch}),
              );

              if (response.statusCode == 200) {
                final result =
                    jsonDecode(response.body) as Map<String, dynamic>;
                final summary =
                    result['summary'] as Map<String, dynamic>? ?? {};
                totalPushed += (summary['success'] as int? ?? 0);
                totalFailed += (summary['failed'] as int? ?? 0);

                if ((summary['failed'] as int? ?? 0) > 0) {
                  final results = result['results'] as List? ?? [];
                  for (final r in results) {
                    if (!((r as Map)['success'] as bool? ?? false)) {
                      errors.add('$entity: ${r['error']}');
                    }
                  }
                }
                batchSucceeded = true;
              } else {
                // Non-200: retry only on 5xx server errors
                if (response.statusCode >= 500 && attempt < 3) {
                  debugPrint(
                    '  ⚠️ $entity batch HTTP ${response.statusCode}, retry $attempt/3...',
                  );
                  await Future.delayed(Duration(seconds: attempt * 2));
                  continue;
                }
                totalFailed += batch.length;
                errors.add('$entity: HTTP ${response.statusCode}');
                batchSucceeded = true; // Don't retry client errors
              }
            } catch (e) {
              if (attempt < 3) {
                debugPrint(
                  '  ⚠️ $entity batch failed (attempt $attempt/3): $e — retrying...',
                );
                await Future.delayed(Duration(seconds: attempt * 2));
              } else {
                // Final attempt failed
                totalFailed += batch.length;
                errors.add('$entity batch (after 3 retries): $e');
                debugPrint('  ❌ $entity batch final failure: $e');
                batchSucceeded = true; // Move on to next batch
              }
            }
          }

          // Report progress
          if (onProgress != null) {
            onProgress(totalPushed, totalRecords, entity);
          }

          // Small delay to avoid D1 rate limits
          await Future.delayed(const Duration(milliseconds: 100));
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

  bool get isSuccess => totalFailed == 0;
}
