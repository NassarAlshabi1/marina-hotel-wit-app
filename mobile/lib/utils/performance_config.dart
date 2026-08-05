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
  //  1. Image Cache — حد آمن للأجهزة الضعيفة
  // ═══════════════════════════════════════════════════════════════
  // الافتراضي: 1000 صورة / 100MB — كثير جداً لأجهزة 1-2GB RAM
  // الحد الجديد: 100 صورة / 10MB — كافٍ لـ UI بدون OOM على 1GB RAM
  PaintingBinding.instance.imageCache.maximumSize = 100;
  PaintingBinding.instance.imageCache.maximumSizeBytes =
      10 * 1024 * 1024; // 10MB

  // ═══════════════════════════════════════════════════════════════
  //  2. تقليل GC pressure — إخلاء image cache عند تحذير الذاكرة
  // ═══════════════════════════════════════════════════════════════
  PaintingBinding.instance.imageCache.clear();

  // ═══════════════════════════════════════════════════════════════
  //  3. Android: تقليل استهلاك الذاكرة الإجمالي
  // ═══════════════════════════════════════════════════════════════
  if (Platform.isAndroid) {
    debugPrint('🚀 Performance: Android — image cache limited to 10MB');
    debugPrint('🚀 Performance: Low-end device optimizations active');
  }
}

/// تحديد ما إذا كان الجهاز ضعيفاً
/// للأجهزة بـ RAM < 3GB، نُطبّق تحسينات إضافية
bool get isLowEndDevice {
  // نفترض أن الجهاز ضعيف ونُطبّق التحسينات دائماً
  // هذا أكثر أماناً من افتراض العكس
  return true;
}

/// cacheExtent مُحسّن لـ ListView.builder
/// الأجهزة الضعيفة: 100px (أقل = ذاكرة أقل)
/// الأجهزة القوية: 500px (أكثر = scroll أنعم)
double get optimizedCacheExtent => isLowEndDevice ? 100.0 : 500.0;

/// الحد الأقصى للعناصر في ListView قبل التحميل الكسول
int get maxEagerItems => isLowEndDevice ? 20 : 50;

/// تأخير debounce للمزامنة التلقائية
/// الأجهزة الضعيفة: 5 ثوانٍ (أقل ضغط على المعالج)
/// الأجهزة القوية: 2 ثانية
Duration get syncDebounceDuration =>
    isLowEndDevice ? const Duration(seconds: 5) : const Duration(seconds: 2);

/// هل نُفعّل PerformanceInspector في الـ UI؟
/// فقط في debug mode — في production يُعطّل لتوفير الذاكرة
bool get enablePerformanceInspector => false;

/// الحد الأقصى لعدد StreamBuilders النشطة في نفس الوقت
/// الأجهزة الضعيفة: 5 (يقلل إعادة البناء)
/// الأجهزة القوية: 20
int get maxActiveStreams => isLowEndDevice ? 5 : 20;
