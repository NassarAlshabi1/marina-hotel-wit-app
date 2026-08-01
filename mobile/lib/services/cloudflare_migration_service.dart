// ═══════════════════════════════════════════════════════════════
//  cloudflare_migration_service.dart — One-time local → D1 migration
//  Reads ALL records from local Drift SQLite and pushes to Cloudflare D1
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io' show gzip, zlib, GZipCodec;
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
  /// With SQL (instead of JSON) + gzip + 15 parallel batches,
  /// effective throughput is ~30x the raw network speed.
  /// SQL is ~40% smaller than JSON, and 15 parallel requests give 3x more
  /// throughput than 5 parallel.
  /// - < 2 KB/s: 10 records per batch (was 5)
  /// - 2-10 KB/s: 25 records per batch
  /// - 10-30 KB/s: 50 records per batch
  /// - > 30 KB/s: 100 records per batch (max efficiency)
  int _calculateBatchSize(double speedKBps) {
    // With SQL + gzip + 15 parallel, effective speed is ~30x raw
    final effectiveSpeed = speedKBps * 30;
    if (effectiveSpeed < 60) return 10;
    if (effectiveSpeed < 300) return 25;
    if (effectiveSpeed < 900) return 50;
    return 100;
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

        // ─── Build SQL INSERT statements (much faster than JSON) ───
        // Instead of sending JSON operations (with idempotencyKey, entity,
        // operation, data, vectorClock, updatedAt, deviceId wrappers),
        // we send raw SQL INSERT statements directly.
        //
        // JSON size per record: ~500 bytes (with wrapper fields)
        // SQL size per record:  ~200 bytes (just VALUES)
        // + gzip compression:   ~60 bytes per record transmitted
        //
        // This gives ~8x size reduction + D1 native batch insert speed.
        final allRecords = <Map<String, dynamic>>[];
        for (final row in records) {
          final record = Map<String, dynamic>.from(row.data);
          record.remove('id'); // Remove local autoIncrement id
          allRecords.add(record);
        }

        // Split records into batches of currentBatchSize
        final allBatches = <List<Map<String, dynamic>>>[];
        for (var i = 0; i < allRecords.length; i += currentBatchSize) {
          allBatches.add(allRecords.sublist(
            i,
            (i + currentBatchSize > allRecords.length)
                ? allRecords.length
                : i + currentBatchSize,
          ));
        }

        debugPrint('  📦 $entity: ${allBatches.length} SQL batches '
            '(${currentBatchSize} records each, parallel=15, gzip=on)');

        // Process batches in groups of 15 (parallel) for maximum throughput
        const parallelCount = 15;
        for (var g = 0; g < allBatches.length; g += parallelCount) {
          final group = allBatches.sublist(
            g,
            (g + parallelCount > allBatches.length)
                ? allBatches.length
                : g + parallelCount,
          );

          // Send group in parallel — each batch becomes one SQL INSERT
          // statement with multiple VALUES, gzipped, sent to /api/sync/migrate
          final results = await Future.wait(
            group.map((batch) => _sendSqlBatchWithRetry(
                  entity: entity,
                  tableName: tableName,
                  batch: batch,
                  token: token,
                  db: db,
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

  /// Build a SQL INSERT statement with multiple VALUES from a batch of records.
  /// Uses INSERT OR IGNORE for idempotency (duplicate local_uuid = skip).
  /// All values are properly SQL-escaped to prevent injection.
  /// Fills NOT NULL columns (without defaults) with empty values to prevent
  /// silent constraint violations.
  Future<String> _buildSqlInsert({
    required String tableName,
    required List<Map<String, dynamic>> batch,
    required AppDatabase db,
  }) async {
    if (batch.isEmpty) return '';

    // ─── Read column metadata from local Drift DB (same schema as D1) ───
    final columnInfo = await db.customSelect(
      'PRAGMA table_info($tableName)',
    ).get();

    // Build map: column name → default value (for NOT NULL without default)
    final notNullDefaults = <String, dynamic>{};
    final allColumns = <String>[];
    for (final col in columnInfo) {
      final name = col.data['name'] as String;
      final notnull = col.data['notnull'] as int;
      final dfltValue = col.data['dflt_value'];
      final type = col.data['type'] as String? ?? 'TEXT';
      allColumns.add(name);

      // If NOT NULL and no default (and not autoIncrement id), fill it
      if (notnull == 1 && dfltValue == null && name != 'id') {
        final typeLower = type.toLowerCase();
        if (typeLower == 'integer' || typeLower == 'real' || typeLower == 'numeric') {
          notNullDefaults[name] = 0;
        } else {
          notNullDefaults[name] = '';
        }
      }
    }

    // Build the column list: union of record columns + NOT NULL defaults
    final recordColumns = batch.first.keys.toSet();
    final requiredColumns = <String>[];
    for (final col in allColumns) {
      if (col == 'id') continue; // Skip autoIncrement
      if (recordColumns.contains(col) || notNullDefaults.containsKey(col)) {
        requiredColumns.add(col);
      }
    }
    // Add any record columns not in schema (shouldn't happen, but be safe)
    for (final col in recordColumns) {
      if (col != 'id' && !requiredColumns.contains(col)) {
        requiredColumns.add(col);
      }
    }

    final columnsStr = requiredColumns.join(', ');

    // Build VALUES clauses with proper escaping + fill defaults
    final valuesClauses = <String>[];
    for (final record in batch) {
      final values = requiredColumns.map((col) {
        if (record.containsKey(col) && record[col] != null) {
          return _escapeSqlValue(record[col]);
        }
        // Fill with default value for NOT NULL columns
        if (notNullDefaults.containsKey(col)) {
          return _escapeSqlValue(notNullDefaults[col]);
        }
        return 'NULL';
      });
      valuesClauses.add('(${values.join(', ')})');
    }

    return 'INSERT OR IGNORE INTO $tableName ($columnsStr) VALUES\n'
        '${valuesClauses.join(',\n')};';
  }

  /// Escape a Dart value for SQL insertion.
  String _escapeSqlValue(dynamic value) {
    if (value == null) return 'NULL';
    if (value is bool) return value ? '1' : '0';
    if (value is int || value is double) return value.toString();
    if (value is String) {
      // Escape single quotes by doubling them (SQL standard)
      final escaped = value.replaceAll("'", "''");
      return "'$escaped'";
    }
    if (value is List || value is Map) {
      // Serialize complex types as JSON strings
      final jsonStr = jsonEncode(value);
      final escaped = jsonStr.replaceAll("'", "''");
      return "'$escaped'";
    }
    // Fallback: treat as string
    final escaped = value.toString().replaceAll("'", "''");
    return "'$escaped'";
  }

  /// Send a single SQL batch with retry logic + gzip compression.
  /// Uses the fast /api/sync/migrate endpoint (raw SQL INSERT).
  Future<_BatchResult> _sendSqlBatchWithRetry({
    required String entity,
    required String tableName,
    required List<Map<String, dynamic>> batch,
    required String token,
    required AppDatabase db,
  }) async {
    int pushed = 0;
    int failed = 0;
    final batchErrors = <String>[];

    // Build SQL INSERT statement with all batch records
    final sql = await _buildSqlInsert(
      tableName: tableName,
      batch: batch,
      db: db,
    );
    if (sql.isEmpty) {
      return _BatchResult(pushed: 0, failed: 0, errors: []);
    }

    // Compress SQL with gzip (even better ratio than JSON — SQL is very
    // repetitive: column names appear once, VALUES are structured)
    final sqlBytes = utf8.encode(sql);
    final gzipCodec = GZipCodec(level: 9);
    final compressedBytes = gzipCodec.encode(sqlBytes);
    final compressionRatio = sqlBytes.isEmpty
        ? 100
        : (compressedBytes.length / sqlBytes.length * 100).round();
    debugPrint('    🗜️ $entity SQL batch: ${sqlBytes.length}B → '
        '${compressedBytes.length}B (${compressionRatio}% of original, '
        '${batch.length} records)');

    for (var attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await _httpClient.post(
          Uri.parse('${CloudflareConfig.workerUrl}/api/sync/migrate'),
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/sql',
            'Content-Encoding': 'gzip',
            'Content-Length': compressedBytes.length.toString(),
          },
          body: compressedBytes,
        );

        if (response.statusCode == 200) {
          final result = jsonDecode(response.body) as Map<String, dynamic>;
          pushed += (result['rowsInserted'] as int? ?? 0);
          final errorList = result['errors'] as List? ?? [];
          if (errorList.isNotEmpty) {
            failed += batch.length - pushed;
            for (final e in errorList) {
              batchErrors.add('$entity: $e');
            }
          }
          return _BatchResult(pushed: pushed, failed: failed, errors: batchErrors);
        } else if (response.statusCode >= 500 && attempt < 3) {
          debugPrint('    ⚠️ $entity SQL batch HTTP ${response.statusCode}, '
              'retry $attempt/3...');
          await Future.delayed(Duration(seconds: attempt));
          continue;
        } else {
          failed += batch.length;
          batchErrors.add('$entity: HTTP ${response.statusCode} — ${response.body}');
          return _BatchResult(pushed: pushed, failed: failed, errors: batchErrors);
        }
      } catch (e) {
        if (attempt < 3) {
          debugPrint('    ⚠️ $entity SQL batch failed (attempt $attempt/3): $e');
          await Future.delayed(Duration(seconds: attempt));
        } else {
          failed += batch.length;
          batchErrors.add('$entity SQL batch (after 3 retries): $e');
          debugPrint('    ❌ $entity SQL batch final failure: $e');
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
