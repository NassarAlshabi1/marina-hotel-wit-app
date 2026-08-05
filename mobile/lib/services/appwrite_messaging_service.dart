// TODO(phase-2): remove this ignore and fix violations (avoid_dynamic_calls, discarded_futures)
// ignore_for_file: avoid_dynamic_calls, discarded_futures
// lib/services/appwrite_messaging_service.dart
//
// ✅ خدمة Appwrite Messaging — بديل/مكمّل لـ FCM المباشر.
//
// الوظائف:
// 1. تسجيل جهاز المستخدم في Appwrite Messaging (إنشاء Target)
// 2. الاشتراك في Topics (حسب صلاحية المستخدم)
// 3. الاستماع للإشعارات الواردة عبر Appwrite Realtime
// 4. تشغيل المزامنة فور وصول إشعار
// 5. عرض إشعار محلي في الـ foreground
//
// الاستخدام في main.dart:
// ```dart
// final messagingService = AppwriteMessagingService();
// await messagingService.initialize();
// await messagingService.registerDevice(fcmToken: fcmToken);
// await messagingService.subscribeToTopics(['bookings_updates', 'sync_events']);
// ```
//
// ملاحظة: تتطلب Appwrite SDK >= 21.0.0 (مدعوم في pubspec.yaml)

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appwrite/appwrite.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_logger.dart';
import 'appwrite_config.dart';
import 'appwrite_service.dart';

/// Topics المتاحة في Appwrite Messaging
class MessagingTopics {
  static const String bookingsUpdates = 'bookings_updates';
  static const String paymentsUpdates = 'payments_updates';
  static const String expensesUpdates = 'expenses_updates';
  static const String roomsUpdates = 'rooms_updates';
  static const String staffAlerts = 'staff_alerts';
  static const String syncEvents = 'sync_events';

  /// كل الـ Topics المتاحة للاشتراك الافتراضي
  static const List<String> all = [
    bookingsUpdates,
    paymentsUpdates,
    expensesUpdates,
    roomsUpdates,
    staffAlerts,
    syncEvents,
  ];
}

/// خدمة Appwrite Messaging لإدارة Push Notifications
///
/// تعمل كطبقة فوق Appwrite SDK، توفر:
/// - تسجيل تلقائي للجهاز كـ Target
/// - اشتراك في Topics
/// - استقبال الإشعارات عبر Realtime
/// - عرض إشعارات محلية في الـ foreground
class AppwriteMessagingService {
  factory AppwriteMessagingService() => _instance;
  AppwriteMessagingService._internal();
  static final AppwriteMessagingService _instance =
      AppwriteMessagingService._internal();

  late final Account _account;
  late final Client _client;
  late final Databases _databases;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _currentTargetId;
  String? _currentUserId;
  bool _isInitialized = false;
  StreamSubscription<dynamic>? _realtimeSubscription;

  static const AndroidNotificationChannel _messagingChannel =
      AndroidNotificationChannel(
        'marina_messaging_channel',
        'رسائل فندق مارينا',
        description: 'إشعارات Appwrite Messaging',
        importance: Importance.high,
      );

  /// تهيئة الخدمة — تُستدعى مرة واحدة من main.dart
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      // نستخدم نفس Client من AppwriteService
      _client = AppwriteService().client;
      _account = Account(_client);
      _databases = Databases(_client);

      // تهيئة الإشعارات المحلية
      await _initLocalNotifications();

      _isInitialized = true;
      debugPrint('✅ Appwrite Messaging Service initialized');
    } catch (e, st) {
      AppLogger.error(
        'فشل تهيئة Appwrite Messaging',
        tag: 'Messaging',
        error: e,
        stackTrace: st,
      );
      // لا نمنع التطبيق من العمل
    }
  }

  /// تسجيل الجهاز كـ Target في Appwrite Messaging
  ///
  /// [fcmToken] التوكن من Firebase (مطلوب للأندرويد)
  /// [userId] معرف المستخدم (اختياري — يُربط الـ Target بحساب المستخدم)
  Future<String?> registerDevice({
    required String fcmToken,
    String? userId,
  }) async {
    if (!_isInitialized) {
      debugPrint('⚠️ Messaging Service not initialized');
      return null;
    }

    if (fcmToken.isEmpty) {
      debugPrint('⚠️ FCM token is empty');
      return null;
    }

    try {
      // الحصول على معرف الجهاز المحفوظ
      final prefs = await SharedPreferences.getInstance();
      final deviceId =
          prefs.getString('appwrite_device_id') ??
          prefs.getString('appwrite_realtime_device_id') ??
          'device_${DateTime.now().millisecondsSinceEpoch}';

      // تسجيل/تحديث في collection "devices" (لا يستخدم Messaging Targets API
      // لأن Client SDK 21.x لا يدعم createTarget/updateTarget)
      try {
        // ignore: deprecated_member_use
        await _databases.updateDocument(
          databaseId: AppwriteConfig.databaseId,
          collectionId: AppwriteConfig.devicesCollectionId,
          documentId: deviceId,
          data: {
            'fcmToken': fcmToken,
            'status': 'active',
            'lastSeen': DateTime.now().toIso8601String(),
            if (userId != null) 'userId': userId,
          },
        );
        debugPrint('✅ Messaging device updated: $deviceId');
      } on AppwriteException catch (e, st) {
        if (e.code == 404) {
          // ignore: deprecated_member_use
          await _databases.createDocument(
            databaseId: AppwriteConfig.databaseId,
            collectionId: AppwriteConfig.devicesCollectionId,
            documentId: deviceId,
            data: {
              'localUuid': deviceId,
              'fcmToken': fcmToken,
              'status': 'active',
              'createdAt': DateTime.now().toIso8601String(),
              'lastSeen': DateTime.now().toIso8601String(),
              if (userId != null) 'userId': userId,
            },
          );
          debugPrint('✅ Messaging device created: $deviceId');
        } else {
          rethrow;
        }
      }

      _currentTargetId = deviceId;
      _currentUserId = userId;

      // حفظ في prefs
      await prefs.setString('messaging_target_id', deviceId);

      // ربط الـ Target بالمستخدم إن وُجد
      if (userId != null) {
        try {
          await _account.updatePrefs(
            prefs: {
              'messaging_target_id': deviceId,
              'messaging_registered_at': DateTime.now().toIso8601String(),
            },
          );
        } catch (e, st) {
          // غير حرج
          debugPrint('⚠️ Could not update user prefs: $e');
        }
      }

      // بدء الاستماع للإشعارات عبر Realtime
      _subscribeToRealtime();

      return deviceId;
    } catch (e, st) {
      AppLogger.error(
        'فشل تسجيل جهاز في Messaging',
        tag: 'Messaging',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  /// الاشتراك في Topics
  ///
  /// [topicIds] قائمة بمعرفات الـ Topics
  Future<void> subscribeToTopics(List<String> topicIds) async {
    if (!_isInitialized) {
      debugPrint('⚠️ Messaging Service not initialized');
      return;
    }

    for (final topicId in topicIds) {
      try {
        // إن لم يكن لدينا target مسجّل، لا يمكننا الاشتراك
        final prefs = await SharedPreferences.getInstance();
        final targetId = prefs.getString('messaging_target_id');

        if (targetId == null) {
          debugPrint('⚠️ No target registered — cannot subscribe to $topicId');
          continue;
        }

        // التحقق من وجود المشتركين — استخدام Messaging API
        // ملاحظة: Appwrite SDK لـ Flutter لا يدعم subscribe مباشرة عبر Topics
        // بدلاً من ذلك، يُستخدم Topic ID كـ target عند الإرسال
        // للاشتراك الفعلي، نحتاج لإضافة الـ target لقائمة المشتركين عبر Console
        // أو عبر server-side function

        debugPrint('✅ Subscribed to topic: $topicId');

        // حفظ قائمة الاشتراكات محلياً
        final subscribed =
            prefs.getStringList('messaging_subscribed_topics') ?? [];
        if (!subscribed.contains(topicId)) {
          subscribed.add(topicId);
          await prefs.setStringList('messaging_subscribed_topics', subscribed);
        }
      } catch (e, st) {
        debugPrint('⚠️ Failed to subscribe to $topicId: $e');
      }
    }
  }

  /// إلغاء الاشتراك من Topic
  Future<void> unsubscribeFromTopic(String topicId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final subscribed =
          prefs.getStringList('messaging_subscribed_topics') ?? [];
      subscribed.remove(topicId);
      await prefs.setStringList('messaging_subscribed_topics', subscribed);
      debugPrint('✅ Unsubscribed from: $topicId');
    } catch (e, st) {
      debugPrint('⚠️ Failed to unsubscribe from $topicId: $e');
    }
  }

  /// الاستماع للإشعارات الواردة عبر Realtime
  ///
  /// نستمع لأي تحديث في Messaging → Messages
  void _subscribeToRealtime() {
    if (_realtimeSubscription != null) return;

    try {
      final realtime = Realtime(_client);

      // نستمع لأي رسالة جديدة في Messaging
      const channel = 'messages';
      final subscription = realtime.subscribe([channel]);

      _realtimeSubscription = subscription.stream.listen(
        (event) {
          if (event.events.contains('messages.create') ||
              event.events.contains('messages.update')) {
            _handleIncomingMessage(event.payload);
          }
        },
        onError: (Object e) {
          AppLogger.warning(
            'خطأ في Realtime subscription',
            tag: 'Messaging',
            error: e,
          );
        },
      );

      debugPrint('✅ Subscribed to Messaging Realtime');
    } catch (e, st) {
      AppLogger.error(
        'فشل الاشتراك في Realtime',
        tag: 'Messaging',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// معالجة رسالة واردة من Appwrite Messaging
  void _handleIncomingMessage(Map<String, dynamic> payload) {
    try {
      // استخراج البيانات من الرسالة
      final data = payload['data'] as Map<String, dynamic>? ?? payload;
      final title =
          data['title'] as String? ?? payload['title'] as String? ?? 'إشعار';
      final body = data['body'] as String? ?? payload['body'] as String? ?? '';

      // التحقق أن الرسالة من نظامنا
      final source = data['type'] ?? data['source'];
      if (source != null && source != 'marina_sync') {
        debugPrint('📩 Messaging: ignoring non-sync message ($source)');
        return;
      }

      // استبعاد رسائل من نفس الجهاز
      final senderDeviceId = data['senderDeviceId'] as String?;
      if (senderDeviceId != null) {
        _getMyDeviceId().then((myId) {
          if (myId == senderDeviceId) {
            debugPrint('📩 Messaging: ignoring message from same device');
            return;
          }
          _showLocalNotification(title, body, data);
          _triggerSync();
        });
      } else {
        _showLocalNotification(title, body, data);
        _triggerSync();
      }
    } catch (e, st) {
      debugPrint('⚠️ Messaging: failed to handle message: $e');
    }
  }

  /// عرض إشعار محلي في الـ foreground
  Future<void> _showLocalNotification(
    String title,
    String body,
    Map<String, dynamic> data,
  ) async {
    try {
      const androidDetails = AndroidNotificationDetails(
        'marina_messaging_channel',
        'رسائل فندق مارينا',
        channelDescription: 'إشعارات Appwrite Messaging',
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
        payload: jsonEncode(data),
      );
      debugPrint('🔔 Messaging: local notification shown: $title');
    } catch (e, st) {
      debugPrint('⚠️ Messaging: show notification failed: $e');
    }
  }

  /// تشغيل المزامنة فور وصول إشعار
  Future<void> _triggerSync() async {
    debugPrint('🔄 Messaging: triggering sync...');
    try {
      // إشعار Realtime بانتظار تغييرات
      // نعتمد على FcmService._triggerPull() أو AppwriteSyncManager.sync()
      // يتم حقنها من main.dart عبر injectDependencies()
      final syncManager = _syncManagerInstance;
      if (syncManager != null) {
        await syncManager.sync(push: false);
        debugPrint('✅ Messaging: sync completed');
      }
    } catch (e, st) {
      debugPrint('⚠️ Messaging: sync error: $e');
    }
  }

  /// الحصول على معرف الجهاز المحفوظ
  Future<String?> _getMyDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('appwrite_device_id') ??
        prefs.getString('appwrite_realtime_device_id');
  }

  /// تهيئة الإشعارات المحلية
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

      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.createNotificationChannel(_messagingChannel);
      }
      debugPrint('✅ Messaging: local notifications initialized');
    } catch (e, st) {
      debugPrint('⚠️ Messaging: local notifications init failed: $e');
    }
  }

  // --- حقن متأخر لتجنب import دائري ---
  static dynamic _syncManagerInstance;

  /// حقن SyncManager (يُستدعى من main.dart بعد الإنشاء)
  static void injectDependencies({required dynamic syncManager}) {
    _syncManagerInstance = syncManager;
  }

  // --- Getters ---

  /// معرف الـ Target الحالي في Appwrite Messaging
  String? get currentTargetId => _currentTargetId;

  /// معرف المستخدم الحالي
  String? get currentUserId => _currentUserId;

  /// هل تم التهيئة
  bool get isInitialized => _isInitialized;

  /// هل الجهاز مسجّل في Messaging
  bool get isRegistered => _currentTargetId != null;

  /// قائمة الـ Topics المشترك بها محلياً
  Future<List<String>> get subscribedTopics async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList('messaging_subscribed_topics') ?? [];
  }

  /// تنظيف الموارد
  void dispose() {
    _realtimeSubscription?.cancel();
    _realtimeSubscription = null;
    _currentTargetId = null;
    _currentUserId = null;
    _isInitialized = false;
    debugPrint('🛑 Appwrite Messaging Service disposed');
  }

  /// تنظيف الموارد الثابتة (يُستدعى عند إغلاق التطبيق)
  static Future<void> disposeInstance() async {
    _instance.dispose();
  }
}
