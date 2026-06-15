/// ============================================================
/// Marina Hotel - Improved Layered Cache Service
/// ============================================================
/// 3-Tier Caching Strategy (مُحسّنة):
///   Tier 1: Memory (fastest, LRU Map)
///   Tier 2: Disk  (sqflite - persistent, يدعم كميات كبيرة)
///   Tier 3: Network (backing store)
/// ============================================================

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../local_db.dart';
import 'sqflite_cache_tier.dart';

class CacheEntry<T> {
  CacheEntry(this.value, this.timestamp, this.ttl);
  final T value;
  final DateTime timestamp;
  final Duration ttl;

  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

/// نسخة محسّنة من LayeredCacheService
/// - Tier 2 يستخدم sqflite بدلاً من SharedPreferences (يدعم بيانات أكبر)
/// - تنظيف تلقائي للإدخالات منتهية الصلاحية
/// - حد أقصى 50MB لذاكرة التخزين المؤقت على القرص
/// - LRU eviction لذاكرة التخزين المؤقت في الذاكرة
class ImprovedLayeredCacheService {
  ImprovedLayeredCacheService(AppDatabase db) : _diskCache = SqfliteCacheTier(db);

  final SqfliteCacheTier _diskCache;

  // ─── Tier 1: Memory Cache ───
  final Map<String, CacheEntry<Object?>> _memoryCache = {};
  static const int _maxMemoryEntries = 100;
  final _memoryAccessOrder = <String>[]; // LRU

  // ─── Public API ───

  /// Get cached or fetch
  Future<T> get<T>(
    String key,
    Future<T> Function() fetcher, {
    Duration? ttl,
    bool forceRefresh = false,
  }) async {
    // Check memory first
    if (!forceRefresh && _memoryCache.containsKey(key)) {
      final entry = _memoryCache[key]!;
      if (!entry.isExpired) {
        _updateLRU(key);
        return entry.value as T;
      } else {
        _memoryCache.remove(key);
      }
    }

    // Check disk (sqflite)
    if (!forceRefresh) {
      final diskValue = await _getFromDisk<T>(key);
      if (diskValue != null) {
        _memoryCache[key] = CacheEntry(diskValue, DateTime.now(), ttl ?? const Duration(minutes: 5));
        _updateLRU(key);
        return diskValue;
      }
    }

    // Fetch from network/DB
    final value = await fetcher();

    // Store in both tiers
    await _setToDisk(key, value, ttl: ttl);
    _memoryCache[key] = CacheEntry(value, DateTime.now(), ttl ?? const Duration(minutes: 5));
    _updateLRU(key);

    return value;
  }

  /// Set value directly
  Future<void> set<T>(
    String key,
    T value, {
    Duration? ttl,
  }) async {
    _memoryCache[key] = CacheEntry(value, DateTime.now(), ttl ?? const Duration(minutes: 5));
    _updateLRU(key);
    await _setToDisk(key, value, ttl: ttl);
  }

  /// Invalidate single key
  Future<void> invalidate(String key) async {
    _memoryCache.remove(key);
    await _diskCache.delete(key);
  }

  /// Clear all cache
  Future<void> clearAll() async {
    _memoryCache.clear();
    _memoryAccessOrder.clear();
    await _diskCache.clearAll();
  }

  /// تنظيف الإدخالات منتهية الصلاحية
  Future<int> cleanExpired() async {
    return await _diskCache.cleanExpired();
  }

  /// الحصول على إحصائيات
  Future<Map<String, dynamic>> getStats() async {
    final diskStats = await _diskCache.getStats();
    return {
      'memoryEntries': _memoryCache.length,
      'memoryMax': _maxMemoryEntries,
      'memoryKeys': _memoryCache.keys.toList(),
      ...diskStats,
    };
  }

  // ─── Private helpers ───

  void _updateLRU(String key) {
    _memoryAccessOrder.remove(key);
    _memoryAccessOrder.add(key);

    // Evict if over limit
    if (_memoryCache.length > _maxMemoryEntries) {
      final lruKey = _memoryAccessOrder.removeAt(0);
      _memoryCache.remove(lruKey);
    }
  }

  Future<T?> _getFromDisk<T>(String key) async {
    try {
      final json = await _diskCache.get(key);
      if (json == null) return null;

      // For simple types
      if (T == String) return json as T;
      if (T == int) return (int.tryParse(json) ?? 0) as T;
      if (T == double) return (double.tryParse(json) ?? 0.0) as T;
      if (T == bool) return (json == 'true') as T;

      // For objects (decode JSON)
      final map = jsonDecode(json) as Map<String, dynamic>;
      return map as T; // Cast based on actual type
    } catch (e) {
      return null;
    }
  }

  Future<void> _setToDisk<T>(String key, T value, {Duration? ttl}) async {
    try {
      String json;
      if (value is String || value is num || value is bool) {
        json = value.toString();
      } else {
        json = jsonEncode(value);
      }
      await _diskCache.set(key, json, ttl: ttl);
    } catch (e) {
      // Disk cache failure - continue without disk cache
    }
  }
}
