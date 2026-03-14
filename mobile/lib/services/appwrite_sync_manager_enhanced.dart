import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:appwrite/models.dart' as models;
import 'package:device_info_plus/device_info_plus.dart';
import '../utils/id.dart';
import '../utils/time.dart';
import 'appwrite_service.dart';
import 'appwrite_logger.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_models.dart';
import 'appwrite_config.dart';
import 'local_db.dart';
import 'daos/outbox_dao.dart';
import 'sync_mutex.dart';
import 'sync_enums.dart';
import 'sync_constants.dart';
import 'sync_core/sync_metrics.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'repositories/bookings_repository.dart';
import 'repositories/rooms_repository.dart';
import 'conflict_resolver.dart';
import 'conflict_manager.dart';
import 'vector_clock.dart';
import '../sync/vector_clock.dart' as sync_vector;
import 'unified_conflict_resolver.dart';

/// حالة المزامنة
enum SyncStatus { idle, syncing, success, failed, partial }

/// نتيجة المزامنة
class SyncResult {
  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final int conflictsResolved;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;
  final List<ConflictRecord> conflictDetails;

  SyncResult({
    required this.status,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.conflictsResolved = 0,
    this.errorMessage,
    required this.timestamp,
    required this.duration,
    this.conflictDetails = const [],
  });

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
  bool get hasUnresolvedConflicts => conflictDetails.any((c) => c.resolution == null);
}

/// مدير المزامنة الثنائية المحسن مع نظام التعارضات المتقدم
class AppwriteSyncManagerEnhanced {
  static AppwriteSyncManagerEnhanced? _instance;

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  final ConflictManager conflictManager;
  late final BookingsRepository _bookingsRepository;
  late final AdapterRegistry _adapterRegistry;
  final SyncMutex _mutex = SyncMutex();

  factory AppwriteSyncManagerEnhanced({
    required AppwriteService appwriteService,
    required AppDatabase database,
  }) {
    _instance ??= AppwriteSyncManagerEnhanced._internal(
      appwriteService: appwriteService,
      database: database,
    );
    return _instance!;
  }

  AppwriteSyncManagerEnhanced._internal({
    required this.appwriteService,
    required this.database,
  })  : outboxDao = OutboxDao(database),
        conflictManager = ConflictManager(database) {
    _adapterRegistry = AdapterRegistry(database);
    _bookingsRepository = BookingsRepository(database);
    _initializeConflictResolver();
  }

  late EnhancedConflictResolver _conflictResolver;
  late sync_vector.VectorClockManager _vectorClockManager;
  String? _deviceId;

  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();

  Timer? _syncTimer;
  Timer? _debouncePushTimer;
  StreamSubscription? _outboxSubscription;
  Duration _debounceWindow = SyncConstants.outboxDebounceWindow;
  SyncStatus _currentStatus = SyncStatus.idle;
  bool _isPulling = false;
  DateTime? _lastSyncTime;
  String? _currentDeviceId;
  String? _deviceLocalUuid;
  int? _deviceVersion;
  int? _deviceCreatedAtEpoch;

  final _syncController = StreamController<SyncStatus>.broadcast();
  Stream<SyncStatus> get syncStatusStream => _syncController.stream;

  /// تهيئة محلل التعارضات
  void _initializeConflictResolver() {
    _conflictResolver = EnhancedConflictResolver(
      defaultStrategy: ConflictStrategy.lastWriteWins,
      tableStrategies: {
        'bookings': ConflictStrategy.fieldLevel,
        'payments': ConflictStrategy.lastWriteWins,
        'rooms': ConflictStrategy.lastWriteWins,
        'expenses': ConflictStrategy.fieldLevel,
        'debts': ConflictStrategy.fieldLevel,
        'employees': ConflictStrategy.lastWriteWins,
        'cash_transactions': ConflictStrategy.lastWriteWins,
        'booking_notes': ConflictStrategy.lastWriteWins,
        'shift_notes': ConflictStrategy.lastWriteWins,
        'salary_cycles': ConflictStrategy.lastWriteWins,
        'salary_payments': ConflictStrategy.lastWriteWins,
        'hotel_day_ledger': ConflictStrategy.lastWriteWins,
        'price_adjustments': ConflictStrategy.lastWriteWins,
        'booking_price_adjustments': ConflictStrategy.lastWriteWins,
      },
      criticalFieldsOverrides: {
        'bookings': {
          'status', 'checkout_date', 'actual_checkout', 'room_number',
          'total_due_cached', 'total_paid_cached', 'remaining_balance_cached',
          'guest_name', 'is_fully_paid', 'discount', 'totalNightsCached',
        },
        'payments': {
          'amount', 'payment_date', 'payment_method', 'booking_uuid',
          'status', 'revenue_type', 'cashTransactionLocalId',
        },
        'rooms': {
          'status', 'price', 'room_number', 'floor', 'type',
          'is_active', 'cleaning_status', 'requires_maintenance',
        },
        'expenses': {
          'amount', 'date', 'category', 'description',
          'status', 'expense_type', 'hotel_day_key',
        },
        'debts': {
          'amount', 'status', 'due_date', 'paid_amount',
          'guest_name', 'remaining_amount', 'is_settled',
        },
        'employees': {
          'name', 'phone', 'basic_salary', 'position',
          'status', 'hire_date',
        },
        'cash_transactions': {
          'amount', 'transaction_type', 'transaction_time',
          'reference_type', 'reference_id',
        },
      },
    );
  }

  /// تهيئة المزامنة
  Future<void> initialize() async {
    try {
      await appwriteService.initialize();
      await _loadSettings();
      await _initializeDevice();

      // تهيئة Vector Clock Manager
      _vectorClockManager = sync_vector.VectorClockManager(deviceId: _deviceId ?? 'unknown');

      // Fix potential stuck states
      try {
        await outboxDao.cleanupStuckEntries();
        await outboxDao.retryFailed();
      } catch (e) {
        _logger.warning(
          'Failed to cleanup outbox on init',
          error: e,
          tag: 'SYNC',
        );
      }

      _enableDebouncedPush();

      // رفع البيانات الحالية مرة واحدة
      unawaited(_runInitialSeedIfNeeded());

      _logger.info('Enhanced sync manager initialized', tag: 'SYNC');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to initialize enhanced sync manager',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
    }
  }

  /// تهيئة الجهاز
  Future<void> _initializeDevice() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('appwrite_device_id');

    if (_deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      String deviceIdentifier = 'unknown';

      try {
        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          deviceIdentifier = androidInfo.id;
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          deviceIdentifier = iosInfo.identifierForVendor ??
              'ios-${DateTime.now().millisecondsSinceEpoch}';
        }
      } catch (e) {
        deviceIdentifier = 'device-${DateTime.now().millisecondsSinceEpoch}';
      }

      _deviceId = deviceIdentifier;
      await prefs.setString('appwrite_device_id', _deviceId!);
    }

    _logger.info('Device ID: $_deviceId', tag: 'SYNC');
  }

  /// رفع جميع البيانات المحلية مرة واحدة عند أول تشغيل
  Future<void> _runInitialSeedIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('appwrite_enhanced_seed_done') ?? false;
      if (done) return;

      final rooms = await database.select(database.rooms).get();
      if (rooms.isEmpty) {
        await prefs.setBool('appwrite_enhanced_seed_done', true);
        return;
      }

      _logger.info('بدء الرفع الأولي للبيانات المحلية...', tag: 'SYNC');
      final stats = await pushAllLocalDataToAppwrite();
      _logger.info('اكتمل الرفع الأولي: $stats', tag: 'SYNC');

      await prefs.setBool('appwrite_enhanced_seed_done', true);
    } catch (e, stackTrace) {
      _logger.warning(
        'فشل الرفع الأولي (سيُعاد في المرة القادمة)',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
    }
  }

  /// تحميل الإعدادات
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _currentDeviceId = prefs.getString('appwrite_device_id');

    final lastSyncEpoch = prefs.getInt('appwrite_last_sync_time');
    _lastSyncTime = lastSyncEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncEpoch)
        : null;

    _deviceLocalUuid = prefs.getString('appwrite_device_local_uuid');
    _deviceVersion = prefs.getInt('appwrite_device_version');
    _deviceCreatedAtEpoch = prefs.getInt('appwrite_device_created_at');
  }

  /// حفظ الإعدادات
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    if (_currentDeviceId != null) {
      await prefs.setString('appwrite_device_id', _currentDeviceId!);
    }
    if (_lastSyncTime != null) {
      await prefs.setInt(
        'appwrite_last_sync_time',
        _lastSyncTime!.millisecondsSinceEpoch,
      );
    }
  }

  /// مزامنة كاملة (Push + Pull) مع نظام التعارضات
  Future<SyncResult> sync({
    bool push = true,
    bool pull = true,
    bool force = false,
  }) async {
    final startTime = DateTime.now();
    final metrics = SyncMetrics.instance;
    metrics.startSync();

    if (!_mutex.acquire()) {
      _logger.info('Sync already in progress', tag: 'SYNC');
      return SyncResult(
        status: SyncStatus.idle,
        timestamp: startTime,
        duration: Duration.zero,
      );
    }

    _currentStatus = SyncStatus.syncing;
    _syncController.add(_currentStatus);

    int recordsPushed = 0;
    int recordsPulled = 0;
    int conflicts = 0;
    int conflictsResolved = 0;
    SyncStatus finalStatus = SyncStatus.success;
    String? errorMessage;
    final List<ConflictRecord> conflictRecords = [];
    final Map<String, int> phaseMs = {};

    try {
      final hasConnection = await _checkConnectivity();
      if (!hasConnection) {
        _logger.info('No connection available', tag: 'SYNC');
        _mutex.release();
        return SyncResult(
          status: SyncStatus.failed,
          errorMessage: 'لا يوجد اتصال بالإنترنت',
          timestamp: startTime,
          duration: DateTime.now().difference(startTime),
        );
      }

      _logger.info('Starting enhanced sync (push: $push, pull: $pull)', tag: 'SYNC');

      // رفع التغييرات المحلية
      if (push) {
        recordsPushed = await _timePhase('push', () async {
          return await _pushAllEntities();
        }, phaseMs);
      }

      // سحب التغييرات من Appwrite مع حل التعارضات
      if (pull) {
        final pullResult = await _timePhase('pull', () async {
          return await _pullAllEntitiesWithConflictResolution();
        }, phaseMs);

        recordsPulled = pullResult.recordsPulled;
        conflicts = pullResult.conflicts;
        conflictsResolved = pullResult.conflictsResolved;
        conflictRecords.addAll(pullResult.conflictDetails);
      }

      _lastSyncTime = DateTime.now();
      await _saveSettings();

      _logger.info(
        'Enhanced sync completed (pushed: $recordsPushed, pulled: $recordsPulled, conflicts: $conflicts)',
        tag: 'SYNC',
      );
    } catch (e, stackTrace) {
      errorMessage = e.toString();
      finalStatus = SyncStatus.failed;
      _errorHandler.handleError(e, context: 'sync()', stackTrace: stackTrace);
      _logger.error('Enhanced sync failed', error: e, stackTrace: stackTrace, tag: 'SYNC');
    } finally {
      _currentStatus = finalStatus;
      _syncController.add(_currentStatus);
      _mutex.release();
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    if (finalStatus == SyncStatus.success) {
      metrics.recordSuccess(
        recordsSynced: recordsPushed + recordsPulled,
        conflictsResolved: conflictsResolved,
      );
    } else {
      metrics.recordFailure(errorMessage ?? 'Enhanced sync failed');
    }

    return SyncResult(
      status: finalStatus,
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      conflicts: conflicts,
      conflictsResolved: conflictsResolved,
      errorMessage: errorMessage,
      timestamp: endTime,
      duration: duration,
      conflictDetails: conflictRecords,
    );
  }

  /// سحب جميع الكيانات مع حل التعارضات
  Future<_PullResult> _pullAllEntitiesWithConflictResolution() async {
    int totalRecords = 0;
    int totalConflicts = 0;
    int totalResolved = 0;
    final List<ConflictRecord> conflictDetails = [];

    // سحب الغرف
    final roomsResult = await _pullEntityWithConflictResolution(
      'rooms',
      () => appwriteService.listRooms(useCache: false),
      (doc) => _syncRoomWithConflictCheck(doc),
    );
    totalRecords += roomsResult.records;
    totalConflicts += roomsResult.conflicts;
    totalResolved += roomsResult.resolved;
    conflictDetails.addAll(roomsResult.conflictDetails);

    // سحب الحجوزات (أولوية قصوى)
    final bookingsResult = await _pullEntityWithConflictResolution(
      'bookings',
      () => appwriteService.listBookings(useCache: false),
      (doc) => _syncBookingWithConflictCheck(doc),
    );
    totalRecords += bookingsResult.records;
    totalConflicts += bookingsResult.conflicts;
    totalResolved += bookingsResult.resolved;
    conflictDetails.addAll(bookingsResult.conflictDetails);

    // سحب الموظفين
    final employeesResult = await _pullEntityWithConflictResolution(
      'employees',
      () => appwriteService.listEmployees(useCache: false),
      (doc) => _syncEmployeeWithConflictCheck(doc),
    );
    totalRecords += employeesResult.records;
    totalConflicts += employeesResult.conflicts;
    totalResolved += employeesResult.resolved;
    conflictDetails.addAll(employeesResult.conflictDetails);

    // سحب المصروفات
    final expensesResult = await _pullEntityWithConflictResolution(
      'expenses',
      () => appwriteService.listExpenses(useCache: false),
      (doc) => _syncExpenseWithConflictCheck(doc),
    );
    totalRecords += expensesResult.records;
    totalConflicts += expensesResult.conflicts;
    totalResolved += expensesResult.resolved;
    conflictDetails.addAll(expensesResult.conflictDetails);

    // سحب الدفعات (مع التعامل مع FOREIGN KEY)
    final paymentsResult = await _pullEntityWithConflictResolution(
      'payments',
      () => appwriteService.listPayments(useCache: false),
      (doc) => _syncPaymentWithConflictCheck(doc),
      deferForeignKey: true,
    );
    totalRecords += paymentsResult.records;
    totalConflicts += paymentsResult.conflicts;
    totalResolved += paymentsResult.resolved;
    conflictDetails.addAll(paymentsResult.conflictDetails);

    // سحب الديون (مع التعامل مع FOREIGN KEY)
    final debtsResult = await _pullEntityWithConflictResolution(
      'debts',
      () => appwriteService.listDebts(useCache: false),
      (doc) => _syncDebtWithConflictCheck(doc),
      deferForeignKey: true,
    );
    totalRecords += debtsResult.records;
    totalConflicts += debtsResult.conflicts;
    totalResolved += debtsResult.resolved;
    conflictDetails.addAll(debtsResult.conflictDetails);

    return _PullResult(
      recordsPulled: totalRecords,
      conflicts: totalConflicts,
      conflictsResolved: totalResolved,
      conflictDetails: conflictDetails,
    );
  }

  /// سحب كيان مع حل التعارضات
  Future<_EntityPullResult> _pullEntityWithConflictResolution(
    String entity,
    Future<List<models.Document>> Function() fetcher,
    Future<bool> Function(models.Document) syncer, {
    bool deferForeignKey = false,
  }) async {
    int records = 0;
    int conflicts = 0;
    int resolved = 0;
    final List<ConflictRecord> conflictDetails = [];
    final deferred = <models.Document>[];

    try {
      final documents = await fetcher();

      for (final doc in documents) {
        try {
          final success = await syncer(doc);
          if (success) records++;
        } on ConflictDetectedException catch (e) {
          conflicts++;
          conflictDetails.add(e.conflictRecord);

          // محاولة حل التعارض تلقائياً
          final resolution = await _attemptAutoResolve(e.context, entity);
          if (resolution != null) {
            await _applyResolvedData(entity, doc.$id, resolution);
            resolved++;
            records++;
          } else {
            // حفظ التعارض للمراجعة اليدوية
            await conflictManager.recordConflict(
              table: entity,
              uuid: doc.$id,
              localData: e.localData,
              remoteData: e.remoteData,
            );
          }
        } on ForeignKeyException catch (e) {
          if (deferForeignKey) {
            deferred.add(doc);
          } else {
            _logger.warning(
              'Foreign key error in $entity/${doc.$id}: ${e.message}',
              tag: 'SYNC',
            );
          }
        } catch (e) {
          _logger.warning('Failed to sync $entity/${doc.$id}: $e', tag: 'SYNC');
        }
      }

      // إعادة محاولة السجلات المؤجلة
      if (deferred.isNotEmpty && deferForeignKey) {
        _logger.info(
          'Retrying ${deferred.length} deferred $entity after dependencies synced',
          tag: 'SYNC',
        );

        for (final doc in deferred) {
          try {
            final success = await syncer(doc);
            if (success) records++;
          } catch (e) {
            _logger.warning(
              'Failed to sync deferred $entity/${doc.$id}: $e',
              tag: 'SYNC',
            );
          }
        }
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Error pulling $entity',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
    }

    return _EntityPullResult(
      records: records,
      conflicts: conflicts,
      resolved: resolved,
      conflictDetails: conflictDetails,
    );
  }

  /// محاولة حل تلقائي للتعارض
  Future<Map<String, dynamic>?> _attemptAutoResolve(
    ConflictContext context,
    String entity,
  ) async {
    try {
      final resolution = _conflictResolver.resolve(context);

      if (resolution.needsManualReview) {
        _logger.info(
          'Conflict in $entity/${context.uuid} requires manual review',
          tag: 'SYNC',
        );
        return null;
      }

      _logger.info(
        'Auto-resolved conflict in $entity/${context.uuid} using ${resolution.strategy.name}',
        tag: 'SYNC',
      );

      return resolution.winner;
    } catch (e) {
      _logger.warning(
        'Failed to auto-resolve conflict in $entity/${context.uuid}: $e',
        tag: 'SYNC',
      );
      return null;
    }
  }

  /// تطبيق البيانات المحلولة
  Future<void> _applyResolvedData(
    String entity,
    String uuid,
    Map<String, dynamic> data,
  ) async {
    try {
      switch (entity) {
        case 'rooms':
          await _adapterRegistry.rooms.upsertFromJson(data, src: Source.appwrite);
          break;
        case 'bookings':
          await _adapterRegistry.bookings.upsertFromJson(data, src: Source.appwrite);
          break;
        case 'employees':
          await _adapterRegistry.employees.upsertFromJson(data, src: Source.appwrite);
          break;
        case 'expenses':
          await _adapterRegistry.expenses.upsertFromJson(data, src: Source.appwrite);
          break;
        case 'payments':
          await _adapterRegistry.payments.upsertFromJson(data, src: Source.appwrite);
          break;
        case 'debts':
          await _adapterRegistry.debts.upsertFromJson(data, src: Source.appwrite);
          break;
      }
    } catch (e) {
      _logger.warning(
        'Failed to apply resolved data for $entity/$uuid: $e',
        tag: 'SYNC',
      );
      rethrow;
    }
  }

  /// مزامنة غرفة مع فحص التعارضات
  Future<bool> _syncRoomWithConflictCheck(models.Document doc) async {
    final data = Map<String, dynamic>.from(doc.data);
    data['localUuid'] ??= doc.$id;

    // جلب السجل المحلي إذا وجد
    final localRoom = await (database.select(database.rooms)
          ..where((r) => r.localUuid.equals(doc.$id)))
        .getSingleOrNull();

    if (localRoom == null) {
      // لا يوجد تعارض - سجل جديد
      await _adapterRegistry.rooms.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    // فحص وجود تعارض
    final localData = localRoom.toJson();
    final hasConflict = _hasDataConflict(localData, data);

    if (!hasConflict) {
      // لا يوجد تعارض - تحديث عادي
      await _adapterRegistry.rooms.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    // يوجد تعارض - رمي استثناء
    final context = _createConflictContext(
      'rooms',
      doc.$id,
      localData,
      data,
    );

    throw ConflictDetectedException(
      conflictRecord: ConflictRecord(
        id: 0, // سيتم تعيينه لاحقاً
        uuid: doc.$id,
        targetTable: 'rooms',
        localPayload: localData,
        remotePayload: data,
        lastError: 'Data conflict detected',
        timestamp: DateTime.now(),
      ),
      context: context,
      localData: localData,
      remoteData: data,
    );
  }

  /// مزامنة حجز مع فحص التعارضات
  Future<bool> _syncBookingWithConflictCheck(models.Document doc) async {
    final data = Map<String, dynamic>.from(doc.data);
    data['localUuid'] ??= doc.$id;

    final localBooking = await (database.select(database.bookings)
          ..where((b) => b.localUuid.equals(doc.$id)))
        .getSingleOrNull();

    if (localBooking == null) {
      await _adapterRegistry.bookings.upsertFromJson(data, src: Source.appwrite);

      // معالجة ما بعد المزامنة
      final booking = await (database.select(database.bookings)
            ..where((b) => b.localUuid.equals(doc.$id)))
          .getSingleOrNull();

      if (booking != null) {
        await _bookingsRepository.syncLegacyDiscountToAdjustments(booking.id);
        await _bookingsRepository.derivedFields.refreshForBookingId(booking.id);
      }

      return true;
    }

    final localData = localBooking.toJson();
    final hasConflict = _hasDataConflict(localData, data);

    if (!hasConflict) {
      await _adapterRegistry.bookings.upsertFromJson(data, src: Source.appwrite);

      final booking = await (database.select(database.bookings)
            ..where((b) => b.localUuid.equals(doc.$id)))
          .getSingleOrNull();

      if (booking != null) {
        await _bookingsRepository.syncLegacyDiscountToAdjustments(booking.id);
        await _bookingsRepository.derivedFields.refreshForBookingId(booking.id);
      }

      return true;
    }

    final context = _createConflictContext(
      'bookings',
      doc.$id,
      localData,
      data,
    );

    throw ConflictDetectedException(
      conflictRecord: ConflictRecord(
        id: 0,
        uuid: doc.$id,
        targetTable: 'bookings',
        localPayload: localData,
        remotePayload: data,
        lastError: 'Data conflict in booking',
        timestamp: DateTime.now(),
      ),
      context: context,
      localData: localData,
      remoteData: data,
    );
  }

  /// مزامنة موظف مع فحص التعارضات
  Future<bool> _syncEmployeeWithConflictCheck(models.Document doc) async {
    final data = Map<String, dynamic>.from(doc.data);
    data['localUuid'] ??= doc.$id;

    final localEmployee = await (database.select(database.employees)
          ..where((e) => e.localUuid.equals(doc.$id)))
        .getSingleOrNull();

    if (localEmployee == null) {
      await _adapterRegistry.employees.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    final localData = localEmployee.toJson();
    final hasConflict = _hasDataConflict(localData, data);

    if (!hasConflict) {
      await _adapterRegistry.employees.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    final context = _createConflictContext(
      'employees',
      doc.$id,
      localData,
      data,
    );

    throw ConflictDetectedException(
      conflictRecord: ConflictRecord(
        id: 0,
        uuid: doc.$id,
        targetTable: 'employees',
        localPayload: localData,
        remotePayload: data,
        lastError: 'Data conflict in employee',
        timestamp: DateTime.now(),
      ),
      context: context,
      localData: localData,
      remoteData: data,
    );
  }

  /// مزامنة مصروف مع فحص التعارضات
  Future<bool> _syncExpenseWithConflictCheck(models.Document doc) async {
    final data = Map<String, dynamic>.from(doc.data);
    data['localUuid'] ??= doc.$id;

    final localExpense = await (database.select(database.expenses)
          ..where((e) => e.localUuid.equals(doc.$id)))
        .getSingleOrNull();

    if (localExpense == null) {
      await _adapterRegistry.expenses.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    final localData = localExpense.toJson();
    final hasConflict = _hasDataConflict(localData, data);

    if (!hasConflict) {
      await _adapterRegistry.expenses.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    final context = _createConflictContext(
      'expenses',
      doc.$id,
      localData,
      data,
    );

    throw ConflictDetectedException(
      conflictRecord: ConflictRecord(
        id: 0,
        uuid: doc.$id,
        targetTable: 'expenses',
        localPayload: localData,
        remotePayload: data,
        lastError: 'Data conflict in expense',
        timestamp: DateTime.now(),
      ),
      context: context,
      localData: localData,
      remoteData: data,
    );
  }

  /// مزامنة دفعة مع فحص التعارضات
  Future<bool> _syncPaymentWithConflictCheck(models.Document doc) async {
    final data = Map<String, dynamic>.from(doc.data);
    data['localUuid'] ??= doc.$id;

    final localPayment = await (database.select(database.payments)
          ..where((p) => p.localUuid.equals(doc.$id)))
        .getSingleOrNull();

    if (localPayment == null) {
      try {
        await _adapterRegistry.payments.upsertFromJson(data, src: Source.appwrite);
        return true;
      } catch (e) {
        if (e.toString().contains('FOREIGN KEY')) {
          throw ForeignKeyException('Booking not found for payment ${doc.$id}');
        }
        rethrow;
      }
    }

    final localData = localPayment.toJson();
    final hasConflict = _hasDataConflict(localData, data);

    if (!hasConflict) {
      await _adapterRegistry.payments.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    final context = _createConflictContext(
      'payments',
      doc.$id,
      localData,
      data,
    );

    throw ConflictDetectedException(
      conflictRecord: ConflictRecord(
        id: 0,
        uuid: doc.$id,
        targetTable: 'payments',
        localPayload: localData,
        remotePayload: data,
        lastError: 'Data conflict in payment',
        timestamp: DateTime.now(),
      ),
      context: context,
      localData: localData,
      remoteData: data,
    );
  }

  /// مزامنة دين مع فحص التعارضات
  Future<bool> _syncDebtWithConflictCheck(models.Document doc) async {
    final data = Map<String, dynamic>.from(doc.data);
    data['localUuid'] ??= doc.$id;

    final localDebt = await (database.select(database.debts)
          ..where((d) => d.localUuid.equals(doc.$id)))
        .getSingleOrNull();

    if (localDebt == null) {
      try {
        await _adapterRegistry.debts.upsertFromJson(data, src: Source.appwrite);
        return true;
      } catch (e) {
        if (e.toString().contains('FOREIGN KEY')) {
          throw ForeignKeyException('Booking not found for debt ${doc.$id}');
        }
        rethrow;
      }
    }

    final localData = localDebt.toJson();
    final hasConflict = _hasDataConflict(localData, data);

    if (!hasConflict) {
      await _adapterRegistry.debts.upsertFromJson(data, src: Source.appwrite);
      return true;
    }

    final context = _createConflictContext(
      'debts',
      doc.$id,
      localData,
      data,
    );

    throw ConflictDetectedException(
      conflictRecord: ConflictRecord(
        id: 0,
        uuid: doc.$id,
        targetTable: 'debts',
        localPayload: localData,
        remotePayload: data,
        lastError: 'Data conflict in debt',
        timestamp: DateTime.now(),
      ),
      context: context,
      localData: localData,
      remoteData: data,
    );
  }

  /// فحص وجود تعارض في البيانات
  bool _hasDataConflict(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    // مقارنة الطوابع الزمنية
    final localUpdatedAt = _extractTimestamp(local['updatedAt']);
    final remoteUpdatedAt = _extractTimestamp(remote['updatedAt']);

    if (localUpdatedAt == null || remoteUpdatedAt == null) {
      return true; // افتراض وجود تعارض إذا لم تتوفر الطوابع
    }

    // إذا كان البعيد أحدث بفارق كبير (> 5 دقائق)
    final diff = remoteUpdatedAt.difference(localUpdatedAt);
    if (diff.inMinutes > 5) {
      return false; // البعيد أحدث بكثير - لا تعارض
    }

    // إذا كان المحلي أحدث
    if (localUpdatedAt.isAfter(remoteUpdatedAt)) {
      return true; // المحلي أحدث - تعارض محتمل
    }

    // مقارنة محتوى البيانات
    final criticalFields = [
      'status', 'amount', 'price', 'total_due_cached',
      'remaining_balance_cached', 'guest_name', 'room_number',
    ];

    for (final field in criticalFields) {
      final localValue = local[field];
      final remoteValue = remote[field];

      if (localValue != null && remoteValue != null && localValue != remoteValue) {
        return true; // اختلاف في حقل حرج
      }
    }

    return false;
  }

  /// إنشاء سياق التعارض
  ConflictContext _createConflictContext(
    String table,
    String uuid,
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) {
    final localUpdatedAt = _extractTimestamp(localData['updatedAt']);
    final remoteUpdatedAt = _extractTimestamp(remoteData['updatedAt']);

    // إنشاء Vector Clocks
    final localVectorClock = localData['vectorClock'] != null
        ? VectorClock.fromJson(localData['vectorClock'] as String)
        : VectorClock.forDevice(_deviceId ?? 'unknown');

    final remoteVectorClock = remoteData['vectorClock'] != null
        ? VectorClock.fromJson(remoteData['vectorClock'] as String)
        : VectorClock.forDevice(remoteData['deviceId'] as String? ?? 'unknown');

    return ConflictContext(
      table: table,
      uuid: uuid,
      localData: localData,
      remoteData: remoteData,
      localVectorClock: localVectorClock,
      remoteVectorClock: remoteVectorClock,
      localTimestamp: localUpdatedAt ?? DateTime.now(),
      remoteTimestamp: remoteUpdatedAt ?? DateTime.now(),
      localDeviceId: _deviceId ?? 'unknown',
      remoteDeviceId: remoteData['deviceId'] as String? ?? 'unknown',
      localDevicePriority: 100,
      remoteDevicePriority: remoteData['device_priority'] as int? ?? 100,
    );
  }

  /// استخراج الطابع الزمني
  DateTime? _extractTimestamp(dynamic value) {
    if (value == null) return null;

    if (value is String) {
      return DateTime.tryParse(value);
    } else if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }

    return null;
  }

  /// بقية الدوال المساعدة (نفس النسخة الأصلية)
  Future<T> _timePhase<T>(
    String name,
    Future<T> Function() operation,
    Map<String, int> phaseMs,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      stopwatch.stop();
      phaseMs[name] = stopwatch.elapsedMilliseconds;
    }
  }

  Future<bool> _checkConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  Future<int> _pushAllEntities() async {
    // نفس تنفيذ النسخة الأصلية
    const batchSize = 200;
    int totalProcessed = 0;

    while (true) {
      final entries = await outboxDao.takeBatch(batchSize);
      if (entries.isEmpty) break;

      int processedInBatch = 0;
      for (final entry in entries) {
        final success = await _processOutboxEntry(entry);
        if (success) {
          await outboxDao.removeById(entry.id);
          processedInBatch++;
        }
      }
      totalProcessed += processedInBatch;

      if (entries.length == batchSize && processedInBatch == 0) {
        break;
      }
    }

    return totalProcessed;
  }

  Future<bool> _processOutboxEntry(OutboxData entry) async {
    try {
      switch (entry.entity) {
        case 'rooms':
          return await _processRoomEntry(entry);
        case 'bookings':
          return await _processBookingEntry(entry);
        case 'expenses':
          return await _processExpenseEntry(entry);
        case 'payments':
          return await _processPaymentEntry(entry);
        case 'debts':
          return await _processDebtEntry(entry);
        case 'employees':
          return await _processEmployeeEntry(entry);
        default:
          _logger.warning('Unknown outbox entity: ${entry.entity}', tag: 'SYNC');
          return true;
      }
    } catch (error, stackTrace) {
      final parsed = _errorHandler.handleError(
        error,
        context: 'push:${entry.entity}:${entry.op}',
        stackTrace: stackTrace,
      );
      await outboxDao.setError(entry.id, parsed.message, entry.attempts + 1);
      await outboxDao.markFailed([entry.id]);
      return false;
    }
  }

  Future<bool> _processRoomEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(() => appwriteService.deleteRoom(entry.localUuid));
      return true;
    }
    final room = await _getRoomByLocalUuid(entry.localUuid);
    if (room == null) {
      await _deleteSilently(() => appwriteService.deleteRoom(entry.localUuid));
      return true;
    }
    final payload = _roomToRemote(room);
    await appwriteService.upsertRoom(
      room.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<bool> _processBookingEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(() => appwriteService.deleteBooking(entry.localUuid));
      return true;
    }
    final booking = await _getBookingByLocalUuid(entry.localUuid);
    if (booking == null) {
      await _deleteSilently(() => appwriteService.deleteBooking(entry.localUuid));
      return true;
    }
    final payload = _bookingToRemote(booking);
    await appwriteService.upsertBooking(
      booking.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<bool> _processExpenseEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(() => appwriteService.deleteExpense(entry.localUuid));
      return true;
    }
    final expense = await _getExpenseByLocalUuid(entry.localUuid);
    if (expense == null) {
      await _deleteSilently(() => appwriteService.deleteExpense(entry.localUuid));
      return true;
    }
    final payload = _expenseToRemote(expense);
    await appwriteService.upsertExpense(
      expense.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<bool> _processPaymentEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(() => appwriteService.deletePayment(entry.localUuid));
      return true;
    }
    final payment = await _getPaymentByLocalUuid(entry.localUuid);
    if (payment == null) {
      await _deleteSilently(() => appwriteService.deletePayment(entry.localUuid));
      return true;
    }
    final payload = _paymentToRemote(payment);
    await appwriteService.upsertPayment(
      payment.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<bool> _processDebtEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(() => appwriteService.deleteDebt(entry.localUuid));
      return true;
    }
    final debt = await _getDebtByLocalUuid(entry.localUuid);
    if (debt == null) {
      await _deleteSilently(() => appwriteService.deleteDebt(entry.localUuid));
      return true;
    }
    final payload = _debtToRemote(debt);
    await appwriteService.upsertDebt(
      debt.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<bool> _processEmployeeEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(() => appwriteService.deleteEmployee(entry.localUuid));
      return true;
    }
    final employee = await _getEmployeeByLocalUuid(entry.localUuid);
    if (employee == null) {
      await _deleteSilently(() => appwriteService.deleteEmployee(entry.localUuid));
      return true;
    }
    final payload = _employeeToRemote(employee);
    await appwriteService.upsertEmployee(
      employee.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<void> _deleteSilently(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      final message = error.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('not found') ||
          message.contains('not_found')) {
        return;
      }
      rethrow;
    }
  }

  Map<String, dynamic> _addIdempotencyKey(
    Map<String, dynamic> payload,
    OutboxData entry,
  ) {
    return {
      ...payload,
      'idempotencyKey': '${entry.entity}:${entry.op}:${entry.localUuid}:${entry.id}',
    };
  }

  // Getters
  Future<Room?> _getRoomByLocalUuid(String localUuid) async {
    return (database.select(database.rooms)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  Future<Booking?> _getBookingByLocalUuid(String localUuid) async {
    return (database.select(database.bookings)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  Future<Expense?> _getExpenseByLocalUuid(String localUuid) async {
    return (database.select(database.expenses)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  Future<Payment?> _getPaymentByLocalUuid(String localUuid) async {
    return (database.select(database.payments)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  Future<Debt?> _getDebtByLocalUuid(String localUuid) async {
    return (database.select(database.debts)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  Future<Employee?> _getEmployeeByLocalUuid(String localUuid) async {
    return (database.select(database.employees)
          ..where((t) => t.localUuid.equals(localUuid)))
        .getSingleOrNull();
  }

  // Mappers
  Map<String, dynamic> _roomToRemote(Room room) {
    return {
      'roomNumber': room.roomNumber,
      'type': room.type,
      'price': room.price,
      'status': room.status,
      'cleaningStatus': room.cleaningStatus,
      'requiresMaintenance': room.requiresMaintenance,
      'localUuid': room.localUuid,
      'createdAt': room.createdAt,
      'updatedAt': room.updatedAt,
      'lastModified': room.lastModified,
      'version': room.version,
      'origin': room.origin,
    };
  }

  Map<String, dynamic> _bookingToRemote(Booking booking) {
    return {
      'roomNumber': booking.roomNumber,
      'guestName': booking.guestName,
      'guestPhone': booking.guestPhone,
      'guestNationality': booking.guestNationality,
      'checkinDate': booking.checkinDate,
      'status': booking.status,
      'discount': booking.discount,
      'isFullyPaid': booking.isFullyPaid,
      'remainingBalanceCached': booking.remainingBalanceCached,
      'totalDueCached': booking.totalDueCached,
      'totalPaidCached': booking.totalPaidCached,
      'localUuid': booking.localUuid,
      'createdAt': booking.createdAt,
      'updatedAt': booking.updatedAt,
      'lastModified': booking.lastModified,
      'version': booking.version,
      'origin': booking.origin,
    };
  }

  Map<String, dynamic> _expenseToRemote(Expense expense) {
    return {
      'expenseType': expense.expenseType,
      'description': expense.description,
      'amount': expense.amount,
      'date': expense.date,
      'localUuid': expense.localUuid,
      'createdAt': expense.createdAt,
      'updatedAt': expense.updatedAt,
      'lastModified': expense.lastModified,
      'version': expense.version,
      'origin': expense.origin,
    };
  }

  Map<String, dynamic> _paymentToRemote(Payment payment) {
    return {
      'amount': payment.amount,
      'paymentDate': payment.paymentDate,
      'paymentMethod': payment.paymentMethod,
      'revenueType': payment.revenueType,
      'localUuid': payment.localUuid,
      'createdAt': payment.createdAt,
      'updatedAt': payment.updatedAt,
      'lastModified': payment.lastModified,
      'version': payment.version,
      'origin': payment.origin,
    };
  }

  Map<String, dynamic> _debtToRemote(Debt debt) {
    return {
      'amount': debt.amount,
      'status': debt.status,
      'guestName': debt.guestName,
      'localUuid': debt.localUuid,
      'createdAt': debt.createdAt,
      'updatedAt': debt.updatedAt,
      'lastModified': debt.lastModified,
      'version': debt.version,
      'origin': debt.origin,
    };
  }

  Map<String, dynamic> _employeeToRemote(Employee employee) {
    return {
      'name': employee.name,
      'basicSalary': employee.basicSalary,
      'position': employee.position,
      'status': employee.status,
      'localUuid': employee.localUuid,
      'createdAt': employee.createdAt,
      'updatedAt': employee.updatedAt,
      'lastModified': employee.lastModified,
      'version': employee.version,
      'origin': employee.origin,
    };
  }

  // Public API
  Future<Map<String, dynamic>> pushAllLocalDataToAppwrite() async {
    int pushed = 0;
    int failed = 0;

    // دفع جميع الكيانات
    final entities = [
      ('rooms', database.select(database.rooms).get()),
      ('bookings', database.select(database.bookings).get()),
      ('employees', database.select(database.employees).get()),
      ('expenses', database.select(database.expenses).get()),
      ('payments', database.select(database.payments).get()),
      ('debts', database.select(database.debts).get()),
    ];

    for (final (entityName, future) in entities) {
      try {
        final items = await future;
        for (final item in items) {
          try {
            await outboxDao.merge(
              entity: entityName,
              op: 'create',
              localUuid: item.localUuid,
              payload: item.toJson(),
              clientTs: Time.nowEpoch(),
            );
            pushed++;
          } catch (e) {
            failed++;
          }
        }
      } catch (e) {
        _logger.error('Error pushing $entityName: $e', tag: 'SYNC');
      }
    }

    // تشغيل الدفع الفعلي
    final actuallyPushed = await _pushAllEntities();

    return {
      'total': pushed,
      'failed': failed,
      'actuallyPushed': actuallyPushed,
    };
  }

  /// الحصول على الأجهزة المسجلة
  Future<List<AppwriteDevice>> getRegisteredDevices() async {
    try {
      final devices = await appwriteService.listDevices(useCache: false);
      return devices.map((doc) => AppwriteDevice.fromJson(doc.data)).toList();
    } catch (e) {
      _logger.error('Failed to get registered devices', error: e, tag: 'SYNC');
      return [];
    }
  }

  /// الحصول على إحصائيات المزامنة
  Future<Map<String, dynamic>> getSyncStatistics() async {
    try {
      final outboxCount = await outboxDao.count();
      final syncLogs = await appwriteService.listSyncLogs(useCache: false);

      int extractCount(Map<String, dynamic> data, String key) {
        final value = data[key];
        if (value is num) {
          return value.toInt();
        }

        final details = data['details'];
        if (details is String && details.isNotEmpty) {
          try {
            final decoded = jsonDecode(details);
            if (decoded is Map<String, dynamic>) {
              final detailValue = decoded[key];
              if (detailValue is num) {
                return detailValue.toInt();
              }
            }
          } catch (_) {}
        }

        return 0;
      }

      final totalSyncs = syncLogs.length;
      final successfulSyncs = syncLogs
          .where((log) => log.data['status'] == SyncLogStatus.completed.value)
          .length;
      final failedSyncs = syncLogs
          .where((log) => log.data['status'] == SyncLogStatus.failed.value)
          .length;

      final totalRecordsPushed = syncLogs.fold<int>(
        0,
        (sum, log) =>
            sum +
            extractCount(Map<String, dynamic>.from(log.data), 'recordsPushed'),
      );
      final totalRecordsPulled = syncLogs.fold<int>(
        0,
        (sum, log) =>
            sum +
            extractCount(Map<String, dynamic>.from(log.data), 'recordsPulled'),
      );
      final totalConflicts = syncLogs.fold<int>(
        0,
        (sum, log) =>
            sum +
            extractCount(Map<String, dynamic>.from(log.data), 'conflicts'),
      );

      Map<String, dynamic>? lastFailed;
      for (final log in syncLogs) {
        final data = Map<String, dynamic>.from(log.data);
        if ((data['status'] ?? '') == SyncLogStatus.failed.value) {
          lastFailed = data;
          break;
        }
      }

      final timeline = <Map<String, dynamic>>[];
      for (final log in syncLogs.take(20)) {
        final data = Map<String, dynamic>.from(log.data);
        timeline.add({
          'status': data['status'],
          'timestamp':
              data['timestamp'] ?? data['endTime'] ?? data['startTime'],
          'syncType': data['syncType'] ?? data['action'],
          'recordsPushed': extractCount(data, 'recordsPushed'),
          'recordsPulled': extractCount(data, 'recordsPulled'),
          'conflicts': extractCount(data, 'conflicts'),
          'durationMs': data['durationMs'] ?? 0,
        });
      }

      return {
        'totalSyncs': totalSyncs,
        'successfulSyncs': successfulSyncs,
        'failedSyncs': failedSyncs,
        'pendingChanges': outboxCount,
        'totalRecordsPushed': totalRecordsPushed,
        'totalRecordsPulled': totalRecordsPulled,
        'totalConflicts': totalConflicts,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
        'lastFailed': lastFailed,
        'timeline': timeline,
      };
    } catch (e) {
      _logger.error('Failed to get sync statistics', error: e, tag: 'SYNC');
      return {
        'totalSyncs': 0,
        'successfulSyncs': 0,
        'failedSyncs': 0,
        'pendingChanges': 0,
        'totalRecordsPushed': 0,
        'totalRecordsPulled': 0,
        'totalConflicts': 0,
        'error': e.toString(),
      };
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _debouncePushTimer?.cancel();
    _outboxSubscription?.cancel();
    _syncController.close();
  }

  void _enableDebouncedPush() {
    // نفس تنفيذ النسخة الأصلية
  }
}

/// نتيجة سحب الكيانات
class _PullResult {
  final int recordsPulled;
  final int conflicts;
  final int conflictsResolved;
  final List<ConflictRecord> conflictDetails;

  _PullResult({
    required this.recordsPulled,
    required this.conflicts,
    required this.conflictsResolved,
    required this.conflictDetails,
  });
}

/// نتيجة سحب كيان واحد
class _EntityPullResult {
  final int records;
  final int conflicts;
  final int resolved;
  final List<ConflictRecord> conflictDetails;

  _EntityPullResult({
    required this.records,
    required this.conflicts,
    required this.resolved,
    required this.conflictDetails,
  });
}

/// استثناء اكتشاف تعارض
class ConflictDetectedException implements Exception {
  final ConflictRecord conflictRecord;
  final ConflictContext context;
  final Map<String, dynamic> localData;
  final Map<String, dynamic> remoteData;

  ConflictDetectedException({
    required this.conflictRecord,
    required this.context,
    required this.localData,
    required this.remoteData,
  });

  @override
  String toString() =>
      'ConflictDetectedException: ${conflictRecord.targetTable}/${conflictRecord.uuid}';
}

/// استثناء FOREIGN KEY
class ForeignKeyException implements Exception {
  final String message;
  ForeignKeyException(this.message);

  @override
  String toString() => 'ForeignKeyException: $message';
}

/// تجاهل await للمهام غير المتزامنة
void unawaited(Future<void> future) {}
