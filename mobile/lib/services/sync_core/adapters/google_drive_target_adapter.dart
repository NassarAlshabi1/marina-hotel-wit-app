import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../google_drive_backup_service.dart';
import '../../google_drive_logger.dart';
import '../../logging/log_models.dart';
import '../../google_drive_unified_sync_coordinator.dart';
import '../../local_db.dart';
import '../events/sync_event.dart';
import 'sync_target_adapter.dart';

class GoogleDriveTargetAdapter extends BackupCapableAdapter {
  final AppDatabase _database;
  GoogleDriveBackupService? _backupService;
  GoogleDriveUnifiedSyncCoordinator? _coordinator;
  GoogleDriveLogger? _logger;
  bool _initialized = false;
  bool _enabled = false;
  bool _isSignedIn = false;
  DateTime? _lastSyncAt;
  String? _lastError;

  GoogleDriveTargetAdapter({
    required AppDatabase database,
    GoogleDriveBackupService? backupService,
    GoogleDriveUnifiedSyncCoordinator? coordinator,
  })  : _database = database,
        _backupService = backupService,
        _coordinator = coordinator;

  @override
  SyncTargetType get type => SyncTargetType.googleDrive;

  @override
  String get name => 'google_drive';

  @override
  String get displayName => 'Google Drive';

  @override
  bool get isAvailable => _backupService != null && _isSignedIn;

  @override
  bool get isEnabled => _enabled;

  @override
  bool get isInitialized => _initialized;

  bool get isSignedIn => _isSignedIn;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      _backupService ??= GoogleDriveBackupService();

      _logger = GoogleDriveLogger();
      await _logger!.initialize(
        minLevel: LogLevel.info,
        enableConsole: true,
        enableFile: false,
      );

      final account = await _backupService!.attemptSilentSignIn();
      _isSignedIn = account != null;

      if (_isSignedIn) {
        _coordinator ??= GoogleDriveUnifiedSyncCoordinator.instance;
        if (!_coordinator!.isInitialized) {
          await _coordinator!.initialize(
            backupService: _backupService!,
            database: _database,
            logger: _logger!,
          );
        }
      }

      final prefs = await SharedPreferences.getInstance();
      _enabled = prefs.getBool('google_drive_sync_enabled') ?? false;

      _initialized = true;
      debugPrint('GoogleDriveTargetAdapter: Initialized (signedIn: $_isSignedIn)');
    } catch (e) {
      _lastError = e.toString();
      debugPrint('GoogleDriveTargetAdapter: Initialization failed: $e');
      rethrow;
    }
  }

  @override
  Future<bool> checkConnection() async {
    if (_backupService == null) return false;
    try {
      _isSignedIn = _backupService!.isSignedIn;
      return _isSignedIn;
    } catch (e) {
      _lastError = e.toString();
      return false;
    }
  }

  @override
  Future<SyncTargetStatus> getStatus() async {
    final isConnected = await checkConnection();

    return SyncTargetStatus(
      type: type,
      isAvailable: _backupService != null,
      isEnabled: _enabled,
      isConnected: isConnected,
      lastSyncAt: _lastSyncAt,
      lastError: _lastError,
      pendingCount: 0,
      metadata: {
        'isSignedIn': _isSignedIn,
      },
    );
  }

  @override
  Future<SyncPushResult> push(List<EnhancedSyncEvent> events) async {
    if (!_initialized || !_enabled || !_isSignedIn) {
      return SyncPushResult.failure(
        error: 'Adapter not ready (initialized: $_initialized, enabled: $_enabled, signedIn: $_isSignedIn)',
        failedIds: events.map((e) => e.id).toList(),
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      if (_coordinator != null) {
        for (final event in events) {
          _coordinator!.notifyLocalChange(
            table: event.table,
            operation: event.operation.name,
            count: 1,
          );
        }

        final result = await _coordinator!.performSync(
          trigger: SyncTrigger.localChange,
          mode: SyncMode.smart,
        );

        stopwatch.stop();

        if (result.success) {
          _lastSyncAt = DateTime.now();
          return SyncPushResult.success(
            affectedCount: events.length,
            duration: stopwatch.elapsed,
            syncedIds: events.map((e) => e.id).toList(),
          );
        } else {
          _lastError = result.error;
          return SyncPushResult.failure(
            error: result.error ?? 'Sync failed',
            duration: stopwatch.elapsed,
            failedIds: events.map((e) => e.id).toList(),
          );
        }
      }

      return SyncPushResult.failure(
        error: 'Coordinator not available',
        duration: stopwatch.elapsed,
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
    if (!_initialized || !_enabled || !_isSignedIn) {
      return SyncPullResult.failure(
        error: 'Adapter not ready',
      );
    }

    final stopwatch = Stopwatch()..start();

    try {
      if (_coordinator != null) {
        final result = await _coordinator!.performSync(
          trigger: SyncTrigger.periodic,
          mode: SyncMode.deltaOnly,
        );

        stopwatch.stop();

        if (result.success) {
          _lastSyncAt = DateTime.now();
          return SyncPullResult.success(
            created: result.pulledChanges ?? 0,
            duration: stopwatch.elapsed,
            lastSyncTimestamp: _lastSyncAt,
          );
        } else {
          _lastError = result.error;
          return SyncPullResult.failure(
            error: result.error ?? 'Pull failed',
            duration: stopwatch.elapsed,
          );
        }
      }

      return SyncPullResult.failure(
        error: 'Coordinator not available',
        duration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      _lastError = e.toString();
      return SyncPullResult.failure(
        error: e.toString(),
        duration: stopwatch.elapsed,
      );
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('google_drive_sync_enabled', enabled);
  }

  @override
  Future<void> reset() async {
    _lastSyncAt = null;
    _lastError = null;
  }

  @override
  Future<void> dispose() async {
    _initialized = false;
    _isSignedIn = false;
  }

  @override
  Future<String> createBackup({String? tag}) async {
    if (_backupService == null || !_isSignedIn) {
      throw StateError('Cannot create backup: not signed in');
    }

    final backupData = await _backupService!.exportDatabaseToJson();
    final fileId = await _backupService!.uploadBackup(backupData);

    return fileId;
  }

  @override
  Future<void> restoreFromBackup(String backupId) async {
    if (_backupService == null || !_isSignedIn) {
      throw StateError('Cannot restore: not signed in');
    }

    final data = await _backupService!.downloadBackup(backupId);
    await _backupService!.restoreFromBackup(data);
  }

  @override
  Future<List<BackupInfo>> listBackups({int? limit}) async {
    if (_backupService == null || !_isSignedIn) {
      return [];
    }

    final files = await _backupService!.listBackupFiles(limit: limit ?? 20);

    return files.map((file) {
      final tag = file.metadata?['backup_type']?.toString();
      return BackupInfo(
        id: file.fileId,
        createdAt: file.createdTime,
        sizeBytes: file.size ?? 0,
        tag: tag,
      );
    }).toList();
  }

  @override
  Future<void> deleteBackup(String backupId) async {
    if (_backupService == null || !_isSignedIn) {
      throw StateError('Cannot delete backup: not signed in');
    }

    await _backupService!.deleteBackup(backupId);
  }

  Future<void> signIn() async {
    if (_backupService == null) return;
    final account = await _backupService!.signInForDrive();
    _isSignedIn = account != null;

    if (_isSignedIn && _coordinator != null) {
      await _coordinator!.onSignInChanged(true);
    }
  }

  Future<void> signOut() async {
    if (_backupService == null) return;
    await _backupService!.signOut();
    _isSignedIn = false;

    if (_coordinator != null) {
      await _coordinator!.onSignInChanged(false);
    }
  }
}
