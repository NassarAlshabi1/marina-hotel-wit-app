// lib/services/crash_alert_service.dart
// خدمة تنبيهات الأعطال — تُرسل تنبيه Telegram عند ارتفاع معدل الأعطال
//
// ترصد معدل الأخطاء في CrashlyticsService وتُرسل تنبيهاً عند تجاوز العتبة.
// العتبة الافتراضية: 50% (نسبة العمليات الفاشلة من إجمالي العمليات).

import 'dart:async';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;
import '../utils/env.dart';

/// خدمة تنبيهات الأعطال عبر Telegram
class CrashAlertService {
  factory CrashAlertService() => _instance;
  CrashAlertService._internal();
  static final CrashAlertService _instance = CrashAlertService._internal();
  static CrashAlertService get instance => _instance;

  Timer? _monitorTimer;
  int _totalOperations = 0;
  int _failedOperations = 0;
  DateTime? _lastAlertTime;
  bool _isMonitoring = false;

  /// عتبة نسبة الأعطال (0.0 - 1.0) — افتراضي 50%
  double crashRateThreshold = 0.5;

  /// الحد الأدنى للعمليات قبل تقييم النسبة (تجنب الإنذارات المبكرة)
  int minOperationsBeforeAlert = 10;

  /// الفاصل الزمني بين التنبيهات (تجنب الرسائل المكررة)
  static const _alertCooldown = Duration(minutes: 30);

  /// بدء مراقبة معدل الأعطال
  void startMonitoring({Duration interval = const Duration(minutes: 5)}) {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _monitorTimer = Timer.periodic(interval, (_) => _checkCrashRate());
    developer.log(
      '✅ CrashAlertService monitoring started (interval=${interval.inMinutes}min)',
      name: 'CrashAlertService',
    );
  }

  /// إيقاف المراقبة
  void stopMonitoring() {
    _monitorTimer?.cancel();
    _monitorTimer = null;
    _isMonitoring = false;
  }

  /// تسجيل عملية ناجحة
  void recordSuccess() {
    _totalOperations++;
  }

  /// تسجيل عملية فاشلة
  void recordFailure() {
    _totalOperations++;
    _failedOperations++;
  }

  /// الحصول على معدل الأعطال الحالي
  double get currentCrashRate {
    if (_totalOperations == 0) return 0.0;
    return _failedOperations / _totalOperations;
  }

  /// إعادة تعيين العدادات
  void resetCounters() {
    _totalOperations = 0;
    _failedOperations = 0;
  }

  /// فحص معدل الأعطال وإرسال تنبيه إذا لزم
  Future<void> _checkCrashRate() async {
    if (_totalOperations < minOperationsBeforeAlert) return;

    final rate = currentCrashRate;
    if (rate < crashRateThreshold) return;

    // التحقق من فترة التهدئة (لا نُرسل تنبيه كل دقيقة)
    if (_lastAlertTime != null) {
      final elapsed = DateTime.now().difference(_lastAlertTime!);
      if (elapsed < _alertCooldown) return;
    }

    await _sendTelegramAlert(rate);
    _lastAlertTime = DateTime.now();

    // إعادة تعيين العدادات بعد التنبيه
    resetCounters();
  }

  /// إرسال تنبيه Telegram
  Future<void> _sendTelegramAlert(double crashRate) async {
    if (!Env.isTelegramConfigured) return;

    try {
      final message = _buildAlertMessage(crashRate);
      final url = Uri.parse(
        'https://api.telegram.org/bot${Env.telegramBotToken}/sendMessage',
      );

      await http
          .post(
            url,
            body: {
              'chat_id': Env.telegramChatId,
              'text': message,
              'parse_mode': 'HTML',
            },
          )
          .timeout(const Duration(seconds: 10));

      developer.log(
        '🚨 Crash alert sent to Telegram (rate=${(crashRate * 100).toStringAsFixed(1)}%)',
        name: 'CrashAlertService',
      );
    } catch (e) {
      developer.log(
        '⚠️ Failed to send crash alert: $e',
        name: 'CrashAlertService',
      );
    }
  }

  /// بناء رسالة التنبيه
  String _buildAlertMessage(double crashRate) {
    final now = DateTime.now().toIso8601String();
    final ratePct = (crashRate * 100).toStringAsFixed(1);
    return '''
🚨 <b>تنبيه: ارتفاع معدل الأعطال</b>

📊 <b>معدل الأعطال:</b> $ratePct%
📈 <b>العمليات الفاشلة:</b> $_failedOperations / $_totalOperations
⏰ <b>الوقت:</b> $now
🏨 <b>التطبيق:</b> Marina Hotel

⚠️ يُنصح بفحص التطبيق و Firebase Crashlytics للحصول على تفاصيل الأخطاء.
''';
  }

  /// فحص يدوي لمعدل الأعطال (لاختبار التنبيه)
  Future<void> checkNow() async {
    await _checkCrashRate();
  }
}
