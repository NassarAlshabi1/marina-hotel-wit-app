import 'package:drift/drift.dart';

/// Serializer يسمح بالتعامل مع قيم null أو أنواع غير متوقعة أثناء تحويل JSON
/// لضمان التوافق مع النسخ الاحتياطية الأقدم.
class LenientValueSerializer extends ValueSerializer {
  const LenientValueSerializer();

  bool _isIntType<T>() => T == int || null is T;
  bool _isDoubleType<T>() => T == double || null is T;
  bool _isStringType<T>() => T == String || null is T;
  bool _isBoolType<T>() => T == bool || null is T;

  @override
  T fromJson<T>(dynamic json) {
    if (json == null) {
      if (_isIntType<T>()) return 0 as T;
      if (_isDoubleType<T>()) return 0.0 as T;
      if (_isBoolType<T>()) return false as T;
      if (_isStringType<T>()) return '' as T;
      return super.fromJson<T>(json);
    }

    if (_isIntType<T>()) {
      if (json is int) return json as T;
      if (json is double) return json.toInt() as T;
      if (json is num) return json.toInt() as T;
      if (json is String) {
        final trimmed = json.trim();
        if (trimmed.isEmpty) return 0 as T;
        final parsed = int.tryParse(trimmed);
        return (parsed ?? 0) as T;
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

    return super.fromJson<T>(json);
  }

  @override
  dynamic toJson<T>(T value) => value;
}

const lenientValueSerializer = LenientValueSerializer();
