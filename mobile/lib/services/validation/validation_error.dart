/// خطأ في التحقق من صحة البيانات
class ValidationError {
  final String field;
  final String message;
  final dynamic value;

  const ValidationError({
    required this.field,
    required this.message,
    this.value,
  });

  @override
  String toString() => '$field: $message';
}

/// استثناء يُرمى عند فشل التحقق من صحة البيانات
class ValidationException implements Exception {
  final List<ValidationError> errors;

  const ValidationException(this.errors);

  String get message {
    if (errors.length == 1) {
      return errors.first.toString();
    }
    return 'فشل التحقق من صحة البيانات:\n${errors.map((e) => '- ${e.toString()}').join('\n')}';
  }

  @override
  String toString() => 'ValidationException: $message';
}
