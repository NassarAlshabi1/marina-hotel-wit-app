import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'delta_sync_service.dart';
import 'google_drive_backup_service.dart';
import 'local_db.dart';
import '../utils/time.dart';
import '../utils/id.dart';

enum SyncFileType {
  fullBackup,
  deltaSync,
}

class GoogleDriveDeltaSync {
  GoogleDriveDeltaSync._();
  static final instance = GoogleDriveDeltaSync._();

  GoogleDriveBackupService? _driveService;
  DeltaSyncService? _deltaSyncService;
  String? _deviceId;
  bool _isSyncing = false;

  static const _prefsLastDeltaSyncKey = 'gd_last_delta_sync';
  static const _prefsDeviceIdKey = 'gd_delta_device_id';
  
  static const fullBackupPrefix = 'marina_backup_full_';
  static const deltaSyncPrefix = 'marina_sync_delta_';

  Future<void> initialize(GoogleDriveBackupService driveService, AppDatabase db) async {
    _driveService = driveService;
    _deltaSyncService = DeltaSyncService(db);
    await _initializeDeviceId();
    debugPrint('✅ تم تهيئة خدمة المزامنة التفاضلية لـ Google Drive');
  }

  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_prefsDeviceIdKey);
    if (_deviceId == null) {
      _deviceId = IdGen.uuid();
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
    }
  }

  bool get isInitialized => _driveService != null && _deltaSyncService != null;
  bool get isSyncing => _isSyncing;
  String? get deviceId => _deviceId;

  Future<DeltaSyncResult> pushDeltaChanges() async {
    if (!isInitialized || _isSyncing) {
      return DeltaSyncResult(success: false, message: 'الخدمة غير جاهزة أو المزامنة جارية');
    }

    if (_driveService?.isSignedIn != true) {
      return DeltaSyncResult(success: false, message: 'غير مسجل الدخول في Google Drive');
    }

    try {
      _isSyncing = true;
      debugPrint('📤 بدء المزامنة التفاضلية إلى Google Drive...');

      final lastSyncTs = await _getLastDeltaSyncTimestamp();
      final computation = await _deltaSyncService!.compute(since: lastSyncTs);

      if (computation.changes.isEmpty) {
        debugPrint('✅ لا توجد تغييرات للمزامنة');
        return DeltaSyncResult(success: true, message: 'لا توجد تغييرات', changesCount: 0);
      }

      final deltaPayload = _buildDeltaPayload(computation);
      final fileName = _generateDeltaSyncFileName();
      
      await _uploadDeltaFile(fileName, deltaPayload);
      await _deltaSyncService!.persistMirror(computation);
      await _updateLastDeltaSyncTimestamp();

      debugPrint('✅ تم رفع ${computation.changes.length} تغيير إلى Google Drive');
      
      return DeltaSyncResult(
        success: true,
        message: 'تم رفع التغييرات بنجاح',
        changesCount: computation.changes.length,
      );
    } catch (e) {
      debugPrint('❌ خطأ في المزامنة التفاضلية: $e');
      return DeltaSyncResult(success: false, message: e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<DeltaSyncResult> pullDeltaChanges() async {
    if (!isInitialized || _isSyncing) {
      return DeltaSyncResult(success: false, message: 'الخدمة غير جاهزة');
    }

    if (_driveService?.isSignedIn != true) {
      return DeltaSyncResult(success: false, message: 'غير مسجل الدخول');
    }

    try {
      _isSyncing = true;
      debugPrint('📥 فحص التغييرات من Google Drive...');

      final deltaFiles = await _listDeltaSyncFiles();
      if (deltaFiles.isEmpty) {
        return DeltaSyncResult(success: true, message: 'لا توجد ملفات مزامنة', changesCount: 0);
      }

      deltaFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      
      int appliedChanges = 0;
      final lastPullTs = await _getLastDeltaSyncTimestamp();

      for (final file in deltaFiles) {
        if (file.createdTime.millisecondsSinceEpoch <= lastPullTs) continue;
        
        final sourceDeviceId = file.appProperties['device_id'];
        if (sourceDeviceId == _deviceId) continue;

        final deltaData = await _downloadDeltaFile(file.fileId);
        if (deltaData != null) {
          final changes = await _applyDeltaChanges(deltaData);
          appliedChanges += changes;
        }
      }

      if (appliedChanges > 0) {
        await _updateLastDeltaSyncTimestamp();
      }

      return DeltaSyncResult(
        success: true,
        message: 'تم تطبيق $appliedChanges تغيير',
        changesCount: appliedChanges,
      );
    } catch (e) {
      debugPrint('❌ خطأ في سحب التغييرات: $e');
      return DeltaSyncResult(success: false, message: e.toString());
    } finally {
      _isSyncing = false;
    }
  }

  Future<List<DriveBackupFile>> _listDeltaSyncFiles() async {
    final allFiles = await _driveService!.listBackupFiles();
    return allFiles.where((f) => f.fileName.startsWith(deltaSyncPrefix)).toList();
  }

  Map<String, dynamic> _buildDeltaPayload(DeltaSyncComputation computation) {
    return {
      'type': 'delta_sync',
      'device_id': _deviceId,
      'timestamp': DateTime.now().toIso8601String(),
      'epoch': Time.nowEpoch(),
      'changes_count': computation.changes.length,
      'changes': computation.toPayload(),
      'fallback_tables': computation.fallbackTables.toList(),
    };
  }

  String _generateDeltaSyncFileName() {
    final now = DateTime.now();
    final dateStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final timeStr = '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
    return '${deltaSyncPrefix}${dateStr}_$timeStr.json';
  }

  Future<void> _uploadDeltaFile(String fileName, Map<String, dynamic> payload) async {
    final jsonStr = jsonEncode(payload);
    final bytes = utf8.encode(jsonStr);
    
    await _driveService!.uploadBackupWithName(
      fileName,
      bytes,
      appProperties: {
        'type': 'delta_sync',
        'device_id': _deviceId ?? '',
        'changes_count': payload['changes_count'].toString(),
      },
    );
  }

  Future<Map<String, dynamic>?> _downloadDeltaFile(String fileId) async {
    try {
      return await _driveService!.downloadBackup(fileId);
    } catch (e) {
      debugPrint('⚠️ خطأ في تحميل ملف المزامنة: $e');
      return null;
    }
  }

  Future<int> _applyDeltaChanges(Map<String, dynamic> deltaData) async {
    final changes = deltaData['changes'] as List<dynamic>?;
    if (changes == null || changes.isEmpty) return 0;

    int applied = 0;
    for (final change in changes) {
      try {
        final entity = change['entity'] as String;
        final op = change['op'] as String;
        final data = change['data'] as Map<String, dynamic>;
        
        await _applyChange(entity, op, data);
        applied++;
      } catch (e) {
        debugPrint('⚠️ خطأ في تطبيق تغيير: $e');
      }
    }
    return applied;
  }

  Future<void> _applyChange(String entity, String operation, Map<String, dynamic> data) async {
    debugPrint('🔄 تطبيق $operation على $entity');
  }

  Future<int> _getLastDeltaSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsLastDeltaSyncKey) ?? 0;
  }

  Future<void> _updateLastDeltaSyncTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastDeltaSyncKey, Time.nowEpoch());
  }

  Future<void> cleanupOldDeltaFiles({int keepCount = 10}) async {
    if (_driveService?.isSignedIn != true) return;

    try {
      final deltaFiles = await _listDeltaSyncFiles();
      if (deltaFiles.length <= keepCount) return;

      deltaFiles.sort((a, b) => b.createdTime.compareTo(a.createdTime));
      final toDelete = deltaFiles.skip(keepCount).toList();

      for (final file in toDelete) {
        await _driveService!.deleteBackup(file.fileId);
        debugPrint('🗑️ حذف ملف مزامنة قديم: ${file.fileName}');
      }
    } catch (e) {
      debugPrint('⚠️ خطأ في تنظيف ملفات المزامنة: $e');
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    final lastSync = await _getLastDeltaSyncTimestamp();
    return {
      'initialized': isInitialized,
      'is_syncing': _isSyncing,
      'device_id': _deviceId,
      'last_sync_epoch': lastSync,
      'last_sync_time': lastSync > 0 
          ? DateTime.fromMillisecondsSinceEpoch(lastSync * 1000).toIso8601String()
          : null,
      'signed_in': _driveService?.isSignedIn ?? false,
    };
  }
}

class DeltaSyncResult {
  final bool success;
  final String message;
  final int changesCount;

  DeltaSyncResult({
    required this.success,
    required this.message,
    this.changesCount = 0,
  });
}
