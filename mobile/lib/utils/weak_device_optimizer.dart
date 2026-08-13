//
// ✅ Low-RAM profile for Android devices, including 1GB RAM devices.
//
// The profile is intentionally conservative: when Android cannot expose the
// physical RAM, the fallback prefers protecting responsiveness over aggressive
// background work.

import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:marina_hotel_mobile/utils/debug_log.dart';

/// تكوين أداء الجهاز الضعيف.
///
/// المستوى 3 مخصص لأجهزة 1GB وما حولها. المستوى 2 للأجهزة الضعيفة، والمستوى
/// 1 للأجهزة المتوسطة. يجب استدعاء [initialize] قبل إنشاء قاعدة البيانات أو
/// أي خدمة مزامنة حتى تُطبّق الحدود منذ البداية.
class WeakDeviceOptimizer {
  WeakDeviceOptimizer._();
  static final WeakDeviceOptimizer instance = WeakDeviceOptimizer._();

  static const MethodChannel _memoryChannel = MethodChannel(
    'com.aden.marina/device_memory',
  );
  static const int _bytesPerMb = 1024 * 1024;

  int _processorCount = 4;
  int get processorCount => _processorCount;

  /// RAM الفعلي بالـ MB. القيمة 0 تعني أن القياس لم يكتمل بعد.
  int _memoryMB = 0;
  int get memoryMB => _memoryMB;

  bool _isWeakDevice = false;
  bool get isWeakDevice => _isWeakDevice;

  /// 3 = شديد الضعف (≈1GB)، 2 = ضعيف، 1 = متوسط، 0 = قوي.
  int _optimizationLevel = 0;
  int get optimizationLevel => _optimizationLevel;
  bool get isCriticalLowMemoryDevice => _optimizationLevel >= 3;

  /// تهيئة المحسّن — تُستدعى في `main()` قبل `runApp()`.
  Future<void> initialize({int? processorCount, int? memoryMB}) async {
    _processorCount = processorCount ?? _detectProcessorCount();
    _memoryMB = memoryMB ?? await _detectMemoryMB();
    _optimizationLevel = _resolveOptimizationLevel(
      memoryMB: _memoryMB,
      processorCount: _processorCount,
    );
    _isWeakDevice = _optimizationLevel >= 2;

    dlog(
      () =>
          'Device profile: $_processorCount cores, $_memoryMB MB RAM '
          '→ optimization level $_optimizationLevel',
    );
  }

  int _detectProcessorCount() {
    try {
      return Platform.numberOfProcessors;
    } catch (_) {
      return 4;
    }
  }

  /// يقرأ RAM من `ActivityManager.MemoryInfo.totalMem` عبر جسر Android.
  ///
  /// لا يعرّض `device_info_plus` حجم RAM الفعلي بشكل ثابت على كل إصداراته،
  /// لذلك لا يعتمد التطبيق على عدد الأنوية إلا عند فشل القناة الأصلية.
  Future<int> _detectMemoryMB() async {
    if (Platform.isAndroid) {
      try {
        final totalBytes = await _memoryChannel.invokeMethod<int>(
          'getTotalMemoryBytes',
        );
        if (totalBytes != null && totalBytes > 0) {
          return totalBytes ~/ _bytesPerMb;
        }
      } on PlatformException catch (error) {
        dlog(() => 'Native RAM probe unavailable: ${error.code}');
      } catch (error) {
        dlog(() => 'Native RAM probe failed: $error');
      }
      return _conservativeAndroidFallback(_processorCount);
    }

    // Android هو المنصة المستهدفة لملف Low-RAM. نحافظ على fallback معقول
    // لباقي المنصات حتى تظل الاختبارات المحلية قابلة للتنبؤ.
    if (_processorCount <= 2) return 1024;
    if (_processorCount <= 4) return 2048;
    return 4096;
  }

  int _conservativeAndroidFallback(int processors) {
    // قد تكون أجهزة 1GB رباعية النوى شائعة؛ لا نفترض 2GB بناءً على الأنوية.
    if (processors <= 2) return 1024;
    if (processors <= 4) return 1536;
    if (processors <= 6) return 2048;
    return 3072;
  }

  int _resolveOptimizationLevel({
    required int memoryMB,
    required int processorCount,
  }) {
    if (memoryMB <= 1536 || processorCount <= 2) {
      return 3;
    }
    if (memoryMB < 3072 || processorCount < 4) {
      return 2;
    }
    if (memoryMB < 4096 || processorCount < 6) {
      return 1;
    }
    return 0;
  }

  bool get shouldUseLazyLoading => _optimizationLevel >= 1;
  bool get shouldLimitListItems => _optimizationLevel >= 2;
  bool get shouldDeferHeavyOps => _optimizationLevel >= 1;

  /// حجم دفعة المزامنة؛ يجب أن يستهلكه منسق المزامنة عند تنفيذ I/O.
  int get syncBatchSize {
    switch (_optimizationLevel) {
      case 3:
        return 10;
      case 2:
        return 20;
      case 1:
        return 50;
      default:
        return 100;
    }
  }

  /// الحد الأقصى لإدخالات cache البيانات داخل الذاكرة.
  int get maxCacheEntries {
    switch (_optimizationLevel) {
      case 3:
        return 30;
      case 2:
        return 50;
      case 1:
        return 100;
      default:
        return 500;
    }
  }

  /// حد ذاكرة cache البيانات بالميجابايت.
  int get maxDataCacheSizeMB {
    switch (_optimizationLevel) {
      case 3:
        return 2;
      case 2:
        return 4;
      case 1:
        return 10;
      default:
        return 20;
    }
  }

  /// حد عناصر image cache.
  int get maxImageCacheSize {
    switch (_optimizationLevel) {
      case 3:
        return 30;
      case 2:
        return 50;
      case 1:
        return 100;
      default:
        return 200;
    }
  }

  /// حد image cache بالبايت.
  int get maxImageCacheBytes {
    switch (_optimizationLevel) {
      case 3:
        return 3 * _bytesPerMb;
      case 2:
        return 5 * _bytesPerMb;
      case 1:
        return 10 * _bytesPerMb;
      default:
        return 20 * _bytesPerMb;
    }
  }

  /// حجم الصفحة الافتراضي للقوائم المحمّلة من SQLite.
  int get maxListItemsBeforePagination {
    switch (_optimizationLevel) {
      case 3:
        return 15;
      case 2:
        return 20;
      case 1:
        return 50;
      default:
        return 100;
    }
  }

  Future<T> deferHeavyOp<T>(Future<T> Function() op) async {
    if (!shouldDeferHeavyOps) {
      return op();
    }
    await WidgetsBinding.instance.endOfFrame;
    return op();
  }

  Widget wrapWithRepaintBoundaryIfNeeded(Widget child) {
    if (_optimizationLevel >= 1) {
      return RepaintBoundary(child: child);
    }
    return child;
  }

  Duration get debounceDuration {
    switch (_optimizationLevel) {
      case 3:
        return const Duration(milliseconds: 700);
      case 2:
        return const Duration(milliseconds: 500);
      case 1:
        return const Duration(milliseconds: 300);
      default:
        return const Duration(milliseconds: 150);
    }
  }

  int get syncConcurrency {
    switch (_optimizationLevel) {
      case 3:
      case 2:
        return 1;
      case 1:
        return 2;
      default:
        return 4;
    }
  }
}
