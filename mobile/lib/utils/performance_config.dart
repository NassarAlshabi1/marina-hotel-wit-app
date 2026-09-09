import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

// ✅ P2-1 (2026-09-09): appwrite_cache_manager.dart حُذف - Drift يتولى الآن caching
// import '../services/appwrite_cache_manager.dart';
import 'debug_log.dart';
import 'weak_device_optimizer.dart';

/// تهيئة تحسينات الأداء — تُستدعى في بداية `main()` قبل `runApp`.
void configurePerformance() {
  final optimizer = WeakDeviceOptimizer.instance;

  // image cache هو أكبر cache افتراضي في Flutter؛ نحده قبل إنشاء أول واجهة.
  PaintingBinding.instance.imageCache.maximumSize = optimizer.maxImageCacheSize;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      optimizer.maxImageCacheBytes;

  // ✅ P2-1 (2026-09-09): حُذفت إدارة cache الـ Appwrite
  // Drift ORM يتولى الآن جميع caching (WAL mode + mmap)
  // AppwriteCacheManager كان مستخدماً قديماً عندما كان Appwrite الخادم.
  // // final dataCache = AppwriteCacheManager.instance;
  // // dataCache.setMaxEntries(optimizer.maxCacheEntries);
  // // dataCache.setMaxSizeMB(optimizer.maxDataCacheSizeMB);

  if (Platform.isAndroid) {
    dlog(
      () =>
          'Performance profile L${optimizer.optimizationLevel}: image cache '
          '${optimizer.maxImageCacheSize} entries / '
          '${optimizer.maxImageCacheBytes ~/ (1024 * 1024)}MB, data cache '
          '${optimizer.maxCacheEntries} entries / '
          '${optimizer.maxDataCacheSizeMB}MB',
    );
  }
}

/// هل الجهاز ضمن ملف الأداء منخفض الموارد.
bool get isLowEndDevice => WeakDeviceOptimizer.instance.isWeakDevice;

/// مجال صغير لإنشاء العناصر خارج مجال العرض على الأجهزة الضعيفة.
/// القوائم تستخدمه بدلاً من Flutter الافتراضي لتفادي prefetch مفرط للـ Widgets.
double get optimizedCacheExtent => isLowEndDevice ? 160.0 : 500.0;

/// واجهة Flutter الحديثة لمجال إنشاء العناصر خارج الشاشة.
/// تُستخدم في ListView.builder وCustomScrollView بدلاً من cacheExtent المهجور.
ScrollCacheExtent get optimizedScrollCacheExtent =>
    ScrollCacheExtent.pixels(optimizedCacheExtent);
