import 'dart:math';

/// حاسبة زمن الانتظار التدريجي (Exponential Backoff with Jitter).
///
/// يُستخدم لمنع إرسال طلبات متكررة عند فشل تهيئة المزامنة.
/// الخوارزمية:
/// - المحاولة 1: 5 ثوانٍ ±1
/// - المحاولة 2: 10 ثوانٍ ±2
/// - المحاولة 3: 20 ثانية ±3
/// - المحاولة 4+: 30 ثانية ±5 (سقف أقصى)
class BackoffCalculator {
  BackoffCalculator._();

  /// جدول الانتظار الأساسي بالمليثانية.
  static const List<int> _baseDelaysMs = [5000, 10000, 20000];

  /// السقف الأقصى للانتظار بالمليثانية.
  static const int _maxDelayMs = 30000;

  /// نطاق التذبذب لكل مرحلة بالمليثانية.
  /// الفهرس 0 → المحاولة 1، الفهرس 1 → المحاولة 2، وهكذا.
  static const List<int> _jitterRangesMs = [1000, 2000, 3000];

  /// السقف الأقصى للتذبذب بالمليثانية.
  static const int _maxJitterMs = 5000;

  /// المولّد العشوائي لضمان Jitter.
  static final Random _random = Random();

  /// حساب مدة الانتظار التالية بناءً على عدد المحاولات السابقة.
  ///
  /// [attempt] رقم المحاولة (يبدأ من 1).
  /// يعيد المدة بالمليثانية مع تطبيق Jitter لتجنب التزامن.
  static int calculateDelay(int attempt) {
    if (attempt <= 0) return _baseDelaysMs.first;

    final int baseDelay;
    final int jitterRange;

    if (attempt - 1 < _baseDelaysMs.length) {
      baseDelay = _baseDelaysMs[attempt - 1];
      jitterRange = _jitterRangesMs[attempt - 1];
    } else {
      baseDelay = _maxDelayMs;
      jitterRange = _maxJitterMs;
    }

    // Jitter: delay + (random * jitterRange * 2 - jitterRange)
    final jitter = (_random.nextDouble() * 2 * jitterRange - jitterRange)
        .round();
    return (baseDelay + jitter).clamp(1000, _maxDelayMs + _maxJitterMs);
  }

  /// حساب مدة الانتظار كـ [Duration].
  ///
  /// مريح للاستخدام المباشر مع [Timer].
  static Duration calculateDuration(int attempt) {
    return Duration(milliseconds: calculateDelay(attempt));
  }

  /// إعادة تعيين العداد (اختباري).
  /// لا حاجة فعلية لأن [attempt] يُمرّر خارجياً.
  static void reset() {
    // No-op: الحالة تُدار خارجياً عبر [attempt].
  }

  /// الحد الأقصى لعدد المحاولات قبل الوصول للسقف الثابت.
  static int get maxVariableAttempts => _baseDelaysMs.length;
}
