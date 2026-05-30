import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';
import '../utils/app_logger.dart';
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
        AppLogger.info('تم نسخ ملف SQLite إلى: $dbBackupPath');
      }
    } catch (e) {
      AppLogger.warning('خطأ في نسخ ملف SQLite: $e');
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

    if (!file.existsSync()) {
      AppLogger.error('ملف النسخة الاحتياطية غير موجود: ${snapshot.filePath}');
      _activeSnapshots.remove(snapshot.key);
      return false;
    }

    try {
      final content = await file.readAsString();
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final localTables = Map<String, dynamic>.from(decoded['tables'] as Map);

      // ✅ إصلاح: تعطيل FK خارج transaction لأن SQLite يتجاهل PRAGMA داخل transaction
      await db.customStatement('PRAGMA foreign_keys = OFF');

      try {
        await db.transaction(() async {
          await _clearAllTables(db);

          for (final tableName in SyncConstants.allTablesInOrder) {
            if (localTables.containsKey(tableName)) {
              await _restoreTable(db, tableName, localTables[tableName]);
            }
          }
        });

        await _appendLog({
          'event': 'rollback-success',
          'syncId': snapshot.syncId,
          'phase': snapshot.phase,
          'timestamp': rollbackAt.toIso8601String(),
        });

        AppLogger.info('تم استعادة قاعدة البيانات بنجاح من النسخة الاحتياطية');
        _activeSnapshots.remove(snapshot.key);
        return true;
      } catch (rollbackError, stack) {
        AppLogger.error('CRITICAL: فشل التراجع — transaction تم التراجع عنها تلقائياً');
        await _appendLog({
          'event': 'rollback-error',
          'syncId': snapshot.syncId,
          'phase': snapshot.phase,
          'timestamp': rollbackAt.toIso8601String(),
          'error': rollbackError.toString(),
          'stack': stack.toString(),
        });
        // ✅ إصلاح: لا نحاول استعادة يدوية ثانية خارج transaction
        // لأن الحذف تم داخل transaction والـ rollback التلقائي يعيد البيانات
        return false;
      } finally {
        // ✅ ضمان إعادة تشغيل FK في كل حالة
        try {
          await db.customStatement('PRAGMA foreign_keys = ON');
          AppLogger.info('تم إعادة تشغيل FOREIGN KEYS');

          // ✅ تحقق من سلامة المفاتيح الأجنبية بعد إعادة التفعيل
          try {
            final violations = await db.customSelect(
              'PRAGMA foreign_key_check',
              readsFrom: Set.unmodifiable({}),
            ).get();
            if (violations.isNotEmpty) {
              developer.log(
                '⚠️ FK violations after sync: ${violations.length} rows',
                name: 'SyncSafety',
              );
            }
          } catch (_) {}
        } catch (e) {
          AppLogger.warning('فشل إعادة تشغيل FOREIGN KEYS: $e');
        }
      }
    } catch (readError, stack) {
      AppLogger.error('فشل قراءة ملف النسخة الاحتياطية: $readError');
      await _appendLog({
        'event': 'rollback-error',
        'syncId': snapshot.syncId,
        'phase': snapshot.phase,
        'timestamp': rollbackAt.toIso8601String(),
        'error': readError.toString(),
        'stack': stack.toString(),
      });
      return false;
    }
  }

  Future<void> _cleanupSnapshot(SyncSafetySnapshot snapshot) async {
    _activeSnapshots.remove(snapshot.key);
    final file = File(snapshot.filePath);
    if (file.existsSync()) {
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
    if (!target.existsSync()) {
      await target.create(recursive: true);
    }
    return target;
  }

  Future<File> _logFile() async {
    final dir = await _ensureBaseDirectory();
    final file = File(p.join(dir.path, 'sync_rollback.log'));
    if (!file.existsSync()) {
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
      ' id INTEGER PRIMARY KEY AUTOINCREMENT,'
      ' sync_id TEXT,'
      ' direction TEXT,'
      ' checksum TEXT,'
      ' schema_version INTEGER,'
      ' device_id TEXT,'
      ' status TEXT,'
      ' created_at TEXT,'
      ' metadata TEXT '
      ')',
    );
    _auditTableEnsured = true;
  }

  Future<void> _clearAllTables(AppDatabase db) async {
    // ملاحظة: FOREIGN KEYS يتم تعطيلها خارج transaction قبل استدعاء هذه الدالة

    for (final table in SyncConstants.allTablesInReverseOrder) {
      try {
        await db.customStatement('DELETE FROM $table');
      } on Exception catch (e) {
        if (e.toString().contains('no such table')) {
          AppLogger.info('الجدول غير موجود، تخطي الحذف: $table');
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
    if (tableData == null) {
      return;
    }

    final rows = (tableData as List<dynamic>)
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();

    if (rows.isEmpty) {
      return;
    }

    final existingColumns = await _tableColumns(db, tableName);

    await db.batch((batch) {
      for (final row in rows) {
        final normalized = <String, dynamic>{};
        for (final entry in row.entries) {
          normalized[_normalizeColumnName(entry.key)] = entry.value;
        }
        final filtered = Map<String, dynamic>.fromEntries(
          normalized.entries.where((e) => existingColumns.contains(e.key)),
        );
        if (filtered.isEmpty) {
          debugPrint(
            '⚠️ تخطي استعادة صف فارغ لـ $tableName بسبب اختلاف الأعمدة',
          );
          continue;
        }
        final columns = filtered.keys.toList();
        final values = filtered.values.toList();
        final placeholders = List.filled(values.length, '?').join(', ');
        final columnNames = columns.join(', ');

        batch.customStatement(
          'INSERT OR REPLACE INTO $tableName ($columnNames) VALUES ($placeholders)',
          values,
        );
      }
    });
    AppLogger.info('تم استعادة ${rows.length} سجل من $tableName');
  }

  Future<Set<String>> _tableColumns(AppDatabase db, String tableName) async {
    final result = await db.customSelect('PRAGMA table_info($tableName)').get();
    return result.map((r) => r.data['name'] as String).toSet();
  }

  String _normalizeColumnName(String key) {
    if (key.contains('_')) {
      return key.toLowerCase();
    }
    return key
        .replaceAllMapped(
          RegExp('([a-z0-9])([A-Z])'),
          (m) => '${m[1]}_${m[2]!.toLowerCase()}',
        )
        .toLowerCase();
  }

  Future<String?> _getDatabasePath() async {
    try {
      final dbDir = await sqflite.getDatabasesPath();
      final dbPath = p.join(dbDir, 'marina_hotel.db');
      if (File(dbPath).existsSync()) {
        return dbPath;
      }
    } catch (e) {
      AppLogger.warning('خطأ في الحصول على مسار قاعدة البيانات: $e');
    }
    return null;
  }
}
