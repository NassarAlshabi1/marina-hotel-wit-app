/// حاسبة زمن الانتظار التدريجي (Exponential Backoff with Jitter).
///
/// يُستخدم لمنع إرسال طلبات متكررة عند فشل تهيئة المزامنة.
/// الخوارزمية:
/// - المحاولة 1: 5 ثوانٍ ±1
/// - المحاولة 2: 10 ثوانٍ ±2
/// - المحاولة 3: 20 ثانية ±3
/// - المحاولة 4+: 30 ثانية ±5 (سقف أقصى)
///
/// لا يستخدم أي مكتبة خارجية (لا dart:math) لتجنب مشاكل
/// AOT compilation في CI.
class BackoffCalculator {
  BackoffCalculator._();

  /// جدول الانتظار الأساسي بالمليثانية.
  static const List<int> _baseDelaysMs = [5000, 10000, 20000];

  /// السقف الأقصى للانتظار بالمليثانية.
  static const int _maxDelayMs = 30000;

  /// نطاق التذبذب لكل مرحلة بالمليثانية.
  static const List<int> _jitterRangesMs = [1000, 2000, 3000];

  /// السقف الأقصى للتذبذب بالمليثانية.
  static const int _maxJitterMs = 5000;

  /// بذرة مولّد الأرقام العشوائية (LCG — Lehmer).
  static int _lcgState = _initialSeed();

  /// بذرة أولية من الوقت الحالي.
  static int _initialSeed() {
    // Use DateTime milliseconds as seed — no external imports needed.
    final now = DateTime.now();
    return now.microsecondsSinceEpoch & 0x7FFFFFFF;
  }

  /// مولّد عشوائي بسيط (Linear Congruential Generator).
  ///
  /// يستخدم معاملات Lehmer القياسية:
  /// state = (state * 48271) % 2147483647
  static int _nextRandom() {
    return _lcgState = (_lcgState * 48271) % 2147483647;
  }

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

    // Jitter: random value in [-jitterRange, +jitterRange]
    final randomValue = _nextRandom() % (2 * jitterRange + 1);
    final jitter = randomValue - jitterRange;
    return (baseDelay + jitter).clamp(1000, _maxDelayMs + _maxJitterMs);
  }

  /// حساب مدة الانتظار كـ [Duration].
  static Duration calculateDuration(int attempt) {
    return Duration(milliseconds: calculateDelay(attempt));
  }

  /// إعادة تعيين البذرة العشوائية.
  static void reset() {
    _lcgState = _initialSeed();
  }

  /// الحد الأقصى لعدد المحاولات قبل الوصول للسقف الثابت.
  static int get maxVariableAttempts => _baseDelaysMs.length;
}
