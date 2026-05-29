/// ============================================================
/// Marina Hotel - Payment Cache Service
/// ============================================================
/// Specialized cache for payment operations with:
///   - In-memory cache for fast access
///   - LRU eviction policy
///   - Automatic invalidation on data changes
///   - Query result caching
/// ============================================================
library;

import 'dart:async';
import '../local_db.dart';
import '../../utils/time.dart';

/// Cache entry with metadata
class CachedPaymentEntry<T> {
  CachedPaymentEntry({
    required this.value,
    required this.timestamp,
    required this.ttl,
    this.hits = 0,
  });
  
  final T value;
  final DateTime timestamp;
  final Duration ttl;
  int hits;
  
  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
  
  CachedPaymentEntry<T> incrementHit() {
    return CachedPaymentEntry(
      value: value,
      timestamp: timestamp,
      ttl: ttl,
      hits: hits + 1,
    );
  }
  
  CachedPaymentEntry<T> withValue(T newValue) {
    return CachedPaymentEntry(
      value: newValue,
      timestamp: DateTime.now(),
      ttl: ttl,
      hits: 0,
    );
  }
}

/// Cache statistics
class PaymentCacheStats {
  const PaymentCacheStats({
    required this.totalEntries,
    required this.memoryUsage,
    required this.hitRate,
    required this.misses,
    required this.evictions,
  });
  
  final int totalEntries;
  final String memoryUsage;
  final double hitRate;
  final int misses;
  final int evictions;
  
  @override
  String toString() => 
    'CacheStats(entries: $totalEntries, memory: $memoryUsage, hitRate: ${(hitRate * 100).toStringAsFixed(1)}%)';
}

/// Payment-specific cache service
class PaymentCacheService {
  // ─── Singleton ───
  PaymentCacheService._();
  static final PaymentCacheService instance = PaymentCacheService._();
  
  // ─── Memory Cache ───
  final Map<String, CachedPaymentEntry<dynamic>> _cache = {};
  final List<String> _accessOrder = []; // LRU tracking
  static const int _maxEntries = 200;
  static const Duration _defaultTTL = Duration(minutes: 5);
  
  // ─── Statistics ───
  int _hits = 0;
  int _misses = 0;
  int _evictions = 0;
  final Map<String, int> _keyAccessCounts = {};
  
  // ─── Subscribers for invalidation ───
  final _invalidationCallbacks = <void Function(String)>[];
  
  // ─── Cache Keys ───
  static String _bookingPaymentsKey(int bookingId) => 'payments_booking_$bookingId';
  static String _bookingSummaryKey(int bookingId) => 'summary_booking_$bookingId';
  static String _dayPaymentsKey(String hotelDayKey) => 'payments_day_$hotelDayKey';
  static String _totalsKey(int bookingId) => 'totals_booking_$bookingId';
  static String _allPaymentsKey() => 'payments_all';
  
  // ─── Get cached payments for booking ───
  /// Get cached payments for a specific booking
  /// Returns null if not in cache or expired
  List<Payment>? getPaymentsForBooking(int bookingId) {
    final key = _bookingPaymentsKey(bookingId);
    return _get<List<Payment>>(key);
  }
  
  /// Cache payments for a booking
  void cachePaymentsForBooking(int bookingId, List<Payment> payments, {Duration? ttl}) {
    final key = _bookingPaymentsKey(bookingId);
    _set(key, payments, ttl: ttl ?? _defaultTTL);
  }
  
  /// Get cached booking summary
  /// Returns null if not in cache or expired
  Map<String, dynamic>? getBookingSummary(int bookingId) {
    final key = _bookingSummaryKey(bookingId);
    return _get<Map<String, dynamic>>(key);
  }
  
  /// Cache booking summary (total, paid, remaining)
  void cacheBookingSummary(
    int bookingId, {
    required double total,
    required double paid,
    required double remaining,
    required int paymentCount,
    Duration? ttl,
  }) {
    final key = _bookingSummaryKey(bookingId);
    _set(key, {
      'total': total,
      'paid': paid,
      'remaining': remaining,
      'paymentCount': paymentCount,
      'cachedAt': Time.nowIso(),
    }, ttl: ttl ?? const Duration(minutes: 2));
  }
  
  /// Get cached day totals
  double? getDayTotal(String hotelDayKey) {
    final key = _dayPaymentsKey(hotelDayKey);
    final data = _get<Map<String, dynamic>>(key);
    return data?['total'] as double?;
  }
  
  /// Cache day totals
  void cacheDayTotal(String hotelDayKey, double total, {Duration? ttl}) {
    final key = _dayPaymentsKey(hotelDayKey);
    _set(key, {
      'total': total,
      'cachedAt': Time.nowIso(),
    }, ttl: ttl ?? const Duration(minutes: 1));
  }
  
  /// Get cached totals for booking
  ({double total, double paid, double remaining})? getBookingTotals(int bookingId) {
    final key = _totalsKey(bookingId);
    final data = _get<Map<String, dynamic>>(key);
    if (data == null) return null;
    return (
      total: data['total'] as double,
      paid: data['paid'] as double,
      remaining: data['remaining'] as double,
    );
  }
  
  /// Cache booking totals
  void cacheBookingTotals(
    int bookingId, {
    required double total,
    required double paid,
    required double remaining,
    Duration? ttl,
  }) {
    final key = _totalsKey(bookingId);
    _set(key, {
      'total': total,
      'paid': paid,
      'remaining': remaining,
    }, ttl: ttl ?? _defaultTTL);
  }
  
  // ─── Generic Cache Operations ───
  
  T? _get<T>(String key) {
    final entry = _cache[key];
    if (entry == null) {
      _misses++;
      return null;
    }
    
    if (entry.isExpired) {
      _remove(key);
      _misses++;
      return null;
    }
    
    // Update LRU and hit count
    _hits++;
    _updateLRU(key);
    _keyAccessCounts[key] = (_keyAccessCounts[key] ?? 0) + 1;
    
    // Return incremented hit entry
    _cache[key] = entry.incrementHit();
    return entry.value as T;
  }
  
  void _set<T>(String key, T value, {Duration? ttl}) {
    // Remove if exists
    if (_cache.containsKey(key)) {
      _cache.remove(key);
      _accessOrder.remove(key);
    }
    
    // Add new entry
    _cache[key] = CachedPaymentEntry<T>(
      value: value,
      timestamp: DateTime.now(),
      ttl: ttl ?? _defaultTTL,
    );
    _accessOrder.add(key);
    
    // LRU eviction
    _evictIfNeeded();
  }
  
  void _remove(String key) {
    _cache.remove(key);
    _accessOrder.remove(key);
  }
  
  void _updateLRU(String key) {
    _accessOrder.remove(key);
    _accessOrder.add(key);
  }
  
  void _evictIfNeeded() {
    while (_cache.length > _maxEntries) {
      if (_accessOrder.isEmpty) break;
      
      final lruKey = _accessOrder.removeAt(0);
      if (_cache.containsKey(lruKey)) {
        _cache.remove(lruKey);
        _evictions++;
        _keyAccessCounts.remove(lruKey);
      }
    }
  }
  
  // ─── Invalidation ───
  
  /// Invalidate all cache for a booking
  void invalidateBooking(int bookingId) {
    final keysToRemove = _cache.keys
        .where((k) => k.contains('_$bookingId'))
        .toList();
    
    for (final key in keysToRemove) {
      _remove(key);
      _notifyInvalidation(key);
    }
  }
  
  /// Invalidate all payments cache
  void invalidateAllPayments() {
    final keysToRemove = _cache.keys
        .where((k) => k.startsWith('payments_') || k.startsWith('summary_') || k.startsWith('totals_'))
        .toList();
    
    for (final key in keysToRemove) {
      _remove(key);
      _notifyInvalidation(key);
    }
  }
  
  /// Invalidate day cache
  void invalidateDay(String hotelDayKey) {
    final key = _dayPaymentsKey(hotelDayKey);
    _remove(key);
    _notifyInvalidation(key);
  }
  
  /// Invalidate specific key
  void invalidate(String key) {
    _remove(key);
    _notifyInvalidation(key);
  }
  
  /// Register invalidation callback
  void registerInvalidationCallback(void Function(String) callback) {
    _invalidationCallbacks.add(callback);
  }
  
  void _notifyInvalidation(String key) {
    for (final callback in _invalidationCallbacks) {
      callback(key);
    }
  }
  
  /// Clear all cache
  void clearAll() {
    final keys = _cache.keys.toList();
    _cache.clear();
    _accessOrder.clear();
    _keyAccessCounts.clear();
    _hits = 0;
    _misses = 0;
    _evictions = 0;
    
    for (final key in keys) {
      _notifyInvalidation(key);
    }
  }
  
  // ─── Statistics ───
  
  /// Get cache statistics
  PaymentCacheStats getStats() {
    final totalAccesses = _hits + _misses;
    final hitRate = totalAccesses > 0 ? _hits / totalAccesses : 0.0;
    
    // Estimate memory usage
    int estimatedBytes = 0;
    for (final entry in _cache.values) {
      if (entry.value is List) {
        estimatedBytes += (entry.value as List).length * 200; // ~200 bytes per payment
      } else if (entry.value is Map) {
        estimatedBytes += 500; // ~500 bytes per map
      }
    }
    
    String memoryUsage;
    if (estimatedBytes < 1024) {
      memoryUsage = '$estimatedBytes B';
    } else if (estimatedBytes < 1024 * 1024) {
      memoryUsage = '${(estimatedBytes / 1024).toStringAsFixed(1)} KB';
    } else {
      memoryUsage = '${(estimatedBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    
    return PaymentCacheStats(
      totalEntries: _cache.length,
      memoryUsage: memoryUsage,
      hitRate: hitRate,
      misses: _misses,
      evictions: _evictions,
    );
  }
  
  /// Get most accessed keys
  List<MapEntry<String, int>> getTopAccessedKeys({int limit = 10}) {
    final sorted = _keyAccessCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }
  
  /// Print cache debug info
  void debugPrint() {
    final stats = getStats();
    print('📊 PaymentCache Stats: $stats');
    print('🔑 Top accessed keys:');
    for (final entry in getTopAccessedKeys()) {
      print('   - ${entry.key}: ${entry.value} accesses');
    }
  }
}

// ─── Payment Cache Extensions for Repository ───

extension PaymentCacheExtensions on PaymentCacheService {
  /// Wrap payment retrieval with cache check
  Future<List<Payment>> getPaymentsCached({
    required int bookingId,
    required Future<List<Payment>> Function() fetcher,
    Duration? ttl,
  }) async {
    // Try cache first
    final cached = getPaymentsForBooking(bookingId);
    if (cached != null) {
      return cached;
    }
    
    // Fetch from DB
    final payments = await fetcher();
    
    // Cache result
    cachePaymentsForBooking(bookingId, payments, ttl: ttl);
    
    return payments;
  }
  
  /// Wrap totals retrieval with cache check
  Future<({double total, double paid, double remaining})> getTotalsCached({
    required int bookingId,
    required Future<({double total, double paid, double remaining})> Function() fetcher,
    Duration? ttl,
  }) async {
    // Try cache first
    final cached = getBookingTotals(bookingId);
    if (cached != null) {
      return cached;
    }
    
    // Fetch from DB
    final totals = await fetcher();
    
    // Cache result
    cacheBookingTotals(
      bookingId,
      total: totals.total,
      paid: totals.paid,
      remaining: totals.remaining,
      ttl: ttl,
    );
    
    return totals;
  }
}