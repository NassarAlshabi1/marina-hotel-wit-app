import 'validation_error.dart';

/// قواعد التحقق من صحة البيانات
class ValidationRules {
  /// التحقق من أن القيمة ليست فارغة
  static ValidationError? required(String field, String? value) {
    if (value == null || value.trim().isEmpty) {
      return ValidationError(
        field: field,
        message: 'الحقل مطلوب',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من الحد الأدنى لطول النص
  static ValidationError? minLength(String field, String? value, int min) {
    if (value != null && value.trim().length < min) {
      return ValidationError(
        field: field,
        message: 'يجب أن يكون الطول $min حرف على الأقل',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من الحد الأقصى لطول النص
  static ValidationError? maxLength(String field, String? value, int max) {
    if (value != null && value.length > max) {
      return ValidationError(
        field: field,
        message: 'يجب ألا يتجاوز الطول $max حرف',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من أن الرقم أكبر من قيمة معينة
  static ValidationError? greaterThan(
    String field,
    num? value,
    num min, {
    bool inclusive = false,
  }) {
    if (value == null) return null;

    final condition = inclusive ? value < min : value <= min;
    if (condition) {
      return ValidationError(
        field: field,
        message: inclusive
            ? 'يجب أن يكون أكبر من أو يساوي $min'
            : 'يجب أن يكون أكبر من $min',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من أن الرقم أقل من قيمة معينة
  static ValidationError? lessThan(
    String field,
    num? value,
    num max, {
    bool inclusive = false,
  }) {
    if (value == null) return null;

    final condition = inclusive ? value > max : value >= max;
    if (condition) {
      return ValidationError(
        field: field,
        message: inclusive
            ? 'يجب أن يكون أقل من أو يساوي $max'
            : 'يجب أن يكون أقل من $max',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من أن القيمة موجبة
  static ValidationError? positive(String field, num? value) {
    if (value != null && value <= 0) {
      return ValidationError(
        field: field,
        message: 'يجب أن يكون أكبر من صفر',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من أن القيمة غير سالبة
  static ValidationError? nonNegative(String field, num? value) {
    if (value != null && value < 0) {
      return ValidationError(
        field: field,
        message: 'يجب ألا يكون سالباً',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من صيغة رقم الهاتف
  static ValidationError? phoneFormat(String field, String? value) {
    if (value == null || value.isEmpty) return null;

    final digitsOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length < 9 || digitsOnly.length > 15) {
      return ValidationError(
        field: field,
        message: 'صيغة رقم الهاتف غير صحيحة',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من صيغة التاريخ (ISO8601)
  static ValidationError? dateFormat(String field, String? value) {
    if (value == null || value.isEmpty) return null;

    try {
      DateTime.parse(value);
      return null;
    } catch (e) {
      return ValidationError(
        field: field,
        message: 'صيغة التاريخ غير صحيحة',
        value: value,
      );
    }
  }

  /// التحقق من أن التاريخ في المستقبل
  static ValidationError? futureDate(String field, String? value) {
    if (value == null || value.isEmpty) return null;

    try {
      final date = DateTime.parse(value);
      if (date.isBefore(DateTime.now())) {
        return ValidationError(
          field: field,
          message: 'يجب أن يكون في المستقبل',
          value: value,
        );
      }
      return null;
    } catch (e) {
      return ValidationError(
        field: field,
        message: 'صيغة التاريخ غير صحيحة',
        value: value,
      );
    }
  }

  /// التحقق من أن التاريخ في الماضي
  static ValidationError? pastDate(String field, String? value) {
    if (value == null || value.isEmpty) return null;

    try {
      final date = DateTime.parse(value);
      if (date.isAfter(DateTime.now())) {
        return ValidationError(
          field: field,
          message: 'يجب أن يكون في الماضي',
          value: value,
        );
      }
      return null;
    } catch (e) {
      return ValidationError(
        field: field,
        message: 'صيغة التاريخ غير صحيحة',
        value: value,
      );
    }
  }

  /// التحقق من أن date1 قبل date2
  static ValidationError? dateBefore(
    String field,
    String? date1,
    String? date2,
    String date2Label,
  ) {
    if (date1 == null || date2 == null) return null;

    try {
      final d1 = DateTime.parse(date1);
      final d2 = DateTime.parse(date2);
      if (d1.isAfter(d2) || d1.isAtSameMomentAs(d2)) {
        return ValidationError(
          field: field,
          message: 'يجب أن يكون قبل $date2Label',
          value: date1,
        );
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  /// التحقق من أن القيمة ضمن مجموعة محددة
  static ValidationError? oneOf<T>(
    String field,
    T? value,
    List<T> allowedValues,
  ) {
    if (value != null && !allowedValues.contains(value)) {
      return ValidationError(
        field: field,
        message: 'قيمة غير صالحة',
        value: value,
      );
    }
    return null;
  }

  /// التحقق من UUID format
  static ValidationError? uuidFormat(String field, String? value) {
    if (value == null || value.isEmpty) return null;

    final uuidRegex = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    );

    if (!uuidRegex.hasMatch(value)) {
      return ValidationError(
        field: field,
        message: 'صيغة UUID غير صحيحة',
        value: value,
      );
    }
    return null;
  }
}
