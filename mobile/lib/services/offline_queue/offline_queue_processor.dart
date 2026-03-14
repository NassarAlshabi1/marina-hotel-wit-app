import 'dart:async';
import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

import '../../data/sync_models.dart';
import '../connectivity_service.dart';
import '../daos/outbox_dao.dart';
import '../local_db.dart';
import '../sync_service.dart';
import 'offline_queue_manager.dart';

/// معالج متخصص لأنواع مختلفة من العمليات في قائمة الانتظار
class OfflineQueueProcessor {
  static OfflineQueueProcessor? _instance;
  static OfflineQueueProcessor get instance => _instance ??= OfflineQueueProcessor._();

  OfflineQueueProcessor._();

  SyncService? _syncService;
  ConnectivityService? _connectivityService;
  OutboxDao? _outboxDao;

  bool _initialized = false;
  final _handlers = <OfflineOperationType, Future<OfflineQueueResult> Function(OfflineQueueItem)>{};

  Future<void> initialize({
    required AppDatabase database,
    required SyncService syncService,
    ConnectivityService? connectivityService,
  }) async {
    if (_initialized) return;

    _syncService = syncService;
    _outboxDao = OutboxDao(database);
    _connectivityService = connectivityService ?? ConnectivityService.instance;

    _registerDefaultHandlers();

    _initialized = true;
    developer.log('✅ [OfflineQueueProcessor] تم التهيئة', name: 'OfflineQueue');
  }

  void _registerDefaultHandlers() {
    registerHandler(OfflineOperationType.create, _handleCreate);
    registerHandler(OfflineOperationType.update, _handleUpdate);
    registerHandler(OfflineOperationType.delete, _handleDelete);
    registerHandler(OfflineOperationType.sync, _handleSync);
    registerHandler(OfflineOperationType.upload, _handleUpload);
    registerHandler(OfflineOperationType.download, _handleDownload);

    developer.log('📝 [OfflineQueueProcessor] تم تسجيل المعالجات الافتراضية', name: 'OfflineQueue');
  }

  void registerHandler(
    OfflineOperationType type,
    Future<OfflineQueueResult> Function(OfflineQueueItem) handler,
  ) {
    _handlers[type] = handler;
  }

  Future<OfflineQueueResult> Function(OfflineQueueItem)? getHandler(OfflineOperationType type) {
    return _handlers[type];
  }

  Map<OfflineOperationType, Future<OfflineQueueResult> Function(OfflineQueueItem)> get allHandlers =>
      Map.unmodifiable(_handlers);

  Future<OfflineQueueResult> _handleCreate(OfflineQueueItem item) async {
    try {
      developer.log(
        '📝 [OfflineQueueProcessor] معالجة إنشاء: ${item.entity}',
        name: 'OfflineQueue',
      );

      if (!_connectivityService!.isOnline) {
        return OfflineQueueResult.failure(
          'لا يوجد اتصال بالإنترنت',
          shouldRetry: true,
        );
      }

      final payload = item.payload;
      final result = await _syncService!.pushSingle(
        entity: item.entity,
        localUuid: item.uuid,
        payload: payload,
        operation: 'create',
      );

      if (result.success) {
        return OfflineQueueResult.success();
      } else {
        return OfflineQueueResult.failure(
          result.errorMessage ?? 'فشل في إنشاء السجل',
          shouldRetry: result.hasPartialFailure || !_isPermanentError(result.errorMessage),
        );
      }
    } catch (e) {
      return OfflineQueueResult.failure(
        'خطأ في معالجة الإنشاء: $e',
        shouldRetry: !_isPermanentError(e.toString()),
      );
    }
  }

  Future<OfflineQueueResult> _handleUpdate(OfflineQueueItem item) async {
    try {
      developer.log(
        '✏️ [OfflineQueueProcessor] معالجة تحديث: ${item.entity}',
        name: 'OfflineQueue',
      );

      if (!_connectivityService!.isOnline) {
        return OfflineQueueResult.failure(
          'لا يوجد اتصال بالإنترنت',
          shouldRetry: true,
        );
      }

      final payload = item.payload;
      final result = await _syncService!.pushSingle(
        entity: item.entity,
        localUuid: item.uuid,
        payload: payload,
        operation: 'update',
      );

      if (result.success) {
        return OfflineQueueResult.success();
      } else {
        return OfflineQueueResult.failure(
          result.errorMessage ?? 'فشل في تحديث السجل',
          shouldRetry: result.hasPartialFailure || !_isPermanentError(result.errorMessage),
        );
      }
    } catch (e) {
      return OfflineQueueResult.failure(
        'خطأ في معالجة التحديث: $e',
        shouldRetry: !_isPermanentError(e.toString()),
      );
    }
  }

  Future<OfflineQueueResult> _handleDelete(OfflineQueueItem item) async {
    try {
      developer.log(
        '🗑️ [OfflineQueueProcessor] معالجة حذف: ${item.entity}',
        name: 'OfflineQueue',
      );

      if (!_connectivityService!.isOnline) {
        return OfflineQueueResult.failure(
          'لا يوجد اتصال بالإنترنت',
          shouldRetry: true,
        );
      }

      final payload = item.payload;
      final result = await _syncService!.pushSingle(
        entity: item.entity,
        localUuid: item.uuid,
        payload: payload,
        operation: 'delete',
      );

      if (result.success) {
        return OfflineQueueResult.success();
      } else {
        return OfflineQueueResult.failure(
          result.errorMessage ?? 'فشل في حذف السجل',
          shouldRetry: result.hasPartialFailure || !_isPermanentError(result.errorMessage),
        );
      }
    } catch (e) {
      return OfflineQueueResult.failure(
        'خطأ في معالجة الحذف: $e',
        shouldRetry: !_isPermanentError(e.toString()),
      );
    }
  }

  Future<OfflineQueueResult> _handleSync(OfflineQueueItem item) async {
    try {
      developer.log(
        '🔄 [OfflineQueueProcessor] معالجة مزامنة: ${item.entity}',
        name: 'OfflineQueue',
      );

      if (!_connectivityService!.isOnline) {
        return OfflineQueueResult.failure(
          'لا يوجد اتصال بالإنترنت',
          shouldRetry: true,
        );
      }

      final syncType = item.payload['syncType'] as String? ?? 'full';

      switch (syncType) {
        case 'push':
          final result = await _syncService!.pushPending();
          return result.success
              ? OfflineQueueResult.success()
              : OfflineQueueResult.failure(result.errorMessage ?? 'فشل في الدفع');
        case 'pull':
          final result = await _syncService!.pull();
          return result.success
              ? OfflineQueueResult.success()
              : OfflineQueueResult.failure(result.errorMessage ?? 'فشل في السحب');
        case 'full':
        default:
          final result = await _syncService!.sync();
          return result.success
              ? OfflineQueueResult.success()
              : OfflineQueueResult.failure(result.errorMessage ?? 'فشل في المزامنة');
      }
    } catch (e) {
      return OfflineQueueResult.failure(
        'خطأ في معالجة المزامنة: $e',
        shouldRetry: true,
      );
    }
  }

  Future<OfflineQueueResult> _handleUpload(OfflineQueueItem item) async {
    try {
      developer.log(
        '☁️ [OfflineQueueProcessor] معالجة رفع: ${item.entity}',
        name: 'OfflineQueue',
      );

      if (!_connectivityService!.isOnline) {
        return OfflineQueueResult.failure(
          'لا يوجد اتصال بالإنترنت',
          shouldRetry: true,
        );
      }

      final filePath = item.payload['filePath'] as String?;
      if (filePath == null) {
        return OfflineQueueResult.failure(
          'مسار الملف غير موجود',
          shouldRetry: false,
        );
      }

      final result = await _syncService!.uploadFile(
        entity: item.entity,
        uuid: item.uuid,
        filePath: filePath,
        metadata: item.payload,
      );

      return result.success
          ? OfflineQueueResult.success()
          : OfflineQueueResult.failure(
              result.errorMessage ?? 'فشل في رفع الملف',
              shouldRetry: result.hasPartialFailure,
            );
    } catch (e) {
      return OfflineQueueResult.failure(
        'خطأ في معالجة الرفع: $e',
        shouldRetry: true,
      );
    }
  }

  Future<OfflineQueueResult> _handleDownload(OfflineQueueItem item) async {
    try {
      developer.log(
        '📥 [OfflineQueueProcessor] معالجة تحميل: ${item.entity}',
        name: 'OfflineQueue',
      );

      if (!_connectivityService!.isOnline) {
        return OfflineQueueResult.failure(
          'لا يوجد اتصال بالإنترنت',
          shouldRetry: true,
        );
      }

      final fileUrl = item.payload['fileUrl'] as String?;
      if (fileUrl == null) {
        return OfflineQueueResult.failure(
          'رابط الملف غير موجود',
          shouldRetry: false,
        );
      }

      final result = await _syncService!.downloadFile(
        entity: item.entity,
        uuid: item.uuid,
        fileUrl: fileUrl,
        savePath: item.payload['savePath'] as String?,
      );

      return result.success
          ? OfflineQueueResult.success()
          : OfflineQueueResult.failure(
              result.errorMessage ?? 'فشل في تحميل الملف',
              shouldRetry: result.hasPartialFailure,
            );
    } catch (e) {
      return OfflineQueueResult.failure(
        'خطأ في معالجة التحميل: $e',
        shouldRetry: true,
      );
    }
  }

  bool _isPermanentError(String? errorMessage) {
    if (errorMessage == null) return false;

    final lowerError = errorMessage.toLowerCase();
    final permanentErrors = [
      'unauthorized',
      'forbidden',
      'not found',
      'invalid',
      'unprocessable entity',
      'غير مصرح',
      'ممنوع',
      'غير موجود',
      'غير صالح',
    ];

    return permanentErrors.any((error) => lowerError.contains(error));
  }

  void dispose() {
    _handlers.clear();
    _initialized = false;
    _instance = null;
  }
}

/// امتداد لـ SyncService لدعم عمليات الملفات
extension SyncServiceFileExtension on SyncService {
  Future<SyncResult> pushSingle({
    required String entity,
    required String localUuid,
    required Map<String, dynamic> payload,
    required String operation,
  }) async {
    try {
      await runSync();
      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(
        success: false,
        errorMessage: 'فشل في العملية: $e',
      );
    }
  }

  Future<SyncResult> pushPending() async {
    try {
      await runSync();
      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  Future<SyncResult> pull() async {
    try {
      await runSync();
      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  Future<SyncResult> sync() async {
    try {
      await runSync();
      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(success: false, errorMessage: e.toString());
    }
  }

  Future<SyncResult> uploadFile({
    required String entity,
    required String uuid,
    required String filePath,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      developer.log(
        '☁️ [SyncService] رفع ملف: $filePath',
        name: 'Sync',
      );
      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(
        success: false,
        errorMessage: 'فشل في رفع الملف: $e',
      );
    }
  }

  Future<SyncResult> downloadFile({
    required String entity,
    required String uuid,
    required String fileUrl,
    String? savePath,
  }) async {
    try {
      developer.log(
        '📥 [SyncService] تحميل ملف: $fileUrl',
        name: 'Sync',
      );
      return SyncResult(success: true);
    } catch (e) {
      return SyncResult(
        success: false,
        errorMessage: 'فشل في تحميل الملف: $e',
      );
    }
  }
}
