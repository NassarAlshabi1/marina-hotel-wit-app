// ignore_for_file: unused_field, use_late_for_private_fields_and_variables, duplicate_ignore, avoid_redundant_argument_values, no_leading_underscores_for_local_identifiers, unused_local_variable, directives_ordering

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
import '../utils/secure_storage.dart';
import '../utils/status_utils.dart';
import '../utils/time.dart';
import 'adapters/adapter_registry.dart';
import 'adapters/id_resolver.dart';
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
import 'daos/ancestor_cache_dao.dart';
import 'daos/outbox_dao.dart';
import 'local_db.dart';
import 'repositories/bookings_repository.dart';
import 'repositories/rooms_repository.dart';
import 'salary_fix_helper.dart';
import 'secondary_appwrite_config.dart';
import 'sync_constants.dart';
import 'sync/payload_mapper.dart';
import 'sync_core/smart_conflict_resolver.dart';
import 'sync_core/sync_error_service.dart';
import 'sync_core/sync_metrics.dart';
import 'sync_core/sync_pull_service.dart';
import 'sync_enums.dart';
import 'sync_locks.dart';
import 'telegram/whatsapp_notification_service.dart';
import 'telegram/telegram_notification_service.dart';
import 'vector_clock_service.dart';

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

/// ✅ نتيجة فحص _isRemoteDataNewer (2026-06-28 P0-3)
/// قد تحتوي على بيانات مدمجة إذا تم حل التعارض المتزامن تلقائياً.
class _RemoteNewerResult {
  const _RemoteNewerResult({
    this.shouldApplyRemote = false,
    this.mergedData,
    this.pushedToRemote = false,
  });

  /// هل يجب تطبيق البيانات البعيدة؟
  final bool shouldApplyRemote;

  /// بيانات مدمجة (إذا تم حل التعارض عبر 3-way merge)
  /// إذا كانت غير null، يجب تطبيقها بدلاً من البيانات البعيدة
  final Map<String, dynamic>? mergedData;

  /// هل يجب رفع النتيجة المدمجة للسحابة؟
  final bool pushedToRemote;

  /// هل يوجد دمج تلقائي؟
  bool get hasMerge => mergedData != null;
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
    _ancestorCacheDao = AncestorCacheDao(database);
    _pullService = SyncPullService(
      appwriteService: appwriteService,
      database: database,
      outboxDao: outboxDao,
    );
  }
  static AppwriteSyncManager? _instance;

  /// الوصول المباشر للـ instance (يُستخدم من شاشات الإعدادات)
  static AppwriteSyncManager? get instance => _instance;

  /// إعادة تهيئة المزامنة بعد تغيير إعدادات Secondary
  Future<void> reinitializeAfterConfigChange() async {
    try {
      // إعادة تحميل الإعدادات
      await _loadSettings();
      // إعادة تهيئة Secondary Appwrite
      await SecondaryAppwriteConfig.ensureInitialized();
      _logger.info('🔄 Reinitialized after config change', tag: 'SYNC');
    } catch (e) {
      _logger.warning('Failed to reinitialize after config change: $e', tag: 'SYNC');
    }
  }

  final AppwriteService appwriteService;
  final AppDatabase database;
  final OutboxDao outboxDao;
  // ✅ P0-4 (2026-06-28): DAO لتخزين الـ ancestor المُشترك لحل التعارضات ثلاثي الأطراف
  late final AncestorCacheDao _ancestorCacheDao;
  late final BookingsRepository _bookingsRepository;
  late final RoomsRepository _roomsRepository;
  late final AdapterRegistry _adapterRegistry;

  final _logger = AppwriteLogger();
  final _errorHandler = AppwriteErrorHandler();
  final _err = SyncErrorService(tag: 'SYNC');
  SyncPullService? _pullService;

  /// PayloadMapper — تم استخراجه من دوال _xxxToRemote لهذا الصنف
  final PayloadMapper _payloadMapper = const PayloadMapper();

  Timer? _syncTimer;
  Timer? _debouncePushTimer;
  Timer? _failedRetryTimer;
  Timer? _cleanupTimer;
  Timer? _stuckRecoveryTimer;
  double _adaptiveBatchSize = 20;
  StreamSubscription<void>? _outboxSubscription;
  Duration _debounceWindow = SyncConstants.outboxDebounceWindow;
  SyncStatus _currentStatus = SyncStatus.idle;
  DateTime? _lastSyncTime;
  String? _currentDeviceId;
  String? _deviceLocalUuid;
  int? _deviceVersion;
  int? _deviceCreatedAtEpoch;
  String? _fcmToken; // توكن FCM للإشعارات بين الأجهزة

  // ✅ إصلاح جوهري: تتبّع أقصى زمن خادم ($updatedAt) في كل دورة سحب.
  // يُحدَّث في _extractUpdatedAtSec لكل مستند يُعالَج، ثم يُستخدم في
  // _updateLastPullTs بدل Time.nowEpoch() — لضمان أن المؤشر يعتمد
  // على سلطة الخادم لا وقت الجهاز الساحب (الذي قد يكون منحرفاً).
  // يُعاد ضبطه عند بداية كل دورة سحب.
  int? _maxUpdatedAtInPull;

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

      _deviceLocalUuid ??= 'marina_${finalDeviceModel.replaceAll(RegExp('[^a-zA-Z0-9_-]'), '_')}_${IdGen.shortId()}';
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
              'createdAtEpoch': _deviceCreatedAtEpoch ?? nowEpoch,
              'updatedAt': nowEpoch,
              'lastModified': nowEpoch,
              'lastModifiedEpoch': nowEpoch,
              'syncTimestamp': nowEpoch,
              'version': _deviceVersion,
              'origin': 'mobile',
              'sync_origin': 'mobile',
              'vectorClock': '{}',
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
          'createdAtEpoch': _deviceCreatedAtEpoch ?? nowEpoch,
          'updatedAt': nowEpoch,
          'lastModified': nowEpoch,
          'lastModifiedEpoch': nowEpoch,
          'syncTimestamp': nowEpoch,
          'version': _deviceVersion,
          'origin': 'mobile',
          'sync_origin': 'mobile',
          'vectorClock': '{}',
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
          final recovered = await outboxDao.cleanupStuckEntries(
            timeout: const Duration(seconds: 60),
          );
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

    // ✅ إصلاح جوهري: إعادة ضبط متتبّع أقصى $updatedAt في بداية دورة السحب.
    // سيُحدَّث في _extractUpdatedAtSec لكل مستند يُعالَج، ثم يُستخدم في
    // _updateLastPullTs بدل Time.nowEpoch().
    _maxUpdatedAtInPull = null;
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
      String effectiveDeviceId;
      if (_currentDeviceId != null) {
        effectiveDeviceId = _currentDeviceId!;
      } else {
        final localId = await _getLocalDeviceId();
        effectiveDeviceId = localId ?? 'unknown';
      }

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
        'startTime': syncLogCreatedEpoch,
        'status': SyncLogStatus.inProgress.value,
        'action': 'sync_start',
        'details': '{"recordsPushed":0,"recordsPulled":0,"conflicts":0}',
        'timestamp': syncLogCreatedEpoch,
        'timestampIso': startTime.toIso8601String(),
        'localUuid': syncLogLocalUuid,
        'createdAt': syncLogCreatedEpoch,
        'createdAtEpoch': syncLogCreatedEpoch,
        'updatedAt': syncLogCreatedEpoch,
        'lastModified': syncLogCreatedEpoch,
        'lastModifiedEpoch': syncLogCreatedEpoch,
        'syncTimestamp': syncLogCreatedEpoch,
        'version': syncLogVersion,
        'origin': 'mobile',
        'sync_origin': 'mobile',
        'vectorClock': '{}',
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
              // ✅ التوصية 5: لف _syncEmployees بطبقة إعادة محاولة لتحصين
              // أسبقية الموظفين قبل المصروفات (يقلّل خطر #4).
              final employeesSynced = await _syncEmployeesWithRetry(employees);
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

          // ✅ التوصية 3: إعادة ربط مؤجّلة لمصروفات الرواتب اليتيمة عبر
          // employeeUuid بعد اكتمال سحب الموظفين. يعالج مصروفات وصلت قبل
          // موظفيها في دورة سابقة (خطر #4).
          try {
            await _relinkOrphanSalaryExpenses();
          } catch (e, st) {
            _logger.warning(
              '⚠️ _relinkOrphanSalaryExpenses فشل بعد سحب الموظفين — '
              'سيُعاد المحاولة في الدورة التالية.',
              error: e,
              stackTrace: st,
              tag: 'SYNC_RELINK',
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
              // ✅ إصلاح جوهري: تحديث lastPullTs الخاص بـ booking_nights من
              // أقصى $updatedAt (سلطة الخادم) بدل Time.nowEpoch().
              // fallback إلى Time.nowEpoch() إذا لم تُعالَج مستندات.
              final nightsNewTs = _maxUpdatedAtInPull ?? Time.nowEpoch();
              await _updateBookingNightsPullTs(nightsNewTs);
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
            // ✅ إصلاح جوهري: اشتقاق المؤشر من أقصى $updatedAt (سلطة الخادم)
            // بدل Time.nowEpoch() (وقت الجهاز الساحب الذي قد يكون منحرفاً).
            // fallback إلى Time.nowEpoch() إذا لم يُعالَج أي مستند (دورة فارغة).
            final newPullTs = _maxUpdatedAtInPull ?? Time.nowEpoch();
            await _updateLastPullTs(newPullTs);
            if (_maxUpdatedAtInPull != null) {
              _logger.debug(
                '📍 مؤشر السحب الجديد مشتق من max(\$updatedAt) = $_maxUpdatedAtInPull '
                '(سلطة الخادم)',
                tag: 'SYNC',
              );
            }
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

          // ✅ إصلاح لمرة واحدة: استعادة روابط مصروفات الرواتب اليتيمة.
          // يعمل تلقائياً بعد اكتمال السحب الأول (عندما تكون الموظفون
          // والسحبيات متاحة محلياً). يستخدم SharedPreferences flag لضمان
          // عدم التكرار. غير محجوب — أخطاؤه لا توقف المزامنة.
          // راجع SalaryFixHelper للتفاصيل.
          try {
            final helper = SalaryFixHelper(database);
            await helper.runOnceAfterFirstPull();
          } catch (e, st) {
            _logger.warning(
              '⚠️ Salary fix helper failed — will retry on next sync.',
              error: e,
              stackTrace: st,
              tag: 'SALARY_FIX',
            );
          }
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
            'endTime': endEpoch,
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

      // ✅ إصلاح لمرة واحدة بعد اكتمال السحب: استعادة روابط مصروفات الرواتب
      // اليتيمة عبر salary_withdrawals. يعمل مرة واحدة فقط (SharedPreferences
      // flag) ويُنتظر حتى يكتمل سحب الموظفين. التحديثات تُضاف للـ outbox
      // وتُرفع تلقائياً في المزامنة التالية. راجع SalaryFixHelper.
      if (pull) {
        try {
          final helper = SalaryFixHelper(database);
          await helper.runOnceAfterFirstPull();
        } catch (e, st) {
          _logger.warning(
            '⚠️ SalaryFixHelper failed — will retry next sync.',
            error: e,
            stackTrace: st,
            tag: 'SYNC',
          );
          // لا نوقف المزامنة بسبب خطأ في الإصلاح.
        }
      }

      _logger.info(
        'Sync completed successfully (pushed: $recordsPushed, pulled: $recordsPulled)',
        tag: 'SYNC',
      );
    } catch (e, stackTrace) {
      errorMessage = e.toString();
      finalStatus = SyncStatus.failed;

      // ✅ جديد: تحديد ما إذا كان الفشل بسبب rate limit (429) — في هذه الحالة
      // لا نحاول كتابة سجل "sync_failed" على Appwrite لأن ذلك قد يُسبب 429
      // إضافي. نكتفي بالتسجيل المحلي.
      final isRateLimitFailure = e is AppwriteException &&
          (e.code == 429 ||
              (e.type ?? '').toLowerCase().contains('rate_limit') ||
              (e.message ?? '').toLowerCase().contains('rate_limit'));

      if (isRateLimitFailure) {
        _logger.warning(
          '🔌 Sync failed due to rate limit (429) — '
          'deferring sync log write. Will retry on next sync.',
          tag: 'SYNC',
        );
      } else if (hasSyncLog) {
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

      // ✅ جديد: تخطّي إشعارات Crashlytics/WhatsApp/Telegram لأخطاء 429
      // العابرة — هذه ليست أخطاءً حرجة تستدعي تنبيه الإدارة، بل ضغط مؤقت
      // على rate limit سيُحل تلقائياً عبر circuit breaker + backoff.
      if (!isRateLimitFailure) {
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
        // ✅ إضافة إشعار Telegram لخطأ المزامنة
        await TelegramNotificationService.instance.notifySyncError(
        operation: 'sync',
        error: errorMessage ?? e.toString(),
        recordsPushed: recordsPushed,
        recordsPulled: recordsPulled,
      );
      } // end if (!isRateLimitFailure)
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
  ///
  /// ✅ إصلاح جوهري: كما يُحدِّث `_maxUpdatedAtInPull` لتتبّع أقصى زمن خادم
  /// في كل دورة سحب — يُستخدم لاحقاً في `_updateLastPullTs` بدل `Time.nowEpoch()`.
  int? _extractUpdatedAtSec(models.Document doc) {
    try {
      final updatedAtStr = doc.$updatedAt;
      if (updatedAtStr.isEmpty) return null;
      final dt = DateTime.parse(updatedAtStr);
      final sec = (dt.millisecondsSinceEpoch / 1000).round();
      // ✅ تتبّع أقصى $updatedAt في هذه الدورة (سلطة الخادم للمؤشر).
      final current = _maxUpdatedAtInPull;
      if (current == null || sec > current) {
        _maxUpdatedAtInPull = sec;
      }
      return sec;
    } catch (_) {
      return null;
    }
  }

  /// ✅ إصلاح جذري (2026-06-27): دمج Vector Clock في حل التعارضات
  ///
  /// المنطق القديم كان يعتمد فقط على `lastModified` (LWW — Last Write Wins).
  /// هذا يُسبب مشكلة حرجة: إذا عدّل جهازان نفس السجل "بشكل متزامن"
  /// (concurrent)، فإن آخر من يصل يكتب فوق السابق دون أن يعرف أن هناك
  /// تعديلاً متزامناً — مما يُفقد البيانات.
  ///
  /// المنطق الجديد يستخدم Vector Clock كطبقة أولى لكشف العلاقة السببية
  /// (causal relationship) بين النسختين المحلية والبعيدة:
  ///
  /// 1. إذا كان البعيد يحدث قبل المحلي (happensBefore) → المحلي أحدث → تجاهل البعيد
  /// 2. إذا كان المحلي يحدث قبل البعيد → البعيد أحدث → طبّق البعيد
  /// 3. إذا كانا متساويين → لا حاجة للتحديث
  /// 4. إذا كانا متزامنين (concurrent) → ⚠️ تعارض حقيقي!
  ///    → نُسجّل التعارض في sync_conflicts
  ///    → نحاول الحل الذكي عبر SmartConflictResolver (3-way merge)
  ///    → إذا فشل الحل التلقائي، نطبّق LWW كحل احتياطي آمن
  ///
  /// Vector Clock يكتشف التعارضات المتزامنة حتى لو كانت ساعات الأجهزة
  /// متطابقة أو متزامنة، لأنه يعتمد على العلاقة السببية وليس الزمن الفيزيائي.
  ///
  /// ✅ إصلاح (2026-06-28 P0-3): تكامل SmartConflictResolver في فرع concurrent.
  /// النتيجة تحتوي على mergedData إذا تم الدمج التلقائي بنجاح.
  Future<_RemoteNewerResult> _isRemoteDataNewer(
    Map<String, dynamic> remoteData,
    int? localLastModified, {
    int? localDeletedAt,
    int? remoteUpdatedAtSec,
    String? localVectorClock,
    String? entityName,
    String? localUuid,
    Map<String, dynamic>? localData,
  }) async {
    // ✅ حماية الحذف المحلي (soft delete) — له أولوية أعلى
    if (localDeletedAt != null) {
      final remoteDeletedAt = _asIntNullable(remoteData['deletedAt']) ??
          _asIntNullable(remoteData['deleted_at']);
      if (remoteDeletedAt != null) {
        return const _RemoteNewerResult(shouldApplyRemote: true); // كلاهما محذوف
      }
      return const _RemoteNewerResult(shouldApplyRemote: false); // نحمي الحذف
    }

    if (localLastModified == null) {
      // ✅ إصلاح (2026-06-28): السجل غير موجود محلياً → يجب إضافته دائماً
      // حتى لو لم يكن لدى المستند البعيد lastModified ولا $updatedAt.
      // المنطق القديم كان يتجاوز السجل إذا لم يكن لديه timestamp → فقدان غرف.
      return const _RemoteNewerResult(shouldApplyRemote: true); // جديد
    }

    final remoteLastModified = _asIntNullable(remoteData['lastModified']) ??
        _asIntNullable(remoteData['last_modified']) ??
        _asIntNullable(remoteData['lastModifiedEpoch']);

    final effectiveRemoteTs = remoteLastModified ?? remoteUpdatedAtSec;

    if (effectiveRemoteTs == null) {
      // ✅ إصلاح (2026-06-28): السجل المحلي موجود لكن البعيد ليس لديه timestamp.
      // المنطق القديم كان يتجاوز التحديث (shouldApplyRemote: false) → الغرف لا تُحدّث.
      // الآن: نقارن بـ $updatedAt من Appwrite (متوفر دائماً).
      // إذا لم يتوفر أي timestamp، نُطبّق البيانات البعيدة كحل آمن
      // (السحابة هي مصدر الحقيقة عند عدم وجود معلومات كافية).
      _logger.debug(
        '_isRemoteDataNewer: no remote timestamp — applying remote data '
        'as safe default. localUuid=$localUuid',
        tag: 'SYNC',
      );
      return const _RemoteNewerResult(shouldApplyRemote: true);
    }

    // ════════════════════════════════════════════════════════════
    // ✅ فحص Vector Clock لكشف التعارضات المتزامنة (concurrent)
    // ════════════════════════════════════════════════════════════
    final remoteVcStr = (remoteData['vectorClock'] as String?) ??
        (remoteData['vector_clock'] as String?) ??
        '{}';

    // إذا كانت كلتا الساعتين فارغتين (جديد أو قديم بدون VC) → نستخدم LWW
    if ((localVectorClock == null || localVectorClock.isEmpty || localVectorClock == '{}') &&
        (remoteVcStr.isEmpty || remoteVcStr == '{}')) {
      // ✅ P0-2 fix: تطبيع وحدة الزمن قبل المقارنة
      // localLastModified بالثواني (Time.nowEpoch ~/ 1000)
      // effectiveRemoteTs قد يكون بالملّي ثانية (إذا جاء من حقل آخر)
      final normalizedRemoteTs = effectiveRemoteTs > 10000000000
          ? effectiveRemoteTs ~/ 1000
          : effectiveRemoteTs;
      final normalizedLocalTs = localLastModified > 10000000000
          ? localLastModified ~/ 1000
          : localLastModified;
      return _RemoteNewerResult(
        shouldApplyRemote: normalizedRemoteTs > normalizedLocalTs,
      );
    }

    // مقارنة Vector Clock
    final localVc = VectorClock.fromString(localVectorClock ?? '{}');
    final remoteVc = VectorClock.fromString(remoteVcStr);
    final comparison = VectorClockComparator.compare(localVc, remoteVc);

    switch (comparison) {
      case VectorClockComparison.equal:
        return const _RemoteNewerResult(shouldApplyRemote: false);

      case VectorClockComparison.remoteNewer:
        return const _RemoteNewerResult(shouldApplyRemote: true);

      case VectorClockComparison.localNewer:
        return const _RemoteNewerResult(shouldApplyRemote: false);

      case VectorClockComparison.concurrent:
        // ⚠️ تعارض متزامن! كلا الجهازين عدّلا نفس السجل بشكل مستقل.
        _logger.warning(
          '⚠️ CONCURRENT CONFLICT detected! '
          'entity=$entityName, uuid=$localUuid, '
          'localVc=$localVectorClock, remoteVc=$remoteVcStr, '
          'localLastModified=$localLastModified, remoteLastModified=$effectiveRemoteTs.',
          tag: 'CONFLICT',
        );

        // ✅ P0-3: محاولة الحل الذكي عبر SmartConflictResolver (3-way merge)
        if (entityName != null && localUuid != null && localData != null) {
          try {
            final ancestor = await _ancestorCacheDao.getAncestor(
              entityName,
              localUuid,
            );
            final resolution = SmartConflictResolver.resolve(
              entity: entityName,
              localData: localData,
              remoteData: remoteData,
              commonAncestor: ancestor,
            );

            if (resolution.strategy == ResolutionStrategy.fieldLevelMerge) {
              _logger.info(
                '✅ Concurrent conflict auto-resolved via 3-way merge: '
                'entity=$entityName, uuid=$localUuid, '
                'warnings=${resolution.warnings.length}',
                tag: 'CONFLICT',
              );
              // ✅ P0-2 إصلاح (2026-06-28): كتابة البيانات المدمجة في remoteData
              // في المكان (in-place) ليتم تطبيقها من المُتصل. المُتصل يستخدم نفس
              // كائن Map كـ `data` وبعد الـ check يمرره مباشرة إلى
              // adapter.upsertFromJson(data, ...). بتعديل remoteData مباشرة،
              // نضمن أن المُتصل يُطبق نتيجة الدمج بدلاً من البيانات البعيدة الخام.
              // ⚠️ آمن: remoteData هو نسخة محلية Map.from(doc.data) وليس كائن Appwrite الأصلي.
              remoteData.clear();
              remoteData.addAll(resolution.mergedData);
              // تخزين ancestor المدمج للمرات القادمة
              await _ancestorCacheDao.saveAncestor(
                entity: entityName,
                localUuid: localUuid,
                data: resolution.mergedData,
              );
              return _RemoteNewerResult(
                shouldApplyRemote: true,
                mergedData: resolution.mergedData,
                pushedToRemote: resolution.pushedToRemote,
              );
            }

          } catch (e) {
            _logger.warning(
              '⚠️ SmartConflictResolver failed, falling back to LWW: $e',
              tag: 'CONFLICT',
            );
          }
        }

        // تسجيل التعارض في sync_conflicts (LWW fallback)
        await _logConcurrentConflict(
          entity: entityName ?? 'unknown',
          uuid: localUuid ?? remoteData['localUuid']?.toString() ?? '',
          localVc: localVectorClock ?? '{}',
          remoteVc: remoteVcStr,
          localLastModified: localLastModified,
          remoteLastModified: effectiveRemoteTs,
          localData: localData,
          remoteData: remoteData,
        );
        // ✅ توحيد كسر التعادل: LWW + عند التساوي يفوز deviceId الأصغر معجمياً
        // نُقارن deviceId البعيد مع deviceId المحلي: إذا كان البعيد أصغر
        // معجمياً، يفوز البعيد (لتطبيق سلوك حتمي ومتناظر بين الأجهزة).
        final normalizedRemoteTs = effectiveRemoteTs > 10000000000
            ? effectiveRemoteTs ~/ 1000 : effectiveRemoteTs;
        final remoteDeviceId = (remoteData['deviceId'] as String?) ?? '';
        final localDeviceId = _currentDeviceId ?? '';
        final shouldApply = normalizedRemoteTs > localLastModified ||
            (normalizedRemoteTs == localLastModified &&
             remoteDeviceId.compareTo(localDeviceId) < 0);
        return _RemoteNewerResult(
          shouldApplyRemote: shouldApply,
        );
    }
  }

  /// تسجيل تعارض متزامن (concurrent conflict) في جدول sync_conflicts
  /// للمراجعة والتدقيق اللاحق.
  ///
  /// ✅ إصلاح (2026-06-28 P1-9): التسجيل الفعلي في جدول sync_conflicts
  /// بدلاً من developer.log فقط. نُنشئ سجل SyncLog أولاً (للحصول على logId)
  /// ثم نُدرج سجل SyncConflict مرتبط به.
  Future<void> _logConcurrentConflict({
    required String entity,
    required String uuid,
    required String localVc,
    required String remoteVc,
    required int localLastModified,
    required int remoteLastModified,
    Map<String, dynamic>? localData,
    Map<String, dynamic>? remoteData,
  }) async {
    try {
      final conflictData = {
        'entity': entity,
        'uuid': uuid,
        'type': 'concurrent',
        'localVectorClock': localVc,
        'remoteVectorClock': remoteVc,
        'localLastModified': localLastModified,
        'remoteLastModified': remoteLastModified,
        'resolution': 'LWW (remote=${remoteLastModified > localLastModified ? "wins" : "loses"})',
        'timestamp': DateTime.now().toIso8601String(),
      };
      // تسجيل في السجلات للتشخيص الفوري
      developer.log(
        '⚠️ Concurrent conflict logged: ${jsonEncode(conflictData)}',
        name: 'SYNC.CONFLICT',
      );
      _logger.warning(
        '⚠️ Concurrent conflict: entity=$entity, uuid=$uuid, '
        'localVc=$localVc, remoteVc=$remoteVc, '
        'localTs=$localLastModified, remoteTs=$remoteLastModified',
        tag: 'CONFLICT',
      );

      // ✅ التسجيل في جدول sync_conflicts للمراجعة اللاحقة
      // نُنشئ سجل SyncLog أولاً (FK مطلوب)، ثم سجل SyncConflict
      final createdAt = DateTime.now().toUtc().toIso8601String();
      final logId = await database.into(database.syncLog).insert(
            SyncLogCompanion.insert(
              syncId: 'conflict_${uuid}_${DateTime.now().millisecondsSinceEpoch}',
              direction: 'pull',
              deviceId: _currentDeviceId ?? 'unknown',
              metadata: jsonEncode(conflictData),
              operations: const drift.Value('[]'),
              checksumMatched: const drift.Value(0),
              createdAt: createdAt,
              completedAt: drift.Value(createdAt),
            ),
          );

      await database.into(database.syncConflicts).insert(
            SyncConflictsCompanion.insert(
              logId: logId,
              targetTable: entity,
              uuid: uuid,
              resolution: 'LWW (remote=${remoteLastModified > localLastModified ? "wins" : "loses"})',
              localPayload: jsonEncode(localData ?? conflictData),
              remotePayload: jsonEncode(remoteData ?? conflictData),
              createdAt: createdAt,
            ),
          );
    } catch (e) {
      // تجاهل أخطاء التسجيل — لا نريد أن نُعطل المزامنة بسببها
      developer.log('Failed to log concurrent conflict: $e',
          name: 'SYNC.CONFLICT');
    }
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

        if (!(await _isRemoteDataNewer(data, existingRoom?.lastModified, localDeletedAt: existingRoom?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existingRoom?.vectorClock, entityName: 'rooms', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existingBooking?.lastModified, localDeletedAt: existingBooking?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existingBooking?.vectorClock, entityName: 'bookings', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'employees', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'expenses', localUuid: localUuid)).shouldApplyRemote) {
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
        // ✅ إصلاح #2-B: تخزين $id الحقيقي كـ serverId عند السحب.
        // في الحالات النادرة التي يُنشأ فيها مستند على Appwrite بـ $id مختلف
        // عن localUuid (مثلاً من خدمة النسخ الاحتياطي الشامل التي تستخدم
        // ID.unique() عند غياب localUuid)، يضيع $id الحقيقي بعد السحب لأن
        // `??=` لا يتجاوز السمة الموجودة. حفظه كـ serverId يتيح للدفع اللاحق
        // مخاطبة المستند الصحيح. هذا إجراء وقائي — راجع payload_mapper.dart
        // الذي يرسل localUuid كسمة لكن يستخدم serverId للمعرّف الفعلي عند
        // توفره. (نفس نمط الموظفين في _syncEmployees.)
        data['serverId'] ??= _asIntSafe(data, 'id') ?? _asIntSafe(data, 'serverId');
        // ملاحظة: $id نصي (UUID)، لكن serverId في المخطط Int. لذا نُسجّله
        // فقط إذا كان رقمياً (نادر). للمعرّفات النصية، يبقى localUuid هو
        // المرجع. هذا لا يضر — الـ adapter يتعامل مع serverId الغائب.

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
            existingPayment.lastModified >= incomingLastModified) {
          _logger.debug(
          'Skipping payment ${doc.$id}: local is newer or equal '
          '(financial immutability, local=${existingPayment.lastModified} '
          '>= remote=$incomingLastModified)',
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
            existingDebt.lastModified >= incomingLastModified) {
          _logger.debug(
          'Skipping debt ${doc.$id}: local is newer or equal '
          '(financial immutability, local=${existingDebt.lastModified} '
          '>= remote=$incomingLastModified)',
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
    List<ConnectivityResult> connectivity = const <ConnectivityResult>[];
    try {
      connectivity = await Connectivity().checkConnectivity();
      if (connectivity.contains(ConnectivityResult.none)) {
        _logger.warning('⚠️ لا يوجد اتصال بالإنترنت - تم تأجيل الرفع', tag: 'SYNC');
        return 0;
      }
    } catch (_) {}

    // ✅ جديد: فحص circuit breaker قبل بدء الـ push. إذا كان مُفعّلاً بسبب
    // تكرار أخطاء 429، نُوقف push phase فوراً لتفادي إغراق الخادم بطلبات
    // إضافية. السجلات تبقى في outbox وتُعالج في المزامنة التالية.
    if (appwriteService.networkHelper.isCircuitBreakerActive) {
      final remaining =
          appwriteService.networkHelper.circuitBreakerRemaining;
      _logger.warning(
        '🔌 Circuit breaker مُفعّل — إيقاف push phase. '
        'المتبقي ${remaining?.inSeconds ?? 0}s',
        tag: 'SYNC',
      );
      return 0;
    }

    int totalProcessed = 0;
    int consecutiveFailures = 0;
    const int maxIterations = 500;
    int iterations = 0;
    final constrainedNetwork = _isConstrainedNetwork(connectivity);
    final minBatchSize = constrainedNetwork ? 5 : 10;
    final maxBatchSize = constrainedNetwork ? 25 : 100;
    final entryTimeout = Duration(seconds: constrainedNetwork ? 12 : 25);

    if (_adaptiveBatchSize > maxBatchSize) {
      _adaptiveBatchSize = maxBatchSize.toDouble();
    } else if (_adaptiveBatchSize < minBatchSize) {
      _adaptiveBatchSize = minBatchSize.toDouble();
    }

    while (true) {
      iterations++;
      if (iterations > maxIterations) {
        _logger.error('Max iterations exceeded in _pushAllEntities', tag: 'SYNC');
        break;
      }
      final batchSize = _adaptiveBatchSize.round();
      final entries = await outboxDao.takeBatch(batchSize, sources: const ['local']);
      if (entries.isEmpty) {
        break;
      }

      int processedInBatch = 0;
      bool abortPush = false; // ✅ يُضبط عند تفعّل circuit breaker أو 429
      for (final entry in entries) {
        // ✅ جديد: فحص circuit breaker داخل الحلقة — إذا تفعّل في منتصف الدفعة
        // (مثلاً بعد عدة 429 متتالية)، نُوقف المعالجة فوراً ونترك بقية السجلات
        // في outbox للمزامنة التالية.
        if (appwriteService.networkHelper.isCircuitBreakerActive) {
          final remaining =
              appwriteService.networkHelper.circuitBreakerRemaining;
          _logger.warning(
            '🔌 Circuit breaker مُفعّل أثناء معالجة الدفعة — إيقاف فوري. '
            'المتبقي ${remaining?.inSeconds ?? 0}s. '
            'تُترك بقية السجلات في outbox.',
            tag: 'SYNC',
          );
          abortPush = true;
          break;
        }
        try {
          final success = await _processOutboxEntry(entry)
              .timeout(entryTimeout);
          if (success) {
            // ✅ Dual-delivery: نضع علامة "مُسلّم للرئيسي" بدلاً من الحذف.
            // السجل يُحذف تلقائياً فقط إذا كان مُسلّماً للثانوي أيضاً.
            await outboxDao.markDeliveredToPrimary(entry.id);
            processedInBatch++;
          }
        } catch (e) {
          // ✅ جديد: إذا كان الخطأ 429 rate limit، لا نضع علامة error على
          // السجل (سيعاد إرساله في المزامنة التالية). فقط نُسجّل تحذيراً.
          final isRateLimit = e is AppwriteException &&
              (e.code == 429 ||
                  (e.type ?? '').toLowerCase().contains('rate_limit'));
          if (isRateLimit) {
            _logger.warning(
              '🔌 429 rate limit على السجل ${entry.id} — '
              'سيُعاد إرساله في المزامنة التالية',
              tag: 'SYNC',
            );
            // لا نضع setError — السجل يبقى eligible للإعادة
            abortPush = true;
            break; // اخرج من حلقة الدفعة لتقليل الضغط على الخادم
          }
          if (e is TimeoutException) {
            final message =
                'Timeout processing entry ${entry.id} after ${entryTimeout.inSeconds}s';
            _logger.warning('⏱️ $message', tag: 'SYNC');
            await outboxDao.setError(entry.id, message, entry.attempts + 1);
          } else {
            final message = 'Unexpected push error for entry ${entry.id}: $e';
            _logger.warning('⚠️ $message', tag: 'SYNC');
            await outboxDao.setError(entry.id, message, entry.attempts + 1);
          }
        }
      }

      // ✅ إذا تفعّل circuit breaker أو حدث 429، أوقف الـ push بالكامل —
      // لا نريد جلب دفعة جديدة و Hammering الخادم.
      if (abortPush) {
        _logger.warning(
          '⛔ إيقاف _pushAllEntities بسبب rate limit — '
          'السجلات المتبقية تُعالج في المزامنة التالية',
          tag: 'SYNC',
        );
        break;
      }

      // Adaptive batch size
      if (processedInBatch == entries.length) {
        _adaptiveBatchSize = (_adaptiveBatchSize * 1.3).clamp(
          minBatchSize,
          maxBatchSize,
        ).toDouble();
        consecutiveFailures = 0;
      } else {
        _adaptiveBatchSize = (_adaptiveBatchSize * 0.6).clamp(
          minBatchSize,
          maxBatchSize,
        ).toDouble();
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

  bool _isConstrainedNetwork(List<ConnectivityResult> connectivity) {
    if (connectivity.isEmpty) {
      return true;
    }
    if (connectivity.contains(ConnectivityResult.wifi) ||
        connectivity.contains(ConnectivityResult.ethernet)) {
      return false;
    }
    return true;
  }

  Future<bool> _processOutboxEntry(OutboxData entry) async {
    // ✅ إصلاح حرج (2026-06-28): زيادة Vector Clock قبل الرفع
    // بدون هذا، يبقى vectorClock دائماً '{}' على Appwrite Cloud
    // مما يُعطل كشف التعارضات المتزامنة تماماً (يصبح النظام LWW فقط).
    String? _oldVcStr;
    if (entry.op != 'delete' && _currentDeviceId != null && _currentDeviceId!.isNotEmpty) {
      _oldVcStr = await _readVectorClock(entry.entity, entry.localUuid);
      await _bumpVectorClockBeforePush(entry.entity, entry.localUuid, _currentDeviceId!);
    }

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
        case 'payment_voids':
          return await _processPaymentVoidEntry(entry);
        default:
          _logger.warning(
            'Unknown outbox entity: ${entry.entity}',
            tag: 'SYNC',
          );
          return false;
      }
    } catch (error, stackTrace) {
      // ✅ استعادة VC القديم إذا فشل الرفع
      if (_oldVcStr != null && entry.op != 'delete') {
        try {
          await _writeVectorClock(entry.entity, entry.localUuid, _oldVcStr);
        } catch (_) {
          // فشل استعادة VC ليس خطأ قاتلاً
        }
      }

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

  /// ✅ P0-5: القفل التفاؤلي (OCC) لكل الكيانات — واجهة مختصرة تستخدم
  /// اسم الكيان فقط وتحدد collectionId تلقائياً.
  /// يُرجع الحمولة النهائية (أصلية أو مدموجة).
  Future<Map<String, dynamic>> _occPushCheck({
    required String entity,
    required String documentId,
    required Map<String, dynamic> localPayload,
  }) async {
    final collectionId = _entityToCollectionId(entity);
    if (collectionId == null) return localPayload;
    return _occCheckAndMerge(
      collectionId: collectionId,
      documentId: documentId,
      localPayload: localPayload,
      entity: entity,
    );
  }

  /// تحويل اسم الكيان إلى معرف مجموعة Appwrite
  String? _entityToCollectionId(String entity) {
    final map = <String, String>{
      'rooms': AppwriteConfig.roomsCollectionId,
      'bookings': AppwriteConfig.bookingsCollectionId,
      'payments': AppwriteConfig.paymentsCollectionId,
      'expenses': AppwriteConfig.expensesCollectionId,
      'debts': AppwriteConfig.debtsCollectionId,
      'employees': AppwriteConfig.employeesCollectionId,
      'booking_notes': AppwriteConfig.bookingNotesCollectionId,
      'booking_nights': AppwriteConfig.bookingNightsCollectionId,
      'cash_transactions': AppwriteConfig.cashTransactionsCollectionId,
      'shift_notes': AppwriteConfig.shiftNotesCollectionId,
      'salary_cycles': AppwriteConfig.salaryCyclesCollectionId,
      'salary_payments': AppwriteConfig.salaryPaymentsCollectionId,
      'salary_withdrawals': AppwriteConfig.salaryWithdrawalsCollectionId,
      'guest_infos': AppwriteConfig.guestInfosCollectionId,
      'blacklist': AppwriteConfig.blacklistCollectionId,
      'booking_price_adjustments': AppwriteConfig.bookingPriceAdjustmentsCollectionId,
      'price_adjustments': AppwriteConfig.priceAdjustmentsCollectionId,
      'payment_voids': AppwriteConfig.paymentVoidsCollectionId,
      'salary_carry_over_logs': 'salary_carry_over_logs',
      'audit_logs': AppwriteConfig.auditLogsCollectionId,
    };
    return map[entity];
  }

  /// ✅ P0-5: القفل التفاؤلي (OCC) — فحص النسخة البعيدة قبل الدفع
  ///
  /// قبل كل عملية update، نقرأ المستند البعيد ونتحقق:
  /// 1. إذا لم يكن موجوداً → نتابع الدفع العادي (create)
  /// 2. إذا كان موجوداً بنفس النسخة → نتابع الدفع العادي (لا تعارض)
  /// 3. إذا كان موجوداً بنسخة أحدث → تعارض! نُشغّل SmartConflictResolver
  ///    ونُرجع البيانات المدموجة ليستخدمها المُتصل بدل الحمولة الأصلية
  ///
  /// [collectionId] — معرف مجموعة Appwrite
  /// [documentId] — localUuid للمستند
  /// [localPayload] — الحمولة المحلية المراد دفعها
  /// [entity] — اسم الكيان (للـ SmartConflictResolver)
  ///
  /// يُرجع: الحمولة النهائية للدفع (الأصلية أو المدموجة)
  Future<Map<String, dynamic>> _occCheckAndMerge({
    required String collectionId,
    required String documentId,
    required Map<String, dynamic> localPayload,
    required String entity,
  }) async {
    try {
      // 1) قراءة المستند البعيد
      // ✅ إصلاح #2-D: كتم 404 المتوقع. في فحص OCC، 404 يعني أن المستند
      // جديد (لم يُرفع بعد) — وهو سلوك متوقع تماماً وليس خطأ. قبل هذا
      // الإصلاح، كان 404 يُسجَّل كـ ERROR في getRow/withTimeout رغم أن
      // _occCheckAndMerge يلتقطه ويعالجه بشكل صحيح (يعيد localPayload
      // للمتابعة إلى create). كتم الخطأ هنا يُخفضه إلى debug.
      final remoteDoc = await appwriteService.getDocument(
        collectionId: collectionId,
        documentId: documentId,
        suppressErrorLog: true,
      );
      final remoteData = Map<String, dynamic>.from(remoteDoc.data);

      // 2) استخراج النسخ المحلية والبعيدة
      final localVersion = (localPayload['version'] as int?) ?? 0;
      final remoteVersion = (remoteData['version'] as int?) ?? 0;

      // 3) إذا النسخة البعيدة <= المحلية → لا تعارض
      if (remoteVersion <= localVersion) {
        return localPayload;
      }

      // 4) تعارض! النسخة البعيدة أحدث → نُشغّل SmartConflictResolver
      _logger.warning(
        '⚠️ OCC conflict detected: entity=$entity, uuid=$documentId, '
        'localVersion=$localVersion, remoteVersion=$remoteVersion → merging',
        tag: 'OCC',
      );

      // محاولة الحصول على ancestor من الـ cache
      Map<String, dynamic>? ancestor;
      try {
        ancestor = await _ancestorCacheDao.getAncestor(entity, documentId);
      } catch (_) {}

      // تشغيل SmartConflictResolver
      final resolution = SmartConflictResolver.resolve(
        entity: entity,
        localData: localPayload,
        remoteData: remoteData,
        commonAncestor: ancestor,
      );

      if (resolution.strategy == ResolutionStrategy.fieldLevelMerge) {
        _logger.info(
          '✅ OCC conflict resolved via 3-way merge: entity=$entity, uuid=$documentId',
          tag: 'OCC',
        );
        // حفظ ancestor المدمج للمرات القادمة
        try {
          await _ancestorCacheDao.saveAncestor(
            entity: entity,
            localUuid: documentId,
            data: resolution.mergedData,
          );
        } catch (_) {}
        return resolution.mergedData;
      }

      // إذا فشل الدمج، نستخدم LWW كـ fallback آمن
      _logger.warning(
        '⚠️ OCC merge failed, falling back to LWW: entity=$entity',
        tag: 'OCC',
      );
      return localPayload;
    } catch (e) {
      // إذا فشل قراءة المستند البعيد (404 أو شبكة)، نتابع الدفع العادي
      // 404 يعني أنه جديد → لا تعارض ممكن
      return localPayload;
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
    final occPayload = await _occPushCheck(
      entity: 'rooms',
      documentId: room.localUuid,
      localPayload: payload,
    );

    try {
      await appwriteService.upsertRoom(
        room.localUuid,
        _filterPayload('rooms', _addIdempotencyKey(occPayload, entry)),
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
          _filterPayload('rooms', occPayload), // بدون idempotencyKey
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

    // ✅ P0-5: OCC check — فحص النسخة البعيدة قبل الدفع
    final occPayload = await _occCheckAndMerge(
      collectionId: AppwriteConfig.bookingsCollectionId,
      documentId: booking.localUuid,
      localPayload: payload,
      entity: 'bookings',
    );

    // ✅ تسجيل تشخيصي: تسجيل الحقول الحرجة قبل الرفع
    _logger.info(
      '📤 Push booking ${booking.localUuid.substring(0, 8)}... '
      'status=${booking.status} '
      'actualCheckout=${booking.actualCheckout} '
      'calculatedNights=${booking.calculatedNights} '
      'lastModified=${booking.lastModified}'
      '${occPayload != payload ? " [OCC merged]" : ""}',
      tag: 'SYNC',
    );

    // ✅ إزالة idempotencyKey إذا لم يكن في مخطط Appwrite
    final cleanPayload = Map<String, dynamic>.from(occPayload);
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
          _filterPayload('bookings', occPayload), // بدون idempotencyKey
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
    // ✅ P0-5: OCC check — فحص النسخة البعيدة قبل الدفع
    final occPayload = await _occCheckAndMerge(
      collectionId: AppwriteConfig.expensesCollectionId,
      documentId: expense.localUuid,
      localPayload: payload,
      entity: 'expenses',
    );
    try {
      await appwriteService.upsertExpense(
        expense.localUuid,
        _filterPayload('expenses', _addIdempotencyKey(occPayload, entry)),
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
    // ✅ P0-5: OCC check — فحص النسخة البعيدة قبل الدفع
    final occPayload = await _occCheckAndMerge(
      collectionId: AppwriteConfig.paymentsCollectionId,
      documentId: payment.localUuid,
      localPayload: payload,
      entity: 'payments',
    );
    try {
      await appwriteService.upsertPayment(
        payment.localUuid,
        _filterPayload('payments', _addIdempotencyKey(occPayload, entry)),
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
    // ✅ P0-5: OCC check — فحص النسخة البعيدة قبل الدفع
    final occPayload = await _occCheckAndMerge(
      collectionId: AppwriteConfig.debtsCollectionId,
      documentId: debt.localUuid,
      localPayload: payload,
      entity: 'debts',
    );
    try {
      await appwriteService.upsertDebt(
        debt.localUuid,
        _filterPayload('debts', _addIdempotencyKey(occPayload, entry)),
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'guest_infos', localUuid: localUuid)).shouldApplyRemote) {
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
    final payload = _payloadMapper.guestInfoToRemote(info);
    final occPayload = await _occPushCheck(
      entity: 'guest_infos',
      documentId: info.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.guestInfosCollectionId,
      documentId: info.localUuid,
      data: _filterPayload('guest_infos', _addIdempotencyKey(occPayload, entry)),
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'salary_withdrawals', localUuid: localUuid)).shouldApplyRemote) {
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
        final empPayload = _payloadMapper.employeeToRemote(employee);
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
            // ✅ إصلاح P0 (2026-06-28): استخدام employee.id بدل hashCode
            // hashCode غير ثابت عبر العمليات — employee.id هو المعرف المحلي الصحيح
            serverId: drift.Value(employee.id),
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

    final payload = _payloadMapper.salaryWithdrawalToRemote(
      withdrawal,
      employeeUuid: employee.localUuid,
    );
    final occPayload = await _occPushCheck(
      entity: 'salary_withdrawals',
      documentId: withdrawal.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.salaryWithdrawalsCollectionId,
      documentId: withdrawal.localUuid,
      data: _filterPayload('salary_withdrawals', _addIdempotencyKey(occPayload, entry)),
    );
    return true;
  }

  Future<SalaryWithdrawal?> _getSalaryWithdrawalByLocalUuid(String localUuid) {
    return (database.select(
      database.salaryWithdrawals,
    )..where((t) => t.localUuid.equals(localUuid))).getSingleOrNull();
  }

  Map<String, dynamic> _roomToRemote(Room room) =>
      _payloadMapper.roomToRemote(room);

  Map<String, dynamic> _bookingToRemote(Booking booking) =>
      _payloadMapper.bookingToRemote(booking);

  Map<String, dynamic> _expenseToRemote(Expense expense) =>
      _payloadMapper.expenseToRemote(expense);

  Map<String, dynamic> _paymentToRemote(Payment payment) =>
      _payloadMapper.paymentToRemote(payment);

  Map<String, dynamic> _debtToRemote(Debt debt) =>
      _payloadMapper.debtToRemote(debt);

  /// هل نوع المصروف مرتبط بالرواتب
  static bool _isSalaryExpenseType(String type) =>
      PayloadMapper.isSalaryExpenseType(type);

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

  // ════════════════════════════════════════════════════════════════════
  // ✅ Vector Clock Bumping (2026-06-28) — يضمن أن VC يُرسل للـ Cloud
  // ════════════════════════════════════════════════════════════════════

  /// قراءة Vector Clock الحالي من قاعدة البيانات
  Future<String?> _readVectorClock(String entity, String localUuid) async {
    final tableName = _entityToTableName(entity);
    if (tableName == null) return null;
    try {
      final rows = await database.customSelect(
        'SELECT vector_clock AS vc FROM $tableName WHERE local_uuid = ? LIMIT 1',
        variables: [drift.Variable<String>(localUuid)],
      ).get();
      if (rows.isEmpty) return '{}';
      return (rows.first.data['vc'] as String?) ?? '{}';
    } catch (_) {
      return null;
    }
  }

  /// كتابة Vector Clock إلى قاعدة البيانات (للاستعادة بعد فشل الرفع)
  Future<void> _writeVectorClock(String entity, String localUuid, String vc) async {
    final tableName = _entityToTableName(entity);
    if (tableName == null) return;
    await database.customStatement(
      'UPDATE $tableName SET vector_clock = ? WHERE local_uuid = ?',
      [vc, localUuid],
    );
  }

  /// زيادة Vector Clock للجهاز الحالي قبل رفعه للسحابة
  Future<void> _bumpVectorClockBeforePush(String entity, String localUuid, String deviceId) async {
    final tableName = _entityToTableName(entity);
    if (tableName == null) return;

    try {
      final rows = await database.customSelect(
        'SELECT vector_clock AS vc FROM $tableName WHERE local_uuid = ? LIMIT 1',
        variables: [drift.Variable<String>(localUuid)],
      ).get();

      if (rows.isEmpty) return;

      final currentVcStr = (rows.first.data['vc'] as String?) ?? '{}';
      final vc = VectorClock.fromString(currentVcStr);
      vc.increment(deviceId);
      final newVcStr = vc.toString();

      await database.customStatement(
        'UPDATE $tableName SET vector_clock = ? WHERE local_uuid = ?',
        [newVcStr, localUuid],
      );

      _logger.debug(
        '⏫ VC bumped: entity=$entity, uuid=${localUuid.substring(0, 8)}..., '
        'old=$currentVcStr, new=$newVcStr',
        tag: 'VC',
      );
    } catch (e) {
      _logger.warning(
        '⚠️ فشل زيادة Vector Clock لـ $entity/$localUuid: $e — '
        'المتابعة بـ VC الحالي',
        tag: 'VC',
      );
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
  /// ✅ P1-3 fix: يُرجع عدد السجلات المدفوعة فعلياً بدل bool
  Future<int> pushLocalChanges() async {
    try {
      final result = await sync(pull: false);
      return result.recordsPushed;
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
      return 0;
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
        // ✅ P1-5 fix: تتبّع Collections الفاشلة لمنع تقديم مؤشّر السحب
        final failedCollections = <String>[];

        // ✅ إصلاح جوهري: إعادة ضبط متتبّع أقصى $updatedAt في بداية دورة السحب.
        // سيُحدَّث في _extractUpdatedAtSec لكل مستند يُعالَج، ثم يُستخدم في
        // _updateLastPullTs بدل Time.nowEpoch().
        _maxUpdatedAtInPull = null;

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
            // ✅ التوصية 5: تحصين أسبقية الموظفين عبر إعادة المحاولة.
            recordsPulled += await _syncEmployeesWithRetry(employees);
          } catch (e, st) {
            _logger.error('❌ فشل سحب employees (pullRemoteChanges)', error: e, stackTrace: st, tag: 'SYNC');
          }

          // ✅ التوصية 3: إعادة ربط مؤجّلة لمصروفات الرواتب اليتيمة بعد سحب
          // الموظفين (يعالج خطر #4 — مصروفات وصلت قبل موظفيها).
          try {
            await _relinkOrphanSalaryExpenses();
          } catch (e, st) {
            _logger.warning(
              '⚠️ _relinkOrphanSalaryExpenses فشل (pullRemoteChanges) — '
              'سيُعاد المحاولة في الدورة التالية.',
              error: e,
              stackTrace: st,
              tag: 'SYNC_RELINK',
            );
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
            // ✅ عند السحب الأولي (nightsPullTs == 0): تحديد 1000 سجل كحد أقصى
            // booking_nights قد يحوي عشرات الآلاف من السجلات (ليالية تاريخية)
            // مما يسبب بطء شديد في التثبيت الأول + استهلاك ذاكرة كبير.
            // السحب التزايدي اللاحق يجلب التغييرات الجديدة فقط.
            const int kInitialBookingNightsLimit = 1000;
            final bool isInitialPull = nightsPullTs == 0;
            if (isInitialPull) {
              _logger.info(
                '📥 السحب الأولي لـ booking_nights — تحديد $kInitialBookingNightsLimit سجل كحد أقصى',
                tag: 'SYNC',
              );
            }
            final bookingNights = await appwriteService.listBookingNights(
              queries: nightsDeltaQ,
              useCache: false,
              maxRecords: isInitialPull ? kInitialBookingNightsLimit : null,
            );
            _logger.info(
              '📊 تم جلب ${bookingNights.length} سجل booking_nights'
              '${isInitialPull ? " (حد أولي: $kInitialBookingNightsLimit)" : ""}',
              tag: 'SYNC',
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

          // ✅ P1-5 fix: تحديث lastPullTs فقط إذا نجحت كل الكولكشنات
          if (failedCollections.isEmpty) {
            // ✅ إصلاح جوهري: اشتقاق المؤشر من أقصى $updatedAt (سلطة الخادم)
            // بدل Time.nowEpoch() (وقت الجهاز الساحب الذي قد يكون منحرفاً).
            // fallback إلى Time.nowEpoch() إذا لم يُعالَج أي مستند (دورة فارغة).
            final newPullTs = _maxUpdatedAtInPull ?? Time.nowEpoch();
            await _updateLastPullTs(newPullTs);
            if (_maxUpdatedAtInPull != null) {
              _logger.debug(
                '📍 pullRemoteChanges: مؤشر السحب مشتق من max(\$updatedAt) = '
                '$_maxUpdatedAtInPull (سلطة الخادم)',
                tag: 'SYNC',
              );
            }
          } else {
            _logger.warning(
              '⚠️ P1-5: ${failedCollections.length} collections فشلت في pullRemoteChanges: '
              '${failedCollections.join(", ")} — لن يتم تحديث lastPullTs',
              tag: 'SYNC',
            );
          }
        });

        _lastSyncTime = DateTime.now();
        await _saveSettings();

        // ✅ إصلاح الحجوزات يتم فقط عبر Google Drive Backup — لا عبر Appwrite.
        // تمت إزالة _runPostPullAutoFix كلياً لأنه كان يستخدم RestoreFixService
        // الذي لا يجب أن يُستدعى من مسار Appwrite (حسب قرار المستخدم).

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
          final payload = _payloadMapper.bookingPriceAdjustmentToRemote(adj);
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
          final payload = _payloadMapper.guestInfoToRemote(info);
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
          final payload = _payloadMapper.salaryWithdrawalToRemote(withdrawal);
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
          final payload = _payloadMapper.salaryCarryOverLogToRemote(log);
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
      // ✅ إضافة إشعار Telegram لخطأ المزامنة
      await TelegramNotificationService.instance.notifySyncError(
        operation: 'bulk_push',
        error: e.toString(),
      );
      rethrow;
    }
  }

  Map<String, dynamic> _employeeToRemote(Employee employee) =>
      _payloadMapper.employeeToRemote(employee);

  Map<String, dynamic> _bookingNoteToRemote(BookingNote note) =>
      _payloadMapper.bookingNoteToRemote(note);

  Map<String, dynamic> _bookingNightToRemote(BookingNight night) =>
      _payloadMapper.bookingNightToRemote(night);

  Map<String, dynamic> _cashTransactionToRemote(CashTransaction transaction) =>
      _payloadMapper.cashTransactionToRemote(transaction);

  Map<String, dynamic> _salaryCycleToRemote(SalaryCycle cycle) =>
      _payloadMapper.salaryCycleToRemote(cycle);

  Map<String, dynamic> _salaryPaymentToRemote(SalaryPayment payment) =>
      _payloadMapper.salaryPaymentToRemote(payment);

  Map<String, dynamic> _shiftNoteToRemote(ShiftNote note) =>
      _payloadMapper.shiftNoteToRemote(note);

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
    final payload = _payloadMapper.salaryPaymentToRemote(item);
    final occPayload = await _occPushCheck(
      entity: 'salary_payments',
      documentId: item.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertSalaryPayment(
      item.localUuid,
      _filterPayload('salary_payments', _addIdempotencyKey(occPayload, entry)),
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

    final payload = _payloadMapper.cashTransactionToRemote(item);

    final occPayload = await _occPushCheck(
      entity: 'cash_transactions',
      documentId: item.localUuid,
      localPayload: payload,
    );

    await appwriteService.upsertCashTransaction(
      item.localUuid,
      _filterPayload('cash_transactions', _addIdempotencyKey(occPayload, entry)),
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

    final payload = _payloadMapper.shiftNoteToRemote(item);
    final occPayload = await _occPushCheck(
      entity: 'shift_notes',
      documentId: item.localUuid,
      localPayload: payload,
    );

    await appwriteService.upsertShiftNote(
      item.localUuid,
      _filterPayload('shift_notes', _addIdempotencyKey(occPayload, entry)),
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
    final payload = _payloadMapper.salaryCarryOverLogToRemote(log);
    final occPayload = await _occPushCheck(
      entity: 'salary_carry_over_logs',
      documentId: entry.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertDocument(
      collectionId: 'salary_carry_over_logs',
      documentId: entry.localUuid,
      data: _filterPayload('salary_carry_over_logs', _addIdempotencyKey(occPayload, entry)),
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
    final occPayload = await _occPushCheck(
      entity: 'blacklist',
      documentId: item.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertBlacklist(
      item.localUuid,
      _filterPayload('blacklist', _addIdempotencyKey(occPayload, entry)),
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
    final occPayload = await _occPushCheck(
      entity: 'price_adjustments',
      documentId: localRow.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.priceAdjustmentsCollectionId,
      documentId: localRow.localUuid,
      data: _filterPayload('price_adjustments', _addIdempotencyKey(occPayload, entry)),
    );
    return true;
  }

  Map<String, dynamic> _priceAdjustmentToRemote(PriceAdjustment row) =>
      _payloadMapper.priceAdjustmentToRemote(row);

  Map<String, dynamic> _blacklistToRemote(ShiftNote item) =>
      _payloadMapper.blacklistToRemote(item);

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
        if (!(await _isRemoteDataNewer(
          data,
          existingForCheck?.lastModified,
          localDeletedAt: existingForCheck?.deletedAt,
          remoteUpdatedAtSec: _extractUpdatedAtSec(doc),
          localVectorClock: existingForCheck?.vectorClock,
          entityName: 'blacklist',
          localUuid: localUuid,
        )).shouldApplyRemote) {
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

  /// ✅ معالجة سجل إلغاء دفع (PaymentVoid) من الـ outbox
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
    final voidRecord = await _getPaymentVoidByLocalUuid(entry.localUuid);
    if (voidRecord == null) {
      await _deleteSilently(
        () => appwriteService.deleteDocument(
          collectionId: AppwriteConfig.paymentVoidsCollectionId,
          documentId: entry.localUuid,
        ),
      );
      return true;
    }
    final payload = _payloadMapper.paymentVoidToRemote(voidRecord);
    final occPayload = await _occPushCheck(
      entity: 'payment_voids',
      documentId: voidRecord.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.paymentVoidsCollectionId,
      documentId: voidRecord.localUuid,
      data: _filterPayload(
        'payment_voids',
        _addIdempotencyKey(occPayload, entry),
      ),
    );
    return true;
  }

  Future<PaymentVoid?> _getPaymentVoidByLocalUuid(String uuid) {
    return (database.select(database.paymentVoids)
          ..where((t) => t.localUuid.equals(uuid))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<bool> _processEmployeeEntry(OutboxData entry) async {
    if (entry.op == 'delete') {
      // ✅ حذف ناعم: نبحث عن الموظف محلياً (بما فيه المحذوف ناعماً)
      // إذا وُجد (deletedAt != null)، نُحدّث Appwrite بحقل deletedAt بدل الحذف الفعلي
      // هذا يمنع فقدان الموظف على الأجهزة الأخرى وحل FK بشكل صحيح
      final item = await _getEmployeeByLocalUuid(entry.localUuid);
      if (item != null && item.deletedAt != null) {
        // ✅ حذف ناعم — إرسال deletedAt إلى Appwrite
        final payload = _payloadMapper.employeeToRemote(item);
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
    final payload = _payloadMapper.employeeToRemote(item);
    final occPayload = await _occPushCheck(
      entity: 'employees',
      documentId: item.localUuid,
      localPayload: payload,
    );
    try {
      await appwriteService.upsertEmployee(
        item.localUuid,
        _filterPayload('employees', _addIdempotencyKey(occPayload, entry)),
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
    final payload = _payloadMapper.bookingNoteToRemote(item);
    final occPayload = await _occPushCheck(
      entity: 'booking_notes',
      documentId: item.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertBookingNote(
      item.localUuid,
      _filterPayload('booking_notes', _addIdempotencyKey(occPayload, entry)),
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
    final payload = _payloadMapper.bookingNightToRemote(item);
    final occPayload = await _occPushCheck(
      entity: 'booking_nights',
      documentId: item.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertBookingNight(
      item.localUuid,
      _filterPayload('booking_nights', _addIdempotencyKey(occPayload, entry)),
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
    final payload = _payloadMapper.salaryCycleToRemote(item);
    final employee = await (database.select(database.employees)
          ..where((e) => e.id.equals(item.employeeId))
          ..limit(1))
        .getSingleOrNull();
    if (employee != null) {
      payload['employeeUuid'] = employee.localUuid;
      payload['employeeLocalUuid'] = employee.localUuid;
    }
    final occPayload = await _occPushCheck(
      entity: 'salary_cycles',
      documentId: item.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertSalaryCycle(
      item.localUuid,
      _filterPayload('salary_cycles', _addIdempotencyKey(occPayload, entry)),
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
    final payload = _payloadMapper.bookingPriceAdjustmentToRemote(item);
    final occPayload = await _occPushCheck(
      entity: 'booking_price_adjustments',
      documentId: item.localUuid,
      localPayload: payload,
    );
    await appwriteService.upsertDocument(
      collectionId: AppwriteConfig.bookingPriceAdjustmentsCollectionId,
      documentId: item.localUuid,
      data: _filterPayload('booking_price_adjustments', _addIdempotencyKey(occPayload, entry)),
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'shift_notes', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'booking_notes', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'booking_nights', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'cash_transactions', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'salary_cycles', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'salary_payments', localUuid: localUuid)).shouldApplyRemote) {
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'booking_price_adjustments', localUuid: localUuid)).shouldApplyRemote) {
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
    // ✅ P1-13 إصلاح: تم نقل إنشاء الخدمة خارج الحلقة
    final derivedFieldsService = BookingDerivedFieldsService(database);
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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'price_adjustments', localUuid: localUuid)).shouldApplyRemote) {
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
                await derivedFieldsService
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
        if (!(await _isRemoteDataNewer(data, existing?.timestamp, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: null, entityName: 'audit_logs', localUuid: localUuid)).shouldApplyRemote) {
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
  /// ✅ الخيار 2: مفاتيح app_settings النصّية (WhatsApp/Telegram) مُجمَّعة في
  /// `config_json` — الثابت المشترك معرّف في `AppwriteSyncUtils.appSettingsConfigKeys`
  /// (DRY: مصدر وحيد يستخدمه Primary و Secondary معاً).
  /// 🔒 لا يُضاف 'api_key' (ثغرة أمنية) ولا 'appwrite_log_level' (إعداد محلي).

  Future<bool> _pushAppSettingsToCloud() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await _getDeviceIdForPrefs();
      final encryptionKey = await SecureStorage.getEncryptionKey(null);
      final now = Time.nowEpoch();

      // ⚠️ حقول app_settings الفعلية في Appwrite Cloud (25 حقل فقط — الحد الأقصى)
      // تم تدقيق كل حقل مقابل المخطط الفعلي في 2026-06-14
      // ❌ لا ترسل حقولاً غير موجودة — يسبب "Unknown attribute" خطأ 400
      // ✅ P0-7 إصلاح: تشفير الحقول الحساسة قبل الإرسال للسحابة
      final data = <String, dynamic>{
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
        'wa_api_token': SecureStorage.encryptValue(prefs.getString('wa_api_token') ?? '', encryptionKey),
        'wa_custom_url_template': prefs.getString('wa_custom_url_template') ?? '',
        'wa_sendzen_api_key': prefs.getString('wa_sendzen_api_key') ?? '',
        'wa_sendzen_from_number': prefs.getString('wa_sendzen_from_number') ?? '',
        // ── Telegram ──
        'telegram_enabled': prefs.getBool('telegram_enabled') ?? false,
        'telegram_bot_token': SecureStorage.encryptValue(prefs.getString('telegram_bot_token') ?? '', encryptionKey),
        'telegram_chat_id': prefs.getString('telegram_chat_id') ?? '',
        'telegram_notifications_enabled': prefs.getBool('telegram_notifications_enabled') ?? false,
        'telegram_daily_report_enabled': prefs.getBool('telegram_daily_report_enabled') ?? false,
        'telegram_daily_report_time': prefs.getString('telegram_daily_report_time') ?? '',
        // ── مزامنة ──
        'appwrite_sync_interval': prefs.getInt('appwrite_sync_interval') ?? 15,
        // ✅ إصلاح (2026-07-04): الحقول المطلوبة إجبارياً في مخطط app_settings
        // على Appwrite Cloud. بدونها، createDocument يفشل بـ:
        //   document_invalid_structure: Missing required attribute "createdAt" (400)
        // والـ updateDocument يفشل بـ 404 (المستند لم يُنشأ بعد).
        // هذه الحقول الخمسة مطلوبة (required=true، default=None) حسب المخطط
        // الفعلي المُتحقَّق منه عبر GET /collections/app_settings/attributes.
        'createdAt': now,
        'updatedAt': now,
        'lastModified': now,
        'lastModifiedEpoch': now,
        'syncTimestamp': now,
      };

      // ✅ الخيار 2: تجميع مفاتيح WhatsApp/Telegram النصّية الحسّاسة في حقل
      // JSON واحد (config_json) بدل أعمدة منفصلة — لتفادي تجاوز حدّ حجم الصف
      // في Appwrite (app_settings كان يفشل بـ "Missing/Unknown attribute").
      // نُزيل المفاتيح الفردية من الحمولة ونضعها داخل config_json.
      final configMap = <String, dynamic>{};
      for (final k in AppwriteSyncUtils.appSettingsConfigKeys) {
        if (data.containsKey(k)) {
          configMap[k] = data.remove(k);
        }
      }
      data['config_json'] = jsonEncode(configMap);

      const docId = 'whatsapp_settings';
      const collectionId = 'app_settings';

      // ✅ إصلاح (PR #451 r3521832521): إزالة اقتطاع النصوص المشفّرة.
      //
      // كان الكود السابق يقتطع كل string إلى 28 حرفاً لتجنّب RangeError
      // من Appwrite. هذا يُفسد القيم المشفّرة (telegram_bot_token,
      // wa_api_token) — ciphertext لا يمكن فكّ تشفيره
      // بعد الاقتطاع، فتفقد الإعدادات قيمتها على الأجهزة الأخرى.
      //
      // السبب الجذري للمشكلة كان مختلفاً: مخطط app_settings الفعلي على
      // Appwrite Cloud uses generic key-value fields (settingKey,
      // settingValue, settingType, category, ...) وليس الحقول المُسماة
      // (telegram_bot_token, ...). لذا فالـ code يُرسل
      // حقولاً غير موجودة، وAppwrite يرفضها بـ "Unknown attribute".
      //
      // الحل الصحيح هو إعادة تصميم الـ push ليستخدم الـ schema الجديد
      // (settingKey/settingValue) أو إضافة الحقول المطلوبة على Appwrite
      // Cloud بحجم كافٍ (255+ حرفاً للقيم المشفّرة). حتى يحدث ذلك،
      // نُزيل الاقتطاع ونعتمد على الـ try-catch الموجود لاحقاً لإخفاق
      // صامت (app_settings غير حرجة — لا تمنع المزامنة).
      //
      // نُطبّق sanitizePayload فقط (يزيل الحقول غير المعروفة صامتاً).
      final filteredData = _filterPayload('app_settings', data);

      // محاولة تحديث، إذا لم يكن موجوداً ننشئه
      // ✅ إصلاح: كتم 404 المتوقع في updateDocument. المستند 'whatsapp_settings'
      // قد لا يكون موجوداً بعد (أول رفع) — 404 متوقع تماماً ويُلتقط في
      // catch لينتقل إلى createDocument. تسجيله كـ ERROR يُسبب ضجيجاً.
      try {
        await appwriteService.updateRow(
          collectionId: collectionId,
          documentId: docId,
          data: filteredData,
        );
      } catch (e) {
        // 404 متوقع للمستند الجديد — ننتقل إلى create.
        // أي خطأ آخر نُسجّله تحذيرًا (app_settings غير حرجة).
        if (e is AppwriteException &&
            (e.code == 404 ||
                (e.type ?? '').contains('document_not_found'))) {
          // متوقع — لا نسجّله.
        } else {
          _logger.warning(
            'app_settings update failed (non-critical): $e',
            tag: 'SYNC',
          );
        }
        try {
          await appwriteService.createRow(
            collectionId: collectionId,
            documentId: docId,
            data: filteredData,
          );
        } catch (e2) {
          // ✅ app_settings غير حرجة — لا تمنع المزامنة
          _logger.warning('app_settings push failed (non-critical): $e2', tag: 'SYNC');
        }
      }

      return true;
    } catch (e) {
      _logger.warning('Failed to push app_settings: $e', tag: 'SYNC');
      return false;
    }
  }

  Future<String> _getDeviceIdForPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('appwrite_delta_device_id') ?? 'default';
  }

  /// مزامنة إعدادات المراسلة (واتساب + تلجرام) من Appwrite → SharedPreferences
  Future<int> _syncAppSettings(List<models.Document> documents) async {
    if (documents.isEmpty) return 0;
    var processed = 0;
    final prefs = await SharedPreferences.getInstance();

    for (final doc in documents) {
      try {
        final data = Map<String, dynamic>.from(doc.data);

        // ✅ الخيار 2: فكّ config_json المُجمّع ودمج مفاتيحه في data قبل
        // منطق الحقول أدناه. config_json هو المصدر الجديد للحقيقة، لذا قيمه
        // تُسبق (overwrite) أي أعمدة قديمة منفصلة قد تكون موجودة في المستند.
        // التوافق الخلفي: إن لم يوجد config_json (مستند من عميل قديم)، يبقى
        // data بأعمدته الأصلية دون تعديل — لأن الـ if block لا يُنفَّذ.
        final rawConfig = data['config_json'];
        if (rawConfig is String && rawConfig.isNotEmpty) {
          try {
            final decoded = jsonDecode(rawConfig);
            if (decoded is Map) {
              decoded.forEach((k, v) {
                data[k.toString()] = v;
              });
            }
          } catch (e) {
            _logger.warning(
              'app_settings: تعذّر فكّ config_json: $e',
              tag: 'SYNC',
            );
          }
        }

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
        if (!(await _isRemoteDataNewer(data, existing?.lastModified, localDeletedAt: existing?.deletedAt, remoteUpdatedAtSec: _extractUpdatedAtSec(doc), localVectorClock: existing?.vectorClock, entityName: 'payment_voids', localUuid: localUuid)).shouldApplyRemote) {
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

        // ✅ إصلاح: إعادة ربط المدفوعات اليتيمة بـ bookingUuidCache
        await _relinkOrphanedPayments();
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

  /// ✅ إعادة ربط المدفوعات اليتيمة بحجوزاتها عبر bookingUuidCache.
  ///
  /// المشكلة: عند المزامنة، قد تصل المدفوعات قبل الحجوزات (أو الحجز
  /// مخزّن بصيغة UUID مختلفة — بالشرطات vs بدون). النتيجة: الدفعة
  /// تُخزّن بـ bookingLocalId=null أو خاطئ → تصبح يتيمة.
  ///
  /// الحل: بعد انتهاء المزامنة، نبحث عن المدفوعات التي لها
  /// bookingUuidCache لكن bookingLocalId غير مربوط بحجز موجود،
  /// ونُعيد ربطها عبر IdResolver (الذي يجرّب كلا صيغتي UUID).
  Future<void> _relinkOrphanedPayments() async {
    try {
      // ابحث عن المدفوعات التي لها bookingUuidCache لكن bookingLocalId
      // غير مربوط (NULL أو يشير لحجز غير موجود)
      // ✅ إصلاح SQL: استخدم علامات اقتباس مفردة '' للـ string literal الفارغ
      // بدل "" — علامات الاقتباس المزدوجة في SQLite تُفسَّر كمعرّف عمود وليس
      // كسلسلة نصية، فتُنتج "no such column". (نفس إصلاح _relinkOrphanSalaryExpenses.)
      final orphans = await database.customSelect(
        'SELECT p.id, p.booking_uuid_cache, p.booking_local_id '
        'FROM payments p '
        'LEFT JOIN bookings b ON p.booking_local_id = b.id '
        'WHERE p.booking_uuid_cache IS NOT NULL '
        "AND p.booking_uuid_cache != '' "
        'AND p.deleted_at IS NULL '
        'AND (p.booking_local_id IS NULL OR b.id IS NULL)',
        readsFrom: {database.payments, database.bookings},
      ).get();

      if (orphans.isEmpty) {
        return;
      }

      _logger.info(
        '🔗 إعادة ربط ${orphans.length} دفعة يتيمة عبر bookingUuidCache',
        tag: 'SYNC_RELINK',
      );

      final resolver = IdResolver(database);
      int relinked = 0;

      for (final row in orphans) {
        final paymentId = row.read<int>('id');
        final bookingUuid = row.read<String>('booking_uuid_cache');

        // استخدم IdResolver لـ resolveBooking (يجرّب كلا صيغتي UUID)
        final resolvedBookingId = await resolver.resolveBooking(
          uuid: bookingUuid,
        );

        if (resolvedBookingId != null) {
          // ✅ وجدنا الحجز — أعد الربط
          await (database.update(database.payments)
                ..where((t) => t.id.equals(paymentId)))
              .write(PaymentsCompanion(
            bookingLocalId: drift.Value(resolvedBookingId),
          ));
          relinked++;
          _logger.debug(
            '  ✅ Payment #$paymentId → booking #$resolvedBookingId '
            '(uuid: ${bookingUuid.substring(0, 8)}...)',
            tag: 'SYNC_RELINK',
          );
        } else {
          _logger.warning(
            '  ❌ Payment #$paymentId: could not resolve booking '
            'uuid: $bookingUuid',
            tag: 'SYNC_RELINK',
          );
        }
      }

      if (relinked > 0) {
        _logger.info(
          '✅ تم إعادة ربط $relinked/$orphans.length دفعة يتيمة',
          tag: 'SYNC_RELINK',
        );

        // أعد حساب الحجوزات المتأثرة
        final relinkedBookingIds = <int>{};
        for (final row in orphans) {
          final paymentId = row.read<int>('id');
          final updated = await (database.select(database.payments)
                ..where((t) => t.id.equals(paymentId)))
              .getSingleOrNull();
          if (updated?.bookingLocalId != null) {
            relinkedBookingIds.add(updated!.bookingLocalId!);
          }
        }
        for (final bookingId in relinkedBookingIds) {
          try {
            await _bookingsRepository.derivedFields
                .refreshForBookingId(bookingId);
          } catch (e) {
            debugPrint('⚠️ refreshForBookingId($bookingId) failed: $e');
          }
        }
      }
    } catch (e, st) {
      _logger.error(
        '❌ فشل إعادة ربط المدفوعات اليتيمة',
        error: e,
        stackTrace: st,
        tag: 'SYNC_RELINK',
      );
    }
  }

  /// ✅ التوصية 3: إعادة ربط مؤجّلة لمصروفات الرواتب اليتيمة عبر employeeUuid.
  ///
  /// المشكلة (خطر #4): قد يصل مصروف راتب من Appwrite/Drive قبل وصول سجل
  /// الموظف (مثلاً فشل سحب الموظفين في دورة ما ونجح سحب المصروفات). مع
  /// التوصية 2 (قصر fallback relatedId على المصدر المحلي)، يبقى المصروف
  /// غير مربوط (relatedId = null) رغم وجود employeeUuid صالح.
  ///
  /// الحل: بعد انتهاء المزامنة (وبعد `_syncEmployees` تحديدًا)، نبحث عن
  /// مصروفات الرواتب ذات employeeUuid غير فارغ و relatedId فارغ، ونُعيد
  /// ربطها بالموظف المحلي المطابق للـ UUID. تغيير additive بحت (استعلام +
  /// تحديث) — لا يكسر المزامنة ولا يفقد بيانات.
  ///
  /// يُستدعى من تدفق المزامنة (push و pull) بعد اكتمال `_syncEmployees`.
  Future<int> _relinkOrphanSalaryExpenses() async {
    var relinked = 0;
    try {
      // ابحث عن مصروفات الرواتب اليتيمة: employeeUuid موجود، relatedId فارغ.
      // نُجري فحص نوع الراتب في Dart عبر PayloadMapper.isSalaryExpenseType
      // لأن الكلمات المفتاحية عربية ومتعددة (رواتب / سحب راتب / خصم راتب…)
      // ولا تُترجم بسهولة إلى LIKE في SQL.
      // ✅ إصلاح SQL: استخدم علامات اقتباس مفردة '' للـ string literal الفارغ
      // بدل "" — علامات الاقتباس المزدوجة في SQLite تُفسَّر كمعرّف عمود وليس
      // كسلسلة نصية، فتُنتج "no such column". (تلميح رسالة الخطأ كان صريحًا.)
      final candidates = await database.customSelect(
        'SELECT id, employee_uuid, expense_type FROM expenses '
        'WHERE employee_uuid IS NOT NULL '
        "AND employee_uuid != '' "
        'AND related_id IS NULL '
        'AND deleted_at IS NULL',
        readsFrom: {database.expenses},
      ).get();

      // فلترة لأنواع الرواتب فقط (توحيد المنطق مع بقية النظام).
      final orphans = candidates
          .where((row) => PayloadMapper.isSalaryExpenseType(
                row.read<String>('expense_type'),
              ))
          .toList();

      if (orphans.isEmpty) {
        return 0;
      }

      _logger.info(
        '🔗 إعادة ربط ${orphans.length} مصروف راتب يتيم عبر employeeUuid',
        tag: 'SYNC_RELINK',
      );

      for (final row in orphans) {
        final expenseId = row.read<int>('id');
        final employeeUuid = row.read<String>('employee_uuid');

        // حل الموظف عبر localUuid (نفس آلية expenses_adapter).
        final employee = await (database.select(database.employees)
              ..where((e) => e.localUuid.equals(employeeUuid))
              ..limit(1))
            .getSingleOrNull();

        if (employee != null) {
          // ✅ وجدنا الموظف — أعد الربط.
          await (database.update(database.expenses)
                ..where((t) => t.id.equals(expenseId)))
              .write(ExpensesCompanion(
            relatedId: drift.Value(employee.id),
          ));
          relinked++;
          _logger.debug(
            '  ✅ Expense #$expenseId → employee #${employee.id} '
            '(uuid: ${employeeUuid.substring(0, employeeUuid.length.clamp(0, 8))}...)',
            tag: 'SYNC_RELINK',
          );
        } else {
          // الموظف لم يصل بعد — نترك المصروف غير مربوط بانتظار دورة لاحقة.
          _logger.warning(
            '  ⏳ Expense #$expenseId: employee not yet synced for '
            'uuid: $employeeUuid — will retry next cycle.',
            tag: 'SYNC_RELINK',
          );
        }
      }

      if (relinked > 0) {
        _logger.info(
          '✅ تم إعادة ربط $relinked/${orphans.length} مصروف راتب يتيم',
          tag: 'SYNC_RELINK',
        );
      }
    } catch (e, st) {
      _logger.error(
        '❌ فشل إعادة ربط مصروفات الرواتب اليتيمة',
        error: e,
        stackTrace: st,
        tag: 'SYNC_RELINK',
      );
    }
    return relinked;
  }

  /// ✅ التوصية 5: تحصين أسبقية مزامنة الموظفين قبل المصروفات.
  ///
  /// يلف `_syncEmployees` بطبقة إعادة محاولة بسيطة. إذا فشل سحب/معالجة
  /// الموظفين في دورة ما، يُعاد المحاولة حتى `maxRetries` مرات قبل
  /// المتابعة إلى `_syncExpenses`. هذا يقلّل السيناريو الوحيد المتبقي
  /// لخطر #4 (وصول مصروفات الرواتب قبل موظفيها).
  ///
  /// ملاحظة: الترتيب نفسه مطبَّق بالفعل (`_syncEmployees` قبل `_syncExpenses`
  /// في الدفع والسحب) — هذه الطبقة تضيف فقط "تحصينًا" عبر إعادة المحاولة
  /// دون تغيير الترتيب.
  Future<int> _syncEmployeesWithRetry(
    List<models.Document> documents, {
    int maxRetries = 2,
  }) async {
    if (documents.isEmpty) return 0;
    var attempts = 0;
    int? lastCount;
    Object? lastError;
    while (attempts <= maxRetries) {
      try {
        lastCount = await _syncEmployees(documents);
        if (attempts > 0) {
          _logger.info(
            '✅ _syncEmployees نجح بعد $attempts إعادة محاولة '
            '($lastCount موظف)',
            tag: 'SYNC',
          );
        }
        return lastCount;
      } catch (e, st) {
        lastError = e;
        attempts++;
        if (attempts <= maxRetries) {
          _logger.warning(
            '⚠️ _syncEmployees فشل (محاولة $attempts/$maxRetries) — '
            'إعادة المحاولة: $e',
            tag: 'SYNC',
            error: e,
            stackTrace: st,
          );
          // فترة انتظار قصيرة متصاعدة قبل إعادة المحاولة.
          await Future<void>.delayed(
            Duration(milliseconds: 300 * attempts),
          );
        }
      }
    }
    _logger.error(
      '❌ _syncEmployees فشل بعد $maxRetries إعادة محاولة — '
      'المتابعة إلى المصروفات قد تترك بعض مصروفات الرواتب غير مربوطة مؤقتًا. '
      'آخر خطأ: $lastError',
      tag: 'SYNC',
    );
    // لا نُعيد رمي الاستثناء للحفاظ على متانة المزامنة (نفس فلسفة الـ catch
    // الموجودة في تدفقات السحب/الدفع). يُعالَج لاحقًا عبر _relinkOrphanSalaryExpenses.
    return lastCount ?? 0;
  }
}
