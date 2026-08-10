// lib/utils/performance_config.dart
//
// ✅ تحسينات الأداء للأجهزة الضعيفة (1-2GB RAM)
//
// المشاكل المُكتشفة:
// 1. لا يوجد حد لـ image cache — قد يستهلك 100MB+ على أجهزة ضعيفة
// 2. ListView() (eager) في 30 مكان — يُحمّل كل العناصر دفعة واحدة
// 3. 0 AutomaticKeepAliveClientMixin — التبويبات تُعاد بناؤها كاملاً
// 4. فقط 28 .select() vs 94 .watch() — إعادة بناء زائدة
// 5. 522 Column() — layout مكلف على المعالجات الضعيفة

import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/painting.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';
import 'package:marina_hotel_mobile/utils/weak_device_optimizer.dart';

/// تهيئة تحسينات الأداء — تُستدعى في بداية main() قبل runApp
void configurePerformance() {
  // ✅ Performance Fix (2026-08-10): استخدام WeakDeviceOptimizer الفعلي
  // بدلاً من قيم ثابتة. الآن image cache يُضبط حسب قوة الجهاز:
  // - أجهزة ضعيفة (level 2): 50 صورة / 5MB
  // - أجهزة متوسطة (level 1): 100 صورة / 10MB
  // - أجهزة قوية (level 0): 200 صورة / 20MB
  final optimizer = WeakDeviceOptimizer.instance;
  PaintingBinding.instance.imageCache.maximumSize = optimizer.maxImageCacheSize;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      optimizer.maxImageCacheBytes;

  if (Platform.isAndroid) {
    dlog(
      () => '🚀 Performance: Android — image cache limited to '
          '${optimizer.maxImageCacheSize} entries / '
          '${optimizer.maxImageCacheBytes ~/ (1024 * 1024)}MB',
    );
  }
}

/// ✅ Performance Fix: استخدام WeakDeviceOptimizer بدلاً من true ثابت
bool get isLowEndDevice => WeakDeviceOptimizer.instance.isWeakDevice;

/// cacheExtent مُحسّن لـ ListView.builder
double get optimizedCacheExtent =>
    isLowEndDevice ? 200.0 : 500.0;
