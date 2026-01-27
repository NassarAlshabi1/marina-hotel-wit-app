class LoadState<T> {
  const LoadState._(this.data, this.error, this.isLoading);

  final T? data;
  final Object? error;
  final bool isLoading;

  static LoadState<T> loading<T>() => LoadState._(null, null, true);
  static LoadState<T> success<T>(T value) => LoadState._(value, null, false);
  static LoadState<T> failure<T>(Object error) =>
      LoadState._(null, error, false);

  bool get hasData => data != null;
  bool get hasError => error != null;
}
