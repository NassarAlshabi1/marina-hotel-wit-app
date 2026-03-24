// lib/services/appwrite_delta_sync.dart

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
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
import 'conflict_resolver.dart';
import 'field_level_sync.dart';  // ✅ Field-Level Sync

class AppwriteDeltaSyncResult {
  AppwriteDeltaSyncResult({
    required this.success,
    required this.message,
    this.pushedCount = 0,
    this.pulledCount = 0,
    this.conflictCount = 0,
    this.failedCount = 0,
  });
  final bool success;
  final String message;
  final int pushedCount;
  final int pulledCount;
  final int conflictCount;
  final int failedCount;

  int get recordsPulled => pulledCount;
  int get recordsPushed => pushedCount;
  bool get hasConflicts => conflictCount > 0;
}

class AppwriteDeltaSync {
  AppwriteDeltaSync._();
  static final instance = AppwriteDeltaSync._();

  AppwriteService? _appwriteService;
  DeltaSyncService? _deltaSyncService;
  AppDatabase? _database;
  AdapterRegistry? _adapterRegistry;
  String? _deviceId;
  bool _isSyncing = false;

  final _logger = AppwriteLogger();

  static const _prefsLastDeltaPushKey = 'appwrite_last_delta_push';
  static const _prefsLastDeltaPullKey = 'appwrite_last_delta_pull';
  static const _prefsDeviceIdKey = 'appwrite_delta_device_id';
  static const _prefsDeltaSyncEnabledKey = 'appwrite_delta_sync_enabled';
  
  /// حجم الدفعة الواحدة في PULL
  static const int _pullBatchSize = 100;
  /// الحد الأقصى للسجلات في PULL الواحد (0 = بدون حد)
  static const int _maxPullRecords = 500;

  Future<void> initialize(
      AppwriteService appwriteService, AppDatabase db) async {
    _appwriteService = appwriteService;
    _database = db;
    _deltaSyncService = DeltaSyncService(db);
    _adapterRegistry = AdapterRegistry(db);
    await _initializeDeviceId();
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

  // ==================== PUSH ====================

  Future<AppwriteDeltaSyncResult> pushDeltaChanges() async {
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
      _logger.info('📤 بدء المزامنة التفاضلية (Field-Level) إلى Appwrite...',
          tag: 'DELTA_SYNC');
      
      // ✅ استخدام Field-Level Sync فقط عبر DeltaSyncService
      // لا نستخدم Outbox التقليدي - DeltaSyncService يحسب الفروقات على مستوى الحقل
      final lastPushTs = await _getLastDeltaPushTimestamp();
      final computation = await _deltaSyncService!.compute(since: lastPushTs);

      if (computation.changes.isEmpty) {
        _logger.info('✅ لا توجد تغييرات للمزامنة', tag: 'DELTA_SYNC');
        return AppwriteDeltaSyncResult(
            success: true, message: 'لا توجد تغييرات', pushedCount: 0);
      }

      _logger.info('📊 تم اكتشاف ${computation.changes.length} تغيير للحصول على Field-Level', tag: 'DELTA_SYNC');

      final successfulChanges = <DeltaSyncChange>[];
      final failedChanges = <DeltaSyncChange>[];

      // تحسين: معالجة الدفعات بشكل تسلسلي لتجنب تعارضات الشبكة وزيادة الاستقرار
      for (final change in computation.changes) {
        try {
          await _pushSingleChange(change);
          successfulChanges.add(change);
        } catch (e) {
          _logger.warning(
              'فشل رفع تغيير: ${change.entity}/${change.localUuid} - $e',
              tag: 'DELTA_SYNC');
          failedChanges.add(change);
          
          // إذا كان الخطأ متعلقاً بالشبكة، نتوقف عن المحاولة لهذه الدفعة
          if (e.toString().contains('SocketException') || 
              e.toString().contains('HttpException') ||
              e.toString().contains('Connection refused')) {
            _logger.error('توقف المزامنة بسبب مشكلة في الاتصال', tag: 'DELTA_SYNC');
            break;
          }
        }
      }

      if (successfulChanges.isNotEmpty) {
        await _persistSuccessfulChanges(computation, successfulChanges);
        // ✅ مسح السجلات الناجحة من Outbox فوراً
        await _cleanupOutboxAfterSync(successfulChanges);
        await _updateLastDeltaPushTimestamp();
      }

      final totalPushed = successfulChanges.length;
      final totalFailed = failedChanges.length;
      
      final hasFailures = totalFailed > 0;
      final message = hasFailures
          ? 'تم رفع $totalPushed تغيير (Field-Level) وفشل $totalFailed'
          : 'تم رفع $totalPushed تغيير (Field-Level) بنجاح';

      _logger.info('✅ $message', tag: 'DELTA_SYNC');
      return AppwriteDeltaSyncResult(
          success: !hasFailures,
          message: message,
          pushedCount: totalPushed,
          failedCount: totalFailed);
    } catch (e) {
      _logger.error('❌ خطأ في المزامنة التفاضلية: $e', tag: 'DELTA_SYNC');
      return AppwriteDeltaSyncResult(success: false, message: e.toString());
    } finally {
      await SyncLocks.appwriteSyncLock.synchronized(() async {
        _isSyncing = false;
      });
    }
  }

  /// ✅ رفع تغيير واحد باستخدام Field-Level Sync
  Future<void> _pushSingleChange(DeltaSyncChange change) async {
    final collectionId = _getCollectionId(change.entity);
    if (collectionId == null) return;

    final payload = Map<String, dynamic>.from(change.data);
    payload['deviceId'] = _deviceId;
    payload['syncTimestamp'] = Time.nowEpoch();

    // ✅ استخدام Field-Level payload إذا كان متاحاً
    Map<String, dynamic> sanitizedPayload;
    if (change.fieldChanges != null && change.fieldChanges!.isNotEmpty) {
      // استخدام الحقول المتغيرة فقط مع Field-Level metadata
      sanitizedPayload = _sanitizePayload(payload, collectionEntity: change.entity);
      
      // إضافة Field-Level metadata
      for (final fieldChange in change.fieldChanges!) {
        sanitizedPayload['_${fieldChange.fieldName}_version'] = fieldChange.version;
        sanitizedPayload['_${fieldChange.fieldName}_timestamp'] = fieldChange.timestamp;
        sanitizedPayload['_${fieldChange.fieldName}_device'] = fieldChange.deviceId;
      }
      
      _logger.debug(
        '📤 Field-Level update: ${change.entity}/${change.localUuid} - ${change.fieldChanges!.length} fields changed',
        tag: 'DELTA_SYNC',
      );
    } else {
      sanitizedPayload = _sanitizePayload(payload, collectionEntity: change.entity);
    }
    
    // إذا كانت البيانات فارغة، نتخطى هذا السجل
    if (sanitizedPayload.isEmpty) {
      _logger.info(
        '⏭️ تخطي ${change.entity}/${change.localUuid} - بيانات غير مكتملة',
        tag: 'DELTA_SYNC',
      );
      return;
    }

    switch (change.operation) {
      case 'insert':
        await _appwriteService!.upsertDocument(
          collectionId: collectionId,
          documentId: change.localUuid,
          data: sanitizedPayload,
        );
      case 'update':
        // تحسين: استخدام التحديث الجزئي (Patch) إذا كان التغيير يحتوي على فروقات فقط
        // هذا يقلل بشكل كبير من استهلاك البيانات ويمنع مسح الحقول غير الموجودة في الـ diff
        await _appwriteService!.databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: collectionId,
          documentId: change.localUuid,
          data: sanitizedPayload,
        );
      case 'delete':
        try {
          await _appwriteService!.deleteDocument(
              collectionId: collectionId, documentId: change.localUuid);
        } on AppwriteException catch (e) {
          // تم التعامل مع خطأ 404 مسبقاً في AppwriteService و AppwriteNetworkHelper
          if (e.code != 404) rethrow;
        }
    }
  }

  // ==================== PULL (مع Pagination) ====================

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
        _SyncEntity('shift_notes', AppwriteConfig.shiftNotesCollectionId, _adapterRegistry!.shiftNotes),
        // ✅ كيانات جديدة
        _SyncEntity('salary_withdrawals', AppwriteConfig.salaryWithdrawalsCollectionId, _adapterRegistry!.salaryWithdrawals),
        _SyncEntity('booking_price_adjustments', AppwriteConfig.bookingPriceAdjustmentsCollectionId, _adapterRegistry!.bookingPriceAdjustments),
      ];

      await _database!.customStatement('PRAGMA foreign_keys = OFF');

      try {
        for (final entity in entities) {
          try {
            // ✅ استخدام pagination لجلب جميع السجلات
            final count = await _pullEntityChangesWithPagination(entity, sinceEpoch);
            totalPulled += count;
          } catch (e) {
            failedEntities.add(entity.name);
            _logger.warning('❌ فشل سحب ${entity.name}: $e', tag: 'DELTA_SYNC');
          }
        }

        if (totalPulled > 0) {
          await RoomsRepository(_database!).refreshAllRoomOccupancy(originIsServer: true);
        }

        await _updateLastDeltaPullTimestamp();

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

  /// ✅ سحب التغييرات مع Pagination لجلب جميع السجلات
  Future<int> _pullEntityChangesWithPagination(_SyncEntity entity, int sinceEpoch) async {
    if (entity.collectionId == null) {
      _logger.warning('⚠️ لا يوجد collectionId لـ ${entity.name}', tag: 'DELTA_SYNC');
      return 0;
    }

    _logger.info('📥 سحب ${entity.name} (syncTimestamp > $sinceEpoch)...', tag: 'DELTA_SYNC');

    int totalSuccessCount = 0;
    int offset = 0;
    int batchCount;
    int totalBatches = 0;

    // استراتيجيات حل التعارضات حسب نوع الكيان
    // lastWriteWins: الأخير يفوز (أبسط وأسرع)
    // fieldLevel: دمج على مستوى الحقل (أكثر دقة)
    final conflictResolver = EnhancedConflictResolver(
      defaultStrategy: ConflictStrategy.lastWriteWins,
      tableStrategies: {
        // الحجوزات: الأخير يفوز (لتجنب تعقيدات الدمج)
        'bookings': ConflictStrategy.lastWriteWins,
        // الغرف: الأخير يفوز (تغييرات بسيطة)
        'rooms': ConflictStrategy.lastWriteWins,
        // المدفوعات: الأخير يفوز (حساس - لا نريد دمج خاطئ)
        'payments': ConflictStrategy.lastWriteWins,
        // المصروفات: الأخير يفوز
        'expenses': ConflictStrategy.lastWriteWins,
        // الديون: دمج على مستوى الحقل (معلومات مالية دقيقة)
        'debts': ConflictStrategy.fieldLevel,
        // الموظفين: دمج على مستوى الحقل (بيانات شخصية متعددة)
        'employees': ConflictStrategy.fieldLevel,
        // المعاملات النقدية: الأخير يفوز
        'cash_transactions': ConflictStrategy.lastWriteWins,
        // ملاحظات الورديات: دمج على مستوى الحقل (محتوى نصي)
        'shift_notes': ConflictStrategy.fieldLevel,
        // ملاحظات الحجز: دمج على مستوى الحقل (تنبيهات متعددة)
        'booking_notes': ConflictStrategy.fieldLevel,
        // ليالي الحجز: الأخير يفوز (بيانات حسابية)
        'booking_nights': ConflictStrategy.lastWriteWins,
        // دورات الرواتب: الأخير يفوز
        'salary_cycles': ConflictStrategy.lastWriteWins,
        // مدفوعات الرواتب: الأخير يفوز
        'salary_payments': ConflictStrategy.lastWriteWins,
        // سحوبات الرواتب: الأخير يفوز (حساس)
        'salary_withdrawals': ConflictStrategy.lastWriteWins,
        // تعديلات أسعار الحجوزات: الأخير يفوز (بيانات حسابية)
        'booking_price_adjustments': ConflictStrategy.lastWriteWins,
        // معلومات الضيوف: دمج على مستوى الحقل
        'guest_infos': ConflictStrategy.fieldLevel,
      },
    );

    // ✅ جلب السجلات على دفعات
    do {
      totalBatches++;
      batchCount = 0;

      try {
        final queries = [
          Query.greaterThan('syncTimestamp', sinceEpoch),
          Query.orderDesc('syncTimestamp'),
          Query.limit(_pullBatchSize),
          Query.offset(offset),
        ];

        final response = await _appwriteService!.databases.listDocuments(
          databaseId: AppwriteConfig.databaseId,
          collectionId: entity.collectionId!,
          queries: queries,
        );

        final documents = response.documents;

        if (documents.isEmpty) {
          break; // لا مزيد من السجلات
        }

        _logger.debug(
          '📦 دفعة $totalBatches: ${documents.length} سجل من ${entity.name}',
          tag: 'DELTA_SYNC',
        );

        for (final doc in documents) {
          try {
            final remoteData = Map<String, dynamic>.from(doc.data);
            final localUuid = remoteData['localUuid'] ?? doc.$id;
            remoteData['localUuid'] = localUuid;
            
            final localData = await entity.repo.getJsonByUuid(localUuid);
            
            if (localData != null) {
              final localTs = localData['lastModified'] ?? localData['updated_at'] ?? 0;
              final remoteTs = remoteData['syncTimestamp'] ?? remoteData['updated_at'] ?? 0;
              
              if (localTs > 0 && remoteTs > 0 && localTs > remoteTs) {
                final resolution = conflictResolver.resolve(ConflictContext(
                  table: entity.name,
                  uuid: localUuid,
                  localData: localData,
                  remoteData: remoteData,
                  localTimestamp: DateTime.fromMillisecondsSinceEpoch(localTs * 1000),
                  remoteTimestamp: DateTime.fromMillisecondsSinceEpoch(remoteTs * 1000),
                  localDeviceId: _deviceId ?? 'unknown',
                  remoteDeviceId: remoteData['deviceId'] ?? 'remote',
                ));
                
                if (resolution.winner == remoteData || resolution.mergedData != null) {
                  await entity.repo.upsertFromJson(resolution.mergedData ?? remoteData, src: Source.appwrite);
                }
              } else {
                await entity.repo.upsertFromJson(remoteData, src: Source.appwrite);
              }
            } else {
              await entity.repo.upsertFromJson(remoteData, src: Source.appwrite);
            }
            
            batchCount++;
            totalSuccessCount++;
          } catch (e) {
            _logger.warning(
              'فشل حفظ ${entity.name}/${doc.$id}: $e',
              tag: 'DELTA_SYNC',
            );
          }
        }

        offset += _pullBatchSize;

        // التحقق من الحد الأقصى
        if (_maxPullRecords > 0 && totalSuccessCount >= _maxPullRecords) {
          _logger.info(
            '⏸️ تم الوصول للحد الأقصى ($_maxPullRecords) في ${entity.name}',
            tag: 'DELTA_SYNC',
          );
          break;
        }

      } on AppwriteException catch (e) {
        _logger.error(
          '❌ خطأ Appwrite في ${entity.name}: ${e.code} - ${e.message}',
          tag: 'DELTA_SYNC',
        );
        rethrow;
      }
    } while (batchCount == _pullBatchSize); // استمر إذا كانت الدفعة ممتلئة

    if (totalSuccessCount > 0) {
      _logger.info(
        '✅ ${entity.name}: $totalSuccessCount سجل في $totalBatches دفعة',
        tag: 'DELTA_SYNC',
      );
    }

    return totalSuccessCount;
  }

  /// الطريقة القديمة (للتوافق)
  Future<int> _pullEntityChanges(_SyncEntity entity, int sinceEpoch) async {
    return _pullEntityChangesWithPagination(entity, sinceEpoch);
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
      // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته
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

  /// حقول محلية فقط لا يجب إرسالها إلى Appwrite
  static const _localOnlyFields = {
    'id',
    'local_id',
    'rowHash',          // حقل محلي للتتبع
    'lastModifiedEpoch',
    'createdAtEpoch',
    'deletedAtEpoch',
  };

  /// حقول sync التي يجب إزالتها من المجموعات التي لا تدعمها
  /// هذه الحقول تُرسل من الـ adapters لكن Appwrite لا يدعمها في بعض المجموعات
  static const _unsupportedSyncFields = {
    'bookings': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'booking_nights': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'salary_payments': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'salary_cycles': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'shift_notes': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'booking_notes': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'rooms': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'employees': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'expenses': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
    'cash_transactions': ['sync_version', 'sync_vector_clock', 'vector_clock', 'sync_origin'],
  };

  /// حقول مطلوبة لكل كيان في Appwrite
  static const _requiredFieldsPerEntity = {
    'salary_payments': ['employeeId', 'cycleId', 'paymentDateIso', 'paymentDate'],
    'shift_notes': ['shiftDate', 'createdAt'],
    'salary_withdrawals': ['employeeId', 'action', 'amount', 'date'],
    'salary_cycles': ['employeeId', 'cycleKey', 'startDate', 'endDate'],
    'cash_transactions': ['transactionType', 'transactionTime'],
    'booking_price_adjustments': ['bookingUuid', 'bookingLocalUuid', 'effectiveHotelDay'],
    'payments': ['amount', 'paymentDate', 'paymentMethod', 'revenueType', 'sync_version', 'sync_vector_clock'],
  };

  /// حقول sync مطلوبة فقط لمجموعات محددة (ليست كل المجموعات)
  static const _syncFieldsPerEntity = {
    'payments': ['sync_version', 'sync_vector_clock'],
    'debts': ['vector_clock', 'sync_version', 'sync_origin', 'sync_vector_clock'],
  };

  Map<String, dynamic> _sanitizePayload(Map<String, dynamic> payload,
      {required String collectionEntity}) {
    final sanitized = Map<String, dynamic>.from(payload);

    // إزالة الحقول المحلية فقط
    for (final field in _localOnlyFields) {
      sanitized.remove(field);
    }

    // ✅ إزالة حقول sync غير المدعومة لهذه المجموعة
    final unsupportedFields = _unsupportedSyncFields[collectionEntity];
    if (unsupportedFields != null) {
      for (final field in unsupportedFields) {
        sanitized.remove(field);
      }
    }

    // تحويل المبالغ إلى أعداد صحيحة (Appwrite يتطلب integer)
    _convertAmountsToInt(sanitized);

    // تحويل vectorClock من Map إلى String إذا كان Map
    if (sanitized.containsKey('vectorClock')) {
      final vc = sanitized['vectorClock'];
      if (vc is Map) {
        sanitized['vectorClock'] = jsonEncode(vc);
      } else if (vc == null) {
        sanitized['vectorClock'] = '{}';
      }
    }

    // ✅ تقليص الحقول النصية الطويلة (Appwrite يحدد 50 حرف للـ strings القصيرة)
    _truncateStringFields(sanitized);

    // ✅ إضافة id إذا لم يكن موجوداً (بعض المجموعات تتطلبه)
    // ملاحظة: لا نضيف id لأن Appwrite يستخدم document ID تلقائياً

    // ✅ إضافة حقول sync فقط للمجموعات التي تتطلبها
    final syncFields = _syncFieldsPerEntity[collectionEntity];
    if (syncFields != null) {
      for (final field in syncFields) {
        if (!sanitized.containsKey(field) || sanitized[field] == null) {
          switch (field) {
            case 'sync_version':
              sanitized['sync_version'] = sanitized['version'] ?? 1;
              break;
            case 'sync_vector_clock':
              final vc = sanitized['vectorClock'] ?? sanitized['vector_clock'];
              sanitized['sync_vector_clock'] = vc is String ? vc : jsonEncode(vc ?? {});
              break;
            case 'vector_clock':
              final vc2 = sanitized['vectorClock'];
              sanitized['vector_clock'] = vc2 is String ? vc2 : jsonEncode(vc2 ?? {});
              break;
            case 'sync_origin':
              sanitized['sync_origin'] = sanitized['origin'] ?? 'mobile';
              break;
          }
        }
      }
    }
    
    // التحقق من الحقول المطلوبة وإضافة قيم افتراضية إذا كانت مفقودة
    final requiredFields = _requiredFieldsPerEntity[collectionEntity];
    if (requiredFields != null) {
      for (final field in requiredFields) {
        if (!sanitized.containsKey(field) || sanitized[field] == null) {
          // إضافة قيم افتراضية للحقول المطلوبة المفقودة
          switch (field) {
            case 'employeeId':
              // محاولة استخراج employeeId من بيانات أخرى
              final relatedId = sanitized['relatedId'];
              if (relatedId != null) {
                sanitized['employeeId'] = relatedId;
              } else {
                _logger.warning(
                  '⚠️ $collectionEntity: $field مفقود، سيتم تخطي هذا السجل',
                  tag: 'DELTA_SYNC',
                );
                return {}; // إرجاع قائمة فارغة لتخطي هذا السجل
              }
              break;
            case 'shiftDate':
              // استخدام createdAtIso كـ shiftDate
              sanitized['shiftDate'] = sanitized['createdAtIso'] ?? 
                  DateTime.now().toIso8601String();
              break;
            case 'paymentDate':
              // استخدام paymentDateIso كـ paymentDate
              sanitized['paymentDate'] = sanitized['paymentDateIso'] ?? 
                  sanitized['createdAtIso'] ?? 
                  DateTime.now().toIso8601String();
              break;
            case 'createdAt':
              // إنشاء createdAt من createdAtIso أو الوقت الحالي
              if (sanitized['createdAtIso'] != null) {
                try {
                  sanitized['createdAt'] = DateTime.parse(sanitized['createdAtIso']).millisecondsSinceEpoch;
                } catch (_) {
                  sanitized['createdAt'] = DateTime.now().millisecondsSinceEpoch;
                }
              } else {
                sanitized['createdAt'] = DateTime.now().millisecondsSinceEpoch;
              }
              break;
            case 'cycleId':
              // cycleId مطلوب، إذا لم يكن موجوداً نتخطى السجل
              _logger.warning(
                '⚠️ $collectionEntity: $field مفقود، سيتم تخطي هذا السجل',
                tag: 'DELTA_SYNC',
              );
              return {};
            case 'startDate':
              // استخدام hotelDayStart أو createdAtIso كـ startDate
              sanitized['startDate'] = sanitized['hotelDayStart'] ?? 
                  sanitized['createdAtIso'] ?? 
                  DateTime.now().toIso8601String();
              break;
            case 'endDate':
              // استخدام hotelDayEnd أو createdAtIso كـ endDate
              sanitized['endDate'] = sanitized['hotelDayEnd'] ?? 
                  sanitized['startDate'] ?? 
                  DateTime.now().toIso8601String();
              break;
            case 'bookingUuid':
              // استخدام bookingLocalUuid كـ bookingUuid
              sanitized['bookingUuid'] = sanitized['bookingLocalUuid'] ?? 
                  sanitized['bookingLocalId']?.toString() ?? 
                  sanitized['localUuid'] ?? '';
              break;
            case 'bookingLocalUuid':
              // bookingLocalUuid مطلوب، استخدام bookingUuid أو localUuid كقيمة افتراضية
              if (sanitized['bookingLocalUuid'] == null) {
                sanitized['bookingLocalUuid'] = sanitized['bookingUuid'] ?? 
                    sanitized['localUuid'] ?? '';
              }
              break;
            case 'effectiveHotelDay':
              // effectiveHotelDay مطلوب، استخدام تاريخ اليوم إذا لم يكن موجوداً
              if (sanitized['effectiveHotelDay'] == null || sanitized['effectiveHotelDay'].toString().isEmpty) {
                sanitized['effectiveHotelDay'] = DateTime.now().toIso8601String().split('T').first;
              }
              break;
            case 'amount':
              // amount مطلوب - استخدام 0 كقيمة افتراضية
              sanitized['amount'] = sanitized['amount'] ?? 0;
              break;
            case 'date':
              // date مطلوب - استخدام التاريخ الحالي
              sanitized['date'] = sanitized['date'] ?? 
                  DateTime.now().toIso8601String().split('T').first;
              break;
            case 'action':
              // action مطلوب لـ salary_withdrawals - قيمة افتراضية
              sanitized['action'] = sanitized['action'] ?? 'سحب راتب';
              break;
            case 'amount':
              // amount مطلوب - استخدام 0 كقيمة افتراضية
              sanitized['amount'] = sanitized['amount'] ?? 0;
              break;
            case 'paymentMethod':
              // paymentMethod مطلوب لـ payments
              sanitized['paymentMethod'] = sanitized['paymentMethod'] ?? 'نقدي';
              break;
            case 'revenueType':
              // revenueType مطلوب لـ payments
              sanitized['revenueType'] = sanitized['revenueType'] ?? 'room';
              break;
            case 'paymentDate':
              // paymentDate مطلوب لـ payments
              sanitized['paymentDate'] = sanitized['paymentDate'] ?? 
                  DateTime.now().toIso8601String();
              break;
            case 'sync_version':
              // sync_version لـ payments/debts
              sanitized['sync_version'] = sanitized['version'] ?? 
                  sanitized['sync_version'] ?? 1;
              break;
            case 'sync_vector_clock':
              // sync_vector_clock لـ payments/debts
              final vc = sanitized['vectorClock'] ?? sanitized['sync_vector_clock'] ?? '{}';
              sanitized['sync_vector_clock'] = vc is String ? vc : jsonEncode(vc);
              break;
            default:
              // للحقول الأخرى، نستخدم قيمة افتراضية
              if (sanitized[field] == null) {
                sanitized[field] = '';
              }
          }
        }
      }
    }
    
    // ✅ التحقق من حقول التخفيض في bookings
    // إذا كان هناك تخفيض، يجب إرسال الثلاثة حقول معاً
    if (collectionEntity == 'bookings') {
      final hasDiscount = sanitized.containsKey('discount') && 
                       sanitized['discount'] != null && 
                       (sanitized['discount'] as num) > 0;
      
      if (hasDiscount) {
        // التأكد من وجود discountType
        if (!sanitized.containsKey('discountType') || 
            sanitized['discountType'] == null ||
            (sanitized['discountType'] as String).isEmpty) {
          sanitized['discountType'] = 'per_night'; // قيمة افتراضية
          _logger.debug(
            '📝 أضيف discountType=default للتخفيض',
            tag: 'DELTA_SYNC',
          );
        }
        
        // التأكد من وجود discountStartDate
        if (!sanitized.containsKey('discountStartDate') || 
            sanitized['discountStartDate'] == null ||
            (sanitized['discountStartDate'] as String).isEmpty) {
          // استخدام تاريخ اليوم كقيمة افتراضية
          sanitized['discountStartDate'] = DateTime.now().toIso8601String().split('T').first;
          _logger.debug(
            '📝 أضيف discountStartDate=${sanitized['discountStartDate']} للتخفيض',
            tag: 'DELTA_SYNC',
          );
        }
      }
    }
    
    return sanitized;
  }

  /// تحويل حقول المبالغ إلى أعداد صحيحة
  void _convertAmountsToInt(Map<String, dynamic> data) {
    final amountFields = [
      'amount',
      'price',
      'basicSalary',
      'totalAmount',
      'paidAmount',
      'remainingAmount',
      'discount',
      'totalDueCached',
      'totalPaidCached',
      'remainingBalanceCached',
      'nightlyRate',
      'baseRate',
      'adjustment',
      'finalRate',
      'expectedAmount',
      'actualPaid',
    ];

    for (final field in amountFields) {
      if (data.containsKey(field) && data[field] != null) {
        final value = data[field];
        if (value is double) {
          data[field] = value.round();
        } else if (value is String) {
          final parsed = double.tryParse(value);
          if (parsed != null) {
            data[field] = parsed.round();
          }
        }
      }
    }
  }

  /// ✅ تقليص الحقول النصية الطويلة (Appwrite يحدد 50 حرف للـ strings القصيرة)
  void _truncateStringFields(Map<String, dynamic> data) {
    // حقول يجب تقليصها إلى 50 حرف كحد أقصى
    final shortStringFields = {
      'stayDurationIso': 50,
      'roomNumber': 20,
      'guestName': 100,
      'guestPhone': 20,
      'nationality': 50,
      'status': 30,
      'paymentMethod': 30,
      'transactionType': 30,
    };

    for (final entry in shortStringFields.entries) {
      final field = entry.key;
      final maxLength = entry.value;

      if (data.containsKey(field) && data[field] is String) {
        final value = data[field] as String;
        if (value.length > maxLength) {
          data[field] = value.substring(0, maxLength);
          _logger.debug(
            '✂️ تم تقليص $field من ${value.length} إلى $maxLength حرف',
            tag: 'DELTA_SYNC',
          );
        }
      }
    }
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

  Future<void> _persistSuccessfulChanges(DeltaSyncComputation computation,
      List<DeltaSyncChange> successfulChanges) async {
    final successfulUuids = successfulChanges.map((c) => c.localUuid).toSet();
    final filteredSnapshot = <String, Map<String, MirrorRow>>{};

    for (final entry in computation.mirrorSnapshot.entries) {
      final filteredRows = <String, MirrorRow>{};
      for (final rowEntry in entry.value.entries) {
        if (successfulUuids.contains(rowEntry.key) ||
            !computation.changes.any((c) => c.localUuid == rowEntry.key)) {
          filteredRows[rowEntry.key] = rowEntry.value;
        }
      }
      filteredSnapshot[entry.key] = filteredRows;
    }

    await _deltaSyncService!.persistMirror(DeltaSyncComputation(
      changes: successfulChanges,
      mirrorSnapshot: filteredSnapshot,
      fallbackTables: computation.fallbackTables,
    ));
  }

  /// ✅ مسح السجلات الناجحة من Outbox فوراً بعد النجاح
  Future<void> _cleanupOutboxAfterSync(
      List<DeltaSyncChange> successfulChanges) async {
    try {
      final outboxDao = OutboxDao(_database!);
      
      // مسح بناءً على entity + localUuid
      int totalDeleted = 0;
      for (final change in successfulChanges) {
        final deleted = await outboxDao.removeByEntityAndUuid(
          change.entity, 
          change.localUuid,
        );
        totalDeleted += deleted;
      }
      
      // أيضاً مسح أي سجلات معلقة مرتبطة بنفس UUIDs (للتأكد)
      final successfulUuids = successfulChanges.map((c) => c.localUuid).toList();
      await outboxDao.cleanupSuccessfulByUuids(successfulUuids);
      
      _logger.info(
        '🧹 تم مسح $totalDeleted سجل من Outbox (${successfulChanges.length} تغيير)',
        tag: 'DELTA_SYNC',
      );
    } catch (e) {
      _logger.warning('⚠️ خطأ في تنظيف Outbox: $e', tag: 'DELTA_SYNC');
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    final lastPush = await _getLastDeltaPushTimestamp();
    final lastPull = await _getLastDeltaPullTimestamp();
    
    // إضافة إحصائيات Outbox
    final outboxDao = OutboxDao(_database!);
    final outboxStats = await outboxDao.getStats();
    
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
      'outbox': {
        'pending': outboxStats.pending,
        'processing': outboxStats.processing,
        'failed': outboxStats.failed,
        'conflicts': outboxStats.conflicts,
        'total': outboxStats.total,
      },
    };
  }
  
  /// مزامنة كاملة (Push + Pull)
  Future<AppwriteDeltaSyncResult> fullSync() async {
    _logger.info('🔄 بدء مزامنة كاملة...', tag: 'DELTA_SYNC');
    
    // Push أولاً
    final pushResult = await pushDeltaChanges();
    
    // ثم Pull
    final pullResult = await pullDeltaChanges();
    
    return AppwriteDeltaSyncResult(
      success: pushResult.success && pullResult.success,
      message: 'Push: ${pushResult.message}\nPull: ${pullResult.message}',
      pushedCount: pushResult.pushedCount,
      pulledCount: pullResult.pulledCount,
      conflictCount: pushResult.conflictCount + pullResult.conflictCount,
      failedCount: pushResult.failedCount + pullResult.failedCount,
    );
  }
}

class _SyncEntity {
  final String name;
  final String? collectionId;
  final BaseRepository repo;

  _SyncEntity(this.name, this.collectionId, this.repo);
}
