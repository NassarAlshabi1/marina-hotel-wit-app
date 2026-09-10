import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../utils/debug_log.dart';

/// ✅ P0: سجل عملية مرفوضة أو عملية متعثرة حُرّرت تلقائياً —
/// للتشخيص اللاحق (يرى عبر [SyncGate.recentRejections] حتى في release).
class SyncGateRejection {
  const SyncGateRejection({
    required this.at,
    required this.kind,
    required this.requestedOperation,
    required this.requestedSource,
    this.busyWithOperation,
    this.busyWithSource,
    this.busyElapsedMs,
  });

  /// وقت الحدث.
  final DateTime at;

  /// نوع الحدث: 'rejected' (رفض دخول والبوّابة مشغولة) أو
  /// 'stuck_released' (تحرير تلقائي لعملية تجاوزت المهلة).
  final String kind;

  /// العملية التي طلبت الدخول.
  final String requestedOperation;

  /// مصدر الطلب.
  final String requestedSource;

  /// العملية التي كانت تحوز البوّابة وقت الحدث.
  final String? busyWithOperation;

  /// مصدر العملية الحائزة.
  final String? busyWithSource;

  /// مدة حيازة العملية الحائزة وقت الحدث (ms).
  final int? busyElapsedMs;

  Map<String, dynamic> toMap() => {
    'at': at.toIso8601String(),
    'kind': kind,
    'requestedOperation': requestedOperation,
    'requestedSource': requestedSource,
    'busyWithOperation': busyWithOperation,
    'busyWithSource': busyWithSource,
    'busyElapsedMs': busyElapsedMs,
  };

  @override
  String toString() {
    final busyOp = busyWithOperation ?? '-';
    final busySrc = busyWithSource ?? '-';
    final elapsed = busyElapsedMs ?? 0;
    return 'SyncGateRejection($kind: $requestedOperation/$requestedSource '
        'while $busyOp/$busySrc (${elapsed}ms))';
  }
}

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
    this.generation = 0,
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

  /// ✅ P0: رمز حيازة أحادي الاتجاه (monotonic) — يُستخدم للتحقق من أن
  /// [SyncGate.exit] يُحرّر نفس الحيازة التي فتحها صاحبها، لا حيازة أحدث
  /// دخلت بعد تحرير تلقائي لعملية متعثرة.
  final int generation;

  /// مدة العملية الحالية بالمللي ثانية، أو null إذا لم تكن مشغولة.
  int? get elapsedMs => isBusy && startedAt != null
      ? DateTime.now().difference(startedAt!).inMilliseconds
      : null;

  SyncGateState copyWith({
    bool? isBusy,
    String? operation,
    String? source,
    DateTime? startedAt,
    int? generation,
    bool clearOperation = false,
    bool clearSource = false,
    bool clearStartedAt = false,
  }) {
    return SyncGateState(
      isBusy: isBusy ?? this.isBusy,
      operation: clearOperation ? null : (operation ?? this.operation),
      source: clearSource ? null : (source ?? this.source),
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
      generation: generation ?? this.generation,
    );
  }

  @override
  String toString() =>
      'SyncGateState(isBusy=$isBusy, operation=$operation, source=$source, '
      'startedAt=$startedAt, generation=$generation)';
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
class SyncGate {
  SyncGate._();
  static final SyncGate instance = SyncGate._();

  /// ✅ P0: المهلة الافتراضية للعمليات المتعثرة — العملية التي تحوز
  /// البوّابة أطول من هذه المدة تُعتبَر متعثّرة، وتُحرَّر تلقائياً عند
  /// أول طلب دخول جديد (recovery عند الطلب، بلا مؤقتات خلفية).
  static const Duration defaultStuckOperationTimeout = Duration(minutes: 5);

  /// المهلة الفعلية للعمليات المتعثرة (قابلة للتعديل للاختبارات).
  Duration stuckOperationTimeout = defaultStuckOperationTimeout;

  /// أقصى عدد لسجلات الرفض/التحرير التلقائي المحفوظة في الذاكرة.
  static const int maxRejectionLogs = 50;

  /// منفذ عام يمكن لأي عنصر واجهة مراقبته عبر `ValueListenableBuilder`.
  final ValueNotifier<SyncGateState> notifier = ValueNotifier<SyncGateState>(
    const SyncGateState(),
  );

  /// ✅ P0: إحصائيات وسجل الرفض — "تسجيل العمليات المرفوضة" يعمل في
  /// release أيضاً (dlog للطباعة فقط، هذا السجل دائم).
  final List<SyncGateRejection> _rejectionLog = <SyncGateRejection>[];
  int _totalEntered = 0;
  int _totalRejected = 0;
  int _totalStuckReleased = 0;
  int _generation = 0;

  /// اختصار للحالة الحالية.
  SyncGateState get state => notifier.value;

  /// هل البوّابة مشغولة الآن بأي عملية من أي مصدر؟
  bool get isBusy => notifier.value.isBusy;

  /// ✅ P0: رمز الحيازة الحالي — يُلتقط بعد tryEnter ناجح ويُمرَّر إلى
  /// [exit] لضمان أن صاحب الحيازة فقط من يحرّرها.
  int get activeToken => _generation;

  /// ✅ P0: عدد عمليات الدخول الناجحة منذ إقلاع التطبيق.
  int get totalEntered => _totalEntered;

  /// ✅ P0: عدد الطلبات المرفوضة لأن البوّابة مشغولة.
  int get totalRejected => _totalRejected;

  /// ✅ P0: عدد العمليات المتعثرة التي حُرّرت تلقائياً.
  int get totalStuckReleased => _totalStuckReleased;

  /// ✅ P0: آخر سجلات الرفض/التحرير التلقائي (الأحدث أخيراً).
  List<SyncGateRejection> get recentRejections =>
      List<SyncGateRejection>.unmodifiable(_rejectionLog);

  /// ✅ P0: لقطة إحصائيات جاهزة للعرض في شاشات التشخيص.
  Map<String, dynamic> get statsSnapshot => {
    'totalEntered': _totalEntered,
    'totalRejected': _totalRejected,
    'totalStuckReleased': _totalStuckReleased,
    'isBusy': isBusy,
    'currentOperation': state.operation,
    'currentSource': state.source,
    'elapsedMs': state.elapsedMs,
    'stuckTimeoutMin': stuckOperationTimeout.inMinutes,
    'rejectionLogSize': _rejectionLog.length,
  };

  /// تفريغ سجل الرفض (للاختبارات أو بعد تصديره).
  void clearRejectionLog() => _rejectionLog.clear();

  void _recordRejection({
    required String kind,
    required String requestedOperation,
    required String requestedSource,
  }) {
    final current = notifier.value;
    _rejectionLog.add(
      SyncGateRejection(
        at: DateTime.now(),
        kind: kind,
        requestedOperation: requestedOperation,
        requestedSource: requestedSource,
        busyWithOperation: current.operation,
        busyWithSource: current.source,
        busyElapsedMs: current.elapsedMs,
      ),
    );
    if (_rejectionLog.length > maxRejectionLogs) {
      _rejectionLog.removeAt(0);
    }
  }

  /// محاولة دخول البوّابة. تُرجع true إذا نجح الدخول، false إذا كانت
  /// البوّابة مشغولة بعملية أخرى.
  ///
  /// يجب أن تُستدعى **متزامناً قبل أي await** لمنع إعادة الدخول.
  ///
  /// ✅ P0: إذا كانت العملية الحائزة للبوّابة تجاوزت [stuckOperationTimeout]
  /// تُعتبَر متعثّرة وتُحرَّر تلقائياً (مع تسجيل الحدث)، ويدخل الطلب الجديد
  /// بدلاً منها. حيازة العملية القديمة يصبح رمزها قديماً — أي exit لاحق
  /// لها برمز قديم سيُتجاهَل بأمان.
  bool tryEnter({required String operation, required String source}) {
    if (notifier.value.isBusy) {
      final elapsedMs = notifier.value.elapsedMs ?? 0;
      final isStuck = elapsedMs >= stuckOperationTimeout.inMilliseconds;
      if (isStuck) {
        _totalStuckReleased++;
        _recordRejection(
          kind: 'stuck_released',
          requestedOperation: operation,
          requestedSource: source,
        );
        if (kDebugMode) {
          dlog(
            () =>
                '⏰ [SyncGate] auto-released STUCK operation '
                '${notifier.value.operation} from ${notifier.value.source} '
                '(held ${elapsedMs}ms > '
                '${stuckOperationTimeout.inMilliseconds}ms)',
          );
        }
        // السقوط للدخول الجديد أدناه — الحيازة القديمة أصبحت مهجورة.
      } else {
        _totalRejected++;
        _recordRejection(
          kind: 'rejected',
          requestedOperation: operation,
          requestedSource: source,
        );
        if (kDebugMode) {
          dlog(
            () =>
                '🚫 [SyncGate] rejected entry: already busy with '
                '${notifier.value.operation} from ${notifier.value.source} '
                '(total rejected: $_totalRejected)',
          );
        }
        return false;
      }
    }
    _generation++;
    _totalEntered++;
    notifier.value = SyncGateState(
      isBusy: true,
      operation: operation,
      source: source,
      startedAt: DateTime.now(),
      generation: _generation,
    );
    if (kDebugMode) {
      dlog(() => '🔒 [SyncGate] entered: $operation from $source');
    }
    return true;
  }

  /// تحرير البوّابة. يجب أن تُستدعى في finally block دائماً.
  ///
  /// ✅ P0: يُفضّل تمرير [token] (رمز [SyncGate.activeToken] الملتقط بعد
  /// دخول ناجح) — إذا كان الرمز قديماً (دخلت عملية أحدث بعد تحرير تلقائي
  /// لعملية متعثرة) يُتجاهَل التحرير حمايةً للحيازة الجديدة.
  /// الاستدعاء بلا رمز يحافظ على السلوك القديم (تحرير غير مشروط).
  void exit({int? token}) {
    if (!notifier.value.isBusy) {
      // Already idle — nothing to do. This is safe to call multiple times.
      return;
    }
    if (token != null && token != _generation) {
      if (kDebugMode) {
        dlog(
          () =>
              '⚠️ [SyncGate] ignored STALE exit (token=$token, '
              'current=$_generation, busy with '
              '${notifier.value.operation} from ${notifier.value.source})',
        );
      }
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
  }

  /// يُنفّذ [task] أثناء حيازة البوّابة. يُرجع null إذا كانت البوّابة
  /// مشغولة، وإلا يُرجع نتيجة [task].
  ///
  /// يضمن تحرير البوّابة في finally حتى لو فشل [task] برمي استثناء.
  /// ✅ P0: يستخدم رمز الحيازة لضمان تحرير حيازته فقط.
  Future<T?> runGuarded<T>({
    required String operation,
    required String source,
    required Future<T> Function() task,
  }) async {
    if (!tryEnter(operation: operation, source: source)) {
      return null;
    }
    final token = activeToken;
    try {
      return await task();
    } finally {
      exit(token: token);
    }
  }

  /// نفس [runGuarded] لكن للمهام التي لا تُرجع قيمة. يُرجع true إذا
  /// نُفّذت المهمة، false إذا رُفض الدخول.
  /// ✅ P0: يستخدم رمز الحيازة لضمان تحرير حيازته فقط.
  Future<bool> runGuardedVoid({
    required String operation,
    required String source,
    required Future<void> Function() task,
  }) async {
    if (!tryEnter(operation: operation, source: source)) {
      return false;
    }
    final token = activeToken;
    try {
      await task();
      return true;
    } finally {
      exit(token: token);
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
