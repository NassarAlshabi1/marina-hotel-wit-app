// lib/services/appwrite_delta_sync.dart

import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'delta_sync_service.dart';
import 'appwrite_service.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'local_db.dart';
import 'daos/outbox_dao.dart';
import '../utils/time.dart';
import '../utils/id.dart';
import 'sync_locks.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'repositories/base_repository.dart';
import 'repositories/rooms_repository.dart';

/// ⭐ نموذج خطأ المزامنة للتتبع
class SyncErrorRecord {
  SyncErrorRecord({
    required this.id,
    required this.entity,
    required this.localUuid,
    required this.operation,
    required this.errorMessage,
    required this.timestamp,
    this.retryCount = 0,
    this.lastRetryAt,
    this.payload,
  });

  final int id;
  final String entity;
  final String localUuid;
  final String operation;
  final String errorMessage;
  final DateTime timestamp;
  final int retryCount;
  final DateTime? lastRetryAt;
  final Map<String, dynamic>? payload;

  /// ⭐ إنشاء نسخة مع زيادة عداد المحاولات
  SyncErrorRecord withRetry() {
    return SyncErrorRecord(
      id: id,
      entity: entity,
      localUuid: localUuid,
      operation: operation,
      errorMessage: errorMessage,
      timestamp: timestamp,
      retryCount: retryCount + 1,
      lastRetryAt: DateTime.now(),
      payload: payload,
    );
  }

  factory SyncErrorRecord.fromMap(Map<String, dynamic> map) {
    return SyncErrorRecord(
      id: map['id'] as int,
      entity: map['entity'] as String,
      localUuid: map['local_uuid'] as String,
      operation: map['operation'] as String,
      errorMessage: map['error_message'] as String,
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      retryCount: map['retry_count'] as int? ?? 0,
      lastRetryAt: map['last_retry_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(map['last_retry_at'] as int)
          : null,
      payload: map['payload'] != null
          ? Map<String, dynamic>.from(map['payload'] as Map)
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entity': entity,
      'local_uuid': localUuid,
      'operation': operation,
      'error_message': errorMessage,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'retry_count': retryCount,
      'last_retry_at': lastRetryAt?.millisecondsSinceEpoch,
      'payload': payload,
    };
  }
}

/// ⭐ نتيجة عملية المزامنة
class AppwriteDeltaSyncResult {
  AppwriteDeltaSyncResult({
    required this.success,
    required this.message,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.conflictCount = 0,
    this.failedCount = 0,
    this.pushedUuids = const [],
    this.failedRecords = const [],
  });
  
  final bool success;
  final String message;
  final int pushedCount;
  final int pulledCount;
  final int conflictCount;
  final int failedCount;
  
  /// ⭐ قائمة الـ UUIDs التي نجح رفعها
  final List<String> pushedUuids;
  
  /// ⭐ قائمة السجلات التي فشلت مع تفاصيل الخطأ
  final List<SyncErrorRecord> failedRecords;

  int get recordsPulled => pulledCount;
  int get recordsPushed => pushedCount;
  bool get hasConflicts => conflictCount > 0;
  bool get hasFailures => failedCount > 0;
}

/// ⭐ Provider لأخطاء المزامنة
final syncErrorsProvider = StateProvider<List<SyncErrorRecord>>((ref) => []);

class AppwriteDeltaSync {
  AppwriteDeltaSync._();
  static final instance = AppwriteDeltaSync._();

  AppwriteService? _appwriteService;
  DeltaSyncService? _deltaSyncService;
  AppDatabase? _database;
  AdapterRegistry? _adapterRegistry;
  String? _deviceId;
  bool _isSyncing = false;
  
  /// ⭐ قائمة الأخطاء المحفوظة
  final List<SyncErrorRecord> _syncErrors = [];
  
  /// ⭐ Stream لأخطاء المزامنة
  final _errorsController = StreamController<SyncErrorRecord>.broadcast();
  Stream<SyncErrorRecord> get errorsStream => _errorsController.stream;
  
  /// ⭐ الحد الأقصى لعدد إعادة المحاولات
  static const int maxRetryAttempts = 3;
  
  /// ⭐ التأخير بين إعادة المحاولات (بالثواني)
  static const int retryDelaySeconds = 5;

  final _logger = AppwriteLogger();

  static const _prefsLastDeltaPushKey = 'appwrite_last_delta_push';
  static const _prefsLastDeltaPullKey = 'appwrite_last_delta_pull';
  static const _prefsDeviceIdKey = 'appwrite_delta_device_id';
  static const _prefsDeltaSyncEnabledKey = 'appwrite_delta_sync_enabled';

  Future<void> initialize(
      AppwriteService appwriteService, AppDatabase db) async {
    _appwriteService = appwriteService;
    _database = db;
    _deltaSyncService = DeltaSyncService(db);
    _adapterRegistry = AdapterRegistry(db);
    await _initializeDeviceId();
    await _loadSyncErrors();
    _logger.info('تم تهيئة خدمة المزامنة التفاضلية لـ Appwrite',
        tag: 'DELTA_SYNC');
  }

  Future<void> _initializeDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString(_prefsDeviceIdKey);
    if (_deviceId == null) {
      _deviceId = IdGen.uuid();
      await prefs.setString(_prefsDeviceIdKey, _deviceId!);
    }
  }

  bool get isInitialized =>
      _appwriteService != null && _deltaSyncService != null;
  bool get isSyncing => _isSyncing;
  String? get deviceId => _deviceId;
  
  /// ⭐ الحصول على قائمة الأخطاء
  List<SyncErrorRecord> get syncErrors => List.unmodifiable(_syncErrors);

  // ==================== PUSH ====================

  Future<AppwriteDeltaSyncResult> pushDeltaChanges({
    bool retryFailed = false,
  }) async {
    final canStart = await SyncLocks.appwriteSyncLock.synchronized(() async {
      if (!isInitialized || _isSyncing) return false;
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      return AppwriteDeltaSyncResult(
          success: false, message: 'الخدمة غير جاهزة أو المزامنة جارية');
    }

    try {
      _logger.info('📤 بدء المزامنة التفاضلية المحسنة إلى Appwrite...',
          tag: 'DELTA_SYNC');
      
      final lastPushTs = await _getLastDeltaPushTimestamp();
      final computation = await _deltaSyncService!.compute(since: lastPushTs);

      if (computation.changes.isEmpty && !retryFailed) {
        _logger.info('✅ لا توجد تغييرات للمزامنة', tag: 'DELTA_SYNC');
        return AppwriteDeltaSyncResult(
            success: true, message: 'لا توجد تغييرات', pushedCount: 0);
      }

      final allChanges = <DeltaSyncChange>[...computation.changes];
      
      // ⭐ إضافة السجلات الفاشلة السابقة للإعادة
      if (retryFailed && _syncErrors.isNotEmpty) {
        _logger.info('🔄 إعادة محاولة ${_syncErrors.length} سجل فاشل', tag: 'DELTA_SYNC');
        for (final error in _syncErrors.where((e) => e.retryCount < maxRetryAttempts)) {
          if (error.payload != null) {
            allChanges.add(DeltaSyncChange(
              entity: error.entity,
              operation: error.operation,
              data: error.payload!,
              rowHash: '',
              localUuid: error.localUuid,
              clientTimestamp: Time.nowEpoch(),
            ));
          }
        }
      }

      if (allChanges.isEmpty) {
        return AppwriteDeltaSyncResult(
          success: true,
          message: 'لا توجد تغييرات جديدة',
          pushedCount: 0,
        );
      }

      final successfulChanges = <DeltaSyncChange>[];
      final failedChanges = <Map<String, dynamic>>[];
      final newErrors = <SyncErrorRecord>[];

      // ⭐ تحسين: batch مع retry لكل عنصر (زيادة الحجم لتحسين الأداء)
      const int batchSize = 20;
      for (int i = 0; i < allChanges.length; i += batchSize) {
        final batch = allChanges.skip(i).take(batchSize).toList();

        final results = await Future.wait(
          batch.map((change) => _pushSingleChangeWithRetry(change)),
        );

        for (final result in results) {
          if (result['success'] == true) {
            successfulChanges.add(result['change'] as DeltaSyncChange);
          } else {
            failedChanges.add(result);
            
            // ⭐ تسجيل الخطأ
            final error = SyncErrorRecord(
              id: DateTime.now().millisecondsSinceEpoch,
              entity: (result['change'] as DeltaSyncChange).entity,
              localUuid: (result['change'] as DeltaSyncChange).localUuid,
              operation: (result['change'] as DeltaSyncChange).operation,
              errorMessage: result['error']?.toString() ?? 'Unknown error',
              timestamp: DateTime.now(),
              retryCount: (result['retryCount'] as int?) ?? 0,
              payload: (result['change'] as DeltaSyncChange).data,
            );
            newErrors.add(error);
            
            // إرسال للـ stream
            _errorsController.add(error);
          }
        }
      }

      // ⭐ تحديث Mirror فقط للسجلات الناجحة
      if (successfulChanges.isNotEmpty) {
        await _updateMirrorForSuccessfulChanges(
          computation, 
          successfulChanges,
        );
        
        // ⭐ تنظيف Outbox فقط للسجلات الناجحة
        await _cleanupOutboxForSuccessful(successfulChanges);
        
        await _updateLastDeltaPushTimestamp();
      }

      // ⭐ تحديث قائمة الأخطاء
      _updateSyncErrors(newErrors);
      await _saveSyncErrors();

      final successfulUuids = successfulChanges.map((c) => c.localUuid).toList();
      final hasFailures = failedChanges.isNotEmpty;
      
      String message;
      if (hasFailures && successfulChanges.isNotEmpty) {
        message = 'تم رفع ${successfulChanges.length} تغيير وفشل ${failedChanges.length}';
      } else if (hasFailures) {
        message = 'فشل رفع جميع التغييرات (${failedChanges.length})';
      } else {
        message = 'تم رفع ${successfulChanges.length} تغيير بنجاح';
      }

      _logger.info('✅ $message', tag: 'DELTA_SYNC');
      
      return AppwriteDeltaSyncResult(
        success: !hasFailures,
        message: message,
        pushedCount: successfulChanges.length,
        failedCount: failedChanges.length,
        pushedUuids: successfulUuids,
        failedRecords: newErrors,
      );
    } catch (e) {
      _logger.error('❌ خطأ في المزامنة التفاضلية: $e', tag: 'DELTA_SYNC');
      return AppwriteDeltaSyncResult(
        success: false,
        message: e.toString(),
        failedRecords: [],
      );
    } finally {
      await SyncLocks.appwriteSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  /// ⭐ رفع تغيير واحد مع retry
  Future<Map<String, dynamic>> _pushSingleChangeWithRetry(
    DeltaSyncChange change, {
    int maxRetries = 3,
  }) async {
    int attempts = 0;
    Exception? lastError;

    while (attempts < maxRetries) {
      try {
        await _pushSingleChange(change);
        return {
          'success': true,
          'change': change,
          'attempts': attempts + 1,
        };
      } on AppwriteException catch (e) {
        lastError = e;
        attempts++;
        
        // ⭐ لا تعيد المحاولة للأخطاء الدائمة
        if (_isPermanentError(e.code)) {
          _logger.warning(
            'خطأ دائم (${e.code}) لـ ${change.entity}/${change.localUuid}: ${e.message}',
            tag: 'DELTA_SYNC',
          );
          break;
        }
        
        if (attempts < maxRetries) {
          _logger.warning(
            'إعادة المحاولة ($attempts/$maxRetries) لـ ${change.entity}/${change.localUuid}',
            tag: 'DELTA_SYNC',
          );
          await Future.delayed(Duration(seconds: retryDelaySeconds * attempts));
        }
      } catch (e) {
        lastError = e is Exception ? e : Exception(e.toString());
        attempts++;
        
        if (attempts < maxRetries) {
          await Future.delayed(Duration(seconds: retryDelaySeconds * attempts));
        }
      }
    }

    return {
      'success': false,
      'change': change,
      'error': lastError?.toString() ?? 'Unknown error',
      'retryCount': attempts,
    };
  }

  /// ⭐ التحقق من أن الخطأ دائم (لا فائدة من إعادة المحاولة)
  bool _isPermanentError(int? code) {
    return code == 400 ||  // Bad Request
           code == 401 ||  // Unauthorized
           code == 403 ||  // Forbidden
           code == 404;    // Not Found (already deleted)
  }

  Future<void> _pushSingleChange(DeltaSyncChange change) async {
    final collectionId = _getCollectionId(change.entity);
    if (collectionId == null) {
      throw Exception('لا يوجد collectionId لـ ${change.entity}');
    }

    final payload = Map<String, dynamic>.from(change.data);

    // ⭐ إضافة الحقول المطلوبة لـ Appwrite (camelCase)
    payload['deviceId'] = _deviceId;
    payload['syncTimestamp'] = Time.nowEpoch();

    // ⭐ التأكد من وجود localUuid (مطلوب في معظم collections)
    if (!payload.containsKey('localUuid') && !payload.containsKey('local_uuid')) {
      payload['localUuid'] = change.localUuid;
    }

    // ⭐ تحويل البيانات (يتولى إضافة الحقول المطلوبة وتحويل snake_case إلى camelCase)
    final sanitizedData = _sanitizePayload(payload, collectionEntity: change.entity);

    // ⭐ تشخيص: طباعة البيانات قبل الإرسال (للتطوير فقط)
    if (kDebugMode) {
      debugPrint('📤 Pushing ${change.entity}/${change.localUuid}');
      debugPrint('   Operation: ${change.operation}');
      debugPrint('   Has localUuid: ${sanitizedData.containsKey('localUuid')}');
      debugPrint('   Has createdAt: ${sanitizedData.containsKey('createdAt')}');
      debugPrint('   Has id: ${sanitizedData.containsKey('id')}');
    }

    switch (change.operation) {
      case 'insert':
      case 'update':
        await _appwriteService!.upsertDocument(
          collectionId: collectionId,
          documentId: change.localUuid,
          data: sanitizedData,
        );
      case 'delete':
        try {
          await _appwriteService!.deleteDocument(
              collectionId: collectionId, documentId: change.localUuid);
        } on AppwriteException catch (e) {
          if (e.code != 404) rethrow;
        }
      default:
        throw Exception('عملية غير معروفة: ${change.operation}');
    }
  }

  /// ⭐ تحديث Mirror للسجلات الناجحة فقط
  Future<void> _updateMirrorForSuccessfulChanges(
    DeltaSyncComputation computation,
    List<DeltaSyncChange> successfulChanges,
  ) async {
    try {
      final successfulUuids = successfulChanges.map((c) => c.localUuid).toSet();
      final filteredSnapshot = <String, Map<String, MirrorRow>>{};

      // نسخ المرآة الحالية
      for (final entry in computation.mirrorSnapshot.entries) {
        final filteredRows = <String, MirrorRow>{};
        
        for (final rowEntry in entry.value.entries) {
          // تضمين إذا كان:
          // 1. من التغييرات الناجحة
          // 2. ليس من التغييرات على الإطلاق (لم يتغير)
          if (successfulUuids.contains(rowEntry.key) ||
              !computation.changes.any((c) => c.localUuid == rowEntry.key)) {
            filteredRows[rowEntry.key] = rowEntry.value;
          }
        }
        
        filteredSnapshot[entry.key] = filteredRows;
      }

      // حفظ المرآة المحدثة
      await _deltaSyncService!.persistMirror(DeltaSyncComputation(
        changes: successfulChanges,
        mirrorSnapshot: filteredSnapshot,
        fallbackTables: computation.fallbackTables,
      ));

      _logger.info(
        '🪞 تم تحديث Mirror بـ ${successfulChanges.length} تغيير ناجح',
        tag: 'DELTA_SYNC',
      );
    } catch (e) {
      _logger.error('❌ خطأ في تحديث Mirror: $e', tag: 'DELTA_SYNC');
      // لا نرمي الخطأ - البيانات مرفوعة بالفعل
    }
  }

  /// ⭐ تنظيف Outbox فقط للسجلات الناجحة
  Future<void> _cleanupOutboxForSuccessful(
    List<DeltaSyncChange> successfulChanges,
  ) async {
    if (successfulChanges.isEmpty) return;
    
    try {
      final outboxDao = OutboxDao(_database!);
      final successfulUuids = successfulChanges.map((c) => c.localUuid).toSet();
      
      // ⭐ حذف فقط السجلات الناجحة
      await outboxDao.removeByUuids(successfulUuids.toList());
      
      _logger.info(
        '🗑️ تم تنظيف ${successfulUuids.length} سجل ناجح من Outbox',
        tag: 'DELTA_SYNC',
      );
    } catch (e) {
      _logger.warning('⚠️ خطأ في تنظيف Outbox: $e', tag: 'DELTA_SYNC');
      // لا نرمي الخطأ - البيانات مرفوعة بالفعل
    }
  }

  /// ⭐ تحديث قائمة الأخطاء
  void _updateSyncErrors(List<SyncErrorRecord> newErrors) {
    // إزالة الأخطاء القديمة للـ UUIDs الناجحة
    final successfulUuids = _syncErrors
        .where((e) => !newErrors.any((ne) => ne.localUuid == e.localUuid))
        .map((e) => e.localUuid)
        .toSet();

    _syncErrors.removeWhere((e) => successfulUuids.contains(e.localUuid));
    
    // إضافة الأخطاء الجديدة
    _syncErrors.addAll(newErrors);
    
    // الاحتفاظ بآخر 100 خطأ فقط
    if (_syncErrors.length > 100) {
      _syncErrors.removeRange(0, _syncErrors.length - 100);
    }
  }

  /// ⭐ حفظ الأخطاء محلياً
  Future<void> _saveSyncErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final errorsJson = _syncErrors.map((e) => e.toMap()).toList();
      await prefs.setString('sync_errors', jsonEncode(errorsJson));
      debugPrint('💾 تم حفظ ${_syncErrors.length} خطأ مزامنة');
    } catch (e) {
      debugPrint('⚠️ فشل حفظ أخطاء المزامنة: $e');
    }
  }

  /// ⭐ تحميل الأخطاء المحفوظة
  Future<void> _loadSyncErrors() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final errorsStr = prefs.getString('sync_errors');
      if (errorsStr != null && errorsStr.isNotEmpty) {
        final List<dynamic> errorsJson = jsonDecode(errorsStr) as List<dynamic>;
        _syncErrors.clear();
        for (final item in errorsJson) {
          try {
            final error = SyncErrorRecord.fromMap(item as Map<String, dynamic>);
            // فقط الأخطاء التي لم تصل للحد الأقصى
            if (error.retryCount < maxRetryAttempts) {
              _syncErrors.add(error);
            }
          } catch (e) {
            debugPrint('⚠️ خطأ في تحليل سجل خطأ: $e');
          }
        }
        debugPrint('📚 تم تحميل ${_syncErrors.length} خطأ مزامنة محفوظ');
      }
    } catch (e) {
      debugPrint('⚠️ فشل تحميل أخطاء المزامنة: $e');
      // في حالة الفشل، نمسح الأخطاء القديمة التالفة
      _syncErrors.clear();
    }
  }

  /// ⭐ مسح جميع الأخطاء
  Future<void> clearAllErrors() async {
    _syncErrors.clear();
    await _saveSyncErrors();
    _logger.info('🗑️ تم مسح جميع أخطاء المزامنة', tag: 'DELTA_SYNC');
  }

  /// ⭐ مسح خطأ محدد
  Future<void> clearError(int errorId) async {
    _syncErrors.removeWhere((e) => e.id == errorId);
    await _saveSyncErrors();
  }

  /// ⭐ إعادة محاولة جميع الأخطاء
  Future<AppwriteDeltaSyncResult> retryAllFailed() async {
    return await pushDeltaChanges(retryFailed: true);
  }

  // ==================== PULL ====================

  Future<AppwriteDeltaSyncResult> pullDeltaChanges() async {
    final canStart = await SyncLocks.appwriteSyncLock.synchronized(() async {
      if (!isInitialized || _isSyncing) return false;
      _isSyncing = true;
      return true;
    });

    if (!canStart) {
      return AppwriteDeltaSyncResult(
          success: false, message: 'الخدمة غير جاهزة أو المزامنة جارية');
    }

    try {
      _logger.info('📥 بدء سحب التغييرات الحديثة من Appwrite...',
          tag: 'DELTA_SYNC');

      final lastPullEpoch = await _getLastDeltaPullTimestamp();
      final sinceEpoch = lastPullEpoch > 0 
          ? lastPullEpoch 
          : Time.nowEpoch() - (24 * 60 * 60);

      _logger.info('⏱️ سحب التغييرات منذ: $sinceEpoch (epoch)', tag: 'DELTA_SYNC');

      int totalPulled = 0;
      final List<String> failedEntities = [];

      final entities = [
        _SyncEntity('rooms', AppwriteConfig.roomsCollectionId, _adapterRegistry!.rooms),
        _SyncEntity('bookings', AppwriteConfig.bookingsCollectionId, _adapterRegistry!.bookings),
        _SyncEntity('employees', AppwriteConfig.employeesCollectionId, _adapterRegistry!.employees),
        _SyncEntity('expenses', AppwriteConfig.expensesCollectionId, _adapterRegistry!.expenses),
        _SyncEntity('payments', AppwriteConfig.paymentsCollectionId, _adapterRegistry!.payments),
        _SyncEntity('debts', AppwriteConfig.debtsCollectionId, _adapterRegistry!.debts),
        _SyncEntity('booking_notes', AppwriteConfig.bookingNotesCollectionId, _adapterRegistry!.bookingNotes),
        _SyncEntity('booking_nights', AppwriteConfig.bookingNightsCollectionId, _adapterRegistry!.nights),
        _SyncEntity('cash_transactions', AppwriteConfig.cashTransactionsCollectionId, _adapterRegistry!.cashTransactions),
        _SyncEntity('salary_cycles', AppwriteConfig.salaryCyclesCollectionId, _adapterRegistry!.salaryCycles),
        _SyncEntity('salary_payments', AppwriteConfig.salaryPaymentsCollectionId, _adapterRegistry!.salaryPayments),
        _SyncEntity('salary_withdrawals', AppwriteConfig.salaryWithdrawalsCollectionId, _adapterRegistry!.salaryWithdrawals),
        _SyncEntity('shift_notes', AppwriteConfig.shiftNotesCollectionId, _adapterRegistry!.shiftNotes),
      ];

      await _database!.customStatement('PRAGMA foreign_keys = OFF');

      try {
        // ⭐ تحسين: معالجة متوازية للـ entities (4 في المرة)
        const int parallelEntities = 4;
        for (int i = 0; i < entities.length; i += parallelEntities) {
          final batch = entities.skip(i).take(parallelEntities).toList();
          final results = await Future.wait(
            batch.map((entity) async {
              try {
                return (entity, await _pullEntityChanges(entity, sinceEpoch), <String>[]);
              } catch (e) {
                return (entity, 0, [e.toString()]);
              }
            }),
          );
          
          for (final (entity, count, errors) in results) {
            totalPulled += count;
            if (errors.isNotEmpty) {
              failedEntities.add(entity.name);
              _logger.warning('❌ فشل سحب ${entity.name}: ${errors.first}', tag: 'DELTA_SYNC');
            }
          }
        }

        if (totalPulled > 0) {
          await RoomsRepository(_database!).refreshAllRoomOccupancy(originIsServer: true);
        }

        await _updateLastDeltaPullTimestamp();

        // ⭐ إعادة بناء Mirror بعد السحب
        if (totalPulled > 0) {
          _logger.info('🔄 إعادة بناء المرآة...', tag: 'DELTA_SYNC');
          await _deltaSyncService!.rebuildMirror();
        }

      } finally {
        await _database!.customStatement('PRAGMA foreign_keys = ON');
        _logger.info('🔓 تم إعادة تفعيل FOREIGN KEYS', tag: 'DELTA_SYNC');
      }

      final message = failedEntities.isEmpty
          ? 'تم سحب $totalPulled تغيير حديث من Appwrite'
          : 'تم سحب $totalPulled تغيير، فشل في: ${failedEntities.join(', ')}';

      _logger.info('✅ $message', tag: 'DELTA_SYNC');

      return AppwriteDeltaSyncResult(
        success: failedEntities.isEmpty,
        message: message,
        pulledCount: totalPulled,
        failedCount: failedEntities.length,
      );

    } catch (e) {
      _logger.error('❌ خطأ في سحب التغييرات: $e', tag: 'DELTA_SYNC');
      return AppwriteDeltaSyncResult(
        success: false,
        message: e.toString(),
        pulledCount: 0,
      );
    } finally {
      await SyncLocks.appwriteSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  Future<int> _pullEntityChanges(_SyncEntity entity, int sinceEpoch) async {
    if (entity.collectionId == null) {
      _logger.warning('⚠️ لا يوجد collectionId لـ ${entity.name}', tag: 'DELTA_SYNC');
      return 0;
    }

    _logger.info('📥 سحب ${entity.name} (syncTimestamp > $sinceEpoch)...', tag: 'DELTA_SYNC');

    try {
      // ⭐ تحسين: زيادة الحد وجلب صفحات متعددة
      const int pageSize = 500;
      int totalPulledForEntity = 0;
      int offset = 0;
      bool hasMore = true;
      
      while (hasMore) {
        final queries = [
          Query.greaterThan('syncTimestamp', sinceEpoch),
          Query.orderDesc('syncTimestamp'),
          Query.limit(pageSize),
          Query.offset(offset),
        ];

        final response = await _appwriteService!.databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: entity.collectionId!,
          queries: queries,
        );

        final documents = response.documents;

        if (documents.isEmpty) {
          hasMore = false;
          break;
        }

        _logger.info('📦 وُجد ${documents.length} تغيير في ${entity.name}', tag: 'DELTA_SYNC');

        for (final doc in documents) {
          try {
            final data = Map<String, dynamic>.from(doc.data);
            // ⭐ دعم كلا الصيغتين: snake_case و camelCase
            data['local_uuid'] ??= data['localUuid'] ?? doc.$id;
            data['localUuid'] ??= data['local_uuid'];
            data['last_modified'] ??= Time.nowEpoch();
            data['lastModified'] ??= data['last_modified'];

            await entity.repo.upsertFromJson(data, src: Source.appwrite);
            totalPulledForEntity++;
          } catch (e) {
            _logger.warning(
              'فشل حفظ ${entity.name}/${doc.$id}: $e',
              tag: 'DELTA_SYNC',
            );
          }
        }

        // إذا كان عدد المستندات أقل من pageSize، انتهت البيانات
        if (documents.length < pageSize) {
          hasMore = false;
        } else {
          offset += pageSize;
        }
      }

      return totalPulledForEntity;

    } on AppwriteException catch (e) {
      _logger.error(
        '❌ خطأ Appwrite في ${entity.name}: ${e.code} - ${e.message}',
        tag: 'DELTA_SYNC',
      );
      rethrow;
    }
  }

  // ==================== HELPERS ====================

  String? _getCollectionId(String entity) {
    switch (entity) {
      case 'rooms': return AppwriteConfig.roomsCollectionId;
      case 'bookings': return AppwriteConfig.bookingsCollectionId;
      case 'booking_notes': return AppwriteConfig.bookingNotesCollectionId;
      case 'booking_nights': return AppwriteConfig.bookingNightsCollectionId;
      case 'payments': return AppwriteConfig.paymentsCollectionId;
      case 'expenses': return AppwriteConfig.expensesCollectionId;
      case 'cash_transactions': return AppwriteConfig.cashTransactionsCollectionId;
      case 'debts': return AppwriteConfig.debtsCollectionId;
      case 'employees': return AppwriteConfig.employeesCollectionId;
      case 'hotel_day_ledger': return AppwriteConfig.hotelDayLedgerCollectionId;
      case 'salary_cycles': return AppwriteConfig.salaryCyclesCollectionId;
      case 'salary_payments': return AppwriteConfig.salaryPaymentsCollectionId;
      case 'salary_withdrawals': return AppwriteConfig.salaryWithdrawalsCollectionId;
      case 'shift_notes': return AppwriteConfig.shiftNotesCollectionId;
      case 'price_adjustments': return AppwriteConfig.priceAdjustmentsCollectionId;
      case 'booking_price_adjustments': return AppwriteConfig.bookingPriceAdjustmentsCollectionId;
      case 'audit_logs': return AppwriteConfig.auditLogsCollectionId;
      case 'payment_voids': return AppwriteConfig.paymentVoidsCollectionId;
      default: return null;
    }
  }

  /// ⭐ إصلاح: Appwrite schema يستخدم camelCase للحقول
  /// يجب إرسال الحقول بصيغة camelCase NOT snake_case
  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> payload,
      {required String collectionEntity}) {
    final sanitized = <String, dynamic>{};

    // ⭐ حقول داخلية للمزامنة المحلية - لا ترسل لـ Appwrite
    final excludedFields = {
      'local_id',      // معرف محلي داخلي
      'row_hash',      // hash للمزامنة المحلية
      'rowHash',       // camelCase version (احتياطي)
    };

    // ⭐ snake_case fields that need to be converted to camelCase for Appwrite
    final snakeToCamel = {
      'local_uuid': 'localUuid',
      'server_id': 'serverId',
      'created_at': 'createdAt',
      'updated_at': 'updatedAt',
      'deleted_at': 'deletedAt',
      'last_modified': 'lastModified',
      'created_at_iso': 'createdAtIso',
      'updated_at_iso': 'updatedAtIso',
      'deleted_at_iso': 'deletedAtIso',
      'created_at_epoch': 'createdAtEpoch',
      'last_modified_epoch': 'lastModifiedEpoch',
      'vector_clock': 'vectorClock',
      'device_id': 'deviceId',
      'sync_timestamp': 'syncTimestamp',
      'booking_local_id': 'bookingLocalId',
      'hotel_day_key': 'hotelDayKey',
      'night_start': 'nightStart',
      'night_end': 'nightEnd',
      'nightly_rate': 'nightlyRate',
      'base_rate': 'baseRate',
      'final_rate': 'finalRate',
      'applied_adjustment_uuid': 'appliedAdjustmentUuid',
      'expense_id': 'expenseId',
      'employee_id': 'employeeId',
      'cycle_id': 'cycleId',
      'payment_date_iso': 'paymentDateIso',
      'is_auto_generated': 'isAutoGenerated',
      'is_processed_by_auto_fix': 'isProcessedByAutoFix',
    };

    // ⭐ الحقول المطلوبة إضافياً (Appwrite required fields) - camelCase
    final nowEpoch = Time.nowEpoch();
    final requiredDefaults = {
      'createdAt': nowEpoch,
      'updatedAt': nowEpoch,
      'lastModified': nowEpoch,
      'version': 1,
      'origin': 'local',
      'vectorClock': '{}',
      'deviceId': _deviceId ?? 'unknown',
      'syncTimestamp': nowEpoch,
    };

    // نسخ جميع الحقول ما عدا المستثناة مع تحويل snake_case إلى camelCase
    for (final entry in payload.entries) {
      final key = entry.key;
      final value = entry.value;

      // تخطي الحقول الداخلية
      if (excludedFields.contains(key)) continue;

      // تحويل snake_case إلى camelCase
      final outputKey = snakeToCamel[key] ?? key;

      // معالجة القيم المتداخلة
      if (value is Map<String, dynamic>) {
        sanitized[outputKey] = _sanitizePayload(value, collectionEntity: collectionEntity);
      } else {
        sanitized[outputKey] = value;
      }
    }

    // ⭐ التأكد من وجود الحقول المطلوبة (فقط إذا لم تكن موجودة أو null)
    for (final req in requiredDefaults.entries) {
      final currentValue = sanitized[req.key];
      if (currentValue == null || (currentValue is String && currentValue.isEmpty && req.key == 'vectorClock')) {
        sanitized[req.key] = req.value;
      }
      // إذا الحقل غير موجود نهائياً
      if (!sanitized.containsKey(req.key)) {
        sanitized[req.key] = req.value;
      }
    }

    // ⭐ التأكد من وجود localUuid (مطلوب في معظم collections)
    if (!sanitized.containsKey('localUuid')) {
      // استخدام الـ UUID من change أو توليد واحد جديد
      sanitized['localUuid'] = payload['localUuid'] ?? 
                               payload['local_uuid'] ?? 
                               IdGen.uuid();
    }

    // ⭐ معالجة خاصة للجداول التي تتطلب حقل id صريح (integer)
    final requiresExplicitId = {
      'salary_withdrawals',
    };

    if (requiresExplicitId.contains(collectionEntity)) {
      if (!sanitized.containsKey('id') || sanitized['id'] == null) {
        // استخدام timestamp كـ id فريد (integer)
        sanitized['id'] = nowEpoch + (DateTime.now().microsecond % 1000);
      }
    }

    return sanitized;
  }

  Future<int> _getLastDeltaPushTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsLastDeltaPushKey) ?? 0;
  }

  Future<void> _updateLastDeltaPushTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastDeltaPushKey, Time.nowEpoch());
  }

  Future<int> _getLastDeltaPullTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_prefsLastDeltaPullKey) ?? 0;
  }

  Future<void> _updateLastDeltaPullTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_prefsLastDeltaPullKey, Time.nowEpoch());
  }

  Future<Map<String, dynamic>> getStatus() async {
    final lastPush = await _getLastDeltaPushTimestamp();
    final lastPull = await _getLastDeltaPullTimestamp();
    return {
      'initialized': isInitialized,
      'is_syncing': _isSyncing,
      'last_push_epoch': lastPush,
      'last_pull_epoch': lastPull,
      'last_push_time': lastPush > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastPush * 1000).toIso8601String()
          : null,
      'last_pull_time': lastPull > 0
          ? DateTime.fromMillisecondsSinceEpoch(lastPull * 1000).toIso8601String()
          : null,
      'pending_errors': _syncErrors.length,
    };
  }

  void dispose() {
    _errorsController.close();
  }
}

class _SyncEntity {
  final String name;
  final String? collectionId;
  final BaseRepository repo;

  _SyncEntity(this.name, this.collectionId, this.repo);
}
