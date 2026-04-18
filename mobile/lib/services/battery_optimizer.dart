// lib/services/battery_optimizer.dart
// خدمة تحسين استهلاك البطارية
// battery_optimizer.dart - تحسين استهلاك البطارية للمزامنة

import 'dart:async';
import 'dart:developer' as developer;
import 'package:battery_plus/battery_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';

/// مستويات توفير البطارية
enum BatteryOptimizationLevel {
  none,       // لا تحسين - المزامنة العادية
  light,      // تحسين خفيف - تقليل التردد
  moderate,   // تحسين متوسط - المزامنة عند الشحن فقط
  aggressive, // تحسين عالي - إيقاف المزامنة التلقائية
}

/// إعدادات المزامنة بناءً على مستوى البطارية
class BatterySyncSettings {
  final Duration syncInterval;
  final int batchSize;
  final bool syncOnBattery;
  final int minBatteryPercentage;
  final bool reduceAnimations;
  final bool compressData;

  const BatterySyncSettings({
    required this.syncInterval,
    required this.batchSize,
    required this.syncOnBattery,
    required this.minBatteryPercentage,
    required this.reduceAnimations,
    required this.compressData,
  });

  static const BatterySyncSettings none = BatterySyncSettings(
    syncInterval: Duration(minutes: 5),
    batchSize: 100,
    syncOnBattery: true,
    minBatteryPercentage: 10,
    reduceAnimations: false,
    compressData: false,
  );

  static const BatterySyncSettings light = BatterySyncSettings(
    syncInterval: Duration(minutes: 15),
    batchSize: 50,
    syncOnBattery: true,
    minBatteryPercentage: 20,
    reduceAnimations: true,
    compressData: true,
  );

  static const BatterySyncSettings moderate = BatterySyncSettings(
    syncInterval: Duration(minutes: 30),
    batchSize: 25,
    syncOnBattery: false,
    minBatteryPercentage: 30,
    reduceAnimations: true,
    compressData: true,
  );

  static const BatterySyncSettings aggressive = BatterySyncSettings(
    syncInterval: Duration(hours: 1),
    batchSize: 10,
    syncOnBattery: false,
    minBatteryPercentage: 50,
    reduceAnimations: true,
    compressData: true,
  );

  factory BatterySyncSettings.fromLevel(BatteryOptimizationLevel level) {
    switch (level) {
      case BatteryOptimizationLevel.none:
        return none;
      case BatteryOptimizationLevel.light:
        return light;
      case BatteryOptimizationLevel.moderate:
        return moderate;
      case BatteryOptimizationLevel.aggressive:
        return aggressive;
    }
  }
}

/// خدمة تحسين استهلاك البطارية
class BatteryOptimizer extends ChangeNotifier {
  static final BatteryOptimizer _instance = BatteryOptimizer._internal();
  factory BatteryOptimizer() => _instance;
  BatteryOptimizer._internal();

  final Battery _battery = Battery();
  final Connectivity _connectivity = Connectivity();

  BatteryState _batteryState = BatteryState.unknown;
  int _batteryLevel = 100;
  List<ConnectivityResult> _connectionState = [ConnectivityResult.none];
  BatteryOptimizationLevel _optimizationLevel = BatteryOptimizationLevel.light;
  bool _isMonitoring = false;
  bool _isCharging = false;
  StreamSubscription<BatteryState>? _batterySubscription;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;

  // Getters
  BatteryState get batteryState => _batteryState;
  int get batteryLevel => _batteryLevel;
  List<ConnectivityResult> get connectionState => _connectionState;
  BatteryOptimizationLevel get optimizationLevel => _optimizationLevel;
  bool get isCharging => _isCharging;
  bool get shouldSync => _shouldSync();
  BatterySyncSettings get syncSettings => BatterySyncSettings.fromLevel(_optimizationLevel);

  /// تهيئة الخدمة
  Future<void> initialize() async {
    try {
      // قراءة حالة البطارية الأولية
      _batteryLevel = await _battery.batteryLevel;
      _batteryState = await _battery.batteryState;
      _isCharging = _batteryState == BatteryState.charging;

      // قراءة حالة الاتصال
      _connectionState = await _connectivity.checkConnectivity();

      // بدء المراقبة
      await startMonitoring();

      developer.log(
        '🔋 BatteryOptimizer initialized: $_batteryLevel% ($_batteryState)',
        name: 'BatteryOptimizer',
      );
    } catch (e) {
      developer.log('⚠️ BatteryOptimizer init error: $e', name: 'BatteryOptimizer');
    }
  }

  /// بدء مراقبة البطارية والاتصال
  Future<void> startMonitoring() async {
    if (_isMonitoring) return;

    _isMonitoring = true;

    // مراقبة حالة البطارية
    _batterySubscription = _battery.onBatteryStateChanged.listen((state) {
      _batteryState = state;
      _isCharging = state == BatteryState.charging;
      _updateOptimizationLevel();
      notifyListeners();

      developer.log(
        '🔋 Battery state changed: $state (Level: $_batteryLevel%)',
        name: 'BatteryOptimizer',
      );
    });

    // مراقبة مستوى البطارية
    Timer.periodic(const Duration(minutes: 1), (_) async {
      final newLevel = await _battery.batteryLevel;
      if (newLevel != _batteryLevel) {
        _batteryLevel = newLevel;
        _updateOptimizationLevel();
        notifyListeners();
      }
    });

    // مراقبة الاتصال
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((result) {
      _connectionState = result;
      notifyListeners();

      developer.log(
        '📡 Connectivity changed: $result',
        name: 'BatteryOptimizer',
      );
    });
  }

  /// إيقاف المراقبة
  void stopMonitoring() {
    _isMonitoring = false;
    _batterySubscription?.cancel();
    _connectivitySubscription?.cancel();
    _batterySubscription = null;
    _connectivitySubscription = null;
  }

  /// تحديث مستوى التحسين بناءً على حالة البطارية
  void _updateOptimizationLevel() {
    if (_isCharging) {
      // عند الشحن، نستخدم التحسين الخفيف
      _optimizationLevel = BatteryOptimizationLevel.light;
      return;
    }

    // تحديد المستوى بناءً على نسبة البطارية
    if (_batteryLevel <= 10) {
      _optimizationLevel = BatteryOptimizationLevel.aggressive;
    } else if (_batteryLevel <= 20) {
      _optimizationLevel = BatteryOptimizationLevel.moderate;
    } else if (_batteryLevel <= 40) {
      _optimizationLevel = BatteryOptimizationLevel.light;
    } else {
      _optimizationLevel = BatteryOptimizationLevel.none;
    }
  }

  /// تعيين مستوى التحسين يدوياً
  void setOptimizationLevel(BatteryOptimizationLevel level) {
    _optimizationLevel = level;
    notifyListeners();

    developer.log(
      '🔋 Optimization level set to: $level',
      name: 'BatteryOptimizer',
    );
  }

  /// التحقق مما إذا كان يجب المزامنة
  bool _shouldSync() {
    final settings = syncSettings;

    // التحقق من نسبة البطارية
    if (_batteryLevel < settings.minBatteryPercentage) {
      return false;
    }

    // التحقق من حالة الشحن
    if (!settings.syncOnBattery && !_isCharging) {
      return false;
    }

    // التحقق من الاتصال
    if (_connectionState.contains(ConnectivityResult.none) && !_connectionState.any((r) => r != ConnectivityResult.none)) {
      return false;
    }

    return true;
  }

  /// الحصول على نص وصف حالة البطارية
  String getBatteryStatusText() {
    if (_isCharging) {
      return 'جاري الشحن ($_batteryLevel%)';
    }

    if (_batteryLevel <= 10) {
      return 'البطارية منخفضة ($_batteryLevel%) - المزامنة متوقفة';
    } else if (_batteryLevel <= 20) {
      return 'البطارية ضعيفة ($_batteryLevel%) - المزامنة عند الشحن فقط';
    } else if (_batteryLevel <= 40) {
      return 'البطارية متوسطة ($_batteryLevel%)';
    } else {
      return 'البطارية جيدة ($_batteryLevel%)';
    }
  }

  /// الحصول على لون حالة البطارية
  Color getBatteryStatusColor() {
    if (_isCharging) return Colors.green;
    if (_batteryLevel <= 10) return Colors.red;
    if (_batteryLevel <= 20) return Colors.orange;
    if (_batteryLevel <= 40) return Colors.yellow.shade700;
    return Colors.green;
  }

  /// الحصول على أيقونة حالة البطارية
  IconData getBatteryIcon() {
    if (_isCharging) return Icons.battery_charging_full;
    if (_batteryLevel <= 10) return Icons.battery_alert;
    if (_batteryLevel <= 20) return Icons.battery_0_bar;
    if (_batteryLevel <= 30) return Icons.battery_1_bar;
    if (_batteryLevel <= 50) return Icons.battery_3_bar;
    if (_batteryLevel <= 60) return Icons.battery_4_bar;
    if (_batteryLevel <= 80) return Icons.battery_5_bar;
    return Icons.battery_full;
  }

  /// اقتراح أفضل وقت للمزامنة
  DateTime? suggestNextSyncTime() {
    if (!shouldSync) {
      // إذا لم يكن الوقت مناسباً للمزامنة، نحسب الوقت التالي
      if (!_isCharging && _batteryLevel < 20) {
        // نفترض أن المستخدم سيشحن الجهاز قريباً
        return DateTime.now().add(const Duration(minutes: 30));
      }
      return null;
    }

    return DateTime.now();
  }

  /// الحصول على توصيات لتحسين البطارية
  List<String> getBatteryRecommendations() {
    final recommendations = <String>[];

    if (_batteryLevel <= 20) {
      recommendations.add('🔋 نسبة البطارية منخفضة - يُفضل الشحن قبل المزامنة');
    }

    if (!_isCharging && _batteryLevel < 40) {
      recommendations.add('⚡ وضع توفير البطارية مفعل تلقائياً');
    }

    if (_connectionState.contains(ConnectivityResult.mobile)) {
      recommendations.add('📶 جاري استخدام بيانات الجوال - قد تستهلك رسوم إضافية');
    }

    if (syncSettings.compressData) {
      recommendations.add('🗜️ ضغط البيانات مفعل لتوفير البطارية والبيانات');
    }

    return recommendations;
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}

/// Extension للتحقق من جاهزية المزامنة
extension BatteryOptimizerExtension on BatteryOptimizer {
  /// التحقق من إمكانية المزامنة الآن
  bool get canSyncNow => shouldSync;

  /// الحصول على فترة انتظار المزامنة القادمة
  Duration? get nextSyncDelay {
    if (shouldSync) return Duration.zero;

    // حساب الوقت المتوقع للشحن
    if (_batteryLevel < 20 && !_isCharging) {
      return const Duration(minutes: 30); // تقدير
    }

    return null;
  }
}
