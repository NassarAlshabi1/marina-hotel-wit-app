import 'dart:async';

import 'package:appwrite/appwrite.dart';

import 'appwrite_cache_manager.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';

/// نوع الحدث في Realtime
enum RealtimeEventType { create, update, delete, unknown }

/// حدث Realtime
class RealtimeEvent {
  RealtimeEvent({
    required this.type,
    required this.collection,
    required this.documentId,
    this.data,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
  final RealtimeEventType type;
  final String collection;
  final String documentId;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  @override
  String toString() =>
      'RealtimeEvent(type: $type, collection: $collection, id: $documentId)';
}

/// معالج أحداث Realtime
typedef RealtimeEventHandler = void Function(RealtimeEvent event);

/// خدمة Appwrite Realtime - التحديثات الفورية
///
/// ⚠️ **DEPRECATED** — تحليل P2-13 أظهر أن هذه الخدمة لا تُستدعى من أي مسار
/// إنتاجي (لا `initialize()` ولا `subscribeToAllCollections()` تُستدعى).
/// الخدمة الفعلية هي `AppwriteRealtimeSync` التي تستخدم اتصال WebSocket واحد
/// (بدلاً من 18 اتصالاً منفصلاً هنا). يُترك هذا الملف للتوافق مع أي استدعاءات
/// مخفية. لا تُضف استدعاءات جديدة — استخدم `AppwriteRealtimeSync` بدلاً من ذلك.
@Deprecated(
  'استخدم AppwriteRealtimeSync بدلاً من ذلك — هذه الخدمة غير مستخدمة في الإنتاج',
)
class AppwriteRealtimeService {
  factory AppwriteRealtimeService() => _instance;
  AppwriteRealtimeService._internal();
  static final AppwriteRealtimeService _instance =
      AppwriteRealtimeService._internal();

  late final Realtime _realtime;
  final _logger = AppwriteLogger();
  final _cache = AppwriteCacheManager();

  bool _initialized = false;
  final Map<String, RealtimeSubscription> _subscriptions = {};
  final Map<String, List<RealtimeEventHandler>> _handlers = {};
  // ✅ تتبع محاولات إعادة الاتصال لكل collection لتطبيق exponential backoff
  // بدون نمو غير محدود (يُصفّر عند نجاح الاتصال).
  final Map<String, int> _reconnectAttempts = {};
  static const int _maxReconnectAttempts = 6;
  static const Duration _baseReconnectDelay = Duration(seconds: 1);
  static const Duration _maxReconnectDelay = Duration(seconds: 30);

  /// تهيئة خدمة Realtime
  Future<void> initialize(Client client) async {
    if (_initialized) {
      return;
    }

    try {
      _realtime = Realtime(client);
      _initialized = true;
      _logger.info('Appwrite Realtime service initialized', tag: 'REALTIME');
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to initialize Realtime service',
        error: e,
        stackTrace: stackTrace,
        tag: 'REALTIME',
      );
      rethrow;
    }
  }

  /// الاشتراك في مجموعة (Collection)
  ///
  /// [collectionId] - معرف المجموعة
  /// [handler] - معالج الأحداث
  /// [events] - أنواع الأحداث المطلوبة (create, update, delete)
  Future<void> subscribeToCollection({
    required String collectionId,
    required RealtimeEventHandler handler,
    List<String>? events,
  }) async {
    if (!_initialized) {
      throw Exception('Realtime service not initialized');
    }

    try {
      // إنشاء قنوات الاشتراك
      final channels = _buildChannels(collectionId, events);
      final subscriptionKey = 'collection_$collectionId';

      _logger.debug(
        'Subscribing to collection: $collectionId',
        tag: 'REALTIME',
      );

      // إلغاء الاشتراك القديم إذا كان موجوداً
      if (_subscriptions.containsKey(subscriptionKey)) {
        unawaited(_subscriptions[subscriptionKey]!.close());
        _subscriptions.remove(subscriptionKey);
      }

      // ✅ مسح قائمة handlers القديمة قبل إضافة الجديدة لمنع النمو غير المحدود
      // عند إعادة الاشتراك المتكرر (إصلاح P3-18 من تقرير الأداء).
      _handlers[subscriptionKey] = [handler];

      // إنشاء اشتراك جديد
      final subscription = _realtime.subscribe(channels);

      // الاستماع للأحداث
      subscription.stream.listen(
        (response) {
          // ✅ تصفير عداد إعادة الاتصال عند نجاح استلام حدث — يعني الاتصال صحي
          _reconnectAttempts.remove(subscriptionKey);
          _handleRealtimeResponse(response, collectionId, handler);
        },
        onError: (Object error) {
          _logger.error(
            'Realtime subscription error for $collectionId',
            error: error,
            tag: 'REALTIME',
          );
          // ✅ إصلاح PR review: لا نُعيد الاتصال هنا — onDone يُستدعى دائماً
          // بعد onError (Stream protocol)، وسيُعيد الاتصال هناك. سابقاً كان
          // _scheduleReconnect يُستدعى مرتين → timer مزدوج → reconnect عشوائي.
        },
        onDone: () {
          _logger.info(
            'Realtime subscription closed for $collectionId',
            tag: 'REALTIME',
          );
          // ✅ إعادة الاتصال عند إغلاق الاتصال (مثل انقطاع الشبكة) — exponential backoff
          _scheduleReconnect(collectionId, events: events, handler: handler);
        },
      );

      _subscriptions[subscriptionKey] = subscription;

      _logger.info(
        'Successfully subscribed to collection: $collectionId',
        tag: 'REALTIME',
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to subscribe to collection: $collectionId',
        error: e,
        stackTrace: stackTrace,
        tag: 'REALTIME',
      );
      rethrow;
    }
  }

  /// إعادة الاتصال بتطبيق exponential backoff — يمنع إغراق الخادم بالمحاولات
  /// عند الانقطاع. التأخير يتضاعف: 1s, 2s, 4s, 8s, 16s, 30s (capped).
  /// بعد _maxReconnectAttempts محاولات، يتوقف لتجنب إهدار البطارية.
  Future<void> _scheduleReconnect(
    String collectionId, {
    List<String>? events,
    RealtimeEventHandler? handler,
  }) async {
    if (!_initialized || handler == null) return;

    final subscriptionKey = 'collection_$collectionId';
    final attempts = (_reconnectAttempts[subscriptionKey] ?? 0) + 1;

    if (attempts > _maxReconnectAttempts) {
      _logger.warning(
        'Max reconnect attempts ($_maxReconnectAttempts) reached for $collectionId — giving up',
        tag: 'REALTIME',
      );
      _reconnectAttempts.remove(subscriptionKey);
      return;
    }

    _reconnectAttempts[subscriptionKey] = attempts;

    // exponential backoff مع سقف أعلى — 2^(n-1) ثانية، max 30s
    final delaySeconds = (_baseReconnectDelay.inSeconds * (1 << (attempts - 1)))
        .clamp(1, _maxReconnectDelay.inSeconds);

    _logger.info(
      'Scheduling reconnect #$attempts for $collectionId in ${delaySeconds}s',
      tag: 'REALTIME',
    );

    await Future<void>.delayed(Duration(seconds: delaySeconds));

    // تحقق أن الخدمة ما زالت مهيّأة وأن المستخدم لم يُلغِ الاشتراك يدوياً
    if (!_initialized || !_handlers.containsKey(subscriptionKey)) {
      _reconnectAttempts.remove(subscriptionKey);
      return;
    }

    try {
      await subscribeToCollection(
        collectionId: collectionId,
        handler: handler,
        events: events,
      );
    } catch (e) {
      _logger.error(
        'Reconnect attempt #$attempts failed for $collectionId',
        error: e,
        tag: 'REALTIME',
      );
      // المحاولة التالية ستُجدول من داخل subscribeToCollection عند فشل الاتصال
    }
  }

  /// الاشتراك في مستند محدد
  Future<void> subscribeToDocument({
    required String collectionId,
    required String documentId,
    required RealtimeEventHandler handler,
  }) async {
    if (!_initialized) {
      throw Exception('Realtime service not initialized');
    }

    try {
      final channel =
          'databases.${AppwriteConfig.databaseId}.collections.$collectionId.documents.$documentId';
      final subscriptionKey = 'document_${collectionId}_$documentId';

      _logger.debug(
        'Subscribing to document: $collectionId/$documentId',
        tag: 'REALTIME',
      );

      // إلغاء الاشتراك القديم
      if (_subscriptions.containsKey(subscriptionKey)) {
        unawaited(_subscriptions[subscriptionKey]!.close());
        _subscriptions.remove(subscriptionKey);
      }

      // ✅ مسح handlers القديمة (تم بالفعل في السطر التالي، لكن نُكرّر التأكيد
      // لمنع نمو القائمة عند إعادة الاشتراك المتكرر).
      _handlers[subscriptionKey] = [handler];

      // إنشاء اشتراك جديد
      final subscription = _realtime.subscribe([channel]);

      subscription.stream.listen(
        (response) {
          _handleRealtimeResponse(response, collectionId, handler);
        },
        onError: (Object error) {
          _logger.error(
            'Realtime subscription error for document $documentId',
            error: error,
            tag: 'REALTIME',
          );
        },
      );

      _subscriptions[subscriptionKey] = subscription;

      _logger.info(
        'Successfully subscribed to document: $collectionId/$documentId',
        tag: 'REALTIME',
      );
    } catch (e, stackTrace) {
      _logger.error(
        'Failed to subscribe to document',
        error: e,
        stackTrace: stackTrace,
        tag: 'REALTIME',
      );
      rethrow;
    }
  }

  /// الاشتراك في جميع المجموعات المهمة
  Future<void> subscribeToAllCollections(RealtimeEventHandler handler) async {
    final collections = [
      AppwriteConfig.roomsCollectionId,
      AppwriteConfig.bookingsCollectionId,
      AppwriteConfig.bookingNotesCollectionId,
      AppwriteConfig.bookingNightsCollectionId,
      AppwriteConfig.paymentsCollectionId,
      AppwriteConfig.expensesCollectionId,
      AppwriteConfig.cashTransactionsCollectionId,
      AppwriteConfig.employeesCollectionId,
      AppwriteConfig.debtsCollectionId,
      // ❌ hotel_day_ledger - محلي فقط
      AppwriteConfig.salaryCyclesCollectionId,
      AppwriteConfig.salaryPaymentsCollectionId,
      AppwriteConfig.salaryWithdrawalsCollectionId,
      AppwriteConfig.shiftNotesCollectionId,
      AppwriteConfig.guestInfosCollectionId,
      AppwriteConfig.priceAdjustmentsCollectionId,
      AppwriteConfig.bookingPriceAdjustmentsCollectionId,
      AppwriteConfig.auditLogsCollectionId,
      AppwriteConfig.paymentVoidsCollectionId,
    ];

    for (final collectionId in collections) {
      try {
        await subscribeToCollection(
          collectionId: collectionId,
          handler: handler,
        );
      } catch (e) {
        _logger.warning(
          'Failed to subscribe to $collectionId, continuing...',
          error: e,
          tag: 'REALTIME',
        );
      }
    }

    _logger.info(
      'Subscribed to ${collections.length} collections',
      tag: 'REALTIME',
    );
  }

  /// إلغاء الاشتراك في مجموعة
  void unsubscribeFromCollection(String collectionId) {
    final subscriptionKey = 'collection_$collectionId';

    if (_subscriptions.containsKey(subscriptionKey)) {
      _subscriptions[subscriptionKey]!.close();
      _subscriptions.remove(subscriptionKey);
      _handlers.remove(subscriptionKey);

      _logger.info(
        'Unsubscribed from collection: $collectionId',
        tag: 'REALTIME',
      );
    }
  }

  /// إلغاء الاشتراك في مستند
  void unsubscribeFromDocument(String collectionId, String documentId) {
    final subscriptionKey = 'document_${collectionId}_$documentId';

    if (_subscriptions.containsKey(subscriptionKey)) {
      _subscriptions[subscriptionKey]!.close();
      _subscriptions.remove(subscriptionKey);
      _handlers.remove(subscriptionKey);

      _logger.info(
        'Unsubscribed from document: $collectionId/$documentId',
        tag: 'REALTIME',
      );
    }
  }

  /// إلغاء جميع الاشتراكات
  void unsubscribeAll() {
    for (final subscription in _subscriptions.values) {
      subscription.close();
    }
    _subscriptions.clear();
    _handlers.clear();

    _logger.info('Unsubscribed from all Realtime channels', tag: 'REALTIME');
  }

  /// معالجة استجابة Realtime
  void _handleRealtimeResponse(
    dynamic response,
    String collectionId,
    RealtimeEventHandler handler,
  ) {
    try {
      final events = response.events as List;

      if (events.isEmpty) {
        _logger.debug(
          'Received Realtime message with no events',
          tag: 'REALTIME',
        );
        return;
      }

      // تحديد نوع الحدث
      RealtimeEventType eventType = RealtimeEventType.unknown;
      if (events.any((e) => (e as String).contains('create'))) {
        eventType = RealtimeEventType.create;
      } else if (events.any((e) => (e as String).contains('update'))) {
        eventType = RealtimeEventType.update;
      } else if (events.any((e) => (e as String).contains('delete'))) {
        eventType = RealtimeEventType.delete;
      }

      // استخراج البيانات
      final payload = (response.payload as Map<String, dynamic>?) ?? {};
      final documentId = (payload[r'$id'] ?? '') as String;

      _logger.debug(
        'Realtime event: $eventType on $collectionId/$documentId',
        tag: 'REALTIME',
      );

      // إنشاء حدث Realtime
      final event = RealtimeEvent(
        type: eventType,
        collection: collectionId,
        documentId: documentId,
        data: payload as Map<String, dynamic>?,
      );

      // تحديث الذاكرة المؤقتة
      _updateCacheOnEvent(event);

      // استدعاء المعالج
      handler(event);
    } catch (e, stackTrace) {
      _logger.error(
        'Error handling Realtime response',
        error: e,
        stackTrace: stackTrace,
        tag: 'REALTIME',
      );
    }
  }

  /// تحديث الذاكرة المؤقتة بناءً على الحدث
  void _updateCacheOnEvent(RealtimeEvent event) {
    try {
      final cacheKey = '${event.collection}_${event.documentId}';

      switch (event.type) {
        case RealtimeEventType.create:
        case RealtimeEventType.update:
          // تحديث أو إضافة إلى الذاكرة المؤقتة
          if (event.data != null) {
            _cache.set(cacheKey, event.data);
          }
          // مسح قائمة المستندات للتحديث
          _cache.clearByPattern('^${event.collection}_all');

        case RealtimeEventType.delete:
          // حذف من الذاكرة المؤقتة
          _cache.remove(cacheKey);
          _cache.clearByPattern('^${event.collection}_all');

        case RealtimeEventType.unknown:
          // لا شيء
          break;
      }
    } catch (e) {
      _logger.warning(
        'Failed to update cache on Realtime event',
        error: e,
        tag: 'REALTIME',
      );
    }
  }

  /// بناء قنوات الاشتراك
  List<String> _buildChannels(String collectionId, List<String>? events) {
    final baseChannel =
        'databases.${AppwriteConfig.databaseId}.collections.$collectionId.documents';

    if (events == null || events.isEmpty) {
      return [baseChannel];
    }

    // إنشاء قنوات محددة لأنواع الأحداث
    return events.map((event) => '$baseChannel.$event').toList();
  }

  /// الحصول على إحصائيات الاشتراكات
  Map<String, dynamic> getSubscriptionStats() {
    return {
      'total_subscriptions': _subscriptions.length,
      'active_subscriptions': _subscriptions.keys.toList(),
      'handlers_count': _handlers.length,
      'initialized': _initialized,
    };
  }

  /// التحقق من وجود اشتراك نشط
  bool hasActiveSubscription(String collectionId) {
    return _subscriptions.containsKey('collection_$collectionId');
  }

  /// إغلاق الخدمة
  void dispose() {
    unsubscribeAll();
    _initialized = false;
    _logger.info('Realtime service disposed', tag: 'REALTIME');
  }

  /// تنظيف الموارد الثابتة للـ singleton (يُستدعى عند إغلاق التطبيق)
  static Future<void> disposeInstance() async {
    _instance.dispose();
  }
}
