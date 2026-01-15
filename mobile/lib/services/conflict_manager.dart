import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'local_db.dart';

class PendingConflict {
  const PendingConflict({
    required this.id,
    required this.table,
    required this.uuid,
    required this.localData,
    required this.remoteData,
    required this.detectedAt,
    this.autoResolvedAt,
    this.manualResolvedAt,
    this.resolution,
  });

  final String id;
  final String table;
  final String uuid;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;
  final DateTime detectedAt;
  final DateTime? autoResolvedAt;
  final DateTime? manualResolvedAt;
  final Map<String, dynamic>? resolution;

  bool get isPending => resolution == null;
  bool get isResolved => resolution != null;
  bool get wasAutoResolved => autoResolvedAt != null;
  bool get wasManualResolved => manualResolvedAt != null;
}

/// مدير التعارضات - يحفظ التعارضات غير المحلولة للمراجعة
class ConflictManager {
  ConflictManager(this.db);

  final AppDatabase db;
  final _conflictsController =
      StreamController<List<PendingConflict>>.broadcast();
  final List<PendingConflict> _pendingConflicts = [];

  Stream<List<PendingConflict>> get conflictsStream =>
      _conflictsController.stream;
  List<PendingConflict> get pendingConflicts =>
      List.unmodifiable(_pendingConflicts);
  int get pendingCount => _pendingConflicts.length;

  Future<void> recordConflict({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    Map<String, dynamic>? autoResolution,
  }) async {
    final conflictId =
        '${table}_${uuid}_${DateTime.now().millisecondsSinceEpoch}';

    final conflict = PendingConflict(
      id: conflictId,
      table: table,
      uuid: uuid,
      localData: localData,
      remoteData: remoteData,
      detectedAt: DateTime.now(),
      autoResolvedAt: autoResolution != null ? DateTime.now() : null,
      resolution: autoResolution,
    );

    if (autoResolution == null) {
      _pendingConflicts.add(conflict);
      _conflictsController.add(_pendingConflicts);
    }

    await _persistConflict(conflict);
  }

  Future<void> resolveManually({
    required String conflictId,
    required Map<String, dynamic> resolution,
  }) async {
    final index = _pendingConflicts.indexWhere((c) => c.id == conflictId);
    if (index == -1) return;

    final conflict = _pendingConflicts[index];
    final resolved = PendingConflict(
      id: conflict.id,
      table: conflict.table,
      uuid: conflict.uuid,
      localData: conflict.localData,
      remoteData: conflict.remoteData,
      detectedAt: conflict.detectedAt,
      manualResolvedAt: DateTime.now(),
      resolution: resolution,
    );

    _pendingConflicts[index] = resolved;
    await _updateConflictResolution(conflictId, resolution);

    _pendingConflicts.removeAt(index);
    _conflictsController.add(_pendingConflicts);
  }

  Future<void> _persistConflict(PendingConflict conflict) async {
    try {
      final existingQuery = db.select(db.syncConflicts)
        ..where((t) =>
            t.targetTable.equals(conflict.table) &
            t.uuid.equals(conflict.uuid));

      final existing = await existingQuery.getSingleOrNull();

      if (existing != null) {
        await (db.update(db.syncConflicts)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          SyncConflictsCompanion(
            localPayload: Value(jsonEncode(conflict.localData)),
            remotePayload: Value(jsonEncode(conflict.remoteData)),
            resolution: Value(conflict.resolution != null
                ? jsonEncode(conflict.resolution)
                : ''),
          ),
        );
      } else {
        // Get latest sync log ID or use 0
        final latestLog = await (db.select(db.syncLog)
              ..orderBy([(t) => OrderingTerm.desc(t.id)])
              ..limit(1))
            .getSingleOrNull();

        await db.into(db.syncConflicts).insert(
              SyncConflictsCompanion.insert(
                logId: latestLog?.id ?? 0,
                targetTable: conflict.table,
                uuid: conflict.uuid,
                localPayload: jsonEncode(conflict.localData),
                remotePayload: jsonEncode(conflict.remoteData),
                resolution: conflict.resolution != null
                    ? jsonEncode(conflict.resolution)
                    : '',
                createdAt: conflict.detectedAt.toIso8601String(),
              ),
            );
      }
    } catch (e) {
      debugPrint('❌ فشل حفظ التعارض: $e');
    }
  }

  Future<void> _updateConflictResolution(
      String conflictId, Map<String, dynamic> resolution) async {
    try {
      final parts = conflictId.split('_');
      if (parts.length < 2) return;

      final table = parts[0];
      final uuid = parts[1];

      final query = db.select(db.syncConflicts)
        ..where((t) => t.targetTable.equals(table) & t.uuid.equals(uuid));

      final existing = await query.getSingleOrNull();
      if (existing != null) {
        await (db.update(db.syncConflicts)
              ..where((t) => t.id.equals(existing.id)))
            .write(
          SyncConflictsCompanion(
            resolution: Value(jsonEncode(resolution)),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ فشل تحديث حل التعارض: $e');
    }
  }

  Future<void> loadPendingConflicts() async {
    try {
      final conflicts = await (db.select(db.syncConflicts)
            ..where((t) => t.resolution.equals(''))
            ..orderBy([(t) => OrderingTerm.desc(t.id)]))
          .get();

      _pendingConflicts.clear();

      for (final row in conflicts) {
        Map<String, dynamic> localData = {};
        Map<String, dynamic> remoteData = {};
        Map<String, dynamic>? resolutionData;

        try {
          localData = jsonDecode(row.localPayload);
          remoteData = jsonDecode(row.remotePayload);
          if (row.resolution.isNotEmpty) {
            resolutionData = jsonDecode(row.resolution);
          }
        } catch (e) {
          debugPrint('❌ فشل في فك ترميز بيانات التعارض: $e');
        }

        _pendingConflicts.add(PendingConflict(
          id: '${row.targetTable}_${row.uuid}_${DateTime.parse(row.createdAt).millisecondsSinceEpoch}',
          table: row.targetTable,
          uuid: row.uuid,
          localData: localData,
          remoteData: remoteData,
          detectedAt: DateTime.parse(row.createdAt),
          resolution: resolutionData,
        ));
      }

      _conflictsController.add(_pendingConflicts);
    } catch (e) {
      debugPrint('❌ فشل تحميل التعارضات المعلقة: $e');
    }
  }

  void dispose() {
    _conflictsController.close();
  }
}
