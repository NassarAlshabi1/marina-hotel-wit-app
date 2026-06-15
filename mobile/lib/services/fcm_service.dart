import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:marina_hotel_mobile/utils/prefs_cache.dart';

import '../utils/app_logger.dart';
import 'appwrite_sync_manager.dart';

/// خدمة Firebase Cloud Messaging
/// تُستخدم لإرسال إشعارات push بين الأجهزة عند حدوث تغييرات في Appwrite
class FcmService {
  factory FcmService() => _instance;
  FcmService._internal();
  static final FcmService _instance = FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _currentToken;
  bool _isInitialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription; // اشتراك تحديث التوكن — يجب إلغاؤه
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  /// تهيئة FCM — تُستدعى من main.dart بعد تثبيت Appwrite
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // 1. Firebase تم تهيئته بالفعل في main.dart
      // لا حاجة لاستدعاء Firebase.initializeApp() هنا

      // 2. طلب إذن الإشعارات
      await _requestPermission();

      // 3. الحصول على التوكن
      _currentToken = await _getToken();
      if (_currentToken != null) {
        AppLogger.info('✅ FCM token obtained: ${_currentToken!.substring(0, 20)}...', tag: 'APP');

        // 4. حفظ التوكن في SharedPreferences
        final prefs = getSharedPrefs();
        await prefs.setString('fcm_token', _currentToken!);
      }

      // 5. الاستماع لتغيير التوكن — حفظ الاشتراك لإلغائه عند التنظيف
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((newToken) async {
        AppLogger.info('🔄 FCM token refreshed', tag: 'APP');
        _currentToken = newToken;
        final prefs = getSharedPrefs();
        await prefs.setString('fcm_token', newToken);

        // تحديث التوكن في Appwrite عبر SyncManager (المُحقن)
        final syncManager = _getSyncManager();
        if (syncManager != null) {
          await syncManager.setFcmToken(newToken);
        }
      });

      // 6. الاستماع للرسائل الواردة
      _setupMessageHandlers();

      // 7. ملاحظة: تحديث التوكن على السيرفر يتم عبر
      //    AppwriteSyncManager.setFcmToken() في _initializeFcm() في main.dart
      //    لتجنب تكرار الطلب

      _isInitialized = true;
      AppLogger.info('✅ FCM Service initialized', tag: 'APP');
    } catch (e) {
      AppLogger.warning('⚠️ FCM initialization error: $e', tag: 'APP');
      // لا نمنع التطبيق من العمل إذا فشل FCM
    }
  }

  /// طلب إذن الإشعارات من المستخدم
  Future<void> _requestPermission() async {
    if (Platform.isIOS) {
      await _messaging.requestPermission(
        
      );
    } else if (Platform.isAndroid) {
      // Android 13+ يحتاج إذن صريح
      await _messaging.requestPermission(
        
      );
    }

    final settings = await _messaging.getNotificationSettings();
    AppLogger.info('📱 FCM notification settings: ${settings.authorizationStatus}', tag: 'APP');
  }

  /// الحصول على توكن FCM الحالي
  Future<String?> _getToken() async {
    try {
      // في Android، نستخدم استراتيجية التحميل المباشر لضمان صحة التوكن
      String? token;
      if (Platform.isIOS) {
        token = await _messaging.getToken();
      } else {
        // Android: استخدم APNs sandbox key للتطوير والتحميل المباشر للإنتاج
        token = await _messaging.getToken(
          
        );
      }
      return token;
    } catch (e) {
      AppLogger.warning('⚠️ Failed to get FCM token: $e', tag: 'APP');
      return null;
    }
  }

  /// إعداد معالجات الرسائل الواردة
  void _setupMessageHandlers() {
    // --- رسالة في المقدمة (التطبيق مفتوح) ---
    _onMessageSubscription = FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      AppLogger.info('📩 FCM: foreground message received', tag: 'APP');
      _handleIncomingMessage(message);
    });

    // --- المستخدم ضغط على الإشعار ---
    _onMessageOpenedAppSubscription = FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      AppLogger.info('📩 FCM: notification tapped', tag: 'APP');
      _handleIncomingMessage(message);
    });

    // --- التطبيق فُتح من إشعار وهو كان مُغلق ---
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        AppLogger.info('📩 FCM: opened from terminated state', tag: 'APP');
        _handleIncomingMessage(message);
      }
    });
  }

  /// معالجة الرسالة الواردة — تشغيل sync
  void _handleIncomingMessage(RemoteMessage message) {
    final data = message.data;

    // التحقق أن الرسالة من نظامنا
    final source = data['type'] ?? data['source'];
    if (source != 'marina_sync') {
      AppLogger.info('📩 FCM: ignoring non-sync message ($source)', tag: 'APP');
      return;
    }

    // تجاهل الرسائل من نفس الجهاز
    final senderDeviceId = data['senderDeviceId'];
    if (senderDeviceId != null) {
      _getMyDeviceId().then((myId) {
        if (myId == senderDeviceId) {
          AppLogger.info('📩 FCM: ignoring message from same device', tag: 'APP');
          return;
        }
        // تشغيل السحب من Appwrite
        _triggerPull();
      });
    } else {
      // لا يوجد معرف جهاز مرسل — نسحب على أي حال
      _triggerPull();
    }
  }

  /// تشغيل سحب التغييرات من Appwrite
  Future<void> _triggerPull() async {
    AppLogger.info('🔄 FCM: triggering pull from Appwrite...', tag: 'APP');

    // إشعار Realtime بانتظار تغييرات
    try {
      final realtime = _getRealtimeSync();
      realtime?.hasRemoteChanges.value = true;
      realtime?.pendingRemoteChangesCount.value++;
    } catch (e, st) {
      AppLogger.warning('فشل تشغيل المزامنة عبر FCM', tag: 'FCM', error: e, stackTrace: st);
    }

    // سحب التغييرات
    try {
      final syncManager = _getSyncManager();
      if (syncManager != null) {
        await syncManager.sync(push: false);
        AppLogger.info('✅ FCM: pull completed', tag: 'APP');
      }
    } catch (e) {
      AppLogger.warning('⚠️ FCM: pull error: $e', tag: 'APP');
    }
  }

  /// الحصول على معرف الجهاز الحالي
  Future<String?> _getMyDeviceId() async {
    final prefs = getSharedPrefs();
    return prefs.getString('appwrite_device_id') ??
        prefs.getString('appwrite_realtime_device_id');
  }

  /// الحصول على SyncManager (import دائري لذلك نستخدم getter خارجي)
  AppwriteSyncManager? _getSyncManager() {
    try {
      // يتم حقن الـ provider من main.dart عبر setInstance
      return _syncManagerInstance;
    } catch (e) { AppLogger.warning('⚠️ silent catch', tag: 'SYNC', error: e);
      return null;
    }
  }

  /// الحصول على RealtimeSync
  dynamic _getRealtimeSync() {
    try {
      return _realtimeInstance;
    } catch (e) { AppLogger.warning('⚠️ silent catch', tag: 'SYNC', error: e);
      return null;
    }
  }

  // --- حقن متأخر لتجنب import دائري ---
  static AppwriteSyncManager? _syncManagerInstance;
  static dynamic _realtimeInstance;

  /// حقن SyncManager (يُستدعى من main.dart بعد الإنشاء)
  static void injectDependencies({
    required AppwriteSyncManager syncManager,
    required dynamic realtimeSync,
  }) {
    _syncManagerInstance = syncManager;
    _realtimeInstance = realtimeSync;
  }

  /// الحصول على التوكن الحالي
  String? get currentToken => _currentToken;

  /// هل تم التهيئة
  bool get isInitialized => _isInitialized;

  /// تنظيف الموارد — إلغاء اشتراك تحديث التوكن
  void dispose() {
    _tokenRefreshSubscription?.cancel();
    _onMessageSubscription?.cancel();
    _onMessageOpenedAppSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _onMessageSubscription = null;
    _onMessageOpenedAppSubscription = null;
    _currentToken = null;
    _isInitialized = false;
    AppLogger.info('🛑 FCM Service disposed', tag: 'APP');
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static Future<void> disposeInstance() async {
    _instance.dispose();
  }
}
