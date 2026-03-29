// lib/services/appwrite_delta_sync.dart

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:appwrite/appwrite.dart' as appwrite;
import 'package:appwrite/models.dart' as models;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
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
  static const _prefsPushedCountKey = 'appwrite_delta_pushed_count';
  static const _prefsPulledCountKey = 'appwrite_delta_pulled_count';
  static const _prefsFailedCountKey = 'appwrite_delta_failed_count';
  
  /// حجم الدفعة الواحدة في PULL
  static const int _pullBatchSize = 100;
  /// الحد الأقصى للسجلات في PULL الواحد (0 = بدون حد)
  static const int _maxPullRecords = 500;

  /// ✅ حقل التimestamp المستخدم للسحب حسب الجدول
  /// بعض الجداول تحتوي على syncTimestamp، والبعض الآخر يستخدم lastModified
  static const _timestampFieldPerEntity = {
    // الجداول التي تحتوي على syncTimestamp
    'employees': 'syncTimestamp',
    // باقي الجداول تستخدم lastModified
    'rooms': 'lastModified',
    'bookings': 'lastModified',
    'payments': 'lastModified',
    'expenses': 'lastModified',
    'debts': 'lastModified',
    'booking_notes': 'lastModified',
    'booking_nights': 'lastModified',
    'cash_transactions': 'lastModified',
    'salary_cycles': 'lastModified',
    'salary_payments': 'lastModified',
    'salary_withdrawals': 'lastModified',
    'shift_notes': 'lastModified',
    'booking_price_adjustments': 'lastModified',
  };

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
      
      // ✅ تشخيص: طباعة lastPushTs
      final lastPushTs = await _getLastDeltaPushTimestamp();
      _logger.info('⏱️ lastPushTs: $lastPushTs (${lastPushTs > 0 ? DateTime.fromMillisecondsSinceEpoch(lastPushTs * 1000) : "never"})', tag: 'DELTA_SYNC');
      
      // ✅ تشخيص: عدد السجلات في المرآة
      final mirrorCount = await _getMirrorCount();
      _logger.info('📊 عدد السجلات في المرآة: $mirrorCount', tag: 'DELTA_SYNC');
      
      // ❌ تم إزالة _ensureMirrorIntegrity() لأنها تُعيد بناء المرآة من البيانات الحالية
      // مما يجعل rowHash متطابقاً ويمنع اكتشاف التغييرات!
      // await _ensureMirrorIntegrity();
      
      // ✅ استخدام Field-Level Sync عبر DeltaSyncService
      // DeltaSyncService يحسب الفروقات من قاعدة البيانات والمرآة
      final computation = await _deltaSyncService!.compute(since: lastPushTs);
      
      // ✅ تشخيص: عدد السجلات المحلية
      final localCounts = await _getLocalRecordCounts();
      _logger.info('📊 السجلات المحلية: $localCounts', tag: 'DELTA_SYNC');

      if (computation.changes.isEmpty) {
        _logger.info('✅ لا توجد تغييرات للمزامنة', tag: 'DELTA_SYNC');
        return AppwriteDeltaSyncResult(
            success: true, message: 'لا توجد تغييرات', pushedCount: 0);
      }

      // ✅ طباعة تفصيلية للتشخيص
      final entityCounts = <String, int>{};
      for (final change in computation.changes) {
        entityCounts[change.entity] = (entityCounts[change.entity] ?? 0) + 1;
      }
      _logger.info('📊 تم اكتشاف ${computation.changes.length} تغيير: $entityCounts', tag: 'DELTA_SYNC');

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

      // ✅ الترتيب الصحيح مع حماية إضافية
      // القاعدة الذهبية: لا تمسح Outbox إلا إذا كنت متأكداً 100% من أن البيانات آمنة
      if (successfulChanges.isNotEmpty) {
        try {
          // 1️⃣ تحديث المرآة أولاً (حفظ الحالة الجديدة للمقارنة في المزامنة القادمة)
          await _persistSuccessfulChanges(computation, successfulChanges);
          
          // 2️⃣ تحديث timestamp (منع إعادة إرسال نفس البيانات)
          await _updateLastDeltaPushTimestamp();
          
          // 3️⃣ مسح Outbox فقط بعد نجاح الخطوتين السابقتين
          await _cleanupOutboxAfterSync(successfulChanges);
          
          _logger.info(
            '✅ تم اكتمال المزامنة المحلية: ${successfulChanges.length} سجل',
            tag: 'DELTA_SYNC',
          );
        } catch (e) {
          // ❌ فشل في الخطوات المحلية - Outbox يبقى سليماً للمحاولة مرة أخرى
          _logger.error(
            '❌ فشل في الخطوات المحلية بعد نجاح الشبكة: $e\n'
            '⚠️ Outbox لم يُمسح - ستتم إعادة المحاولة تلقائياً',
            tag: 'DELTA_SYNC',
          );
          // نعيد نتيجة فشل جزئي
          return AppwriteDeltaSyncResult(
            success: false,
            message: 'تم الرفع لكن فشل التحديث المحلي: $e',
            pushedCount: successfulChanges.length,
            failedCount: failedChanges.length + 1, // +1 للفشل المحلي
          );
        }
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
    // ✅ عدم الكتابة فوق القيم الموجودة إذا كانت أحدث
    payload['deviceId'] ??= _deviceId;
    payload['syncTimestamp'] = Time.nowEpoch(); // هذا يجب أن يكون دائماً جديداً

    // ✅ استخدام Field-Level payload إذا كان متاحاً
    Map<String, dynamic> sanitizedPayload;
    if (change.fieldChanges != null && change.fieldChanges!.isNotEmpty) {
      // استخدام الحقول المتغيرة فقط
      sanitizedPayload = _sanitizePayload(payload, collectionEntity: change.entity);
      
      // ✅ إصلاح: لا تُرسل حقول metadata (_version, _timestamp, _device) إلى Appwrite
      // لأنها ليست معرّفة في Appwrite schema وستُسبب document_invalid_structure
      // المتبقي metadata محفوظ في change.fieldMetadata / change.toMap() للاستخدام المحلي فقط
      
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
        } on appwrite.AppwriteException catch (e) {
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
      
      // ✅ إذا كان أول سحب (lastPullEpoch == 0)، نجلب جميع السجلات
      // وليس آخر 24 ساعة فقط
      final sinceEpoch = lastPullEpoch > 0 
          ? lastPullEpoch 
          : 0; // جلب الكل من البداية

      final isFirstPull = lastPullEpoch == 0;
      _logger.info(
        '⏱️ سحب التغييرات منذ: $sinceEpoch (epoch) ${isFirstPull ? "- أول سحب (جلب الكل)" : ""}',
        tag: 'DELTA_SYNC',
      );

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

        // ✅ الترتيب الصحيح: إعادة بناء المرآة قبل إعادة تفعيل Foreign Keys
        if (totalPulled > 0) {
          _logger.info('🔄 إعادة بناء المرآة...', tag: 'DELTA_SYNC');
          await _deltaSyncService!.rebuildMirror();
          
          // ✅ تحديث occupancy بعد إعادة بناء المرآة
          await RoomsRepository(_database!).refreshAllRoomOccupancy(originIsServer: true);
        }

        await _updateLastDeltaPullTimestamp();

      } finally {
        await _database!.customStatement('PRAGMA foreign_keys = ON');
        _logger.info('🔓 تم إعادة تفعيل FOREIGN KEYS', tag: 'DELTA_SYNC');
      }

      final message = failedEntities.isEmpty
          ? 'تم سحب $totalPulled تغيير حديث من Appwrite'
          : 'تم سحب $totalPulled تغيير، فشل في: ${failedEntities.join(', ')}';

      _logger.info('✅ $message', tag: 'DELTA_SYNC');
      
      // تحديث الإحصائيات المحفوظة للسحب
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsPulledCountKey, (prefs.getInt(_prefsPulledCountKey) ?? 0) + totalPulled);

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

    // ✅ تحديد حقل التimestamp للسحب حسب الجدول
    // بعض الجداول لا تحتوي على syncTimestamp، نستخدم lastModified بدلاً منها
    final timestampField = _timestampFieldPerEntity[entity.name] ?? 'lastModified';
    
    _logger.info(
      '📥 سحب ${entity.name} باستخدام $timestampField > $sinceEpoch...',
      tag: 'DELTA_SYNC',
    );

    // ✅ جلب السجلات على دفعات
    do {
      totalBatches++;
      batchCount = 0;

      try {
        final queries = <String>[
          appwrite.Query.greaterThan(timestampField, sinceEpoch),
          appwrite.Query.orderDesc(timestampField),
          appwrite.Query.limit(_pullBatchSize),
          appwrite.Query.offset(offset),
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
            
            // ✅ التحقق من الحذف في Appwrite - حذف محلي بدلاً من upsert
            final isDeletedInRemote = remoteData['deletedAt'] != null || 
                                      remoteData['isDeleted'] == true ||
                                      remoteData['deletedAtEpoch'] != null;
            
            if (isDeletedInRemote) {
              try {
                await entity.repo.deleteByUuid(localUuid);
                _logger.debug('🗑️ حذف محلي للسجل المحذوف في Appwrite: $localUuid', tag: 'DELTA_SYNC');
              } catch (e) {
                _logger.warning('فشل حذف ${entity.name}/$localUuid: $e', tag: 'DELTA_SYNC');
              }
              batchCount++;
              totalSuccessCount++;
              continue;
            }
            
            final localData = await entity.repo.getJsonByUuid(localUuid);
            
            if (localData != null) {
              final localTs = localData['lastModified'] ?? localData['updated_at'] ?? 0;
              // ✅ استخدام الحقل المناسب حسب الجدول
              final remoteTs = remoteData[timestampField] ?? remoteData['lastModified'] ?? remoteData['updated_at'] ?? 0;
              
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

      } on appwrite.AppwriteException catch (e) {
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

  // ==================== MIRROR INTEGRITY ====================

  /// ✅ التحقق من صحة المرآة وإعادة بنائها إذا لزم الأمر
  /// هذا يضمن أن Delta Sync يكتشف جميع التغييرات بشكل صحيح
  Future<void> _ensureMirrorIntegrity() async {
    try {
      // الجداول الحرجة التي يجب التحقق منها
      const criticalTables = [
        'salary_withdrawals',
        'expenses',
        'payments',
        'bookings',
      ];

      for (final tableName in criticalTables) {
        final mirrorCount = await _getMirrorCount(tableName);
        final dbCount = await _getDbCount(tableName);

        // إذا كانت المرآة فارغة أو أقل من قاعدة البيانات
        if (mirrorCount == 0 && dbCount > 0) {
          _logger.warning(
            '⚠️ المرآة فارغة لـ $tableName ($dbCount سجل) - إعادة بناء...',
            tag: 'DELTA_SYNC',
          );
          await _rebuildTableMirror(tableName);
        } else if (mirrorCount < dbCount * 0.9) {
          // إذا كانت المرآة ناقصة بأكثر من 10%
          _logger.warning(
            '⚠️ المرآة ناقصة لـ $tableName (مرآة: $mirrorCount, قاعدة: $dbCount) - إعادة بناء...',
            tag: 'DELTA_SYNC',
          );
          await _rebuildTableMirror(tableName);
        }
      }
    } catch (e) {
      _logger.error('❌ خطأ في التحقق من المرآة: $e', tag: 'DELTA_SYNC');
    }
  }

  /// الحصول على عدد سجلات المرآة لجدول معين
  Future<int> _getMirrorCount([String? tableName]) async {
    try {
      if (tableName != null) {
        final result = await _database!.customSelect(
          'SELECT COUNT(*) as count FROM sync_mirror WHERE sync_entity_name = ?',
          variables: [Variable.withString(tableName)],
        ).getSingle();
        return result.read<int>('count');
      } else {
        // إجمالي جميع السجلات في المرآة
        final result = await _database!.customSelect(
          'SELECT COUNT(*) as count FROM sync_mirror',
        ).getSingle();
        return result.read<int>('count');
      }
    } catch (e) {
      return 0;
    }
  }

  /// الحصول على عدد سجلات الجداول المحلية
  Future<Map<String, int>> _getLocalRecordCounts() async {
    try {
      final counts = <String, int>{};
      final tables = ['rooms', 'bookings', 'employees', 'expenses', 'payments', 'debts', 'salary_withdrawals'];
      
      for (final table in tables) {
        try {
          final result = await _database!.customSelect(
            'SELECT COUNT(*) as count FROM $table WHERE deleted_at IS NULL',
          ).getSingle();
          counts[table] = result.read<int>('count');
        } catch (_) {
          counts[table] = 0;
        }
      }
      return counts;
    } catch (e) {
      return {};
    }
  }

  /// الحصول على عدد سجلات جدول معين
  Future<int> _getDbCount(String tableName) async {
    try {
      final result = await _database!.customSelect(
        'SELECT COUNT(*) as count FROM $tableName WHERE deleted_at IS NULL',
      ).getSingle();
      return result.read<int>('count');
    } catch (e) {
      return 0;
    }
  }

  /// إعادة بناء مرآة جدول معين
  Future<void> _rebuildTableMirror(String tableName) async {
    try {
      // مسح المرآة القديمة
      await _database!.customStatement(
        'DELETE FROM sync_mirror WHERE sync_entity_name = ?',
        [tableName],
      );

      final now = Time.nowEpoch();
      int count = 0;

      // بناء المرآة حسب نوع الجدول
      switch (tableName) {
        case 'salary_withdrawals':
          count = await _rebuildSalaryWithdrawalsMirror(now);
          break;
        case 'expenses':
          count = await _rebuildExpensesMirror(now);
          break;
        case 'payments':
          count = await _rebuildPaymentsMirror(now);
          break;
        case 'bookings':
          count = await _rebuildBookingsMirror(now);
          break;
      }

      _logger.info('✅ تم إعادة بناء مرآة $tableName: $count سجل', tag: 'DELTA_SYNC');
    } catch (e) {
      _logger.error('❌ فشل إعادة بناء مرآة $tableName: $e', tag: 'DELTA_SYNC');
    }
  }

  /// إعادة بناء مرآة salary_withdrawals
  Future<int> _rebuildSalaryWithdrawalsMirror(int now) async {
    final records = await _database!.select(_database!.salaryWithdrawals).get();
    int count = 0;

    for (final record in records) {
      final payload = _adapterRegistry!.salaryWithdrawals.adapter.toJson(
        record,
        src: Source.appwrite,
      );
      final rowHash = _computeHash(payload);

      await _database!.customStatement(
        '''INSERT INTO sync_mirror 
           (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) 
           VALUES (?, ?, ?, ?, ?)''',
        ['salary_withdrawals', record.localUuid, rowHash, jsonEncode(payload), now],
      );
      count++;
    }

    return count;
  }

  /// إعادة بناء مرآة expenses
  Future<int> _rebuildExpensesMirror(int now) async {
    final records = await _database!.select(_database!.expenses).get();
    int count = 0;

    for (final record in records) {
      final payload = _adapterRegistry!.expenses.adapter.toJson(record, src: Source.appwrite);
      final rowHash = _computeHash(payload);

      await _database!.customStatement(
        '''INSERT INTO sync_mirror 
           (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) 
           VALUES (?, ?, ?, ?, ?)''',
        ['expenses', record.localUuid, rowHash, jsonEncode(payload), now],
      );
      count++;
    }

    return count;
  }

  /// إعادة بناء مرآة payments
  Future<int> _rebuildPaymentsMirror(int now) async {
    final records = await _database!.select(_database!.payments).get();
    int count = 0;

    for (final record in records) {
      final payload = _adapterRegistry!.payments.adapter.toJson(record, src: Source.appwrite);
      final rowHash = _computeHash(payload);

      await _database!.customStatement(
        '''INSERT INTO sync_mirror 
           (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) 
           VALUES (?, ?, ?, ?, ?)''',
        ['payments', record.localUuid, rowHash, jsonEncode(payload), now],
      );
      count++;
    }

    return count;
  }

  /// إعادة بناء مرآة bookings
  Future<int> _rebuildBookingsMirror(int now) async {
    final records = await _database!.select(_database!.bookings).get();
    int count = 0;

    for (final record in records) {
      final payload = _adapterRegistry!.bookings.adapter.toJson(record, src: Source.appwrite);
      final rowHash = _computeHash(payload);

      await _database!.customStatement(
        '''INSERT INTO sync_mirror 
           (sync_entity_name, local_uuid, row_hash, payload, last_seen_at) 
           VALUES (?, ?, ?, ?, ?)''',
        ['bookings', record.localUuid, rowHash, jsonEncode(payload), now],
      );
      count++;
    }

    return count;
  }

  /// حساب hash للبيانات
  String _computeHash(Map<String, dynamic> payload) {
    final sorted = _sortMapForHash(payload);
    final jsonStr = jsonEncode(sorted);
    return sha1.convert(utf8.encode(jsonStr)).toString();
  }

  /// ترتيب Map لحساب hash متسق
  Map<String, dynamic> _sortMapForHash(Map<String, dynamic> source) {
    final entries = source.entries.map((entry) {
      final value = entry.value;
      dynamic normalized;
      if (value is Map<String, dynamic>) {
        normalized = _sortMapForHash(value);
      } else if (value is List) {
        normalized = value.map((item) {
          if (item is Map<String, dynamic>) return _sortMapForHash(item);
          return item;
        }).toList();
      } else {
        normalized = value;
      }
      return MapEntry(entry.key, normalized);
    }).toList()..sort((a, b) => a.key.compareTo(b.key));
    return Map<String, dynamic>.fromEntries(entries);
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
    'payments': ['amount', 'paymentDate', 'paymentMethod', 'revenueType'], // sync_version و sync_vector_clock تُعالج في _syncFieldsPerEntity
    'debts': ['guestName', 'checkinDate', 'totalAmount', 'paidAmount', 'localUuid', 'createdAt', 'updatedAt', 'lastModified'],
    'expenses': ['expenseType', 'description', 'amount', 'date', 'localUuid', 'createdAt', 'updatedAt', 'lastModified'],
    'rooms': ['roomNumber', 'type', 'status', 'price', 'localUuid', 'createdAt', 'updatedAt', 'lastModified'],
  };

  /// حقول sync مطلوبة فقط لمجموعات محددة (ليست كل المجموعات)
  /// ملاحظة: debts لا تحتوي على حقول sync في Appwrite - تمت الإزالة
  static const _syncFieldsPerEntity = {
    'payments': ['sync_version', 'sync_vector_clock'],
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
            case 'guestName':
              // اسم الضيف مطلوب للديون
              sanitized['guestName'] = sanitized['guestName'] ?? 'Unknown Guest';
              break;
            case 'checkinDate':
              // تاريخ تسجيل الدخول مطلوب للديون
              sanitized['checkinDate'] = sanitized['checkinDate'] ?? 
                  sanitized['createdAtIso'] ?? DateTime.now().toIso8601String();
              break;
            case 'totalAmount':
              // المبلغ الإجمالي مطلوب - افتراضي 0
              sanitized['totalAmount'] = sanitized['totalAmount'] ?? 0.0;
              break;
            case 'paidAmount':
              // المبلغ المدفوع مطلوب - افتراضي 0
              sanitized['paidAmount'] = sanitized['paidAmount'] ?? 0.0;
              break;
            case 'localUuid':
              // المعرف المحلي مطلوب
              if (sanitized['localUuid'] == null) {
                _logger.warning(
                  '⚠️ $collectionEntity: localUuid مفقود، سيتم تخطي هذا السجل',
                  tag: 'DELTA_SYNC',
                );
                return {};
              }
              break;
            case 'expenseType':
              // نوع المصروف مطلوب
              sanitized['expenseType'] = sanitized['expenseType'] ?? 'general';
              break;
            case 'description':
              // الوصف مطلوب للمصروفات
              sanitized['description'] = sanitized['description'] ?? 'No description';
              break;
            case 'roomNumber':
              // رقم الغرفة مطلوب
              sanitized['roomNumber'] = sanitized['roomNumber'] ?? 'Unknown';
              break;
            case 'type':
              // نوع الغرفة مطلوب
              sanitized['type'] = sanitized['type'] ?? sanitized['roomType'] ?? 'standard';
              break;
            case 'status':
              // حالة الغرفة مطلوبة
              sanitized['status'] = sanitized['status'] ?? 'available';
              break;
            case 'price':
              // سعر الغرفة مطلوب - double
              sanitized['price'] = (sanitized['price'] ?? sanitized['basePrice'] ?? 0.0).toDouble();
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
  /// ملاحظة: للنص العربي، كل حرف = 2 بايت تقريباً في UTF-8
  void _truncateStringFields(Map<String, dynamic> data) {
    // حقول يجب تقليصها (القيمة هي عدد الرموز، وليس البايتات)
    final shortStringFields = {
      'stayDurationIso': 50,
      'roomNumber': 20,
      'guestName': 50, // ✅ تقليل إلى 50 رمز (100 بايت تقريباً للعربي)
      'guestPhone': 20,
      'nationality': 50,
      'status': 30,
      'paymentMethod': 30,
      'transactionType': 30,
    };

    for (final entry in shortStringFields.entries) {
      final field = entry.key;
      final maxChars = entry.value;

      if (data.containsKey(field) && data[field] is String) {
        final value = data[field] as String;
        // ✅ حساب البايتات الفعلية للنص العربي
        final bytes = utf8.encode(value);
        final maxBytes = maxChars * 2; // افتراض 2 بايت/حرف للعربي
        
        if (bytes.length > maxBytes) {
          // تقليص مع مراعاة عدم قطع الحرف في المنتصف
          var truncated = value;
          while (utf8.encode(truncated).length > maxBytes && truncated.isNotEmpty) {
            truncated = truncated.substring(0, truncated.length - 1);
          }
          data[field] = truncated;
          _logger.debug(
            '✂️ تم تقليص $field من ${bytes.length} بايت إلى ${utf8.encode(truncated).length} بايت',
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

  /// ✅ إعادة تعيين timestamp للسحب - يُستخدم قبل السحب الشامل
  Future<void> resetPullTimestamp() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_prefsLastDeltaPullKey);
    _logger.info('🔄 تم إعادة تعيين timestamp للسحب', tag: 'DELTA_SYNC');
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
      
      // ✅ تنظيف إضافي: مسح جميع السجلات المعلقة القديمة (أكثر من ساعة)
      // هذا يضمن عدم تراكم سجلات قديمة بسبب مشاكل في الاكتشاف
      final oldRecordsDeleted = await outboxDao.cleanupOldPendingRecords(
        maxAgeHours: 1,
      );
      totalDeleted += oldRecordsDeleted;
      
      _logger.info(
        '🧹 تم مسح $totalDeleted سجل من Outbox (${successfulChanges.length} تغيير + $oldRecordsDeleted قديم)',
        tag: 'DELTA_SYNC',
      );
    } catch (e) {
      _logger.warning('⚠️ خطأ في تنظيف Outbox: $e', tag: 'DELTA_SYNC');
    }
  }

  Future<Map<String, dynamic>> getStatus() async {
    final lastPush = await _getLastDeltaPushTimestamp();
    final lastPull = await _getLastDeltaPullTimestamp();
    final prefs = await SharedPreferences.getInstance();
    
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
      'pushed_count': prefs.getInt(_prefsPushedCountKey) ?? 0,
      'pulled_count': prefs.getInt(_prefsPulledCountKey) ?? 0,
      'failed_count': prefs.getInt(_prefsFailedCountKey) ?? 0,
      'outbox': {
        'pending': outboxStats.pending,
        'processing': outboxStats.processing,
        'failed': outboxStats.failed,
        'conflicts': outboxStats.conflicts,
        'total': outboxStats.total,
      },
    };
  }
  
  /// مزامنة كاملة (Pull ثم Push للسلامة)
  /// الترتيب الصحيح: Pull أولاً للحصول على أحدث بيانات، ثم Push
  Future<AppwriteDeltaSyncResult> fullSync() async {
    _logger.info('🔄 بدء مزامنة كاملة...', tag: 'DELTA_SYNC');
    
    // 1️⃣ Pull أولاً للحصول على أحدث بيانات من الخادم
    final pullResult = await pullDeltaChanges();
    
    // 2️⃣ Push بعد الـ Pull (للتأكد من عدم فقدان بيانات محلية)
    final pushResult = await pushDeltaChanges();
    
    // 3️⃣ Pull نهائي إذا كان هناك push ناجح (للحصول على التغييرات المتزامنة)
    if (pushResult.pushedCount > 0 && pushResult.success) {
      final finalPull = await pullDeltaChanges();
      return AppwriteDeltaSyncResult(
        success: pushResult.success && pullResult.success && finalPull.success,
        message: 'Pull 1: ${pullResult.message}\n'
                'Push: ${pushResult.message}\n'
                'Pull 2: ${finalPull.message}',
        pushedCount: pushResult.pushedCount,
        pulledCount: pullResult.pulledCount + finalPull.pulledCount,
        conflictCount: pushResult.conflictCount + pullResult.conflictCount + finalPull.conflictCount,
        failedCount: pushResult.failedCount + pullResult.failedCount + finalPull.failedCount,
      );
    }
    
    return AppwriteDeltaSyncResult(
      success: pushResult.success && pullResult.success,
      message: 'Pull: ${pullResult.message}\nPush: ${pushResult.message}',
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
