import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../utils/debug_log.dart';

/// Offline cache for API responses with TTL (time-to-live) support.
///
/// استخدام: عندما تفشل API calls بسبب network issues، نستخدم نسخة
/// مخزنة من آخر response ناجح (إن كانت موجودة). هذا يسمح بـ graceful
/// degradation بدل عرض blank screens.
///
/// السياق: في الشبكات غير المستقرة، قد تتطلب عدة محاولات قبل الاتصال.
/// الـ cache يسمح بـ continue working بـ stale data أثناء حل المشكلة.
class OfflineCache {
  static const String _cachePrefix = 'offline_cache:';
  static const String _ttlPrefix = 'offline_cache_ttl:';

  /// TTL افتراضي: 24 ساعة
  static const Duration defaultTTL = Duration(hours: 24);

  /// احفظ response في cache مع TTL.
  static Future<void> save({
    required String key,
    required dynamic data,
    Duration ttl = defaultTTL,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = jsonEncode(data);
      final expiresAt = DateTime.now().add(ttl).millisecondsSinceEpoch;

      await Future.wait([
        prefs.setString('$_cachePrefix$key', json),
        prefs.setInt('$_ttlPrefix$key', expiresAt),
      ]);

      dlog(() =>
          '💾 OfflineCache: Saved $key (TTL: ${ttl.inHours}h, expires at $expiresAt)');
    } catch (e) {
      derr(() => '❌ OfflineCache save failed for $key: $e');
    }
  }

  /// استرجع من cache إن كان صحيحاً (لم ينتهِ).
  static Future<T?> get<T>({
    required String key,
    T? Function(dynamic)? parser,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('$_cachePrefix$key');
      final expiresAt = prefs.getInt('$_ttlPrefix$key');

      if (json == null || expiresAt == null) {
        return null;
      }

      // تحقق TTL
      if (DateTime.now().millisecondsSinceEpoch > expiresAt) {
        dlog(() => '⏰ OfflineCache: $key expired — removing');
        await Future.wait([
          prefs.remove('$_cachePrefix$key'),
          prefs.remove('$_ttlPrefix$key'),
        ]);
        return null;
      }

      final data = jsonDecode(json);
      final result = parser != null ? parser(data) : data as T;

      dlog(() => '✅ OfflineCache: Hit for $key');
      return result;
    } catch (e) {
      derr(() => '❌ OfflineCache get failed for $key: $e');
      return null;
    }
  }

  /// حذف entry محدد.
  static Future<void> delete(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await Future.wait([
        prefs.remove('$_cachePrefix$key'),
        prefs.remove('$_ttlPrefix$key'),
      ]);
      dlog(() => '🗑️ OfflineCache: Deleted $key');
    } catch (e) {
      derr(() => '❌ OfflineCache delete failed for $key: $e');
    }
  }

  /// حذف كل الـ cache.
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      final cacheKeys = keys
          .where(
            (k) =>
                k.startsWith(_cachePrefix) || k.startsWith(_ttlPrefix),
          )
          .toList();

      await Future.wait(
        cacheKeys.map((k) => prefs.remove(k)),
      );

      dlog(() => '🗑️ OfflineCache: Cleared ${cacheKeys.length} entries');
    } catch (e) {
      derr(() => '❌ OfflineCache clear failed: $e');
    }
  }

  /// دالة مساعدة: احفظ وأرجع، أو احصل من cache عند الفشل.
  ///
  /// Example:
  /// ```dart
  /// final users = await OfflineCache.getOrFetch(
  ///   key: 'users_list',
  ///   fetcher: () => api.getUsers(),
  ///   parser: (json) => UserList.fromJson(json),
  /// );
  /// ```
  static Future<T?> getOrFetch<T>({
    required String key,
    required Future<dynamic> Function() fetcher,
    required T Function(dynamic) parser,
    Duration ttl = defaultTTL,
  }) async {
    try {
      // حاول fetch
      final data = await fetcher.call();
      final result = parser(data);

      // احفظ نسخة ناجحة
      await save(key: key, data: data, ttl: ttl);

      dlog(() => '🔄 OfflineCache: Fetched & cached $key');
      return result;
    } catch (e) {
      // فشل — حاول cache
      derr(() => '⚠️ Fetch failed for $key: $e — trying cache');

      final cached = await get<T>(key: key, parser: parser);
      if (cached != null) {
        dwarn(() => '💾 OfflineCache: Using stale data for $key');
        return cached;
      }

      // لا cache ولا fetch
      rethrow;
    }
  }
}
