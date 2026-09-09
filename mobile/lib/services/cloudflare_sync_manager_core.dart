/// Core orchestrator for Cloudflare sync operations.
///
/// Extracted from cloudflare_sync_manager.dart (3,370 LOC) as Phase 3 Week 2.
/// Coordinates device registration, push, and pull services while handling
/// record application with FK resolution, quarantine management, and statistics.
///
/// This module is the single source of truth for:
/// - Record apply logic (FK resolution, column filtering, tombstones)
/// - Entity detection from raw record fields
/// - Quarantine management for orphan records
/// - Pull-priority ordering for parent-first application
/// - Sync statistics tracking
library;

import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'booking_derived_fields_service.dart';
import 'cloudflare_config.dart';
import 'cloudflare_sync_device_service.dart';
import 'cloudflare_sync_pull_service.dart';
import 'cloudflare_sync_push_service.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'remote_change_notifier.dart';
import 'sync_core/smart_conflict_resolver.dart';
import 'sync_enums.dart';
import 'vector_clock_service.dart';

// ─── FK Rules ─────────────────────────────────────────────────

enum FkKind { numericPointer, naturalKey }

class FkRule {
  const FkRule({
    required this.entity,
    required this.column,
    required this.kind,
    required this.parentTable,
    required this.parentKeyColumn,
    this.nullable = false,
    this.uuidCacheColumn,
    this.legacyServerBookingId = false,
    this.nullWhenUnresolvable = false,
  });

  final String entity;
  final String column;
  final FkKind kind;
  final String parentTable;
  final String parentKeyColumn;
  final bool nullable;
  final String? uuidCacheColumn;
  final bool legacyServerBookingId;
  final bool nullWhenUnresolvable;
}

const List<FkRule> fkRules = [
  FkRule(
    entity: 'bookings',
    column: 'room_number',
    kind: FkKind.naturalKey,
    parentTable: 'rooms',
    parentKeyColumn: 'room_number',
  ),
  FkRule(
    entity: 'booking_nights',
    column: 'booking_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'booking_uuid_cache',
    legacyServerBookingId: true,
  ),
  FkRule(
    entity: 'booking_notes',
    column: 'booking_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    legacyServerBookingId: true,
  ),
  FkRule(
    entity: 'payments',
    column: 'booking_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    nullable: true,
    uuidCacheColumn: 'booking_uuid_cache',
    legacyServerBookingId: true,
  ),
  FkRule(
    entity: 'payments',
    column: 'cash_transaction_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'cash_transactions',
    parentKeyColumn: 'id',
    nullable: true,
    nullWhenUnresolvable: true,
  ),
  FkRule(
    entity: 'booking_price_adjustments',
    column: 'booking_local_id',
    kind: FkKind.numericPointer,
    parentTable: 'bookings',
    parentKeyColumn: 'id',
    nullable: true,
    uuidCacheColumn: 'booking_uuid',
    legacyServerBookingId: true,
  ),
  FkRule(
    entity: 'booking_price_adjustments',
    column: 'booking_local_uuid',
    kind: FkKind.naturalKey,
    parentTable: 'bookings',
    parentKeyColumn: 'local_uuid',
  ),
  FkRule(
    entity: 'salary_cycles',
    column: 'employee_id',
    kind: FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
  ),
  FkRule(
    entity: 'salary_payments',
    column: 'cycle_id',
    kind: FkKind.numericPointer,
    parentTable: 'salary_cycles',
    parentKeyColumn: 'id',
  ),
  FkRule(
    entity: 'salary_withdrawals',
    column: 'employee_id',
    kind: FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
  ),
  FkRule(
    entity: 'salary_carry_over_logs',
    column: 'employee_id',
    kind: FkKind.numericPointer,
    parentTable: 'employees',
    parentKeyColumn: 'id',
  ),
  FkRule(
    entity: 'inventory_transactions',
    column: 'item_id',
    kind: FkKind.numericPointer,
    parentTable: 'inventory_items',
    parentKeyColumn: 'id',
    uuidCacheColumn: 'item_local_uuid',
  ),
];

final Map<String, List<FkRule>> fkRulesByEntity = (() {
  final map = <String, List<FkRule>>{};
  for (final rule in fkRules) {
    map.putIfAbsent(rule.entity, () => <FkRule>[]).add(rule);
  }
  return map;
})();

// ─── Pull Apply Priority ──────────────────────────────────────

const Map<String, int> pullApplyPriority = {
  'rooms': 0,
  'employees': 1,
  'inventory_items': 1,
  'cash_transactions': 1,
  'bookings': 2,
  'payments': 2,
  'booking_nights': 3,
  'booking_notes': 3,
  'guest_infos': 3,
  'booking_price_adjustments': 3,
  'inventory_transactions': 4,
  'salary_cycles': 5,
  'salary_payments': 5,
  'salary_withdrawals': 6,
  'salary_carry_over_logs': 6,
};

// ─── Derived Refresh Entities ─────────────────────────────────

const Set<String> derivedRefreshEntities = {
  'bookings',
  'booking_nights',
  'payments',
  'price_adjustments',
  'booking_price_adjustments',
  'payment_voids',
};

// ─── SyncResult ───────────────────────────────────────────────

class SyncResult {
  SyncResult({
    required this.status,
    required this.timestamp,
    required this.duration,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
  });

  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
}

// ─── Pull Apply Report ────────────────────────────────────────

@visibleForTesting
class PullApplyReport {
  PullApplyReport({
    required this.appliedCount,
    required this.deferredCount,
    required this.touchedEntities,
    required this.unresolvable,
    required this.errors,
  });

  final int appliedCount;
  final int deferredCount;
  final Set<String> touchedEntities;
  final List<String> unresolvable;
  final List<String> errors;

  bool get isClean => unresolvable.isEmpty && errors.isEmpty;
}

// ─── Quarantine State ─────────────────────────────────────────

class QuarantineState {
  QuarantineState({
    Map<String, int>? blockCounts,
    Map<String, Map<String, dynamic>>? quarantinedRecords,
  })  : blockCounts = blockCounts ?? {},
        quarantinedRecords = quarantinedRecords ?? {};

  final Map<String, int> blockCounts;
  final Map<String, Map<String, dynamic>> quarantinedRecords;

  static const int blockThreshold = 3;
  static const String countsKey = 'cf_pull_orphan_block_counts';
  static const String recordsKey = 'cf_pull_quarantined_records';

  bool isQuarantined(String entity, String? localUuid) =>
      quarantinedRecords.containsKey(_identity(entity, localUuid));

  String _identity(String entity, String? localUuid) => '$entity/$localUuid';

  void loadFromPrefs(SharedPreferences prefs) {
    try {
      final countsRaw = prefs.getString(countsKey);
      if (countsRaw != null && countsRaw.isNotEmpty) {
        final decoded = jsonDecode(countsRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          blockCounts[key] = (value as num?)?.toInt() ?? 0;
        });
      }
      final recordsRaw = prefs.getString(recordsKey);
      if (recordsRaw != null && recordsRaw.isNotEmpty) {
        final decoded = jsonDecode(recordsRaw) as Map<String, dynamic>;
        decoded.forEach((key, value) {
          if (value is Map) {
            quarantinedRecords[key] = Map<String, dynamic>.from(value);
          }
        });
      }
    } catch (_) {}
  }

  Future<void> persist(SharedPreferences prefs) async {
    try {
      await prefs.setString(countsKey, jsonEncode(blockCounts));
      await prefs.setString(recordsKey, jsonEncode(quarantinedRecords));
    } catch (_) {}
  }

  void recordBlock(String entity, String? localUuid) {
    final id = _identity(entity, localUuid);
    blockCounts[id] = (blockCounts[id] ?? 0) + 1;
  }

  void quarantine(
    String entity,
    String? localUuid,
    Map<String, dynamic> record,
  ) {
    final id = _identity(entity, localUuid);
    quarantinedRecords[id] = <String, dynamic>{
      'entity': entity,
      'local_uuid': localUuid,
      'first_seen': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'updated_at': record['updated_at'],
    };
  }

  void clearRecord(String entity, String? localUuid) {
    final id = _identity(entity, localUuid);
    quarantinedRecords.remove(id);
    blockCounts.remove(id);
  }

  int get totalQuarantined => quarantinedRecords.length;
}

// ─── Sync Statistics ──────────────────────────────────────────

class SyncStats {
  int totalSyncs = 0;
  int successfulSyncs = 0;
  int failedSyncs = 0;
  int totalPushed = 0;
  int totalPulled = 0;
  DateTime? lastSyncTime;

  static const String _kSyncStatsKey = 'cf_sync_stats_v1';

  void loadFromPrefs(SharedPreferences prefs) {
    try {
      final raw = prefs.getString(_kSyncStatsKey);
      if (raw == null) return;
      final map = jsonDecode(raw) as Map<String, dynamic>;
      totalSyncs = (map['totalSyncs'] as num?)?.toInt() ?? 0;
      successfulSyncs = (map['successfulSyncs'] as num?)?.toInt() ?? 0;
      failedSyncs = (map['failedSyncs'] as num?)?.toInt() ?? 0;
      totalPushed = (map['totalPushed'] as num?)?.toInt() ?? 0;
      totalPulled = (map['totalPulled'] as num?)?.toInt() ?? 0;
      final lastMs = (map['lastSyncMs'] as num?)?.toInt();
      lastSyncTime = lastMs == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(lastMs);
    } catch (_) {}
  }

  Future<void> recordOutcome({
    required bool success,
    required int pushed,
    required int pulled,
    required DateTime startedAt,
  }) async {
    totalSyncs++;
    if (success) {
      successfulSyncs++;
    } else {
      failedSyncs++;
    }
    totalPushed += pushed;
    totalPulled += pulled;
    lastSyncTime = startedAt;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kSyncStatsKey,
        jsonEncode(<String, dynamic>{
          'totalSyncs': totalSyncs,
          'successfulSyncs': successfulSyncs,
          'failedSyncs': failedSyncs,
          'totalPushed': totalPushed,
          'totalPulled': totalPulled,
          'lastSyncMs': startedAt.millisecondsSinceEpoch,
        }),
      );
    } catch (_) {}
  }

  Map<String, dynamic> toMap({int outboxCount = 0, bool? fullSyncCompleted, String? lastError}) {
    return <String, dynamic>{
      'totalSyncs': totalSyncs,
      'successfulSyncs': successfulSyncs,
      'failedSyncs': failedSyncs,
      'totalRecordsPushed': totalPushed,
      'totalRecordsPulled': totalPulled,
      'totalConflicts': 0,
      'successRate': totalSyncs == 0 ? 0.0 : successfulSyncs / totalSyncs,
      'lastSyncTime': lastSyncTime?.toIso8601String(),
      'outboxCount': outboxCount,
      'fullSyncCompleted': fullSyncCompleted ?? false,
      'lastError': lastError,
    };
  }
}

// ─── CloudflareSyncManagerCore ────────────────────────────────

/// Core orchestrator that coordinates device, push, and pull services.
///
/// Handles record application with FK resolution, quarantine management,
/// entity detection, and statistics tracking. The main
/// CloudflareSyncManager delegates complex operations here.
class CloudflareSyncManagerCore {
  CloudflareSyncManagerCore({
    required AppDatabase database,
    required http.Client httpClient,
    required VectorClockService vectorClockService,
  })  : database = database,
        httpClient = httpClient,
        deviceService = CloudflareSyncDeviceService(
          httpClient: httpClient,
          database: database,
        ),
        pushService = CloudflareSyncPushService(
          httpClient: httpClient,
          database: database,
          vectorClockService: vectorClockService,
        ),
        pullService = CloudflareSyncPullService(
          httpClient: httpClient,
          database: database,
        ),
        vectorClockService = vectorClockService;

  final AppDatabase database;
  final http.Client httpClient;
  final CloudflareSyncDeviceService deviceService;
  final CloudflareSyncPushService pushService;
  final CloudflareSyncPullService pullService;
  final VectorClockService vectorClockService;

  // ─── State ──────────────────────────────────────────────────
  final QuarantineState quarantine = QuarantineState();
  final SyncStats stats = SyncStats();
  final Set<String> failedCollectionsInLastSync = <String>{};
  final Set<String> _fkLogSeen = <String>{};
  final Map<String, Set<String>> _localColumnsCache = <String, Set<String>>{};

  bool _derivedRefreshRunning = false;

  // ─── Initialize ─────────────────────────────────────────────

  /// Load persisted state from SharedPreferences.
  Future<void> loadPersistedState() async {
    final prefs = await SharedPreferences.getInstance();
    quarantine.loadFromPrefs(prefs);
    stats.loadFromPrefs(prefs);
  }

  /// Set credentials on all sub-services.
  void setCredentials(String token, String deviceId) {
    deviceService.setCredentials(token, deviceId);
    pushService.setCredentials(token, deviceId);
    pullService.setCredentials(token, deviceId);
  }

  /// Clear state between sync cycles.
  void resetCycleState() {
    failedCollectionsInLastSync.clear();
  }

  // ─── Entity Detection ───────────────────────────────────────

  /// Detect entity type from record fields.
  ///
  /// Returns null if the entity cannot be determined from the record.
  /// This is used when the server does not provide an `_entity` field.
  static String? detectEntity(Map<String, dynamic> record) {
    if (record.containsKey('room_number') && record.containsKey('price')) {
      return 'rooms';
    }
    if (record.containsKey('guest_name') &&
        record.containsKey('checkin_date')) {
      return 'bookings';
    }
    if (record.containsKey('amount') && record.containsKey('payment_method')) {
      return 'payments';
    }
    if (record.containsKey('expense_type') &&
        record.containsKey('description')) {
      return 'expenses';
    }
    if (record.containsKey('basic_salary') && record.containsKey('position')) {
      return 'employees';
    }
    if (record.containsKey('debt_reason') &&
        record.containsKey('remaining_amount')) {
      return 'debts';
    }
    if (record.containsKey('final_rate') &&
        record.containsKey('hotel_day_key')) {
      return 'booking_nights';
    }
    if (record.containsKey('adjustment_type') &&
        record.containsKey('effective_hotel_day')) {
      return 'booking_price_adjustments';
    }
    if (record.containsKey('note_text') && record.containsKey('alert_type')) {
      return 'booking_notes';
    }
    if (record.containsKey('guest_name') && record.containsKey('id_number')) {
      return 'guest_infos';
    }
    if (record.containsKey('shift_date') && record.containsKey('is_read')) {
      return 'shift_notes';
    }
    if (record.containsKey('transaction_type') &&
        record.containsKey('transaction_time')) {
      return 'cash_transactions';
    }
    if (record.containsKey('cycle_key') &&
        record.containsKey('expected_amount')) {
      return 'salary_cycles';
    }
    if (record.containsKey('payment_date_iso') &&
        record.containsKey('cycle_id')) {
      return 'salary_payments';
    }
    if (record.containsKey('withdrawal_type') && record.containsKey('amount')) {
      return 'salary_withdrawals';
    }
    if (record.containsKey('previous_cycle_start') &&
        record.containsKey('new_cycle_start')) {
      return 'salary_carry_over_logs';
    }
    if (record.containsKey('target_type') &&
        record.containsKey('target_uuid')) {
      return 'price_adjustments';
    }
    if (record.containsKey('operation_type') &&
        record.containsKey('entity_type')) {
      return 'audit_logs';
    }
    if (record.containsKey('void_reason') && record.containsKey('voided_by')) {
      return 'payment_voids';
    }
    if (record.containsKey('minimum_quantity')) {
      return 'inventory_items';
    }
    if (record.containsKey('movement_type') &&
        record.containsKey('balance_after')) {
      return 'inventory_transactions';
    }
    if (record.containsKey('device_name')) {
      return 'devices';
    }
    if (record.containsKey('reported_by')) {
      return 'blacklist';
    }
    if (record.containsKey('username') &&
        record.containsKey('credentials_version')) {
      return 'app_users';
    }
    return null;
  }

  // ─── Column Filtering ───────────────────────────────────────

  /// Get local columns for a table (cached via PRAGMA table_info).
  Future<Set<String>> localColumns(String tableName) async {
    final cached = _localColumnsCache[tableName];
    if (cached != null) return cached;
    final rows = await database.customSelect(
      'PRAGMA table_info($tableName)',
    ).get();
    final cols = <String>{
      for (final row in rows)
        if (row.data['name'] != null) row.data['name'].toString(),
    };
    _localColumnsCache[tableName] = cols;
    return cols;
  }

  /// Filter record to only include columns that exist locally.
  ///
  /// Drops unknown server columns with a log entry instead of failing the
  /// entire record with "no such column".
  Future<Map<String, dynamic>> filterToLocalColumns(
    String tableName,
    Map<String, dynamic> record,
  ) async {
    final cols = await localColumns(tableName);
    if (cols.isEmpty) return Map<String, dynamic>.of(record);
    final out = <String, dynamic>{};
    final dropped = <String>[];
    record.forEach((key, value) {
      if (cols.contains(key)) {
        out[key] = value;
      } else {
        dropped.add(key);
      }
    });
    if (dropped.isNotEmpty) {
      _logFkOnce('dropped unknown column(s) for $tableName: ${dropped.join(', ')}');
    }
    return out;
  }

  // ─── FK Resolution ──────────────────────────────────────────

  /// Look up a local parent ID by column and key.
  Future<Object?> lookupLocalParentId(
    String parentTable,
    String keyColumn,
    Object? keyValue,
  ) async {
    try {
      final row = await database
          .customSelect(
            'SELECT id FROM $parentTable WHERE $keyColumn = ? LIMIT 1',
            variables: [Variable.withString(keyValue.toString())],
          )
          .getSingleOrNull();
      return row?.data['id'];
    } catch (e) {
      _logFkOnce('parent lookup failed $parentTable.$keyColumn: $e');
      return null;
    }
  }

  /// Check if a parent key exists in the parent table.
  Future<bool> parentKeyExists(
    String parentTable,
    String keyColumn,
    Object? keyValue,
  ) async {
    try {
      final row = await database
          .customSelect(
            'SELECT 1 AS hit FROM $parentTable WHERE $keyColumn = ? LIMIT 1',
            variables: [Variable.withString(keyValue.toString())],
          )
          .getSingleOrNull();
      return row != null;
    } catch (_) {
      return false;
    }
  }

  void _logFkOnce(String message) {
    if (_fkLogSeen.add(message)) {
      debugPrint('🔗 Pull/FK: $message');
    }
  }

  /// Resolve foreign keys for a record before applying it.
  ///
  /// Returns true if all required relations are resolved (or the record
  /// was already existing and can keep its current values). Returns false
  /// if the record should be deferred for later retry.
  Future<bool> resolveForeignKeysForRecord({
    required String entity,
    required Map<String, dynamic> record,
    required Map<String, dynamic>? existing,
  }) async {
    final rules = fkRulesByEntity[entity];
    if (rules == null || rules.isEmpty) return true;

    for (final rule in rules) {
      final wireValue = record[rule.column];

      if (rule.kind == FkKind.numericPointer) {
        if (wireValue == null) {
          if (record.containsKey(rule.column) && !rule.nullable) {
            if (existing != null) {
              record[rule.column] = existing[rule.column];
              continue;
            }
            return false;
          }
          continue;
        }

        final serverValue = wireValue is int
            ? wireValue
            : int.tryParse(wireValue.toString());
        Object? resolved;
        if (serverValue != null) {
          final cacheKey = rule.uuidCacheColumn == null
              ? null
              : record[rule.uuidCacheColumn]?.toString();
          if (cacheKey != null && cacheKey.isNotEmpty) {
            resolved = await lookupLocalParentId(
              rule.parentTable,
              'local_uuid',
              cacheKey,
            );
          }
          resolved ??= await lookupLocalParentId(
            rule.parentTable,
            'server_id',
            serverValue,
          );
          if (resolved == null && rule.legacyServerBookingId) {
            final legacy = record['server_booking_id'];
            final legacyInt = legacy is int
                ? legacy
                : int.tryParse(legacy?.toString() ?? '');
            if (legacyInt != null) {
              resolved = await lookupLocalParentId(
                rule.parentTable,
                'server_booking_id',
                legacyInt,
              );
            }
          }
        }

        if (resolved != null) {
          record[rule.column] = resolved;
          continue;
        }
        if (existing != null) {
          record[rule.column] = existing[rule.column];
          continue;
        }
        if (rule.nullWhenUnresolvable && rule.nullable) {
          record[rule.column] = null;
          _logFkOnce(
            'null-substituted $entity.${rule.column} '
            '(wire=$wireValue, no resolvable parent)',
          );
          continue;
        }
        return false;
      } else {
        if (wireValue == null || wireValue.toString().isEmpty) continue;
        final exists = await parentKeyExists(
          rule.parentTable,
          rule.parentKeyColumn,
          wireValue,
        );
        if (exists) continue;
        if (existing != null) {
          record[rule.column] = existing[rule.column];
          continue;
        }
        return false;
      }
    }
    return true;
  }

  // ─── Record Application ─────────────────────────────────────

  /// Convert a value for Drift storage.
  static dynamic toDriftValue(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value ? 1 : 0;
    if (value is List || value is Map) return jsonEncode(value);
    return value;
  }

  /// Apply a single pulled change record to the local database.
  ///
  /// Returns:
  /// - `true` if the record was applied (or intentionally skipped)
  /// - `false` if the record should be deferred for later retry
  ///
  /// Throws on real database errors (not silently swallowed).
  Future<bool> applyChange(
    String entity,
    Map<String, dynamic> record,
  ) async {
    if (record.isEmpty) return true;

    // Tombstone (soft delete)
    if (record['deleted_at'] != null) {
      return applyTombstone(entity, record);
    }

    // Blacklist conversion
    if (entity == 'blacklist') {
      final converted = _blacklistShiftNoteRowFromD1(record);
      if (converted == null) return true;
      entity = 'shift_notes';
      record = converted;
    }

    final tableName = CloudflareConfig.tableNameFor(entity);
    if (tableName == null) {
      debugPrint('⚠️ Pull: no local table for entity "$entity" — skipped');
      return true;
    }

    final localUuid = record['local_uuid'] as String?;
    if (localUuid == null) return true;

    final remoteUpdatedAt = record['updated_at'] as int? ?? 0;

    // Filter to local columns
    final filtered = await filterToLocalColumns(tableName, record);

    // Store server ID shadow
    final wireId = filtered['id'];
    if (wireId is int &&
        (await localColumns(tableName)).contains('server_id')) {
      filtered['server_id'] = wireId;
    }

    // Read existing local record
    final existing = await database
        .customSelect(
          'SELECT * FROM $tableName WHERE local_uuid = ?',
          variables: [Variable.withString(localUuid)],
        )
        .getSingleOrNull();
    final existingData =
        existing == null ? null : Map<String, dynamic>.from(existing.data);

    // Resolve FK relations
    final relationsResolved = await resolveForeignKeysForRecord(
      entity: entity,
      record: filtered,
      existing: existingData,
    );
    if (!relationsResolved) {
      if (quarantine.isQuarantined(entity, localUuid)) {
        debugPrint(
          '⏭️ Pull: quarantined $entity/$localUuid still unresolvable — '
          'skipped (parent still missing server-side)',
        );
        return true;
      }
      debugPrint(
        '⏸️ Pull: deferred $entity/$localUuid — parent not pulled yet',
      );
      return false;
    }

    if (existing != null) {
      final localData = Map<String, dynamic>.from(existing.data);
      final localUpdatedAt = localData['updated_at'] as int? ?? 0;
      final localId = localData['id'];

      // Tombstone on existing record
      final deletedAt = record['deleted_at'];
      if (deletedAt != null) {
        await database.customStatement(
          'UPDATE $tableName SET deleted_at = ?, updated_at = ?, last_modified = ? WHERE id = ?',
          [deletedAt, remoteUpdatedAt, remoteUpdatedAt, localId],
        );
        debugPrint('  🗑️ $entity/$localUuid: soft delete applied');
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'delete',
          ),
        );
        return true;
      }

      // Skip if local is newer (LWW)
      if (localUpdatedAt > remoteUpdatedAt) {
        debugPrint(
          '  ⏭️ $entity/$localUuid: local newer '
          '($localUpdatedAt > $remoteUpdatedAt) — skip',
        );
        return true;
      }

      // Vector clock conflict detection
      final localVcStr = (localData['vector_clock'] as String?) ?? '{}';
      final remoteVcStr = (record['vector_clock'] as String?) ?? '{}';
      final localVc = VectorClock.fromString(localVcStr);
      final remoteVc = VectorClock.fromString(remoteVcStr);

      if (localVc.isNotEmpty &&
          remoteVc.isNotEmpty &&
          localVc.isConcurrent(remoteVc)) {
        final resolution = SmartConflictResolver.resolve(
          entity: entity,
          localData: localData,
          remoteData: filtered,
          commonAncestor: null,
        );

        final mergedData = resolution.mergedData;
        final cleanRecord = Map<String, dynamic>.from(mergedData)
          ..remove('id');
        final setClauses = cleanRecord.keys.map((c) => '$c = ?').join(', ');
        final values = cleanRecord.values.map(toDriftValue).toList();
        await database.customStatement(
          'UPDATE $tableName SET $setClauses WHERE id = ?',
          [...values, localId],
        );

        if (resolution.pushedToRemote) {
          try {
            final outboxDao = OutboxDao(database);
            await outboxDao.merge(
              entity: entity,
              op: 'update',
              localUuid: localUuid,
              payload: mergedData,
              clientTs: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            );
            debugPrint(
              '  🤝 $entity/$localUuid: conflict resolved + queued for re-upload',
            );
          } catch (e) {
            debugPrint('  ⚠️ Failed to queue merged conflict result: $e');
          }
        }

        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'update',
          ),
        );
        return true;
      }

      // Sequential update (remote is newer)
      final cleanRecord = Map<String, dynamic>.from(filtered)..remove('id');
      final setClauses = cleanRecord.keys.map((c) => '$c = ?').join(', ');
      final values = cleanRecord.values.map(toDriftValue).toList();
      await database.customStatement(
        'UPDATE $tableName SET $setClauses WHERE id = ?',
        [...values, localId],
      );

      unawaited(
        RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: entity,
          record: record,
          op: 'update',
        ),
      );
    } else {
      // New record — insert
      final cleanRecord = Map<String, dynamic>.from(filtered)..remove('id');
      final columns = cleanRecord.keys.join(', ');
      final placeholders = cleanRecord.keys.map((_) => '?').join(', ');
      final values = cleanRecord.values.map(toDriftValue).toList();
      await database.customStatement(
        'INSERT OR REPLACE INTO $tableName ($columns) VALUES ($placeholders)',
        values,
      );

      final inserted = await database
          .customSelect(
            'SELECT 1 FROM $tableName WHERE local_uuid = ? AND updated_at = ?',
            variables: [
              Variable.withString(localUuid),
              Variable.withInt(remoteUpdatedAt),
            ],
          )
          .getSingleOrNull();
      if (inserted != null) {
        unawaited(
          RemoteChangeNotifier.instance.onRemoteChangeApplied(
            entity: entity,
            record: record,
            op: 'create',
          ),
        );
      }
    }

    quarantine.clearRecord(entity, localUuid);
    return true;
  }

  /// Apply a tombstone (soft delete) record.
  Future<bool> applyTombstone(
    String entity,
    Map<String, dynamic> record,
  ) async {
    var tableName = CloudflareConfig.tableNameFor(entity);
    var extraWhere = '';
    if (entity == 'blacklist') {
      tableName = 'shift_notes';
      extraWhere =
          " AND created_by = '${CloudflareConfig.blacklistStorageTag}'";
    }
    if (tableName == null) {
      debugPrint('⏭️ Tombstone: no local table for "$entity" — skipped');
      return true;
    }
    final localUuid = record['local_uuid'] as String?;
    if (localUuid == null || localUuid.isEmpty) return true;

    final deletedAt = record['deleted_at'];
    final updatedAt = record['updated_at'] as int? ?? 0;
    try {
      final existing = await database
          .customSelect(
            'SELECT id FROM $tableName WHERE local_uuid = ?$extraWhere',
            variables: [Variable.withString(localUuid)],
          )
          .getSingleOrNull();
      if (existing == null) {
        debugPrint(
          '⏭️ Tombstone: $entity/$localUuid not present locally — no-op',
        );
        quarantine.clearRecord(entity, localUuid);
        return true;
      }
      final localId = existing.data['id'];
      final cols = await localColumns(tableName);
      if (cols.contains('deleted_at')) {
        final hasLastModified = cols.contains('last_modified');
        await database.customStatement(
          'UPDATE $tableName SET deleted_at = ?, updated_at = ?'
          '${hasLastModified ? ', last_modified = ?' : ''} WHERE id = ?',
          [
            deletedAt,
            updatedAt,
            if (hasLastModified) updatedAt,
            localId,
          ],
        );
      } else {
        await database.customStatement(
          'DELETE FROM $tableName WHERE id = ?',
          [localId],
        );
      }
      debugPrint('  🗑️ $entity/$localUuid: remote tombstone applied');
      unawaited(
        RemoteChangeNotifier.instance.onRemoteChangeApplied(
          entity: entity,
          record: record,
          op: 'delete',
        ),
      );
      quarantine.clearRecord(entity, localUuid);
    } catch (e) {
      throw Exception('Tombstone apply failed for $entity/$localUuid: $e');
    }
    return true;
  }

  // ─── Batch Apply ────────────────────────────────────────────

  /// Apply a batch of pulled records with deferred-sink support.
  @visibleForTesting
  Future<PullApplyReport> applyPulledRecords(
    List<({String entity, Map<String, dynamic> record})> records, {
    List<({String entity, Map<String, dynamic> record})>? deferredSink,
  }) async {
    var applied = 0;
    final touched = <String>{};
    final errors = <String>[];
    var pending = List.of(records);

    for (var pass = 0; pass < 3 && pending.isNotEmpty; pass++) {
      if (pass > 0) {
        pending.sort(
          (a, b) => (pullApplyPriority[a.entity] ?? 9)
              .compareTo(pullApplyPriority[b.entity] ?? 9),
        );
      }
      final stillPending = <({String entity, Map<String, dynamic> record})>[];
      for (final item in pending) {
        try {
          final ok = await applyChange(item.entity, item.record);
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

    var unresolvableCount = 0;
    if (deferredSink != null) {
      deferredSink.addAll(pending);
    } else {
      unresolvableCount = pending.length;
      if (pending.isNotEmpty) {
        final names = [
          for (final item in pending.take(5))
            '${item.entity}/${item.record['local_uuid']}',
        ];
        debugPrint(
          '⏸️ Pull: ${pending.length} record(s) deferred-unresolved: '
          '${names.join(', ')}',
        );
      }
    }

    return PullApplyReport(
      appliedCount: applied,
      deferredCount: unresolvableCount,
      touchedEntities: touched,
      unresolvable: [
        for (final item in pending.take(
          deferredSink == null ? pending.length : 0,
        ))
          '${item.entity}/${item.record['local_uuid']}',
      ],
      errors: errors,
    );
  }

  /// Retry deferred records after full pagination.
  Future<List<({String entity, Map<String, dynamic> record})>>
      retryDeferredRecords(
    List<({String entity, Map<String, dynamic> record})> deferred, {
    required void Function(String entity) onApplied,
    required List<String> errors,
  }) async {
    var remaining = List.of(deferred);
    for (var pass = 0; pass < 2 && remaining.isNotEmpty; pass++) {
      remaining.sort(
        (a, b) => (pullApplyPriority[a.entity] ?? 9)
            .compareTo(pullApplyPriority[b.entity] ?? 9),
      );
      final stillPending = <({String entity, Map<String, dynamic> record})>[];
      for (final item in remaining) {
        try {
          final ok = await applyChange(item.entity, item.record);
          if (ok) {
            onApplied(item.entity);
          } else {
            stillPending.add(item);
          }
        } catch (e) {
          errors.add('${item.entity}/${item.record['local_uuid']}: $e');
        }
      }
      final progressed = stillPending.length < remaining.length;
      remaining = stillPending;
      if (!progressed) break;
    }
    return remaining;
  }

  // ─── Derived Fields Refresh ─────────────────────────────────

  /// Refresh derived booking fields after pull.
  Future<void> refreshDerivedAfterPull() async {
    if (_derivedRefreshRunning) return;
    _derivedRefreshRunning = true;
    try {
      final service = BookingDerivedFieldsService(database);
      final refreshed = await service.refreshAllActiveBookings(
        enqueueOutbox: false,
      );
      debugPrint('🔄 Derived refresh after pull: $refreshed bookings rebuilt');
    } catch (e) {
      debugPrint('⚠️ Derived refresh after pull failed: $e');
    } finally {
      _derivedRefreshRunning = false;
    }
  }

  // ─── Utilities ──────────────────────────────────────────────

  /// Simple blacklist-to-shift_notes conversion.
  static Map<String, dynamic>? _blacklistShiftNoteRowFromD1(
    Map<String, dynamic> record,
  ) {
    try {
      return {
        'local_uuid': record['local_uuid'],
        'shift_date': record['shift_date'] ?? '',
        'note_text': record['note_text'] ?? record['reported_by'] ?? '',
        'alert_type': 'blacklist',
        'created_by': CloudflareConfig.blacklistStorageTag,
        'is_read': record['is_read'] ?? 0,
        'updated_at': record['updated_at'],
        'version': record['version'] ?? 1,
        'origin': record['origin'] ?? 'remote',
        'vector_clock': record['vector_clock'] ?? '{}',
      };
    } catch (_) {
      return null;
    }
  }

  /// Clear the local columns cache (e.g., after schema migration).
  void clearColumnsCache() {
    _localColumnsCache.clear();
  }

  /// Dispose resources.
  void dispose() {
    _localColumnsCache.clear();
    _fkLogSeen.clear();
  }
}
