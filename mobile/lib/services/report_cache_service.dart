// lib/services/report_cache_service.dart

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// ⭐ خدمة التخزين المؤقت للتقارير
/// تحسين أداء التقارير عبر تخزين النتائج مؤقتاً
class ReportCacheService {
  ReportCacheService._();
  static final instance = ReportCacheService._();

  /// مدة صلاحية الـ cache بالدقائق
  static const int cacheValidityMinutes = 5;

  /// الذاكرة المؤقتة (in-memory cache)
  final Map<String, _CacheEntry> _memoryCache = {};

  /// مفتاح التخزين الدائم
  static const String _prefsKeyPrefix = 'report_cache_';

  /// ⭐ إنشاء مفتاح فريد للـ cache
  String _generateKey(String reportType, Map<String, dynamic> params) {
    final paramsStr = jsonEncode(params);
    final hash = paramsStr.hashCode.toString();
    return '${reportType}_$hash';
  }

  /// ⭐ الحصول على البيانات من الـ cache
  Future<T?> get<T>(
    String reportType,
    Map<String, dynamic> params,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final key = _generateKey(reportType, params);

    // 1. البحث في الذاكرة أولاً
    final memoryEntry = _memoryCache[key];
    if (memoryEntry != null && !memoryEntry.isExpired) {
      debugPrint('📦 Report cache HIT (memory): $reportType');
      return fromJson(memoryEntry.data);
    }

    // 2. البحث في التخزين الدائم
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_prefsKeyPrefix$key';
      final cachedStr = prefs.getString(cacheKey);

      if (cachedStr != null) {
        final cached = jsonDecode(cachedStr) as Map<String, dynamic>;
        final entry = _CacheEntry.fromJson(cached);

        if (!entry.isExpired) {
          // تخزين في الذاكرة للوصول السريع لاحقاً
          _memoryCache[key] = entry;
          debugPrint('📦 Report cache HIT (disk): $reportType');
          return fromJson(entry.data);
        } else {
          // حذف الـ cache المنتهي
          await prefs.remove(cacheKey);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Error reading cache: $e');
    }

    debugPrint('📦 Report cache MISS: $reportType');
    return null;
  }

  /// ⭐ تخزين البيانات في الـ cache
  Future<void> set<T>(
    String reportType,
    Map<String, dynamic> params,
    T data,
    Map<String, dynamic> Function(T) toJson,
  ) async {
    final key = _generateKey(reportType, params);
    final expiresAt = DateTime.now().add(
      const Duration(minutes: cacheValidityMinutes),
    );

    final entry = _CacheEntry(
      data: toJson(data),
      cachedAt: DateTime.now().millisecondsSinceEpoch,
      expiresAt: expiresAt.millisecondsSinceEpoch,
    );

    // 1. تخزين في الذاكرة
    _memoryCache[key] = entry;
    debugPrint('💾 Report cache SET (memory): $reportType');

    // 2. تخزين في التخزين الدائم
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheKey = '$_prefsKeyPrefix$key';
      await prefs.setString(cacheKey, jsonEncode(entry.toJson()));
      debugPrint('💾 Report cache SET (disk): $reportType');
    } catch (e) {
      debugPrint('⚠️ Error writing cache: $e');
    }
  }

  /// ⭐ مسح جميع الـ cache
  Future<void> clearAll() async {
    _memoryCache.clear();

    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_prefsKeyPrefix)) {
          await prefs.remove(key);
        }
      }
      debugPrint('🗑️ All report cache cleared');
    } catch (e) {
      debugPrint('⚠️ Error clearing cache: $e');
    }
  }

  /// ⭐ مسح cache منتهي الصلاحية
  Future<void> cleanExpired() async {
    final now = DateTime.now().millisecondsSinceEpoch;

    // تنظيف الذاكرة
    _memoryCache.removeWhere((key, entry) => entry.isExpired);

    // تنظيف التخزين الدائم
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith(_prefsKeyPrefix));

      for (final key in keys) {
        final cachedStr = prefs.getString(key);
        if (cachedStr != null) {
          final cached = jsonDecode(cachedStr) as Map<String, dynamic>;
          final expiresAt = cached['expiresAt'] as int;
          if (expiresAt < now) {
            await prefs.remove(key);
          }
        }
      }
      debugPrint('🧹 Expired cache cleaned');
    } catch (e) {
      debugPrint('⚠️ Error cleaning expired cache: $e');
    }
  }

  /// ⭐ إحصائيات الـ cache
  Map<String, dynamic> getStats() {
    final validEntries = _memoryCache.values.where((e) => !e.isExpired).length;

    return {
      'memory_entries': _memoryCache.length,
      'valid_entries': validEntries,
      'expired_entries': _memoryCache.length - validEntries,
    };
  }
}

/// ⭐ مدخل الـ cache
class _CacheEntry {
  _CacheEntry({
    required this.data,
    required this.cachedAt,
    required this.expiresAt,
  });

  factory _CacheEntry.fromJson(Map<String, dynamic> json) {
    return _CacheEntry(
      data: json['data'] as Map<String, dynamic>,
      cachedAt: json['cachedAt'] as int,
      expiresAt: json['expiresAt'] as int,
    );
  }

  final Map<String, dynamic> data;
  final int cachedAt;
  final int expiresAt;

  bool get isExpired => DateTime.now().millisecondsSinceEpoch > expiresAt;

  Map<String, dynamic> toJson() {
    return {
      'data': data,
      'cachedAt': cachedAt,
      'expiresAt': expiresAt,
    };
  }
}

/// ⭐ ثوابت أنواع التقارير
class ReportCacheKeys {
  static const String payments = 'payments_report';
  static const String expenses = 'expenses_report';
  static const String debts = 'debts_report';
  static const String incomeExpense = 'income_expense_report';
  static const String salaryWithdrawals = 'salary_withdrawals_report';
}
