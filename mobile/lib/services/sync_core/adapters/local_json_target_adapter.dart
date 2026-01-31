import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../local_db.dart';
import '../events/sync_event.dart';
import 'sync_target_adapter.dart';

class LocalJsonTargetAdapter extends BackupCapableAdapter {
  final AppDatabase _database;
  bool _initialized = false;
  bool _enabled = true;
  DateTime? _lastSyncAt;
  String? _lastError;
  String? _backupDirectory;

  static const String _backupDirName = 'marina_backups';
  static const String _currentBackupFile = 'current_backup.json';
  static const int _maxBackups = 10;

  LocalJsonTargetAdapter({
    required AppDatabase database,
  }) : _database = database;

  @override
  SyncTargetType get type => SyncTargetType.localJson;

  @override
  String get name => 'local_json';

  @override
  String get displayName => 'نسخة احتياطية محلية';

  @override
  bool get isAvailable => true;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _backupDirectory = '${appDir.path}/$_backupDirName';

      final dir = Directory(_backupDirectory!);
      if (!dir.existsSync()) {
        await dir.create(recursive: true);
      }

      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('local_backup_enabled') ?? true;

      _initialized = true;
      debugPrint('LocalJsonTargetAdapter: Initialized at $_backupDirectory');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('LocalJsonTargetAdapter: Initialization failed: $e');
      rethrow;
    }
  }

  @override
  Future<bool> checkConnection() async {
    if (_backupDirectory == null) return false;
    return Directory(_backupDirectory!).existsSync();
  }

  @override
  Future<SyncTargetStatus> getStatus() async {
    final isConnected = await checkConnection();
    final backups = await listBackups();

    return SyncTargetStatus(
      type: type,
      isAvailable: true,
      isEnabled: _enabled,
      isConnected: isConnected,
      lastSyncAt: _lastSyncAt,
      lastError: _lastError,
      pendingCount: 0,
      metadata: {
        'backupCount': backups.length,
        'directory': _backupDirectory,
      },
    );
  }

  @override
  Future<SyncPushResult> push(List<EnhancedSyncEvent> events) async {
    if (!_initialized || !_enabled) {
      return SyncPushResult.failure(
        error: 'Adapter not ready',
        failedIds: events.map((e) => e.id).toList(),
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      final snapshot = await _createSnapshot();
      final file = File('$_backupDirectory/$_currentBackupFile');
      await file.writeAsString(jsonEncode(snapshot));

      stopwatch.stop();
      _lastSyncAt = DateTime.now();

      return SyncPushResult.success(
        affectedCount: events.length,
        duration: stopwatch.elapsed,
        syncedIds: events.map((e) => e.id).toList(),
      );
    } catch (e) {
      stopwatch.stop();
      _lastError = e.toString();
      return SyncPushResult.failure(
        error: e.toString(),
        duration: stopwatch.elapsed,
        failedIds: events.map((e) => e.id).toList(),
      );
    }
  }

  @override
  Future<SyncPullResult> pull({
    DateTime? since,
    List<String>? tables,
    int? limit,
  }) async {
    return SyncPullResult.success(
      lastSyncTimestamp: DateTime.now(),
    );
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('local_backup_enabled', enabled);
  }

  @override
  Future<void> reset() async {
    _lastSyncAt = null;
    _lastError = null;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
  }

  @override
  Future<String> createBackup({String? tag}) async {
    if (!_initialized || _backupDirectory == null) {
      throw StateError('Adapter not initialized');
    }

    final timestamp = DateTime.now();
    final backupId = 'backup_${timestamp.millisecondsSinceEpoch}';
    final fileName = tag != null ? '${backupId}_$tag.json' : '$backupId.json';

    final snapshot = await _createSnapshot();
    snapshot['_meta'] = {
      'id': backupId,
      'tag': tag,
      'createdAt': timestamp.toIso8601String(),
      'version': 1,
    };

    final file = File('$_backupDirectory/$fileName');
    await file.writeAsString(jsonEncode(snapshot), flush: true);

    await _cleanupOldBackups();

    return backupId;
  }

  @override
  Future<void> restoreFromBackup(String backupId) async {
    if (!_initialized || _backupDirectory == null) {
      throw StateError('Adapter not initialized');
    }

    final dir = Directory(_backupDirectory!);
    final files = dir.listSync().whereType<File>();

    File? backupFile;
    for (final file in files) {
      if (file.path.contains(backupId)) {
        backupFile = file;
        break;
      }
    }

    if (backupFile == null) {
      throw FileSystemException('Backup not found: $backupId');
    }

    final content = await backupFile.readAsString();
    final snapshot = jsonDecode(content) as Map<String, dynamic>;

    await _restoreSnapshot(snapshot);
  }

  @override
  Future<List<BackupInfo>> listBackups({int? limit}) async {
    if (!_initialized || _backupDirectory == null) {
      return [];
    }

    final dir = Directory(_backupDirectory!);
    if (!dir.existsSync()) return [];

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json') && f.path.contains('backup_'))
        .toList();

    files.sort((a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()));

    final backups = <BackupInfo>[];
    for (final file in files.take(limit ?? files.length)) {
      try {
        final stat = file.statSync();
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        final meta = data['_meta'] as Map<String, dynamic>?;

        backups.add(BackupInfo(
          id: meta?['id'] ?? file.path.split('/').last.replaceAll('.json', ''),
          createdAt: meta?['createdAt'] != null
              ? DateTime.parse(meta!['createdAt'] as String)
              : stat.modified,
          sizeBytes: stat.size,
          tag: meta?['tag'] as String?,
          tableCounts: _extractTableCounts(data),
        ));
      } catch (e) {
        debugPrint('LocalJsonTargetAdapter: Error reading backup: $e');
      }
    }

    return backups;
  }

  @override
  Future<void> deleteBackup(String backupId) async {
    if (!_initialized || _backupDirectory == null) {
      throw StateError('Adapter not initialized');
    }

    final dir = Directory(_backupDirectory!);
    final files = dir.listSync().whereType<File>();

    for (final file in files) {
      if (file.path.contains(backupId)) {
        await file.delete();
        return;
      }
    }

    throw FileSystemException('Backup not found: $backupId');
  }

  Future<Map<String, dynamic>> _createSnapshot() async {
    final results = await Future.wait([
      (_database.select(_database.rooms)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.bookings)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.bookingNotes)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.bookingNights)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.employees)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.expenses)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.cashTransactions)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.payments)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.debts)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.hotelDayLedger)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.shiftNotes)).get(),
      (_database.select(_database.salaryCycles)..where((t) => t.deletedAt.isNull())).get(),
      (_database.select(_database.salaryPayments)..where((t) => t.deletedAt.isNull())).get(),
    ]);

    return {
      'rooms': (results[0] as List).map((e) => e.toJson()).toList(),
      'bookings': (results[1] as List).map((e) => e.toJson()).toList(),
      'booking_notes': (results[2] as List).map((e) => e.toJson()).toList(),
      'booking_nights': (results[3] as List).map((e) => e.toJson()).toList(),
      'employees': (results[4] as List).map((e) => e.toJson()).toList(),
      'expenses': (results[5] as List).map((e) => e.toJson()).toList(),
      'cash_transactions': (results[6] as List).map((e) => e.toJson()).toList(),
      'payments': (results[7] as List).map((e) => e.toJson()).toList(),
      'debts': (results[8] as List).map((e) => e.toJson()).toList(),
      'hotel_day_ledger': (results[9] as List).map((e) => e.toJson()).toList(),
      'shift_notes': (results[10] as List).map((e) => e.toJson()).toList(),
      'salary_cycles': (results[11] as List).map((e) => e.toJson()).toList(),
      'salary_payments': (results[12] as List).map((e) => e.toJson()).toList(),
    };
  }

  Future<void> _restoreSnapshot(Map<String, dynamic> snapshot) async {
    debugPrint('LocalJsonTargetAdapter: Restoring snapshot...');
  }

  Future<void> _cleanupOldBackups() async {
    final backups = await listBackups();
    if (backups.length > _maxBackups) {
      final toDelete = backups.sublist(_maxBackups);
      for (final backup in toDelete) {
        try {
          await deleteBackup(backup.id);
        } catch (e) {
          debugPrint('LocalJsonTargetAdapter: Failed to delete old backup: $e');
        }
      }
    }
  }

  Map<String, int>? _extractTableCounts(Map<String, dynamic> data) {
    final counts = <String, int>{};
    for (final key in data.keys) {
      if (key != '_meta' && data[key] is List) {
        counts[key] = (data[key] as List).length;
      }
    }
    return counts.isNotEmpty ? counts : null;
  }

  Future<String?> getCurrentBackupPath() async {
    if (_backupDirectory == null) return null;
    return '$_backupDirectory/$_currentBackupFile';
  }

  Future<int> getBackupSizeBytes() async {
    final path = await getCurrentBackupPath();
    if (path == null) return 0;

    final file = File(path);
    if (!file.existsSync()) return 0;

    return file.statSync().size;
  }
}
