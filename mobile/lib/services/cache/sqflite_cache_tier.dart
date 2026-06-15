/// ============================================================
/// Marina Hotel - Sqflite Cache Tier
/// ============================================================
/// Tier 2 Disk Cache using sqflite (raw SQL) instead of SharedPreferences
/// Supports: larger data, TTL-based eviction, size limits, indexing
/// No Drift code generation required - uses custom SQL
/// ============================================================
library;


import 'package:flutter/foundation.dart';

import '../local_db.dart';
import 'package:marina_hotel_mobile/utils/app_logger.dart';

/// مدير ذاكرة التخزين المؤقت على القرص باستخدام sqflite
class SqfliteCacheTier {
  SqfliteCacheTier(this.db);

  final AppDatabase db;

  static const int _maxCacheSize = 50 * 1024 * 1024; // 50 MB max
  static const Duration _defaultTtl = Duration(hours: 24);
  static bool _tableCreated = false;

  /// تهيئة الجدول (يُستدعى مرة واحدة)
  Future<void> ensureTable() async {
    if (_tableCreated) return;
    try {
      await db.customStatement('''
        CREATE TABLE IF NOT EXISTS cache_store (
          key TEXT PRIMARY KEY,
          value TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          expires_at INTEGER,
          size INTEGER NOT NULL DEFAULT 0
        )
      ''');
      await db.customStatement('''
        CREATE INDEX IF NOT EXISTS idx_cache_expires 
        ON cache_store (expires_at)
      ''');
      _tableCreated = true;
      AppLogger.info('✅ SqfliteCacheTier table initialized', tag: 'APP');
    } catch (e) {
      AppLogger.warning('⚠️ SqfliteCacheTier.ensureTable failed: $e', tag: 'APP');
    }
  }

  /// قراءة من ذاكرة التخزين المؤقت على القرص
  Future<String?> get(String key) async {
    try {
      await ensureTable();
      final result = await db.customSelect(
        'SELECT value, expires_at FROM cache_store WHERE key = ?',
        variables: [Variable<String>(key)],
      ).getSingleOrNull();

      if (result == null) return null;

      final expiresAt = result.read<int?>('expires_at');
      final now = DateTime.now().millisecondsSinceEpoch;

      // التحقق من انتهاء الصلاحية
      if (expiresAt != null && expiresAt < now) {
        await db.customUpdate(
          'DELETE FROM cache_store WHERE key = ?',
          variables: [Variable<String>(key)],
        );
        return null;
      }

      return result.read<String>('value');
    } catch (e) {
      AppLogger.warning('⚠️ SqfliteCacheTier.get($key) failed: $e', tag: 'APP');
      return null;
    }
  }

  /// كتابة في ذاكرة التخزين المؤقت على القرص
  Future<void> set(
    String key,
    String value, {
    Duration? ttl,
  }) async {
    try {
      await ensureTable();
      final now = DateTime.now().millisecondsSinceEpoch;
      final expiresAt = ttl != null
          ? now + ttl.inMilliseconds
          : now + _defaultTtl.inMilliseconds;
      final size = value.length;

      await db.customUpdate(
        'INSERT OR REPLACE INTO cache_store (key, value, created_at, expires_at, size) '
        'VALUES (?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(key),
          Variable<String>(value),
          Variable<int>(now),
          Variable<int>(expiresAt),
          Variable<int>(size),
        ],
      );

      // تنظيف إذا تجاوزنا الحد الأقصى
      await _enforceMaxSize();
    } catch (e) {
      AppLogger.warning('⚠️ SqfliteCacheTier.set($key) failed: $e', tag: 'APP');
    }
  }

  /// حذف مفتاح
  Future<void> delete(String key) async {
    try {
      await ensureTable();
      await db.customUpdate(
        'DELETE FROM cache_store WHERE key = ?',
        variables: [Variable<String>(key)],
      );
    } catch (e) {
      AppLogger.warning('⚠️ SqfliteCacheTier.delete($key) failed: $e', tag: 'APP');
    }
  }

  /// مسح جميع المفاتيح منتهية الصلاحية
  Future<int> cleanExpired() async {
    try {
      await ensureTable();
      final now = DateTime.now().millisecondsSinceEpoch;
      final result = await db.customUpdate(
        'DELETE FROM cache_store WHERE expires_at IS NOT NULL AND expires_at < ?',
        variables: [Variable<int>(now)],
      );
      return result;
    } catch (e) {
      AppLogger.warning('⚠️ SqfliteCacheTier.cleanExpired failed: $e', tag: 'APP');
      return 0;
    }
  }

  /// مسح جميع المفاتيح
  Future<void> clearAll() async {
    try {
      await ensureTable();
      await db.customUpdate('DELETE FROM cache_store');
    } catch (e) {
      AppLogger.warning('⚠️ SqfliteCacheTier.clearAll failed: $e', tag: 'APP');
    }
  }

  /// الحصول على إحصائيات
  Future<Map<String, dynamic>> getStats() async {
    try {
      await ensureTable();
      final totalCount = await db.customSelect(
        'SELECT COUNT(*) as cnt FROM cache_store',
      ).getSingle();
      final totalSize = await db.customSelect(
        'SELECT COALESCE(SUM(size), 0) as sz FROM cache_store',
      ).getSingle();
      final expiredCount = await db.customSelect(
        'SELECT COUNT(*) as cnt FROM cache_store WHERE expires_at < ?',
        variables: [Variable<int>(DateTime.now().millisecondsSinceEpoch)],
      ).getSingle();

      return {
        'totalEntries': totalCount.read<int>('cnt'),
        'totalSize': totalSize.read<int>('sz'),
        'expiredEntries': expiredCount.read<int>('cnt'),
      };
    } catch (e) {
      return {'error': e.toString()};
    }
  }

  /// فرض الحد الأقصى لحجم ذاكرة التخزين المؤقت
  Future<void> _enforceMaxSize() async {
    try {
      await ensureTable();
      final totalSize = (await db.customSelect(
        'SELECT COALESCE(SUM(size), 0) as sz FROM cache_store',
      ).getSingle()).read<int>('sz');

      if (totalSize <= _maxCacheSize) return;

      // حذف أقدم الإدخالات حتى نعود تحت الحد الأقصى
      await db.customUpdate('''
        DELETE FROM cache_store WHERE key IN (
          SELECT key FROM cache_store 
          ORDER BY created_at ASC 
          LIMIT MAX(1, (SELECT COUNT(*) FROM cache_store) - 1000)
        )
      ''');
    } catch (e) {
      AppLogger.warning('⚠️ SqfliteCacheTier._enforceMaxSize failed: $e', tag: 'APP');
    }
  }
}
