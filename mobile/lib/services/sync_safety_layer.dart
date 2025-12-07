import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'local_db.dart';

class SyncSafetySnapshot {
  SyncSafetySnapshot({
    required this.syncId,
    required this.phase,
    required this.filePath,
    required this.createdAt,
  });

  final String syncId;
  final String phase;
  final String filePath;
  final DateTime createdAt;

  String get key => '$syncId|$phase';
}

/// طبقة حماية المزامنة: مسؤولة عن إنشاء نسخ JSON قبل المزامنة
/// وتسجيل سجل Rollback وإدخال بيانات التدقيق في جدول sync_audit.
class SyncSafetyLayer {
  SyncSafetyLayer._();

  static final SyncSafetyLayer instance = SyncSafetyLayer._();

  Directory? _baseDirectoryOverride;
  final Map<String, SyncSafetySnapshot> _activeSnapshots = {};
  bool _auditTableEnsured = false;

  /// تخصيص دليل مخصص لأغراض الاختبار فقط.
  @visibleForTesting
  void setTestingDirectory(Directory directory) {
    _baseDirectoryOverride = directory;
  }

  Future<SyncSafetySnapshot> captureSnapshot({
    required AppDatabase db,
    required String syncId,
    required String phase,
  }) async {
    final dir = await _ensureBaseDirectory();
    final timestamp = DateTime.now().toUtc();
    final fileName =
        'snapshot_${syncId.replaceAll(':', '_')}_${phase}_${timestamp.microsecondsSinceEpoch}.json';
    final file = File(p.join(dir.path, fileName));

    final tables = await db.getAllTablesAsJson();
    final payload = <String, dynamic>{
      'syncId': syncId,
      'phase': phase,
      'createdAt': timestamp.toIso8601String(),
      'tables': tables,
    };

    await file.writeAsString(jsonEncode(payload));

    final snapshot = SyncSafetySnapshot(
      syncId: syncId,
      phase: phase,
      filePath: file.path,
      createdAt: timestamp,
    );

    _activeSnapshots[snapshot.key] = snapshot;

    await _appendLog({
      'event': 'snapshot',
      'syncId': syncId,
      'phase': phase,
      'file': snapshot.filePath,
      'timestamp': snapshot.createdAt.toIso8601String(),
    });

    return snapshot;
  }

  Future<void> commitSnapshot({
    required AppDatabase db,
    required SyncSafetySnapshot snapshot,
    required String direction,
    required String checksum,
    required String deviceId,
    required Map<String, dynamic> metadata,
  }) async {
    await _ensureAuditTable(db);
    final createdAt = DateTime.now().toUtc();

    await db.customStatement(
      'INSERT INTO sync_audit (sync_id, direction, checksum, schema_version, device_id, status, created_at, metadata) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        snapshot.syncId,
        direction,
        checksum,
        db.schemaVersion,
        deviceId,
        'success',
        createdAt.toIso8601String(),
        jsonEncode(metadata),
      ],
    );

    await _appendLog({
      'event': 'commit',
      'syncId': snapshot.syncId,
      'phase': snapshot.phase,
      'timestamp': createdAt.toIso8601String(),
      'metadata': metadata,
    });

    await _cleanupSnapshot(snapshot);
  }

  Future<void> rollbackSnapshot({
    required AppDatabase db,
    required SyncSafetySnapshot snapshot,
    required Object error,
  }) async {
    final file = File(snapshot.filePath);
    final rollbackAt = DateTime.now().toUtc();

    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final decoded = jsonDecode(content) as Map<String, dynamic>;
        final tables = Map<String, dynamic>.from(decoded['tables'] as Map);
        await db.applyMergedData(tables);
      } catch (rollbackError, stack) {
        debugPrint('❌ CRITICAL: Failed to rollback snapshot ${snapshot.filePath}. Error: $rollbackError');
        await _appendLog({
          'event': 'rollback-error',
          'syncId': snapshot.syncId,
          'phase': snapshot.phase,
          'timestamp': rollbackAt.toIso8601String(),
          'error': rollbackError.toString(),
          'stack': stack.toString(),
        });
      }
    }

    await _appendLog({
      'event': 'rollback',
      'syncId': snapshot.syncId,
      'phase': snapshot.phase,
      'timestamp': rollbackAt.toIso8601String(),
      'error': error.toString(),
    });

    _activeSnapshots.remove(snapshot.key);
  }

  Future<void> _cleanupSnapshot(SyncSafetySnapshot snapshot) async {
    _activeSnapshots.remove(snapshot.key);
    final file = File(snapshot.filePath);
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<Directory> _ensureBaseDirectory() async {
    if (_baseDirectoryOverride != null) {
      return _baseDirectoryOverride!;
    }

    final dir = await getApplicationSupportDirectory();
    final target = Directory(p.join(dir.path, 'sync_safety'));
    if (!await target.exists()) {
      await target.create(recursive: true);
    }
    return target;
  }

  Future<File> _logFile() async {
    final dir = await _ensureBaseDirectory();
    final file = File(p.join(dir.path, 'sync_rollback.log'));
    if (!await file.exists()) {
      await file.create(recursive: true);
    }
    return file;
  }

  Future<void> _appendLog(Map<String, dynamic> payload) async {
    try {
      final file = await _logFile();
      await file.writeAsString('${jsonEncode(payload)}\n', mode: FileMode.append, flush: true);
    } catch (_) {
      // تجاهل أخطاء السجل حتى لا تؤثر على سير المزامنة
    }
  }

  Future<void> _ensureAuditTable(AppDatabase db) async {
    if (_auditTableEnsured) {
      return;
    }
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS sync_audit ('
      'id INTEGER PRIMARY KEY AUTOINCREMENT,'
      'sync_id TEXT,'
      'direction TEXT,'
      'checksum TEXT,'
      'schema_version INTEGER,'
      'device_id TEXT,'
      'status TEXT,'
      'created_at TEXT,'
      'metadata TEXT'
      ')',
    );
    _auditTableEnsured = true;
  }
}
