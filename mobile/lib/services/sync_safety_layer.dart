import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart' as sqflite;

import 'local_db.dart';
import 'sync_constants.dart';

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

    try {
      final dbPath = await _getDatabasePath();
      if (dbPath != null) {
        final dbBackupPath = p.join(
          dir.path,
          'db_${syncId.replaceAll(':', '_')}_${phase}_${timestamp.microsecondsSinceEpoch}.sqlite',
        );
        await File(dbPath).copy(dbBackupPath);
        tables['sqliteBackupPath'] = dbBackupPath;
        debugPrint('✅ تم نسخ ملف SQLite إلى: $dbBackupPath');
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في نسخ ملف SQLite: $e');
    }

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

  Future<bool> rollbackSnapshot({
    required AppDatabase db,
    required SyncSafetySnapshot snapshot,
    required Object error,
  }) async {
    final file = File(snapshot.filePath);
    final rollbackAt = DateTime.now().toUtc();

    if (!await file.exists()) {
      debugPrint('❌ ملف النسخة الاحتياطية غير موجود: ${snapshot.filePath}');
      _activeSnapshots.remove(snapshot.key);
      return false;
    }

    Map<String, dynamic>? tables;

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      tables = Map<String, dynamic>.from(decoded['tables'] as Map);
      final localTables = tables;

      if (localTables == null) {
        throw StateError('Snapshot tables missing');
      }

      try {
        await db.transaction(() async {
          await _clearAllTables(db);

          for (final tableName in SyncConstants.allTablesInOrder) {
            if (localTables.containsKey(tableName)) {
              await _restoreTable(db, tableName, localTables[tableName]);
            }
          }
        });
      } finally {
        // إعادة تشغيل FOREIGN KEYS بعد الانتهاء من الحذف والاستعادة
        await db.customStatement('PRAGMA foreign_keys = ON');
        debugPrint('🔓 تم إعادة تشغيل FOREIGN KEYS');
      }

      await _appendLog({
        'event': 'rollback-success',
        'syncId': snapshot.syncId,
        'phase': snapshot.phase,
        'timestamp': rollbackAt.toIso8601String(),
      });

      debugPrint('✅ تم استعادة قاعدة البيانات بنجاح من النسخة الاحتياطية');
      _activeSnapshots.remove(snapshot.key);
      return true;
    } catch (rollbackError, stack) {
      debugPrint(
        '❌ CRITICAL: Rollback failed - attempting SQLite file restore',
      );
      await _appendLog({
        'event': 'rollback-error',
        'syncId': snapshot.syncId,
        'phase': snapshot.phase,
        'timestamp': rollbackAt.toIso8601String(),
        'error': rollbackError.toString(),
        'stack': stack.toString(),
      });

      // محاولة استعادة الجداول مباشرة قبل اللجوء لنسخة SQLite
      if (tables != null) {
        try {
          await _clearAllTables(db);
        } catch (_) {}
        var restored = false;
        for (final tableName in SyncConstants.allTablesInOrder) {
          if (tables.containsKey(tableName)) {
            try {
              await _restoreTable(db, tableName, tables[tableName]);
              restored = true;
            } catch (e) {
              debugPrint('⚠️ تعذر استعادة جدول $tableName: $e');
            }
          }
        }
        if (restored) {
          _activeSnapshots.remove(snapshot.key);
          return true;
        }
      }

      return await _attemptFileRestore(db, file.path);
    }
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

    Directory dir;
    try {
      dir = await getApplicationSupportDirectory();
    } catch (_) {
      dir = await Directory.systemTemp.createTemp('sync_support_');
    }
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
      await file.writeAsString(
        '${jsonEncode(payload)}\n',
        mode: FileMode.append,
        flush: true,
      );
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

  Future<void> _clearAllTables(AppDatabase db) async {
    // ملاحظة: FOREIGN KEYS يتم تعطيلها هنا ولكن لا يتم إعادة تشغيلها
    // لأن الاستعادة ستحدث مباشرة بعد الحذف في نفس transaction
    await db.customStatement('PRAGMA foreign_keys = OFF');

    for (final table in SyncConstants.allTablesInReverseOrder) {
      try {
        await db.customStatement('DELETE FROM $table');
      } on Exception catch (e) {
        if (e.toString().contains('no such table')) {
          debugPrint('ℹ️ الجدول غير موجود، تخطي الحذف: $table');
        } else {
          rethrow;
        }
      }
    }
  }

  Future<void> _restoreTable(
    AppDatabase db,
    String tableName,
    dynamic tableData,
  ) async {
    if (tableData == null) return;

    final rows = (tableData as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    if (rows.isEmpty) return;

    await db.batch((batch) {
      for (final row in rows) {
        final columns = row.keys.toList();
        final values = row.values.toList();
        final placeholders = List.filled(values.length, '?').join(', ');
        final columnNames = columns.join(', ');

        batch.customStatement(
          'INSERT OR REPLACE INTO $tableName ($columnNames) VALUES ($placeholders)',
          values,
        );
      }
    });
    debugPrint('✅ تم استعادة ${rows.length} سجل من $tableName');
  }

  Future<bool> _attemptFileRestore(AppDatabase db, String snapshotPath) async {
    try {
      final content = await File(snapshotPath).readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final tables = Map<String, dynamic>.from(decoded['tables'] as Map);
      final sqliteBackupPath = tables['sqliteBackupPath'] as String?;

      if (sqliteBackupPath == null || !await File(sqliteBackupPath).exists()) {
        debugPrint('❌ لا توجد نسخة احتياطية من ملف SQLite');
        return false;
      }

      final dbPath = await _getDatabasePath();
      if (dbPath == null) {
        debugPrint('❌ لم يتم العثور على مسار قاعدة البيانات');
        return false;
      }

      await DatabaseManager.close();
      await File(sqliteBackupPath).copy(dbPath);
      await DatabaseManager.reopen();
      debugPrint('✅ تم استعادة ملف SQLite بنجاح وإعادة فتح قاعدة البيانات');

      await _appendLog({
        'event': 'file-restore-success',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'source': sqliteBackupPath,
        'target': dbPath,
      });

      return true;
    } catch (e, stack) {
      debugPrint('❌ فشلت استعادة ملف SQLite: $e');
      await _appendLog({
        'event': 'file-restore-error',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'error': e.toString(),
        'stack': stack.toString(),
      });
      return false;
    }
  }

  Future<String?> _getDatabasePath() async {
    try {
      final dbDir = await sqflite.getDatabasesPath();
      final dbPath = p.join(dbDir, 'marina_hotel.db');
      if (await File(dbPath).exists()) {
        return dbPath;
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في الحصول على مسار قاعدة البيانات: $e');
    }
    return null;
  }
}
