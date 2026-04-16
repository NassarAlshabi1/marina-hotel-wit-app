import 'package:drift/drift.dart';

/// Serializer يسمح بالتعامل مع قيم null أو أنواع غير متوقعة أثناء تحويل JSON
/// لضمان التوافق مع النسخ الاحتياطية الأقدم.
class LenientValueSerializer extends ValueSerializer {
  const LenientValueSerializer();

  Type _typeOf<X>() => X;

  bool _isNullable<T>() => null is T;

  bool _isIntType<T>() {
    final type = _typeOf<T>();
    return type == int || type == _typeOf<int?>();
  }

  bool _isDoubleType<T>() {
    final type = _typeOf<T>();
    return type == double || type == _typeOf<double?>();
  }

  bool _isStringType<T>() {
    final type = _typeOf<T>();
    return type == String || type == _typeOf<String?>();
  }

  bool _isBoolType<T>() {
    final type = _typeOf<T>();
    return type == bool || type == _typeOf<bool?>();
  }

  @override
  T fromJson<T>(dynamic json) {
    final defaultSerializer = driftRuntimeOptions.defaultSerializer;

    if (json == null) {
      if (_isNullable<T>()) return json as T;
      if (_isIntType<T>()) return 0 as T;
      if (_isDoubleType<T>()) return 0.0 as T;
      if (_isBoolType<T>()) return false as T;
      if (_isStringType<T>()) return '' as T;
      return defaultSerializer.fromJson<T>(json);
    }

    if (_isIntType<T>()) {
      if (json is int) return json as T;
      if (json is double) return json.toInt() as T;
      if (json is num) return json.toInt() as T;
      if (json is String) {
        final trimmed = json.trim();
        if (trimmed.isEmpty) {
          return (_isNullable<T>() ? null : 0) as T;
        }
        // إذا كان النص يحتوي على UUID أو قيم غير رقمية، نعيد null أو 0
        if (trimmed.contains('-') || trimmed.length > 20) {
          return (_isNullable<T>() ? null : 0) as T;
        }
        final parsed = int.tryParse(trimmed);
        if (parsed == null) {
          return (_isNullable<T>() ? null : 0) as T;
        }
        return parsed as T;
      }
      if (json is bool) return (json ? 1 : 0) as T;
    }

    if (_isDoubleType<T>()) {
      if (json is double) return json as T;
      if (json is int) return json.toDouble() as T;
      if (json is num) return json.toDouble() as T;
      if (json is String) {
        final trimmed = json.trim();
        if (trimmed.isEmpty) return 0.0 as T;
        final parsed = double.tryParse(trimmed);
        return (parsed ?? 0.0) as T;
      }
      if (json is bool) return (json ? 1.0 : 0.0) as T;
    }

    if (_isBoolType<T>()) {
      if (json is bool) return json as T;
      if (json is num) return (json != 0) as T;
      if (json is String) {
        final lower = json.trim().toLowerCase();
        if (lower.isEmpty) return false as T;
        if (lower == '1' || lower == 'true') return true as T;
        if (lower == '0' || lower == 'false') return false as T;
      }
    }

    if (_isStringType<T>()) {
      if (json is String) return json as T;
      return json.toString() as T;
    }

    return defaultSerializer.fromJson<T>(json);
  }

  @override
  dynamic toJson<T>(T value) => value;
}

const lenientValueSerializer = LenientValueSerializer();
