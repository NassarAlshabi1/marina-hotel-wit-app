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
  // الحد الجديد: 200 صورة / 20MB — كافٍ لـ UI بدون OOM
  PaintingBinding.instance.imageCache.maximumSize = 200;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 20 * 1024 * 1024; // 20MB

  // ═══════════════════════════════════════════════════════════════
  //  2. تخفيض viewport cache للـ ListView على الأجهزة الضعيفة
  // ═══════════════════════════════════════════════════════════════
  // cacheExtent الافتراضي: 250px — معقول، لكن نتحكم به عبر ScrollView
  // لا نُغيّره هنا بل نُمرره في ListView.builder عبر addAutomaticKeepAlives

  // ═══════════════════════════════════════════════════════════════
  //  3. Android: garbage collection أكثر عدوانية لتقليل الذاكرة
  // ═══════════════════════════════════════════════════════════════
  if (Platform.isAndroid) {
    // لا يوجد API مباشر، لكن تقليل image cache يُساعد
    debugPrint('🚀 Performance: Android — image cache limited to 20MB');
  }
}

/// تحديد ما إذا كان الجهاز ضعيفاً (يمكن توسيعه بـ device_info_plus)
/// للأجهزة بـ RAM < 3GB، نُطبّق تحسينات إضافية
bool get isLowEndDevice {
  // مؤقتاً: نفترض أن الجهاز ضعيف ونُطبّق التحسينات دائماً
  // مستقبلاً: استخدم device_info_plus لقراءة RAM الفعلي
  return true;
}

/// cacheExtent مُحسّن لـ ListView.builder
/// الأجهزة الضعيفة: 200px (أقل = ذاككة أقل = scroll أقل سلاسة)
/// الأجهزة القوية: 500px (أكثر = scroll أنعم = ذاكرة أكثر)
double get optimizedCacheExtent => isLowEndDevice ? 200.0 : 500.0;
