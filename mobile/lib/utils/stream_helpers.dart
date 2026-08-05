import 'dart:async';
import 'package:flutter/foundation.dart';
// ✅ استخدمنا alias لتجنّب تعارض اسم الدالة signal<T>() مع الـ field/getter signal
// في الـ class StreamToSignal. بدون alias، يُفسّر Dart `signal<T>(...)` كمرجع
// للـ getter المحلي بدلاً من الدالة المستوردة من signals_flutter.
import 'package:signals_flutter/signals_flutter.dart'
import 'package:marina_hotel_mobile/utils/debug_log.dart';
    as signals
    show Signal, signal;

/// ✅ تأخير إصدار بيانات الـ Stream حتى تهدأ التغييرات.
Stream<T> debounceStream<T>(Stream<T> source, Duration duration) {
  Timer? timer;
  T? latest;

  return source.transform(
    StreamTransformer<T, T>.fromHandlers(
      handleData: (data, sink) {
        timer?.cancel();
        latest = data;
        timer = Timer(duration, () {
          if (latest != null) {
            sink.add(latest as T);
          }
        });
      },
      handleDone: (sink) {
        timer?.cancel();
        if (latest != null) {
          sink.add(latest as T);
        }
        sink.close();
      },
      handleError: (error, stack, sink) {
        timer?.cancel();
        sink.addError(error, stack);
      },
    ),
  );
}

/// ✅ P0: بديل StreamBuilder — Stream → ValueNotifier مع debounce.
/// أسرع من StreamBuilder لأنه لا يعيد بناء Widget tree بالكامل.
class StreamToValueNotifier<T> extends ValueNotifier<T> {
  StreamToValueNotifier({
    required Stream<T> source,
    required T initialValue,
    Duration? debounce,
  }) : super(initialValue) {
    var stream = source;
    if (debounce != null) {
      stream = debounceStream(stream, debounce);
    }
    _subscription = stream.listen(
      (data) {
        if (value != data) value = data;
      },
      onError: (Object error) {
        dlog(() => '❌ [StreamToValueNotifier] Stream error: $error');
      },
    );
  }

  StreamSubscription<T>? _subscription;

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

/// ✅ P0: Signals bridge — Stream → Signal (signals_flutter).
/// الأسرع على الإطلاق لأنه يحدّث الأجزاء المصابة فقط دون مس شجرة الـ Widget.
///
/// ## لماذا Signal أسرع من ValueNotifier؟
/// - Signal يخزّن القيمة في الذاكرة مباشرة (لا يمر عبر Widget tree)
/// - Signal يقارن التغييرات بدقة ذرية (يعرف بالضبط أي جزء تغير)
/// - تأثير جانبي صفري (Zero side-effect) على Widgets غير المتأثرة
///
/// ## الاستخدام مع signals_flutter:
/// ```dart
/// final signal = StreamToSignal(
///   source: repo.watchAll(),
///   initialValue: <Item>[],
/// );
///
/// // في build:
/// Watch((context) => myWidget(signal.signal.value))
/// ```
class StreamToSignal<T> {
  StreamToSignal({
    required Stream<T> source,
    required T initialValue,
    Duration? debounce,
  }) : _signal = signals.signal<T>(initialValue) {
    var stream = source;
    if (debounce != null) {
      stream = debounceStream(stream, debounce);
    }
    _subscription = stream.listen(
      (data) {
        _signal.value = data;
      },
      onError: (Object error) {
        dlog(() => '❌ [StreamToSignal] Stream error: $error');
      },
    );
  }

  StreamSubscription<T>? _subscription;
  // ✅ استخدمنا _signal (خاص) بدلاً من signal لتجنّب تعارض الاسم مع الدالة
  // signal<T>() من signals_flutter — كان يسبب 4 أخطاء compilation لأن Dart
  // يُفسّر `signal = signal<T>(...)` كمرجع للـ field نفسه (recursive) وليس للدالة.
  final signals.Signal<T> _signal;

  /// وصول للـ Signal للقراءة فقط (للاستخدام مع Watch/effect في signals_flutter).
  signals.Signal<T> get signal => _signal;

  /// تنظيف الموارد
  void dispose() {
    _subscription?.cancel();
    _signal.dispose();
  }
}
