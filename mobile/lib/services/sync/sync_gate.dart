// TODO(phase-2): remove this ignore and fix violations (discarded_futures)
// ignore_for_file: discarded_futures
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  /// مدة العملية الحالية بالمللي ثانية، أو null إذا لم تكن مشغولة.
  int? get elapsedMs => isBusy && startedAt != null
      ? DateTime.now().difference(startedAt!).inMilliseconds
      : null;

  SyncGateState copyWith({
    bool? isBusy,
    String? operation,
    String? source,
    DateTime? startedAt,
    bool clearOperation = false,
    bool clearSource = false,
    bool clearStartedAt = false,
  }) {
    return SyncGateState(
      isBusy: isBusy ?? this.isBusy,
      operation: clearOperation ? null : (operation ?? this.operation),
      source: clearSource ? null : (source ?? this.source),
      startedAt: clearStartedAt ? null : (startedAt ?? this.startedAt),
    );
  }

  @override
  String toString() =>
      'SyncGateState(isBusy=$isBusy, operation=$operation, source=$source, '
      'startedAt=$startedAt)';
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

  /// منفذ عام يمكن لأي عنصر واجهة مراقبته عبر `ValueListenableBuilder`.
  final ValueNotifier<SyncGateState> notifier = ValueNotifier<SyncGateState>(
    const SyncGateState(),
  );

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
      if (kDebugMode) {
        debugPrint(
          '🚫 [SyncGate] rejected entry: already busy with '
          '${notifier.value.operation} from ${notifier.value.source}',
        );
      }
      return false;
    }
    notifier.value = SyncGateState(
      isBusy: true,
      operation: operation,
      source: source,
      startedAt: DateTime.now(),
    );
    if (kDebugMode) {
      debugPrint('🔒 [SyncGate] entered: $operation from $source');
    }
    return true;
  }

  /// تحرير البوّابة. يجب أن تُستدعى في finally block دائماً.
  void exit() {
    if (!notifier.value.isBusy) {
      // Already idle — nothing to do. This is safe to call multiple times.
      return;
    }
    if (kDebugMode) {
      final elapsed = notifier.value.elapsedMs;
      debugPrint(
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
  Future<T?> runGuarded<T>({
    required String operation,
    required String source,
    required Future<T> Function() task,
  }) async {
    if (!tryEnter(operation: operation, source: source)) {
      return null;
    }
    try {
      return await task();
    } finally {
      exit();
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
    try {
      await task();
      return true;
    } finally {
      exit();
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
    controller.close();
  });
  // البث الأول للحالة الحالية
  controller.add(SyncGate.instance.notifier.value);
  return controller.stream;
});
