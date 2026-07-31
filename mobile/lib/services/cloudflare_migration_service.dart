// ═══════════════════════════════════════════════════════════════
//  cloudflare_migration_service.dart — One-time local → D1 migration
//  Reads ALL records from local Drift SQLite and pushes to Cloudflare D1
// ═══════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart' show dlog, dwarn, derr;
import 'cloudflare_config.dart';
import 'cloudflare_sync_manager.dart';
import 'local_db.dart';

class CloudflareMigrationService {
  CloudflareMigrationService._();
  static final CloudflareMigrationService instance = CloudflareMigrationService._();

  static const _migrationCompleteKey = 'cf_migration_complete';
  static const _migrationProgressKey = 'cf_migration_progress';

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

    dlog('🔄 Starting Cloudflare migration...');

    for (final entity in CloudflareConfig.migrationOrder) {
      // Skip if already completed
      if (completedTables[entity] == true) {
        dlog('  ⏭️ $entity: already migrated');
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
        dlog('  📦 $entity: $count records found');

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

        // Send in batches
        for (var i = 0; i < operations.length; i += CloudflareConfig.batchSize) {
          final batch = operations.sublist(
            i,
            (i + CloudflareConfig.batchSize > operations.length)
                ? operations.length
                : i + CloudflareConfig.batchSize,
          );

          final response = await http.post(
            Uri.parse('${CloudflareConfig.workerUrl}/api/sync/push'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'operations': batch}),
          ).timeout(const Duration(seconds: 30));

          if (response.statusCode == 200) {
            final result = jsonDecode(response.body) as Map<String, dynamic>;
            final summary = result['summary'] as Map<String, dynamic>? ?? {};
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
          } else {
            totalFailed += batch.length;
            errors.add('$entity: HTTP ${response.statusCode}');
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
        dlog('  ✅ $entity: migration complete');
      } catch (e) {
        errors.add('$entity: $e');
        dlog('  ❌ $entity: $e');
      }
    }

    // Mark migration as complete
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_migrationCompleteKey, true);

    final duration = DateTime.now().difference(startTime);
    dlog('🔄 Migration complete: $totalPushed/$totalRecords pushed in ${duration.inSeconds}s');

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
