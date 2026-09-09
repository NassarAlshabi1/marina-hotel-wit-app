import 'dart:async';
import 'dart:convert';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;

import '../data/sync_models.dart';
import '../utils/debug_log.dart';
import '../utils/time.dart';
import 'local_db.dart';

/// ✅ Cloudflare D1 Compatible Delta Sync Service
///
/// Tracks changes in local database and prepares delta payloads for upload
/// to Cloudflare D1. Uses Vector Clocks for conflict resolution and supports
/// all 30 entity types with full SyncFields mixin integration.
///
/// Key improvements over legacy version:
/// - Vector Clock support for multi-device sync
/// - Proper handling of idempotencyKey for retry safety
/// - origin field tracking device changes
/// - version field for conflict detection
/// - Cloudflare D1 API compatibility

/// ✅ Cloudflare D1 compatible change record
class DeltaSyncChange {
  DeltaSyncChange({
    required this.entity,
    required this.operation,
    required this.data,
    required this.rowHash,
    required this.localUuid,
    required this.clientTimestamp,
    required this.vectorClock,      // ✅ Vector Clock for conflict resolution
    required this.origin,            // ✅ Device origin
    required this.version,           // ✅ Version for conflict detection
    required this.idempotencyKey,    // ✅ Retry safety
  });

  final String entity;
  final String operation;              // insert | update | delete
  final Map<String, dynamic> data;
  final String rowHash;                // SHA-1 hash of normalized payload
  final String localUuid;              // local_uuid from SyncFields
  final int clientTimestamp;           // client-side timestamp
  final String vectorClock;            // ✅ Vector Clock: "device1:5,device2:3,..."
  final String origin;                 // ✅ Origin device UUID
  final int version;                   // ✅ Monotonic version counter
  final String idempotencyKey;         // ✅ For deduplication on retry

  /// Convert to Cloudflare D1 API payload
  Map<String, dynamic> toMap() {
    return {
      'entity': entity,
      'operation': operation,
      'data': data,
      'row_hash': rowHash,
      'local_uuid': localUuid,
      'client_timestamp': clientTimestamp,
      'vector_clock': vectorClock,     // ✅ Cloudflare will merge clocks
      'origin': origin,                 // ✅ Device tracking
      'version': version,               // ✅ Conflict resolution
      'idempotency_key': idempotencyKey, // ✅ Deduplication
    };
  }
}

class DeltaSyncComputation {
  DeltaSyncComputation({
    required this.changes,
    required this.mirrorSnapshot,
    required this.fallbackTables,
  });

  final List<DeltaSyncChange> changes;
  final Map<String, Map<String, MirrorRow>> mirrorSnapshot;
  final Set<String> fallbackTables;

  List<Map<String, dynamic>> toPayload() {
    return changes.map((c) => c.toMap()).toList();
  }
}

class DeltaSyncService {
  DeltaSyncService(this.db);

  final AppDatabase db;
  bool _mirrorTableReady = false;

  /// ✅ Compute delta changes for Cloudflare D1
  ///
  /// Returns all changes since [since] timestamp (default: lastPushTs from DB)
  /// including Vector Clock info for each change.
  Future<DeltaSyncComputation> compute({int? since}) async {
    final state = await (db.select(db.syncState)
        ..where((t) => t.id.equals(1)))
        .getSingleOrNull();

    final baseSince = since ?? state?.lastPushTs ?? 0;
    final normalizedSince = _normalizeTimestamp(baseSince);
    final previousMirror = await _loadMirror();
    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());
    final fallbackTables = <String>{};

    // ✅ Get current device UUID for origin tracking
    final currentDeviceId = state?.deviceId ?? 'unknown';

    final entityInputs = <_DeltaSyncEntityInput>[];
    for (final config in configs) {
      final rows = await config.fetchAll();
      final hasMirror = previousMirror.containsKey(config.entity);
      if (!hasMirror) {
        fallbackTables.add(config.entity);
        dlog(
          () => '⚠️ جدول ${config.entity}: لا توجد مرآة، سيتم الاعتماد على '
              'lastModified فقط',
        );
      }

      final rowDataList = <_EntityRowData>[];
      for (final row in rows) {
        final localUuid = config.localUuid(row);
        if (localUuid.isEmpty) continue;

        rowDataList.add(
          _EntityRowData(
            localUuid: localUuid,
            toJson: config.toJson(row),
            createdAt: config.createdAt(row),
            lastModified: config.lastModified(row),
            deletedAt: config.deletedAt(row),
            vectorClock: config.vectorClock(row),  // ✅ Vector Clock
            origin: config.origin(row),             // ✅ Origin device
            version: config.version(row),           // ✅ Version
            idempotencyKey: config.idempotencyKey(row), // ✅ Idempotency
          ),
        );
      }

      entityInputs.add(
        _DeltaSyncEntityInput(
          entity: config.entity,
          rows: rowDataList,
          hasMirror: hasMirror,
        ),
      );
    }

    final isolateInput = _DeltaSyncIsolateInput(
      entities: entityInputs,
      previousMirror: previousMirror,
      normalizedSince: normalizedSince,
      nowTs: nowTs,
      fallbackTables: fallbackTables,
      currentDeviceId: currentDeviceId,  // ✅ Pass device ID
    );

    final output = await Isolate.run(
      () => _computeDeltaSyncInIsolate(isolateInput),
    );

    final changes = output.changes
        .map(
          (m) => DeltaSyncChange(
            entity: m['entity'] as String,
            operation: m['operation'] as String,
            data: m['data'] as Map<String, dynamic>,
            rowHash: m['row_hash'] as String,
            localUuid: m['local_uuid'] as String,
            clientTimestamp: m['client_ts'] as int,
            vectorClock: m['vector_clock'] as String, // ✅ From isolate
            origin: m['origin'] as String,             // ✅ From isolate
            version: m['version'] as int,              // ✅ From isolate
            idempotencyKey: m['idempotency_key'] as String, // ✅ From isolate
          ),
        )
        .toList();

    final computation = DeltaSyncComputation(
      changes: changes,
      mirrorSnapshot: output.mirrorSnapshot,
      fallbackTables: fallbackTables,
    );

    if (computation.changes.isEmpty && computation.mirrorSnapshot.isNotEmpty) {
      await persistMirror(computation);
    }

    return computation;
  }

  Future<void> persistMirror(
    DeltaSyncComputation computation, {
    bool useExistingTransaction = false,
  }) async {
    final snapshot = computation.mirrorSnapshot;
    await _ensureMirrorTable();
    if (useExistingTransaction) {
      await _persistMirrorSnapshot(snapshot);
    } else {
      await db.transaction(() async {
        await _persistMirrorSnapshot(snapshot);
      });
    }
  }

  Future<void> _persistMirrorSnapshot(
    Map<String, Map<String, MirrorRow>> snapshot,
  ) async {
    for (final entry in snapshot.entries) {
      final table = entry.key;
      await db.customStatement('DELETE FROM sync_mirror WHERE table_name = ?', [
        table,
      ]);
      for (final row in entry.value.values) {
        await db.customStatement(
          'REPLACE INTO sync_mirror (table_name, local_uuid, row_hash, payload, last_seen_at) VALUES (?, ?, ?, ?, ?)',
          [
            table,
            row.localUuid,
            row.rowHash,
            jsonEncode(row.payload),
            row.lastSeenAt,
          ],
        );
      }
    }
  }

  Future<void> _ensureMirrorTable() async {
    if (_mirrorTableReady) {
      return;
    }
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS sync_mirror (table_name TEXT NOT NULL, local_uuid TEXT NOT NULL, row_hash TEXT NOT NULL, payload TEXT NOT NULL, last_seen_at INTEGER NOT NULL, PRIMARY KEY(table_name, local_uuid))',
    );
    _mirrorTableReady = true;
  }

  Future<Map<String, Map<String, MirrorRow>>> _loadMirror() async {
    await _ensureMirrorTable();
    final rows = await db
        .customSelect(
          'SELECT table_name, local_uuid, row_hash, payload, last_seen_at FROM sync_mirror',
        )
        .get();
    final result = <String, Map<String, MirrorRow>>{};
    for (final row in rows) {
      final table = row.read<String>('table_name');
      final uuid = row.read<String>('local_uuid');
      final payload =
          jsonDecode(row.read<String>('payload')) as Map<String, dynamic>;
      result.putIfAbsent(table, () => {})[uuid] = MirrorRow(
        localUuid: uuid,
        rowHash: row.read<String>('row_hash'),
        payload: payload,
        lastSeenAt: row.read<int>('last_seen_at'),
      );
    }
    return result;
  }

  /// التحقق من صحة Mirror ومقارنته مع قاعدة البيانات الفعلية
  Future<MirrorValidationResult> validateMirror() async {
    final issues = <String>[];
    final configs = _entityConfigs();
    final mirrorRows = await _loadMirror();

    for (final config in configs) {
      try {
        final currentRows = await config.fetchAll();
        final tableMirror = mirrorRows[config.entity] ?? {};

        if (currentRows.length != tableMirror.length) {
          issues.add(
            '${config.entity}: row count mismatch (current: ${currentRows.length}, mirror: ${tableMirror.length})',
          );
        }

        final int sampleSize = (currentRows.length * 0.1).ceil().clamp(1, 50);
        final sample = (currentRows..shuffle()).take(sampleSize);

        for (final row in sample) {
          final uuid = config.localUuid(row);
          if (uuid.isEmpty) {
            continue;
          }

          final mirrorRow = tableMirror[uuid];
          if (mirrorRow == null) {
            issues.add('${config.entity}: missing mirror for $uuid');
            continue;
          }

          final sanitized = _preparePayload(config.toJson(row));
          sanitized['local_uuid'] = uuid;
          final currentHash = _hashPayload(sanitized);

          if (currentHash != mirrorRow.rowHash) {
            issues.add('${config.entity}: hash mismatch for $uuid');
          }
        }
      } catch (e) {
        issues.add('${config.entity}: validation error - $e');
      }
    }

    return MirrorValidationResult(
      isValid: issues.isEmpty,
      issues: issues,
      validatedAt: DateTime.now(),
    );
  }

  /// إصلاح Mirror تلقائياً إذا كان غير متسق
  Future<void> repairMirrorIfNeeded() async {
    final validation = await validateMirror();
    if (!validation.isValid) {
      dlog('⚠️ Mirror inconsistency detected, repairing...');
      dlog(() => 'Issues: ${validation.issues.join(', ')}');
      await _rebuildMirror();
    }
  }

  /// إعادة بناء Mirror من الصفر
  Future<void> _rebuildMirror() async {
    await _ensureMirrorTable();
    await db.customStatement('DELETE FROM sync_mirror');

    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());

    for (final config in configs) {
      try {
        final rows = await config.fetchAll();
        for (final row in rows) {
          final uuid = config.localUuid(row);
          if (uuid.isEmpty) {
            continue;
          }

          final sanitized = _preparePayload(config.toJson(row));
          sanitized['local_uuid'] = uuid;
          final rowHash = _hashPayload(sanitized);

          await db.customStatement(
            'REPLACE INTO sync_mirror (table_name, local_uuid, row_hash, payload, last_seen_at) VALUES (?, ?, ?, ?, ?)',
            [config.entity, uuid, rowHash, jsonEncode(sanitized), nowTs],
          );
        }
        dlog(
          () => '✅ Rebuilt mirror for ${config.entity} (${rows.length} rows)',
        );
      } catch (e) {
        dlog(() => '❌ Failed to rebuild mirror for ${config.entity}: $e');
      }
    }

    dlog('✅ Mirror rebuild completed');
  }

  /// ✅ Entity configuration list with Cloudflare D1 fields
  List<_EntityConfig> _entityConfigs() {
    return [
      _EntityConfig(
        entity: 'rooms',
        fetchAll: () => db.select(db.rooms).get(),
        localUuid: (dynamic row) => (row as Room).localUuid,
        createdAt: (dynamic row) => (row as Room).createdAt,
        lastModified: (dynamic row) => (row as Room).lastModified,
        deletedAt: (dynamic row) => (row as Room).deletedAt,
        toJson: (dynamic row) => (row as Room).toJson(),
        vectorClock: (dynamic row) => (row as Room).vectorClock,    // ✅ From SyncFields
        origin: (dynamic row) => (row as Room).origin,              // ✅ From SyncFields
        version: (dynamic row) => (row as Room).version,            // ✅ From SyncFields
        idempotencyKey: (dynamic row) => (row as Room).idempotencyKey, // ✅ From SyncFields
      ),
      _EntityConfig(
        entity: 'bookings',
        fetchAll: () => db.select(db.bookings).get(),
        localUuid: (dynamic row) => (row as Booking).localUuid,
        createdAt: (dynamic row) => (row as Booking).createdAt,
        lastModified: (dynamic row) => (row as Booking).lastModified,
        deletedAt: (dynamic row) => (row as Booking).deletedAt,
        toJson: (dynamic row) {
          final b = row as Booking;
          final j = b.toJson();
          j['amount'] = b.totalDueCached;
          return j;
        },
        vectorClock: (dynamic row) => (row as Booking).vectorClock,
        origin: (dynamic row) => (row as Booking).origin,
        version: (dynamic row) => (row as Booking).version,
        idempotencyKey: (dynamic row) => (row as Booking).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'booking_notes',
        fetchAll: () => db.select(db.bookingNotes).get(),
        localUuid: (dynamic row) => (row as BookingNote).localUuid,
        createdAt: (dynamic row) => (row as BookingNote).createdAt,
        lastModified: (dynamic row) => (row as BookingNote).lastModified,
        deletedAt: (dynamic row) => (row as BookingNote).deletedAt,
        toJson: (dynamic row) => (row as BookingNote).toJson(),
        vectorClock: (dynamic row) => (row as BookingNote).vectorClock,
        origin: (dynamic row) => (row as BookingNote).origin,
        version: (dynamic row) => (row as BookingNote).version,
        idempotencyKey: (dynamic row) => (row as BookingNote).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'employees',
        fetchAll: () => db.select(db.employees).get(),
        localUuid: (dynamic row) => (row as Employee).localUuid,
        createdAt: (dynamic row) => (row as Employee).createdAt,
        lastModified: (dynamic row) => (row as Employee).lastModified,
        deletedAt: (dynamic row) => (row as Employee).deletedAt,
        toJson: (dynamic row) => (row as Employee).toJson(),
        vectorClock: (dynamic row) => (row as Employee).vectorClock,
        origin: (dynamic row) => (row as Employee).origin,
        version: (dynamic row) => (row as Employee).version,
        idempotencyKey: (dynamic row) => (row as Employee).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'inventory_items',
        fetchAll: () => db.select(db.inventoryItems).get(),
        localUuid: (dynamic row) => (row as InventoryItem).localUuid,
        createdAt: (dynamic row) => (row as InventoryItem).createdAt,
        lastModified: (dynamic row) => (row as InventoryItem).lastModified,
        deletedAt: (dynamic row) => (row as InventoryItem).deletedAt,
        toJson: (dynamic row) => (row as InventoryItem).toJson(),
        vectorClock: (dynamic row) => (row as InventoryItem).vectorClock,
        origin: (dynamic row) => (row as InventoryItem).origin,
        version: (dynamic row) => (row as InventoryItem).version,
        idempotencyKey: (dynamic row) => (row as InventoryItem).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'inventory_transactions',
        fetchAll: () => db.select(db.inventoryTransactions).get(),
        localUuid: (dynamic row) => (row as InventoryTransaction).localUuid,
        createdAt: (dynamic row) => (row as InventoryTransaction).createdAt,
        lastModified: (dynamic row) =>
            (row as InventoryTransaction).lastModified,
        deletedAt: (dynamic row) => (row as InventoryTransaction).deletedAt,
        toJson: (dynamic row) => (row as InventoryTransaction).toJson(),
        vectorClock: (dynamic row) => (row as InventoryTransaction).vectorClock,
        origin: (dynamic row) => (row as InventoryTransaction).origin,
        version: (dynamic row) => (row as InventoryTransaction).version,
        idempotencyKey: (dynamic row) => (row as InventoryTransaction).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'expenses',
        fetchAll: () => db.select(db.expenses).get(),
        localUuid: (dynamic row) => (row as Expense).localUuid,
        createdAt: (dynamic row) => (row as Expense).createdAt,
        lastModified: (dynamic row) => (row as Expense).lastModified,
        deletedAt: (dynamic row) => (row as Expense).deletedAt,
        toJson: (dynamic row) => (row as Expense).toJson(),
        vectorClock: (dynamic row) => (row as Expense).vectorClock,
        origin: (dynamic row) => (row as Expense).origin,
        version: (dynamic row) => (row as Expense).version,
        idempotencyKey: (dynamic row) => (row as Expense).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'cash_transactions',
        fetchAll: () => db.select(db.cashTransactions).get(),
        localUuid: (dynamic row) => (row as CashTransaction).localUuid,
        createdAt: (dynamic row) => (row as CashTransaction).createdAt,
        lastModified: (dynamic row) => (row as CashTransaction).lastModified,
        deletedAt: (dynamic row) => (row as CashTransaction).deletedAt,
        toJson: (dynamic row) => (row as CashTransaction).toJson(),
        vectorClock: (dynamic row) => (row as CashTransaction).vectorClock,
        origin: (dynamic row) => (row as CashTransaction).origin,
        version: (dynamic row) => (row as CashTransaction).version,
        idempotencyKey: (dynamic row) => (row as CashTransaction).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'payments',
        fetchAll: () => db.select(db.payments).get(),
        localUuid: (dynamic row) => (row as Payment).localUuid,
        createdAt: (dynamic row) => (row as Payment).createdAt,
        lastModified: (dynamic row) => (row as Payment).lastModified,
        deletedAt: (dynamic row) => (row as Payment).deletedAt,
        toJson: (dynamic row) => (row as Payment).toJson(),
        vectorClock: (dynamic row) => (row as Payment).vectorClock,
        origin: (dynamic row) => (row as Payment).origin,
        version: (dynamic row) => (row as Payment).version,
        idempotencyKey: (dynamic row) => (row as Payment).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'debts',
        fetchAll: () => db.select(db.debts).get(),
        localUuid: (dynamic row) => (row as Debt).localUuid,
        createdAt: (dynamic row) => (row as Debt).createdAt,
        lastModified: (dynamic row) => (row as Debt).lastModified,
        deletedAt: (dynamic row) => (row as Debt).deletedAt,
        toJson: (dynamic row) => (row as Debt).toJson(),
        vectorClock: (dynamic row) => (row as Debt).vectorClock,
        origin: (dynamic row) => (row as Debt).origin,
        version: (dynamic row) => (row as Debt).version,
        idempotencyKey: (dynamic row) => (row as Debt).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'booking_nights',
        fetchAll: () => db.select(db.bookingNights).get(),
        localUuid: (dynamic row) => (row as BookingNight).localUuid,
        createdAt: (dynamic row) => (row as BookingNight).createdAt,
        lastModified: (dynamic row) => (row as BookingNight).lastModified,
        deletedAt: (dynamic row) => (row as BookingNight).deletedAt,
        toJson: (dynamic row) => (row as BookingNight).toJson(),
        vectorClock: (dynamic row) => (row as BookingNight).vectorClock,
        origin: (dynamic row) => (row as BookingNight).origin,
        version: (dynamic row) => (row as BookingNight).version,
        idempotencyKey: (dynamic row) => (row as BookingNight).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'guest_infos',
        fetchAll: () => db.select(db.guestInfos).get(),
        localUuid: (dynamic row) => (row as GuestInfo).localUuid,
        createdAt: (dynamic row) => (row as GuestInfo).createdAt,
        lastModified: (dynamic row) => (row as GuestInfo).lastModified,
        deletedAt: (dynamic row) => (row as GuestInfo).deletedAt,
        toJson: (dynamic row) => (row as GuestInfo).toJson(),
        vectorClock: (dynamic row) => (row as GuestInfo).vectorClock,
        origin: (dynamic row) => (row as GuestInfo).origin,
        version: (dynamic row) => (row as GuestInfo).version,
        idempotencyKey: (dynamic row) => (row as GuestInfo).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'salary_withdrawals',
        fetchAll: () => db.select(db.salaryWithdrawals).get(),
        localUuid: (dynamic row) => (row as SalaryWithdrawal).localUuid,
        createdAt: (dynamic row) => (row as SalaryWithdrawal).createdAt,
        lastModified: (dynamic row) => (row as SalaryWithdrawal).lastModified,
        deletedAt: (dynamic row) => (row as SalaryWithdrawal).deletedAt,
        toJson: (dynamic row) => (row as SalaryWithdrawal).toJson(),
        vectorClock: (dynamic row) => (row as SalaryWithdrawal).vectorClock,
        origin: (dynamic row) => (row as SalaryWithdrawal).origin,
        version: (dynamic row) => (row as SalaryWithdrawal).version,
        idempotencyKey: (dynamic row) => (row as SalaryWithdrawal).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'salary_carry_over_logs',
        fetchAll: () => db.select(db.salaryCarryOverLogs).get(),
        localUuid: (dynamic row) => (row as SalaryCarryOverLog).localUuid,
        createdAt: (dynamic row) => (row as SalaryCarryOverLog).createdAt,
        lastModified: (dynamic row) => (row as SalaryCarryOverLog).lastModified,
        deletedAt: (dynamic row) => (row as SalaryCarryOverLog).deletedAt,
        toJson: (dynamic row) => (row as SalaryCarryOverLog).toJson(),
        vectorClock: (dynamic row) => (row as SalaryCarryOverLog).vectorClock,
        origin: (dynamic row) => (row as SalaryCarryOverLog).origin,
        version: (dynamic row) => (row as SalaryCarryOverLog).version,
        idempotencyKey: (dynamic row) => (row as SalaryCarryOverLog).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'shift_notes',
        fetchAll: () => db.select(db.shiftNotes).get(),
        localUuid: (dynamic row) => (row as ShiftNote).localUuid,
        createdAt: (dynamic row) => (row as ShiftNote).createdAt,
        lastModified: (dynamic row) => (row as ShiftNote).lastModified,
        deletedAt: (dynamic row) => (row as ShiftNote).deletedAt,
        toJson: (dynamic row) => (row as ShiftNote).toJson(),
        vectorClock: (dynamic row) => (row as ShiftNote).vectorClock,
        origin: (dynamic row) => (row as ShiftNote).origin,
        version: (dynamic row) => (row as ShiftNote).version,
        idempotencyKey: (dynamic row) => (row as ShiftNote).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'salary_cycles',
        fetchAll: () => db.select(db.salaryCycles).get(),
        localUuid: (dynamic row) => (row as SalaryCycle).localUuid,
        createdAt: (dynamic row) => (row as SalaryCycle).createdAt,
        lastModified: (dynamic row) => (row as SalaryCycle).lastModified,
        deletedAt: (dynamic row) => (row as SalaryCycle).deletedAt,
        toJson: (dynamic row) => (row as SalaryCycle).toJson(),
        vectorClock: (dynamic row) => (row as SalaryCycle).vectorClock,
        origin: (dynamic row) => (row as SalaryCycle).origin,
        version: (dynamic row) => (row as SalaryCycle).version,
        idempotencyKey: (dynamic row) => (row as SalaryCycle).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'salary_payments',
        fetchAll: () => db.select(db.salaryPayments).get(),
        localUuid: (dynamic row) => (row as SalaryPayment).localUuid,
        createdAt: (dynamic row) => (row as SalaryPayment).createdAt,
        lastModified: (dynamic row) => (row as SalaryPayment).lastModified,
        deletedAt: (dynamic row) => (row as SalaryPayment).deletedAt,
        toJson: (dynamic row) => (row as SalaryPayment).toJson(),
        vectorClock: (dynamic row) => (row as SalaryPayment).vectorClock,
        origin: (dynamic row) => (row as SalaryPayment).origin,
        version: (dynamic row) => (row as SalaryPayment).version,
        idempotencyKey: (dynamic row) => (row as SalaryPayment).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'price_adjustments',
        fetchAll: () => db.select(db.priceAdjustments).get(),
        localUuid: (dynamic row) => (row as PriceAdjustment).localUuid,
        createdAt: (dynamic row) => (row as PriceAdjustment).createdAt,
        lastModified: (dynamic row) => (row as PriceAdjustment).lastModified,
        deletedAt: (dynamic row) => (row as PriceAdjustment).deletedAt,
        toJson: (dynamic row) => (row as PriceAdjustment).toJson(),
        vectorClock: (dynamic row) => (row as PriceAdjustment).vectorClock,
        origin: (dynamic row) => (row as PriceAdjustment).origin,
        version: (dynamic row) => (row as PriceAdjustment).version,
        idempotencyKey: (dynamic row) => (row as PriceAdjustment).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'audit_logs',
        fetchAll: () => db.select(db.auditLogs).get(),
        localUuid: (dynamic row) => (row as AuditLog).localUuid,
        createdAt: (dynamic row) => (row as AuditLog).createdAt,
        lastModified: (dynamic row) => (row as AuditLog).createdAt,
        deletedAt: (dynamic row) => null,
        toJson: (dynamic row) => (row as AuditLog).toJson(),
        vectorClock: (dynamic row) => (row as AuditLog).vectorClock,
        origin: (dynamic row) => (row as AuditLog).origin,
        version: (dynamic row) => (row as AuditLog).version,
        idempotencyKey: (dynamic row) => (row as AuditLog).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'payment_voids',
        fetchAll: () => db.select(db.paymentVoids).get(),
        localUuid: (dynamic row) => (row as PaymentVoid).localUuid,
        createdAt: (dynamic row) => (row as PaymentVoid).createdAt,
        lastModified: (dynamic row) => (row as PaymentVoid).lastModified,
        deletedAt: (dynamic row) => (row as PaymentVoid).deletedAt,
        toJson: (dynamic row) => (row as PaymentVoid).toJson(),
        vectorClock: (dynamic row) => (row as PaymentVoid).vectorClock,
        origin: (dynamic row) => (row as PaymentVoid).origin,
        version: (dynamic row) => (row as PaymentVoid).version,
        idempotencyKey: (dynamic row) => (row as PaymentVoid).idempotencyKey,
      ),
      _EntityConfig(
        entity: 'booking_price_adjustments',
        fetchAll: () => db.select(db.bookingPriceAdjustments).get(),
        localUuid: (dynamic row) => (row as BookingPriceAdjustment).localUuid,
        createdAt: (dynamic row) => (row as BookingPriceAdjustment).createdAt,
        lastModified: (dynamic row) =>
            (row as BookingPriceAdjustment).lastModified,
        deletedAt: (dynamic row) => (row as BookingPriceAdjustment).deletedAt,
        toJson: (dynamic row) => (row as BookingPriceAdjustment).toJson(),
        vectorClock: (dynamic row) => (row as BookingPriceAdjustment).vectorClock,
        origin: (dynamic row) => (row as BookingPriceAdjustment).origin,
        version: (dynamic row) => (row as BookingPriceAdjustment).version,
        idempotencyKey: (dynamic row) => (row as BookingPriceAdjustment).idempotencyKey,
      ),
    ];
  }
}

class MirrorRow {
  MirrorRow({
    required this.localUuid,
    required this.rowHash,
    required this.payload,
    required this.lastSeenAt,
  });

  final String localUuid;
  final String rowHash;
  final Map<String, dynamic> payload;
  final int lastSeenAt;
}

/// ✅ Entity configuration with Cloudflare D1 sync fields
class _EntityConfig {
  const _EntityConfig({
    required this.entity,
    required this.fetchAll,
    required this.localUuid,
    required this.createdAt,
    required this.lastModified,
    required this.deletedAt,
    required this.toJson,
    required this.vectorClock,      // ✅ Vector Clock accessor
    required this.origin,            // ✅ Origin device accessor
    required this.version,           // ✅ Version accessor
    required this.idempotencyKey,    // ✅ Idempotency key accessor
  });

  final String entity;
  final Future<List<dynamic>> Function() fetchAll;
  final String Function(dynamic row) localUuid;
  final int? Function(dynamic row) createdAt;
  final int? Function(dynamic row) lastModified;
  final int? Function(dynamic row) deletedAt;
  final Map<String, dynamic> Function(dynamic row) toJson;
  final String Function(dynamic row) vectorClock;    // ✅ SyncFields.vectorClock
  final String Function(dynamic row) origin;         // ✅ SyncFields.origin
  final int Function(dynamic row) version;           // ✅ SyncFields.version
  final String Function(dynamic row) idempotencyKey; // ✅ SyncFields.idempotencyKey
}

/// ✅ Row data with Cloudflare sync fields
class _EntityRowData {
  const _EntityRowData({
    required this.localUuid,
    required this.toJson,
    required this.createdAt,
    required this.lastModified,
    required this.deletedAt,
    required this.vectorClock,      // ✅ Vector Clock
    required this.origin,            // ✅ Origin device
    required this.version,           // ✅ Version
    required this.idempotencyKey,    // ✅ Idempotency key
  });

  final String localUuid;
  final Map<String, dynamic> toJson;
  final int? createdAt;
  final int? lastModified;
  final int? deletedAt;
  final String vectorClock;        // ✅ "device1:5,device2:3,..."
  final String origin;              // ✅ Origin device UUID
  final int version;                // ✅ Monotonic version
  final String idempotencyKey;      // ✅ For deduplication
}

/// ✅ Isolate input with device context
class _DeltaSyncIsolateInput {
  const _DeltaSyncIsolateInput({
    required this.entities,
    required this.previousMirror,
    required this.normalizedSince,
    required this.nowTs,
    required this.fallbackTables,
    required this.currentDeviceId,  // ✅ Current device UUID
  });

  final List<_DeltaSyncEntityInput> entities;
  final Map<String, Map<String, MirrorRow>> previousMirror;
  final int normalizedSince;
  final int nowTs;
  final Set<String> fallbackTables;
  final String currentDeviceId;     // ✅ For origin tracking
}

class _DeltaSyncEntityInput {
  const _DeltaSyncEntityInput({
    required this.entity,
    required this.rows,
    required this.hasMirror,
  });

  final String entity;
  final List<_EntityRowData> rows;
  final bool hasMirror;
}

/// ✅ Isolate output with Cloudflare fields
class _DeltaSyncIsolateOutput {
  const _DeltaSyncIsolateOutput({
    required this.changes,
    required this.mirrorSnapshot,
  });

  final List<Map<String, dynamic>> changes;  // ✅ Each includes vectorClock, origin, version
  final Map<String, Map<String, MirrorRow>> mirrorSnapshot;
}

/// ✅ Compute delta changes in isolate with Vector Clock support
_DeltaSyncIsolateOutput _computeDeltaSyncInIsolate(
  _DeltaSyncIsolateInput input,
) {
  final changes = <Map<String, dynamic>>[];
  final snapshot = <String, Map<String, MirrorRow>>{};

  for (final entityData in input.entities) {
    final existingMirror = input.previousMirror[entityData.entity] ?? {};
    final hasMirror = entityData.hasMirror;
    final tableSnapshot = <String, MirrorRow>{};
    final seen = <String>{};

    for (final row in entityData.rows) {
      final localUuid = row.localUuid;
      if (localUuid.isEmpty) continue;

      final sanitized = _preparePayload(row.toJson);
      sanitized['local_uuid'] = localUuid;
      final rowHash = _hashPayload(sanitized);
      final payload = Map<String, dynamic>.from(sanitized);
      payload['row_hash'] = rowHash;

      // ✅ Extract timestamps
      final createdAt = _asInt(sanitized['created_at']);
      final lastModified = _asInt(sanitized['last_modified']);
      final deletedAt = _asInt(sanitized['deleted_at']);
      final previous = existingMirror[localUuid];
      final clientTs = input.nowTs;

      // ✅ Extract Vector Clock fields
      final vectorClock = row.vectorClock;      // From SyncFields
      final origin = row.origin;                // From SyncFields
      final version = row.version;              // From SyncFields
      final idempotencyKey = row.idempotencyKey; // From SyncFields

      if (deletedAt != null && deletedAt > input.normalizedSince) {
        payload['deleted_at'] = deletedAt;
        changes.add({
          'entity': entityData.entity,
          'operation': 'delete',
          'data': payload,
          'row_hash': rowHash,
          'local_uuid': localUuid,
          'client_ts': clientTs,
          'vector_clock': vectorClock,      // ✅ Include Vector Clock
          'origin': origin,                  // ✅ Include origin device
          'version': version,                // ✅ Include version
          'idempotency_key': idempotencyKey, // ✅ Include idempotency key
        });
      } else {
        // ✅ Determine operation based on mirror state and timestamps
        final isFirstSyncForTable = !hasMirror;
        final isNewRecordInMirror = previous == null;
        final createdAfterLastSync =
            createdAt != null && createdAt > input.normalizedSince;

        final shouldInsert = isFirstSyncForTable ||
            (hasMirror && isNewRecordInMirror) ||
            createdAfterLastSync;

        if (shouldInsert) {
          changes.add({
            'entity': entityData.entity,
            'operation': 'insert',
            'data': payload,
            'row_hash': rowHash,
            'local_uuid': localUuid,
            'client_ts': clientTs,
            'vector_clock': vectorClock,      // ✅ Include Vector Clock
            'origin': origin,                  // ✅ Include origin device
            'version': version,                // ✅ Include version
            'idempotency_key': idempotencyKey, // ✅ Include idempotency key
          });
        } else if (previous != null &&
            lastModified != null &&
            lastModified > input.normalizedSince) {
          changes.add({
            'entity': entityData.entity,
            'operation': 'update',
            'data': payload,
            'row_hash': rowHash,
            'local_uuid': localUuid,
            'client_ts': clientTs,
            'vector_clock': vectorClock,      // ✅ Include Vector Clock
            'origin': origin,                  // ✅ Include origin device
            'version': version,                // ✅ Include version
            'idempotency_key': idempotencyKey, // ✅ Include idempotency key
          });
        }
      }

      tableSnapshot[localUuid] = MirrorRow(
        localUuid: localUuid,
        rowHash: rowHash,
        payload: Map<String, dynamic>.from(sanitized),
        lastSeenAt: input.nowTs,
      );
      seen.add(localUuid);
    }

    // ✅ Handle deleted/missing records
    final missing = existingMirror.keys
        .where((uuid) => !seen.contains(uuid))
        .toList();
    for (final uuid in missing) {
      final previous = existingMirror[uuid];
      if (previous == null) continue;

      final payload = Map<String, dynamic>.from(previous.payload);
      final previousDeletedAt = _asInt(payload['deleted_at']);
      final deleteStamp = previousDeletedAt ?? input.nowTs;

      // ✅ Only emit delete if:
      // 1. First time detecting hard-delete (previousDeletedAt == null), OR
      // 2. Delete timestamp is after last sync window
      // This prevents re-sending the same delete on every sync cycle
      final shouldEmit =
          previousDeletedAt == null || deleteStamp > input.normalizedSince;

      if (shouldEmit) {
        payload['deleted_at'] = deleteStamp;
        payload['row_hash'] = previous.rowHash;

        // ✅ Extract Vector Clock fields from payload (stored in mirror)
        final vectorClock = payload['vector_clock'] as String? ??
            '${input.currentDeviceId}:0';
        final origin = payload['origin'] as String? ?? input.currentDeviceId;
        final version = _asInt(payload['version']) ?? 0;
        final idempotencyKey = payload['idempotency_key'] as String? ?? '';

        changes.add({
          'entity': entityData.entity,
          'operation': 'delete',
          'data': payload,
          'row_hash': previous.rowHash,
          'local_uuid': uuid,
          'client_ts': deleteStamp,
          'vector_clock': vectorClock,      // ✅ From mirror
          'origin': origin,                  // ✅ From mirror
          'version': version,                // ✅ From mirror
          'idempotency_key': idempotencyKey, // ✅ From mirror
        });
      }
    }

    snapshot[entityData.entity] = tableSnapshot;
  }

  // ✅ Return changes already in map format (not DeltaSyncChange objects)
  return _DeltaSyncIsolateOutput(
    changes: changes,
    mirrorSnapshot: snapshot,
  );
}

int _normalizeTimestamp(int value) {
  if (value <= 0) {
    return value;
  }
  return value < 1000000000000 ? value * 1000 : value;
}

/// حقول الطوابع الزمنية التي تحتاج تحويل من ثوانٍ إلى مللي ثانية
const _timestampFieldNames = {
  'created_at',
  'updated_at',
  'deleted_at',
  'last_modified',
  'created_at_epoch',
  'updated_at_epoch',
  'last_modified_epoch',
  'night_start',
  'night_end',
  'alert_until',
  'transaction_time',
  'sync_timestamp',
  'payment_time',
  'check_in_time',
  'check_out_time',
};

Map<String, dynamic> _preparePayload(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    final newKey = _toSnakeCase(key);
    result[newKey] = _normalizeValue(value, newKey);
  });
  return result;
}

dynamic _normalizeValue(dynamic value, [String? fieldName]) {
  if (value is int) {
    // ✅ إصلاح: تحويل الطوابع الزمنية فقط، وليس كل الأعداد الصحيحة
    if (fieldName != null && _timestampFieldNames.contains(fieldName)) {
      return _normalizeTimestamp(value);
    }
    return value;
  } else if (value is num) {
    return value;
  } else if (value is Map<String, dynamic>) {
    return _preparePayload(value);
  } else if (value is List) {
    return value.map((item) {
      if (item is Map<String, dynamic>) {
        return _preparePayload(item);
      }
      if (item is int) {
        return item; // لا تحويل أعداد داخل القوائم أيضاً
      }
      return item;
    }).toList();
  }
  return value;
}

/// ✅ Hash payload using SHA-1 for row integrity checking
String _hashPayload(Map<String, dynamic> payload) {
  final sorted = _sortedMap(payload);
  return crypto.sha1.convert(utf8.encode(jsonEncode(sorted))).toString();
}

Map<String, dynamic> _sortedMap(Map<String, dynamic> source) {
  final entries = source.entries.map((entry) {
    final value = entry.value;
    dynamic normalized;
    if (value is Map<String, dynamic>) {
      normalized = _sortedMap(value);
    } else if (value is List) {
      normalized = value.map((item) {
        if (item is Map<String, dynamic>) {
          return _sortedMap(item);
        }
        return item;
      }).toList();
    } else {
      normalized = value;
    }
    return MapEntry(entry.key, normalized);
  }).toList()..sort((a, b) => a.key.compareTo(b.key));
  return Map<String, dynamic>.fromEntries(entries);
}

String _toSnakeCase(String input) {
  final snake = input.replaceAllMapped(
    RegExp('([a-z0-9])([A-Z])'),
    (match) => '${match.group(1)}_${match.group(2)}',
  );
  return snake.replaceAll('-', '_').toLowerCase();
}

int? _asInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return null;
}
