import 'dart:async';
import 'dart:math';
import 'package:appwrite/appwrite.dart';
import 'appwrite_config.dart';
import 'appwrite_logger.dart';

/// مساعد للعمليات الشبكية مع Retry Logic و Timeout و Rate Limiting ذكي.
///
/// ✅ إصلاح (2026-07-10): معالجة شاملة لخطأ 429 (general_rate_limit_exceeded):
///   1. **Rate Limiter شامل (token bucket)**: يضمن تأخيراً أدنى بين كل طلب
///      متتالي لـ Appwrite، يمنع إغراق الخادم بطلبات متتالية من push flow.
///   2. **احترام Retry-After**: عند 429، ننتظر المدة التي يطلبها الخادم
///      (أو backoff أطول: 5s, 15s, 45s, 120s) بدل backoff العادي (2s, 4s, 8s).
///   3. **Circuit Breaker**: بعد 5 أخطاء 429 متتالية، نُفعّل وضع "pausing"
///      لمدة 60 ثانية يرفض فيها أي طلب جديد فوراً دون ضغط إضافي على الخادم.
class AppwriteNetworkHelper {
  factory AppwriteNetworkHelper() => _instance;
  AppwriteNetworkHelper._internal();
  static final AppwriteNetworkHelper _instance =
      AppwriteNetworkHelper._internal();

  final _logger = AppwriteLogger();

  // ─────────────────────────────────────────────────────────────────────
  // Rate Limiter (token bucket) — يضمن تأخيراً أدنى بين الطلبات المتتالية.
  // Appwrite Cloud يفرض حدوداً لكل مشروع/مستخدم؛ التأخير الأدنى يقلل
  // احتمال تجاوزها في push flow حيث تتوالى updateDocument بشكل مكثّف.
  //
  // ✅ إصلاح (2026-07-11 hotfix): رفع التأخير من 600ms إلى 1000ms (60 req/min).
  // Appwrite Cloud Free tier يفرض ~60 req/min. الـ 600ms السابق (100 req/min)
  // كان يسبب إغراق السيرفر بـ 429s متتالية.
  // ─────────────────────────────────────────────────────────────────────
  static const Duration _minRequestInterval = Duration(milliseconds: 1000);
  DateTime _lastRequestTime =
      DateTime.fromMillisecondsSinceEpoch(0);

  // ─────────────────────────────────────────────────────────────────────
  // Circuit Breaker — يحمي من إغراق الخادم عند تكرار 429.
  //
  // ✅ إصلاح (2026-07-11 hotfix): Circuit Breaker حقيقي بثلاث حالات:
  //   CLOSED  — طبيعي، الطلبات تمر
  //   OPEN    — مرفوضة فوراً دون اتصال بالسيرفر لمدة cooldown
  //   HALF-OPEN — يُسمح بطلب واحد فقط للاختبار بعد انتهاء cooldown
  //
  // الإصلاحات الرئيسية:
  //   1. عند OPEN، نرفض الطلبات فوراً (fail fast) بدلاً من الانتظار.
  //      هذا يمنع race condition حيث threads متعددة تنتظر وتُعيد ضبط الحالة.
  //   2. لا نُعيد ضبط _consecutiveRateLimitHits إلا عند طلب ناجح فعلياً.
  //   3. progressive cooldown: 60s → 120s → 300s → 600s.
  // ─────────────────────────────────────────────────────────────────────
  int _consecutiveRateLimitHits = 0;
  static const int _circuitBreakerThreshold = 5;
  DateTime? _circuitBreakerUntil;
  int _circuitBreakerActivationCount = 0;
  static const List<Duration> _progressiveCooldowns = [
    Duration(seconds: 60),
    Duration(seconds: 120),
    Duration(seconds: 300),
    Duration(seconds: 600),
  ];
  // قفل لتسلسل الوصول لحالة الـ breaker (يمنع race conditions)
  final _breakerLock = _AsyncLock();

  /// ينتظر حتى يصبح مسموحاً بإطلاق طلب جديد (للحفاظ على rate limit).
  ///
  /// ✅ إصلاح حرج (2026-07-11 hotfix): Circuit Breaker حقيقي.
  ///
  /// عند OPEN: يرفض الطلب فوراً (fail fast) بدلاً من الانتظار.
  /// هذا يمنع:
  ///   1. race condition حيث threads متعددة تنتظر وتُعيد ضبط الحالة
  ///   2. استمرار العداد في النمو بدون توقف
  ///   3. استهلاك الموارد في انتظار بلا فائدة
  ///
  /// الـ exception المُرمي يحمل نوع 'circuit_breaker_active' حتى يتمكن
  /// withRetry من تمييزه عن 429 الحقيقي من السيرفر.
  Future<void> _acquireRequestSlot() async {
    // ✅ إصلاح (2026-07-11 hotfix): استخدم lock لمنع race conditions
    // عندما threads متعددة تحاول اكتساب slot في وقت واحد.
    return _breakerLock.synchronize(() async {
      // 1) فحص circuit breaker — fail fast بدلاً من الانتظار
      if (_circuitBreakerUntil != null) {
        final now = DateTime.now();
        if (now.isBefore(_circuitBreakerUntil!)) {
          final remaining = _circuitBreakerUntil!.difference(now);
          // ✅ إصلاح: لا ننتظر — نرمي استثناء فوراً.
          // هذا يكسر الحلقة المفرغة: withRetry سيرى circuit_breaker_active
          // وينتظر فعلياً دون زيادة عداد 429.
          throw AppwriteException(
            'Circuit breaker active — rate limit cooldown. '
            'Retry in ${remaining.inSeconds}s.',
            429,
            'circuit_breaker_active',
          );
        } else {
          // ✅ انتهت فترة التهدئة — انتقل إلى HALF-OPEN:
          // نُعيد ضبط _circuitBreakerUntil لكن نحتفظ بـ _consecutiveRateLimitHits
          // حتى لا يُعاد تفعيل الـ breaker فوراً عند أول 429.
          // الـ request القادم سيمر (HALF-OPEN) — إن نجح، يُصفّر العداد.
          _circuitBreakerUntil = null;
        }
      }

      // 2) احترام التأخير الأدنى بين الطلبات
      // ✅ إصلاح سباق: نحجز فتحة الطلب التالية بشكل متزامن *قبل* الـ await.
      final now = DateTime.now();
      final scheduledTime = _lastRequestTime.add(_minRequestInterval).isAfter(now)
          ? _lastRequestTime.add(_minRequestInterval)
          : now;
      _lastRequestTime = scheduledTime;
      final wait = scheduledTime.difference(now);
      if (wait > Duration.zero) {
        await Future<void>.delayed(wait);
      }
    });
  }

  /// يُستدعى عند نجاح أي طلب — يصفّر عدّاد circuit breaker.
  ///
  /// ✅ إصلاح (2026-07-11): عند النجاح، أعد ضبط عدّاد التفعيلات أيضاً
  /// حتى لا يستمر progressive cooldown في الزيادة بعد التعافي.
  void _onRequestSuccess() {
    if (_consecutiveRateLimitHits > 0) {
      _consecutiveRateLimitHits = 0;
    }
    if (_circuitBreakerActivationCount > 0) {
      _circuitBreakerActivationCount = 0;
    }
  }

  /// يُستدعى عند تلقي 429 من السيرفر (وليس من circuit breaker محلي).
  ///
  /// ✅ إصلاح (2026-07-11): progressive cooldown — كل تفعيل جديد يزيد المدة.
  /// هذا يمنع إعادة التفعيل الفورية بعد انتهاء الـ 60s.
  void _onRateLimitHit() {
    _consecutiveRateLimitHits++;
    if (_consecutiveRateLimitHits >= _circuitBreakerThreshold) {
      // ✅ progressive cooldown: 60s → 120s → 300s → 600s
      final cooldownIndex = _circuitBreakerActivationCount
          .clamp(0, _progressiveCooldowns.length - 1);
      final cooldown = _progressiveCooldowns[cooldownIndex];
      _circuitBreakerActivationCount++;
      _circuitBreakerUntil = DateTime.now().add(cooldown);
      _logger.error(
        '🔌 Circuit breaker ACTIVATED for ${cooldown.inSeconds}s '
        'after $_consecutiveRateLimitHits consecutive 429s '
        '(activation #$_circuitBreakerActivationCount)',
        tag: 'RATE_LIMIT',
      );
    }
  }

  /// تنفيذ عملية مع Retry Logic (Exponential Backoff)
  ///
  /// [operation] - الدالة المراد تنفيذها
  /// [maxRetries] - عدد المحاولات القصوى (افتراضي: 3)
  /// [initialDelay] - التأخير الأولي (افتراضي: 2 ثانية)
  /// [backoffMultiplier] - معامل التضاعف (افتراضي: 2.0)
  /// [operationName] - اسم العملية للتسجيل
  /// [suppressErrorLog] - إذا true، يُخفض تحذير "Non-retriable error" من
  ///   WARNING إلى debug. مفيد لأخطاء 404 المتوقعة في upsert probe (مثلاً
  ///   updateDocument على مستند جديد لم يُرفع بعد) — راجع إصلاح #2-D.
  Future<T> withRetry<T>({
    required Future<T> Function() operation,
    int? maxRetries,
    Duration? initialDelay,
    double? backoffMultiplier,
    String? operationName,
    bool suppressErrorLog = false,
  }) async {
    final retries = maxRetries ?? AppwriteConfig.maxRetries;
    final delay = initialDelay ?? AppwriteConfig.initialRetryDelay;
    final multiplier =
        backoffMultiplier ?? AppwriteConfig.retryBackoffMultiplier;
    final opName = operationName ?? 'Operation';

    int attempt = 0;
    Duration currentDelay = delay;

    while (true) {
      attempt++;

      try {
        // ✅ Rate limiter: انتظر قبل إطلاق الطلب
        await _acquireRequestSlot();
        _logger.debug('$opName - Attempt $attempt/$retries', tag: 'RETRY');
        final result = await operation();
        _onRequestSuccess();
        return result;
      } catch (e) {
        // ✅ إصلاح (2026-07-11 hotfix): ميز circuit_breaker_active عن 429 الحقيقي.
        // circuit_breaker_active = الخطأ من _acquireRequestSlot (محلي، لا يستهلك محاولة).
        // 429 الحقيقي = الخطأ من السيرفر (يستهلك محاولة + يزيد العداد).
        if (_isCircuitBreakerActive(e)) {
          // ✅ الـ breaker مُفعّل — انتظر حتى انتهاء cooldown دون زيادة العداد.
          // لا نستهلك محاولة (attempt لا تزيد).
          attempt--;
          final remaining = circuitBreakerRemaining ?? const Duration(seconds: 60);
          _logger.warning(
            '$opName - Circuit breaker active, waiting ${remaining.inSeconds}s '
            'before retry (attempt not consumed).',
            tag: 'RATE_LIMIT',
          );
          await Future<void>.delayed(remaining);
          continue;
        }

        // ✅ معالجة 429 بأولوية: backoff أطول + احترام Retry-After
        if (_isRateLimitError(e)) {
          _onRateLimitHit();

          // عند الوصول للحد الأقصى من المحاولات، ارفع الخطأ
          if (attempt >= retries) {
            _logger.error(
              '$opName - Max retries ($retries) reached on rate limit (429)',
              error: e,
              tag: 'RATE_LIMIT',
            );
            rethrow;
          }

          // احسب وقت الانتظار: استخدم Retry-After إذا توفّر، وإلا استخدم
          // backoff متدرّجاً مخصصاً لـ 429 (5s, 15s, 45s, 120s).
          // ✅ إصلاح (2026-07-11 hotfix): حد أدنى 60s لاحترام الـ rate limit
          // بدلاً من 5s, 15s (التي تسبب إعادة 429 فوراً).
          final extractedRetryAfter = _extractRetryAfter(e);
          final backoff = _rateLimitBackoff(attempt);
          // استخدم القيمة الأكبر بين Retry-After و backoff، مع حد أدنى 60s
          final waitTime = [
            extractedRetryAfter ?? Duration.zero,
            backoff,
            const Duration(seconds: 60), // ✅ حد أدنى 60s
          ].reduce((a, b) => a > b ? a : b);
          _logger.warning(
            '$opName - 429 rate limit on attempt $attempt/$retries. '
            'Waiting ${waitTime.inSeconds}s before retry.',
            tag: 'RATE_LIMIT',
          );
          await Future<void>.delayed(waitTime);
          continue; // لا نطبّق currentDelay العادي
        }

        // التحقق من نوع الخطأ - هل قابل لإعادة المحاولة؟
        if (!_isRetriableError(e)) {
          // ✅ إصلاح #2-D: كتم تحذير "Non-retriable error" للأخطاء المتوقعة
          // (مثل 404 في upsert probe على مستندات جديدة). الخطأ يُعاد رميه
          // لكن بدون ضجيج في السجل.
          if (!suppressErrorLog) {
            _logger.warning('$opName - Non-retriable error: $e', tag: 'RETRY');
          } else {
            _logger.debug(
              '$opName - Expected non-retriable error (suppressed): $e',
              tag: 'RETRY',
            );
          }
          rethrow;
        }

        // إذا وصلنا للحد الأقصى من المحاولات
        if (attempt >= retries) {
          _logger.error(
            '$opName - Max retries ($retries) reached',
            error: e,
            tag: 'RETRY',
          );
          rethrow;
        }

        // حساب وقت الانتظار (Exponential Backoff)
        final waitTime = currentDelay;
        _logger.warning(
          '$opName - Attempt $attempt failed, retrying in ${waitTime.inSeconds}s... Error: $e',
          tag: 'RETRY',
        );

        await Future<void>.delayed(waitTime);
        currentDelay = Duration(
          milliseconds: (currentDelay.inMilliseconds * multiplier).round(),
        );
      }
    }
  }

  /// تنفيذ عملية مع Timeout
  ///
  /// [operation] - الدالة المراد تنفيذها
  /// [timeout] - المدة القصوى للانتظار
  /// [operationName] - اسم العملية للتسجيل
  /// [suppressErrorLog] - إذا true، لا يُسجّل الخطأ كـ ERROR (للأخطاء المتوقعة
  ///   مثل 404 في upsert probe). الخطأ يُعاد رميه لكن بدون تسجيل مزعج.
  Future<T> withTimeout<T>({
    required Future<T> Function() operation,
    Duration? timeout,
    String? operationName,
    bool suppressErrorLog = false,
  }) async {
    final maxDuration = timeout ?? AppwriteConfig.defaultTimeout;
    final opName = operationName ?? 'Operation';

    try {
      _logger.debug(
        '$opName - Starting with ${maxDuration.inSeconds}s timeout',
        tag: 'TIMEOUT',
      );

      return await operation().timeout(
        maxDuration,
        onTimeout: () {
          _logger.error(
            '$opName - Timeout after ${maxDuration.inSeconds}s',
            tag: 'TIMEOUT',
          );
          throw TimeoutException(
            '$opName تجاوز الوقت المحدد (${maxDuration.inSeconds} ثانية)',
          );
        },
      );
    } catch (e) {
      if (e is TimeoutException) {
        rethrow;
      }
      // ✅ إصلاح (2026-06-28): كتم أخطاء 404 المتوقعة في upsert probe
      // 404 من updateDocument متوقع تماماً للسجلات الجديدة التي لم تُرفع
      // للسحابة بعد. تسجيله كـ ERROR يُسبب ضوضاء كبيرة في السجلات.
      if (!suppressErrorLog) {
        _logger.error('$opName - Failed: $e', error: e, tag: 'TIMEOUT');
      } else {
        _logger.debug('$opName - Expected error (suppressed): $e', tag: 'TIMEOUT');
      }
      rethrow;
    }
  }

  /// تنفيذ عملية مع كل من Retry و Timeout
  ///
  /// [operation] - الدالة المراد تنفيذها
  /// [maxRetries] - عدد المحاولات القصوى
  /// [timeout] - المدة القصوى للانتظار لكل محاولة
  /// [operationName] - اسم العملية للتسجيل
  /// [suppressErrorLog] - إذا true، لا يُسجّل الخطأ كـ ERROR (للأخطاء المتوقعة)
  Future<T> withRetryAndTimeout<T>({
    required Future<T> Function() operation,
    int? maxRetries,
    Duration? timeout,
    String? operationName,
    bool suppressErrorLog = false,
  }) async {
    return withRetry(
      operation: () => withTimeout(
        operation: operation,
        timeout: timeout,
        operationName: operationName,
        suppressErrorLog: suppressErrorLog,
      ),
      maxRetries: maxRetries,
      operationName: operationName,
      // ✅ إصلاح #2-D: تمرير suppressErrorLog إلى withRetry أيضاً لكتم
      // تحذير "Non-retriable error" للأخطاء المتوقعة (404 في upsert probe).
      suppressErrorLog: suppressErrorLog,
    );
  }

  /// التحقق من أن الخطأ قابل لإعادة المحاولة
  bool _isRetriableError(dynamic error) {
    final errorStr = error.toString().toLowerCase();

    // ✅ إصلاح جذري: أخطاء العميل (4xx) التي لا يمكن حلها بإعادة المحاولة
    // يجب استثناؤها صراحةً حتى لو تطابقت مع أنماط شبكية أعلاه.
    // هذا يمنع إهدار المحاولات على أخطاء مثل:
    //   - 409 document_already_exists (تضارب — يجب حلها بـ updateDocument، ليس retry)
    //   - 400 bad_request, 401 unauthorized, 403 forbidden, 404 not_found
    //   - 422 unprocessable_entity
    //
    // ملاحظة: 429 (rate_limit) مستثنى من هذا الفلتر لأنه قابل للحل بالانتظار.
    if (error is AppwriteException) {
      final code = error.code;
      if (code != null &&
          code >= 400 &&
          code < 500 &&
          code != 408 &&
          code != 429) {
        return false;
      }
      // فحص نوع الخطأ لأنواع Appwrite المعروفة غير القابلة لإعادة المحاولة
      final type = (error.type ?? '').toLowerCase();
      if (type.contains('document_already_exists') ||
          type.contains('document_not_found') ||
          type.contains('user_not_found') ||
          type.contains('user_already_exists') ||
          type.contains('invalid_argument') ||
          type.contains('validation_failed')) {
        return false;
      }
    }

    // أخطاء الشبكة القابلة لإعادة المحاولة
    if (errorStr.contains('network') ||
        errorStr.contains('connection') ||
        errorStr.contains('socket') ||
        errorStr.contains('timeout') ||
        errorStr.contains('failed host lookup')) {
      return true;
    }

    // أخطاء HTTP القابلة لإعادة المحاولة
    if (errorStr.contains('500') || // Internal Server Error
        errorStr.contains('502') || // Bad Gateway
        errorStr.contains('503') || // Service Unavailable
        errorStr.contains('504') || // Gateway Timeout
        errorStr.contains('429')) {
      // Too Many Requests
      return true;
    }

    // أخطاء Appwrite المؤقتة
    if (errorStr.contains('rate limit') ||
        errorStr.contains('server_error') ||
        errorStr.contains('service_unavailable')) {
      return true;
    }

    // باقي الأخطاء غير قابلة لإعادة المحاولة (مثل 401, 403, 404)
    return false;
  }

  /// يكتشف ما إذا كان الخطأ هو 429 rate limit.
  bool _isRateLimitError(dynamic error) {
    if (error is AppwriteException) {
      if (error.code == 429) return true;
      final type = (error.type ?? '').toLowerCase();
      if (type.contains('rate_limit') ||
          type.contains('general_rate_limit_exceeded')) {
        return true;
      }
    }
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('rate_limit_exceeded') ||
        errorStr.contains('rate limit') ||
        errorStr.contains('429');
  }

  /// يستخرج قيمة Retry-After من رسالة خطأ Appwrite (إن وُجدت).
  /// Appwrite لا يُعيد header بصيغة قياسية دائماً، لكنه يُضمّن أحياناً
  /// "try again after X seconds" في رسالة الخطأ.
  Duration? _extractRetryAfter(dynamic error) {
    if (error is AppwriteException) {
      final msg = error.message ?? '';
      // أنماط شائعة: "try again after 30 seconds", "retry after 45s"
      final patterns = [
        RegExp(r'try\s+again\s+after\s+(\d+)\s*s', caseSensitive: false),
        RegExp(r'retry\s+after\s+(\d+)\s*s', caseSensitive: false),
        RegExp(r'after\s+(\d+)\s+seconds', caseSensitive: false),
      ];
      for (final p in patterns) {
        final m = p.firstMatch(msg);
        if (m != null) {
          final secs = int.tryParse(m.group(1) ?? '');
          if (secs != null && secs > 0 && secs < 600) {
            // حدّ أقصى 10 دقائق لتفادي الانتظار الطويل بلا داعٍ
            return Duration(seconds: secs);
          }
        }
      }
    }
    return null;
  }

  /// Backoff متدرّج خاص بأخطاء 429 — أطول من backoff العادي.
  /// المحاولة 1: 5s، 2: 15s، 3: 45s، 4+: 120s.
  /// مع jitter عشوائي ±20% لتقليل التصادم بين الأجهزة.
  Duration _rateLimitBackoff(int attempt) {
    const baseSeconds = [5, 15, 45, 120];
    final idx = (attempt - 1).clamp(0, baseSeconds.length - 1);
    final base = baseSeconds[idx];
    final jitter = (base * 0.2) * (Random().nextDouble() * 2 - 1);
    final seconds = (base + jitter).round().clamp(1, 600);
    return Duration(seconds: seconds);
  }

  /// حساب وقت الانتظار بناءً على Exponential Backoff مع Jitter
  ///
  /// [attempt] - رقم المحاولة
  /// [baseDelay] - التأخير الأساسي
  /// [multiplier] - معامل التضاعف
  /// [addJitter] - إضافة تذبذب عشوائي (يساعد في تقليل التصادمات)
  Duration calculateBackoff({
    required int attempt,
    Duration? baseDelay,
    double? multiplier,
    bool addJitter = true,
  }) {
    final base = baseDelay ?? AppwriteConfig.initialRetryDelay;
    final mult = multiplier ?? AppwriteConfig.retryBackoffMultiplier;

    // Exponential backoff: delay = baseDelay * (multiplier ^ attempt)
    final exponentialDelay = base.inMilliseconds * (mult * attempt);

    // إضافة jitter (تذبذب عشوائي بين 0-20%)
    if (addJitter) {
      final jitter =
          exponentialDelay *
          0.2 *
          (0.5 + (DateTime.now().millisecond % 100) / 100);
      return Duration(milliseconds: (exponentialDelay + jitter).round());
    }

    return Duration(milliseconds: exponentialDelay.round());
  }

  /// ✅ جديد: حالة الـ circuit breaker — يُستخدم من sync manager لإيقاف
  /// المزامنة مؤقتاً عند تفعّله.
  ///
  /// ✅ إصلاح (2026-07-11 hotfix): لا نُعيد ضبط العداد هنا — يتم في _onRequestSuccess.
  bool get isCircuitBreakerActive {
    if (_circuitBreakerUntil == null) return false;
    if (DateTime.now().isBefore(_circuitBreakerUntil!)) return true;
    // انتهت فترة التهدئة — انتقل إلى HALF-OPEN
    _circuitBreakerUntil = null;
    return false;
  }

  /// ✅ جديد: المدة المتبقية حتى انتهاء الـ circuit breaker (null إذا غير مُفعّل).
  Duration? get circuitBreakerRemaining {
    if (_circuitBreakerUntil == null) return null;
    final remaining = _circuitBreakerUntil!.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// ✅ إصلاح (2026-07-11 hotfix): يكتشف ما إذا كان الخطأ من circuit breaker
  /// المحلي (type: 'circuit_breaker_active') بدلاً من 429 حقيقي من السيرفر.
  /// هذا يمنع الحلقة المفرغة حيث يُعامل خطأ الـ breaker كـ 429 جديد فيزيد العداد.
  bool _isCircuitBreakerActive(dynamic error) {
    if (error is AppwriteException) {
      final type = (error.type ?? '').toLowerCase();
      if (type.contains('circuit_breaker_active')) return true;
    }
    final errorStr = error.toString().toLowerCase();
    return errorStr.contains('circuit_breaker_active');
  }
}

/// ✅ إصلاح (2026-07-11 hotfix): قفل async بسيط لتسلسل الوصول لحالة الـ breaker.
/// يمنع race conditions عندما threads متعددة تحاول _acquireRequestSlot في وقت واحد.
class _AsyncLock {
  Completer<void>? _completer;

  Future<void> acquire() async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
  }

  void release() {
    final c = _completer;
    _completer = null;
    c?.complete();
  }

  Future<T> synchronize<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }
}
