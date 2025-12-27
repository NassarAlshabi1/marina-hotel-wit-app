import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'google_drive_sync_service.dart';

enum SyncPhaseState {
  idle,
  preparing,
  prepared,
  committing,
  committed,
  aborting,
  aborted,
  error,
}

class TwoPhaseCommit {
  TwoPhaseCommit({
    required this.driveService,
    required this.deviceId,
  });

  final GoogleDriveSyncService driveService;
  final String deviceId;

  SyncPhaseState _state = SyncPhaseState.idle;
  Map<String, dynamic>? _preparedData;
  String? _transactionId;

  static const String _lockFileName = 'sync_lock.json';
  static const Duration _lockTimeout = Duration(minutes: 2);

  /// المرحلة 1: التحضير (Prepare)
  /// - التحقق من عدم وجود مزامنة جارية
  /// - إنشاء lock file
  /// - التحقق من الإصدار
  Future<bool> prepare(Map<String, dynamic> dataToSync) async {
    if (_state != SyncPhaseState.idle) {
      debugPrint('❌ Two-Phase Commit: لا يمكن التحضير - الحالة: $_state');
      return false;
    }

    _state = SyncPhaseState.preparing;
    _transactionId = 'txn_${DateTime.now().millisecondsSinceEpoch}_$deviceId';

    try {
      final hasLock = await _acquireLock();
      if (!hasLock) {
        debugPrint('⚠️ فشل الحصول على Lock - جهاز آخر يقوم بالمزامنة');
        _state = SyncPhaseState.aborted;
        return false;
      }

      final remoteSnapshot = await driveService.downloadLatestSnapshot();
      if (remoteSnapshot != null) {
        final expectedVersion = remoteSnapshot.driveVersion;
        dataToSync['_expectedVersion'] = expectedVersion;
      }

      _preparedData = dataToSync;
      _state = SyncPhaseState.prepared;
      
      debugPrint('✅ Phase 1: تم التحضير - Transaction: $_transactionId');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في مرحلة التحضير: $e');
      _state = SyncPhaseState.error;
      await _releaseLock();
      return false;
    }
  }

  /// المرحلة 2: الالتزام (Commit)
  /// - رفع البيانات
  /// - التحقق من النجاح
  /// - تحرير Lock
  Future<bool> commit() async {
    if (_state != SyncPhaseState.prepared) {
      debugPrint('❌ Two-Phase Commit: لا يمكن الالتزام - الحالة: $_state');
      return false;
    }

    if (_preparedData == null) {
      debugPrint('❌ لا توجد بيانات محضرة للالتزام');
      await abort();
      return false;
    }

    _state = SyncPhaseState.committing;

    try {
      final snapshot = _preparedData!['snapshot'];
      final expectedVersion = _preparedData!['_expectedVersion'] as int? ?? 0;

      final uploadResult = await driveService.uploadSnapshot(
        snapshot: snapshot,
        deviceId: deviceId,
        expectedVersion: expectedVersion,
      );

      if (uploadResult.version > expectedVersion) {
        await _updateLocalVersion(uploadResult.version);
        _state = SyncPhaseState.committed;
        
        debugPrint('✅ Phase 2: تم الالتزام - Version: ${uploadResult.version}');
        
        await _releaseLock();
        _reset();
        return true;
      } else {
        debugPrint('⚠️ فشل الالتزام - تعارض في الإصدار');
        await abort();
        return false;
      }
    } catch (e) {
      debugPrint('❌ خطأ في مرحلة الالتزام: $e');
      _state = SyncPhaseState.error;
      await abort();
      return false;
    }
  }

  /// إلغاء المعاملة
  Future<void> abort() async {
    _state = SyncPhaseState.aborting;
    
    await _releaseLock();
    
    _state = SyncPhaseState.aborted;
    _reset();
    
    debugPrint('⚠️ تم إلغاء المعاملة: $_transactionId');
  }

  /// الحصول على Lock من Google Drive
  Future<bool> _acquireLock() async {
    try {
      final lockData = {
        'device_id': deviceId,
        'transaction_id': _transactionId,
        'locked_at': DateTime.now().toUtc().toIso8601String(),
        'expires_at': DateTime.now().add(_lockTimeout).toUtc().toIso8601String(),
      };

      final existingLock = await driveService.downloadFile(_lockFileName);
      
      if (existingLock != null) {
        final lockMap = jsonDecode(existingLock) as Map<String, dynamic>;
        final expiresAt = DateTime.parse(lockMap['expires_at'] as String);
        
        if (DateTime.now().isBefore(expiresAt)) {
          final lockDeviceId = lockMap['device_id'] as String;
          
          if (lockDeviceId == deviceId) {
            debugPrint('🔓 Lock موجود من نفس الجهاز - إعادة استخدام');
            return true;
          }
          
          debugPrint('🔒 Lock نشط من جهاز آخر: $lockDeviceId');
          return false;
        }
        
        debugPrint('🔓 Lock منتهي - سيتم استبداله');
      }

      await driveService.uploadFile(
        fileName: _lockFileName,
        content: jsonEncode(lockData),
      );

      debugPrint('🔒 تم الحصول على Lock بنجاح');
      return true;
    } catch (e) {
      debugPrint('❌ خطأ في الحصول على Lock: $e');
      return false;
    }
  }

  /// تحرير Lock
  Future<void> _releaseLock() async {
    try {
      await driveService.deleteFile(_lockFileName);
      debugPrint('🔓 تم تحرير Lock');
    } catch (e) {
      debugPrint('⚠️ خطأ في تحرير Lock: $e');
    }
  }

  Future<void> _updateLocalVersion(int version) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('sync_last_version', version);
  }

  void _reset() {
    _preparedData = null;
    _transactionId = null;
    _state = SyncPhaseState.idle;
  }

  void dispose() {
    _conflictsController.close();
  }
}
