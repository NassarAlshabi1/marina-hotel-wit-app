import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'appwrite_messaging_service.dart';
import 'appwrite_sync_manager.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// خدمة Firebase Cloud Messaging
/// تُستخدم لإرسال إشعارات push بين الأجهزة عند حدوث تغييرات في Appwrite
class FcmService {
  factory FcmService() => _instance;
  FcmService._internal();
  static final FcmService _instance = FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  String? _currentToken;
  bool _isInitialized = false;
  StreamSubscription<String>? _tokenRefreshSubscription;
  StreamSubscription<RemoteMessage>? _onMessageSubscription;
  StreamSubscription<RemoteMessage>? _onMessageOpenedAppSubscription;

  static const AndroidNotificationChannel _syncChannel =
      AndroidNotificationChannel(
        'marina_sync_channel',
        'مزامنة فندق مارينا',
        description: 'إشعارات المزامنة والتحديثات',
        importance: Importance.high,
      );

  /// تهيئة FCM — تُستدعى من main.dart بعد تثبيت Appwrite
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    try {
      // 0. ✅ تهيئة الإشعارات المحلية لعرض notifications في foreground
      await _initLocalNotifications();

      // 1. Firebase تم تهيئته بالفعل في main.dart
      // لا حاجة لاستدعاء Firebase.initializeApp() هنا

      // 2. طلب إذن الإشعارات
      await _requestPermission();

      // 3. الحصول على التوكن
      _currentToken = await _getToken();
      if (_currentToken != null) {
        dlog(
          () => '✅ FCM token obtained: ${_currentToken!.substring(0, 20)}...',
        );

        // 4. حفظ التوكن في SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _currentToken!);

        // 4.b ✅ تسجيل الجهاز في Appwrite Messaging أيضاً (بالتوازي مع FCM التقليدي)
        // هذا يُتيح الاستفادة من مزايا Messaging API (Logs, Topics, UI)
        await _registerInAppwriteMessaging(_currentToken!);
      }

      // 5. الاستماع لتغيير التوكن — حفظ الاشتراك لإلغائه عند التنظيف
      _tokenRefreshSubscription = _messaging.onTokenRefresh.listen((
        newToken,
      ) async {
        dlog('🔄 FCM token refreshed');
        _currentToken = newToken;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', newToken);

        // تحديث التوكن في Appwrite عبر SyncManager (المُحقن)
        final syncManager = _getSyncManager();
        if (syncManager != null) {
          await syncManager.setFcmToken(newToken);
        }

        // ✅ تحديث التوكن في Appwrite Messaging أيضاً
        await _registerInAppwriteMessaging(newToken);
      });

      // 6. الاستماع للرسائل الواردة
      _setupMessageHandlers();

      // 7. ملاحظة: تحديث التوكن على السيرفر يتم عبر
      //    AppwriteSyncManager.setFcmToken() في _initializeFcm() في main.dart
      //    لتجنب تكرار الطلب

      _isInitialized = true;
      dlog('✅ FCM Service initialized');
    } catch (e) {
      dlog(() => '⚠️ FCM initialization error: $e');
      // لا نمنع التطبيق من العمل إذا فشل FCM
    }
  }

  /// طلب إذن الإشعارات من المستخدم
  Future<void> _requestPermission() async {
    if (Platform.isIOS) {
      await _messaging.requestPermission();
    } else if (Platform.isAndroid) {
      // Android 13+ يحتاج إذن صريح
      await _messaging.requestPermission();
    }

    final settings = await _messaging.getNotificationSettings();
    dlog(() => '📱 FCM notification settings: ${settings.authorizationStatus}');
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
        token = await _messaging.getToken();
      }
      return token;
    } catch (e) {
      dlog(() => '⚠️ Failed to get FCM token: $e');
      return null;
    }
  }

  /// إعداد معالجات الرسائل الواردة
  void _setupMessageHandlers() {
    // --- رسالة في المقدمة (التطبيق مفتوح) ---
    _onMessageSubscription = FirebaseMessaging.onMessage.listen((
      RemoteMessage message,
    ) {
      dlog('📩 FCM: foreground message received');
      // ✅ عرض إشعار محلي مرئي للمستخدم في foreground
      _showLocalNotification(message);
      _handleIncomingMessage(message);
    });

    // --- المستخدم ضغط على الإشعار ---
    _onMessageOpenedAppSubscription = FirebaseMessaging.onMessageOpenedApp
        .listen((RemoteMessage message) {
          dlog('📩 FCM: notification tapped');
          _handleIncomingMessage(message);
        });

    // --- التطبيق فُتح من إشعار وهو كان مُغلق ---
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        dlog('📩 FCM: opened from terminated state');
        _handleIncomingMessage(message);
      }
    });
  }

  /// ✅ تهيئة الإشعارات المحلية لعرض notifications في foreground
  Future<void> _initLocalNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(settings);

      // إنشاء قناة الإشعارات لأندرويد
      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_syncChannel);
      }
      dlog('✅ Local notifications initialized');
    } catch (e) {
      dlog(() => '⚠️ Local notifications init failed: $e');
    }
  }

  /// ✅ عرض إشعار محلي مرئي للمستخدم
  Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final title =
          (message.notification?.title ?? message.data['title'] ?? 'إشعار')
              as String;
      final body =
          (message.notification?.body ?? message.data['body'] ?? '') as String;

      const androidDetails = AndroidNotificationDetails(
        'marina_sync_channel',
        'مزامنة فندق مارينا',
        channelDescription: 'إشعارات المزامنة والتحديثات',
        importance: Importance.high,
        priority: Priority.high,
        icon: '@mipmap/ic_launcher',
      );
      const iosDetails = DarwinNotificationDetails();
      const details = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
        payload: jsonEncode(message.data),
      );
      dlog(() => '🔔 Local notification shown: $title');
    } catch (e) {
      dlog(() => '⚠️ Show local notification failed: $e');
    }
  }

  /// معالجة الرسالة الواردة — تشغيل sync
  void _handleIncomingMessage(RemoteMessage message) {
    final data = message.data;

    // التحقق أن الرسالة من نظامنا
    final source = data['type'] ?? data['source'];
    if (source != 'marina_sync') {
      dlog(() => '📩 FCM: ignoring non-sync message ($source)');
      return;
    }

    // تجاهل الرسائل من نفس الجهاز
    final senderDeviceId = data['senderDeviceId'];
    if (senderDeviceId != null) {
      _getMyDeviceId().then((myId) {
        if (myId == senderDeviceId) {
          dlog('📩 FCM: ignoring message from same device');
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
    dlog('🔄 FCM: triggering pull from Appwrite...');

    // إشعار Realtime بانتظار تغييرات
    try {
      final realtime = _getRealtimeSync();
      realtime?.hasRemoteChanges.value = true;
      realtime?.pendingRemoteChangesCount.value++;
    } catch (e, st) {
      AppLogger.warning(
        'فشل تشغيل المزامنة عبر FCM',
        tag: 'FCM',
        error: e,
        stackTrace: st,
      );
    }

    // سحب التغييرات
    try {
      final syncManager = _getSyncManager();
      if (syncManager != null) {
        await syncManager.sync(push: false);
        dlog('✅ FCM: pull completed');
      }
    } catch (e) {
      dlog(() => '⚠️ FCM: pull error: $e');
    }
  }

  /// الحصول على معرف الجهاز الحالي
  Future<String?> _getMyDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('appwrite_device_id') ??
        prefs.getString('appwrite_realtime_device_id');
  }

  /// الحصول على SyncManager (import دائري لذلك نستخدم getter خارجي)
  AppwriteSyncManager? _getSyncManager() {
    try {
      // يتم حقن الـ provider من main.dart عبر setInstance
      return _syncManagerInstance;
    } catch (_) {
      return null;
    }
  }

  /// الحصول على RealtimeSync
  dynamic _getRealtimeSync() {
    try {
      return _realtimeInstance;
    } catch (_) {
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

  /// ✅ تسجيل/تحديث جهاز في Appwrite Messaging (بالتوازي مع FCM التقليدي)
  ///
  /// هذه الدالة تُكمّل نظام FCM المباشر بتسجيل إضافي في Appwrite Messaging،
  /// مما يُتيح الاستفادة من:
  ///   - سجل تسليم كامل في Messaging → Messages
  ///   - واجهة UI لإدارة الإشعارات
  ///   - Topics للاشتراك في مجموعات محددة
  ///   - إرسال مركزي عبر Function بدون Firebase Admin SDK
  ///
  /// آمنة للفشل — إذا تعذّر التسجيل، يُكمل التطبيق بدون مشاكل (FCM التقليدي يعمل).
  Future<void> _registerInAppwriteMessaging(String fcmToken) async {
    try {
      final messagingService = AppwriteMessagingService();
      if (!messagingService.isInitialized) {
        await messagingService.initialize();
      }
      final targetId = await messagingService.registerDevice(
        fcmToken: fcmToken,
      );
      if (targetId != null) {
        dlog(() => '✅ Device also registered in Appwrite Messaging: $targetId');
        // اشترك في Topics الافتراضية
        await messagingService.subscribeToTopics(MessagingTopics.all);
      }
    } catch (e) {
      // آمن للفشل — نُسجّل تحذيراً فقط
      dlog(
        () => '⚠️ Appwrite Messaging registration failed (FCM still works): $e',
      );
    }
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
    dlog('🛑 FCM Service disposed');
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static Future<void> disposeInstance() async {
    _instance.dispose();
  }
}
