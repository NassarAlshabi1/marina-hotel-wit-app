import '../utils/debug_log.dart';
import '../utils/env.dart';

/// Manages API endpoint fallback and selection for resilient connections.
///
/// استراتيجية:
/// 1. حاول الـ endpoint الأساسي (workers.dev)
/// 2. عند الفشل، انتقل للبدائل بالترتيب
/// 3. تذكر آخر endpoint نجح (sticky) واستخدمه أولاً في الطلب القادم
/// 4. إذا فشل، عد للتدوير بين الخيارات
///
/// هذا يعني أن الشبكات المحجوبة تنجح بعد محاولة أو اثنتين فقط.
class EndpointManager {
  EndpointManager._();

  /// القائمة المرتبة للـ endpoints
  static List<String> get all => Env.cloudflareWorkerFallbacks;

  /// الـ endpoint الحالي (يُحدَّث عند النجاح)
  static String _current = Env.cloudflareWorkerUrl;
  static int _currentIndex = 0;

  /// معلومات الفشل (لتجنب إعادة المحاولة الفورية على نفس endpoint)
  static final Map<String, DateTime> _lastFailures = {};
  static const Duration _failureMemory = Duration(minutes: 5);

  /// الحصول على الـ endpoint الحالي.
  static String get current => _current;

  /// الحصول على جميع البدائل (للـ resilient client).
  static List<String> get candidates => _getCandidates();

  /// تسجيل نجاح على endpoint معين (sticky).
  static void recordSuccess(String endpoint) {
    if (!all.contains(endpoint)) return;

    _current = endpoint;
    _currentIndex = all.indexOf(endpoint);
    _lastFailures.remove(endpoint);

    dlog(
      () =>
          '✅ EndpointManager: Sticky endpoint → $endpoint (index: $_currentIndex)',
    );
  }

  /// تسجيل فشل على endpoint معين.
  static void recordFailure(String endpoint) {
    _lastFailures[endpoint] = DateTime.now();

    dwarn(
      () =>
          '⚠️ EndpointManager: Failure recorded for $endpoint — will try alternatives',
    );

    // إذا كان endpoint الحالي قد فشل، انتقل للتالي
    if (_current == endpoint) {
      _moveToNextEndpoint();
    }
  }

  /// محاولة الـ endpoint التالي في القائمة.
  static void _moveToNextEndpoint() {
    final available = all.where(_isAvailable).toList();
    if (available.isEmpty) {
      dwarn(
        () => '⚠️ EndpointManager: No available endpoints — will retry all',
      );
      _lastFailures.clear();
      _current = Env.cloudflareWorkerUrl;
      _currentIndex = 0;
      return;
    }

    // ابحث عن أول available بعد الحالي
    for (int i = _currentIndex + 1; i < all.length; i++) {
      if (_isAvailable(all[i])) {
        _current = all[i];
        _currentIndex = i;
        dlog(() => '🔄 EndpointManager: Switched to ${all[i]} (index: $i)');
        return;
      }
    }

    // إذا لم تجد، ابدأ من البداية
    for (final endpoint in available) {
      final index = all.indexOf(endpoint);
      if (index < _currentIndex) {
        _current = endpoint;
        _currentIndex = index;
        dlog(
          () =>
              '🔄 EndpointManager: Wrapped around to $endpoint (index: $index)',
        );
        return;
      }
    }
  }

  /// هل الـ endpoint متاح (لم يفشل مؤخراً أو فشله انتهى)؟
  static bool _isAvailable(String endpoint) {
    final lastFailure = _lastFailures[endpoint];
    if (lastFailure == null) return true;

    final elapsed = DateTime.now().difference(lastFailure);
    if (elapsed > _failureMemory) {
      _lastFailures.remove(endpoint);
      return true;
    }

    return false;
  }

  /// قائمة candidates مرتبة: الحالي أولاً، ثم البقية.
  static List<String> _getCandidates() {
    final result = <String>[_current];
    for (final endpoint in all) {
      if (endpoint != _current && _isAvailable(endpoint)) {
        result.add(endpoint);
      }
    }
    // أضف الـ unavailable في النهاية (سيُحاول بعد انتهاء failure memory)
    for (final endpoint in all) {
      if (endpoint != _current && !_isAvailable(endpoint)) {
        result.add(endpoint);
      }
    }
    return result;
  }

  /// إعادة تعيين للاختبارات.
  static void reset() {
    _current = Env.cloudflareWorkerUrl;
    _currentIndex = 0;
    _lastFailures.clear();
  }

  /// معلومات تشخيص.
  static String get diagnostics =>
      '''
Current: $_current (index: $_currentIndex)
All: ${all.join(', ')}
Last failures: ${_lastFailures.entries.map((e) => '${e.key} @ ${e.value}').join(', ')}
Available: ${_getCandidates().join(', ')}
  ''';
}
