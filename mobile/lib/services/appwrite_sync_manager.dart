// ignore_for_file: unused_field, use_late_for_private_fields_and_variables, duplicate_ignore

import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:appwrite/models.dart' as models;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

import '../utils/app_logger.dart';
import '../utils/id.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/salary_withdrawals_adapter.dart';
import 'adapters/source.dart';
import 'appwrite_config.dart';
import 'appwrite_error_handler.dart';
import 'appwrite_logger.dart';
import 'appwrite_models.dart';
import 'appwrite_service.dart';
import 'appwrite_sync_utils.dart';
import 'booking_derived_fields_service.dart';
import 'crashlytics_service.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'repositories/bookings_repository.dart';
import 'repositories/rooms_repository.dart';
import 'sync_constants.dart';
import 'sync_core/sync_error_service.dart';
import 'sync_core/sync_metrics.dart';
import 'sync_core/sync_pull_service.dart';
import 'sync_core/sync_push_service.dart';
import 'sync_enums.dart';
import 'sync_locks.dart';
import 'telegram/whatsapp_notification_service.dart';

// SyncStatus is now defined in sync_enums.dart
export 'sync_enums.dart' show SyncStatus;

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
    _roomsRepository = RoomsRepository(database);
    _pushService = SyncPushService(
      appwriteService: appwriteService,
      database: database,
      outboxDao: outboxDao,
      adapterRegistry: _adapterRegistry,
      bookingsRepository: _bookingsRepository,
      roomsRepository: _roomsRepository,
      errorService: _err,
    );
    _pullService = SyncPullService(
      appwriteService: appwriteService,
      database: database,
      outboxDao: outboxDao,
      adapterRegistry: _adapterRegistry,
      bookingsRepository: _bookingsRepository,
      roomsRepository: _roomsRepository,
      errorService: _err,
    );
  }
  static AppwriteSyncManager? _instance;

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  late final BookingsRepository _bookingsRepository;
  late final RoomsRepository _roomsRepository;
  late final AdapterRegistry _adapterRegistry;

  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();
  final _err = SyncErrorService(tag: 'SYNC');
  SyncPushService? _pushService;
  SyncPullService? _pullService;

  Timer? _syncTimer;
  Timer? _debouncePushTimer;
  Timer? _failedRetryTimer;
  Timer? _cleanupTimer;
  Timer? _stuckRecoveryTimer;
  double _adaptiveBatchSize = 50;
  StreamSubscription<void>? _outboxSubscription;
  Duration _debounceWindow = SyncConstants.outboxDebounceWindow;
  SyncStatus _currentStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _currentDeviceId;
  String? _deviceLocalUuid;
  int? _deviceVersion;
  int? _deviceCreatedAtEpoch;
  String? _fcmToken; // توكن FCM للإشعارات بين الأجهزة
  bool? _remoteEpochIsMillis;

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

      // ─── مؤقت إعادة محاولة العناصر الفاشلة كل 5 دقائق ───
      _startFailedRetryTimer();

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
      await CrashlyticsService.instance.recordFatalSyncError(
        operation: 'sync_initialize',
        error: e,
        stackTrace: stackTrace,
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

      // ✅ إصلاح حرج: انتظر حتى يتم تفريغ outbox أولاً
      // إذا كان outbox يحتوي على تغييرات (مثل تسجيل خروج نزيل)،
      // يجب رفعها أولاً عبر _pushAllEntities قبل الرفع الأولي
      // لأن pushAllLocalDataToAppwrite يقرأ البيانات من DB مباشرة
      // وقد يرفع بيانات قديمة (قبل تسجيل الخروج) فوق البيانات المحدثة
      final outboxCount = await outboxDao.count();
      if (outboxCount > 0) {
        _logger.info(
          '⏳ outbox يحتوي على $outboxCount عنصر — رفعها أولاً قبل الرفع الأولي',
          tag: 'SYNC',
        );
        await _pushAllEntities();
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
      await CrashlyticsService.instance.recordSyncError(
        operation: 'initial_seed',
        error: e.toString(),
        stackTrace: stackTrace,
      );
    }
  }

  /// تحميل الإعدادات
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    // قراءة الإعدادات المحفوظة (بدون تغييرها)
    _currentDeviceId = prefs.getString('appwrite_device_id');
    AppwriteSyncManager.updateStaticDeviceId(_currentDeviceId);

    final lastSyncEpoch = prefs.getInt('appwrite_last_sync_time');
    _lastSyncTime = lastSyncEpoch != null
        ? DateTime.fromMillisecondsSinceEpoch(lastSyncEpoch)
        : null;

    _deviceLocalUuid = prefs.getString('appwrite_device_local_uuid');
    _deviceVersion = prefs.getInt('appwrite_device_version');
    _deviceCreatedAtEpoch = prefs.getInt('appwrite_device_created_at');
    _fcmToken = prefs.getString('fcm_token');
  }

  /// تعيين توكن FCM (يُستدعى من FcmService بعد الحصول على التوكن)
  Future<void> setFcmToken(String token) async {
    _fcmToken = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('fcm_token', token);

    // إذا كان الجهاز مسجلاً، نحدث التوكن على السيرفر
    if (_currentDeviceId != null) {
      try {
        await appwriteService.updateDocument(
          collectionId: AppwriteConfig.devicesCollectionId,
          documentId: _currentDeviceId!,
          data: {
            'fcmToken': token,
            'fcmTokenUpdatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
          },
        );
      } catch (e) {
        debugPrint('⚠️ Failed to update FCM token: $e');
      }
    }
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
        await SyncLocks.appwriteSyncLock.synchronized(() async {
          final existingDoc = await appwriteService.getDocument(
            collectionId: AppwriteConfig.devicesCollectionId,
            documentId: _currentDeviceId!,
          );
          final currentRemoteVersion = _asInt(
            existingDoc.data['version'],
          );
          if (_deviceVersion == null ||
              _deviceVersion! <= currentRemoteVersion) {
            _deviceVersion = currentRemoteVersion + 1;
          }

          await appwriteService.updateDocument(
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
              // ✅ الحقول المطلوبة في Appwrite Cloud
              'deviceId': _deviceLocalUuid,
              'isActive': true,
              // FCM token
              if (_fcmToken != null) 'fcmToken': _fcmToken,
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
          // ✅ الحقول المطلوبة في Appwrite Cloud
          'deviceId': _deviceLocalUuid,
          'isActive': true,
          // FCM token
          if (_fcmToken != null) 'fcmToken': _fcmToken,
        });

        _currentDeviceId = device.$id;
        AppwriteSyncManager.updateStaticDeviceId(_currentDeviceId);
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

  /// مؤقت إعادة محاولة العناصر الفاشلة — كل 5 دقائق يفحص ويعيد المحاولة
  void _startFailedRetryTimer() {
    _failedRetryTimer?.cancel();
    _failedRetryTimer = Timer.periodic(
      const Duration(minutes: 5),
      (_) async {
        try {
          final failedCount = await outboxDao.count();
          if (failedCount == 0) return;

          // إعادة تعيين العناصر الفاشلة إلى pending مع backoff
          final resetCount = await outboxDao.retryFailedWithBackoff(

          );
          if (resetCount == 0) return;

          debugPrint(
            '🔄 إعادة محاولة العناصر الفاشلة في outbox (عدد: $resetCount)',
          );

          // محاولة رفعها فوراً
          final result = await sync(pull: false);
          if (result.status == SyncStatus.success) {
            debugPrint('✅ نجحت إعادة محاولة رفع العناصر الفاشلة');
          }
        } catch (e) {
          debugPrint('⚠️ فشلت إعادة محاولة العناصر الفاشلة: $e');
        }
      },
    );
    debugPrint('🔄 تم تشغيل مؤقت إعادة محاولة العناصر الفاشلة (كل 5 دقائق)');

    // ✅ إصلاح حرج (audit agent-6): استعادة stuck 'processing' entries بشكل دوري
    // المشكلة: cleanupStuckEntries كان يُستدعى فقط عند initialize() (مرة واحدة عند بدء التطبيق)
    // بعدها، أي entry يعلق في 'processing' (بسبب crash أو timeout) يبقى غير مرئي
    // لـ takeBatch (الذي يجلب فقط 'pending') → فقدان صامت للبيانات حتى إعادة
    // تشغيل التطبيق بعد >5 دقائق.
    // الحل: تشغيل cleanupStuckEntries كل دقيقة بعتبة 60 ثانية (أقصر من الـ 5 دقائق
    // السابقة) لاستعادة العناصر العالقة بسرعة.
    _stuckRecoveryTimer?.cancel();
    _stuckRecoveryTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) async {
        try {
          final recovered = await outboxDao.cleanupStuckEntries();
          if (recovered > 0) {
            _logger.info(
              '🔧 تم استعادة $recovered عنصر عالق في outbox من "processing" إلى "pending"',
              tag: 'SYNC',
            );
          }
        } catch (e) {
          _logger.warning('⚠️ فشل استعادة العناصر العالقة: $e', tag: 'SYNC');
        }
      },
    );
    debugPrint('🔧 تم تشغيل مؤقت استعادة العناصر العالقة (كل دقيقة)');

    // ✅ تنظيف outbox تلقائي كل 24 ساعة
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(const Duration(hours: 24), (_) async {
      try {
        await outboxDao.cleanupCompleted();
        await outboxDao.cleanupOrphanedEntries();
      } catch (e) {
        _logger.warning('⚠️ فشل تنظيف outbox الدوري: $e', tag: 'SYNC');
      }
    });
  }

  /// تمكين الدفع المؤجل بعد تغييرات outbox
  void _enableDebouncedPush({Duration? window}) {
    if (window != null) {
      _debounceWindow = window;
    }
    _outboxSubscription?.cancel();
    _outboxSubscription = database.select(database.outbox).watch().listen(
      (_) {
        _debouncePushTimer?.cancel();
        _debouncePushTimer = Timer(_debounceWindow, () async {
          _logger.debug('Debounced push triggered', tag: 'SYNC');
          try {
            final result = await sync(pull: false);
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
      onError: (Object e, StackTrace stackTrace) {
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
  void dispose() {
    _syncTimer?.cancel();
    _debouncePushTimer?.cancel();
    _failedRetryTimer?.cancel();
    _cleanupTimer?.cancel();
    _stuckRecoveryTimer?.cancel();
    _outboxSubscription?.cancel();
    stopAutoSync();
    _syncController.close();
  }

  /// دورة المزامنة الكاملة مع Appwrite:
  /// - تتحقق من الاتصال بالشبكة
  /// - تنشئ سجل في sync_logs (start)
  /// - Push: تفرّغ outbox إلى Appwrite
  /// - Pull: تسحب collections (rooms → bookings → employees → expenses → payments → debts)
  /// - تحدّث sync_logs (completed/failed) وتخزّن آخر وقت مزامنة محلياً
  ///
  /// الدالة لا ترمي عادةً استثناءات، وتعيد SyncResult مع status/errorMessage.
  Future<SyncResult> sync({bool push = true, bool pull = true}) async {
    if (_currentStatus == SyncStatus.syncing) {
      _logger.warning('Sync already in progress', tag: 'SYNC');
      return SyncResult(
        status: SyncStatus.failed,
        errorMessage: 'Sync already in progress',
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
    }

    try {
      return await SyncLocks.appwriteSyncLock.synchronized(() async {
    _currentStatus = SyncStatus.syncing;
    _syncController.add(_currentStatus);

    final startTime = DateTime.now();

    final metrics = SyncMetrics.instance;
    metrics.startSync();

    final phaseMs = <String, int>{};
    int recordsPushed = 0;
    int recordsPulled = 0;
    const int conflicts = 0;
    String? errorMessage;
    SyncStatus finalStatus = SyncStatus.success;
    late String syncLogId;
    late String syncLogLocalUuid;
    int syncLogVersion = 1;
    bool hasSyncLog = false;
    int? syncLogCreatedEpoch;

    try {
      _logger.info('Starting sync...', tag: 'SYNC');

      // التحقق من الاتصال
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        throw Exception('No internet connection');
      }

      // ✅ تسجيل الجهاز تلقائياً إذا لم يكن مسجلاً بعد
      if (_currentDeviceId == null) {
        try {
          await registerDevice();
        } catch (e) {
          _logger.warning('تسجيل الجهاز فشل، سنستخدم معرف محلي: $e', tag: 'SYNC');
        }
      }

      // ✅ استخدام معرف محلي كـ fallback إذا فشل تسجيل الجهاز
      final effectiveDeviceId = _currentDeviceId ?? _getLocalDeviceId() ?? 'unknown'; // ignore: dead_null_aware_expression

      // إنشاء سجل مزامنة
      syncLogLocalUuid = IdGen.uuid();
      syncLogCreatedEpoch = Time.nowEpoch();

      final syncLog = await appwriteService.createSyncLog({
        'deviceId': effectiveDeviceId,
        'operation': push && pull
            ? 'full'
            : push
            ? 'push'
            : pull
            ? 'pull'
            : 'noop',
        'collection': push && pull
            ? 'all'
            : push
            ? 'bookings'
            : pull
            ? 'all'
            : 'none',
        'syncType': push && pull
            ? 'full'
            : push
            ? 'push'
            : pull
            ? 'pull'
            : 'noop',
        'startTime': startTime.toIso8601String(),
        'status': SyncLogStatus.inProgress.value,
        'action': 'sync_start',
        'details': '{"recordsPushed":0,"recordsPulled":0,"conflicts":0}',
        'timestamp': syncLogCreatedEpoch,
        'localUuid': syncLogLocalUuid,
        'createdAt': syncLogCreatedEpoch,
        'updatedAt': syncLogCreatedEpoch,
        'lastModified': syncLogCreatedEpoch,
        'version': syncLogVersion,
        'origin': 'mobile',
      });
      syncLogId = syncLog.$id;
      hasSyncLog = true;

      if (push) {
        recordsPushed += await _timePhase(
          'pushAllEntities',
          _pushAllEntities,
          phaseMs,
        );

        // رفع إعدادات الواتساب إلى Appwrite (يدفع من SharedPreferences → السحابة)
        try {
          recordsPushed += await _timePhase('pushAppSettings', () async {
            final pushed = await _pushAppSettingsToCloud();
            if (pushed) {
              _logger.debug('WhatsApp settings pushed to cloud', tag: 'SYNC');
              return 1;
            }
            return 0;
          }, phaseMs,);
        } catch (e, st) {
          _logger.error('❌ فشل رفع app_settings', error: e, stackTrace: st, tag: 'SYNC');
        }
      }

      if (pull) {
        // ✅ إصلاح حرج: لا نعطل PRAGMA foreign_keys أثناء السحب
        // تعطيلها كان يسمح بإدخال سجلات أبناء بدون آباء (مدفوعات بدون حجوزات)
        // مما يسبب انتهاكات FK بعد إعادة التفعيل ويجعل نمط التأجيل/إعادة المحاولة بلا فائدة
        // ترتيب السحب (غرف → حجوزات → مدفوعات) يضمن وجود الآباء قبل الأبناء
        // ونمط التأجيل في _syncPayments/_syncDebts يعالج الحالات الاستثنائية
        try {
          _logger.info('📥 سحب التغييرات من Appwrite...', tag: 'SYNC');
          final failedCollections = <String>[];

          // Delta Sync: قراءة آخر timestamp وإنشاء فلتر
          final lastPullTs = await _getLastPullTs();
          final List<String> deltaQ = await (_pullService?.buildDeltaQueries(lastPullTs) ?? <String>[]);
          final isDelta = deltaQ.isNotEmpty;
          if (isDelta) {
            _logger.info(
              '🔄 Delta Sync: جلب التغييرات منذ ${DateTime.fromMillisecondsSinceEpoch(lastPullTs * 1000).toIso8601String()}',
              tag: 'SYNC',
            );
          } else {
            _logger.info('🔄 Full Sync: أول مزامنة أو إعادة كاملة', tag: 'SYNC');
          }

          // مزامنة كل كولكشن بشكل مستقل — فشل واحد لا يوقف الباقي
          // ✅ ترتيب السحب محسّن حسب علاقات FK:
          // rooms ← bookings.roomNumber
          // employees ← salary_cycles.employeeId, salary_withdrawals.employeeId
          // bookings ← booking_nights.bookingLocalId, booking_notes.bookingId, payments.bookingLocalId, debts.bookingLocalId
          // cash_transactions ← payments.cashTransactionLocalId
          // salary_cycles ← salary_payments.cycleId

          try {
            recordsPulled += await _timePhase('syncRooms', () async {
              final rooms = await appwriteService.listRooms(queries: deltaQ, useCache: false);
              final roomsSynced = await _syncRooms(rooms);
              _logger.debug('Synced $roomsSynced rooms', tag: 'SYNC');
              return roomsSynced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('rooms');
            _logger.error('❌ فشل سحب rooms', error: e, stackTrace: st, tag: 'SYNC');
            await CrashlyticsService.instance.recordSyncError(
              operation: 'pull_rooms', error: e.toString(), stackTrace: st, context: {'phase': 'sync'},
            );
          }

          try {
            recordsPulled += await _timePhase('syncEmployees', () async {
              final employees = await appwriteService.listEmployees(
                queries: deltaQ,
                useCache: false,
              );
              final employeesSynced = await _syncEmployees(employees);
              _logger.debug('Synced $employeesSynced employees', tag: 'SYNC');
              return employeesSynced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('employees');
            _logger.error('❌ فشل سحب employees', error: e, stackTrace: st, tag: 'SYNC');
            await CrashlyticsService.instance.recordSyncError(
              operation: 'pull_employees', error: e.toString(), stackTrace: st, context: {'phase': 'sync'},
            );
          }

          try {
            recordsPulled += await _timePhase('syncBookings', () async {
              final bookings = await appwriteService.listBookings(queries: deltaQ, useCache: false);
              final bookingsSynced = await _syncBookings(bookings);
              _logger.debug('Synced $bookingsSynced bookings', tag: 'SYNC');
              return bookingsSynced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('bookings');
            _logger.error('❌ فشل سحب bookings', error: e, stackTrace: st, tag: 'SYNC');
            await CrashlyticsService.instance.recordSyncError(
              operation: 'pull_bookings', error: e.toString(), stackTrace: st,
              severity: CrashlyticsSeverity.fatal, context: {'phase': 'sync'},
            );
          }

          try {
            recordsPulled += await _timePhase('syncCashTransactions', () async {
              final cashTransactions = await appwriteService.listCashTransactions(queries: deltaQ, useCache: false);
              final synced = await _syncCashTransactions(cashTransactions);
              _logger.debug('Synced $synced cash transactions', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('cash_transactions');
            _logger.error('❌ فشل سحب cash_transactions', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncExpenses', () async {
              final expenses = await appwriteService.listExpenses(queries: deltaQ, useCache: false);
              final expensesSynced = await _syncExpenses(expenses);
              _logger.debug('Synced $expensesSynced expenses', tag: 'SYNC');
              return expensesSynced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('expenses');
            _logger.error('❌ فشل سحب expenses', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncBookingNights', () async {
              // booking_nights يستخدم lastPullTs خاص به (مستقل عن باقي الجداول)
              final nightsPullTs = await _getBookingNightsPullTs();
              final bool remoteEpochIsMillis = await (_pullService?.isRemoteEpochMillis() ?? false);
              final nightsDeltaQ = _bookingNightsDeltaQueries(
                nightsPullTs,
                remoteEpochIsMillis: remoteEpochIsMillis,
              );
              if (nightsDeltaQ.isNotEmpty) {
                _logger.info(
                  '🔄 booking_nights Delta: جلب التغييرات منذ ${DateTime.fromMillisecondsSinceEpoch(nightsPullTs * 1000).toIso8601String()}',
                  tag: 'SYNC',
                );
              }
              final bookingNights = await appwriteService.listBookingNights(queries: nightsDeltaQ, useCache: false);
              final synced = await _syncBookingNights(bookingNights);
              // تحديث lastPullTs الخاص بـ booking_nights بعد نجاح السحب
              await _updateBookingNightsPullTs(Time.nowEpoch());
              _logger.debug('Synced $synced booking nights', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('booking_nights');
            _logger.error('❌ فشل سحب booking_nights', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncBookingNotes', () async {
              final bookingNotes = await appwriteService.listBookingNotes(queries: deltaQ, useCache: false);
              final synced = await _syncBookingNotes(bookingNotes);
              _logger.debug('Synced $synced booking notes', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('booking_notes');
            _logger.error('❌ فشل سحب booking_notes', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncPayments', () async {
              final payments = await appwriteService.listPayments(queries: deltaQ, useCache: false);
              final paymentsSynced = await _syncPayments(payments);
              _logger.debug('Synced $paymentsSynced payments', tag: 'SYNC');
              return paymentsSynced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('payments');
            _logger.error('❌ فشل سحب payments', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncDebts', () async {
              final debts = await appwriteService.listDebts(queries: deltaQ, useCache: false);
              final debtsSynced = await _syncDebts(debts);
              _logger.debug('Synced $debtsSynced debts', tag: 'SYNC');
              return debtsSynced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('debts');
            _logger.error('❌ فشل سحب debts', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncSalaryCycles', () async {
              final salaryCycles = await appwriteService.listSalaryCycles(queries: deltaQ, useCache: false);
              final synced = await _syncSalaryCycles(salaryCycles);
              _logger.debug('Synced $synced salary_cycles', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('salary_cycles');
            _logger.error('❌ فشل سحب salary_cycles', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncSalaryPayments', () async {
              final salaryPayments = await appwriteService.listSalaryPayments(queries: deltaQ, useCache: false);
              final synced = await _syncSalaryPayments(salaryPayments);
              _logger.debug('Synced $synced salary_payments', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('salary_payments');
            _logger.error('❌ فشل سحب salary_payments', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncSalaryWithdrawals', () async {
              final salaryWithdrawals = await appwriteService.listSalaryWithdrawals(queries: deltaQ, useCache: false);
              final synced = await _syncSalaryWithdrawals(salaryWithdrawals);
              _logger.debug('Synced $synced salary_withdrawals', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('salary_withdrawals');
            _logger.error('❌ فشل سحب salary_withdrawals', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncGuestInfos', () async {
              final guestInfos = await appwriteService.listGuestInfos(queries: deltaQ, useCache: false);
              final synced = await _syncGuestInfos(guestInfos);
              _logger.debug('Synced $synced guest_infos', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('guest_infos');
            _logger.error('❌ فشل سحب guest_infos', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncBookingPriceAdjustments', () async {
              final adjustments = await appwriteService.listDocuments(
                collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
                queries: deltaQ,
              );
              final adjustmentsSynced = await _syncBookingPriceAdjustments(adjustments);
              _logger.debug('Synced $adjustmentsSynced booking price adjustments', tag: 'SYNC');
              return adjustmentsSynced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('booking_price_adjustments');
            _logger.error('❌ فشل سحب booking_price_adjustments', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncShiftNotes', () async {
              final shiftNotes = await appwriteService.listShiftNotes(queries: deltaQ, useCache: false);
              final synced = await _syncShiftNotes(shiftNotes);
              _logger.debug('Synced $synced shift notes', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('shift_notes');
            _logger.error('❌ فشل سحب shift_notes', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncBlacklist', () async {
              final blacklistDocs = await appwriteService.listBlacklist(queries: deltaQ, useCache: false);
              final synced = await _syncBlacklist(blacklistDocs);
              _logger.debug('Synced $synced blacklist entries', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('blacklist');
            _logger.error('❌ فشل سحب blacklist', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncPriceAdjustments', () async {
              final docs = await appwriteService.listDocuments(
                collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
                queries: deltaQ,
              );
              final synced = await _syncPriceAdjustments(docs);
              _logger.debug('Synced $synced price adjustments', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('price_adjustments');
            _logger.error('❌ فشل سحب price_adjustments', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncAuditLogs', () async {
              final docs = await appwriteService.listDocuments(
                collectionId: AppwriteConfig.auditLogsCollectionId,
                queries: deltaQ,
              );
              final synced = await _syncAuditLogs(docs);
              _logger.debug('Synced $synced audit logs', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('audit_logs');
            _logger.error('❌ فشل سحب audit_logs', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            recordsPulled += await _timePhase('syncPaymentVoids', () async {
              final docs = await appwriteService.listDocuments(
                collectionId: AppwriteConfig.paymentVoidsCollectionId,
                queries: deltaQ,
              );
              final synced = await _syncPaymentVoids(docs);
              _logger.debug('Synced $synced payment voids', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e, st) {
            failedCollections.add('payment_voids');
            _logger.error('❌ فشل سحب payment_voids', error: e, stackTrace: st, tag: 'SYNC');
          }

          // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته

          // مزامنة إعدادات الواتساب (app_settings) — غير حرجة، لا تمنع Delta Sync
          // ⚠️ app_settings لا يحتوي على حقل lastModified، لذا نستخدم queries فارغة
          // (full pull) بدلاً من deltaQ لتجنب خطأ "Attribute not found in schema"
          try {
            recordsPulled += await _timePhase('syncAppSettings', () async {
              final docs = await appwriteService.listDocuments(
                collectionId: 'app_settings',
                queries: <String>[], // بدون delta filter - app_settings لا يملك lastModified
              );
              final synced = await _syncAppSettings(docs);
              _logger.debug('Synced $synced app_settings', tag: 'SYNC');
              return synced;
            }, phaseMs,);
          } catch (e) {
            // ⚠️ app_settings غير حرجة — لا تمنع تحديث lastPullTs
            // إعدادات واتساب ليست بيانات فندقية أساسية
            _logger.warning(
              '⚠️ فشل سحب app_settings (غير حرج — لن يؤثر على Delta Sync): $e',
              tag: 'SYNC',
            );
          }

          // تحديث lastPullTs فقط إذا نجحت كل الكولكشنات
          // إذا فشل بعضها، لا نحدّث timestamp حتى نتمكن من سحبها في المرة القادمة
          if (failedCollections.isEmpty) {
            await _updateLastPullTs(Time.nowEpoch());
          } else {
            _logger.warning(
              '⚠️ ${failedCollections.length} collections فشل سحبها: ${failedCollections.join(", ")} — لن يتم تحديث lastPullTs',
              tag: 'SYNC',
            );
          }

          // ✅ تنظيف outbox بعد السحب: إذا السحابة أرسلت نفس البيانات المحلية
          // فلا حاجة لإعادة إرسالها عبر outbox — هذا يمنع حلقة المزامنة الدائرية
          try {
            final removed = await _cleanupOutboxAfterPull();
            if (removed > 0) {
              _logger.info(
                '🧹 تم حذف $removed عنصر outbox مطابق للبيانات المسحوبة',
                tag: 'SYNC',
              );
            }
          } catch (e) {
            _logger.warning(
              '⚠️ فشل تنظيف outbox بعد السحب: $e',
              tag: 'SYNC',
            );
          }

          // ✅ تنظيف outbox للكيانات المحذوفة (soft/hard delete)
          try {
            final deletedRemoved = await _cleanupOutboxForDeletedEntities();
            if (deletedRemoved > 0) {
              _logger.info(
                '🧹 تم حذف $deletedRemoved عنصر outbox لكيانات محذوفة',
                tag: 'SYNC',
              );
            }
          } catch (e) {
            _logger.warning(
              '⚠️ فشل تنظيف outbox للكيانات المحذوفة: $e',
              tag: 'SYNC',
            );
          }

          // ✅ إعادة حساب حالة إشغال الغرف بناءً على الحجوزات النشطة
          // هذا يضمن أن الغرف التي تم تسجيل خروج نزلائها تظهر كـ "شاغرة"
          // والغرف التي بها حجوزات نشطة تظهر كـ "محجوزة" - بغض النظر عن
          // حالة الغرفة المخزنة على Appwrite (التي قد تكون قديمة/غير محدثة)
          try {
            await _roomsRepository.refreshAllRoomOccupancy(
              originIsServer: true,
            );
            _logger.info(
              '🔄 تم إعادة حساب حالة إشغال الغرف بعد المزامنة',
              tag: 'SYNC',
            );
          } catch (e, st) {
            _logger.warning(
              '⚠️ فشل إعادة حساب حالة إشغال الغرف: $e',
              tag: 'SYNC',
            );
            await CrashlyticsService.instance.recordSyncError(
              operation: 'refresh_room_occupancy',
              error: e.toString(),
              stackTrace: st,
              context: {'phase': 'post_sync'},
            );
          }
        } finally {
          // ✅ تحقق معزز من سلامة البيانات والمفاتيح الأجنبية بعد المزامنة
          await _performPostSyncIntegrityCheck();
        }
      }

      // تحديث سجل المزامنة
      final endTime = DateTime.now();
      final endEpoch = Time.nowEpoch();
      syncLogVersion += 1;

      if (hasSyncLog) {
        await appwriteService.updateDocument(
          collectionId: AppwriteConfig.syncLogsCollectionId,
          documentId: syncLogId,
          data: {
            'endTime': endTime.toIso8601String(),
            'status': SyncLogStatus.completed.value,
            'action': 'sync_complete',
            'details':
                '{"recordsPushed":$recordsPushed,"recordsPulled":$recordsPulled,"conflicts":$conflicts}',
            'updatedAt': endEpoch,
            'lastModified': endEpoch,
            'timestamp': endEpoch,
            'version': syncLogVersion,
            'localUuid': syncLogLocalUuid,
            'origin': 'mobile',
          },
        );
      }

      _lastSyncTime = endTime;
      await _saveSettings();

      _logger.info(
        'Sync completed successfully (pushed: $recordsPushed, pulled: $recordsPulled)',
        tag: 'SYNC',
      );
    } catch (e, stackTrace) {
      errorMessage = e.toString();
      finalStatus = SyncStatus.failed;

      if (hasSyncLog) {
        final failEpoch = Time.nowEpoch();
        syncLogVersion += 1;
        try {
          await appwriteService.updateDocument(
            collectionId: AppwriteConfig.syncLogsCollectionId,
            documentId: syncLogId,
            data: {
              'status': SyncLogStatus.failed.value,
              'action': 'sync_failed',
              'errorMessage': (() {
                final msg = errorMessage ?? '';
                if (msg.length > SyncConstants.maxErrorMessageLength) {
                  return msg.substring(0, SyncConstants.maxErrorMessageLength);
                }
                return msg;
              })(),
              'details':
                  '{"recordsPushed":$recordsPushed,"recordsPulled":$recordsPulled,"conflicts":$conflicts}',
              'updatedAt': failEpoch,
              'lastModified': failEpoch,
              'timestamp': failEpoch,
              'localUuid': syncLogLocalUuid,
              'origin': 'mobile',
            },
          );
        } catch (logError, logStackTrace) {
          _logger.warning(
            'Failed to update sync log after failure',
            tag: 'SYNC',
            error: logError,
            stackTrace: logStackTrace,
          );
        }
      }

      _errorHandler.handleError(e, context: 'sync()', stackTrace: stackTrace);

      _logger.error(
        'Sync failed',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );

      // Crashlytics + WhatsApp alert على فشل المزامنة الرئيسي
      await CrashlyticsService.instance.recordFatalSyncError(
        operation: 'sync',
        error: e,
        stackTrace: stackTrace,
        context: {
          'recordsPushed': '$recordsPushed',
          'recordsPulled': '$recordsPulled',
          // ignore: dead_null_aware_expression
          'errorMessage': errorMessage ?? '',
        },
      );
      await WhatsAppNotificationService.instance.notifySyncError(
        operation: 'sync',
        // ignore: dead_null_aware_expression
          error: errorMessage ?? e.toString(),
        recordsPushed: recordsPushed,
        recordsPulled: recordsPulled,
      );
    } finally {
      // ✅ إصلاح حرج (audit agent-6): ضمان إعادة ضبط _currentStatus دائماً
      // حتى لو فشل معالج الأخطاء نفسه (مثل CrashlyticsService أو
      // WhatsAppNotificationService). بدون finally، كان _currentStatus
      // يبقى stuck عند 'syncing' → المزامنة التالية ترجع "Sync already in
      // progress" → توقف دائم للمزامنة حتى إعادة تشغيل التطبيق.
      _currentStatus = finalStatus;
      _syncController.add(_currentStatus);
    }

    final endTime = DateTime.now();
    final duration = endTime.difference(startTime);

    if (finalStatus == SyncStatus.success) {
      metrics.recordSuccess(
        recordsSynced: recordsPushed + recordsPulled,
      );
    } else {
      metrics.recordFailure(errorMessage ?? 'Appwrite sync failed');
    }

    try {
      final payload = <String, Object?>{
        'durationMs': duration.inMilliseconds,
        'recordsPushed': recordsPushed,
        'recordsPulled': recordsPulled,
        'conflicts': conflicts,
        'status': finalStatus.name,
        'phasesMs': phaseMs,
      };

      var encoded = jsonEncode(payload, toEncodable: (v) => v.toString());
      if (encoded.length > SyncConstants.maxMetricsPayloadLength) {
        const ellipsis = '…';
        const maxLen = SyncConstants.maxMetricsPayloadLength - ellipsis.length;
        if (maxLen > 0) {
          encoded = String.fromCharCodes(encoded.runes.take(maxLen)) + ellipsis;
        } else {
          encoded = encoded.substring(0, SyncConstants.maxMetricsPayloadLength);
        }
      }

      _logger.debug('Sync metrics: $encoded', tag: 'METRICS');
    } catch (e, stackTrace) {
      _logger.warning(
        'Failed to log sync metrics',
        error: e,
        stackTrace: stackTrace,
        tag: 'METRICS',
      );
    }

    return SyncResult(
      status: finalStatus,
      recordsPushed: recordsPushed,
      recordsPulled: recordsPulled,
      errorMessage: errorMessage,
      timestamp: endTime,
      duration: duration,
    );
      });
    } on TimeoutException {
      _logger.warning('Failed to acquire sync lock', tag: 'SYNC');
      return SyncResult(
        status: SyncStatus.failed,
        errorMessage: 'Sync lock timeout',
        timestamp: DateTime.now(),
        duration: Duration.zero,
      );
    }
  }

  /// الحصول على إحصائيات المزامنة
  Future<Map<String, dynamic>> getSyncStatistics() async {
    try {
      final outboxCount = await outboxDao.count();
      // جلب سجلات المزامنة الخاصة بهذا الجهاز فقط لتقليل حجم البيانات المسحوبة
      final syncLogs = await appwriteService.listSyncLogs(
        queries: [
          if (_currentDeviceId != null) Query.equal('deviceId', _currentDeviceId),
          Query.orderDesc('timestamp'),
          Query.limit(1),
        ],
        useCache: false,
      );

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
          } catch (e, st) {
            AppLogger.warning('سياق مزامنة غير معروف', tag: 'SYNC', error: e, stackTrace: st);
          }
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
        'successRate': totalSyncs > 0
            ? (successfulSyncs / totalSyncs * 100)
            : 0.0,
        'totalRecordsPushed': totalRecordsPushed,
        'totalRecordsPulled': totalRecordsPulled,
        'totalConflicts': totalConflicts,
        'lastSyncTime': _lastSyncTime?.toIso8601String(),
        'outboxCount': outboxCount,
        'lastErrorMessage': lastFailed != null
            ? (lastFailed['errorMessage'] ?? '')
            : null,
        'lastErrorTime': lastFailed != null
            ? (lastFailed['timestamp'] ??
                  lastFailed['endTime'] ??
                  lastFailed['startTime'])
            : null,
        'timeline': timeline,
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
        'lastErrorMessage': null,
        'lastErrorTime': null,
        'timeline': <Map<String, dynamic>>[],
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

  /// ✅ فحص: هل البيانات البعيدة أحدث من المحلية؟
  /// يُستخدم لتخطي التحديث غير الضروري عند سحب بيانات مطابقة من Appwrite.
  /// إذا كان lastModified البعيد <= المحلي، فالبيانات مطابقة أو المحلية أحدث.
  ///
  /// هذا يمنع:
  /// - كتابة غير ضرورية لبيانات مطابقة
  /// - تغيير lastModified المحلي بدون سبب حقيقي
  /// - حلقة المزامنة الدائرية (pull → update → push → pull → ...)
  /// ✅ استخراج $updatedAt من مستند Appwrite وتحويله إلى ثوانٍ epoch.
  ///
  /// $updatedAt هو حقل نظام في Appwrite يتوفر دائماً في كل مستند ويُحدَّث
  /// تلقائياً عند أي تعديل. نستخدمه كمرجع زمني موثوق لفحص التعارضات عندما
  /// يكون lastModified البعيد مفقوداً (وهو ما يحدث في بعض المجموعات مثل
  /// bookings حيث لا يُخزن lastModified في مخطط Appwrite).
  int? _extractUpdatedAtSec(models.Document doc) {
    try {
      final updatedAtStr = doc.$updatedAt;
      if (updatedAtStr.isEmpty) return null;
      final dt = DateTime.parse(updatedAtStr);
      return (dt.millisecondsSinceEpoch / 1000).round();
    } catch (_) {
      return null;
    }
  }

  bool _isRemoteDataNewer(
    Map<String, dynamic> remoteData,
    int? localLastModified, {
    int? localDeletedAt,
    int? remoteUpdatedAtSec,
  }) {
    // ✅ إصلاح: إذا حُذف السجل محلياً (soft delete) وكان الحذف أحدث
    // من البيانات البعيدة، لا نكتب فوق الحذف المحلي — نحمي الحذف
    if (localDeletedAt != null) {
      final remoteDeletedAt = _asIntNullable(remoteData['deletedAt']) ??
          _asIntNullable(remoteData['deleted_at']);
      // إذا كانت البيانات البعيدة أيضاً محذوفة → نتابع (كلاهما محذوف)
      if (remoteDeletedAt != null) {
        return true; // كلاهما محذوف — نسمح بالتحديث
      }
      // البيانات البعيدة غير محذوفة لكن المحلي محذوف — نرفض الكتابة فوق الحذف
      // الحذف المحلي متعمد ويجب أن يكون له أولوية أعلى
      return false;
    }

    if (localLastModified == null) {
      // لا يوجد سجل محلي — البيانات البعيدة "أحدث" (جديدة)
      return true;
    }

    final remoteLastModified = _asIntNullable(remoteData['lastModified']) ??
        _asIntNullable(remoteData['last_modified']) ??
        _asIntNullable(remoteData['lastModifiedEpoch']);

    // ✅ إصلاح حرج لمنع فقدان التحديثات (Lost Update):
    // المنطق السابق كان يرجع true عند غياب lastModified البعيد، مما يسمح
    // للبيانات البعيدة القديمة باستبدال البيانات المحلية الأحدث. هذا يحدث
    // خصوصاً مع مجموعة bookings في Appwrite حيث لا يُخزن lastModified في
    // المخطط. الآن نستخدم $updatedAt (متوفر دائماً في كل مستند Appwrite)
    // كمرجع زمني موثوق بدلاً من إرجاع true بشكل خطير.
    final effectiveRemoteTs = remoteLastModified ?? remoteUpdatedAtSec;

    if (effectiveRemoteTs == null) {
      // ⚠️ لا نعرف عمر البيانات البعيدة على الإطلاق (لا lastModified ولا
      // $updatedAt) — هذا حالة استثنائية نادرة جداً.
      // السياسة الآمنة: لا نستبدل بيانات محلية موجودة ببيانات بعيدة مجهولة العمر.
      // هذا يحمي من فقدان التحديثات المحلية الأحدث.
      _logger.warning(
        '⚠️ _isRemoteDataNewer: لا يوجد lastModified ولا \$updatedAt للبيان البعيد — '
        'الحفاظ على البيانات المحلية (localLastModified=$localLastModified) '
        'لمنع فقدان التحديثات. localUuid=${remoteData['localUuid']}',
        tag: 'SYNC',
      );
      return false;
    }

    // البيانات البعيدة أحدث فقط إذا كان lastModified أكبر من المحلي
    // ✅ استخدام >= بدلاً من > سيتسبب في إعادة كتابة نفس البيان — نستخدم >
    // للسماح بالتحديث فقط عند التأكد من أن البعيد أحدث فعلاً.
    return effectiveRemoteTs > localLastModified;
  }

  Future<int> _syncRooms(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existingRoom = await (database.select(database.rooms)
              ..where((r) => r.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();

        if (!_isRemoteDataNewer(data, existingRoom?.lastModified, localDeletedAt: existingRoom?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue; // البيانات مطابقة أو السجل محذوف محلياً
        }

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
    final affectedRoomNumbers = <String>{};

    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ حفظ حالة الحجز القديمة قبل التحديث لمقارنتها
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existingBooking = await (database.select(database.bookings)
              ..where((b) => b.localUuid.equals(localUuid)))
            .getSingleOrNull();
        final oldStatus = existingBooking?.status;
        final oldRoomNumber = existingBooking?.roomNumber;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        if (!_isRemoteDataNewer(data, existingBooking?.lastModified, localDeletedAt: existingBooking?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue; // البيانات مطابقة أو السجل محذوف محلياً
        }

        // ✅ تسجيل تشخيصي: تسجيل الحقول الحرجة عند السحب من Appwrite
        final remoteStatus = data['status']?.toString();
        final remoteActualCheckout = data['actualCheckout']?.toString();
        final remoteLastModified = data['lastModified'];
        _logger.info(
          '📥 Pull booking ${localUuid.substring(0, 8)}... '
          'status=$remoteStatus '
          'actualCheckout=$remoteActualCheckout '
          'lastModified=$remoteLastModified '
          'existing=${existingBooking != null ? 'yes(status=${existingBooking.status})' : 'no'}',
          tag: 'SYNC',
        );

        await _adapterRegistry.bookings.upsertFromJson(
          data,
          src: Source.appwrite,
        );

        // TRIGGER POST-SYNC PROCESSING
        // 1. Resolve local ID from UUID
        final booking = await (database.select(database.bookings)
              ..where((b) => b.localUuid.equals(localUuid)))
            .getSingleOrNull();

        if (booking != null) {
          // ✅ تسجيل تشخيصي بعد السحب: التحقق من حفظ الحقول الحرجة محلياً
          if (remoteStatus != null && booking.status != remoteStatus) {
            _logger.error(
              '❌ بعد upsert: status محلي=${booking.status} ≠ بعيد=$remoteStatus '
              'booking=${localUuid.substring(0, 8)}... — فقدان بيانات!',
              tag: 'SYNC',
            );
          }
          if (remoteActualCheckout != null &&
              booking.actualCheckout != remoteActualCheckout) {
            _logger.error(
              '❌ بعد upsert: actualCheckout محلي=${booking.actualCheckout} ≠ بعيد=$remoteActualCheckout '
              'booking=${localUuid.substring(0, 8)}... — فقدان بيانات!',
              tag: 'SYNC',
            );
          }

          // 2. Convert legacy discount to adjustments
          await _bookingsRepository.syncLegacyDiscountToAdjustments(booking.id);

          // ✅ 3. Recalculate derived fields — فقط للحجوزات النشطة أو غير المكتملة.
          //
          // منع حرج: لا نستدعي refreshForBookingId للحجوزات المكتملة (التي تمت
          // مغادرتها) لأن:
          //   - جهاز 1: عند _processCheckout، يحدّث الحجز + الغرفة + يرفع البيانات
          //     (بما في ذلك الليالي النهائية) إلى Appwrite Cloud.
          //   - جهاز 2: عند _syncBookings، يستقبل الحجز المكتمل + الليالي من السحابة.
          //     إذا استدعينا refreshForBookingId هنا، سيُعيد بناء الليالي محلياً
          //     بـ UUIDs جديدة مختلفة عن تلك المرفوعة من جهاز 1، مما يُسبب:
          //       (أ) تكرار منطق حساب الليالي (إعادة تنفيذ جزء من المغادرة)
          //       (ب) تضارب UUIDs بين الأجهزة عند الرفع التالي
          //       (ج) احتمال إنشاء ليالٍ إضافية أو فروقات مالية
          //   الحل: نعتمد الليالي المرفوعة من جهاز المصدر كما هي للحجوزات
          //   المكتملة، ونُعيد الحساب فقط للحجوزات النشطة (التي قد تتغير لياليها
          //   مع مرور الوقت).
          final isCompletedBooking = !StatusUtils.isActiveBooking(booking.status) ||
              (booking.actualCheckout != null &&
                  booking.actualCheckout!.isNotEmpty);

          if (!isCompletedBooking) {
            await _bookingsRepository.derivedFields.refreshForBookingId(booking.id);
          } else {
            _logger.debug(
              '⏭️ تخطي refreshForBookingId للحجز المكتمل ${localUuid.substring(0, 8)}... '
              '(status=${booking.status}, actualCheckout=${booking.actualCheckout}) — '
              'الليالي مرفوعة من جهاز المصدر، لا حاجة لإعادة الحساب',
              tag: 'SYNC',
            );
          }

          // ✅ 4. تتبع الغرف المتأثرة بتغيير حالة الحجز
          // إذا تغيرت الحالة من نشطة إلى غير نشطة (مثل تسجيل الخروج)
          // نحتاج لإعادة حساب حالة الإشغال للغرفة
          final newStatus = booking.status;
          final newRoomNumber = booking.roomNumber;

          final statusChanged = oldStatus != null && oldStatus != newStatus;
          final wasActive = oldStatus != null &&
              StatusUtils.isActiveBooking(oldStatus);
          final isNowActive = StatusUtils.isActiveBooking(newStatus);

          if (statusChanged && wasActive != isNowActive) {
            // الحالة تغيرت بين نشطة وغير نشطة - أضف الغرفة للقائمة
            if (oldRoomNumber != null && oldRoomNumber.isNotEmpty) {
              affectedRoomNumbers.add(oldRoomNumber);
            }
            if (newRoomNumber.isNotEmpty) {
              affectedRoomNumbers.add(newRoomNumber);
            }
          } else if (existingBooking == null) {
            // حجز جديد من المزامنة - أضف الغرفة للقائمة
            if (newRoomNumber.isNotEmpty) {
              affectedRoomNumbers.add(newRoomNumber);
            }
          }
        }

        processed++;
      } catch (e) {
        _logger.warning('Failed to sync booking ${doc.$id}: $e', tag: 'SYNC');
      }
    }

    // ✅ إعادة حساب حالة الإشغال للغرف المتأثرة فقط (تحسين الأداء)
    if (affectedRoomNumbers.isNotEmpty) {
      try {
        for (final roomNumber in affectedRoomNumbers) {
          await _refreshSingleRoomOccupancy(roomNumber);
        }
        _logger.debug(
          '🔄 تم تحديث حالة ${affectedRoomNumbers.length} غرفة متأثرة بتغييرات الحجوزات',
          tag: 'SYNC',
        );
      } catch (e) {
        _logger.warning(
          '⚠️ فشل تحديث حالة الغرف المتأثرة: $e',
          tag: 'SYNC',
        );
      }
    }

    return processed;
  }

  /// ✅ إعادة حساب حالة إشغال غرفة واحدة بناءً على الحجوزات النشطة
  /// يستخدم RoomsRepository لضمان تحديث version و lastModified
  Future<void> _refreshSingleRoomOccupancy(String roomNumber) async {
    try {
      // التحقق من وجود حجز نشط للغرفة
      final activeBooking = await _bookingsRepository.getActiveBookingForRoom(
        roomNumber,
      );

      final room = await (database.select(database.rooms)
            ..where((r) => r.roomNumber.equals(roomNumber))
            ..limit(1))
          .getSingleOrNull();

      if (room == null || room.deletedAt != null) return;

      final shouldBeOccupied = activeBooking != null;
      final isCurrentlyOccupied = StatusUtils.isRoomOccupied(room.status);
      final isCurrentlyAvailable = StatusUtils.isRoomAvailable(room.status);

      if (shouldBeOccupied && !isCurrentlyOccupied) {
        await _roomsRepository.updateByRoomNumber(
          roomNumber,
          status: StatusUtils.roomStatusForOccupancy(true),
          originIsServer: true,
        );
      } else if (!shouldBeOccupied && !isCurrentlyAvailable) {
        await _roomsRepository.updateByRoomNumber(
          roomNumber,
          status: StatusUtils.roomStatusForOccupancy(false),
          originIsServer: true,
        );
      }
    } catch (e) {
      _logger.warning(
        '⚠️ فشل تحديث حالة الغرفة $roomNumber: $e',
        tag: 'SYNC',
      );
    }
  }

  Future<int> _syncEmployees(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.employees)
              ..where((e) => e.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        // ✅ تخزين remote id كـ serverId — يسمح بحل FK عبر الأجهزة
        // salary_withdrawals و salary_cycles يستخدمان employeeId البعيد
        // الذي يساوي id الموظف على جهاز المصدر. بتخزينه في serverId
        // يمكن حل FK بالبحث عن serverId = remoteEmployeeId
        final remoteId = _asIntSafe(data, 'id');
        if (remoteId != null && data['serverId'] == null) {
          data['serverId'] = remoteId;
        }

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

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.expenses)
              ..where((e) => e.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

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

        // ✅ إصلاح: التحقق من الحذف الناعم + عدم تجاوز البيانات المحلية الأحدث
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existingPayment = await _getPaymentByLocalUuid(localUuid);

        // منع إعادة إحياء السجلات المحذوفة softly
        if (existingPayment != null && existingPayment.deletedAt != null) {
          final remoteDeletedAt = _asIntNullable(data['deletedAt']) ??
              _asIntNullable(data['deleted_at']);
          if (remoteDeletedAt == null) {
            // السجل محذوف محلياً لكن البعيد غير محذوف — نرفض الإحياء
            _logger.debug(
              'Skipping payment ${doc.$id}: locally soft-deleted, refusing revival',
              tag: 'SYNC',
            );
            processed++;
            continue;
          }
          // كلاهما محذوف — نسمح بالتحديث إذا كان البعيد أحدث
        }

        // Financial immutability: if local payment exists and is newer, keep local
        // ✅ إصلاح حرج: نستخدم $updatedAt كـ fallback عند غياب lastModified البعيد
        // (المستندات القديمة قبل تثبيت التحديث). بدون هذا، incomingLastModified=0
        // ويتخطى كل التحديثات حتى لو كانت بعيدة وأحدث.
        final incomingLastModified = _asIntNullable(data['lastModified']) ??
            _extractUpdatedAtSec(doc) ?? 0;
        if (existingPayment != null &&
            existingPayment.lastModified > incomingLastModified) {
          _logger.debug(
            'Skipping payment ${doc.$id}: local is newer (financial immutability, '
            'local=${existingPayment.lastModified} > remote=$incomingLastModified)',
            tag: 'SYNC',
          );
          processed++;
          continue;
        }

        await _adapterRegistry.payments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        // ✅ تأجيل الدفعة فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
        // (بيانات مفقودة مثل bookingLocalId) — لا نشمل 'constraint failed' عام
        // لأنه يطابق UNIQUE و CHECK أيضاً ويؤدي لتأجيل خاطئ لسجلات مكررة
        final errStr = e.toString();
        if (errStr.contains('FOREIGN KEY constraint failed') ||
            errStr.contains('NOT NULL constraint failed')) {
          _logger.debug(
            'Deferring payment ${doc.$id}: FK/NOT NULL constraint (missing booking)',
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

        // ✅ إصلاح: التحقق من الحذف الناعم + عدم تجاوز البيانات المحلية الأحدث
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existingDebt = await _getDebtByLocalUuid(localUuid);

        // منع إعادة إحياء السجلات المحذوفة softly
        if (existingDebt != null && existingDebt.deletedAt != null) {
          final remoteDeletedAt = _asIntNullable(data['deletedAt']) ??
              _asIntNullable(data['deleted_at']);
          if (remoteDeletedAt == null) {
            // السجل محذوف محلياً لكن البعيد غير محذوف — نرفض الإحياء
            _logger.debug(
              'Skipping debt ${doc.$id}: locally soft-deleted, refusing revival',
              tag: 'SYNC',
            );
            processed++;
            continue;
          }
          // كلاهما محذوف — نسمح بالتحديث إذا كان البعيد أحدث
        }

        // Financial immutability: if local debt exists and is newer, keep local
        // ✅ إصلاح حرج: نستخدم $updatedAt كـ fallback عند غياب lastModified البعيد
        // (المستندات القديمة قبل تثبيت التحديث).
        final incomingLastModified = _asIntNullable(data['lastModified']) ??
            _extractUpdatedAtSec(doc) ?? 0;
        if (existingDebt != null &&
            existingDebt.lastModified > incomingLastModified) {
          _logger.debug(
            'Skipping debt ${doc.$id}: local is newer (financial immutability, '
            'local=${existingDebt.lastModified} > remote=$incomingLastModified)',
            tag: 'SYNC',
          );
          processed++;
          continue;
        }

        await _adapterRegistry.debts.upsertFromJson(data, src: Source.appwrite);
        processed++;
      } catch (e) {
        // ✅ تأجيل الدين فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
        final errStr = e.toString();
        if (errStr.contains('FOREIGN KEY constraint failed') ||
            errStr.contains('NOT NULL constraint failed')) {
          _logger.debug(
            'Deferring debt ${doc.$id}: FK/NOT NULL constraint (missing booking)',
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

  /// ✅ تحويل آمن للقيمة الرقمية من Map — يتعامل مع int/double/num/String
  /// يُستخدم بدل `data['key'] as int?` الذي قد يرمي TypeError مع double
  int? _asIntSafe(Map<String, dynamic> data, String key) {
    final value = data[key];
    return _asIntNullable(value);
  }

  Future<int> _pushAllEntities() async {
    // ✅ فحص الاتصال أولاً
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        _logger.warning('⚠️ لا يوجد اتصال بالإنترنت - تم تأجيل الرفع', tag: 'SYNC');
        return 0;
      }
    } catch (_) {}

    int totalProcessed = 0;
    int consecutiveFailures = 0;

    while (true) {
      final batchSize = _adaptiveBatchSize.round();
      final entries = await outboxDao.takeBatch(batchSize, sources: const ['local']);
      if (entries.isEmpty) {
        break;
      }

      int processedInBatch = 0;
      for (final entry in entries) {
        try {
          const timeoutSeconds = 30;
          final success = await _processOutboxEntry(entry)
              .timeout(const Duration(seconds: timeoutSeconds));
          if (success) {
            // ✅ Dual-delivery: نضع علامة "مُسلّم للرئيسي" بدلاً من الحذف.
            // السجل يُحذف تلقائياً فقط إذا كان مُسلّماً للثانوي أيضاً.
            await outboxDao.markDeliveredToPrimary(entry.id);
            processedInBatch++;
          }
        } catch (e) {
          if (e is TimeoutException) {
            _logger.warning('⏱️ Timeout processing entry ${entry.id}', tag: 'SYNC');
          }
        }
      }

      // Adaptive batch size
      if (processedInBatch == entries.length) {
        _adaptiveBatchSize = (_adaptiveBatchSize * 1.3).clamp(10, 200);
        consecutiveFailures = 0;
      } else {
        _adaptiveBatchSize = (_adaptiveBatchSize * 0.6).clamp(5, 100);
        consecutiveFailures++;
      }

      totalProcessed += processedInBatch;

      if (consecutiveFailures >= 3) {
        _logger.warning('⛔ 3 دفعات فاشلة متتالية - إيقاف المزامنة', tag: 'SYNC');
        break;
      }

      if (entries.length < batchSize) {
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
        case 'booking_price_adjustments':
          return await _processBookingPriceAdjustmentEntry(entry);
        case 'guest_infos':
          return await _processGuestInfoEntry(entry);
        case 'salary_withdrawals':
          return await _processSalaryWithdrawalEntry(entry);
        case 'salary_carry_over_logs':
          return await _processSalaryCarryOverLogEntry(entry);
        case 'blacklist':
          return await _processBlacklistEntry(entry);
        case 'price_adjustments':
          return await _processPriceAdjustmentEntry(entry);
        default:
          _logger.warning(
            'Unknown outbox entity: ${entry.entity}',
            tag: 'SYNC',
          );
          // لا نحذف الإدخال — نُبقيه للتحقيق ونعيد false ليبقى في الطابور
          return false;
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

  /// تصفية الحمولة قبل الإرسال — إبقاء فقط الحقول الموجودة في مخطط Appwrite الفعلي
  /// ⚠️ هذا يمنع خطأ "Unknown attribute" نهائياً
  Map<String, dynamic> _filterPayload(
    String collectionId,
    Map<String, dynamic> payload,
  ) {
    return AppwriteSyncUtils.filterPayloadForCollection(collectionId, payload);
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

    try {
      await appwriteService.upsertRoom(
        room.localUuid,
        _filterPayload('rooms', _addIdempotencyKey(payload, entry)),
      );
    } catch (e) {
      // ✅ إذا فشل الرفع بسبب حقل idempotencyKey غير موجود، نُعيد المحاولة بدونه
      if (e.toString().contains('attribute_not_found') ||
          e.toString().contains('Property not found') ||
          e.toString().contains('invalid_attribute') ||
          e.toString().contains('idempotencyKey')) {
        _logger.warning(
          '⚠️ إعادة محاولة رفع الغرفة بدون idempotencyKey: $e',
          tag: 'SYNC',
        );
        await appwriteService.upsertRoom(
          room.localUuid,
          _filterPayload('rooms', payload), // بدون idempotencyKey
        );
      } else {
        rethrow;
      }
    }
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

    // ✅ تسجيل تشخيصي: تسجيل الحقول الحرجة قبل الرفع
    _logger.info(
      '📤 Push booking ${booking.localUuid.substring(0, 8)}... '
      'status=${booking.status} '
      'actualCheckout=${booking.actualCheckout} '
      'calculatedNights=${booking.calculatedNights} '
      'lastModified=${booking.lastModified}',
      tag: 'SYNC',
    );

    // ✅ إزالة idempotencyKey إذا لم يكن في مخطط Appwrite
    // هذا الحقل غير موجود في مخطط Appwrite وقد يسبب فشل صامت في updateDocument
    // إذا كان التحقق من المخطط مفعّلاً على Appwrite Cloud
    final cleanPayload = Map<String, dynamic>.from(payload);
    // idempotencyKey يُضاف لاحقاً عبر _addIdempotencyKey

    final finalPayload = _addIdempotencyKey(cleanPayload, entry);

    try {
      await appwriteService.upsertBooking(
        booking.localUuid,
        _filterPayload('bookings', finalPayload),
      );

      // ✅ تحقق بعد الرفع: قراءة المستند من Appwrite والتأكد من حفظ الحقول الحرجة
      await _verifyPushedBooking(booking.localUuid, booking);
    } catch (e) {
      // ✅ إذا فشل الرفع بسبب حقل idempotencyKey غير موجود، نُعيد المحاولة بدونه
      if (e.toString().contains('attribute_not_found') ||
          e.toString().contains('Property not found') ||
          e.toString().contains('invalid_attribute')) {
        _logger.warning(
          '⚠️ إعادة محاولة رفع الحجز بدون idempotencyKey: $e',
          tag: 'SYNC',
        );
        await appwriteService.upsertBooking(
          booking.localUuid,
          _filterPayload('bookings', payload), // بدون idempotencyKey
        );
      } else {
        rethrow;
      }
    }
    return true;
  }

  /// ✅ تحقق من حفظ الحقول الحرجة بعد الرفع إلى Appwrite
  /// يقرأ المستند من Appwrite ويقارن status و actualCheckout
  Future<void> _verifyPushedBooking(
    String localUuid,
    Booking expected,
  ) async {
    try {
      // ignore: deprecated_member_use
      final doc = await appwriteService.databases.getDocument(
        databaseId: AppwriteConfig.databaseId,
        collectionId: AppwriteConfig.bookingsCollectionId,
        documentId: localUuid,
      );
      final remoteStatus = doc.data['status']?.toString();
      final remoteActualCheckout = doc.data['actualCheckout']?.toString();

      if (remoteStatus != expected.status ||
          remoteActualCheckout != expected.actualCheckout) {
        _logger.error(
          '❌ تحقق بعد الرفع فشل! booking=${localUuid.substring(0, 8)}... '
          'expected: status=${expected.status}, actualCheckout=${expected.actualCheckout} '
          'remote: status=$remoteStatus, actualCheckout=$remoteActualCheckout',
          tag: 'SYNC',
        );
      } else {
        _logger.debug(
          '✅ تحقق بعد الرفع ناجح: booking=${localUuid.substring(0, 8)}... '
          'status=$remoteStatus, actualCheckout=$remoteActualCheckout',
          tag: 'SYNC',
        );
      }
    } catch (e) {
      // فشل التحقق ليس حرجاً — لا نوقف المزامنة
      _logger.warning(
        '⚠️ فشل التحقق بعد رفع الحجز $localUuid: $e',
        tag: 'SYNC',
      );
    }
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
    // ✅ إضافة employeeUuid لمصروفات الرواتب لربط الموظف عبر الأجهزة
    if (expense.relatedId != null && _isSalaryExpenseType(expense.expenseType)) {
      final employee = await (database.select(database.employees)
            ..where((e) => e.id.equals(expense.relatedId!))
            ..limit(1))
          .getSingleOrNull();
      if (employee != null) {
        payload['employeeUuid'] = employee.localUuid;
      }
    }
    try {
      await appwriteService.upsertExpense(
        expense.localUuid,
        _filterPayload('expenses', _addIdempotencyKey(payload, entry)),
      );
    } catch (e) {
      // ✅ إذا فشل الرفع بسبب حقل idempotencyKey غير موجود، نُعيد المحاولة بدونه
      if (e.toString().contains('attribute_not_found') ||
          e.toString().contains('Property not found') ||
          e.toString().contains('invalid_attribute') ||
          e.toString().contains('idempotencyKey') ||
          e.toString().contains('document_invalid_structure')) {
        _logger.warning(
          '⚠️ إعادة محاولة رفع المصروف بدون idempotencyKey: $e',
          tag: 'SYNC',
        );
        await appwriteService.upsertExpense(
          expense.localUuid,
          _filterPayload('expenses', payload), // بدون idempotencyKey
        );
      } else {
        rethrow;
      }
    }
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
    try {
      await appwriteService.upsertPayment(
        payment.localUuid,
        _filterPayload('payments', _addIdempotencyKey(payload, entry)),
      );
    } catch (e) {
      // ✅ إذا فشل الرفع بسبب حقل idempotencyKey غير موجود، نُعيد المحاولة بدونه
      if (e.toString().contains('attribute_not_found') ||
          e.toString().contains('Property not found') ||
          e.toString().contains('invalid_attribute') ||
          e.toString().contains('idempotencyKey') ||
          e.toString().contains('document_invalid_structure')) {
        _logger.warning(
          '⚠️ إعادة محاولة رفع الدفع بدون idempotencyKey: $e',
          tag: 'SYNC',
        );
        await appwriteService.upsertPayment(
          payment.localUuid,
          _filterPayload('payments', payload), // بدون idempotencyKey
        );
      } else {
        rethrow;
      }
    }
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
    try {
      await appwriteService.upsertDebt(
        debt.localUuid,
        _filterPayload('debts', _addIdempotencyKey(payload, entry)),
      );
    } catch (e) {
      // ✅ إذا فشل الرفع بسبب حقل idempotencyKey غير موجود، نُعيد المحاولة بدونه
      if (e.toString().contains('attribute_not_found') ||
          e.toString().contains('Property not found') ||
          e.toString().contains('invalid_attribute') ||
          e.toString().contains('idempotencyKey') ||
          e.toString().contains('document_invalid_structure')) {
        _logger.warning(
          '⚠️ إعادة محاولة رفع الدين بدون idempotencyKey: $e',
          tag: 'SYNC',
        );
        await appwriteService.upsertDebt(
          debt.localUuid,
          _filterPayload('debts', payload), // بدون idempotencyKey
        );
      } else {
        rethrow;
      }
    }
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

  // ─── GuestInfos ──────────────────────────────────────────────────────────

  Future<int> _syncGuestInfos(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.guestInfos)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        await _adapterRegistry.guestInfos.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync guest_info ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<bool> _processGuestInfoEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteGuestInfo(entry.localUuid),
      );
      return true;
    }
    final info = await _getGuestInfoByLocalUuid(entry.localUuid);
    if (info == null) {
      await _deleteSilently(
        () => appwriteService.deleteGuestInfo(entry.localUuid),
      );
      return true;
    }
    final payload = _adapterRegistry.guestInfos.adapter.toJson(
      info,
      src: Source.appwrite,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.guestInfosCollectionId,
      documentId: info.localUuid,
      data: _filterPayload('guest_infos', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Future<GuestInfo?> _getGuestInfoByLocalUuid(String localUuid) {
    return (database.select(
      database.guestInfos,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  // ─── SalaryWithdrawals ──────────────────────────────────────────────────

  Future<int> _syncSalaryWithdrawals(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final deferred = <Map<String, dynamic>>[];

    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.salaryWithdrawals)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        // ✅ حل FK الموظف بثلاث مستويات: UUID → id → serverId
        final remoteEmployeeId = _asIntSafe(data, 'employeeId') ??
            _asIntSafe(data, 'employee_id');
        final employeeUuid = (data['employeeUuid'] as String?) ??
            (data['employee_uuid'] as String?) ??
            (data['employeeLocalUuid'] as String?) ??
            (data['employee_local_uuid'] as String?);

        Employee? employee;

        // الطريقة 1: البحث بالـ UUID (الأكثر موثوقية عبر الأجهزة)
        if (employeeUuid != null && employeeUuid.isNotEmpty) {
          employee = await (database.select(database.employees)
                ..where((e) => e.localUuid.equals(employeeUuid))
                ..limit(1))
              .getSingleOrNull();
        }

        // الطريقة 2: البحث بالـ id البعيد كـ id محلي (يعمل إذا تطابقت المعرفات)
        if (employee == null && remoteEmployeeId != null) {
          employee = await (database.select(database.employees)
                ..where((e) => e.id.equals(remoteEmployeeId))
                ..limit(1))
              .getSingleOrNull();
        }

        // الطريقة 3: البحث بالـ serverId (id الأصلي من جهاز المصدر)
        if (employee == null && remoteEmployeeId != null) {
          employee = await (database.select(database.employees)
                ..where((e) => e.serverId.equals(remoteEmployeeId))
                ..limit(1))
              .getSingleOrNull();
        }

        if (employee == null) {
          _logger.warning(
            '⏭️ تخطي salary_withdrawal ${doc.$id}: الموظف $remoteEmployeeId (uuid=$employeeUuid) غير موجود محلياً (سجل يتيم)',
            tag: 'SYNC',
          );
          continue;
        }

        // ✅ استبدال employeeId البعيد بالمعرف المحلي للموظف
        // هذا يضمن أن FK يشير للمعرف المحلي الصحيح
        data['employeeId'] = employee.id;

        final insertedId = await _adapterRegistry.salaryWithdrawals.upsertFromJson(
          data,
          src: Source.appwrite,
        );

        // ✅ كتابة expense_id في العمود الخام (Migration 40+)
        // العمود ليس في الـ data class المُولّد لذلك نكتبه يدوياً
        final remoteExpenseId = _asIntSafe(data, 'expenseId');
        if (remoteExpenseId != null && remoteExpenseId > 0) {
          final swAdapter = _adapterRegistry.salaryWithdrawals.adapter;
          if (swAdapter is SalaryWithdrawalsAdapter) {
            await swAdapter.writeExpenseIdRaw(database, insertedId, remoteExpenseId);
          }
        }

        processed++;
      } on SqliteException catch (e) {
        if (e.resultCode == 787) {
          // FK constraint failed - تأجيل السجل لإعادة المحاولة لاحقاً
          final data = Map<String, dynamic>.from(doc.data);
          data['localUuid'] ??= doc.$id;
          deferred.add(data);
          _logger.warning(
            '⏳ تأجيل salary_withdrawal ${doc.$id}: FK constraint failed - سيتم إعادة المحاولة',
            tag: 'SYNC',
          );
        } else {
          _logger.warning(
            'Failed to sync salary_withdrawal ${doc.$id}: $e',
            tag: 'SYNC',
          );
        }
      } catch (e) {
        _logger.warning(
          'Failed to sync salary_withdrawal ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }

    // ✅ إعادة محاولة السجلات المؤجلة بعد اكتمال باقي السجلات
    if (deferred.isNotEmpty) {
      _logger.info(
        '🔄 إعادة محاولة ${deferred.length} سجل salary_withdrawals مؤجل...',
        tag: 'SYNC',
      );
      for (final data in deferred) {
        try {
          final deferredInsertedId = await _adapterRegistry.salaryWithdrawals.upsertFromJson(
            data,
            src: Source.appwrite,
          );
          // ✅ كتابة expense_id في العمود الخام
          final deferredExpenseId = _asIntSafe(data, 'expenseId');
          if (deferredExpenseId != null && deferredExpenseId > 0) {
            final swAdapter = _adapterRegistry.salaryWithdrawals.adapter;
            if (swAdapter is SalaryWithdrawalsAdapter) {
              await swAdapter.writeExpenseIdRaw(database, deferredInsertedId, deferredExpenseId);
            }
          }
          processed++;
        } catch (e) {
          _logger.warning(
            '⏭️ فشل نهائي لـ salary_withdrawal (يتيم): الموظف ${data['employeeId'] ?? data['employee_id']} غير موجود - $e',
            tag: 'SYNC',
          );
        }
      }
    }

    return processed;
  }

  Future<bool> _processSalaryWithdrawalEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteSalaryWithdrawal(entry.localUuid),
      );
      return true;
    }
    final withdrawal = await _getSalaryWithdrawalByLocalUuid(entry.localUuid);
    if (withdrawal == null) {
      await _deleteSilently(
        () => appwriteService.deleteSalaryWithdrawal(entry.localUuid),
      );
      return true;
    }

    // ✅ إصلاح FK constraint: التأكد أن الموظف موجود على Appwrite قبل الدفع
    // إذا لم يكن الموظف قد رُفع بعد، نرفعه أولاً لمنع فشل FK constraint
    final employee = await (database.select(database.employees)
          ..where((e) => e.id.equals(withdrawal.employeeId))
          ..limit(1))
        .getSingleOrNull();
    if (employee != null && employee.serverId == null) {
      // الموظف لم يُرفع بعد — نرفعه أولاً
      _logger.info(
        '🔄 رفع الموظف ${employee.id} أولاً لضمان FK constraint',
        tag: 'SYNC',
      );
      try {
        final empPayload = _adapterRegistry.employees.adapter.toJson(
          employee,
          src: Source.appwrite,
        );
        await appwriteService.upsertEmployee(
          employee.localUuid,
          _filterPayload('employees', _addIdempotencyKey(empPayload, entry)),
        );
        // تحديث serverId محلياً لمنع الرفع المكرر
        try {
          final remoteDoc = await appwriteService.getDocument(
            collectionId: AppwriteConfig.employeesCollectionId,
            documentId: employee.localUuid,
          );
          await (database.update(database.employees)
                ..where((e) => e.id.equals(employee.id)))
              .write(EmployeesCompanion(
            serverId: drift.Value(remoteDoc.$id.hashCode),
          ));
        } catch (_) {
          // فشل جلب المستند البعيد — نتجاوز، الأهم أن الموظف رُفع بنجاح
        }
      } catch (e) {
        _logger.warning(
          '⚠️ فشل رفع الموظف ${employee.id} — سيتم تأجيل سحب الراتب: $e',
          tag: 'SYNC',
        );
        // فشل رفع الموظف — لا نستطيع رفع السحب بدون FK
        // نُعيد false ليبقى في الطابور للمحاولة لاحقاً
        return false;
      }
    } else if (employee == null) {
      // الموظف غير موجود محلياً — سجل يتيم
      _logger.warning(
        '⏭️ تخطي salary_withdrawal: الموظف ${withdrawal.employeeId} غير موجود محلياً (سجل يتيم)',
        tag: 'SYNC',
      );
      // لا نستطيع رفع سحب راتب بدون موظف — نحذفه من الطابور
      return true;
    }

    final payload = _adapterRegistry.salaryWithdrawals.adapter.toJson(
      withdrawal,
      src: Source.appwrite,
    );
    // ✅ إضافة employeeUuid لربط السلف بالموضف عبر الأجهزة
    payload['employeeUuid'] = employee.localUuid;
    payload['employeeLocalUuid'] = employee.localUuid;
    // ✅ إضافة sync_origin للتوافق مع مخطط Appwrite Cloud
    payload['sync_origin'] = withdrawal.origin;
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
      documentId: withdrawal.localUuid,
      data: _filterPayload('salary_withdrawals', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Future<SalaryWithdrawal?> _getSalaryWithdrawalByLocalUuid(String localUuid) {
    return (database.select(
      database.salaryWithdrawals,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  Map<String, dynamic> _roomToRemote(Room room) {
    final data = <String, dynamic>{
      'roomNumber': room.roomNumber,
      'type': room.type,
      'price': room.price,
      'status': room.status,
      'localUuid': room.localUuid,
      'createdAt': room.createdAt,
      'updatedAt': room.updatedAt,
      'lastModified': room.lastModified,
      'version': room.version,
      'origin': room.origin,
      'deviceId': room.deviceId,
      // حقول مطلوبة إضافية من Appwrite schema
      'roomType': room.type,
      'basePrice': room.price,
      'floor': 1,
      'bedsCount': 1,
    };
    _putIfNotNull(data, 'serverId', room.serverId);
    data['deletedAt'] = room.deletedAt;
    _putIfStringNotEmpty(data, 'imageUrl', room.imageUrl);
    return AppwriteSyncUtils.sanitizePayload('rooms', data, collectionId: AppwriteConfig.roomsCollectionId);
  }

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
      'localUuid': booking.localUuid,
      'createdAt': booking.createdAt,
      'updatedAt': booking.updatedAt,
      'lastModified': booking.lastModified,
      'version': booking.version,
      'origin': booking.origin,
    };
    _putIfNotNull(data, 'serverBookingId', booking.serverBookingId);
    _putIfNotNull(data, 'serverId', booking.serverId);
    data['deletedAt'] = booking.deletedAt;
    _putIfStringNotEmpty(data, 'guestIdIssueDate', booking.guestIdIssueDate);
    _putIfStringNotEmpty(data, 'guestIdIssuePlace', booking.guestIdIssuePlace);
    _putIfStringNotEmpty(data, 'guestEmail', booking.guestEmail);
    _putIfStringNotEmpty(data, 'guestAddress', booking.guestAddress);
    // ✅ إصلاح حرج: checkoutDate و actualCheckout يجب إرسالهما دائماً
    // حتى لو كانا null — لأن `_putIfStringNotEmpty` يحذف المفتاح إذا كان null،
    // مما يمنع Appwrite من تحديث الحقل عند تسجيل الخروج.
    // بدون هذا الإصلاح: إذا رُفع الحجز قبل الخروج (actualCheckout=null)،
    // ثم رُفع بعد الخروج (actualCheckout='2026-...')، المفتاح يُضاف ✅.
    // لكن إذا عمل DeltaSync push بينهما ببيانات قديمة، يضبط actualCheckout=null على السيرفر.
    // الحل: إرسال الحقول دائماً صراحةً لضمان تناسق البيانات.
    data['checkoutDate'] = booking.checkoutDate;
    data['actualCheckout'] = booking.actualCheckout;
    _putIfStringNotEmpty(data, 'notes', booking.notes);
    // حقول مالية
    data['discount'] = booking.discount;
    _putIfStringNotEmpty(data, 'discountType', booking.discountType);
    _putIfStringNotEmpty(data, 'discountStartDate', booking.discountStartDate);
    data['totalDueCached'] = booking.totalDueCached;
    data['totalPaidCached'] = booking.totalPaidCached;
    data['remainingBalanceCached'] = booking.remainingBalanceCached;
    // حقول تواريخ ومشتقات
    data['totalNightsCached'] = booking.totalNightsCached;
    data['isFullyPaid'] = booking.isFullyPaid;
    _putIfStringNotEmpty(data, 'hotelDayCheckin', booking.hotelDayCheckin);
    _putIfStringNotEmpty(data, 'hotelDayCheckout', booking.hotelDayCheckout);
    _putIfStringNotEmpty(data, 'vectorClock', booking.vectorClock);
    data['deviceId'] = booking.deviceId;
    // ✅ حقول SyncFields المضافة حديثاً إلى Appwrite Cloud
    _putIfStringNotEmpty(data, 'createdAtIso', booking.createdAtIso);
    _putIfStringNotEmpty(data, 'updatedAtIso', booking.updatedAtIso);
    _putIfStringNotEmpty(data, 'deletedAtIso', booking.deletedAtIso);
    _putIfNotNull(data, 'createdAtEpoch', booking.createdAtEpoch);
    _putIfNotNull(data, 'lastModifiedEpoch', booking.lastModifiedEpoch);
    // ✅ إصلاح (2026-06-27): حقول موجودة على Appwrite Cloud يجب إرسالها
    // — كانت تُحذف بواسطة filterPayloadForCollection لأنها غير مُدرجة
    _putIfStringNotEmpty(data, 'sync_origin', booking.origin);
    _putIfNotNull(data, 'syncTimestamp', booking.lastModified);
    return AppwriteSyncUtils.sanitizePayload('bookings', data, collectionId: AppwriteConfig.bookingsCollectionId);
  }

  Map<String, dynamic> _expenseToRemote(Expense expense) {
    final data = <String, dynamic>{
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
      'vectorClock': expense.vectorClock,
      'deviceId': expense.deviceId,
    };
    _putIfNotNull(data, 'relatedId', expense.relatedId);
    _putIfNotNull(data, 'cashTransactionId', expense.cashTransactionId);
    _putIfNotNull(data, 'serverId', expense.serverId);
    data['deletedAt'] = expense.deletedAt;
    _putIfStringNotEmpty(data, 'hotelDayKey', expense.hotelDayKey);
    _putIfStringNotEmpty(data, 'categoryUuid', expense.categoryUuid);
    _putIfStringNotEmpty(data, 'cashFlowUuid', expense.cashFlowUuid);
    if (expense.isAutoGenerated) data['isAutoGenerated'] = true;
    return AppwriteSyncUtils.sanitizePayload('expenses', data, collectionId: AppwriteConfig.expensesCollectionId);
  }

  Map<String, dynamic> _paymentToRemote(Payment payment) {
    final data = <String, dynamic>{
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
      // ✅ تم حذف sync_version و sync_vector_clock — حقول مكررة وقديمة
      // version و vectorClock يُرسلان بأسمائهما الصحيحة
      'hotelDayKey': payment.hotelDayKey ?? '',
      'isPendingBalance': payment.isPendingBalance,
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
    _putIfNotNull(data, 'serverId', payment.serverId);
    data['deletedAt'] = payment.deletedAt;
    _putIfStringNotEmpty(data, 'deletedAtIso', payment.deletedAtIso);
    _putIfStringNotEmpty(data, 'linkedDebtUuid', payment.linkedDebtUuid);
    _putIfNotNull(data, 'discountAmount', payment.discountAmount);
    _putIfStringNotEmpty(data, 'discountStartDate', payment.discountStartDate);
    // ✅ إرسال isVoided دائماً (حتى لو false) لضمان المزامنة الصحيحة
    data['isVoided'] = payment.isVoided;
    _putIfNotNull(data, 'voidedAt', payment.voidedAt);
    _putIfStringNotEmpty(data, 'voidedBy', payment.voidedBy);
    // ✅ إرسال حقول SyncFields الإضافية المتوفرة في Appwrite Cloud
    _putIfNotNull(data, 'createdAtEpoch', payment.createdAtEpoch);
    _putIfNotNull(data, 'lastModifiedEpoch', payment.lastModifiedEpoch);
    data['vectorClock'] = payment.vectorClock;
    data['deviceId'] = payment.deviceId;
    return AppwriteSyncUtils.sanitizePayload('payments', data, collectionId: AppwriteConfig.paymentsCollectionId);
  }

  Map<String, dynamic> _debtToRemote(Debt debt) {
    final data = <String, dynamic>{
      // ── Required fields ──
      'localUuid': debt.localUuid,
      'guestName': debt.guestName,
      'checkinDate': debt.checkinDate,
      'totalAmount': debt.totalAmount,
      'paidAmount': debt.paidAmount,
      'remainingAmount': debt.remainingAmount.round(), // ✅ Appwrite: integer
      // ── Required sync fields ──
      // ✅ تم حذف vector_clock/sync_vector_clock/sync_version/sync_origin
      // — حقول مكررة وقديمة، يُرسل vectorClock/version/origin بأسمائهم الصحيحة
      // ── Business fields ──
      'bookingLocalId': debt.bookingLocalId,
      'checkoutDate': debt.checkoutDate,
      'paymentDate': debt.paymentDate,
      'isSettled': debt.isSettled,
      'debtReason': debt.debtReason,
      'note': debt.note,
      'debtUuid': debt.debtUuid,
      'pledge': debt.pledge,
      'pledgeType': debt.pledgeType,
      'isFromAutoFix': debt.isFromAutoFix,
      'settlementConfirmed': debt.settlementConfirmed,
      // ── Timestamps ──
      'createdAt': debt.createdAt,
      'updatedAt': debt.updatedAt,
      'lastModified': debt.lastModified,
      'version': debt.version,
      'origin': debt.origin,
    };
    _putIfNotNull(data, 'serverId', debt.serverId);
    data['deletedAt'] = debt.deletedAt;
    _putIfStringNotEmpty(data, 'deletedAtIso', debt.deletedAtIso);
    _putIfStringNotEmpty(data, 'hotelDayOpened', debt.hotelDayOpened);
    _putIfStringNotEmpty(data, 'hotelDayClosed', debt.hotelDayClosed);
    // ✅ حقول SyncFields المضافة حديثاً إلى Appwrite Cloud
    data['vectorClock'] = debt.vectorClock;
    data['deviceId'] = debt.deviceId;
    _putIfNotNull(data, 'createdAtEpoch', debt.createdAtEpoch);
    _putIfNotNull(data, 'lastModifiedEpoch', debt.lastModifiedEpoch);
    return AppwriteSyncUtils.sanitizePayload('debts', data, collectionId: AppwriteConfig.debtsCollectionId);
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

  /// هل نوع المصروف مرتبط بالرواتب
  static bool _isSalaryExpenseType(String type) {
    const salaryKeywords = ['رواتب', 'سحب راتب', 'سحب من الراتب', 'خصم راتب', 'خصم من الراتب'];
    for (final keyword in salaryKeywords) {
      if (type.contains(keyword)) return true;
    }
    return false;
  }

  // ─── Delta Sync ────────────────────────────────────────────────────────

  /// قراءة آخر timestamp خاص بـ booking_nights من SharedPreferences
  Future<int> _getBookingNightsPullTs() async {
    return _pullService?.getBookingNightsPullTs() ?? 0;
  }

  /// تحديث آخر timestamp خاص بـ booking_nights
  Future<void> _updateBookingNightsPullTs(int ts) async {
    await _pullService?.updateBookingNightsPullTs(ts);
  }

  /// بناء delta queries خاصة بـ booking_nights
  List<String> _bookingNightsDeltaQueries(
    int lastPullTs, {
    required bool remoteEpochIsMillis,
  }) {
    return _pullService?.bookingNightsDeltaQueries(
      lastPullTs,
      remoteEpochIsMillis: remoteEpochIsMillis,
    ) ?? [];
  }

  /// تنظيف outbox بعد سحب البيانات من السحابة بنجاح.
  /// يحذف عناصر outbox التي تتطابق مع بيانات تم سحبها فعلياً (بنفس entity + localUuid).
  /// المنطق: إذا السحابة أرسلت هذا السجل فلا حاجة لإعادة إرساله عبر outbox.
  /// ✅ فصل هندسي: يحذف فقط عناصر source='local' — لا يمس عناصر 'restore'
  /// ✅ تنظيف outbox بعد السحب: يحذف فقط عناصر outbox التي تم سحب
  /// بياناتها المطابقة من السحابة. لا يحذف عناصر outbox للبيانات
  /// التي لم تُسحب (حماية التغييرات المحلية المشروعة).
  ///
  /// المنطق: إذا تم سحب بيانات من Appwrite وكان lastModified البعيد
  /// أكبر من أو يساوي المحلي، فهذا يعني أن السحابة لديها نفس
  /// البيانات أو أحدث، وبالتالي لا حاجة لإعادة إرسالها.
  Future<int> _cleanupOutboxAfterPull() async {
    int totalRemoved = 0;

    // الكيانات الرئيسية التي يتم مزامنتها مع جدول UUID المقابل
    const entityUuidMap = {
      'rooms': 'rooms',
      'bookings': 'bookings',
      'employees': 'employees',
      'expenses': 'expenses',
      'payments': 'payments',
      'debts': 'debts',
      'guest_infos': 'guest_infos',
      'salary_withdrawals': 'salary_withdrawals',
      'salary_carry_over_logs': 'salary_carry_over_logs',
      'booking_price_adjustments': 'booking_price_adjustments',
      'shift_notes': 'shift_notes',
      'blacklist': 'blacklist',
      'booking_notes': 'booking_notes',
      'booking_nights': 'booking_nights',
      'cash_transactions': 'cash_transactions',
      'salary_cycles': 'salary_cycles',
      'salary_payments': 'salary_payments',
      'price_adjustments': 'price_adjustments',
      'audit_logs': 'audit_logs',
      'payment_voids': 'payment_voids',
    };

    for (final entity in entityUuidMap.keys) {
      try {
        // جلب عناصر outbox المعلقة فقط (pending أو failed)
        // لا نحذف العناصر في حالة 'processing' لأنها قيد الرفع حالياً
        final outboxEntries = await (database.select(database.outbox)
              ..where((t) =>
                  t.entity.equals(entity) &
                  t.source.equals('local') &
                  t.processingStatus.isIn(['pending', 'failed'])))
            .get();

        if (outboxEntries.isEmpty) continue;

        // ✅ فحص كل عنصر: هل البيانات المحلية لا تزال أقدم من السحابة؟
        // إذا كان outbox entry يمثل تغييراً محلياً لم يُرفع بعد،
        // والسحابة ليس لديها بيانات أحدث لهذا localUuid،
        // يجب إبقاء العنصر في outbox.
        //
        // ⚠️ إصلاح حرج (audit agent-5):
        // المنطق السابق كان يحذف العنصر إذا كان `origin == 'server'` حتى لو
        // كان `entry.source == 'local'` (تغيير محلي فعلي). المشكلة أن
        // `updateById` و `softDelete` لا يُحدّثان حقل `origin` إلى `'local'`
        // عند التعديل المحلي، فتبقى القيمة `'server'` من السحب السابق.
        // هذا يسبب فقدان صامت للتغييرات المحلية المعلقة في outbox.
        //
        // المنطق الجديد: نعتمد على `entry.source == 'local'` كدليل قاطع على
        // وجود تغيير محلي لم يُرفع. نحذف العنصر فقط في حالتين:
        //   (أ) السجل المحلي لم يعد موجوداً (حُذف نهائياً)
        //   (ب) السجل المحلي أحدث من `entry.clientTs` (السحب حدّثه فعلاً
        //       بقيمة أحدث من التغيير المعلق — وهذا نادر لأن السحب يحترم
        //       lastModified المحلي الأحدث عبر _isRemoteDataNewer)
        final uuidsToRemove = <String>[];
        for (final entry in outboxEntries) {
          // فقط عناصر source='local' تفحص (الاستعلام أعلاه يضمن ذلك)
          final localData = await _getLocalLastModified(entity, entry.localUuid);
          if (localData == null) {
            // لا يوجد سجل محلي — ربما تم حذفه نهائياً، نحذف outbox entry
            uuidsToRemove.add(entry.localUuid);
            continue;
          }

          if (localData > entry.clientTs) {
            // البيانات المحلية أحدث من outbox entry — يعني السحب حدّثها
            // بقيمة أحدث من التغيير المعلق. آمن الحذف.
            uuidsToRemove.add(entry.localUuid);
          }
          // في جميع الحالات الأخرى (localData == clientTs أو localData < clientTs):
          // التغيير المحلي لا يزال صالحاً ويحتاج الرفع — نبقي العنصر.
          // ✅ هذا يحمي التغييرات المحلية المعلقة من الحذف الخاطئ.
        }

        if (uuidsToRemove.isEmpty) continue;

        final removed =
            await outboxDao.removePulledEntities(uuidsToRemove, entity: entity);
        totalRemoved += removed;
      } catch (e) {
        _logger.warning('فشل تنظيف outbox للكيان $entity: $e', tag: 'SYNC');
      }
    }

    return totalRemoved;
  }

  /// ✅ تنظيف سجلات Outbox للكيانات المحذوفة (soft-delete أو hard-delete)
  /// 1. يجمع localUuid لجميع عناصر outbox الحالية
  /// 2. يتحقق من وجودها محلياً ومن حالة الحذف
  /// 3. يزيل سجلات outbox المُكتملة للكيانات المحذوفة softly
  /// 4. يزيل سجلات outbox المعلقة/الفاشلة للكيانات المحذوفة نهائياً
  Future<int> _cleanupOutboxForDeletedEntities() async {
    int totalRemoved = 0;

    try {
      // جلب جميع عناصر outbox غير المُعالجة حالياً
      final entries = await (database.select(database.outbox)
            ..where((t) => t.processingStatus.isIn(['pending', 'failed', 'completed'])))
          .get();

      if (entries.isEmpty) return 0;

      final softDeletedUuids = <String, int?>{};
      final missingUuids = <String>[];

      for (final entry in entries) {
        final deletedAt = await _getLocalEntityDeletedAt(entry.entity, entry.localUuid);
        if (deletedAt == null) {
          // الكيان غير موجود محلياً (hard-delete)
          if (entry.processingStatus != 'completed') {
            missingUuids.add(entry.localUuid);
          }
        } else if (deletedAt > 0) {
          // الكيان محذوف softly — نظّف سجل outbox المُكتمل فقط
          softDeletedUuids[entry.localUuid] = deletedAt;
        }
      }

      // تنظيف سجلات outbox المُكتملة للكيانات المحذوفة softly
      if (softDeletedUuids.isNotEmpty) {
        totalRemoved += await outboxDao.cleanupForSoftDeletedEntities(softDeletedUuids);
      }

      // تنظيف سجلات outbox المعلقة/الفاشلة للكيانات غير الموجودة
      if (missingUuids.isNotEmpty) {
        totalRemoved += await outboxDao.cleanupForMissingEntities(missingUuids);
      }
    } catch (e) {
      _logger.warning('فشل تنظيف outbox للكيانات المحذوفة: $e', tag: 'SYNC');
    }

    return totalRemoved;
  }

  /// جلب deletedAt لكيان محلي بناءً على entity و localUuid
  /// يُعيد null إذا الكيان غير موجود، أو 0 إذا موجود وغير محذوف
  Future<int?> _getLocalEntityDeletedAt(String entity, String localUuid) async {
    try {
      switch (entity) {
        case 'bookings':
          final b = await _getBookingByLocalUuid(localUuid);
          return b?.deletedAt;
        case 'rooms':
          final r = await _getRoomByLocalUuid(localUuid);
          return r?.deletedAt;
        case 'employees':
          final e = await _getEmployeeByLocalUuid(localUuid);
          return e?.deletedAt;
        case 'expenses':
          final e = await _getExpenseByLocalUuid(localUuid);
          return e?.deletedAt;
        case 'payments':
          final p = await _getPaymentByLocalUuid(localUuid);
          return p?.deletedAt;
        case 'debts':
          final d = await _getDebtByLocalUuid(localUuid);
          return d?.deletedAt;
        default:
          return null;
      }
    } catch (_) {
      return null;
    }
  }

  /// جلب lastModified لسجل محلي بناءً على entity و localUuid
  Future<int?> _getLocalLastModified(String entity, String localUuid) async {
    switch (entity) {
      case 'rooms':
        return _getLocalRoomLastModified(localUuid);
      case 'bookings':
        return _getLocalBookingLastModified(localUuid);
      case 'employees':
        return _getLocalEmployeeLastModified(localUuid);
      case 'expenses':
        return _getLocalExpenseLastModified(localUuid);
      case 'payments':
        return _getLocalPaymentLastModified(localUuid);
      case 'debts':
        return _getLocalDebtLastModified(localUuid);
      case 'guest_infos':
        return _getLocalGuestInfoLastModified(localUuid);
      case 'salary_withdrawals':
        return _getLocalSalaryWithdrawalLastModified(localUuid);
      case 'salary_carry_over_logs':
        return _getLocalSalaryCarryOverLogLastModified(localUuid);
      case 'booking_price_adjustments':
        return _getLocalBookingPriceAdjustmentLastModified(localUuid);
      case 'shift_notes':
      case 'blacklist':
        return _getLocalShiftNoteLastModified(localUuid);
      case 'booking_notes':
        return _getLocalBookingNoteLastModified(localUuid);
      case 'booking_nights':
        return _getLocalBookingNightLastModified(localUuid);
      case 'cash_transactions':
        return _getLocalCashTransactionLastModified(localUuid);
      case 'salary_cycles':
        return _getLocalSalaryCycleLastModified(localUuid);
      case 'salary_payments':
        return _getLocalSalaryPaymentLastModified(localUuid);
      case 'price_adjustments':
        return _getLocalPriceAdjustmentLastModified(localUuid);
      case 'audit_logs':
        return _getLocalAuditLogLastModified(localUuid);
      case 'payment_voids':
        return _getLocalPaymentVoidLastModified(localUuid);
      default:
        // للكيانات غير المعروفة، نعيد null — الحذف الآمن
        return null;
    }
  }

  /// جلب حقل origin لسجل محلي بناءً على entity و localUuid
  /// يُستخدم لتحديد ما إذا كانت البيانات قادمة من السيرفر ('server')
  /// أو تم إنشاؤها محلياً ('local')
  // ignore: unused_element
  Future<String?> _getLocalOrigin(String entity, String localUuid) async {
    try {
      // استخدام استعلام SQL مباشر لتجنب مشاكل الأنواع العامة في Drift
      final tableName = _entityToTableName(entity);
      if (tableName == null) return null;

      final rows = await database.customSelect(
        'SELECT origin FROM $tableName WHERE local_uuid = ? LIMIT 1',
        variables: [drift.Variable.withString(localUuid)],
        readsFrom: Set.unmodifiable({}),
      ).get();

      if (rows.isEmpty) return null;
      return rows.first.data['origin']?.toString();
    } catch (e) {
      _logger.debug('Failed to get origin for $entity/$localUuid: $e', tag: 'SYNC');
      return null;
    }
  }

  /// تحويل اسم الكيان إلى اسم الجدول في قاعدة البيانات
  String? _entityToTableName(String entity) {
    switch (entity) {
      case 'rooms':
        return 'rooms';
      case 'bookings':
        return 'bookings';
      case 'employees':
        return 'employees';
      case 'expenses':
        return 'expenses';
      case 'payments':
        return 'payments';
      case 'debts':
        return 'debts';
      case 'guest_infos':
        return 'guest_infos';
      case 'salary_withdrawals':
        return 'salary_withdrawals';
      case 'salary_carry_over_logs':
        return 'salary_carry_over_logs';
      case 'booking_price_adjustments':
        return 'booking_price_adjustments';
      case 'shift_notes':
      case 'blacklist':
        return 'shift_notes';
      case 'booking_notes':
        return 'booking_notes';
      case 'booking_nights':
        return 'booking_nights';
      case 'cash_transactions':
        return 'cash_transactions';
      case 'salary_cycles':
        return 'salary_cycles';
      case 'salary_payments':
        return 'salary_payments';
      case 'price_adjustments':
        return 'price_adjustments';
      case 'audit_logs':
        return null; // AuditLogs لا تحتوي على حقل origin
      case 'payment_voids':
        return 'payment_voids';
      default:
        return null;
    }
  }

  Future<int?> _getLocalRoomLastModified(String localUuid) async {
    final row = await (database.select(database.rooms)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalBookingLastModified(String localUuid) async {
    final row = await (database.select(database.bookings)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalEmployeeLastModified(String localUuid) async {
    final row = await (database.select(database.employees)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalExpenseLastModified(String localUuid) async {
    final row = await (database.select(database.expenses)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalPaymentLastModified(String localUuid) async {
    final row = await _getPaymentByLocalUuid(localUuid);
    return row?.lastModified;
  }

  Future<int?> _getLocalDebtLastModified(String localUuid) async {
    final row = await _getDebtByLocalUuid(localUuid);
    return row?.lastModified;
  }

  Future<int?> _getLocalGuestInfoLastModified(String localUuid) async {
    final row = await (database.select(database.guestInfos)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalSalaryWithdrawalLastModified(String localUuid) async {
    final row = await (database.select(database.salaryWithdrawals)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalSalaryCarryOverLogLastModified(String localUuid) async {
    final row = await (database.select(database.salaryCarryOverLogs)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalBookingPriceAdjustmentLastModified(
    String localUuid,
  ) async {
    final row = await (database.select(database.bookingPriceAdjustments)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalShiftNoteLastModified(String localUuid) async {
    final row = await (database.select(database.shiftNotes)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalBookingNoteLastModified(String localUuid) async {
    final row = await (database.select(database.bookingNotes)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalBookingNightLastModified(String localUuid) async {
    final row = await (database.select(database.bookingNights)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalCashTransactionLastModified(String localUuid) async {
    final row = await (database.select(database.cashTransactions)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalSalaryCycleLastModified(String localUuid) async {
    final row = await (database.select(database.salaryCycles)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalSalaryPaymentLastModified(String localUuid) async {
    final row = await (database.select(database.salaryPayments)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalPriceAdjustmentLastModified(String localUuid) async {
    final row = await (database.select(database.priceAdjustments)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  Future<int?> _getLocalAuditLogLastModified(String localUuid) async {
    final row = await (database.select(database.auditLogs)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    // AuditLogs لا تحتوي على lastModified — نستخدم timestamp
    return row?.timestamp;
  }

  Future<int?> _getLocalPaymentVoidLastModified(String localUuid) async {
    final row = await (database.select(database.paymentVoids)
          ..where((t) => t.localUuid.equals(localUuid))
          ..limit(1))
        .getSingleOrNull();
    return row?.lastModified;
  }

  /// قراءة آخر timestamp لسحب البيانات من جدول SyncState
  Future<int> _getLastPullTs() async {
    return _pullService?.getLastPullTs() ?? 0;
  }

  /// تحديث آخر timestamp لسحب البيانات في جدول SyncState
  /// ✅ نستخدم insertOnConflictUpdate بدلاً من update فقط
  /// لأن صف SyncState (id=1) قد لا يكون موجوداً بعد، مما يجعل UPDATE
  /// لا يؤثر على أي صف — وبالتالي lastPullTs يبقى 0 للأبد،
  /// وكل مزامنة تسحب كل البيانات بدلاً من التغييرات فقط (delta).
  Future<void> _updateLastPullTs(int ts) async {
    await _pullService?.updateLastPullTs(ts);
  }


  /// الحصول على قائمة الأجهزة المسجلة
  /// [limit] عدد الأجهزة المطلوبة (افتراضياً 2)
  /// يحاول الترتيب من الخادم أولاً، وإذا فشل (لا يوجد فهرس) يرجع للترتيب المحلي
  Future<List<AppwriteDevice>> getRegisteredDevices({int limit = 2}) async {
    try {
      // محاولة جلب آخر الأجهزة مرتبة من الخادم (يتطلب فهرس على lastSeen)
      final devices = await appwriteService.listDevices(
        queries: [
          Query.orderDesc('lastSeen'),
          Query.limit(limit),
        ],
        useCache: false,
      );
      return devices.map((doc) => AppwriteDevice.fromJson(doc.data)).toList();
    } catch (e) {
      // إذا فشل الترتيب (مثلاً لا يوجد فهرس على lastSeen)، نستخدم الطريقة البديلة
      _logger.warning(
        'orderDesc(lastSeen) failed, falling back to local sort: $e',
        tag: 'SYNC',
      );
      try {
        final devices = await appwriteService.listDevices(useCache: false);
        final mapped = devices
            .map((doc) => AppwriteDevice.fromJson(doc.data))
            .toList();
        mapped.sort((a, b) => b.lastSeen.compareTo(a.lastSeen));
        return mapped.take(limit).toList();
      } catch (e2) {
        _logger.error(
          'Failed to get registered devices',
          error: e2,
          tag: 'SYNC',
        );
        return [];
      }
    }
  }

  /// رفع التغييرات المحلية إلى Appwrite فوراً
  Future<bool> pushLocalChanges() async {
    try {
      final result = await sync(pull: false);
      return result.status == SyncStatus.success;
    } catch (e, stackTrace) {
      _logger.error(
        'pushLocalChanges failed via sync()',
        error: e,
        stackTrace: stackTrace,
        tag: 'SYNC',
      );
      await CrashlyticsService.instance.recordSyncError(
        operation: 'pushLocalChanges', error: e.toString(), stackTrace: stackTrace,
      );
      return false;
    }
  }

  /// سحب التغييرات من Appwrite
  /// يُرجع true إذا كانت هناك تغييرات جديدة تم تطبيقها
  /// Guarded by [SyncLocks.appwriteSyncLock] to prevent concurrent pulls.
  /// All collection syncs are wrapped in a single database transaction for atomicity.
  Future<bool> pullRemoteChanges() async {
    return await SyncLocks.appwriteSyncLock.synchronized(() async {
      if (_currentStatus == SyncStatus.syncing) {
        _logger.warning('⏸️ تخطي السحب - المزامنة جارية', tag: 'SYNC');
        return false;
      }

      try {
        _logger.info('📥 سحب التغييرات من Appwrite...', tag: 'SYNC');

        int recordsPulled = 0;

        // Delta Sync: قراءة آخر timestamp وإنشاء فلتر
        final lastPullTs = await _getLastPullTs();
        final List<String> deltaQ = await (_pullService?.buildDeltaQueries(lastPullTs) ?? <String>[]);
        final isDelta = deltaQ.isNotEmpty;
        if (isDelta) {
          _logger.info(
            '🔄 Delta Sync: جلب التغييرات منذ ${DateTime.fromMillisecondsSinceEpoch(lastPullTs * 1000).toIso8601String()}',
            tag: 'SYNC',
          );
        } else {
          _logger.info('🔄 Full Sync: أول مزامنة أو إعادة كاملة', tag: 'SYNC');
        }

        // Wrap all collection syncs in a single transaction for atomicity.
        // Individual collection failures are caught internally so partial progress
        // is preserved, but the entire batch either commits or rolls back together.
        await database.transaction(() async {
          // مزامنة كل كولكشن بشكل مستقل — فشل واحد لا يوقف الباقي
          try {
            final rooms = await appwriteService.listRooms(queries: deltaQ, useCache: false);
            recordsPulled += await _syncRooms(rooms);
          } catch (e, st) {
            _logger.error('❌ فشل سحب rooms (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final bookings = await appwriteService.listBookings(queries: deltaQ, useCache: false);
            recordsPulled += await _syncBookings(bookings);
          } catch (e, st) {
            _logger.error('❌ فشل سحب bookings (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final employees = await appwriteService.listEmployees(queries: deltaQ, useCache: false);
            recordsPulled += await _syncEmployees(employees);
          } catch (e, st) {
            _logger.error('❌ فشل سحب employees (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final expenses = await appwriteService.listExpenses(queries: deltaQ, useCache: false);
            recordsPulled += await _syncExpenses(expenses);
          } catch (e, st) {
            _logger.error('❌ فشل سحب expenses (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final payments = await appwriteService.listPayments(queries: deltaQ, useCache: false);
            recordsPulled += await _syncPayments(payments);
          } catch (e, st) {
            _logger.error('❌ فشل سحب payments (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final debts = await appwriteService.listDebts(queries: deltaQ, useCache: false);
            recordsPulled += await _syncDebts(debts);
          } catch (e, st) {
            _logger.error('❌ فشل سحب debts (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final guestInfos = await appwriteService.listGuestInfos(queries: deltaQ, useCache: false);
            recordsPulled += await _syncGuestInfos(guestInfos);
          } catch (e, st) {
            _logger.error('❌ فشل سحب guest_infos (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final salaryWithdrawals = await appwriteService.listSalaryWithdrawals(queries: deltaQ, useCache: false);
            recordsPulled += await _syncSalaryWithdrawals(salaryWithdrawals);
          } catch (e, st) {
            _logger.error('❌ فشل سحب salary_withdrawals (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final bookingPriceAdjustments = await appwriteService.listDocuments(
              collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
              queries: deltaQ,
            );
            recordsPulled += await _syncBookingPriceAdjustments(bookingPriceAdjustments);
          } catch (e, st) {
            _logger.error('❌ فشل سحب booking_price_adjustments (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final shiftNotes = await appwriteService.listShiftNotes(queries: deltaQ, useCache: false);
            recordsPulled += await _syncShiftNotes(shiftNotes);
          } catch (e, st) {
            _logger.error('❌ فشل سحب shift_notes (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final blacklistDocs = await appwriteService.listBlacklist(queries: deltaQ, useCache: false);
            recordsPulled += await _syncBlacklist(blacklistDocs);
          } catch (e, st) {
            _logger.error('❌ فشل سحب blacklist (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final bookingNotes = await appwriteService.listBookingNotes(
              queries: deltaQ,
              useCache: false,
            );
            recordsPulled += await _syncBookingNotes(bookingNotes);
          } catch (e, st) {
            _logger.error('❌ فشل سحب booking_notes (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            // booking_nights يستخدم lastPullTs خاص به (مستقل عن باقي الجداول)
            final nightsPullTs = await _getBookingNightsPullTs();
            final bool remoteEpochIsMillis = await (_pullService?.isRemoteEpochMillis() ?? false);
            final nightsDeltaQ = _bookingNightsDeltaQueries(
              nightsPullTs,
              remoteEpochIsMillis: remoteEpochIsMillis,
            );
            final bookingNights = await appwriteService.listBookingNights(
              queries: nightsDeltaQ,
              useCache: false,
            );
            recordsPulled += await _syncBookingNights(bookingNights);
            await _updateBookingNightsPullTs(Time.nowEpoch());
          } catch (e, st) {
            _logger.error('❌ فشل سحب booking_nights (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final cashTransactions = await appwriteService.listCashTransactions(
              queries: deltaQ,
              useCache: false,
            );
            recordsPulled += await _syncCashTransactions(cashTransactions);
          } catch (e, st) {
            _logger.error('❌ فشل سحب cash_transactions (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final salaryCycles = await appwriteService.listSalaryCycles(
              queries: deltaQ,
              useCache: false,
            );
            recordsPulled += await _syncSalaryCycles(salaryCycles);
          } catch (e, st) {
            _logger.error('❌ فشل سحب salary_cycles (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final salaryPayments = await appwriteService.listSalaryPayments(
              queries: deltaQ,
              useCache: false,
            );
            recordsPulled += await _syncSalaryPayments(salaryPayments);
          } catch (e, st) {
            _logger.error('❌ فشل سحب salary_payments (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final priceAdjustments = await appwriteService.listDocuments(
              collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
              queries: deltaQ,
            );
            recordsPulled += await _syncPriceAdjustments(priceAdjustments);
          } catch (e, st) {
            _logger.error('❌ فشل سحب price_adjustments (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final auditLogs = await appwriteService.listDocuments(
              collectionId: AppwriteConfig.auditLogsCollectionId,
              queries: deltaQ,
            );
            recordsPulled += await _syncAuditLogs(auditLogs);
          } catch (e, st) {
            _logger.error('❌ فشل سحب audit_logs (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          try {
            final paymentVoids = await appwriteService.listDocuments(
              collectionId: AppwriteConfig.paymentVoidsCollectionId,
              queries: deltaQ,
            );
            recordsPulled += await _syncPaymentVoids(paymentVoids);
          } catch (e, st) {
            _logger.error('❌ فشل سحب payment_voids (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          // ❌ hotel_day_ledger - محلي فقط، لا يتم مزامنته

          // تحديث lastPullTs بعد محاولة سحب كل الكولكشنات
          await _updateLastPullTs(Time.nowEpoch());
        });

        _lastSyncTime = DateTime.now();
        await _saveSettings();

        if (recordsPulled > 0) {
          _logger.info('✅ تم سحب $recordsPulled سجل من Appwrite', tag: 'SYNC');
          return true;
        } else {
          _logger.info('ℹ️ لا توجد تغييرات جديدة من Appwrite', tag: 'SYNC');
          return false;
        }
      } catch (e, stackTrace) {
        _logger.error(
          '❌ خطأ في سحب التغييرات من Appwrite',
          error: e,
          stackTrace: stackTrace,
          tag: 'SYNC',
        );
        await CrashlyticsService.instance.recordFatalSyncError(
          operation: 'pullRemoteChanges',
          error: e,
          stackTrace: stackTrace,
        );
        return false;
      }
    // ignore: dead_null_aware_expression
    }, timeout: const Duration(minutes: 5),) ?? false;
  }

  /// رفع جميع البيانات المحلية
  Future<void> pushAllLocalData() async {
    _logger.info('Pushing all local data...', tag: 'SYNC');
    await pushLocalChanges();
  }

  /// سحب جميع البيانات من Appwrite مع الحفاظ على Foreign Keys مفعّلة
  /// يُستخدم عند التثبيت الأول (المتابعة بدون مزامنة)
  /// ✅ إصلاح: لم نعد نعطل FK — ترتيب السحب يضمن وجود الآباء قبل الأبناء
  /// ونمط التأجيل/إعادة المحاولة يعالج الحالات الاستثنائية
  Future<void> pullAllDataWithDisabledFK() async {
    if (_currentStatus == SyncStatus.syncing) {
      _logger.warning('⏸️ تخطي السحب - المزامنة جارية', tag: 'SYNC');
      return;
    }

    _logger.info('📥 سحب شامل مع الحفاظ على Foreign Keys مفعّلة...', tag: 'SYNC');

    // ✅ لم نعد نعطل FOREIGN KEY — ترتيب السحب + نمط التأجيل يكفيان
    try {
      await pullRemoteChanges();
      _logger.info('✅ تم السحب الشامل بنجاح', tag: 'SYNC');
    } finally {
      // ✅ تحقق من سلامة المفاتيح الأجنبية بعد السحب
      try {
        final violations = await database.customSelect(
          'PRAGMA foreign_key_check',
          readsFrom: Set.unmodifiable({}),
        ).get();
        if (violations.isNotEmpty) {
          developer.log(
            '⚠️ FK violations after sync: ${violations.length} rows',
            name: 'SyncSafety',
          );
        }
        // تشغيل فحص السلامة الشامل مع الإصلاح التلقائي
        await _performPostSyncIntegrityCheck();
      } catch (_) {}
    }
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
      'shift_notes': 0,
      'booking_price_adjustments': 0,
      'guest_infos': 0,
      'salary_withdrawals': 0,
      'salary_carry_over_logs': 0,
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
          await appwriteService.upsertRoom(room.localUuid, _filterPayload('rooms', payload));
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
          await appwriteService.upsertEmployee(employee.localUuid, _filterPayload('employees', payload));
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
          await appwriteService.upsertBooking(booking.localUuid, _filterPayload('bookings', payload));
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
          await appwriteService.upsertExpense(expense.localUuid, _filterPayload('expenses', payload));
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
          await appwriteService.upsertPayment(payment.localUuid, _filterPayload('payments', payload));
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
          await appwriteService.upsertDebt(debt.localUuid, _filterPayload('debts', payload));
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
          await appwriteService.upsertBookingNote(note.localUuid, _filterPayload('booking_notes', payload));
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
          await appwriteService.upsertBookingNight(night.localUuid, _filterPayload('booking_nights', payload));
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
            _filterPayload('cash_transactions', payload),
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
          await appwriteService.upsertSalaryCycle(cycle.localUuid, _filterPayload('salary_cycles', payload));
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
          await appwriteService.upsertSalaryPayment(payment.localUuid, _filterPayload('salary_payments', payload));
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

      // رفع ملاحظات الشيفت
      final shiftNotes = await database.select(database.shiftNotes).get();
      for (final item in shiftNotes) {
        if (skipDeleted && item.deletedAt != null) continue;
        try {
          final payload = _shiftNoteToRemote(item);
          await appwriteService.upsertShiftNote(item.localUuid, _filterPayload('shift_notes', payload));
          stats['shift_notes'] = (stats['shift_notes'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع ملاحظة شيفت: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['shift_notes']} ملاحظة شيفت', tag: 'SYNC');

      // رفع تعديلات أسعار الحجوزات
      final adjustments = await database.select(database.bookingPriceAdjustments).get();
      for (final adj in adjustments) {
        if (skipDeleted && adj.deletedAt != null) continue;
        try {
          final payload = _adapterRegistry.bookingPriceAdjustments.adapter.toJson(
            adj,
            src: Source.appwrite,
          );
          await appwriteService.upsertDocument(
            collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
            documentId: adj.localUuid,
            data: _filterPayload('booking_price_adjustments', payload),
          );
          stats['booking_price_adjustments'] = (stats['booking_price_adjustments'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع تعديل سعر حجز: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['booking_price_adjustments']} تعديل سعر حجز', tag: 'SYNC');

      // رفع معلومات النزلاء
      final guestInfos = await database.select(database.guestInfos).get();
      for (final info in guestInfos) {
        if (skipDeleted && info.deletedAt != null) continue;
        try {
          final payload = _adapterRegistry.guestInfos.adapter.toJson(
            info,
            src: Source.appwrite,
          );
          await appwriteService.upsertDocument(
            collectionId: AppwriteConfig.guestInfosCollectionId,
            documentId: info.localUuid,
            data: _filterPayload('guest_infos', payload),
          );
          stats['guest_infos'] = (stats['guest_infos'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع معلومة نزيل: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['guest_infos']} معلومة نزيل', tag: 'SYNC');

      // رفع سحوبات الرواتب
      final salaryWithdrawals = await database.select(database.salaryWithdrawals).get();
      for (final withdrawal in salaryWithdrawals) {
        if (skipDeleted && withdrawal.deletedAt != null) continue;
        try {
          final payload = _adapterRegistry.salaryWithdrawals.adapter.toJson(
            withdrawal,
            src: Source.appwrite,
          );
          await appwriteService.upsertDocument(
            collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
            documentId: withdrawal.localUuid,
            data: _filterPayload('salary_withdrawals', payload),
          );
          stats['salary_withdrawals'] = (stats['salary_withdrawals'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع سحب راتب: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['salary_withdrawals']} سحب راتب', tag: 'SYNC');

      // ✅ رفع سجلات ترحيل الراتب
      final carryOverLogs = await database.select(database.salaryCarryOverLogs).get();
      _logger.info('📦 وُجد ${carryOverLogs.length} سجل ترحيل راتب', tag: 'SYNC');
      for (final log in carryOverLogs) {
        if (log.deletedAt != null) continue;
        try {
          final payload = _adapterRegistry.salaryCarryOverLogs.adapter.toJson(
            log,
            src: Source.appwrite,
          );
          await appwriteService.upsertDocument(
            collectionId: 'salary_carry_over_logs',
            documentId: log.localUuid,
            data: _filterPayload('salary_carry_over_logs', payload),
          );
          stats['salary_carry_over_logs'] = (stats['salary_carry_over_logs'] ?? 0) + 1;
        } catch (e) {
          _logger.warning('خطأ في رفع سجل ترحيل: $e', tag: 'SYNC');
          stats['errors'] = (stats['errors'] ?? 0) + 1;
        }
      }
      _logger.info('✅ تم رفع ${stats['salary_carry_over_logs']} سجل ترحيل راتب', tag: 'SYNC');

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
          stats['shift_notes']! +
          (stats['booking_price_adjustments'] ?? 0) +
          (stats['guest_infos'] ?? 0) +
          (stats['salary_withdrawals'] ?? 0) +
          (stats['salary_carry_over_logs'] ?? 0);

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
      await CrashlyticsService.instance.recordFatalSyncError(
        operation: 'pushAllLocalDataToAppwrite',
        error: e,
        stackTrace: stackTrace,
      );
      await WhatsAppNotificationService.instance.notifySyncError(
        operation: 'bulk_push',
        error: e.toString(),
      );
      rethrow;
    }
  }

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
      'deviceId': employee.deviceId,
    };
    _putIfNotNull(data, 'serverId', employee.serverId);
    data['deletedAt'] = employee.deletedAt;
    return data;
  }

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
      'sync_origin': note.origin,
      'deviceId': note.deviceId,
    };
    _putIfNotNull(data, 'serverId', note.serverId);
    data['deletedAt'] = note.deletedAt;
    _putIfStringNotEmpty(data, 'alertUntil', note.alertUntil);
    return data;
  }

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
      'vectorClock': night.vectorClock,
      'deviceId': night.deviceId,
    };
    _putIfNotNull(data, 'serverId', night.serverId);
    data['deletedAt'] = night.deletedAt;
    _putIfStringNotEmpty(data, 'appliedAdjustmentUuid', night.appliedAdjustmentUuid);
    _putIfStringNotEmpty(data, 'appliedAdjustmentsJson', night.appliedAdjustmentsJson);
    return data;
  }

  Map<String, dynamic> _cashTransactionToRemote(CashTransaction transaction) {
    final data = <String, dynamic>{
      'transactionType': transaction.transactionType,
      'amount': transaction.amount.round(), // Appwrite: integer
      'transactionTime': transaction.transactionTime,
      'localUuid': transaction.localUuid,
      'createdAt': transaction.createdAt,
      'updatedAt': transaction.updatedAt,
      'lastModified': transaction.lastModified,
      'version': transaction.version,
      'origin': transaction.origin,
      'deviceId': transaction.deviceId,
    };
    _putIfNotNull(data, 'registerId', transaction.registerId);
    _putIfNotNull(data, 'referenceId', transaction.referenceId);
    _putIfNotNull(data, 'createdBy', transaction.createdBy);
    _putIfNotNull(data, 'serverId', transaction.serverId);
    data['deletedAt'] = transaction.deletedAt;
    _putIfStringNotEmpty(data, 'referenceType', transaction.referenceType);
    _putIfStringNotEmpty(data, 'description', transaction.description);
    return data;
  }

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
      'vectorClock': cycle.vectorClock,
      'deviceId': cycle.deviceId,
    };
    _putIfNotNull(data, 'serverId', cycle.serverId);
    data['deletedAt'] = cycle.deletedAt;
    _putIfStringNotEmpty(data, 'hotelDayStart', cycle.hotelDayStart);
    _putIfStringNotEmpty(data, 'hotelDayEnd', cycle.hotelDayEnd);
    return data;
  }

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
      'deviceId': payment.deviceId,
    };
    _putIfNotNull(data, 'serverId', payment.serverId);
    data['deletedAt'] = payment.deletedAt;
    _putIfStringNotEmpty(data, 'hotelDayKey', payment.hotelDayKey);
    _putIfStringNotEmpty(data, 'method', payment.method);
    return data;
  }

  Map<String, dynamic> _shiftNoteToRemote(ShiftNote note) {
    final createdDate = DateTime.fromMillisecondsSinceEpoch(
      note.createdAt * 1000,
    );
    final shiftDate = createdDate.toIso8601String().substring(0, 10);
    final data = <String, dynamic>{
      'localUuid': note.localUuid,
      'title': note.title,
      'content': note.content,
      'priority': note.priority,
      'shiftType': note.shiftType,
      'isRead': note.isRead == 1, // Appwrite يتوقع boolean
      'createdAt': note.createdAt, // Appwrite يتوقع integer epoch
      'updatedAt': note.updatedAt, // integer epoch — مطلوب
      'lastModified': note.lastModified, // مطلوب للـ Delta Sync
      'createdBy': note.createdBy,
      'shiftDate': shiftDate, // مطلوب — مشتق من createdAt
      'deviceId': note.deviceId,
      // ✅ تم حذف حقل 'note' المكرر — Appwrite shift_notes لا يملكه (يستخدم content)
    };
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
      _filterPayload('salary_payments', _addIdempotencyKey(payload, entry)),
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
      _filterPayload('cash_transactions', _addIdempotencyKey(payload, entry)),
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
      _filterPayload('shift_notes', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Future<ShiftNote?> _getShiftNoteByLocalUuid(String uuid) {
    return (database.select(database.shiftNotes)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  // ─── Blacklist ──────────────────────────────────────────────────────────

  /// ✅ رفع سجل ترحيل الراتب إلى Appwrite
  Future<bool> _processSalaryCarryOverLogEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: 'salary_carry_over_logs',
          documentId: entry.localUuid,
        ),
      );
      return true;
    }
    final log = await (database.select(database.salaryCarryOverLogs)
          ..where((t) => t.localUuid.equals(entry.localUuid))
          ..limit(1))
        .getSingleOrNull();
    if (log == null) {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: 'salary_carry_over_logs',
          documentId: entry.localUuid,
        ),
      );
      return true;
    }
    final payload = _adapterRegistry.salaryCarryOverLogs.adapter.toJson(
      log,
      src: Source.appwrite,
    );
    await appwriteService.upsertDocument(
      collectionId: 'salary_carry_over_logs',
      documentId: entry.localUuid,
      data: _filterPayload('salary_carry_over_logs', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Future<bool> _processBlacklistEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteBlacklist(entry.localUuid),
      );
      return true;
    }
    final item = await _getBlacklistShiftNoteByLocalUuid(entry.localUuid);
    if (item == null) {
      await _deleteSilently(
        () => appwriteService.deleteBlacklist(entry.localUuid),
      );
      return true;
    }

    final payload = _blacklistToRemote(item);
    await appwriteService.upsertBlacklist(
      item.localUuid,
      _filterPayload('blacklist', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Future<ShiftNote?> _getBlacklistShiftNoteByLocalUuid(String uuid) {
    return (database.select(database.shiftNotes)
          ..where((t) =>
              t.localUuid.equals(uuid) &
              t.createdBy.equals('blacklist'),)
          ..limit(1))
        .getSingleOrNull();
  }

  // ─── PriceAdjustments ─────────────────────────────────────────────────

  Future<bool> _processPriceAdjustmentEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
          documentId: entry.localUuid,
        ),
      );
      return true;
    }

    // جلب السجل المحلي للحصول على البيانات الكاملة
    final localRow = await (database.select(database.priceAdjustments)
          ..where((t) => t.localUuid.equals(entry.localUuid))
          ..limit(1))
        .getSingleOrNull();

    if (localRow == null) {
      // السجل غير موجود محلياً — نحذف من Appwrite أيضاً
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
          documentId: entry.localUuid,
        ),
      );
      return true;
    }

    final payload = _priceAdjustmentToRemote(localRow);
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
      documentId: localRow.localUuid,
      data: _filterPayload('price_adjustments', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Map<String, dynamic> _priceAdjustmentToRemote(PriceAdjustment row) {
    final now = Time.nowEpoch();
    return {
      'localUuid': row.localUuid,
      'targetType': row.targetType,
      'targetUuid': row.targetUuid,
      'adjustmentType': row.adjustmentType,
      'previousValue': row.previousValue,
      'newValue': row.newValue,
      'reason': row.reason,
      'effectiveDate': row.effectiveDate,
      'appliedBy': row.appliedBy,
      'hotelDayKey': row.hotelDayKey,
      'isReversed': row.isReversed,
      'reversedAt': row.reversedAt,
      'reversedBy': row.reversedBy,
      'createdAt': row.createdAt,
      'updatedAt': now,
      'lastModified': now,
      'origin': 'mobile',
      'syncTimestamp': now,
      'deviceId': row.deviceId,
      if (row.serverId != null) 'serverId': row.serverId,
    };
  }

  Map<String, dynamic> _blacklistToRemote(ShiftNote item) {
    Map<String, dynamic> extra = {};
    try {
      extra = jsonDecode(item.content) as Map<String, dynamic>;
    } catch (e) { debugPrint('WARN: Failed to parse blacklist content for sync: $e'); }

    final now = Time.nowEpoch();
    // Appwrite blacklist collection: createdAt/updatedAt/deletedAt are STRING (ISO)
    final createdAtIso = item.createdAtIso ??
        DateTime.fromMillisecondsSinceEpoch(item.createdAt * 1000)
            .toIso8601String();
    final updatedAtIso = DateTime.fromMillisecondsSinceEpoch(item.updatedAt * 1000)
        .toIso8601String();

    return {
      'name': item.title,
      'nationality': (extra['nationality'] as String?) ?? '',
      'nationalId': (extra['nationalId'] as String?) ?? '',
      'phone': (extra['phone'] as String?) ?? '',
      'reason': (extra['reason'] as String?) ?? '',
      'notes': (extra['notes'] as String?) ?? '',
      'reportedBy': (extra['reportedBy'] as String?) ?? 'police',
      'active': (extra['active'] as bool?) ?? true,
      'localUuid': item.localUuid,
      'createdAt': createdAtIso,
      'createdAtIso': createdAtIso,
      'updatedAt': updatedAtIso,
      'updatedAtIso': updatedAtIso,
      'deletedAt': item.deletedAt != null
          ? DateTime.fromMillisecondsSinceEpoch(item.deletedAt! * 1000)
              .toIso8601String()
          : null,
      'lastModified': item.lastModified,
      'origin': 'mobile',
      'syncTimestamp': now,
      'deviceId': item.deviceId,
      if (item.serverId != null) 'serverId': item.serverId,
    };
  }

  Future<int> _syncBlacklist(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        final localUuid = (data['localUuid'] as String?) ?? doc.$id;
        final name = (data['name'] as String?) ?? '';

        // تحويل بيانات Appwrite إلى صيغة shift_notes المحلية
        final content = jsonEncode({
          'nationality': (data['nationality'] as String?) ?? '',
          'nationalId': (data['nationalId'] as String?) ?? '',
          'phone': (data['phone'] as String?) ?? '',
          'reason': (data['reason'] as String?) ?? '',
          'notes': (data['notes'] as String?) ?? '',
          'reportedBy': (data['reportedBy'] as String?) ?? 'police',
          'active': (data['active'] as bool?) ?? true,
        });

        // Appwrite blacklist: createdAt/updatedAt/deletedAt هي STRING (ISO)
        final createdAtIso = (data['createdAt'] as String?) ??
            (data['createdAtIso'] as String?) ??
            DateTime.now().toIso8601String();
        final updatedAtIso = (data['updatedAt'] as String?) ??
            (data['updatedAtIso'] as String?) ??
            createdAtIso;

        // تحويل ISO إلى epoch seconds لقاعدة البيانات المحلية
        int? createdAtEpoch;
        try {
          createdAtEpoch = DateTime.parse(createdAtIso).millisecondsSinceEpoch ~/ 1000;
        } catch (_) {
          createdAtEpoch = Time.nowEpoch();
        }
        int? updatedAtEpoch;
        try {
          updatedAtEpoch = DateTime.parse(updatedAtIso).millisecondsSinceEpoch ~/ 1000;
        } catch (_) {
          updatedAtEpoch = Time.nowEpoch();
        }

        // ✅ إصلاح حرج (audit agent-2): استخدام _asIntNullable بدلاً من _asInt
        // _asInt يرجع 0 عند غياب lastModified → يلوّث قاعدة البيانات المحلية
        // بقيمة 0 → كل سحب لاحق يرى المحلي "قديم جداً" ويستبدله → حلقة فقدان بيانات.
        final lastModified = _asIntNullable(data['lastModified']) ??
            _extractUpdatedAtSec(doc) ??
            Time.nowEpoch();
        final serverId = _asIntNullable(data['serverId']);

        // معالجة الحذف الناعم
        final deletedAtVal = data['deletedAt'];
        int? deletedAtEpoch;
        if (deletedAtVal != null) {
          final deletedAtStr = deletedAtVal as String?;
          if (deletedAtStr != null && deletedAtStr.isNotEmpty) {
            try {
              deletedAtEpoch = DateTime.parse(deletedAtStr).millisecondsSinceEpoch ~/ 1000;
            } catch (_) {
              deletedAtEpoch = _asIntNullable(deletedAtVal);
            }
          } else {
            deletedAtEpoch = _asIntNullable(deletedAtVal);
          }
        }

        // إذا كان السجل محذوفاً، نحذفه محلياً
        if (deletedAtEpoch != null && deletedAtEpoch > 0) {
          final existing = await (database.select(database.shiftNotes)
                ..where((t) => t.localUuid.equals(localUuid)))
              .getSingleOrNull();
          if (existing != null) {
            await (database.delete(database.shiftNotes)
                  ..where((t) => t.localUuid.equals(localUuid)))
                .go();
          }
          processed++;
          continue;
        }

        // ✅ إصلاح حرج (audit agent-2): فحص _isRemoteDataNewer قبل الكتابة
        // المنطق السابق كان يستبدل السجل المحلي بغض النظر عن lastModified.
        // الآن نفحص أولاً: إذا كان المحلي أحدث، نتخطى (نحمي تعديلات المستخدم).
        final existingForCheck = await (database.select(database.shiftNotes)
              ..where((t) => t.localUuid.equals(localUuid)))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(
          data,
          existingForCheck?.lastModified,
          localDeletedAt: existingForCheck?.deletedAt,
          remoteUpdatedAtSec: _extractUpdatedAtSec(doc),
        )) {
          _logger.debug(
            'Skipping blacklist ${doc.$id}: local is newer or equal '
            '(local=${existingForCheck?.lastModified}, remote=$lastModified)',
            tag: 'SYNC',
          );
          processed++;
          continue;
        }

        final companion = ShiftNotesCompanion(
          title: drift.Value(name),
          content: drift.Value(content),
          priority: const drift.Value('high'),
          shiftType: const drift.Value('all'),
          createdAt: drift.Value(createdAtEpoch),
          createdAtIso: drift.Value(createdAtIso),
          updatedAt: drift.Value(updatedAtEpoch),
          lastModified: drift.Value(lastModified),
          expiresAt: const drift.Value(null),
          isRead: const drift.Value(0),
          createdBy: const drift.Value('blacklist'),
          localUuid: drift.Value(localUuid),
          serverId: serverId != null
              ? drift.Value(serverId)
              : const drift.Value(null),
        );

        // upsert: البحث عن سجل موجود بنفس localUuid
        if (existingForCheck != null) {
          await (database.update(database.shiftNotes)
                ..where((t) => t.localUuid.equals(localUuid)))
              .write(companion);
        } else {
          await database.into(database.shiftNotes).insert(companion);
        }

        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync blacklist ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<bool> _processEmployeeEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      // ✅ حذف ناعم: نبحث عن الموظف محلياً (بما فيه المحذوف ناعماً)
      // إذا وُجد (deletedAt != null)، نُحدّث Appwrite بحقل deletedAt بدل الحذف الفعلي
      // هذا يمنع فقدان الموظف على الأجهزة الأخرى وحل FK بشكل صحيح
      final item = await _getEmployeeByLocalUuid(entry.localUuid);
      if (item != null && item.deletedAt != null) {
        // ✅ حذف ناعم — إرسال deletedAt إلى Appwrite
        final payload = outboxDao.adapters.employees.adapter.toJson(
          item,
          src: Source.appwrite,
        );
        try {
          await appwriteService.upsertEmployee(
            item.localUuid,
            _filterPayload('employees', _addIdempotencyKey(payload, entry)),
          );
        } catch (e) {
          if (e.toString().contains('attribute_not_found') ||
              e.toString().contains('Property not found') ||
              e.toString().contains('invalid_attribute') ||
              e.toString().contains('idempotencyKey') ||
              e.toString().contains('document_invalid_structure')) {
            _logger.warning(
              '⚠️ إعادة محاولة رفع الموظف بدون idempotencyKey: $e',
              tag: 'SYNC',
            );
            await appwriteService.upsertEmployee(
              item.localUuid,
              _filterPayload('employees', payload),
            );
          } else {
            rethrow;
          }
        }
        return true;
      }
      // الموظف غير موجود محلياً إطلاقاً — حذف فعلي من Appwrite
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
    try {
      await appwriteService.upsertEmployee(
        item.localUuid,
        _filterPayload('employees', _addIdempotencyKey(payload, entry)),
      );
    } catch (e) {
      if (e.toString().contains('attribute_not_found') ||
          e.toString().contains('Property not found') ||
          e.toString().contains('invalid_attribute') ||
          e.toString().contains('idempotencyKey') ||
          e.toString().contains('document_invalid_structure')) {
        _logger.warning(
          '⚠️ إعادة محاولة رفع الموظف بدون idempotencyKey: $e',
          tag: 'SYNC',
        );
        await appwriteService.upsertEmployee(
          item.localUuid,
          _filterPayload('employees', payload),
        );
      } else {
        rethrow;
      }
    }
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
      _filterPayload('booking_notes', _addIdempotencyKey(payload, entry)),
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
      _filterPayload('booking_nights', _addIdempotencyKey(payload, entry)),
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
    // ✅ إضافة employeeUuid لربط دورة الراتب بالموظف عبر الأجهزة
    final employee = await (database.select(database.employees)
          ..where((e) => e.id.equals(item.employeeId))
          ..limit(1))
        .getSingleOrNull();
    if (employee != null) {
      payload['employeeUuid'] = employee.localUuid;
      payload['employeeLocalUuid'] = employee.localUuid;
    }
    await appwriteService.upsertSalaryCycle(
      item.localUuid,
      _filterPayload('salary_cycles', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Future<SalaryCycle?> _getSalaryCycleByLocalUuid(String uuid) {
    return (database.select(database.salaryCycles)
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
      data: _filterPayload('booking_price_adjustments', _addIdempotencyKey(payload, entry)),
    );
    return true;
  }

  Future<BookingPriceAdjustment?> _getBookingPriceAdjustmentByLocalUuid(String uuid) {
    return (database.select(database.bookingPriceAdjustments)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  /// تحميل جميع البيانات من الخادم
  Future<void> pullAllRemoteData() async {
    _logger.info('Pulling all remote data...', tag: 'SYNC');
    await pullRemoteChanges();
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

  /// ✅ static getter لمعرف الجهاز — يُستخدم من DAOs و Repositories
  /// لتعيين deviceId عند إنشاء سجلات جديدة محلياً
  static String? _staticDeviceId;
  static String? get currentDeviceIdStatic => _staticDeviceId;

  /// تحديث الـ static deviceId — يُستدعى عند تسجيل الجهاز أو تهيئة المزامنة
  static void updateStaticDeviceId(String? id) {
    _staticDeviceId = id;
  }

  /// ✅ معرف الجهاز المحلي من SharedPreferences (fallback إذا لم يُسجَّل في Appwrite)
  Future<String?> _getLocalDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('appwrite_delta_device_id');
  }

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

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.shiftNotes)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

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

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.bookingNotes)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

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
    final deferred = <models.Document>[];

    // المرحلة الأولى: معالجة الليالي
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.bookingNights)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        await _adapterRegistry.nights.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        // ✅ تأجيل الليالي فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
        // bookingLocalId هو NOT NULL في booking_nights، لذا إذا فشل resolveBooking
        // سيحدث خطأ NOT NULL constraint بدلاً من FK constraint
        // لا نشمل 'constraint failed' عام لأنه يطابق UNIQUE أيضاً
        final errStr = e.toString();
        if (errStr.contains('FOREIGN KEY constraint failed') ||
            errStr.contains('NOT NULL constraint failed')) {
          _logger.debug(
            'Deferring booking night ${doc.$id}: FK/NOT NULL constraint (missing booking)',
            tag: 'SYNC',
          );
          deferred.add(doc);
        } else {
          _logger.warning(
            'Failed to sync booking night ${doc.$id}: $e',
            tag: 'SYNC',
          );
        }
      }
    }

    // المرحلة الثانية: إعادة محاولة الليالي المؤجلة
    if (deferred.isNotEmpty) {
      _logger.info(
        'Retrying ${deferred.length} deferred booking nights after all bookings synced',
        tag: 'SYNC',
      );

      for (final doc in deferred) {
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
            'Failed to sync deferred booking night ${doc.$id} after retry: $e',
            tag: 'SYNC',
          );
        }
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

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.cashTransactions)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

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
    final deferred = <Map<String, dynamic>>[];

    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.salaryCycles)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        // ✅ حل FK الموظف بثلاث مستويات: UUID → id → serverId
        final remoteEmployeeId =
            _asIntSafe(data, 'employeeId') ?? _asIntSafe(data, 'employee_id');
        final employeeUuid = (data['employeeUuid'] as String?) ??
            (data['employee_uuid'] as String?) ??
            (data['employeeLocalUuid'] as String?) ??
            (data['employee_local_uuid'] as String?);

        Employee? employee;

        // الطريقة 1: البحث بالـ UUID (الأكثر موثوقية عبر الأجهزة)
        if (employeeUuid != null && employeeUuid.isNotEmpty) {
          employee = await (database.select(database.employees)
                ..where((e) => e.localUuid.equals(employeeUuid))
                ..limit(1))
              .getSingleOrNull();
        }

        // الطريقة 2: البحث بالـ id البعيد كـ id محلي
        if (employee == null && remoteEmployeeId != null) {
          employee = await (database.select(database.employees)
                ..where((e) => e.id.equals(remoteEmployeeId))
                ..limit(1))
              .getSingleOrNull();
        }

        // الطريقة 3: البحث بالـ serverId (id الأصلي من جهاز المصدر)
        if (employee == null && remoteEmployeeId != null) {
          employee = await (database.select(database.employees)
                ..where((e) => e.serverId.equals(remoteEmployeeId))
                ..limit(1))
              .getSingleOrNull();
        }

        if (employee == null) {
          _logger.warning(
            '⏭️ تخطي salary_cycle ${doc.$id}: الموظف $remoteEmployeeId (uuid=$employeeUuid) غير موجود محلياً (سجل يتيم)',
            tag: 'SYNC',
          );
          continue;
        }

        // ✅ استبدال employeeId البعيد بالمعرف المحلي الصحيح
        data['employeeId'] = employee.id;

        await _adapterRegistry.salaryCycles.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } on SqliteException catch (e) {
        if (e.resultCode == 787) {
          final data = Map<String, dynamic>.from(doc.data);
          data['localUuid'] ??= doc.$id;
          deferred.add(data);
          _logger.warning(
            '⏳ تأجيل salary_cycle ${doc.$id}: FK constraint failed',
            tag: 'SYNC',
          );
        } else {
          _logger.warning(
            'Failed to sync salary cycle ${doc.$id}: $e',
            tag: 'SYNC',
          );
        }
      } catch (e) {
        _logger.warning(
          'Failed to sync salary cycle ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }

    // ✅ إعادة محاولة السجلات المؤجلة
    if (deferred.isNotEmpty) {
      _logger.info(
        '🔄 إعادة محاولة ${deferred.length} سجل salary_cycles مؤجل...',
        tag: 'SYNC',
      );
      for (final data in deferred) {
        try {
          await _adapterRegistry.salaryCycles.upsertFromJson(
            data,
            src: Source.appwrite,
          );
          processed++;
        } catch (e) {
          _logger.warning(
            '⏭️ فشل نهائي لـ salary_cycle (يتيم): $e',
            tag: 'SYNC',
          );
        }
      }
    }

    return processed;
  }

  Future<int> _syncSalaryPayments(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final deferred = <Map<String, dynamic>>[];

    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.salaryPayments)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        // ✅ إصلاح: ترك المحول يحل FK لدورة الراتب عبر UUID → localId → serverId
        // الفحص المسبق السابق كان يبحث فقط بـ c.id.equals(remoteCycleId) ويتخطى
        // السجلات الصالحة التي يمكن للمحول حلها عبر UUID أو serverId
        // المحول (SalaryPaymentsAdapter.resolveRefs) يعالج 3 مستويات من البحث
        // وإذا فشل يستخدم d.Value.absent() مما يسبب NOT NULL constraint
        // الذي يتم التقاطه في on SqliteException أدناه ويُؤجل السجل

        await _adapterRegistry.salaryPayments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } on SqliteException catch (e) {
        if (e.resultCode == 787) {
          final data = Map<String, dynamic>.from(doc.data);
          data['localUuid'] ??= doc.$id;
          deferred.add(data);
          _logger.warning(
            '⏳ تأجيل salary_payment ${doc.$id}: FK constraint failed',
            tag: 'SYNC',
          );
        } else {
          _logger.warning(
            'Failed to sync salary payment ${doc.$id}: $e',
            tag: 'SYNC',
          );
        }
      } catch (e) {
        _logger.warning(
          'Failed to sync salary payment ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }

    // ✅ إعادة محاولة السجلات المؤجلة
    if (deferred.isNotEmpty) {
      _logger.info(
        '🔄 إعادة محاولة ${deferred.length} سجل salary_payments مؤجل...',
        tag: 'SYNC',
      );
      for (final data in deferred) {
        try {
          await _adapterRegistry.salaryPayments.upsertFromJson(
            data,
            src: Source.appwrite,
          );
          processed++;
        } catch (e) {
          _logger.warning(
            '⏭️ فشل نهائي لـ salary_payment (يتيم): $e',
            tag: 'SYNC',
          );
        }
      }
    }

    return processed;
  }

  Future<int> _syncBookingPriceAdjustments(
    List<models.Document> documents,
  ) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final deferred = <models.Document>[];

    // المرحلة الأولى: معالجة تعديلات الأسعار
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;
        // إزالة id عند السحب من Appwrite لتجنب تعارض autoIncrement
        data.remove('id');

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.bookingPriceAdjustments)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        final result = await _adapterRegistry.bookingPriceAdjustments.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        
        // Refresh calculations for the affected booking
        if (result > 0) {
           final adj = await (database.select(database.bookingPriceAdjustments)
            ..where((t) => t.id.equals(result)))
            .getSingleOrNull();
           
           if (adj != null && adj.bookingLocalId != null) {
              await _bookingsRepository.derivedFields.refreshForBookingId(adj.bookingLocalId!);
           }
        }
        
        processed++;
      } catch (e) {
        // ✅ تأجيل تعديل السعر فقط إذا كان الخطأ FOREIGN KEY أو NOT NULL constraint
        // لا نشمل 'constraint failed' عام لأنه يطابق UNIQUE أيضاً
        final errStr = e.toString();
        if (errStr.contains('FOREIGN KEY constraint failed') ||
            errStr.contains('NOT NULL constraint failed')) {
          _logger.debug(
            'Deferring booking price adjustment ${doc.$id}: FK/NOT NULL constraint (missing booking)',
            tag: 'SYNC',
          );
          deferred.add(doc);
        } else {
          _logger.warning(
            'Failed to sync booking price adjustment ${doc.$id}: $e',
            tag: 'SYNC',
          );
        }
      }
    }

    // المرحلة الثانية: إعادة محاولة التعديلات المؤجلة
    if (deferred.isNotEmpty) {
      _logger.info(
        'Retrying ${deferred.length} deferred booking price adjustments after all bookings synced',
        tag: 'SYNC',
      );

      for (final doc in deferred) {
        try {
          final data = Map<String, dynamic>.from(doc.data);
          data['localUuid'] ??= doc.$id;
          data.remove('id');

          final result = await _adapterRegistry.bookingPriceAdjustments.upsertFromJson(
            data,
            src: Source.appwrite,
          );
          
          if (result > 0) {
            final adj = await (database.select(database.bookingPriceAdjustments)
              ..where((t) => t.id.equals(result)))
              .getSingleOrNull();
            
            if (adj != null && adj.bookingLocalId != null) {
              await _bookingsRepository.derivedFields.refreshForBookingId(adj.bookingLocalId!);
            }
          }
          
          processed++;
        } catch (e) {
          _logger.warning(
            'Failed to sync deferred booking price adjustment ${doc.$id} after retry: $e',
            tag: 'SYNC',
          );
        }
      }
    }

    return processed;
  }

  // ─── PriceAdjustments ──────────────────────────────────────────────────

  Future<int> _syncPriceAdjustments(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.priceAdjustments)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        await _adapterRegistry.priceAdjustments.upsertFromJson(
          data,
          src: Source.appwrite,
        );

        // ✅ إعادة حساب الحجوزات المتأثرة بعد سحب تغيير سعر الغرفة
        final targetType = data['targetType'] as String? ?? '';
        final targetUuid = data['targetUuid'] as String? ?? '';
        if (targetType == 'room' && targetUuid.isNotEmpty) {
          try {
            // تحديث سعر الغرفة المحلي
            final room = await (database.select(database.rooms)
                  ..where((r) => r.localUuid.equals(targetUuid))
                  ..limit(1))
                .getSingleOrNull();
            if (room != null) {
              final newValue = data['newValue'];
              if (newValue != null) {
                await (database.update(database.rooms)
                      ..where((r) => r.localUuid.equals(targetUuid)))
                    .write(RoomsCompanion(
                      price: drift.Value((newValue as num).toDouble()),
                      updatedAt: drift.Value(Time.nowEpoch()),
                      lastModified: drift.Value(Time.nowEpoch()),
                    ),);
              }
              // إعادة حساب الحجوزات النشطة للغرفة
              final activeBookings = await (database.select(database.bookings)
                    ..where((b) => b.roomNumber.equals(room.roomNumber))
                    ..where((b) => b.deletedAt.isNull())
                    ..where((b) => b.actualCheckout.isNull()))
                  .get();
              for (final booking in activeBookings) {
                await BookingDerivedFieldsService(database)
                    .refreshForBookingId(booking.id, forceRebuild: true);
              }
            }
          } catch (e) {
            _logger.warning(
              'فشل إعادة حساب الحجوزات بعد سحب price_adjustment $localUuid: $e',
              tag: 'SYNC',
            );
          }
        }

        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync price adjustment ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  // ─── AuditLogs ────────────────────────────────────────────────────────

  Future<int> _syncAuditLogs(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        // AuditLog لا يحتوي على lastModified — نستخدم timestamp للمقارنة
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.auditLogs)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.timestamp, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        await _adapterRegistry.auditLogs.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync audit log ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  // ─── PaymentVoids ─────────────────────────────────────────────────────

  /// رفع كل الإعدادات المحلية من SharedPreferences → Appwrite
  Future<bool> _pushAppSettingsToCloud() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // ⚠️ حقول app_settings الفعلية في Appwrite Cloud (25 حقل فقط — الحد الأقصى)
      // تم تدقيق كل حقل مقابل المخطط الفعلي في 2026-06-14
      // ❌ لا ترسل حقولاً غير موجودة — يسبب "Unknown attribute" خطأ 400
      final data = <String, dynamic>{
        'key': 'whatsapp_settings',
        'value': '',
        // ── فندق ──
        'hotel_name': prefs.getString('hotel_name') ?? 'فندق مارينا بلازا',
        'hotel_cutoff_hour': prefs.getInt('hotel_cutoff_hour') ?? 14,
        // ── مظهر ──
        'dark_mode': prefs.getBool('dark_mode') ?? false,
        // ── WhatsApp ──
        'wa_api_type': prefs.getString('wa_api_type') ?? 'greenapi',
        'wa_api_base_url': prefs.getString('wa_api_base_url') ?? '',
        'wa_api_instance_id': prefs.getString('wa_api_instance_id') ?? '',
        'wa_api_token': prefs.getString('wa_api_token') ?? '',
        'wa_custom_url_template': prefs.getString('wa_custom_url_template') ?? '',
        'wa_sendzen_api_key': prefs.getString('wa_sendzen_api_key') ?? '',
        'wa_sendzen_from_number': prefs.getString('wa_sendzen_from_number') ?? '',
        'wa_template': prefs.getString('whatsapp_template') ?? '',
        // ── Telegram ──
        'telegram_enabled': prefs.getBool('telegram_enabled') ?? false,
        'telegram_bot_token': prefs.getString('telegram_bot_token') ?? '',
        'telegram_chat_id': prefs.getString('telegram_chat_id') ?? '',
        'telegram_notifications_enabled': prefs.getBool('telegram_notifications_enabled') ?? false,
        'telegram_daily_report_enabled': prefs.getBool('telegram_daily_report_enabled') ?? false,
        'telegram_daily_report_time': prefs.getString('telegram_daily_report_time') ?? '',
        // ── Lark ──
        'lark_enabled': prefs.getBool('lark_enabled') ?? false,
        'lark_app_id': prefs.getString('lark_app_id') ?? '',
        'lark_app_secret': prefs.getString('lark_app_secret') ?? '',
        'lark_webhook_url': prefs.getString('lark_webhook_url') ?? '',
        'lark_daily_report_enabled': prefs.getBool('lark_daily_report_enabled') ?? false,
        'lark_daily_report_time': prefs.getString('lark_daily_report_time') ?? '08:00',
        'lark_daily_report_chat_id': prefs.getString('lark_daily_report_chat_id') ?? '',
        // ── مزامنة ──
        'appwrite_sync_interval': prefs.getInt('appwrite_sync_interval') ?? 15,
      };

      const docId = 'whatsapp_settings';
      const collectionId = 'app_settings';

      // محاولة تحديث، إذا لم يكن موجوداً ننشئه
      try {
        await appwriteService.updateDocument(
          collectionId: collectionId,
          documentId: docId,
          data: _filterPayload('app_settings', data),
        );
      } catch (_) {
        await appwriteService.createDocument(
          collectionId: collectionId,
          documentId: docId,
          data: _filterPayload('app_settings', data),
        );
      }

      return true;
    } catch (e) {
      _logger.warning('Failed to push app_settings: $e', tag: 'SYNC');
      return false;
    }
  }

  /// مزامنة إعدادات المراسلة (واتساب + تلجرام) من Appwrite → SharedPreferences
  Future<int> _syncAppSettings(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final prefs = await SharedPreferences.getInstance();

    for (final doc in documents) {
      try {
        final data = doc.data;

        // ── WhatsApp fields ──
        const waStringFields = {
          'wa_api_type': 'wa_api_type',
          'wa_api_base_url': 'wa_api_base_url',
          'wa_api_instance_id': 'wa_api_instance_id',
          'wa_api_token': 'wa_api_token',
          'wa_custom_url_template': 'wa_custom_url_template',
        };

        for (final entry in waStringFields.entries) {
          final value = data[entry.key];
          if (value != null && value.toString().isNotEmpty) {
            await prefs.setString(entry.value, value.toString());
          }
        }

        // wa_template → whatsapp_template (مفتاح مختلف في prefs)
        final template = data['wa_template'];
        if (template != null && template.toString().isNotEmpty) {
          await prefs.setString('whatsapp_template', template.toString());
        }

        // ── Telegram fields ──
        const tgStringFields = {
          'telegram_bot_token': 'telegram_bot_token',
          'telegram_chat_id': 'telegram_chat_id',
          'telegram_daily_report_time': 'telegram_daily_report_time',
        };

        for (final entry in tgStringFields.entries) {
          final value = data[entry.key];
          if (value != null && value.toString().isNotEmpty) {
            await prefs.setString(entry.value, value.toString());
          }
        }

        const tgBoolFields = {
          'telegram_enabled': 'telegram_enabled',
          'telegram_notifications_enabled': 'telegram_notifications_enabled',
          'telegram_daily_report_enabled': 'telegram_daily_report_enabled',
        };

        for (final entry in tgBoolFields.entries) {
          final value = data[entry.key];
          if (value != null) {
            await prefs.setBool(entry.value, value as bool);
          }
        }

        processed++;
        _logger.debug('AppSettings synced: ${doc.$id}', tag: 'SYNC');
      } catch (e) {
        _logger.warning(
          'Failed to sync app_settings ${doc.$id}: $e',
          tag: 'SYNC',
        );
      }
    }
    return processed;
  }

  Future<int> _syncPaymentVoids(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);
        data['localUuid'] ??= doc.$id;

        // ✅ تخطي التحديث إذا كانت البيانات البعيدة مطابقة للمحلية
        final localUuid = (data['localUuid'] as String?) ?? '';
        final existing = await (database.select(database.paymentVoids)
              ..where((t) => t.localUuid.equals(localUuid))
              ..limit(1))
            .getSingleOrNull();
        if (!_isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc))) {
          continue;
        }

        await _adapterRegistry.paymentVoids.upsertFromJson(
          data,
          src: Source.appwrite,
        );
        processed++;
      } catch (e) {
        _logger.warning(
          'Failed to sync payment void ${doc.$id}: $e',
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

  /// إجراء فحص شامل لسلامة البيانات بعد انتهاء المزامنة
  /// ✅ إصلاح: أصبح يُصلح السجلات اليتيمة تلقائياً بدلاً من مجرد التسجيل
  Future<void> _performPostSyncIntegrityCheck() async {
    try {
      // 1. فحص انتهاكات المفاتيح الأجنبية (Foreign Key Violations)
      final violations = await database.customSelect(
        'PRAGMA foreign_key_check',
        readsFrom: Set.unmodifiable({}),
      ).get();

      if (violations.isNotEmpty) {
        _logger.warning(
          '⚠️ تم اكتشاف ${violations.length} انتهاك للمفاتيح الأجنبية بعد المزامنة',
          tag: 'SYNC_INTEGRITY',
        );
        
        for (final row in violations) {
          final table = row.data['table']?.toString() ?? '';
          final rowId = row.data['rowid']?.toString() ?? '';
          final parent = row.data['parent']?.toString() ?? '';
          _logger.debug(
            'FK Violation: Table=$table, RowId=$rowId, Parent=$parent',
            tag: 'SYNC_INTEGRITY',
          );

          // ✅ إصلاح تلقائي: حذف السجلات اليتيمة (التي تشير لآباء غير موجودين)
          try {
            if (table == 'salary_withdrawals' || table == 'salary_cycles') {
              // حذف السجل الذي يشير لموظف غير موجود
              await database.customStatement(
                'DELETE FROM $table WHERE rowid = ?',
                [int.tryParse(rowId)],
              );
              _logger.info(
                '🧹 تم حذف سجل يتيم من $table (rowid=$rowId)',
                tag: 'SYNC_INTEGRITY',
              );
            } else if (table == 'salary_payments') {
              // حذف السجل الذي يشير لدورة راتب غير موجودة
              await database.customStatement(
                'DELETE FROM $table WHERE rowid = ?',
                [int.tryParse(rowId)],
              );
              _logger.info(
                '🧹 تم حذف سجل يتيم من $table (rowid=$rowId)',
                tag: 'SYNC_INTEGRITY',
              );
            } else if (table == 'payments' && parent == 'bookings') {
              // دفعة تشير لحجز غير موجود - إزالة FK فقط (لأن bookingLocalId nullable)
              await database.customStatement(
                'UPDATE payments SET booking_local_id = NULL, booking_uuid_cache = NULL WHERE rowid = ?',
                [int.tryParse(rowId)],
              );
              _logger.info(
                '🧹 تم إزالة ربط الدفعة اليتيمة بالحجز (rowid=$rowId)',
                tag: 'SYNC_INTEGRITY',
              );
            } else if (table == 'debts' && parent == 'bookings') {
              // دين يشير لحجز غير موجود - إزالة FK فقط (لأن bookingLocalId nullable)
              await database.customStatement(
                'UPDATE debts SET booking_local_id = NULL WHERE rowid = ?',
                [int.tryParse(rowId)],
              );
              _logger.info(
                '🧹 تم إزالة ربط الدين اليتيم بالحجز (rowid=$rowId)',
                tag: 'SYNC_INTEGRITY',
              );
            }
          } catch (fixError) {
            _logger.warning(
              '⚠️ فشل إصلاح سجل يتيم في $table: $fixError',
              tag: 'SYNC_INTEGRITY',
            );
          }
        }

        // تسجيل الأخطاء في Crashlytics للمراقبة
        await CrashlyticsService.instance.recordSyncError(
          operation: 'post_sync_integrity_check',
          error: 'Foreign key violations detected and auto-fixed: ${violations.length} rows',
          context: {'violations_count': violations.length.toString()},
        );

        // ✅ إصلاح تلقائي: حذف السجلات التي تشير إلى آباء غير موجودين
        // هذه سجلات أيتيمة نتجت عن حجوزات محذوفة على أجهزة أخرى
        // نستخدم soft delete (تعيين deletedAt) بدلاً من الحذف الفعلي
        try {
          for (final row in violations) {
            final table = row.data['table']?.toString();
            final rowId = row.data['rowid'];

            if (table == null || rowId == null) continue;

            _logger.info(
              '🔧 إصلاح تلقائي: حذف سجل يتيم من $table (rowId=$rowId)',
              tag: 'SYNC_INTEGRITY',
            );

            try {
              final nowEpoch = DateTime.now().millisecondsSinceEpoch ~/ 1000;
              if (table == 'payments') {
                await (database.update(database.payments)
                      ..where((t) => t.id.equals(rowId as int)))
                    .write(PaymentsCompanion(
                  deletedAt: drift.Value(nowEpoch),
                ));
              } else if (table == 'debts') {
                await (database.update(database.debts)
                      ..where((t) => t.id.equals(rowId as int)))
                    .write(DebtsCompanion(
                  deletedAt: drift.Value(nowEpoch),
                ));
              } else if (table == 'booking_nights') {
                await (database.update(database.bookingNights)
                      ..where((t) => t.id.equals(rowId as int)))
                    .write(BookingNightsCompanion(
                  deletedAt: drift.Value(nowEpoch),
                ));
              } else if (table == 'booking_price_adjustments') {
                await (database.update(database.bookingPriceAdjustments)
                      ..where((t) => t.id.equals(rowId as int)))
                    .write(BookingPriceAdjustmentsCompanion(
                  deletedAt: drift.Value(nowEpoch),
                ));
              }
            } catch (fixError) {
              _logger.warning(
                '⚠️ فشل إصلاح سجل يتيم في $table (rowId=$rowId): $fixError',
                tag: 'SYNC_INTEGRITY',
              );
            }
          }
        } catch (e) {
          _logger.warning('⚠️ فشل إصلاح انتهاكات FK: $e', tag: 'SYNC_INTEGRITY');
        }
      }

      // 2. التحقق من السجلات اليتيمة - باستخدام JOIN بدل الأعمدة غير الموجودة
      // ✅ إصلاح: استخدام LEFT JOIN للتحقق من وجود الحجز بدلاً من booking_uuid_cache
      // (booking_uuid_cache موجود فقط في جدول payments وليس في جدول debts)
      final orphanPayments = await database.customSelect('''
        SELECT COUNT(*) as count FROM payments p
        LEFT JOIN bookings b ON p.booking_local_id = b.id
        WHERE p.booking_local_id IS NOT NULL AND b.id IS NULL AND p.deleted_at IS NULL
      ''').getSingle();
      
      final orphanPayCount = orphanPayments.read<int>('count');
      if (orphanPayCount > 0) {
        _logger.warning(
          '⚠️ يوجد $orphanPayCount دفعة يتيمة (بدون ربط بحجز موجود)',
          tag: 'SYNC_INTEGRITY',
        );
      }

      // 3. التحقق من سحوبات الرواتب اليتيمة
      final orphanWithdrawals = await database.customSelect('''
        SELECT COUNT(*) as count FROM salary_withdrawals sw
        LEFT JOIN employees e ON sw.employee_id = e.id
        WHERE e.id IS NULL AND sw.deleted_at IS NULL
      ''').getSingle();

      final orphanWdCount = orphanWithdrawals.read<int>('count');
      if (orphanWdCount > 0) {
        _logger.warning(
          '⚠️ يوجد $orphanWdCount سحب راتب يتيم (بدون موظف موجود)',
          tag: 'SYNC_INTEGRITY',
        );
      }

      // 4. التحقق من دورات الرواتب اليتيمة
      final orphanCycles = await database.customSelect('''
        SELECT COUNT(*) as count FROM salary_cycles sc
        LEFT JOIN employees e ON sc.employee_id = e.id
        WHERE e.id IS NULL AND sc.deleted_at IS NULL
      ''').getSingle();

      final orphanCycleCount = orphanCycles.read<int>('count');
      if (orphanCycleCount > 0) {
        _logger.warning(
          '⚠️ يوجد $orphanCycleCount دورة راتب يتيمة (بدون موظف موجود)',
          tag: 'SYNC_INTEGRITY',
        );
      }

      _logger.info('✅ اكتمل فحص سلامة البيانات بعد المزامنة', tag: 'SYNC_INTEGRITY');
    } catch (e, st) {
      _logger.error(
        '❌ فشل إجراء فحص سلامة البيانات',
        error: e,
        stackTrace: st,
        tag: 'SYNC_INTEGRITY',
      );
    }
  }
}
