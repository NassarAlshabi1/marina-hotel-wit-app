/// ============================================================
/// Marina Hotel - Layered Cache Service
/// ============================================================
/// 3-Tier Caching Strategy:
///   Tier 1: Memory (fastest, limited size)
///   Tier 2: Disk  (persistent, sqflite)
///   Tier 3: Network (backing store)
/// ============================================================

import 'dart:collection';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../local_db.dart' as local_db;

class CacheEntry<T> {
  final T value;
  final DateTime timestamp;
  final Duration ttl;
  CacheEntry(this.value, this.timestamp, this.ttl);
  
  bool get isExpired => DateTime.now().difference(timestamp) > ttl;
}

class LayeredCacheService {
  // ─── Tier 1: Memory Cache ───
  static final Map<String, CacheEntry<dynamic>> _memoryCache = {};
  static const int _maxMemoryEntries = 100;
  static final _memoryAccessOrder = <String>[]; // LRU
  
  // ─── Tier 2: Disk Cache (SharedPreferences) ───
  static Future<SharedPreferences> get _prefs async {
    return await SharedPreferences.getInstance();
  }
  
  // ─── Public API ───
  
  /// Get cached or fetch
  static Future<T> get<T>(
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
    
    // Check disk
    if (!forceRefresh) {
      final diskValue = await _getFromDisk<T>(key);
      if (diskValue != null) {
        _memoryCache[key] = CacheEntry(diskValue, DateTime.now(), ttl ?? Duration(minutes: 5));
        _updateLRU(key);
        return diskValue;
      }
    }
    
    // Fetch from network/DB
    final value = await fetcher();
    
    // Store in both tiers
    await _setToDisk(key, value);
    _memoryCache[key] = CacheEntry(value, DateTime.now(), ttl ?? Duration(minutes: 5));
    _updateLRU(key);
    
    return value;
  }
  
  /// Set value directly
  static Future<void> set<T>(
    String key,
    T value, {
    Duration? ttl,
  }) async {
    _memoryCache[key] = CacheEntry(value, DateTime.now(), ttl ?? Duration(minutes: 5));
    _updateLRU(key);
    await _setToDisk(key, value);
  }
  
  /// Invalidate single key
  static void invalidate(String key) {
    _memoryCache.remove(key);
    _removeFromDisk(key);
  }
  
  /// Clear all cache
  static Future<void> clearAll() async {
    _memoryCache.clear();
    _memoryAccessOrder.clear();
    final prefs = await _prefs;
    await prefs.remove('cache_v1');
  }
  
  // ─── Private helpers ───
  
  static void _updateLRU(String key) {
    _memoryAccessOrder.remove(key);
    _memoryAccessOrder.add(key);
    
    // Evict if over limit
    if (_memoryCache.length > _maxMemoryEntries) {
      final lruKey = _memoryAccessOrder.removeAt(0);
      _memoryCache.remove(lruKey);
    }
  }
  
  static Future<T?> _getFromDisk<T>(String key) async {
    try {
      final prefs = await _prefs;
      final json = prefs.getString('cache_v1_$key');
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
  
  static Future<void> _setToDisk<T>(String key, T value) async {
    try {
      final prefs = await _prefs;
      String json;
      
      if (value is String || value is num || value is bool) {
        json = value.toString();
      } else {
        json = jsonEncode(value);
      }
      
      await prefs.setString('cache_v1_$key', json);
    } catch (e) {
      // Disk cache failure - continue without disk cache
    }
  }
  
  static Future<void> _removeFromDisk(String key) async {
    final prefs = await _prefs;
    await prefs.remove('cache_v1_$key');
  }
  
  /// Get statistics
  static Map<String, dynamic> getStats() {
    return {
      'memoryEntries': _memoryCache.length,
      'memoryMax': _maxMemoryEntries,
      'keys': _memoryCache.keys.toList(),
    };
  }
}

/// Extension for paginated cache
extension PaginatedCache on LayeredCacheService {
  /// Cache paginated results
  static Future<List<T>> getPaginated<T>(
    String baseKey,
    Future<List<T>> Function(int page) fetcher, {
    int pageSize = 50,
    Duration? ttl,
  }) async {
    final pageKey = '${baseKey}_page_1'; // Simplifed to first page
    return await get<List<T>>(
      pageKey,
      () => fetcher(1),
      ttl: ttl ?? Duration(minutes: 2),
    );
  }
}
