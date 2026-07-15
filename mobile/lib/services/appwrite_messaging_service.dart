// lib/services/appwrite_messaging_service.dart
//
// ✅ خدمة Appwrite Messaging — بديل/مكمّل لـ FCM المباشر.
//
// الوظائف:
// 1. تسجيل جهاز المستخدم في collection "devices" (يستخدمها messaging-notifier Function)
// 2. الاشتراك في Topics (حسب صلاحية المستخدم) — عبر createSubscriber
// 3. الاستماع للإشعارات الواردة عبر Appwrite Realtime
// 4. تشغيل المزامنة فور وصول إشعار
// 5. عرض إشعار محلي في الـ foreground
//
// ⚠️ ملاحظة مهمة عن Appwrite Client SDK 21.x:
// Client SDK (Flutter) محدود جداً في Messaging — يدعم فقط:
//   - Messaging.createSubscriber(topicId, subscriberId, targetId)
//   - Messaging.deleteSubscriber(topicId, subscriberId)
//
// الـ methods التالية موجودة فقط في Server SDK (node-appwrite):
//   - createTarget / updateTarget / listTargets
//   - createPush / listMessages / getMessage
//   - createTopic / updateTopic / listTopics
//   - listProviders
//
// لذلك تسجيل الأجهزة يتم عبر collection "devices" المخصّصة (التي تقرأها
// messaging-notifier Function)، وليس عبر Targets API الرسمي.

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
/// - تسجيل تلقائي للجهاز في collection "devices" (للتوافق مع messaging-notifier)
/// - اشتراك في Topics عبر createSubscriber (عند توفر targetId من console)
/// - استقبال الإشعارات عبر Realtime
/// - عرض إشعارات محلية في الـ foreground
class AppwriteMessagingService {
  factory AppwriteMessagingService() => _instance;
  AppwriteMessagingService._internal();
  static final AppwriteMessagingService _instance =
      AppwriteMessagingService._internal();

  late final Messaging _messaging;
  late final Account _account;
  late final Client _client;
  late final Databases _databases;

  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _currentTargetId;
  String? _currentUserId;
  bool _isInitialized = false;
  // ✅ استخدام StreamSubscription<dynamic> بدلاً من raw type
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
      _messaging = Messaging(_client);
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

  /// تسجيل الجهاز في collection "devices" (تستخدمه messaging-notifier Function)
  ///
  /// [fcmToken] التوكن من Firebase (مطلوب للأندرويد)
  /// [userId] معرف المستخدم (اختياري — يُربط الـ Target بحساب المستخدم)
  ///
  /// ملاحظة: Appwrite Client SDK 21.x لا يدعم createTarget/updateTarget.
  /// لذلك نُسجّل في collection "devices" المخصّصة، التي تقرأها
  /// messaging-notifier Function لإرسال FCM مباشرة.
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
      final deviceId = prefs.getString('appwrite_device_id') ??
          prefs.getString('appwrite_realtime_device_id') ??
          'device_${DateTime.now().millisecondsSinceEpoch}';

      // تسجيل/تحديث في collection "devices"
      // نستخدم upsert pattern: نُحاول update أولاً، إذا فشل (404) نُنشئ
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
        debugPrint('✅ Messaging device updated in collection: $deviceId');
      } on AppwriteException catch (e) {
        // إذا المستند غير موجود (404)، نُنشئه
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
          debugPrint('✅ Messaging device created in collection: $deviceId');
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
          // ✅ updatePrefs يأخذ Map (ليس Map<String, dynamic>)
          await _account.updatePrefs(
            prefs: {
              'messaging_target_id': deviceId,
              'messaging_registered_at': DateTime.now().toIso8601String(),
            },
          );
        } catch (e) {
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

  /// الاشتراك في Topics عبر Messaging.createSubscriber
  ///
  /// [topicIds] قائمة بمعرفات الـ Topics
  ///
  /// ملاحظة: يتطلب وجود targetId مُسجّل مسبقاً في Appwrite Messaging Console
  /// (Targets API). إذا لم يكن موجوداً، نكتفي بتسجيل الاشتراك محلياً
  /// لإعادة المحاولة لاحقاً.
  Future<void> subscribeToTopics(List<String> topicIds) async {
    if (!_isInitialized) {
      debugPrint('⚠️ Messaging Service not initialized');
      return;
    }

    for (final topicId in topicIds) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final targetId = prefs.getString('messaging_target_id');

        if (targetId == null) {
          debugPrint('⚠️ No target registered — cannot subscribe to $topicId');
          continue;
        }

        // محاولة الاشتراك عبر createSubscriber
        // ✅ createSubscriber(topicId, subscriberId, targetId) — Client SDK 21.x
        try {
          final subscriberId = '${targetId}_$topicId';
          await _messaging.createSubscriber(
            topicId: topicId,
            subscriberId: subscriberId,
            targetId: targetId,
          );
          debugPrint('✅ Subscribed to topic: $topicId');
        } on AppwriteException catch (e) {
          // 409 = subscriber already exists — ليس خطأً
          if (e.code != 409) {
            debugPrint('⚠️ Failed to subscribe to $topicId: ${e.message}');
          }
        }

        // حفظ قائمة الاشتراكات محلياً
        final subscribed =
            prefs.getStringList('messaging_subscribed_topics') ?? [];
        if (!subscribed.contains(topicId)) {
          subscribed.add(topicId);
          await prefs.setStringList('messaging_subscribed_topics', subscribed);
        }
      } catch (e) {
        debugPrint('⚠️ Failed to subscribe to $topicId: $e');
      }
    }
  }

  /// إلغاء الاشتراك من Topic
  Future<void> unsubscribeFromTopic(String topicId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final targetId = prefs.getString('messaging_target_id');

      if (targetId != null) {
        final subscriberId = '${targetId}_$topicId';
        try {
          await _messaging.deleteSubscriber(
            topicId: topicId,
            subscriberId: subscriberId,
          );
        } on AppwriteException catch (e) {
          // 404 = subscriber not found — ليس خطأً
          if (e.code != 404) {
            debugPrint('⚠️ Failed to unsubscribe from $topicId: ${e.message}');
          }
        }
      }

      final subscribed =
          prefs.getStringList('messaging_subscribed_topics') ?? [];
      subscribed.remove(topicId);
      await prefs.setStringList('messaging_subscribed_topics', subscribed);
      debugPrint('✅ Unsubscribed from: $topicId');
    } catch (e) {
      debugPrint('⚠️ Failed to unsubscribe from $topicId: $e');
    }
  }

  /// الاستماع للإشعارات الواردة عبر Realtime
  void _subscribeToRealtime() {
    if (_realtimeSubscription != null) return;

    try {
      final realtime = Realtime(_client);

      // نستمع لأي تحديث في Messaging → Messages
      const channel = 'messages';
      final subscription = realtime.subscribe([channel]);

      _realtimeSubscription = subscription.stream.listen(
        // ✅ تحديد نوع event بشكل صريح
        (dynamic event) {
          try {
            final eventMap = event as Map<String, dynamic>;
            final events = eventMap['events'] as List<dynamic>?;
            if (events != null &&
                (events.contains('messages.create') ||
                    events.contains('messages.update'))) {
              _handleIncomingMessage(
                  eventMap['payload'] as Map<String, dynamic>? ?? {});
            }
          } catch (e) {
            debugPrint('⚠️ Messaging: failed to parse realtime event: $e');
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
    } catch (e) {
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
      const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

      await _localNotifications.show(
        DateTime.now().millisecondsSinceEpoch ~/ 1000,
        title,
        body,
        details,
        payload: jsonEncode(data),
      );
      debugPrint('🔔 Messaging: local notification shown: $title');
    } catch (e) {
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
    } catch (e) {
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
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );
      await _localNotifications.initialize(settings);

      if (Platform.isAndroid) {
        await _localNotifications
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_messagingChannel);
      }
      debugPrint('✅ Messaging: local notifications initialized');
    } catch (e) {
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
