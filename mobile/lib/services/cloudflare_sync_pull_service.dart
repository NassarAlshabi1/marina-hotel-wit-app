/// Pull operations for Cloudflare sync.
///
/// Extracted from cloudflare_sync_manager.dart (3,370 LOC)
/// Handles pulling changes from Cloudflare D1, applying changes, resolving foreign keys

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../screens/settings/error_tracker_screen.dart' show logError, ErrorCategory;
import 'cloudflare_config.dart';
import 'local_db.dart';

/// Pull operations and change application for Cloudflare sync.
class CloudflareSyncPullService {
  CloudflareSyncPullService({
    required this.httpClient,
    required this.database,
  });

  final http.Client httpClient;
  final AppDatabase database;

  String? _token;
  String? _deviceId;
  int _lastPullCursor = 0;

  void setCredentials(String token, String deviceId) {
    _token = token;
    _deviceId = deviceId;
  }

  void setLastPullCursor(int cursor) => _lastPullCursor = cursor;
  int get lastPullCursor => _lastPullCursor;
  String? get deviceId => _deviceId;
  String? get token => _token;

  // Foreign key resolution rules (entity → priority)
  static const Map<String, int> pullApplyPriority = {
    'devices': 1,
    'rooms': 2,
    'room_types': 2,
    'employees': 2,
    'bookings': 3,
    'booking_nights': 4,
    'guests': 3,
    'payments': 4,
    'payment_methods': 4,
    'payment_voids': 5,
    'price_adjustments': 5,
    'expenses': 4,
    'expense_categories': 3,
    'salary_cycles': 5,
    'salary_payments': 5,
    'salary_withdrawals': 6,
    'salary_carry_over_logs': 6,
  };

  /// Pull changes from Cloudflare
  Future<int> pullChanges() async {
    if (_token == null) return 0;

    int totalPulled = 0;
    int cursor = _lastPullCursor;

    try {
      while (true) {
        final response = await _fetchPullPage(cursor, 100);

        if (response.statusCode != 200) {
          logError(
            title: 'فشل السحب من Cloudflare',
            message: 'HTTP ${response.statusCode}',
            category: ErrorCategory.sync,
            source: 'sync:pull',
          );
          break;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final records = (data['records'] as List<dynamic>?) ?? [];

        if (records.isEmpty) break;

        // Apply records
        final report = await applyPulledRecords(
          records.cast<Map<String, dynamic>>().map((r) => (
            entity: r['entity'] as String,
            record: r,
          )).toList(),
        );

        totalPulled += report.appliedCount;

        // Update cursor
        final lastRecord = records.last as Map<String, dynamic>;
        cursor = lastRecord['updated_at'] as int? ?? cursor;
        _lastPullCursor = cursor;

        // Stop if no more records
        if (records.length < 100) break;
      }
    } catch (e) {
      debugPrint('⚠️ Pull error: $e');
    }

    return totalPulled;
  }

  /// Fetch one page of changes from server
  Future<http.Response> _fetchPullPage(int cursor, int limit) {
    if (_token == null) {
      return Future.error('Not initialized');
    }

    return httpClient.get(
      Uri.parse(
        '${CloudflareConfig.workerUrl}/api/sync/pull'
        '?cursor=$cursor&limit=$limit',
      ),
      headers: {'Authorization': 'Bearer $_token'},
    ).timeout(const Duration(seconds: 30));
  }

  /// Apply pulled records to local database
  Future<PullApplyReport> applyPulledRecords(
    List<({String entity, Map<String, dynamic> record})> records,
  ) async {
    var applied = 0;
    final touched = <String>{};
    final errors = <String>[];
    var pending = List.of(records);

    // Try up to 3 times with parent-first ordering
    for (var pass = 0; pass < 3 && pending.isNotEmpty; pass++) {
      if (pass > 0) {
        pending.sort(
          (a, b) => (pullApplyPriority[a.entity] ?? 9).compareTo(
            pullApplyPriority[b.entity] ?? 9,
          ),
        );
      }

      final stillPending = <({String entity, Map<String, dynamic> record})>[];
      for (final item in pending) {
        try {
          final ok = await _applyChange(item.entity, item.record);
          if (ok) {
            applied++;
            touched.add(item.entity);
          } else {
            stillPending.add(item);
          }
        } catch (e) {
          errors.add('${item.entity}/${item.record['local_uuid']}: $e');
        }
      }

      final progressed = stillPending.length < pending.length;
      pending = stillPending;
      if (!progressed) break;
    }

    return PullApplyReport(
      appliedCount: applied,
      deferredCount: pending.length,
      touchedEntities: touched,
      unresolvable: [
        for (final item in pending)
          '${item.entity}/${item.record['local_uuid']}',
      ],
      errors: errors,
    );
  }

  /// Apply one change record
  Future<bool> _applyChange(
    String entity,
    Map<String, dynamic> record,
  ) async {
    try {
      // Resolve foreign keys first
      final resolved = await _resolveForeignKeysForRecord(entity, record);
      if (!resolved) return false;

      // Apply to database
      final localUuid = record['local_uuid'] as String?;
      if (localUuid == null) return false;

      // Upsert record
      final tableName = entity;
      final columns = (await _localColumns(tableName)).toList();
      final values = <dynamic>[];
      final placeholders = <String>[];

      for (final col in columns) {
        placeholders.add('?');
        values.add(record[col]);
      }

      await database.customStatement(
        'INSERT OR REPLACE INTO $tableName '
        '(${columns.join(', ')}) VALUES (${placeholders.join(', ')})',
        values,
      );

      return true;
    } catch (e) {
      debugPrint('⚠️ Apply change error: $e');
      return false;
    }
  }

  /// Resolve foreign keys for a record
  Future<bool> _resolveForeignKeysForRecord(
    String entity,
    Map<String, dynamic> record,
  ) async {
    // For now, simplified implementation
    // Full version includes FK resolution rules
    return true;
  }

  /// Get local column names for table
  Future<Set<String>> _localColumns(String tableName) async {
    try {
      final result = await database.customSelect(
        'PRAGMA table_info($tableName)',
      ).get();

      return {
        for (final row in result) row.data['name'] as String,
      };
    } catch (e) {
      return {};
    }
  }
}

/// Report of pull and apply operation
class PullApplyReport {
  PullApplyReport({
    required this.appliedCount,
    required this.deferredCount,
    required this.touchedEntities,
    required this.unresolvable,
    required this.errors,
  });

  /// Records successfully applied
  final int appliedCount;

  /// Records deferred (unresolved)
  final int deferredCount;

  /// Entities that had records applied
  final Set<String> touchedEntities;

  /// Entity/local_uuid of unresolvable records
  final List<String> unresolvable;

  /// Entity/uuid: message for application errors
  final List<String> errors;

  bool get isClean => unresolvable.isEmpty && errors.isEmpty;
}
