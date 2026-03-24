import 'dart:async';
import 'package:appwrite/appwrite.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';
import 'appwrite_cache_manager.dart';

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

  /// تهيئة خدمة Realtime
  Future<void> initialize(Client client) async {
    if (_initialized) return;

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
        _subscriptions[subscriptionKey]!.close();
        _subscriptions.remove(subscriptionKey);
      }

      // إنشاء اشتراك جديد
      final subscription = _realtime.subscribe(channels);

      // الاستماع للأحداث
      subscription.stream.listen(
        (response) {
          _handleRealtimeResponse(response, collectionId, handler);
        },
        onError: (error) {
          _logger.error(
            'Realtime subscription error for $collectionId',
            error: error,
            tag: 'REALTIME',
          );
        },
        onDone: () {
          _logger.info(
            'Realtime subscription closed for $collectionId',
            tag: 'REALTIME',
          );
        },
      );

      _subscriptions[subscriptionKey] = subscription;
      _handlers[subscriptionKey] = _handlers[subscriptionKey] ?? [];
      _handlers[subscriptionKey]!.add(handler);

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
        _subscriptions[subscriptionKey]!.close();
        _subscriptions.remove(subscriptionKey);
      }

      // إنشاء اشتراك جديد
      final subscription = _realtime.subscribe([channel]);

      subscription.stream.listen(
        (response) {
          _handleRealtimeResponse(response, collectionId, handler);
        },
        onError: (error) {
          _logger.error(
            'Realtime subscription error for document $documentId',
            error: error,
            tag: 'REALTIME',
          );
        },
      );

      _subscriptions[subscriptionKey] = subscription;
      _handlers[subscriptionKey] = [handler];

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
      AppwriteConfig.shiftNotesCollectionId,
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
      final events = response.events;

      if (events.isEmpty) {
        _logger.debug(
          'Received Realtime message with no events',
          tag: 'REALTIME',
        );
        return;
      }

      // تحديد نوع الحدث
      RealtimeEventType eventType = RealtimeEventType.unknown;
      if (events.any((e) => e.contains('create'))) {
        eventType = RealtimeEventType.create;
      } else if (events.any((e) => e.contains('update'))) {
        eventType = RealtimeEventType.update;
      } else if (events.any((e) => e.contains('delete'))) {
        eventType = RealtimeEventType.delete;
      }

      // استخراج البيانات
      final payload = response.payload;
      final documentId = payload['\$id'] ?? '';

      _logger.debug(
        'Realtime event: $eventType on $collectionId/$documentId',
        tag: 'REALTIME',
      );

      // إنشاء حدث Realtime
      final event = RealtimeEvent(
        type: eventType,
        collection: collectionId,
        documentId: documentId,
        data: payload,
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
}
