import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/sync_models.dart';
import '../utils/time.dart';
import 'local_db.dart';

class DeltaSyncChange {
  DeltaSyncChange({
    required this.entity,
    required this.operation,
    required this.data,
    required this.rowHash,
    required this.localUuid,
    required this.clientTimestamp,
  });

  final String entity;
  final String operation;
  final Map<String, dynamic> data;
  final String rowHash;
  final String localUuid;
  final int clientTimestamp;

  Map<String, dynamic> toMap() {
    return {
      'entity': entity,
      'op': operation,
      'data': data,
      'row_hash': rowHash,
      'local_uuid': localUuid,
      'client_ts': clientTimestamp,
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

  Future<DeltaSyncComputation> compute({int? since}) async {
    final state = await (db.select(
      db.syncState,
    )..where((t) => t.id.equals(1)))
        .getSingleOrNull();
    final baseSince = since ?? state?.lastPushTs ?? 0;
    final normalizedSince = _normalizeTimestamp(baseSince);
    final previousMirror = await _loadMirror();
    final configs = _entityConfigs();
    final nowTs = _normalizeTimestamp(Time.nowEpoch());
    final changes = <DeltaSyncChange>[];
    final snapshot = <String, Map<String, MirrorRow>>{};
    final fallbackTables = <String>{};

    for (final config in configs) {
      final rows = await config.fetchAll();
      final existingMirror = previousMirror[config.entity] ?? {};
      final hasMirror = previousMirror.containsKey(config.entity);
      if (!hasMirror) {
        fallbackTables.add(config.entity);
        debugPrint(
          '⚠️ تعذر إعادة بناء مرآة جدول ${config.entity}، سيتم الاعتماد على createdAt فقط',
        );
      }
      final tableSnapshot = <String, MirrorRow>{};
      final seen = <String>{};

      for (final row in rows) {
        final localUuid = config.localUuid(row);
        if (localUuid.isEmpty) {
          continue;
        }
        final sanitized = _preparePayload(config.toJson(row));
        sanitized['local_uuid'] = localUuid;
        final rowHash = _hashPayload(sanitized);
        final payload = Map<String, dynamic>.from(sanitized);
        payload['row_hash'] = rowHash;
        final createdAt = _asInt(sanitized['created_at']);
        final lastModified = _asInt(sanitized['last_modified']);
        final deletedAt = _asInt(sanitized['deleted_at']);
        final previous = existingMirror[localUuid];
        final clientTs = nowTs;

        if (deletedAt != null && deletedAt > normalizedSince) {
          payload['deleted_at'] = deletedAt;
          changes.add(
            DeltaSyncChange(
              entity: config.entity,
              operation: 'delete',
              data: payload,
              rowHash: rowHash,
              localUuid: localUuid,
              clientTimestamp: clientTs,
            ),
          );
          debugPrint('إرسال كـ DELETE: ${config.entity}/$localUuid');
        } else {
          final isFirstSyncForTable = !hasMirror;
          final isNewRecordInMirror = previous == null;
          final createdAfterLastSync =
              createdAt != null && createdAt > normalizedSince;

          final shouldInsert = isFirstSyncForTable ||
              (hasMirror && isNewRecordInMirror) ||
              createdAfterLastSync;

          if (shouldInsert) {
            changes.add(
              DeltaSyncChange(
                entity: config.entity,
                operation: 'insert',
                data: payload,
                rowHash: rowHash,
                localUuid: localUuid,
                clientTimestamp: clientTs,
              ),
            );
            debugPrint('إرسال كـ INSERT: ${config.entity}/$localUuid');
          } else if (previous != null &&
              lastModified != null &&
              lastModified > normalizedSince) {
            changes.add(
              DeltaSyncChange(
                entity: config.entity,
                operation: 'update',
                data: payload,
                rowHash: rowHash,
                localUuid: localUuid,
                clientTimestamp: clientTs,
              ),
            );
            debugPrint('إرسال كـ UPDATE: ${config.entity}/$localUuid');
          }
        }

        tableSnapshot[localUuid] = MirrorRow(
          localUuid: localUuid,
          rowHash: rowHash,
          payload: Map<String, dynamic>.from(sanitized),
          lastSeenAt: nowTs,
        );
        seen.add(localUuid);
      }

      final missing =
          existingMirror.keys.where((uuid) => !seen.contains(uuid)).toList();
      for (final uuid in missing) {
        final previous = existingMirror[uuid];
        if (previous == null) {
          continue;
        }
        final payload = Map<String, dynamic>.from(previous.payload);
        final previousDeletedAt = _asInt(payload['deleted_at']);
        final deleteStamp = previousDeletedAt ?? nowTs;
        payload['deleted_at'] = deleteStamp;
        payload['row_hash'] = previous.rowHash;
        changes.add(
          DeltaSyncChange(
            entity: config.entity,
            operation: 'delete',
            data: payload,
            rowHash: previous.rowHash,
            localUuid: uuid,
            clientTimestamp: deleteStamp,
          ),
        );
        debugPrint('إرسال كـ DELETE: ${config.entity}/$uuid');
      }

      snapshot[config.entity] = tableSnapshot;
    }

    final computation = DeltaSyncComputation(
      changes: changes,
      mirrorSnapshot: snapshot,
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
          if (uuid.isEmpty) continue;

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
      debugPrint('⚠️ Mirror inconsistency detected, repairing...');
      debugPrint('Issues: ${validation.issues.join(', ')}');
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
          if (uuid.isEmpty) continue;

          final sanitized = _preparePayload(config.toJson(row));
          sanitized['local_uuid'] = uuid;
          final rowHash = _hashPayload(sanitized);

          await db.customStatement(
            'REPLACE INTO sync_mirror (table_name, local_uuid, row_hash, payload, last_seen_at) VALUES (?, ?, ?, ?, ?)',
            [config.entity, uuid, rowHash, jsonEncode(sanitized), nowTs],
          );
        }
        debugPrint(
          '✅ Rebuilt mirror for ${config.entity} (${rows.length} rows)',
        );
      } catch (e) {
        debugPrint('❌ Failed to rebuild mirror for ${config.entity}: $e');
      }
    }

    debugPrint('✅ Mirror rebuild completed');
  }

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
      ),
      _EntityConfig(
        entity: 'bookings',
        fetchAll: () => db.select(db.bookings).get(),
        localUuid: (dynamic row) => (row as Booking).localUuid,
        createdAt: (dynamic row) => (row as Booking).createdAt,
        lastModified: (dynamic row) => (row as Booking).lastModified,
        deletedAt: (dynamic row) => (row as Booking).deletedAt,
        toJson: (dynamic row) => (row as Booking).toJson(),
      ),
      _EntityConfig(
        entity: 'booking_notes',
        fetchAll: () => db.select(db.bookingNotes).get(),
        localUuid: (dynamic row) => (row as BookingNote).localUuid,
        createdAt: (dynamic row) => (row as BookingNote).createdAt,
        lastModified: (dynamic row) => (row as BookingNote).lastModified,
        deletedAt: (dynamic row) => (row as BookingNote).deletedAt,
        toJson: (dynamic row) => (row as BookingNote).toJson(),
      ),
      _EntityConfig(
        entity: 'employees',
        fetchAll: () => db.select(db.employees).get(),
        localUuid: (dynamic row) => (row as Employee).localUuid,
        createdAt: (dynamic row) => (row as Employee).createdAt,
        lastModified: (dynamic row) => (row as Employee).lastModified,
        deletedAt: (dynamic row) => (row as Employee).deletedAt,
        toJson: (dynamic row) => (row as Employee).toJson(),
      ),
      _EntityConfig(
        entity: 'expenses',
        fetchAll: () => db.select(db.expenses).get(),
        localUuid: (dynamic row) => (row as Expense).localUuid,
        createdAt: (dynamic row) => (row as Expense).createdAt,
        lastModified: (dynamic row) => (row as Expense).lastModified,
        deletedAt: (dynamic row) => (row as Expense).deletedAt,
        toJson: (dynamic row) => (row as Expense).toJson(),
      ),
      _EntityConfig(
        entity: 'cash_transactions',
        fetchAll: () => db.select(db.cashTransactions).get(),
        localUuid: (dynamic row) => (row as CashTransaction).localUuid,
        createdAt: (dynamic row) => (row as CashTransaction).createdAt,
        lastModified: (dynamic row) => (row as CashTransaction).lastModified,
        deletedAt: (dynamic row) => (row as CashTransaction).deletedAt,
        toJson: (dynamic row) => (row as CashTransaction).toJson(),
      ),
      _EntityConfig(
        entity: 'payments',
        fetchAll: () => db.select(db.payments).get(),
        localUuid: (dynamic row) => (row as Payment).localUuid,
        createdAt: (dynamic row) => (row as Payment).createdAt,
        lastModified: (dynamic row) => (row as Payment).lastModified,
        deletedAt: (dynamic row) => (row as Payment).deletedAt,
        toJson: (dynamic row) => (row as Payment).toJson(),
      ),
      _EntityConfig(
        entity: 'debts',
        fetchAll: () => db.select(db.debts).get(),
        localUuid: (dynamic row) => (row as Debt).localUuid,
        createdAt: (dynamic row) => (row as Debt).createdAt,
        lastModified: (dynamic row) => (row as Debt).lastModified,
        deletedAt: (dynamic row) => (row as Debt).deletedAt,
        toJson: (dynamic row) => (row as Debt).toJson(),
      ),
      _EntityConfig(
        entity: 'booking_nights',
        fetchAll: () => db.select(db.bookingNights).get(),
        localUuid: (dynamic row) => (row as BookingNight).localUuid,
        createdAt: (dynamic row) => (row as BookingNight).createdAt,
        lastModified: (dynamic row) => (row as BookingNight).lastModified,
        deletedAt: (dynamic row) => (row as BookingNight).deletedAt,
        toJson: (dynamic row) => (row as BookingNight).toJson(),
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
      ),
      _EntityConfig(
        entity: 'hotel_day_ledger',
        fetchAll: () => db.select(db.hotelDayLedger).get(),
        localUuid: (dynamic row) => (row as HotelDayLedgerEntry).localUuid,
        createdAt: (dynamic row) => (row as HotelDayLedgerEntry).createdAt,
        lastModified: (dynamic row) =>
            (row as HotelDayLedgerEntry).lastModified,
        deletedAt: (dynamic row) => (row as HotelDayLedgerEntry).deletedAt,
        toJson: (dynamic row) => (row as HotelDayLedgerEntry).toJson(),
      ),
      _EntityConfig(
        entity: 'shift_notes',
        fetchAll: () => db.select(db.shiftNotes).get(),
        localUuid: (dynamic row) => (row as ShiftNote).localUuid,
        createdAt: (dynamic row) => (row as ShiftNote).createdAt,
        lastModified: (dynamic row) => (row as ShiftNote).lastModified,
        deletedAt: (dynamic row) => (row as ShiftNote).deletedAt,
        toJson: (dynamic row) => (row as ShiftNote).toJson(),
      ),
      _EntityConfig(
        entity: 'salary_cycles',
        fetchAll: () => db.select(db.salaryCycles).get(),
        localUuid: (dynamic row) => (row as SalaryCycle).localUuid,
        createdAt: (dynamic row) => (row as SalaryCycle).createdAt,
        lastModified: (dynamic row) => (row as SalaryCycle).lastModified,
        deletedAt: (dynamic row) => (row as SalaryCycle).deletedAt,
        toJson: (dynamic row) => (row as SalaryCycle).toJson(),
      ),
      _EntityConfig(
        entity: 'salary_payments',
        fetchAll: () => db.select(db.salaryPayments).get(),
        localUuid: (dynamic row) => (row as SalaryPayment).localUuid,
        createdAt: (dynamic row) => (row as SalaryPayment).createdAt,
        lastModified: (dynamic row) => (row as SalaryPayment).lastModified,
        deletedAt: (dynamic row) => (row as SalaryPayment).deletedAt,
        toJson: (dynamic row) => (row as SalaryPayment).toJson(),
      ),
      _EntityConfig(
        entity: 'price_adjustments',
        fetchAll: () => db.select(db.priceAdjustments).get(),
        localUuid: (dynamic row) => (row as PriceAdjustment).localUuid,
        createdAt: (dynamic row) => (row as PriceAdjustment).createdAt,
        lastModified: (dynamic row) => (row as PriceAdjustment).lastModified,
        deletedAt: (dynamic row) => (row as PriceAdjustment).deletedAt,
        toJson: (dynamic row) => (row as PriceAdjustment).toJson(),
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
      ),
      _EntityConfig(
        entity: 'audit_logs',
        fetchAll: () => db.select(db.auditLogs).get(),
        localUuid: (dynamic row) => (row as AuditLog).localUuid,
        createdAt: (dynamic row) => (row as AuditLog).createdAt,
        lastModified: (dynamic row) => (row as AuditLog).createdAt,
        deletedAt: (dynamic row) => null,
        toJson: (dynamic row) => (row as AuditLog).toJson(),
      ),
      _EntityConfig(
        entity: 'payment_voids',
        fetchAll: () => db.select(db.paymentVoids).get(),
        localUuid: (dynamic row) => (row as PaymentVoid).localUuid,
        createdAt: (dynamic row) => (row as PaymentVoid).createdAt,
        lastModified: (dynamic row) => (row as PaymentVoid).lastModified,
        deletedAt: (dynamic row) => (row as PaymentVoid).deletedAt,
        toJson: (dynamic row) => (row as PaymentVoid).toJson(),
      ),
      _EntityConfig(
        entity: 'guest_infos',
        fetchAll: () => db.select(db.guestInfos).get(),
        localUuid: (dynamic row) => (row as GuestInfo).localUuid,
        createdAt: (dynamic row) => (row as GuestInfo).createdAt,
        lastModified: (dynamic row) => (row as GuestInfo).lastModified,
        deletedAt: (dynamic row) => (row as GuestInfo).deletedAt,
        toJson: (dynamic row) => (row as GuestInfo).toJson(),
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

class _EntityConfig {
  const _EntityConfig({
    required this.entity,
    required this.fetchAll,
    required this.localUuid,
    required this.createdAt,
    required this.lastModified,
    required this.deletedAt,
    required this.toJson,
  });

  final String entity;
  final Future<List<dynamic>> Function() fetchAll;
  final String Function(dynamic row) localUuid;
  final int? Function(dynamic row) createdAt;
  final int? Function(dynamic row) lastModified;
  final int? Function(dynamic row) deletedAt;
  final Map<String, dynamic> Function(dynamic row) toJson;
}

int _normalizeTimestamp(int value) {
  if (value <= 0) {
    return value;
  }
  return value < 1000000000000 ? value * 1000 : value;
}

Map<String, dynamic> _preparePayload(Map<String, dynamic> source) {
  final result = <String, dynamic>{};
  source.forEach((key, value) {
    final newKey = _toSnakeCase(key);
    result[newKey] = _normalizeValue(value);
  });
  return result;
}

dynamic _normalizeValue(dynamic value) {
  if (value is int) {
    return _normalizeTimestamp(value);
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
        return _normalizeTimestamp(item);
      }
      return item;
    }).toList();
  }
  return value;
}

String _hashPayload(Map<String, dynamic> payload) {
  final sorted = _sortedMap(payload);
  return sha1.convert(utf8.encode(jsonEncode(sorted))).toString();
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
  }).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
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
