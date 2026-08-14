import 'dart:io';

import 'package:flutter/painting.dart';

import '../services/appwrite_cache_manager.dart';
import 'debug_log.dart';
import 'weak_device_optimizer.dart';

/// تهيئة تحسينات الأداء — تُستدعى في بداية `main()` قبل `runApp`.
void configurePerformance() {
  final optimizer = WeakDeviceOptimizer.instance;

  // image cache هو أكبر cache افتراضي في Flutter؛ نحده قبل إنشاء أول واجهة.
  PaintingBinding.instance.imageCache.maximumSize = optimizer.maxImageCacheSize;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      optimizer.maxImageCacheBytes;

  // تطبيق الحدود نفسها على cache بيانات Appwrite. هذه القيم كانت موجودة في
  // WeakDeviceOptimizer ولكنها لم تكن موصولة بمسار التنفيذ.
  final dataCache = AppwriteCacheManager.instance;
  dataCache.setMaxEntries(optimizer.maxCacheEntries);
  dataCache.setMaxSizeMB(optimizer.maxDataCacheSizeMB);
  // الاستجابات البعيدة قصيرة العمر على الأجهزة الضعيفة؛ المصدر الدائم
  // للبيانات غير المتصلة هو Drift وليس Cache الذاكرة.
  dataCache.setDefaultTTL(
    optimizer.isWeakDevice
        ? const Duration(minutes: 2)
        : const Duration(minutes: 5),
  );
  // يزيل النتائج منتهية الصلاحية حتى إن لم يُعاد فتح الشاشة نفسها.
  dataCache.startCleanup(
    interval: optimizer.isWeakDevice
        ? const Duration(minutes: 5)
        : const Duration(minutes: 15),
  );

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

/// `cacheExtent` منخفض للحد من إنشاء widgets خارج حدود العرض.
double get optimizedCacheExtent => isLowEndDevice ? 160.0 : 500.0;
