import 'dart:async';
import 'package:flutter/foundation.dart';
import 'debug_log.dart';

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
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}
