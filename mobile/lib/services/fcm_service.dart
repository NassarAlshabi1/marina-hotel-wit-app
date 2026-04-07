import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appwrite_sync_manager.dart';
import 'appwrite_service.dart';
import 'appwrite_config.dart';

/// خدمة Firebase Cloud Messaging
/// تُستخدم لإرسال إشعارات push بين الأجهزة عند حدوث تغييرات في Appwrite
class FcmService {
  static final FcmService _instance = FcmService._internal();
  factory FcmService() => _instance;
  FcmService._internal();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  String? _currentToken;
  bool _isInitialized = false;

  /// تهيئة FCM — تُستدعى من main.dart بعد تثبيت Appwrite
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // 1. إعداد Firebase (إذا لم يتم بعد)
      await Firebase.initializeApp();

      // 2. طلب إذن الإشعارات
      await _requestPermission();

      // 3. الحصول على التوكن
      _currentToken = await _getToken();
      if (_currentToken != null) {
        debugPrint('✅ FCM token obtained: ${_currentToken!.substring(0, 20)}...');

        // 4. حفظ التوكن في SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', _currentToken!);
      }

      // 5. الاستماع لتغيير التوكن
      _messaging.onTokenRefresh.listen((newToken) async {
        debugPrint('🔄 FCM token refreshed');
        _currentToken = newToken;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('fcm_token', newToken);

        // تحديث التوكن في Appwrite
        await _updateFcmTokenOnServer(newToken);
      });

      // 6. الاستماع للرسائل الواردة
      _setupMessageHandlers();

      // 7. تحديث التوكن على السيرفر عند فتح التطبيق
      if (_currentToken != null) {
        await _updateFcmTokenOnServer(_currentToken!);
      }

      _isInitialized = true;
      debugPrint('✅ FCM Service initialized');
    } catch (e) {
      debugPrint('⚠️ FCM initialization error: $e');
      // لا نمنع التطبيق من العمل إذا فشل FCM
    }
  }

  /// طلب إذن الإشعارات من المستخدم
  Future<void> _requestPermission() async {
    if (Platform.isIOS) {
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );
    } else if (Platform.isAndroid) {
      // Android 13+ يحتاج إذن صريح
      await _messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
    }

    final settings = await _messaging.getNotificationSettings();
    debugPrint('📱 FCM notification settings: ${settings.authorizationStatus}');
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
          vapidKey: null,
        );
      }
      return token;
    } catch (e) {
      debugPrint('⚠️ Failed to get FCM token: $e');
      return null;
    }
  }

  /// إعداد معالجات الرسائل الواردة
  void _setupMessageHandlers() {
    // --- رسالة في المقدمة (التطبيق مفتوح) ---
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 FCM: foreground message received');
      _handleIncomingMessage(message);
    });

    // --- المستخدم ضغط على الإشعار ---
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📩 FCM: notification tapped');
      _handleIncomingMessage(message);
    });

    // --- التطبيق فُتح من إشعار وهو كان مُغلق ---
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) {
        debugPrint('📩 FCM: opened from terminated state');
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
      debugPrint('📩 FCM: ignoring non-sync message ($source)');
      return;
    }

    // تجاهل الرسائل من نفس الجهاز
    final senderDeviceId = data['senderDeviceId'];
    if (senderDeviceId != null) {
      _getMyDeviceId().then((myId) {
        if (myId == senderDeviceId) {
          debugPrint('📩 FCM: ignoring message from same device');
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
    debugPrint('🔄 FCM: triggering pull from Appwrite...');

    // إشعار Realtime بانتظار تغييرات
    try {
      final realtime = _getRealtimeSync();
      realtime?.hasRemoteChanges.value = true;
      realtime?.pendingRemoteChangesCount.value++;
    } catch (_) {}

    // سحب التغييرات
    try {
      final syncManager = _getSyncManager();
      if (syncManager != null) {
        await syncManager.sync(push: false, pull: true);
        debugPrint('✅ FCM: pull completed');
      }
    } catch (e) {
      debugPrint('⚠️ FCM: pull error: $e');
    }
  }

  /// تحديث توكن FCM على سيرفر Appwrite
  Future<void> _updateFcmTokenOnServer(String token) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = prefs.getString('appwrite_device_id');
      if (deviceId == null || deviceId.isEmpty) return;

      await AppwriteService().updateDocument(
        collectionId: AppwriteConfig.devicesCollectionId,
        documentId: deviceId,
        data: {
          'fcmToken': token,
          'fcmTokenUpdatedAt': DateTime.now().millisecondsSinceEpoch ~/ 1000,
        },
      );
      debugPrint('✅ FCM token updated on server for device: $deviceId');
    } catch (e) {
      debugPrint('⚠️ Failed to update FCM token on server: $e');
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

  /// الحصول على التوكن الحالي
  String? get currentToken => _currentToken;

  /// هل تم التهيئة
  bool get isInitialized => _isInitialized;
}
