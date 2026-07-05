import 'dart:async';

/// تأخير إصدار بيانات الـ Stream حتى تهدأ التغييرات.
/// يمنع إعادة بناء الـ UI عدة مرات عند ورود تغييرات متتالية.
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
