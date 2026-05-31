import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';

enum PerformanceMode {
  low,      // للأجهزة الضعيفة (تعطيل الرسوم المتحركة، تقليل جودة الصور)
  balanced, // للأجهزة المتوسطة
  high      // للأجهزة القوية
}

class PerformanceOptimizer extends ChangeNotifier {
  static final PerformanceOptimizer _instance = PerformanceOptimizer._internal();
  factory PerformanceOptimizer() => _instance;
  PerformanceOptimizer._internal();

  PerformanceMode _currentMode = PerformanceMode.balanced;
  bool _isLowRamDevice = false;

  PerformanceMode get currentMode => _currentMode;
  bool get isLowRamDevice => _isLowRamDevice;

  // إعدادات محسنة للأجهزة الضعيفة
  bool get useAnimations => _currentMode != PerformanceMode.low;
  // تم تعطيل جودة الصور لأن التطبيق لا يستخدمها لضمان السرعة
  double get imageQuality => 0.0; 
  bool get useShadows => _currentMode != PerformanceMode.low;

  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final savedMode = prefs.getString('performance_mode');

    if (savedMode != null) {
      _currentMode = PerformanceMode.values.firstWhere(
        (e) => e.toString() == savedMode,
        orElse: () => PerformanceMode.balanced,
      );
    } else {
      // الكشف التلقائي عن مواصفات الجهاز
      await _autoDetectPerformance();
    }
    notifyListeners();
  }

  Future<void> _autoDetectPerformance() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      // تقدير بناءً على إصدار الأندرويد أو الذاكرة إذا كانت متاحة
      // في Flutter، لا يمكن الوصول المباشر للرام بدون plugin إضافي،
      // لكن يمكننا استخدام مؤشرات مثل إصدار SDK
      if (androidInfo.version.sdkInt < 28) { // Android 9 وما قبله
        _currentMode = PerformanceMode.low;
        _isLowRamDevice = true;
      } else {
        _currentMode = PerformanceMode.balanced;
      }
    } else if (Platform.isIOS) {
      final iosInfo = await DeviceInfoPlugin().iosInfo;
      if (iosInfo.model.contains('iPhone 6') || iosInfo.model.contains('iPhone 7')) {
        _currentMode = PerformanceMode.low;
      } else {
        _currentMode = PerformanceMode.balanced;
      }
    }
  }

  Future<void> setPerformanceMode(PerformanceMode mode) async {
    _currentMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('performance_mode', mode.toString());
    notifyListeners();
  }
}

/// ويدجت مساعد لتعطيل الرسوم المتحركة في الأجهزة الضعيفة
class AdaptiveAnimation extends StatelessWidget {
  final Widget child;
  final Widget Function(BuildContext, Widget) animationBuilder;

  const AdaptiveAnimation({
    super.key,
    required this.child,
    required this.animationBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final optimizer = PerformanceOptimizer();
    if (optimizer.useAnimations) {
      return animationBuilder(context, child);
    }
    return child;
  }
}
