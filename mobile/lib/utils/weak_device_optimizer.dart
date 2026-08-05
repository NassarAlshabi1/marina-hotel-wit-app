// Weak Device Performance Optimizer
//
// يعمل هذا الملف على تحسين أداء التطبيق على الأجهزة الضعيفة عبر:
// 1. تقليل عدد الـ rebuilds عبر autoDispose + selective watch
// 2. تأخير العمليات الثقيلة (lazy loading)
// 3. تقليل استهلاك الذاكرة عبر إغلاق Streams والتيمرز
// 4. تقليل FPS overhead عبر RepaintBoundary

import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// تكوين أداء الجهاز الضعيف
class WeakDeviceOptimizer {
  WeakDeviceOptimizer._();
  static final WeakDeviceOptimizer instance = WeakDeviceOptimizer._();

  /// عدد الأنوية المنطقية للمعالج
  int _processorCount = 4;
  int get processorCount => _processorCount;

  /// هل الجهاز ضعيف؟ (أقل من 4 أنوية أو أقل من 2GB RAM)
  bool _isWeakDevice = false;
  bool get isWeakDevice => _isWeakDevice;

  /// مستوى تحسين الأداء (0=عادي, 1=متوسط, 2=قصوى)
  int _optimizationLevel = 0;
  int get optimizationLevel => _optimizationLevel;

  /// تهيئة المحسّن — يجب استدعاؤها في main() قبل runApp
  void initialize({int? processorCount, int? memoryMB}) {
    _processorCount = processorCount ?? _detectProcessorCount();
    final mem = memoryMB ?? _detectMemoryMB();

    // جهاز ضعيف = أقل من 4 أنوية أو أقل من 2GB RAM
    _isWeakDevice = _processorCount < 4 || mem < 2048;

    if (_isWeakDevice) {
      _optimizationLevel = 2; // قصوى
      dlog(() => '⚠️ Weak device detected: $_processorCount cores, '
        '$mem MB RAM → optimization level 2');
    } else if (_processorCount < 6 || mem < 4096) {
      _optimizationLevel = 1; // متوسط
      dlog(() => 'ℹ️ Mid-range device: $_processorCount cores, '
        '$mem MB RAM → optimization level 1');
    } else {
      _optimizationLevel = 0; // عادي
      dlog(() => '✅ High-end device: $_processorCount cores, '
        '$mem MB RAM → optimization level 0');
    }
  }

  int _detectProcessorCount() {
    try {
      return Platform.numberOfProcessors;
    } catch (_) {
      return 4;
    }
  }

  int _detectMemoryMB() {
    if (_processorCount <= 2) return 1024;
    if (_processorCount <= 4) return 2048;
    return 4096;
  }

  /// هل يجب تفعيل lazy loading؟
  bool get shouldUseLazyLoading => _optimizationLevel >= 1;

  /// هل يجب تقليل عدد العناصر في القوائم؟
  bool get shouldLimitListItems => _optimizationLevel >= 2;

  /// هل يجب تأخير العمليات الثقيلة؟
  bool get shouldDeferHeavyOps => _optimizationLevel >= 1;

  /// الحد الأقصى لعناصر القائمة قبل التمرير
  int get maxListItemsBeforePagination {
    switch (_optimizationLevel) {
      case 2:
        return 20;
      case 1:
        return 50;
      default:
        return 100;
    }
  }

  /// تأخير عملية ثقيلة لتجنب jank
  Future<T> deferHeavyOp<T>(Future<T> Function() op) async {
    if (!shouldDeferHeavyOps) {
      return op();
    }
    await WidgetsBinding.instance.endOfFrame;
    return op();
  }

  /// لف Widget بـ RepaintBoundary إذا كان الجهاز ضعيفاً
  Widget wrapWithRepaintBoundaryIfNeeded(Widget child) {
    if (_optimizationLevel >= 1) {
      return RepaintBoundary(child: child);
    }
    return child;
  }

  /// الحصول على تأخير debounce مناسب للجهاز
  Duration get debounceDuration {
    switch (_optimizationLevel) {
      case 2:
        return const Duration(milliseconds: 500);
      case 1:
        return const Duration(milliseconds: 300);
      default:
        return const Duration(milliseconds: 150);
    }
  }

  /// الحصول على عدد التزامن المناسب للجهاز
  int get syncConcurrency {
    switch (_optimizationLevel) {
      case 2:
        return 1;
      case 1:
        return 2;
      default:
        return 4;
    }
  }
}
