import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/debug_log.dart';

/// العتبة الافتراضية لتعثّر العملية — 5 دقائق حسب توصية التقرير.
const int _defaultStuckThresholdMs = 300000;

/// حالة بوّابة المزامنة العامة — تعكس ما إذا كانت أي عملية مزامنة
/// جارية في التطبيق كله، بصرف النظر عن المصدر (زر يدوي، سحب تلقائي
/// عند الفتح، مؤقّت، مهمة خلفية).
///
/// هذه هي نقطة التحقق المركزية الوحيدة. كل نقاط دخول المزامنة يجب
/// أن تستدعي [SyncGate.tryEnter] قبل البدء، و[SyncGate.exit] عند الانتهاء.
/// كل أزرار/مؤشرات المزامنة في الواجهة يجب أن تراقب [SyncGate.instance]
/// وتعطّل نفسها تلقائياً طالما البوّابة مشغولة.
@immutable
class SyncGateState {
  const SyncGateState({
    this.isBusy = false,
    this.operation,
    this.source,
    this.startedAt,
    this.entryId,
    this.rejectedCount = 0,
  });

  /// هل توجد عملية مزامنة جارية الآن من أي مصدر؟
  final bool isBusy;

  /// نوع العملية: 'push', 'pull', 'auto_pull', 'auto_sync', 'guardian', ...
  final String? operation;

  /// مصدر العملية: 'dashboard_button', 'auto_open', 'timer',
  /// 'background', 'exit_mixin', 'settings', ...
  final String? source;

  /// وقت بدء العملية (للكشف عن العمليات المتعثرة).
  final DateTime? startedAt;

  /// تذكرة ملكية فريدة لكل دخول ناجح — تُستخدم لمنع تحرير البوّابة
  /// من عملية قديمة متأخرة (stale release) بعد تحريرها تلقائياً بسبب
  /// التعثر ثم دخول عملية أخرى. الحالة الخاملة دائماً `null`.
  final int? entryId;

  /// ✅ P0: عدد مرات رفض الدخول (البوّابة مشغولة) خلال دورة الحيازة
  /// الحالية — لتشخيص الازدحام، وظاهر لعناصر الواجهة عبر الـ notifier.
  /// يُصفَّر عند كل دخول/خروج جديد (دورة جديدة)، بينما العدّاد التراكمي
  /// الدائم على [SyncGate] نفسه.
  final int rejectedCount;

  /// مدة العملية الحالية بالمللي ثانية، أو null إذا لم تكن مشغولة.
  int? get elapsedMs => isBusy && startedAt != null
      ? DateTime.now().difference(startedAt!).inMilliseconds
      : null;

  /// هل العملية الحالية متعثرة (تجاوزت العتبة الافتراضية 5 دقائق)؟
  bool get isStuck => isStuckAt(const Duration(milliseconds: 300000));

  /// فحص التعثر بعتبة مخصّصة — البوّابة تمرر [SyncGate.stuckTimeout]
  /// القابل للضبط (للاختبارات أو سياسات أقصر/أطول).
  bool isStuckAt(Duration threshold) =>
      isBusy && (elapsedMs ?? 0) > threshold.inMilliseconds;

  SyncGateState copyWith({
    bool? isBusy,
    String? operation,
    String? source,
    DateTime? startedAt,
    int? entryId,
    int? rejectedCount,
    bool clearOperation = false,
    bool clearSource = false,
    bool clearStartedAt = false,
    bool clearEntryId = false,
    bool clearRejectedCount = false,
  }) {
    return SyncGateState(
      isBusy: isBusy ?? this.isBusy,
      operation: clearOperation ? null : (operation ?? this.operation),
      source: clearSource ? null : (source ?? this.source),
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      entryId: clearEntryId ? null : (entryId ?? this.entryId),
      rejectedCount: clearRejectedCount
          ? 0
          : (rejectedCount ?? this.rejectedCount),
    );
  }

  @override
  String toString() =>
      'SyncGateState(isBusy=$isBusy, operation=$operation, source=$source, '
      'startedAt=$startedAt, entryId=$entryId, rejected=$rejectedCount, '
      'isStuck=$isStuck)';
}

/// سجل عملية مرفوضة لأن البوّابة كانت مشغولة.
///
/// ✅ P0 (تقرير 2026-09-11): سابقاً كان الرفض يُسجَّل في وضع الـ debug
/// فقط — في الإنتاج لا أثر إطلاقاً للعمليات المرفوضة مما يصعّب تشخيص
/// «لماذا لا تُزامن الأجهزة عند الضغط على الزر». الآن كل رفض يُسجَّل
/// في `_rejectionLog` المحدود وعدّاد دائم، مع رد نداء اختياري
/// `SyncGate.onRejected`
/// لتوصيل مسجّل خارجي عند الحاجة.
@immutable
class SyncGateRejection {
  const SyncGateRejection({
    required this.operation,
    required this.source,
    required this.attemptedAt,
    this.busyOperation,
    this.busySource,
  });

  /// العملية التي حاولت الدخول و رُفضت.
  final String operation;

  /// مصدر المحاولة المرفوضة.
  final String source;

  /// وقت المحاولة.
  final DateTime attemptedAt;

  /// العملية التي كانت تحوز البوّابة لحظة الرفض.
  final String? busyOperation;

  /// مصدر العملية الحابزة للبوّابة لحظة الرفض.
  final String? busySource;

  @override
  String toString() =>
      'SyncGateRejection(operation=$operation, source=$source, '
      'busyWith=$busyOperation/$busySource, at=$attemptedAt)';
}

/// البوّابة العامة للمزامنة — منع التزامن العابر للمسارات.
///
/// Singleton يعيش في الـ main isolate. أي عملية مزامنة في الـ main
/// isolate يجب أن تمرّ عبر هذه البوّابة. العمليات في isolates منفصلة
/// (مثل Workmanager background tasks) لا يمكنها تحديث هذه البوّابة
/// مباشرة — وهذا مقصود، لأن الـ UI لا يحتاج لرؤية عمليات الـ background
/// أصلاً.
///
/// الاستخدام النموذجي:
/// ```dart
/// final result = await SyncGate.instance.runGuarded(
///   operation: 'pull',
///   source: 'dashboard_button',
///   task: () => actuallyDoPull(),
/// );
/// if (result == null) {
///   // البوّابة مشغولة بعملية أخرى — تجاهل أو أظهر إشعار
/// }
/// ```
///
/// طرق الاستخدام:
/// - `tryEnter(operation, source)` ثم `exit()` في finally — للتحكم اليدوي.
/// - `runGuarded(operation, source, task)` — للتغليف التلقائي بـ try/finally.
///
/// ✅ P0 (تقرير 2026-09-11) — التحصينات المضافة:
///
/// 1. **مهلة العمليات المتعثرة**: أي عملية تحوز البوّابة أطول من
///    [stuckTimeout] (5 دقائق افتراضياً) تُعتبر متعثرة (معلّقة دون
///    عائد — كقاعدة شبكة لا تستجيب أبداً) وتُحرَّر البوّابة تلقائياً:
///    - عند أول محاولة دخول جديدة (نقطة الاختناق الطبيعية)، و/أو
///    - عبر مؤقّت يدير البوّابة نفسها يُسلَّح عند الدخول ويُلغى عند الخروج.
///
///    ملاحظة هندسية: التحرير التلقائي لا يلغي المهمة المعلّقة نفسها —
///    لذلك كل تحرير عبر `runGuarded*` محميّ بـ **تذكرة ملكية**
///    ([SyncGateState.entryId]): عملية قديمة تتأخر في الانتهاء لا تستطيع
///    تحرير البوّابة وهي بحوزة عملية أحدث (stale release محجوب).
///
/// 2. **تسجيل العمليات المرفوضة**: عدّاد تراكمي + سجل محدود + رد نداء
///    اختياري — يعمل في الإنتاج أيضاً (ليس debug فقط)، إضافة إلى
///    `SyncGateState.rejectedCount` الظاهر لعناصر الواجهة لكل دورة حيازة.
class SyncGate {
  SyncGate._();
  static final SyncGate instance = SyncGate._();

  /// منفذ عام يمكن لأي عنصر واجهة مراقبته عبر `ValueListenableBuilder`.
  final ValueNotifier<SyncGateState> notifier = ValueNotifier<SyncGateState>(
    const SyncGateState(),
  );

  /// ✅ P0-1: المهلة التي تُعتبر بعدها العملية الحالية «متعثرة» وتُحرَّر
  /// البوّابة تلقائياً. قابلة للتعديل للاختبارات (الافتراضي 5 دقائق
  /// حسب توصية التقرير).
  Duration stuckTimeout = const Duration(milliseconds: _defaultStuckThresholdMs);

  /// ✅ P0-2: رد نداء اختياري يُستدعى عند كل رفض دخول — لتوصيل مسجّل
  /// خارجي (AppwriteLogger مثلاً) دون إدخال تبعيات في هذه الوحدة.
  void Function(SyncGateRejection rejection)? onRejected;

  // ─── تسجيل الرفض والتعثر ───

  int _rejectedCount = 0;
  int _stuckReleases = 0;
  SyncGateRejection? _lastRejection;
  final List<SyncGateRejection> _rejectionLog = <SyncGateRejection>[];
  static const int _maxRejectionLog = 100;

  /// إجمالي محاولات الدخول المرفوضة منذ آخر [resetStats] — تراكمي دائم
  /// لا يتأثر بدورات الحيازة (عكس `SyncGateState.rejectedCount`).
  int get rejectedCount => _rejectedCount;

  /// إجمالي مرات التحرير التلقائي بسبب التعثر منذ آخر [resetStats].
  int get stuckReleases => _stuckReleases;

  /// آخر رفض مسجَّل (أو null).
  SyncGateRejection? get lastRejection => _lastRejection;

  /// سجل الرفض المحدود (الأحدث آخراً) — حتى 100 عملية مرفوضة.
  List<SyncGateRejection> get rejectionLog =>
      List<SyncGateRejection>.unmodifiable(_rejectionLog);

  /// لقطة إحصائية شاملة — للتشخيص وشاشات الصحة.
  Map<String, dynamic> get stats => {
    'isBusy': isBusy,
    'operation': state.operation,
    'source': state.source,
    'elapsedMs': state.elapsedMs,
    'rejectedCount': _rejectedCount,
    'stuckReleases': _stuckReleases,
    'lastRejection': _lastRejection?.toString(),
    'stuckTimeoutSeconds': stuckTimeout.inSeconds,
  };

  /// تصفير العدادات والسجل (لا يمس حالة الحيازة الحالية).
  void resetStats() {
    _rejectedCount = 0;
    _stuckReleases = 0;
    _lastRejection = null;
    _rejectionLog.clear();
  }

  int _entrySeq = 0;
  Timer? _stuckWatchdog;

  /// اختصار للحالة الحالية.
  SyncGateState get state => notifier.value;

  /// هل البوّابة مشغولة الآن بأي عملية من أي مصدر؟
  bool get isBusy => notifier.value.isBusy;

  /// محاولة دخول البوّابة. تُرجع true إذا نجح الدخول، false إذا كانت
  /// البوّابة مشغولة بعملية أخرى.
  ///
  /// يجب أن تُستدعى **متزامناً قبل أي await** لمنع إعادة الدخول.
  bool tryEnter({required String operation, required String source}) {
    if (notifier.value.isBusy) {
      // ✅ P0-1: قبل الرفض — إن كانت الحابزة متعثرة تجاوزت المهلة،
      // حرّرها تلقائياً ودع المحاولة الحالية تكمل.
      _releaseIfStuck();
      if (notifier.value.isBusy) {
        // ✅ P0-2: سجّل الرفض دائماً (ليس debug فقط).
        _recordRejection(operation, source);
        return false;
      }
    }
    _entrySeq++;
    notifier.value = SyncGateState(
      isBusy: true,
      operation: operation,
      source: source,
      startedAt: DateTime.now(),
      entryId: _entrySeq,
    );
    _armStuckWatchdog();
    if (kDebugMode) {
      dlog(() => '🔒 [SyncGate] entered: $operation from $source');
    }
    return true;
  }

  /// تحرير البوّابة. يجب أن تُستدعى في finally block دائماً.
  ///
  /// ملاحظة: المسارات المغلَّفة بـ [runGuarded]/[runGuardedVoid] تستخدم
  /// تحريراً محميّاً بالتذكرة تلقائياً — هذه الطريقة للمسارات اليدوية.
  void exit() {
    if (!notifier.value.isBusy) {
      // Already idle — nothing to do. This is safe to call multiple times.
      return;
    }
    if (kDebugMode) {
      final elapsed = notifier.value.elapsedMs;
      dlog(
        () =>
            '🔓 [SyncGate] exited: ${notifier.value.operation} from '
            '${notifier.value.source} (took ${elapsed}ms)',
      );
    }
    notifier.value = const SyncGateState();
    _disarmStuckWatchdog();
  }

  /// ✅ P0-1: فحص يدوي/برمجي — يحرر البوّابة إذا كانت العملية الحالية
  /// تجاوزت المهلة. يُرجع true إذا تم تحرير فعلي.
  ///
  /// يُستدعى تلقائياً من: مؤقّت البوّابة الداخلي، وكل [tryEnter] جديد.
  bool releaseIfStuck({Duration? timeout}) {
    final s = notifier.value;
    if (!s.isBusy || s.startedAt == null) {
      return false;
    }
    final limit = timeout ?? stuckTimeout;
    final elapsed = DateTime.now().difference(s.startedAt!);
    if (elapsed < limit) {
      return false;
    }
    _stuckReleases++;
    dlog(
      () =>
          '⏱️ [SyncGate] auto-release stuck operation "${s.operation}" '
          '(${s.source}) بعد ${elapsed.inSeconds}s — تجاوزت المهلة '
          '(${limit.inSeconds}s)',
    );
    notifier.value = const SyncGateState();
    _disarmStuckWatchdog();
    return true;
  }

  void _releaseIfStuck() {
    if (state.isStuckAt(stuckTimeout)) {
      releaseIfStuck();
    }
  }

  /// تحرير محميّ بالتذكرة: عملية قديمة (auto-released ثم دخل غيرها)
  /// لا تحرر البوّابة المسروقة حديثاً.
  void _exitIfCurrent(int? ticket) {
    final s = notifier.value;
    if (!s.isBusy) {
      return; // خاملة أصلاً — لا شيء
    }
    if (s.entryId == null || ticket == null || s.entryId != ticket) {
      dlog(
        () =>
            '🔒 [SyncGate] stale exit ignored (ticket=$ticket, '
            'current=${s.entryId} للعملية ${s.operation})',
      );
      return;
    }
    exit();
  }

  void _armStuckWatchdog() {
    _stuckWatchdog?.cancel();
    _stuckWatchdog = Timer(stuckTimeout, releaseIfStuck);
  }

  void _disarmStuckWatchdog() {
    _stuckWatchdog?.cancel();
    _stuckWatchdog = null;
  }

  void _recordRejection(String operation, String source) {
    _rejectedCount++;
    final current = notifier.value;
    final rejection = SyncGateRejection(
      operation: operation,
      source: source,
      attemptedAt: DateTime.now(),
      busyOperation: current.operation,
      busySource: current.source,
    );
    _lastRejection = rejection;
    _rejectionLog.add(rejection);
    if (_rejectionLog.length > _maxRejectionLog) {
      _rejectionLog.removeAt(0);
    }
    // ✅ العدّاد الظاهر للواجهة خلال دورة الحيازة الحالية.
    notifier.value = current.copyWith(
      rejectedCount: current.rejectedCount + 1,
    );
    if (kDebugMode) {
      dlog(
        () =>
            '🚫 [SyncGate] rejected entry: already busy with '
            '${notifier.value.operation} from ${notifier.value.source} — '
            'rejected: $operation from $source (total: $_rejectedCount)',
      );
    }
    onRejected?.call(rejection);
  }

  /// يُنفّذ [task] أثناء حيازة البوّابة. يُرجع null إذا كانت البوّابة
  /// مشغولة، وإلا يُرجع نتيجة [task].
  ///
  /// يضمن تحرير البوّابة في finally حتى لو فشل [task] برمي استثناء،
  /// والتحرير محميّ بالتذكرة: بعد تحرير تلقائي بسبب التعثر ودخول عملية
  /// أخرى، انتهاء المهمة القديمة المتأخرة لا يسرق الحيازة الجديدة.
  Future<T?> runGuarded<T>({
    required String operation,
    required String source,
    required Future<T> Function() task,
  }) async {
    if (!tryEnter(operation: operation, source: source)) {
      return null;
    }
    final ticket = notifier.value.entryId;
    try {
      return await task();
    } finally {
      _exitIfCurrent(ticket);
    }
  }

  /// نفس [runGuarded] لكن للمهام التي لا تُرجع قيمة. يُرجع true إذا
  /// نُفّذت المهمة، false إذا رُفض الدخول.
  Future<bool> runGuardedVoid({
    required String operation,
    required String source,
    required Future<void> Function() task,
  }) async {
    if (!tryEnter(operation: operation, source: source)) {
      return false;
    }
    final ticket = notifier.value.entryId;
    try {
      await task();
      return true;
    } finally {
      _exitIfCurrent(ticket);
    }
  }
}

/// مزوّد Riverpod للوصول إلى الـ singleton.
final syncGateProvider = Provider<SyncGate>((ref) {
  return SyncGate.instance;
});

/// مزوّد Riverpod يبث حالة البوّابة. يستخدمه الـ UI لمراقبة التغييرات.
final syncGateStateProvider = StreamProvider<SyncGateState>((ref) {
  final controller = StreamController<SyncGateState>();
  void listener() {
    controller.add(SyncGate.instance.notifier.value);
  }

  SyncGate.instance.notifier.addListener(listener);
  ref.onDispose(() {
    SyncGate.instance.notifier.removeListener(listener);
    unawaited(controller.close());
  });
  // البث الأول للحالة الحالية
  controller.add(SyncGate.instance.notifier.value);
  return controller.stream;
});
