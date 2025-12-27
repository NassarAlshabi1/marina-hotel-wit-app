import 'dart:async';
import 'package:flutter/foundation.dart';
import 'conflict_resolver.dart';
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
  final _conflictsController = StreamController<List<PendingConflict>>.broadcast();
  final List<PendingConflict> _pendingConflicts = [];

  Stream<List<PendingConflict>> get conflictsStream => _conflictsController.stream;
  List<PendingConflict> get pendingConflicts => List.unmodifiable(_pendingConflicts);
  int get pendingCount => _pendingConflicts.length;

  Future<void> recordConflict({
    required String table,
    required String uuid,
    required Map<String, dynamic> localData,
    required Map<String, dynamic> remoteData,
    Map<String, dynamic>? autoResolution,
  }) async {
    final conflictId = '${table}_${uuid}_${DateTime.now().millisecondsSinceEpoch}';
    
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
        ..where((t) => t.tableName.equals(conflict.table) & t.recordUuid.equals(conflict.uuid));
      
      final existing = await existingQuery.getSingleOrNull();
      
      if (existing != null) {
        await (db.update(db.syncConflicts)..where((t) => t.id.equals(existing.id))).write(
          SyncConflictsCompanion(
            localSnapshot: Value(conflict.localData.toString()),
            remoteSnapshot: Value(conflict.remoteData.toString()),
            detectedAt: Value(conflict.detectedAt.toIso8601String()),
            status: const Value('pending'),
          ),
        );
      } else {
        await db.into(db.syncConflicts).insert(
          SyncConflictsCompanion.insert(
            tableName: conflict.table,
            recordUuid: conflict.uuid,
            localSnapshot: conflict.localData.toString(),
            remoteSnapshot: conflict.remoteData.toString(),
            detectedAt: conflict.detectedAt.toIso8601String(),
            status: 'pending',
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ فشل حفظ التعارض: $e');
    }
  }

  Future<void> _updateConflictResolution(String conflictId, Map<String, dynamic> resolution) async {
    try {
      final parts = conflictId.split('_');
      if (parts.length < 2) return;
      
      final table = parts[0];
      final uuid = parts[1];
      
      final query = db.select(db.syncConflicts)
        ..where((t) => t.tableName.equals(table) & t.recordUuid.equals(uuid));
      
      final existing = await query.getSingleOrNull();
      if (existing != null) {
        await (db.update(db.syncConflicts)..where((t) => t.id.equals(existing.id))).write(
          SyncConflictsCompanion(
            resolvedSnapshot: Value(resolution.toString()),
            resolvedAt: Value(DateTime.now().toIso8601String()),
            status: const Value('resolved'),
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
        ..where((t) => t.status.equals('pending'))
        ..orderBy([(t) => OrderingTerm.desc(t.id)])).get();
      
      _pendingConflicts.clear();
      
      for (final row in conflicts) {
        Map<String, dynamic> localData = {};
        Map<String, dynamic> remoteData = {};
        try {
          if (row.localSnapshot != null) {
            localData = jsonDecode(row.localSnapshot!);
          }
          if (row.remoteSnapshot != null) {
            remoteData = jsonDecode(row.remoteSnapshot!);
          }
        } catch(e) {
          debugPrint('❌ فشل في فك ترميز بيانات التعارض: $e');
        }

        _pendingConflicts.add(PendingConflict(
          id: '${row.tableName}_${row.recordUuid}_${DateTime.parse(row.detectedAt).millisecondsSinceEpoch}',
          table: row.tableName,
          uuid: row.recordUuid,
          localData: localData,
          remoteData: remoteData,
          detectedAt: DateTime.parse(row.detectedAt),
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
