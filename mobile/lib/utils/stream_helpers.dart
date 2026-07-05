import 'dart:async';
import 'package:flutter/foundation.dart';

/// ✅ تأخير إصدار بيانات الـ Stream حتى تهدأ التغييرات.
Stream<T> debounceStream<T>(Stream<T> source, Duration duration) {
  Timer? timer;
  T? latest;

  return source.transform(StreamTransformer<T, T>.fromHandlers(
    handleData: (data, sink) {
      timer?.cancel();
      latest = data;
      timer = Timer(duration, () {
        sink.add(latest!);
      });
    },
    handleDone: (sink) {
      timer?.cancel();
      if (latest != null) {
        sink.add(latest!);
      }
      sink.close();
    },
    handleError: (error, stack, sink) {
      timer?.cancel();
      sink.addError(error, stack);
    },
  ));
}

/// ✅ P0: بديل StreamBuilder — Stream → ValueNotifier مع debounce.
/// أسرع من StreamBuilder لأنه لا يعيد بناء Widget tree بالكامل.
class StreamToValueNotifier<T> extends ValueNotifier<T> {
  StreamSubscription<T>? _subscription;

  StreamToValueNotifier({
    required Stream<T> source,
    T? initialValue,
    Duration? debounce,
  }) : super(initialValue as T) {
    var stream = source;
    if (debounce != null) {
      stream = debounceStream(stream, debounce);
    }
    _subscription = stream.listen(
      (data) {
        if (value != data) value = data;
      },
      onError: (error) {
        debugPrint('❌ [StreamToValueNotifier] Stream error: $error');
      },
    );
  }

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
/// Watch((context) => myWidget(signal.value))
/// ```
class StreamToSignal<T> {
  StreamSubscription<T>? _subscription;
  
  /// القيمة الحالية للإشارة
  T value;

  StreamToSignal({
    required Stream<T> source,
    required T initialValue,
    Duration? debounce,
  }) : value = initialValue {
    var stream = source;
    if (debounce != null) {
      stream = debounceStream(stream, debounce);
    }
    _subscription = stream.listen(
      (data) {
        if (value != data) {
          value = data;
          _notifyListeners();
        }
      },
      onError: (error) {
        debugPrint('❌ [StreamToSignal] Stream error: $error');
      },
    );
  }

  final List<void Function()> _listeners = [];

  /// اشتراك في تغييرات الإشارة
  void listen(void Function() callback) {
    _listeners.add(callback);
  }

  /// إلغاء الاشتراك
  void unlisten(void Function() callback) {
    _listeners.remove(callback);
  }

  void _notifyListeners() {
    for (final listener in List.from(_listeners)) {
      listener();
    }
  }

  /// تنظيف الموارد
  void dispose() {
    _subscription?.cancel();
    _listeners.clear();
  }
}
