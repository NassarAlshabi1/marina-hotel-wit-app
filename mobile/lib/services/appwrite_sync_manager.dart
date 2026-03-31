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
import 'appwrite_delta_sync.dart'; // ✅ Field-Level Delta Sync
import 'appwrite_full_pull.dart'; // ✅ Full Pull Service
import 'local_db.dart';
import 'daos/outbox_dao.dart';
import 'daos/sync_log_dao.dart';
import 'sync_mutex.dart';
import 'sync_enums.dart';
import 'sync_constants.dart';
import 'sync_core/sync_metrics.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/source.dart';
import 'repositories/bookings_repository.dart';

/// حالة المزامنة
enum SyncStatus { idle, syncing, success, failed, partial }

/// نتيجة المزامنة
class SyncResult {
  SyncResult({
    required this.status,
    this.recordsPushed = 0,
    this.recordsPulled = 0,
    this.conflicts = 0,
    this.errorMessage,
    required this.timestamp,
    required this.duration,
  });
  final SyncStatus status;
  final int recordsPushed;
  final int recordsPulled;
  final int conflicts;
  final String? errorMessage;
  final DateTime timestamp;
  final Duration duration;

  bool get isSuccess => status == SyncStatus.success;
  bool get hasConflicts => conflicts > 0;
}

/// مدير المزامنة الثنائية
class AppwriteSyncManager {
  factory AppwriteSyncManager({
    required AppwriteService appwriteService,
    required AppDatabase database,
  }) {
    _instance ??= AppwriteSyncManager._internal(
      appwriteService: appwriteService,
      database: database,
    );
    return _instance!;
  }

  AppwriteSyncManager._internal({
    required this.appwriteService,
    required this.database,
  }) : outboxDao = OutboxDao(database) {
    _adapterRegistry = AdapterRegistry(database);
    _bookingsRepository = BookingsRepository(database);
  }
  static AppwriteSyncManager? _instance;

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  late final BookingsRepository _bookingsRepository;
  late final AdapterRegistry _adapterRegistry;
  final SyncMutex _mutex = SyncMutex();

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

  /// تهيئة المزامنة
  Future<void> initialize() async {
    try {
      await appwriteService.initialize();
      await _loadSettings();

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

      // رفع البيانات الحالية مرة واحدة (للبيانات التي أُنشئت قبل تفعيل Outbox)
      unawaited(_runInitialSeedIfNeeded());

      _logger.info('Sync manager initialized', tag: 'SYNC');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to initialize sync manager',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
    }
  }

  /// رفع جميع البيانات المحلية مرة واحدة عند أول تشغيل بعد التفعيل
  Future<void> _runInitialSeedIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final done = prefs.getBool('appwrite_initial_seed_done') ?? false;
      if (done) return;

      // التحقق من وجود بيانات محلية تحتاج رفع
      final rooms = await database.select(database.rooms).get();
      if (rooms.isEmpty) {
        await prefs.setBool('appwrite_initial_seed_done', true);
        return;
      }

      _logger.info('بدء الرفع الأولي للبيانات المحلية...', tag: 'SYNC');
      final stats = await pushAllLocalDataToAppwrite();
      _logger.info('اكتمل الرفع الأولي: $stats', tag: 'SYNC');

      await prefs.setBool('appwrite_initial_seed_done', true);
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
    // قراءة الإعدادات المحفوظة (بدون تغييرها)
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
    if (_deviceLocalUuid != null) {
      await prefs.setString('appwrite_device_local_uuid', _deviceLocalUuid!);
    }
    if (_deviceVersion != null) {
      await prefs.setInt('appwrite_device_version', _deviceVersion!);
    }
    if (_deviceCreatedAtEpoch != null) {
      await prefs.setInt('appwrite_device_created_at', _deviceCreatedAtEpoch!);
    }
  }

  /// تسجيل الجهاز تلقائياً
  Future<String> registerDevice({
    String? deviceName,
    String? deviceModel,
    String? osVersion,
  }) async {
    try {
      String finalDeviceName = deviceName ?? 'Unknown Device';
      String finalDeviceModel = deviceModel ?? 'Unknown Model';
      String finalOsVersion = osVersion ?? 'Unknown OS';

      if (deviceName == null || deviceModel == null || osVersion == null) {
        final deviceInfo = DeviceInfoPlugin();

        if (Platform.isAndroid) {
          final androidInfo = await deviceInfo.androidInfo;
          finalDeviceName = androidInfo.model;
          finalDeviceModel = androidInfo.device;
          finalOsVersion = 'Android ${androidInfo.version.release}';
        } else if (Platform.isIOS) {
          final iosInfo = await deviceInfo.iosInfo;
          finalDeviceName = iosInfo.name;
          finalDeviceModel = iosInfo.model;
          finalOsVersion = '${iosInfo.systemName} ${iosInfo.systemVersion}';
        }
      }

      _logger.info('Registering device: $finalDeviceName', tag: 'SYNC');
      final deviceType = _resolveDeviceType();
      final nowIso = Time.nowIso();
      final nowEpoch = Time.nowEpoch();

      _deviceLocalUuid ??= IdGen.uuid();
      _deviceCreatedAtEpoch ??= nowEpoch;

      if (_currentDeviceId != null) {
        await _mutex.runExclusive(() async {
          var currentRemoteVersion = 0;
          try {
            final existingDoc = await appwriteService.getDocument(
              collectionId: AppwriteConfig.devicesCollectionId,
              documentId: _currentDeviceId!,
            );
            currentRemoteVersion = _asInt(
              existingDoc.data['version'],
              fallback: 0,
            );
          } catch (_) {
            currentRemoteVersion = 0;
          }

          if (_deviceVersion == null ||
              _deviceVersion! <= currentRemoteVersion) {
            _deviceVersion = currentRemoteVersion + 1;
          }

          await appwriteService.upsertDocument(
            collectionId: AppwriteConfig.devicesCollectionId,
            documentId: _currentDeviceId!,
            data: {
              'deviceName': finalDeviceName,
              'deviceModel': finalDeviceModel,
              'osVersion': finalOsVersion,
              'deviceType': deviceType,
              'status': DeviceStatus.active.value,
              'localUuid': _deviceLocalUuid,
              'lastSeen': nowIso,
              'lastActive': nowEpoch,
              'createdAt': _deviceCreatedAtEpoch,
              'updatedAt': nowEpoch,
              'lastModified': nowEpoch,
              'version': _deviceVersion,
              'origin': 'mobile',
            },
          );
        });

        await _saveSettings();
        _logger.info('Device updated: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      } else {
        _deviceVersion = 1;
        _deviceCreatedAtEpoch = nowEpoch;

        final device = await appwriteService.createDevice({
          'deviceName': finalDeviceName,
          'deviceModel': finalDeviceModel,
          'osVersion': finalOsVersion,
          'deviceType': deviceType,
          'status': DeviceStatus.active.value,
          'localUuid': _deviceLocalUuid,
          'lastSeen': nowIso,
          'lastActive': nowEpoch,
          'createdAt': _deviceCreatedAtEpoch,
          'updatedAt': nowEpoch,
          'lastModified': nowEpoch,
          'version': _deviceVersion,
          'origin': 'mobile',
        });

        _currentDeviceId = device.$id;
        await _saveSettings();

        _logger.info('Device registered: $_currentDeviceId', tag: 'SYNC');
        return _currentDeviceId!;
      }
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to register device',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      rethrow;
    }
  }

  /// بدء المزامنة التلقائية
  void startAutoSync({
    Duration interval = SyncConstants.defaultAutoSyncInterval,
  }) {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(interval, (timer) async {
      await sync();
    });
    _logger.info(
      'Auto sync started (interval: ${interval.inMinutes} min)',
      tag: 'SYNC',
    );
  }

  /// إيقاف المزامنة التلقائية
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _logger.info('Auto sync stopped', tag: 'SYNC');
  }

  /// تمكين الدفع المؤجل بعد تغييرات outbox
  void _enableDebouncedPush({Duration? window}) {
    if (window != null) {
      _debounceWindow = window;
    }
    _outboxSubscription?.cancel();
    _outboxSubscription = database
        .select(database.outbox)
        .watch()
        .listen(
          (_) {
            _debouncePushTimer?.cancel();
            _debouncePushTimer = Timer(_debounceWindow, () async {
              if (_isPulling) return;
              _logger.debug('Debounced push triggered', tag: 'SYNC');
              try {
                final result = await sync(push: true, pull: false);
                if (result.status != SyncStatus.success) {
                  _logger.warning(
                    'Debounced push sync failed: ${result.errorMessage ?? ''}',
                    tag: 'SYNC',
                  );
                }
              } catch (e, stackTrace) {
                _logger.error(
                  'Debounced push failed',
                  error: e,
                  stackTrace: stackTrace,
                  tag: 'SYNC',
                );
              }
            });
          },
          onError: (e, stackTrace) {
            _logger.error(
              'Outbox watch stream failed',
              error: e,
              stackTrace: stackTrace,
              tag: 'SYNC',
            );
          },
        );
    _logger.info(
      'Debounced push enabled (window: ${_debounceWindow.inSeconds}s)',
      tag: 'SYNC',
    );
  }

  /// تنظيف الموارد
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _debouncePushTimer?.cancel();

    // ✅ انتظر إلغاء الاشتراك
    await _outboxSubscription?.cancel();
    _outboxSubscription = null;

    stopAutoSync();

    // ✅ أغلق الـ stream بأمان
    if (!_syncController.isClosed) {
      await _syncController.close();
    }
  }

  /// دورة المزامنة الكاملة مع Appwrite:
  /// ✅ تستخدم Field-Level Delta Sync
  /// - تتحقق من الاتصال بالشبكة
  /// - Push: تستخدم AppwriteDeltaSync لإرسال الحقول المتغيرة فقط
  /// - Pull: تسحب التحديثات من Appwrite وتدمج محلياً
  ///
  /// الدالة لا ترمي عادةً استثناءات، وتعيد SyncResult مع status/errorMessage.
  Future<SyncResult> sync({bool push = true, bool pull = true}) async {
    // ✅ فحص واحد فقط للـ mutex مع timeout
    if (!await _mutex.acquire(timeout: const Duration(seconds: 30))) {
      _logger.warning(
        'Failed to acquire sync mutex (timeout or busy)',
        tag: 'SYNC',
      );
      return SyncResult(
        status: SyncStatus.failed,
        errorMessage: 'Sync in progress or timeout',
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
    }

    // ✅ الآن نحن الوحيدون الذين يمكنهم التغيير
    _currentStatus = SyncStatus.syncing;
    _syncController.add(_currentStatus);

    final startTime = DateTime.now();
    final syncId = 'appwrite_${DateTime.now().millisecondsSinceEpoch}';
    int recordsPushed = 0;
    int recordsPulled = 0;
    int conflicts = 0;
    String? errorMessage;
    SyncStatus finalStatus = SyncStatus.success;

    // ✅ تسجيل بداية عملية المزامنة في SyncLogDao
    final syncLogDao = SyncLogDao(database);
    try {
      await syncLogDao.logSync(
        syncId: syncId,
        direction: push && pull ? 'bidirectional' : (push ? 'push' : 'pull'),
        deviceId: _currentDeviceId ?? 'unknown',
        target: 'Appwrite',
        status: 'in_progress',
      );
    } catch (e) {
      _logger.warning('Failed to log sync start: $e', tag: 'SYNC');
    }

    try {
      _logger.info('Starting Field-Level Delta Sync...', tag: 'SYNC');

      // التحقق من الاتصال
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity == ConnectivityResult.none) {
        throw Exception('No internet connection');
      }

      // ✅ تهيئة AppwriteService أولاً قبل استخدامه
      await appwriteService.initialize();

      // ✅ تهيئة AppwriteDeltaSync إذا لم يكن مهيأً
      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        await deltaSync.initialize(appwriteService, database);
      }

      // ✅ تنفيذ المزامنة باستخدام Field-Level Delta Sync
      if (push && pull) {
        final result = await deltaSync.fullSync();
        recordsPushed = result.pushedCount;
        recordsPulled = result.pulledCount;
        conflicts = result.conflictCount;
        if (!result.success) {
          errorMessage = result.message;
          finalStatus = SyncStatus.failed;
        }
      } else if (push) {
        final result = await deltaSync.pushDeltaChanges();
        recordsPushed = result.pushedCount;
        conflicts = result.conflictCount;
        if (!result.success) {
          errorMessage = result.message;
          finalStatus = SyncStatus.failed;
        }
      } else if (pull) {
        final result = await deltaSync.pullDeltaChanges();
        recordsPulled = result.pulledCount;
        if (!result.success) {
          errorMessage = result.message;
          finalStatus = SyncStatus.failed;
        }
      }

      _lastSyncTime = DateTime.now();
      await _saveSettings();

      _logger.info(
        'Field-Level Delta Sync completed (pushed: $recordsPushed, pulled: $recordsPulled)',
        tag: 'SYNC',
      );
    } catch (e, stackTrace) {
      errorMessage = e.toString();
      finalStatus = SyncStatus.failed;
      _errorHandler.handleError(e, context: 'sync()', stackTrace: stackTrace);
      _logger.error(
        'Field-Level Delta Sync failed',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
    }

    // ✅ دائماً حرر الـ mutex في finally
    _currentStatus = finalStatus;
    _syncController.add(_currentStatus);
    _mutex.release();

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    final metrics = SyncMetrics.instance;
    if (finalStatus == SyncStatus.success) {
      metrics.recordSuccess(
        recordsSynced: recordsPushed + recordsPulled,
        conflictsResolved: conflicts,
      );
    } else {
      metrics.recordFailure(errorMessage ?? 'Appwrite sync failed');
    }

    // ✅ تسجيل نتيجة عملية المزامنة في SyncLogDao (للإحصائيات)
    try {
      await syncLogDao.logSync(
        syncId: syncId,
        direction: push && pull ? 'bidirectional' : (push ? 'push' : 'pull'),
        deviceId: _currentDeviceId ?? 'unknown',
        target: 'Appwrite',
        status: finalStatus == SyncStatus.success
            ? 'success'
            : (finalStatus == SyncStatus.failed ? 'failed' : 'partial'),
        recordsPushed: recordsPushed,
        recordsPulled: recordsPulled,
        errorMessage: errorMessage,
        durationMs: duration.inMilliseconds,
      );
    } catch (e) {
      _logger.warning('Failed to log sync result: $e', tag: 'SYNC');
    }

    return SyncResult(
      status: finalStatus,
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      conflicts: conflicts,
      errorMessage: errorMessage,
      timestamp: endTime,
      duration: duration,
    );
  }

  /// الحصول على إحصائيات المزامنة من قاعدة البيانات المحلية
  Future<Map<String, dynamic>> getSyncStatistics() async {
    try {
      final outboxCount = await outboxDao.count();
      final outboxStats = await outboxDao.getStats();

      // استخدام SyncLogDao المحلي بدلاً من Appwrite السحابي
      final syncLogDao = SyncLogDao(database);
      final syncStats = await syncLogDao.getSyncStats();
      final recentLogs = await syncLogDao.getSyncHistory(limit: 20);

      final timeline = recentLogs.map((log) {
        return {
          'status': log.status,
          'timestamp': log.createdAt.toIso8601String(),
          'syncType': log.direction,
          'recordsPushed': log.recordsCount ?? 0,
          'recordsPulled': log.recordsCount ?? 0,
          'durationMs': log.durationMs ?? 0,
          'errorMessage': log.errorMessage,
        };
      }).toList();

      // الحصول على آخر سجل فاشل
      final failedLogs = await syncLogDao.getSyncHistory(
        limit: 1,
        status: 'failed',
      );
      final lastFailed = failedLogs.isNotEmpty ? failedLogs.first : null;

      return {
        'totalSyncs': syncStats.totalSyncs,
        'successfulSyncs': syncStats.successfulSyncs,
        'failedSyncs': syncStats.failedSyncs,
        'successRate': syncStats.successRate,
        'totalRecordsPushed': syncStats.totalRecordsPushed,
        'totalRecordsPulled': syncStats.totalRecordsPulled,
        'totalConflicts': outboxStats.conflicts,
        'lastSyncTime': syncStats.lastSync?.toIso8601String(),
        'outboxCount': outboxCount,
        'pendingCount': outboxStats.pending,
        'failedCount': outboxStats.failed,
        'conflictCount': outboxStats.conflicts,
        'lastErrorMessage': lastFailed?.errorMessage,
        'lastErrorTime': lastFailed?.createdAt.toIso8601String(),
        'timeline': timeline,
        'averageDurationMs': syncStats.averageDurationMs,
      };
    } catch (e) {
      _logger.error('Failed to get sync statistics', error: e, tag: 'SYNC');
      return {
        'totalSyncs': 0,
        'successfulSyncs': 0,
        'failedSyncs': 0,
        'successRate': 0.0,
        'totalRecordsPushed': 0,
        'totalRecordsPulled': 0,
        'totalConflicts': 0,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
        'outboxCount': 0,
        'pendingCount': 0,
        'failedCount': 0,
        'conflictCount': 0,
        'lastErrorMessage': null,
        'lastErrorTime': null,
        'timeline': <Map<String, dynamic>>[],
        'averageDurationMs': 0,
      };
    }
  }

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

  Future<int> _syncRooms(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.rooms.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) {
        _logger.warning('Failed to sync room ${doc.$id}: $e', tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _syncBookings(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ التحقق من صحة discountStartDate
        if (data.containsKey('discountStartDate')) {
          final dateStr = data['discountStartDate']?.toString();
          if (dateStr != null && dateStr.isNotEmpty) {
            try {
              // التحقق من صحة التاريخ
              DateTime.parse(dateStr);
              data['discountStartDate'] = dateStr;
            } catch (_) {
              data.remove('discountStartDate'); // إزالة إذا كان غير صالح
            }
          }
        }

        await _adapterRegistry.bookings.upsertFromJson(
          data,
          src: Source.appwrite,
        );

        // TRIGGER POST-SYNC PROCESSING
        // 1. Resolve local ID from UUID
        final localUuid = data['localUuid'];
        final booking = await (database.select(
          database.bookings,
        )..where((b) => b.localUuid.equals(localUuid))).getSingleOrNull();

        if (booking != null) {
          // 2. Convert legacy discount to adjustments

          // 3. Recalculate derived fields (nightly rates, total due)
          await _bookingsRepository.derivedFields.refreshForBookingId(
            booking.id,
          );
        }

        processed++;
      } catch (e) {
        _logger.warning('Failed to sync booking ${doc.$id}: $e', tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _syncEmployees(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.employees.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning('Failed to sync employee ${doc.$id}: $e', tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _syncExpenses(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.expenses.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning('Failed to sync expense ${doc.$id}: $e', tag: 'SYNC');
      }
    }
    return processed;
  }

  Future<int> _syncPayments(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final deferred = <models.Document>[];

    // المرحلة الأولى: معالجة الدفعات
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        await _adapterRegistry.payments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        // تأجيل الدفعة إذا كان الخطأ FOREIGN KEY constraint
        if (e.toString().contains('FOREIGN KEY constraint failed') ||
            e.toString().contains('constraint failed')) {
          _logger.debug(
            'Deferring payment ${doc.$id}: FOREIGN KEY constraint (missing booking)',
            tag: 'SYNC',
          );
          deferred.add(doc);
        } else {
          _logger.warning('Failed to sync payment ${doc.$id}: $e', tag: 'SYNC');
        }
      }
    }

    // المرحلة الثانية: إعادة محاولة الدفعات المؤجلة
    if (deferred.isNotEmpty) {
      _logger.info(
        'Retrying ${deferred.length} deferred payments after all bookings synced',
        tag: 'SYNC',
      );

      for (final doc in deferred) {
        try {
          final data = Map<String, dynamic>.from(doc.data);
          data['localUuid'] ??= doc.$id;
          await _adapterRegistry.payments.upsertFromJson(
            data,
            src: Source.appwrite,
          );
          processed++;
        } catch (e) {
          _logger.warning(
            'Failed to sync deferred payment ${doc.$id} after retry: $e',
            tag: 'SYNC',
          );
        }
      }
    }

    return processed;
  }

  Future<int> _syncDebts(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final deferred = <models.Document>[];

    // المرحلة الأولى: معالجة الديون
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.debts.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) {
        // تأجيل الدين إذا كان الخطأ FOREIGN KEY constraint
        if (e.toString().contains('FOREIGN KEY constraint failed') ||
            e.toString().contains('constraint failed')) {
          _logger.debug(
            'Deferring debt ${doc.$id}: FOREIGN KEY constraint (missing booking)',
            tag: 'SYNC',
          );
          deferred.add(doc);
        } else {
          _logger.warning('Failed to sync debt ${doc.$id}: $e', tag: 'SYNC');
        }
      }
    }

    // المرحلة الثانية: إعادة محاولة الديون المؤجلة
    if (deferred.isNotEmpty) {
      _logger.info(
        'Retrying ${deferred.length} deferred debts after all bookings synced',
        tag: 'SYNC',
      );

      for (final doc in deferred) {
        try {
          final data = Map<String, dynamic>.from(doc.data);
          data['localUuid'] ??= doc.$id;
          await _adapterRegistry.debts.upsertFromJson(
            data,
            src: Source.appwrite,
          );
          processed++;
        } catch (e) {
          _logger.warning(
            'Failed to sync deferred debt ${doc.$id} after retry: $e',
            tag: 'SYNC',
          );
        }
      }
    }

    return processed;
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    final result = _asIntNullable(value);
    return result ?? fallback;
  }

  int? _asIntNullable(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    if (value is String && value.isNotEmpty) {
      final parsedInt = int.tryParse(value);
      if (parsedInt != null) {
        return parsedInt;
      }
      final parsedDouble = double.tryParse(value);
      if (parsedDouble != null) {
        return parsedDouble.toInt();
      }
    }
    return null;
  }

  Future<int> _pushAllEntities() async {
    const batchSize = 50; // ✅ أصغر حجم لتجنب rate limiting
    const maxConcurrent = 3; // ✅ تحديد concurrent operations
    int totalProcessed = 0;

    while (true) {
      final entries = await outboxDao.takeBatch(batchSize);
      if (entries.isEmpty) {
        break;
      }

      // ✅ معالجة batch بشكل متوازي مع حد
      final results =
          await Future.wait(
            entries.map(
              (entry) => _processOutboxEntry(entry).then((success) async {
                if (success) {
                  await outboxDao.removeById(entry.id);
                  return true;
                }
                return false;
              }),
            ),
            eagerError: false,
          ).catchError((e) {
            _logger.warning('Batch failed partially: $e', tag: 'SYNC');
            return <bool>[];
          });

      final processedInBatch = results.where((r) => r).length;
      totalProcessed += processedInBatch;

      // ✅ تأخير بين الـ batches لتجنب rate limiting
      if (entries.length == batchSize) {
        await Future.delayed(const Duration(milliseconds: 100));
      }

      if (entries.length == batchSize && processedInBatch == 0) {
        _logger.warning(
          'Push loop stuck on failing entries. Breaking.',
          tag: 'SYNC',
        );
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
        case 'salary_payments':
          return await _processSalaryPaymentEntry(entry);
        case 'cash_transactions':
          return await _processCashTransactionEntry(entry);
        case 'shift_notes':
          return await _processShiftNoteEntry(entry);
        case 'debts':
          return await _processDebtEntry(entry);
        case 'employees':
          return await _processEmployeeEntry(entry);
        case 'booking_notes':
          return await _processBookingNoteEntry(entry);
        case 'booking_nights':
          return await _processBookingNightEntry(entry);
        case 'salary_cycles':
          return await _processSalaryCycleEntry(entry);
        case 'salary_withdrawals':
          return await _processSalaryWithdrawalEntry(entry);
        case 'booking_price_adjustments':
          return await _processBookingPriceAdjustmentEntry(entry);
        case 'payment_voids':
          return await _processPaymentVoidEntry(entry);
        default:
          _logger.warning(
            'Unknown outbox entity: ${entry.entity}',
            tag: 'SYNC',
          );
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

  Map<String, dynamic> _addIdempotencyKey(
    Map<String, dynamic> payload,
    OutboxData entry,
  ) {
    return {
      ...payload,
      'idempotencyKey':
          '${entry.entity}:${entry.op}:${entry.localUuid}:${entry.id}',
    };
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
      await _deleteSilently(
        () => appwriteService.deleteBooking(entry.localUuid),
      );
      return true;
    }
    final booking = await _getBookingByLocalUuid(entry.localUuid);
    if (booking == null) {
      await _deleteSilently(
        () => appwriteService.deleteBooking(entry.localUuid),
      );
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
      await _deleteSilently(
        () => appwriteService.deleteExpense(entry.localUuid),
      );
      return true;
    }
    final expense = await _getExpenseByLocalUuid(entry.localUuid);
    if (expense == null) {
      await _deleteSilently(
        () => appwriteService.deleteExpense(entry.localUuid),
      );
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
      await _deleteSilently(
        () => appwriteService.deletePayment(entry.localUuid),
      );
      return true;
    }
    final payment = await _getPaymentByLocalUuid(entry.localUuid);
    if (payment == null) {
      await _deleteSilently(
        () => appwriteService.deletePayment(entry.localUuid),
      );
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

  Future<void> _deleteSilently(Future<void> Function() action) async {
    try {
      await action();
    } catch (error) {
      if (error is AppwriteError && error.code == 'NOT_FOUND') {
        _logger.debug(
          'Delete target not found (AppwriteError): ${error.message}',
          tag: 'SYNC',
        );
        return;
      }

      final message = error.toString().toLowerCase();
      if (message.contains('404') ||
          message.contains('not found') ||
          message.contains('not_found') ||
          message.contains('document_not_found')) {
        _logger.debug('Delete target not found: $message', tag: 'SYNC');
        return;
      }
      rethrow;
    }
  }

  Future<Room?> _getRoomByLocalUuid(String localUuid) {
    return (database.select(
      database.rooms,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  Future<Booking?> _getBookingByLocalUuid(String localUuid) {
    return (database.select(
      database.bookings,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  Future<Expense?> _getExpenseByLocalUuid(String localUuid) {
    return (database.select(
      database.expenses,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  Future<Payment?> _getPaymentByLocalUuid(String localUuid) {
    return (database.select(
      database.payments,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  Future<Debt?> _getDebtByLocalUuid(String localUuid) {
    return (database.select(
      database.debts,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  /// تم الاستبدال بـ AppwriteDeltaSync الذي يرسل الحقول المتغيرة فقط
  /// يُستخدم فقط في pushAllLocalDataToAppwrite للاستعادة من backup
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _roomToRemote(Room room) {
    final data = <String, dynamic>{
      'roomNumber': room.roomNumber,
      'type': room.type,
      'roomType': room.type,
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
      // ✅ الحقول المطلوبة في Appwrite (required=true)
      'basePrice': room.price ?? 0.0,
      'floor': 1, // قيمة افتراضية للطابق
    };
    _putIfNotNull(data, 'serverId', room.serverId);
    _putIfNotNull(data, 'deletedAt', room.deletedAt);
    _putIfStringNotEmpty(data, 'imageUrl', room.imageUrl);
    _putIfStringNotEmpty(data, 'lastCleanedHotelDay', room.lastCleanedHotelDay);
    _putIfStringNotEmpty(
      data,
      'lastOccupiedHotelDay',
      room.lastOccupiedHotelDay,
    );
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  /// تم الاستبدال بـ AppwriteDeltaSync الذي يرسل الحقول المتغيرة فقط
  /// يُستخدم فقط في pushAllLocalDataToAppwrite للاستعادة من backup
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _bookingToRemote(Booking booking) {
    final data = <String, dynamic>{
      'roomNumber': booking.roomNumber,
      'guestName': booking.guestName,
      'guestPhone': booking.guestPhone,
      'guestIdType': booking.guestIdType,
      'guestIdNumber': booking.guestIdNumber,
      'guestNationality': booking.guestNationality,
      'checkinDate': booking.checkinDate,
      'status': booking.status,
      'expectedNights': booking.expectedNights,
      'calculatedNights': booking.calculatedNights,
      'discount': booking.discount,
      'isOverdue': booking.isOverdue,
      'isFullyPaid': booking.isFullyPaid,
      'remainingBalanceCached': booking.remainingBalanceCached,
      'totalDueCached': booking.totalDueCached,
      'totalPaidCached': booking.totalPaidCached,
      'totalNightsCached': booking.totalNightsCached,
      'needsCheckoutReview': booking.needsCheckoutReview,
      'localUuid': booking.localUuid,
      'createdAt': booking.createdAt,
      'updatedAt': booking.updatedAt,
      'lastModified': booking.lastModified,
      'version': booking.version,
      'origin': booking.origin,
      'vectorClock': jsonEncode(booking.vectorClock ?? {}),
    };

    _putIfNotNull(data, 'serverBookingId', booking.serverBookingId);
    _putIfNotNull(data, 'serverId', booking.serverId);
    _putIfNotNull(data, 'deletedAt', booking.deletedAt);
    _putIfNotNull(data, 'lastNightEpoch', booking.lastNightEpoch);
    _putIfStringNotEmpty(data, 'guestIdIssueDate', booking.guestIdIssueDate);
    _putIfStringNotEmpty(data, 'guestIdIssuePlace', booking.guestIdIssuePlace);
    _putIfStringNotEmpty(data, 'guestEmail', booking.guestEmail);
    _putIfStringNotEmpty(data, 'guestAddress', booking.guestAddress);
    _putIfStringNotEmpty(data, 'checkoutDate', booking.checkoutDate);
    _putIfStringNotEmpty(data, 'actualCheckout', booking.actualCheckout);
    _putIfStringNotEmpty(data, 'hotelDayCheckin', booking.hotelDayCheckin);
    _putIfStringNotEmpty(data, 'hotelDayCheckout', booking.hotelDayCheckout);

    // ✅ تصحيح: discountStartDate (Data وليس Date)
    _putIfStringNotEmpty(data, 'discountType', booking.discountType);
    _putIfStringNotEmpty(data, 'discountStartDate', booking.discountStartDate);

    _putIfStringNotEmpty(data, 'stayDurationIso', booking.stayDurationIso);
    _putIfStringNotEmpty(data, 'financialHash', booking.financialHash);
    _putIfStringNotEmpty(data, 'financialFrozenAt', booking.financialFrozenAt);
    _putIfStringNotEmpty(data, 'notes', booking.notes);

    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _expenseToRemote(Expense expense) {
    final data = <String, dynamic>{
      'expenseType': expense.expenseType,
      'description': expense.description,
      'amount': expense.amount,
      'date': expense.date,
      'isAutoGenerated': expense.isAutoGenerated,
      'localUuid': expense.localUuid,
      'createdAt': expense.createdAt,
      'updatedAt': expense.updatedAt,
      'lastModified': expense.lastModified,
      'version': expense.version,
      'origin': expense.origin,
    };
    _putIfNotNull(data, 'relatedId', expense.relatedId);
    _putIfNotNull(data, 'cashTransactionId', expense.cashTransactionId);
    _putIfNotNull(data, 'serverId', expense.serverId);
    _putIfNotNull(data, 'deletedAt', expense.deletedAt);
    _putIfStringNotEmpty(data, 'hotelDayKey', expense.hotelDayKey);
    _putIfStringNotEmpty(data, 'categoryUuid', expense.categoryUuid);
    _putIfStringNotEmpty(data, 'cashFlowUuid', expense.cashFlowUuid);
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _paymentToRemote(Payment payment) {
    final data = <String, dynamic>{
      'amount': payment.amount,
      'paymentDate': payment.paymentDate,
      'paymentMethod': payment.paymentMethod,
      'revenueType': payment.revenueType,
      'isPendingBalance': payment.isPendingBalance,
      'localUuid': payment.localUuid,
      'createdAt': payment.createdAt,
      'updatedAt': payment.updatedAt,
      'lastModified': payment.lastModified,
      'version': payment.version,
      'origin': payment.origin,
      // ✅ الحقول المطلوبة في Appwrite (required=true)
      'sync_version': payment.version ?? 1,
      'sync_vector_clock': '{}',
    };
    _putIfNotNull(data, 'serverPaymentId', payment.serverPaymentId);
    _putIfNotNull(data, 'bookingLocalId', payment.bookingLocalId);
    _putIfStringNotEmpty(data, 'bookingUuidCache', payment.bookingUuidCache);
    _putIfNotNull(data, 'serverBookingId', payment.serverBookingId);
    _putIfStringNotEmpty(data, 'roomNumber', payment.roomNumber);
    _putIfStringNotEmpty(data, 'notes', payment.notes);
    _putIfNotNull(
      data,
      'cashTransactionLocalId',
      payment.cashTransactionLocalId,
    );
    _putIfNotNull(
      data,
      'cashTransactionServerId',
      payment.cashTransactionServerId,
    );
    _putIfStringNotEmpty(data, 'referenceNumber', payment.referenceNumber);
    _putIfStringNotEmpty(data, 'hotelDayKey', payment.hotelDayKey);
    _putIfStringNotEmpty(data, 'linkedDebtUuid', payment.linkedDebtUuid);
    _putIfNotNull(data, 'serverId', payment.serverId);
    _putIfNotNull(data, 'deletedAt', payment.deletedAt);
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _debtToRemote(Debt debt) {
    final data = <String, dynamic>{
      'localUuid': debt.localUuid,
      'createdAt': debt.createdAt,
      'updatedAt': debt.updatedAt,
      'lastModified': debt.lastModified,
      'version': debt.version,
      'origin': debt.origin,
      'guestName': debt.guestName,
      'checkinDate': debt.checkinDate,
      'checkoutDate': debt.checkoutDate,
      'dateRecorded': debt.dateRecorded,
      'debtReason': debt.debtReason,
      'totalAmount': debt.totalAmount,
      'paidAmount': debt.paidAmount,
      'remainingAmount': debt.remainingAmount,
      'paymentDate': debt.paymentDate,
      'isSettled': debt.isSettled,
      'isFromAutoFix': debt.isFromAutoFix,
      'settlementConfirmed': debt.settlementConfirmed,
      // ✅ الحقول المطلوبة في Appwrite (required=true)
      'vector_clock': '{}',
      'sync_version': debt.version ?? 1,
      'sync_origin': debt.origin ?? 'mobile',
      'sync_vector_clock': '{}',
    };
    _putIfNotNull(data, 'serverId', debt.serverId);
    _putIfNotNull(data, 'deletedAt', debt.deletedAt);
    _putIfNotNull(data, 'bookingLocalId', debt.bookingLocalId);
    _putIfStringNotEmpty(data, 'pledge', debt.pledge);
    _putIfStringNotEmpty(data, 'pledgeType', debt.pledgeType);
    _putIfStringNotEmpty(data, 'note', debt.note);
    _putIfStringNotEmpty(data, 'debtUuid', debt.debtUuid);
    _putIfStringNotEmpty(data, 'hotelDayOpened', debt.hotelDayOpened);
    _putIfStringNotEmpty(data, 'hotelDayClosed', debt.hotelDayClosed);
    return data;
  }

  void _putIfNotNull<T>(Map<String, dynamic> map, String key, T? value) {
    if (value != null) {
      map[key] = value;
    }
  }

  void _putIfStringNotEmpty(
    Map<String, dynamic> map,
    String key,
    String? value,
  ) {
    if (value != null && value.isNotEmpty) {
      map[key] = value;
    }
  }

  /// الحصول على قائمة الأجهزة المسجلة
  Future<List<AppwriteDevice>> getRegisteredDevices() async {
    try {
      final devices = await appwriteService.listDevices(useCache: false);
      return devices.map((doc) => AppwriteDevice.fromJson(doc.data)).toList();
    } catch (e) {
      _logger.error('Failed to get registered devices', error: e, tag: 'SYNC');
      return [];
    }
  }

  /// رفع التغييرات المحلية إلى Appwrite فوراً
  Future<bool> pushLocalChanges() async {
    try {
      final result = await sync(push: true, pull: false);
      return result.status == SyncStatus.success;
    } catch (e, stackTrace) {
      _logger.error(
        'pushLocalChanges failed via sync()',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      return false;
    }
  }

  /// سحب جميع البيانات من Appwrite مع تعطيل Foreign Key لجدول الديون مؤقتاً
  Future<void> pullAllDataWithDisabledFK() async {
    _logger.info(
      '🚀 بدء سحب جميع البيانات مع تعطيل Foreign Keys مؤقتاً...',
      tag: 'SYNC',
    );
    try {
      await database.transaction(() async {
        // تعطيل Foreign Keys مؤقتاً
        await database.customStatement('PRAGMA foreign_keys = OFF');
        _logger.debug('🔓 تم تعطيل Foreign Keys', tag: 'SYNC');

        try {
          // سحب البيانات بنفس ترتيب pullRemoteChanges لضمان الاتساق
          await pullRemoteChanges();
          _logger.info('✅ اكتمل سحب جميع البيانات بنجاح', tag: 'SYNC');
        } finally {
          // إعادة تفعيل Foreign Keys دائماً
          await database.customStatement('PRAGMA foreign_keys = ON');
          _logger.debug('🔒 تم إعادة تفعيل Foreign Keys', tag: 'SYNC');
        }
      });
    } catch (e, stackTrace) {
      _logger.error(
        '❌ فشل سحب البيانات مع تعطيل FK',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      rethrow;
    }
  }

  /// سحب التغييرات من Appwrite باستخدام Field-Level Delta Sync
  /// يُرجع true إذا كانت هناك تغييرات جديدة تم تطبيقها
  Future<bool> pullRemoteChanges() async {
    if (_currentStatus == SyncStatus.syncing) {
      _logger.warning('⏸️ تخطي السحب - المزامنة جارية', tag: 'SYNC');
      return false;
    }

    _isPulling = true;
    final pullStartTime = DateTime.now();
    final pullSyncId = 'appwrite_pull_${DateTime.now().millisecondsSinceEpoch}';
    final syncLogDao = SyncLogDao(database);

    // ✅ تسجيل بداية عملية السحب في SyncLogDao
    try {
      await syncLogDao.logSync(
        syncId: pullSyncId,
        direction: 'pull',
        deviceId: _currentDeviceId ?? 'unknown',
        target: 'Appwrite',
        status: 'in_progress',
      );
    } catch (e) {
      _logger.warning('Failed to log pull start: $e', tag: 'SYNC');
    }

    try {
      _logger.info(
        '📥 سحب التغييرات من Appwrite (Field-Level Delta Sync)...',
        tag: 'SYNC',
      );

      // ✅ تهيئة AppwriteDeltaSync إذا لم يكن مهيأً
      final deltaSync = AppwriteDeltaSync.instance;
      if (!deltaSync.isInitialized) {
        await deltaSync.initialize(appwriteService, database);
      }

      // ✅ استخدام Field-Level Delta Sync للسحب
      final result = await deltaSync.pullDeltaChanges();

      _lastSyncTime = DateTime.now();
      await _saveSettings();

      final pullDuration = DateTime.now().difference(pullStartTime);

      if (result.success) {
        // ✅ تسجيل نجاح عملية السحب في SyncLogDao
        try {
          await syncLogDao.logSync(
            syncId: pullSyncId,
            direction: 'pull',
            deviceId: _currentDeviceId ?? 'unknown',
            target: 'Appwrite',
            status: 'success',
            recordsPulled: result.pulledCount,
            durationMs: pullDuration.inMilliseconds,
          );
        } catch (e) {
          _logger.warning('Failed to log pull result: $e', tag: 'SYNC');
        }

        if (result.pulledCount > 0) {
          _logger.info(
            '✅ تم سحب ${result.pulledCount} سجل من Appwrite (Field-Level)',
            tag: 'SYNC',
          );
          return true;
        } else {
          _logger.info('ℹ️ لا توجد تغييرات جديدة من Appwrite', tag: 'SYNC');
          return false;
        }
      } else {
        // ✅ تسجيل فشل عملية السحب في SyncLogDao
        try {
          await syncLogDao.logSync(
            syncId: pullSyncId,
            direction: 'pull',
            deviceId: _currentDeviceId ?? 'unknown',
            target: 'Appwrite',
            status: 'failed',
            errorMessage: result.message,
            durationMs: pullDuration.inMilliseconds,
          );
        } catch (e) {
          _logger.warning('Failed to log pull failure: $e', tag: 'SYNC');
        }
        return false;
      }
    } catch (e, stackTrace) {
      final pullDuration = DateTime.now().difference(pullStartTime);

      // ✅ تسجيل فشل عملية السحب في SyncLogDao
      try {
        await syncLogDao.logSync(
          syncId: pullSyncId,
          direction: 'pull',
          deviceId: _currentDeviceId ?? 'unknown',
          target: 'Appwrite',
          status: 'failed',
          errorMessage: e.toString(),
          durationMs: pullDuration.inMilliseconds,
        );
      } catch (logError) {
        _logger.warning('Failed to log pull failure: $logError', tag: 'SYNC');
      }

      _logger.error(
        '❌ خطأ في سحب التغييرات من Appwrite',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      return false;
    } finally {
      _isPulling = false;
    }
  }

  /// رفع جميع البيانات المحلية
  Future<void> pushAllLocalData() async {
    _logger.info('Pushing all local data...', tag: 'SYNC');
    await pushLocalChanges();
  }

  /// رفع جميع البيانات المحلية مباشرة إلى Appwrite (بعد الاستعادة من Google Drive)
  Future<Map<String, int>> pushAllLocalDataToAppwrite({
    bool skipDeleted = false, // تغيير إلى false لرفع كل شيء
  }) async {
    _logger.info(
      '🚀 بدء رفع جميع البيانات المحلية إلى Appwrite...',
      tag: 'SYNC',
    );

    final stats = <String, int>{
      'rooms': 0,
      'bookings': 0,
      'booking_notes': 0,
      'booking_nights': 0,
      'employees': 0,
      'expenses': 0,
      'cash_transactions': 0,
      'payments': 0,
      'debts': 0,
      'salary_cycles': 0,
      'salary_payments': 0,
      'salary_withdrawals': 0,
      'shift_notes': 0,
      'booking_price_adjustments': 0,
      'errors': 0,
    };

    try {
      // التأكد من تهيئة الخدمة أولاً
      _logger.info('🔄 تهيئة خدمة Appwrite...', tag: 'SYNC');
      await appwriteService.initialize();

      // التحقق من الاتصال بـ Appwrite
      if (!appwriteService.isInitialized) {
        _logger.error('❌ فشل تهيئة Appwrite', tag: 'SYNC');
        throw Exception('Appwrite service not initialized');
      }

      _logger.info('✅ تم تهيئة Appwrite بنجاح', tag: 'SYNC');
      // رفع الغرف
      final rooms = await database.select(database.rooms).get();
      _logger.info(
        '📦 وُجد ${rooms.length} غرفة في قاعدة البيانات المحلية',
        tag: 'SYNC',
      );
      for (final room in rooms) {
        if (skipDeleted && room.deletedAt != null) continue;
        try {
          final payload = _roomToRemote(room);
          await appwriteService.upsertRoom(room.localUuid, payload);
          stats['rooms'] = (stats['rooms'] ?? 0) + 1;
        } catch (e) {
          _logger.warning(
            'خطأ في رفع غرفة ${room.roomNumber}: $e',
            tag: 'SYNC',
          );
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['rooms']} غرفة من ${rooms.length}',
        tag: 'SYNC',
      );

      // رفع الموظفين
      final employees = await database.select(database.employees).get();
      _logger.info(
        '📦 وُجد ${employees.length} موظف في قاعدة البيانات المحلية',
        tag: 'SYNC',
      );
      for (final employee in employees) {
        if (skipDeleted && employee.deletedAt != null) continue;
        try {
          final payload = _employeeToRemote(employee);
          await appwriteService.upsertEmployee(employee.localUuid, payload);
          stats['employees'] = (stats['employees'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع موظف ${employee.name}: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['employees']} موظف من ${employees.length}',
        tag: 'SYNC',
      );

      // رفع الحجوزات
      final bookings = await database.select(database.bookings).get();
      _logger.info(
        '📦 وُجد ${bookings.length} حجز في قاعدة البيانات المحلية',
        tag: 'SYNC',
      );
      for (final booking in bookings) {
        if (skipDeleted && booking.deletedAt != null) continue;
        try {
          final payload = _bookingToRemote(booking);
          await appwriteService.upsertBooking(booking.localUuid, payload);
          stats['bookings'] = (stats['bookings'] ?? 0) + 1;
        } catch (e) {
          _logger.warning(
            'خطأ في رفع حجز ${booking.guestName}: $e',
            tag: 'SYNC',
          );
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['bookings']} حجز من ${bookings.length}',
        tag: 'SYNC',
      );

      // رفع المصروفات
      final expenses = await database.select(database.expenses).get();
      for (final expense in expenses) {
        if (skipDeleted && expense.deletedAt != null) continue;
        try {
          final payload = _expenseToRemote(expense);
          await appwriteService.upsertExpense(expense.localUuid, payload);
          stats['expenses'] = (stats['expenses'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع مصروف: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['expenses']} مصروف', tag: 'SYNC');

      // رفع المدفوعات
      final payments = await database.select(database.payments).get();
      _logger.info(
        '📦 وُجد ${payments.length} دفعة في قاعدة البيانات المحلية',
        tag: 'SYNC',
      );
      for (final payment in payments) {
        if (skipDeleted && payment.deletedAt != null) continue;
        try {
          final payload = _paymentToRemote(payment);
          await appwriteService.upsertPayment(payment.localUuid, payload);
          stats['payments'] = (stats['payments'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع دفعة: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['payments']} دفعة من ${payments.length}',
        tag: 'SYNC',
      );

      // رفع الديون
      final debts = await database.select(database.debts).get();
      for (final debt in debts) {
        if (skipDeleted && debt.deletedAt != null) continue;
        try {
          final payload = _debtToRemote(debt);
          await appwriteService.upsertDebt(debt.localUuid, payload);
          stats['debts'] = (stats['debts'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع دين: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['debts']} دين', tag: 'SYNC');

      // رفع ملاحظات الحجوزات
      final bookingNotes = await database.select(database.bookingNotes).get();
      for (final note in bookingNotes) {
        if (skipDeleted && note.deletedAt != null) continue;
        try {
          final payload = _bookingNoteToRemote(note);
          await appwriteService.upsertBookingNote(note.localUuid, payload);
          stats['booking_notes'] = (stats['booking_notes'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع ملاحظة حجز: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['booking_notes']} ملاحظة حجز',
        tag: 'SYNC',
      );

      // رفع ليالي الحجوزات
      final bookingNights = await database.select(database.bookingNights).get();
      for (final night in bookingNights) {
        if (skipDeleted && night.deletedAt != null) continue;
        try {
          final payload = _bookingNightToRemote(night);
          await appwriteService.upsertBookingNight(night.localUuid, payload);
          stats['booking_nights'] = (stats['booking_nights'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع ليلة حجز: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['booking_nights']} ليلة حجز', tag: 'SYNC');

      // رفع المعاملات النقدية
      final cashTransactions = await database
          .select(database.cashTransactions)
          .get();
      for (final transaction in cashTransactions) {
        if (skipDeleted && transaction.deletedAt != null) continue;
        try {
          final payload = _cashTransactionToRemote(transaction);
          await appwriteService.upsertCashTransaction(
            transaction.localUuid,
            payload,
          );
          stats['cash_transactions'] = (stats['cash_transactions'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع معاملة نقدية: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['cash_transactions']} معاملة نقدية',
        tag: 'SYNC',
      );

      // رفع دورات الرواتب
      final salaryCycles = await database.select(database.salaryCycles).get();
      for (final cycle in salaryCycles) {
        if (skipDeleted && cycle.deletedAt != null) continue;
        try {
          final payload = _salaryCycleToRemote(cycle);
          await appwriteService.upsertSalaryCycle(cycle.localUuid, payload);
          stats['salary_cycles'] = (stats['salary_cycles'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع دورة راتب: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['salary_cycles']} دورة راتب', tag: 'SYNC');

      // رفع دفعات الرواتب
      final salaryPayments = await database
          .select(database.salaryPayments)
          .get();
      for (final payment in salaryPayments) {
        if (skipDeleted && payment.deletedAt != null) continue;
        try {
          final payload = _salaryPaymentToRemote(payment);
          await appwriteService.upsertSalaryPayment(payment.localUuid, payload);
          stats['salary_payments'] = (stats['salary_payments'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع دفعة راتب: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['salary_payments']} دفعة راتب',
        tag: 'SYNC',
      );

      // رفع سحوبات الرواتب
      final salaryWithdrawals = await database
          .select(database.salaryWithdrawals)
          .get();
      for (final item in salaryWithdrawals) {
        if (skipDeleted && item.deletedAt != null) continue;
        try {
          final payload = _adapterRegistry.salaryWithdrawals.adapter.toJson(
            item,
            src: Source.appwrite,
          );
          await appwriteService.upsertSalaryWithdrawal(item.localUuid, payload);
          stats['salary_withdrawals'] = (stats['salary_withdrawals'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع سحب راتب: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['salary_withdrawals']} سحب راتب',
        tag: 'SYNC',
      );

      // رفع ملاحظات الشيفت
      final shiftNotes = await database.select(database.shiftNotes).get();
      for (final item in shiftNotes) {
        if (skipDeleted && item.deletedAt != null) continue;
        try {
          final payload = _shiftNoteToRemote(item);
          await appwriteService.upsertShiftNote(item.localUuid, payload);
          stats['shift_notes'] = (stats['shift_notes'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع ملاحظة شيفت: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['shift_notes']} ملاحظة شيفت', tag: 'SYNC');

      // رفع تعديلات أسعار الحجوزات
      final adjustments = await database
          .select(database.bookingPriceAdjustments)
          .get();
      for (final adj in adjustments) {
        if (skipDeleted && adj.deletedAt != null) continue;
        try {
          final payload = _adapterRegistry.bookingPriceAdjustments.adapter
              .toJson(adj, src: Source.appwrite);
          await appwriteService.upsertDocument(
            collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
            documentId: adj.localUuid,
            data: payload,
          );
          stats['booking_price_adjustments'] =
              (stats['booking_price_adjustments'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع تعديل سعر حجز: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info(
        '✅ تم رفع ${stats['booking_price_adjustments']} تعديل سعر حجز',
        tag: 'SYNC',
      );

      final totalRecords =
          stats['rooms']! +
          stats['bookings']! +
          stats['booking_notes']! +
          stats['booking_nights']! +
          stats['employees']! +
          stats['expenses']! +
          stats['cash_transactions']! +
          stats['payments']! +
          stats['debts']! +
          stats['salary_cycles']! +
          stats['salary_payments']! +
          stats['salary_withdrawals']! +
          stats['shift_notes']! +
          (stats['booking_price_adjustments'] ?? 0);

      _logger.info(
        '✅ اكتمل رفع البيانات: $totalRecords سجل، ${stats['errors']} خطأ',
        tag: 'SYNC',
      );

      return stats;
    } catch (e, stackTrace) {
      _logger.error(
        '❌ خطأ في رفع البيانات إلى Appwrite',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      rethrow;
    }
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _employeeToRemote(Employee employee) {
    final data = <String, dynamic>{
      'name': employee.name,
      'basicSalary': employee.basicSalary,
      'position': employee.position,
      'phone': employee.phone,
      'hireDate': employee.hireDate,
      'status': employee.status,
      'localUuid': employee.localUuid,
      'createdAt': employee.createdAt,
      'updatedAt': employee.updatedAt,
      'lastModified': employee.lastModified,
      'version': employee.version,
      'origin': employee.origin,
    };
    _putIfNotNull(data, 'serverId', employee.serverId);
    _putIfNotNull(data, 'deletedAt', employee.deletedAt);
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _bookingNoteToRemote(BookingNote note) {
    final data = <String, dynamic>{
      'bookingId': note.bookingId,
      'noteText': note.noteText,
      'alertType': note.alertType,
      'isActive': note.isActive,
      'localUuid': note.localUuid,
      'createdAt': note.createdAt,
      'updatedAt': note.updatedAt,
      'lastModified': note.lastModified,
      'version': note.version,
      'origin': note.origin,
      // ✅ الحقول المطلوبة في Appwrite (required=true)
      'bookingUuid': note.localUuid ?? '',
      'note': note.noteText ?? '',
    };
    _putIfNotNull(data, 'serverId', note.serverId);
    _putIfNotNull(data, 'deletedAt', note.deletedAt);
    _putIfStringNotEmpty(data, 'alertUntil', note.alertUntil);
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _bookingNightToRemote(BookingNight night) {
    final data = <String, dynamic>{
      'bookingLocalId': night.bookingLocalId,
      'hotelDayKey': night.hotelDayKey,
      'nightStart': night.nightStart,
      'nightEnd': night.nightEnd,
      'nightlyRate': night.nightlyRate,
      'sequence': night.sequence,
      'isProcessedByAutoFix': night.isProcessedByAutoFix,
      'baseRate': night.baseRate,
      'adjustment': night.adjustment,
      'finalRate': night.finalRate,
      'localUuid': night.localUuid,
      'createdAt': night.createdAt,
      'updatedAt': night.updatedAt,
      'lastModified': night.lastModified,
      'version': night.version,
      'origin': night.origin,
    };
    _putIfNotNull(data, 'serverId', night.serverId);
    _putIfNotNull(data, 'deletedAt', night.deletedAt);
    _putIfStringNotEmpty(
      data,
      'appliedAdjustmentUuid',
      night.appliedAdjustmentUuid,
    );
    _putIfStringNotEmpty(
      data,
      'appliedAdjustmentsJson',
      night.appliedAdjustmentsJson,
    );
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _cashTransactionToRemote(CashTransaction transaction) {
    final data = <String, dynamic>{
      'transactionType': transaction.transactionType,
      'amount': transaction.amount,
      'transactionTime': transaction.transactionTime,
      'localUuid': transaction.localUuid,
      'createdAt': transaction.createdAt,
      'updatedAt': transaction.updatedAt,
      'lastModified': transaction.lastModified,
      'version': transaction.version,
      'origin': transaction.origin,
    };
    _putIfNotNull(data, 'registerId', transaction.registerId);
    _putIfNotNull(data, 'referenceId', transaction.referenceId);
    _putIfNotNull(data, 'createdBy', transaction.createdBy);
    _putIfNotNull(data, 'serverId', transaction.serverId);
    _putIfNotNull(data, 'deletedAt', transaction.deletedAt);
    _putIfStringNotEmpty(data, 'referenceType', transaction.referenceType);
    _putIfStringNotEmpty(data, 'description', transaction.description);
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _salaryCycleToRemote(SalaryCycle cycle) {
    final data = <String, dynamic>{
      'employeeId': cycle.employeeId,
      'cycleKey': cycle.cycleKey,
      'expectedAmount': cycle.expectedAmount,
      'actualPaid': cycle.actualPaid,
      'remainingAmount': cycle.remainingAmount,
      'status': cycle.status,
      'localUuid': cycle.localUuid,
      'createdAt': cycle.createdAt,
      'updatedAt': cycle.updatedAt,
      'lastModified': cycle.lastModified,
      'version': cycle.version,
      'origin': cycle.origin,
      // ✅ استخدام hotelDayStart و hotelDayEnd الموجودين فعلياً
      'startDate': cycle.hotelDayStart ?? '',
      'endDate': cycle.hotelDayEnd ?? '',
    };
    _putIfNotNull(data, 'serverId', cycle.serverId);
    _putIfNotNull(data, 'deletedAt', cycle.deletedAt);
    _putIfStringNotEmpty(data, 'hotelDayStart', cycle.hotelDayStart);
    _putIfStringNotEmpty(data, 'hotelDayEnd', cycle.hotelDayEnd);
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _salaryPaymentToRemote(SalaryPayment payment) {
    final data = <String, dynamic>{
      'cycleId': payment.cycleId,
      'amount': payment.amount,
      'paymentDateIso': payment.paymentDateIso,
      'isAutoGenerated': payment.isAutoGenerated,
      'localUuid': payment.localUuid,
      'createdAt': payment.createdAt,
      'updatedAt': payment.updatedAt,
      'lastModified': payment.lastModified,
      'version': payment.version,
      'origin': payment.origin,
      // ✅ الحقول المطلوبة في Appwrite (required=true) - يجب إرسالها دائماً
      'employeeId': payment.employeeId ?? 0,
      'paymentDate': payment.paymentDateIso ?? DateTime.now().toIso8601String(),
    };
    _putIfNotNull(data, 'serverId', payment.serverId);
    _putIfNotNull(data, 'deletedAt', payment.deletedAt);
    _putIfStringNotEmpty(data, 'hotelDayKey', payment.hotelDayKey);
    _putIfStringNotEmpty(data, 'method', payment.method);
    return data;
  }

  /// ⚠️ DEPRECATED: يستخدم full document payload
  @Deprecated('Use AppwriteDeltaSync for Field-Level Delta Sync')
  Map<String, dynamic> _shiftNoteToRemote(ShiftNote note) {
    // حساب shiftDate من createdAtIso أو createdAt
    String shiftDate;
    if (note.createdAtIso != null && note.createdAtIso!.isNotEmpty) {
      shiftDate = note.createdAtIso!.split('T').first;
    } else {
      shiftDate = DateTime.fromMillisecondsSinceEpoch(
        note.createdAt * 1000,
      ).toIso8601String().split('T').first;
    }

    final data = <String, dynamic>{
      'localUuid': note.localUuid,
      'title': note.title,
      'content': note.content,
      'priority': note.priority,
      'shiftType': note.shiftType,
      'isRead': note.isRead,
      'createdBy': note.createdBy,
      'createdAt': note.createdAt,
      'updatedAt': note.updatedAt,
      'lastModified': note.lastModified,
      'version': note.version,
      'origin': note.origin,
      // ✅ الحقول المطلوبة في Appwrite (required=true)
      'shiftDate': shiftDate,
      'note': note.content ?? note.title ?? '',
    };
    _putIfNotNull(data, 'serverId', note.serverId);
    _putIfNotNull(data, 'deletedAt', note.deletedAt);
    _putIfStringNotEmpty(data, 'expiresAt', note.expiresAt);
    return data;
  }

  Future<bool> _processSalaryPaymentEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteSalaryPayment(entry.localUuid),
      );
      return true;
    }
    final item = await _getSalaryPaymentByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteSalaryPayment(entry.localUuid),
      );
      return true;
    }
    final payload = outboxDao.adapters.salaryPayments.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    await appwriteService.upsertSalaryPayment(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<SalaryPayment?> _getSalaryPaymentByLocalUuid(String uuid) {
    return (database.select(database.salaryPayments)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processCashTransactionEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteCashTransaction(entry.localUuid),
      );
      return true;
    }
    final item = await _getCashTransactionByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteCashTransaction(entry.localUuid),
      );
      return true;
    }

    final payload = outboxDao.adapters.cashTransactions.adapter.toJson(
      item,
      src: Source.appwrite,
    );

    await appwriteService.upsertCashTransaction(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<CashTransaction?> _getCashTransactionByLocalUuid(String uuid) {
    return (database.select(database.cashTransactions)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processShiftNoteEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteShiftNote(entry.localUuid),
      );
      return true;
    }
    final item = await _getShiftNoteByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteShiftNote(entry.localUuid),
      );
      return true;
    }

    final payload = outboxDao.adapters.shiftNotes.adapter.toJson(
      item,
      src: Source.appwrite,
    );

    await appwriteService.upsertShiftNote(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<ShiftNote?> _getShiftNoteByLocalUuid(String uuid) {
    return (database.select(database.shiftNotes)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processEmployeeEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteEmployee(entry.localUuid),
      );
      return true;
    }
    final item = await _getEmployeeByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteEmployee(entry.localUuid),
      );
      return true;
    }
    final payload = outboxDao.adapters.employees.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    await appwriteService.upsertEmployee(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<Employee?> _getEmployeeByLocalUuid(String uuid) {
    return (database.select(database.employees)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processBookingNoteEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteBookingNote(entry.localUuid),
      );
      return true;
    }
    final item = await _getBookingNoteByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteBookingNote(entry.localUuid),
      );
      return true;
    }
    final payload = outboxDao.adapters.bookingNotes.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    // Note: booking notes often part of booking but if synced separately:
    await appwriteService.upsertBookingNote(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<BookingNote?> _getBookingNoteByLocalUuid(String uuid) {
    return (database.select(database.bookingNotes)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processBookingNightEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteBookingNight(entry.localUuid),
      );
      return true;
    }
    final item = await _getBookingNightByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteBookingNight(entry.localUuid),
      );
      return true;
    }
    final payload = outboxDao.adapters.nights.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    await appwriteService.upsertBookingNight(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<BookingNight?> _getBookingNightByLocalUuid(String uuid) {
    return (database.select(database.bookingNights)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processSalaryCycleEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteSalaryCycle(entry.localUuid),
      );
      return true;
    }
    final item = await _getSalaryCycleByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteSalaryCycle(entry.localUuid),
      );
      return true;
    }
    final payload = outboxDao.adapters.salaryCycles.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    await appwriteService.upsertSalaryCycle(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<SalaryCycle?> _getSalaryCycleByLocalUuid(String uuid) {
    return (database.select(database.salaryCycles)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processSalaryWithdrawalEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteSalaryWithdrawal(entry.localUuid),
      );
      return true;
    }
    final item = await _getSalaryWithdrawalByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteSalaryWithdrawal(entry.localUuid),
      );
      return true;
    }
    final payload = outboxDao.adapters.salaryWithdrawals.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    await appwriteService.upsertSalaryWithdrawal(
      item.localUuid,
      _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<SalaryWithdrawal?> _getSalaryWithdrawalByLocalUuid(String uuid) {
    return (database.select(database.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processBookingPriceAdjustmentEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
          documentId: entry.localUuid,
        ),
      );
      return true;
    }
    final item = await _getBookingPriceAdjustmentByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
          documentId: entry.localUuid,
        ),
      );
      return true;
    }
    final payload = outboxDao.adapters.bookingPriceAdjustments.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
      documentId: item.localUuid,
      data: _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<BookingPriceAdjustment?> _getBookingPriceAdjustmentByLocalUuid(
    String uuid,
  ) {
    return (database.select(database.bookingPriceAdjustments)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processPaymentVoidEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: AppwriteConfig.paymentVoidsCollectionId,
          documentId: entry.localUuid,
        ),
      );
      return true;
    }
    final item = await _getPaymentVoidByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: AppwriteConfig.paymentVoidsCollectionId,
          documentId: entry.localUuid,
        ),
      );
      return true;
    }
    final payload = outboxDao.adapters.paymentVoids.adapter.toJson(
      item,
      src: Source.appwrite,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.paymentVoidsCollectionId,
      documentId: item.localUuid,
      data: _addIdempotencyKey(payload, entry),
    );
    return true;
  }

  Future<PaymentVoid?> _getPaymentVoidByLocalUuid(String uuid) {
    return (database.select(database.paymentVoids)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  /// تحميل جميع البيانات من الخادم مع تعطيل القيود الخارجية مؤقتاً
  Future<void> pullAllRemoteData() async {
    _logger.info('Pulling all remote data...', tag: 'SYNC');

    // ✅ استخدام خدمة السحب الشامل الجديدة
    final fullPull = AppwriteFullPull();
    if (!fullPull.isInitialized) {
      await fullPull.initialize(appwriteService, database);
    }

    final result = await fullPull.pullAll();

    if (result.success) {
      _logger.info('✅ ${result.message}', tag: 'SYNC');
    } else {
      _logger.error('❌ ${result.message}', tag: 'SYNC');
    }

    // تحديث وقت آخر مزامنة
    _lastSyncTime = DateTime.now();
    await _saveSettings();
  }

  /// دالة wrapper لتنفيذ المزامنة الكاملة مع تعطيل FOREIGN KEY
  Future<void> startFullSync() async {
    try {
      _logger.info('Disabling FOREIGN KEY constraints for sync', tag: 'SYNC');
      await database.customStatement('PRAGMA foreign_keys=OFF');

      // تنفيذ سحب البيانات الفعلي
      await pullRemoteChanges();

      _logger.info('Full sync completed successfully', tag: 'SYNC');
    } catch (e, stackTrace) {
      _logger.error(
        'Error during startFullSync',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      rethrow;
    } finally {
      _logger.info('Re-enabling FOREIGN KEY constraints', tag: 'SYNC');
      await database.customStatement('PRAGMA foreign_keys=ON');
    }
  }

  /// إعادة تعيين حالة المزامنة
  Future<void> resetSyncState() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('appwrite_last_sync_time');
    _lastSyncTime = null;
    _logger.info('Sync state reset', tag: 'SYNC');
  }

  // Getters
  SyncStatus get currentStatus => _currentStatus;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get currentDeviceId => _currentDeviceId;
  bool get isSyncing => _currentStatus == SyncStatus.syncing;

  // ---------------------------------------------------------------------------
  // Sync Helpers for Additional Entities
  // ---------------------------------------------------------------------------

  Future<int> _syncShiftNotes(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.shiftNotes.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync shift note ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<int> _syncBookingNotes(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.bookingNotes.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync booking note ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<int> _syncBookingNights(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.nights.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync booking night ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<int> _syncCashTransactions(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.cashTransactions.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync cash transaction ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<int> _syncSalaryCycles(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.salaryCycles.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync salary cycle ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<int> _syncSalaryPayments(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        await _adapterRegistry.salaryPayments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync salary payment ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<int> _syncBookingPriceAdjustments(
    List<models.Document> documents,
  ) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        final result = await _adapterRegistry.bookingPriceAdjustments
            .upsertFromJson(data, src: Source.appwrite);

        // Refresh calculations for the affected booking
        if (result > 0) {
          final adj = await (database.select(
            database.bookingPriceAdjustments,
          )..where((t) => t.id.equals(result))).getSingleOrNull();

          if (adj != null && adj.bookingLocalId != null) {
            await _bookingsRepository.derivedFields.refreshForBookingId(
              adj.bookingLocalId!,
            );
          }
        }

        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync booking price adjustment ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  String _resolveDeviceType() {
    if (kIsWeb) {
      return 'web';
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return 'fuchsia';
    }
  }
}
