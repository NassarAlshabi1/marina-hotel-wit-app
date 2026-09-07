import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../utils/debug_log.dart';
import 'appwrite_config.dart';

/// نموذج عنصر الذاكرة المؤقتة.
class CacheEntry<T> {
  CacheEntry({required this.data, required this.timestamp, required this.ttl});
  final T data;
  final DateTime timestamp;
  final Duration ttl;

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;

  int get sizeInBytes {
    // تقدير متحفظ ومحدود؛ سياسة LRU تمنع تحوّل عدم دقة التقدير إلى نمو غير محدود.
    if (data is List) {
      return (data as List).length * 100;
    }
    if (data is Map) {
      return (data as Map).length * 120;
    }
    return 100;
  }
}

/// إحصائيات الذاكرة المؤقتة.
class CacheStatistics {
  CacheStatistics({
    required this.totalEntries,
    required this.validEntries,
    required this.expiredEntries,
    required this.totalSizeBytes,
    required this.maxSizeBytes,
    required this.hitRate,
    required this.hits,
    required this.misses,
  });
  final int totalEntries;
  final int validEntries;
  final int expiredEntries;
  final int totalSizeBytes;
  final int maxSizeBytes;
  final double hitRate;
  final int hits;
  final int misses;

  double get usagePercentage =>
      maxSizeBytes > 0 ? (totalSizeBytes / maxSizeBytes) * 100 : 0;

  String get totalSizeMB => (totalSizeBytes / (1024 * 1024)).toStringAsFixed(2);
  String get maxSizeMB => (maxSizeBytes / (1024 * 1024)).toStringAsFixed(2);
}

/// مدير cache داخل الذاكرة.
///
/// يستخدم [LinkedHashMap] كـ LRU: المفتاح الأول هو الأقل استخدامًا. بذلك تكون
/// عملية الإخلاء O(1) لكل عنصر بدلاً من فحص جميع العناصر في كل مرة.
class AppwriteCacheManager {
  factory AppwriteCacheManager() => _instance;
  AppwriteCacheManager._internal();
  static final AppwriteCacheManager _instance =
      AppwriteCacheManager._internal();
  static AppwriteCacheManager get instance => _instance;

  final LinkedHashMap<String, CacheEntry<dynamic>> _cache =
      LinkedHashMap<String, CacheEntry<dynamic>>();
  final Map<String, Future<dynamic>> _inFlightRequests =
      <String, Future<dynamic>>{};
  Timer? _cleanupTimer;

  // يمنع طلب قديم بدأ قبل clear()/ضغط الذاكرة من إعادة ملء Cache بعد التفريغ.
  int _generation = 0;
  int _hits = 0;
  int _misses = 0;
  int _currentSizeBytes = 0;
  int _maxSizeBytes = AppwriteConfig.maxCacheSizeMB * 1024 * 1024;
  int _maxEntries = 500;
  Duration _defaultTTL = AppwriteConfig.cacheExpiry;
  bool _enabled = true;

  /// تفعيل/تعطيل الذاكرة المؤقتة.
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      clear();
    }
  }

  /// تعيين الحد الأقصى للحجم بالميجابايت.
  void setMaxSizeMB(int sizeMB) {
    _maxSizeBytes = sizeMB.clamp(1, 1024) * 1024 * 1024;
    _evictIfNeeded();
  }

  /// تعيين حد إدخالات LRU. مفيد خصوصًا للأجهزة ذات 1GB RAM.
  void setMaxEntries(int maxEntries) {
    _maxEntries = maxEntries.clamp(1, 10000);
    _evictIfNeeded();
  }

  /// تعيين مدة الصلاحية الافتراضية.
  void setDefaultTTL(Duration ttl) {
    _defaultTTL = ttl;
  }

  /// يعيد قيمة cache أو يشارك طلباً جارياً لنفس المفتاح.
  ///
  /// يمنع ذلك تكرار استدعاءات Appwrite ونسخ الاستجابة نفسها في الذاكرة عندما
  /// تطلب عدة Widgets أو Providers قائمة البيانات ذاتها في اللحظة نفسها.
  Future<T> getOrLoad<T>(
    String key,
    Future<T> Function() loader, {
    Duration? ttl,
  }) {
    if (!_enabled) {
      return Future<T>.sync(loader);
    }

    final cached = get<T>(key);
    if (cached != null) {
      return Future<T>.value(cached);
    }

    final inFlight = _inFlightRequests[key];
    if (inFlight != null) {
      return inFlight as Future<T>;
    }

    final generationAtStart = _generation;
    late final Future<T> request;
    request = Future<T>.sync(loader)
        .then((value) {
          // لا تعِد إدخال نتيجة بدأت قبل تفريغ cache بسبب ضغط الذاكرة أو
          // انتقال التطبيق للخلفية.
          if (_enabled && generationAtStart == _generation) {
            set(key, value, ttl: ttl);
          }
          return value;
        })
        .whenComplete(() {
          // لا نعيد Future المحذوف من callback؛ إعادته ستنشئ دورة انتظار
          // مع الطلب ذاته وتمنع اكتماله.
          unawaited(_inFlightRequests.remove(key));
        });
    _inFlightRequests[key] = request;
    return request;
  }

  /// حفظ بيانات في الذاكرة المؤقتة.
  void set<T>(String key, T data, {Duration? ttl}) {
    if (!_enabled) {
      return;
    }

    _removeEntry(key);
    final entry = CacheEntry<T>(
      data: data,
      timestamp: DateTime.now(),
      ttl: ttl ?? _defaultTTL,
    );
    _cache[key] = entry;
    _currentSizeBytes += entry.sizeInBytes;
    _evictIfNeeded();
  }

  /// الحصول على بيانات من الذاكرة المؤقتة وتحديث ترتيب LRU.
  T? get<T>(String key) {
    if (!_enabled) {
      return null;
    }

    final entry = _cache[key];
    if (entry == null) {
      _misses++;
      return null;
    }

    if (entry.isExpired) {
      _removeEntry(key);
      _misses++;
      return null;
    }

    _touch(key, entry);
    _hits++;
    return entry.data as T?;
  }

  /// التحقق من وجود مفتاح. يعامل كاستخدام للمفتاح ويحدث ترتيب LRU.
  bool has(String key) {
    if (!_enabled) {
      return false;
    }

    final entry = _cache[key];
    if (entry == null) {
      return false;
    }

    if (entry.isExpired) {
      _removeEntry(key);
      return false;
    }

    _touch(key, entry);
    return true;
  }

  /// حذف عنصر من الذاكرة المؤقتة.
  void remove(String key) {
    _removeEntry(key);
  }

  /// مسح جميع العناصر.
  void clear() {
    _generation++;
    _cache.clear();
    _currentSizeBytes = 0;
    _hits = 0;
    _misses = 0;
  }

  /// مسح العناصر منتهية الصلاحية.
  int clearExpired() {
    final expiredKeys = <String>[];
    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    expiredKeys.forEach(_removeEntry);
    return expiredKeys.length;
  }

  /// مسح العناصر بناءً على نمط.
  int clearByPattern(String pattern) {
    final regex = RegExp(pattern);
    final keysToRemove = _cache.keys.where(regex.hasMatch).toList();
    keysToRemove.forEach(_removeEntry);
    return keysToRemove.length;
  }

  /// يقلص cache عند وضع التطبيق في الخلفية بدلاً من مسحه كاملاً.
  /// يحتفظ بربع الحد الأقصى فقط لتسريع العودة القصيرة للواجهة على الأجهزة
  /// الضعيفة، ويترك قاعدة Drift وOutbox دون أي تغيير.
  int trimForBackground() {
    final targetEntries = (_maxEntries / 4).ceil().clamp(1, _maxEntries);
    final targetBytes = (_maxSizeBytes / 4).ceil().clamp(1, _maxSizeBytes);
    var removed = clearExpired();

    while ((_cache.length > targetEntries || _currentSizeBytes > targetBytes) &&
        _cache.isNotEmpty) {
      _removeEntry(_cache.keys.first);
      removed++;
    }
    return removed;
  }

  /// يخفض cache فورًا عند إشارة ضغط ذاكرة من النظام.
  void handleMemoryPressure() {
    clear();
    if (kDebugMode) {
      dlog('🧹 Appwrite cache cleared due to memory pressure');
    }
  }

  void _touch(String key, CacheEntry<dynamic> entry) {
    _cache.remove(key);
    _cache[key] = entry;
  }

  void _removeEntry(String key) {
    final removed = _cache.remove(key);
    if (removed != null) {
      _currentSizeBytes = (_currentSizeBytes - removed.sizeInBytes).clamp(
        0,
        1 << 62,
      );
    }
  }

  /// إزالة عناصر LRU حتى يتحقق حد الحجم وحد العدد.
  void _evictIfNeeded() {
    while ((_currentSizeBytes > _maxSizeBytes || _cache.length > _maxEntries) &&
        _cache.isNotEmpty) {
      _removeEntry(_cache.keys.first);
    }
  }

  /// بدء التنظيف التلقائي.
  void startCleanup({Duration interval = const Duration(minutes: 30)}) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(interval, (timer) {
      final removed = clearExpired();
      if (removed > 0 && kDebugMode) {
        dlog(() => '🧹 Cache cleanup: removed $removed expired entries');
      }
    });
  }

  /// إيقاف التنظيف التلقائي.
  void stopCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// الحصول على الإحصائيات.
  CacheStatistics getStatistics() {
    var validEntries = 0;
    var expiredEntries = 0;

    for (final entry in _cache.values) {
      if (entry.isExpired) {
        expiredEntries++;
      } else {
        validEntries++;
      }
    }

    final totalRequests = _hits + _misses;
    final hitRate = totalRequests > 0 ? (_hits / totalRequests) : 0.0;

    return CacheStatistics(
      totalEntries: _cache.length,
      validEntries: validEntries,
      expiredEntries: expiredEntries,
      totalSizeBytes: _currentSizeBytes,
      maxSizeBytes: _maxSizeBytes,
      hitRate: hitRate,
      hits: _hits,
      misses: _misses,
    );
  }

  /// إعادة تعيين الإحصائيات.
  void resetStatistics() {
    _hits = 0;
    _misses = 0;
  }

  /// التخلص من الموارد.
  void dispose() {
    stopCleanup();
    clear();
  }

  // مساعدات لمفاتيح الذاكرة المؤقتة.
  static String roomsKey() => 'rooms_all';
  static String roomKey(String id) => 'room_$id';
  static String bookingsKey() => 'bookings_all';
  static String bookingKey(String id) => 'booking_$id';
  static String paymentsKey() => 'payments_all';
  static String paymentKey(String id) => 'payment_$id';
  static String expensesKey() => 'expenses_all';
  static String expenseKey(String id) => 'expense_$id';
  static String employeesKey() => 'employees_all';
  static String employeeKey(String id) => 'employee_$id';
  static String debtsKey() => 'debts_all';
  static String debtKey(String id) => 'debt_$id';
}
