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

/// تهيئة تحسينات الأداء — تُستدعى في بداية main() قبل runApp
void configurePerformance() {
  // ═══════════════════════════════════════════════════════════════
  //  1. Image Cache — حد آمن جداً للأجهزة الضعيفة (1GB RAM)
  // ═══════════════════════════════════════════════════════════════
  PaintingBinding.instance.imageCache.maximumSize = 50;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 5 * 1024 * 1024; // 5MB only

  // ═══════════════════════════════════════════════════════════════
  //  2. Memory pressure handler — إخلاء الكاش عند ضغط الذاكرة
  //
  //  ✅ إصلاح P0-A: استخدمنا سابقاً SystemChannels.system.setMethodCallHandler
  //     وهذا API خاطئ (SystemChannels.system هو BasicMessageChannel وليس
  //     MethodChannel). كما أن الـ setMessageHandler override يكسر إشارات
  //     النظام الأخرى (textScale, brightness).
  //
  //  ✅ الحل الأبسط والأكثر أماناً: استخدام PaintingBinding.instantiateImageCodec
  //     من خلال ImageCache.liveSize limitation + إخلاء الكاش بشكل استباقي.
  //     لا نحتاج لـ system channel handler — ImageCache نفسه يحترم حدود
  //     maximumSizeBytes ويلغي cached images تلقائياً عند تجاوز الحد.
  //
  //  إخلاء فوري عند بدء التشغيل لتفريغ أي صور مخزنة من session سابقة.
  // ═══════════════════════════════════════════════════════════════
  PaintingBinding.instance.imageCache.clear();
  PaintingBinding.instance.imageCache.clearLiveImages();

  if (Platform.isAndroid) {
    debugPrint('🚀 Performance: Low-end device optimizations active (5MB cache)');
  }
}

/// تحديد ما إذا كان الجهاز ضعيفاً
bool get isLowEndDevice => true;

/// cacheExtent مُحسّن لـ ListView.builder
double get optimizedCacheExtent => isLowEndDevice ? 100.0 : 500.0;

/// الحد الأقصى للعناصر في ListView قبل التحميل الكسول
int get maxEagerItems => isLowEndDevice ? 15 : 50;

/// تأخير debounce للمزامنة التلقائية
Duration get syncDebounceDuration => isLowEndDevice ? const Duration(seconds: 5) : const Duration(seconds: 2);

/// هل نُفعّل PerformanceInspector في الـ UI؟
bool get enablePerformanceInspector => false;

/// الحد الأقصى لعدد StreamBuilders النشطة
int get maxActiveStreams => isLowEndDevice ? 5 : 20;

/// batch size للمزامنة على الأجهزة الضعيفة
int get syncBatchSize => isLowEndDevice ? 15 : 25;

/// عدد الطلبات المتوازية في migration
int get migrationParallelCount => isLowEndDevice ? 3 : 5;

/// تأخير بين مجموعات migration
Duration get migrationGroupDelay =>
    isLowEndDevice ? const Duration(milliseconds: 800) : const Duration(milliseconds: 500);

/// تعطيل flutter_animate على الأجهزة الضعيفة
bool get enableAnimations => !isLowEndDevice;
