import 'dart:async';

import 'package:flutter/foundation.dart';

import 'google_drive_backup_service.dart';

class BackupSyncService {
  BackupSyncService(this._driveService);

  final GoogleDriveBackupService _driveService;
  Timer? _debounceTimer;
  bool _isSyncRunning = false;

  Future<void> triggerAutoBackup() async {
    try {
      final enabled = await _driveService.isAutoBackupEnabled();
      if (!enabled) {
        return;
      }
      final signedIn = _driveService.isSignedIn || await _driveService.trySilentSignIn();
      if (!signedIn) {
        return;
      }
      _debounceTimer?.cancel();
      _debounceTimer = Timer(const Duration(seconds: 10), () {
        unawaited(_executeBackup());
      });
    } catch (e, stackTrace) {
      debugPrint('⚠️ triggerAutoBackup failed: $e');
      debugPrint('$stackTrace');
    }
  }

  Future<void> _executeBackup() async {
    if (_isSyncRunning) {
      return;
    }
    _isSyncRunning = true;
    try {
      final signedIn = _driveService.isSignedIn || await _driveService.trySilentSignIn();
      if (!signedIn) {
        return;
      }
      await _driveService.performAutoBackup();
      final latest = await _driveService.getLatestBackupFile();
      if (latest != null) {
        await _driveService.setLastAppliedBackupId(latest.fileId);
      }
    } catch (e, stackTrace) {
      debugPrint('❌ executeBackup failed: $e');
      debugPrint('$stackTrace');
    } finally {
      _isSyncRunning = false;
    }
  }

  Future<void> syncFromDriveIfNeeded() async {
    if (_isSyncRunning) {
      return;
    }
    try {
      final signedIn = _driveService.isSignedIn || await _driveService.trySilentSignIn();
      if (!signedIn) {
        return;
      }
      final latest = await _driveService.getLatestBackupFile();
      if (latest == null) {
        return;
      }
      final lastAppliedId = await _driveService.getLastAppliedBackupId();
      if (lastAppliedId == latest.fileId) {
        return;
      }
      _isSyncRunning = true;
      final backupData = await _driveService.downloadBackup(latest.fileId);
      await _driveService.restoreFromBackup(backupData);
      await _driveService.setLastAppliedBackupId(latest.fileId);
    } catch (e, stackTrace) {
      debugPrint('❌ syncFromDriveIfNeeded failed: $e');
      debugPrint('$stackTrace');
    } finally {
      _isSyncRunning = false;
    }
  }
}
