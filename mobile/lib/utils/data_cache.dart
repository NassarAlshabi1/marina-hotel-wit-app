import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple in-memory cache with TTL support for reports and data
class DataCache {
  factory DataCache() => _instance;
  DataCache._internal();
  static final DataCache _instance = DataCache._internal();

  final Map<String, _CacheItem> _cache = {};
  static const _defaultTTL = Duration(minutes: 5);

  /// Get cached data if not expired
  T? get<T>(String key) {
    final item = _cache[key];
    if (item == null) return null;

    if (item.isExpired) {
      _cache.remove(key);
      return null;
    }
    return item.value as T?;
  }

  /// Set cached data with optional TTL
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    _cache[key] = _CacheItem(
      value: value,
      expiresAt: DateTime.now().add(ttl ?? _defaultTTL),
    );
  }

  /// Check if key exists and is valid
  bool hasValid(String key) {
    final item = _cache[key];
    if (item == null) return false;
    if (item.isExpired) {
      _cache.remove(key);
      return false;
    }
    return true;
  }

  /// Remove specific key
  void remove(String key) {
    _cache.remove(key);
  }

  /// Clear all cache
  void clear() {
    _cache.clear();
  }

  /// Get or fetch pattern - simple cache-aside
  Future<T> getOrFetch<T>(
    String key,
    Future<T> Function() fetcher, {
    Duration? ttl,
  }) async {
    final cached = get<T>(key);
    if (cached != null) return cached;

    final fresh = await fetcher();
    await set(key, fresh, ttl: ttl);
    return fresh;
  }
}

class _CacheItem {
  _CacheItem({required this.value, required this.expiresAt});

  final dynamic value;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Persisted cache using SharedPreferences (for larger data)
class PersistedCache {
  factory PersistedCache() => _instance;
  PersistedCache._internal();
  static final PersistedCache _instance = PersistedCache._internal();

  static const _prefix = 'cache_';
  static const _ttlPrefix = 'cache_ttl_';

  /// Get persisted data
  Future<T?> get<T>(String key) async {
    final prefs = await SharedPreferences.getInstance();
    final dataStr = prefs.getString('$_prefix$key');
    final ttl = prefs.getInt('$_ttlPrefix$key');

    if (dataStr == null) return null;
    if (ttl != null && DateTime.now().millisecondsSinceEpoch > ttl) {
      await prefs.remove('$_prefix$key');
      await prefs.remove('$_ttlPrefix$key');
      return null;
    }

    try {
      return jsonDecode(dataStr) as T;
    } catch (e) {
      return null;
    }
  }

  /// Set persisted data with TTL
  Future<void> set<T>(String key, T value, {Duration? ttl}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('$_prefix$key', jsonEncode(value));
    if (ttl != null) {
      final ttlMs = DateTime.now().add(ttl).millisecondsSinceEpoch;
      await prefs.setInt('$_ttlPrefix$key', ttlMs);
    }
  }

  /// Remove key
  Future<void> remove(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('$_prefix$key');
    await prefs.remove('$_ttlPrefix$key');
  }
}
