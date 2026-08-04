import 'dart:async';
import 'dart:collection';
import 'package:flutter/foundation.dart';
import 'appwrite_config.dart';

/// نموذج عنصر الذاكرة المؤقتة
class CacheEntry<T> {
  CacheEntry({required this.data, required this.timestamp, required this.ttl});
  final T data;
  final DateTime timestamp;
  final Duration ttl;

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;

  int get sizeInBytes {
    // تقدير حجم البيانات (تقريبي)
    if (data is List) {
      return (data as List).length * 100; // تقدير 100 بايت لكل عنصر
    }
    return 100; // افتراضي
  }
}

/// إحصائيات الذاكرة المؤقتة
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

/// مدير الذاكرة المؤقتة
class AppwriteCacheManager {
  factory AppwriteCacheManager() => _instance;
  AppwriteCacheManager._internal();
  static final AppwriteCacheManager _instance =
      AppwriteCacheManager._internal();

  final Map<String, CacheEntry<dynamic>> _cache =
      HashMap<String, CacheEntry<dynamic>>();
  Timer? _cleanupTimer;

  int _hits = 0;
  int _misses = 0;
  int _maxSizeBytes = AppwriteConfig.maxCacheSizeMB * 1024 * 1024;
  Duration _defaultTTL = AppwriteConfig.cacheExpiry;
  bool _enabled = true;

  /// تفعيل/تعطيل الذاكرة المؤقتة
  void setEnabled(bool enabled) {
    _enabled = enabled;
    if (!enabled) {
      clear();
    }
  }

  /// تعيين الحد الأقصى للحجم (بالميجابايت)
  void setMaxSizeMB(int sizeMB) {
    _maxSizeBytes = sizeMB * 1024 * 1024;
    _evictIfNeeded();
  }

  /// تعيين مدة الصلاحية الافتراضية
  void setDefaultTTL(Duration ttl) {
    _defaultTTL = ttl;
  }

  /// حفظ بيانات في الذاكرة المؤقتة
  void set<T>(String key, T data, {Duration? ttl}) {
    if (!_enabled) {
      return;
    }

    final entry = CacheEntry<T>(
      data: data,
      timestamp: DateTime.now(),
      ttl: ttl ?? _defaultTTL,
    );

    _cache[key] = entry;
    _evictIfNeeded();
  }

  /// الحصول على بيانات من الذاكرة المؤقتة
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
      _cache.remove(key);
      _misses++;
      return null;
    }

    _hits++;
    return entry.data as T?;
  }

  /// التحقق من وجود مفتاح
  bool has(String key) {
    if (!_enabled) {
      return false;
    }

    final entry = _cache[key];
    if (entry == null) {
      return false;
    }

    if (entry.isExpired) {
      _cache.remove(key);
      return false;
    }

    return true;
  }

  /// حذف عنصر من الذاكرة المؤقتة
  void remove(String key) {
    _cache.remove(key);
  }

  /// مسح جميع العناصر
  void clear() {
    _cache.clear();
    _hits = 0;
    _misses = 0;
  }

  /// مسح العناصر منتهية الصلاحية
  int clearExpired() {
    final expiredKeys = <String>[];

    for (final entry in _cache.entries) {
      if (entry.value.isExpired) {
        expiredKeys.add(entry.key);
      }
    }

    expiredKeys.forEach(_cache.remove);

    return expiredKeys.length;
  }

  /// مسح العناصر بناءً على نمط (pattern)
  int clearByPattern(String pattern) {
    final regex = RegExp(pattern);
    final keysToRemove = _cache.keys.where(regex.hasMatch).toList();

    keysToRemove.forEach(_cache.remove);

    return keysToRemove.length;
  }

  /// إزالة عناصر إذا تجاوزت الحد الأقصى
  void _evictIfNeeded() {
    while (_getTotalSize() > _maxSizeBytes && _cache.isNotEmpty) {
      // إزالة أقدم عنصر
      final oldestKey = _cache.entries
          .reduce(
            (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b,
          )
          .key;
      _cache.remove(oldestKey);
    }
  }

  /// الحصول على الحجم الكلي
  int _getTotalSize() {
    return _cache.values.fold<int>(0, (sum, entry) => sum + entry.sizeInBytes);
  }

  /// بدء التنظيف التلقائي
  void startCleanup({Duration interval = const Duration(minutes: 30)}) {
    _cleanupTimer?.cancel();
    _cleanupTimer = Timer.periodic(interval, (timer) {
      final removed = clearExpired();
      if (removed > 0 && kDebugMode) {
        debugPrint('🧹 Cache cleanup: removed $removed expired entries');
      }
    });
  }

  /// إيقاف التنظيف التلقائي
  void stopCleanup() {
    _cleanupTimer?.cancel();
    _cleanupTimer = null;
  }

  /// الحصول على الإحصائيات
  CacheStatistics getStatistics() {
    int validEntries = 0;
    int expiredEntries = 0;

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
      totalSizeBytes: _getTotalSize(),
      maxSizeBytes: _maxSizeBytes,
      hitRate: hitRate,
      hits: _hits,
      misses: _misses,
    );
  }

  /// إعادة تعيين الإحصائيات
  void resetStatistics() {
    _hits = 0;
    _misses = 0;
  }

  /// التخلص من الموارد
  void dispose() {
    stopCleanup();
    clear();
  }

  // مساعدات لمفاتيح الذاكرة المؤقتة
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
  static String devicesKey() => 'devices_all';
  static String syncLogsKey() => 'sync_logs_all';
}
