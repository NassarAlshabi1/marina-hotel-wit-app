import 'package:flutter/foundation.dart';

class ValidationResult {
  final bool isValid;
  final String? error;
  final List<String> warnings;

  ValidationResult({required this.isValid, this.error, List<String>? warnings})
    : warnings = warnings ?? [];

  factory ValidationResult.valid({List<String>? warnings}) {
    return ValidationResult(isValid: true, warnings: warnings);
  }

  factory ValidationResult.invalid(String error, {List<String>? warnings}) {
    return ValidationResult(isValid: false, error: error, warnings: warnings);
  }
}

class SyncValidator {
  static SyncValidator? _instance;
  static SyncValidator get instance => _instance ??= SyncValidator._();

  SyncValidator._();

  ValidationResult validateSyncData(Map<String, dynamic> data) {
    final warnings = <String>[];

    if (data.isEmpty) {
      return ValidationResult.invalid('البيانات فارغة');
    }

    if (!data.containsKey('timestamp')) {
      warnings.add('لا يوجد timestamp في البيانات');
    }

    if (data.containsKey('timestamp')) {
      try {
        DateTime.parse(data['timestamp'] as String);
      } catch (e) {
        return ValidationResult.invalid('timestamp غير صالح');
      }
    }

    final dataSize = _estimateSize(data);
    if (dataSize > 10 * 1024 * 1024) {
      return ValidationResult.invalid('حجم البيانات كبير جدًا (> 10MB)');
    } else if (dataSize > 5 * 1024 * 1024) {
      warnings.add('حجم البيانات كبير (> 5MB)');
    }

    return ValidationResult.valid(warnings: warnings.isEmpty ? null : warnings);
  }

  ValidationResult validateNetworkConditions({
    required bool hasConnection,
    int? signalStrength,
    bool? isWifi,
  }) {
    final warnings = <String>[];

    if (!hasConnection) {
      return ValidationResult.invalid('لا يوجد اتصال بالإنترنت');
    }

    if (signalStrength != null && signalStrength < 30) {
      warnings.add('إشارة الشبكة ضعيفة');
    }

    if (isWifi != null && !isWifi) {
      warnings.add('الاتصال عبر بيانات الجوال قد يكون أبطأ');
    }

    return ValidationResult.valid(warnings: warnings.isEmpty ? null : warnings);
  }

  ValidationResult validateStorageSpace(int requiredBytes) {
    return ValidationResult.valid();
  }

  ValidationResult validateConflictResolution(
    Map<String, dynamic> localData,
    Map<String, dynamic> remoteData,
  ) {
    final warnings = <String>[];

    if (localData['timestamp'] == null || remoteData['timestamp'] == null) {
      return ValidationResult.invalid('timestamps مفقودة للمقارنة');
    }

    try {
      final localTime = DateTime.parse(localData['timestamp'] as String);
      final remoteTime = DateTime.parse(remoteData['timestamp'] as String);

      final difference = localTime.difference(remoteTime).abs();
      if (difference > const Duration(hours: 24)) {
        warnings.add('فرق كبير في التوقيت بين البيانات المحلية والسحابية');
      }
    } catch (e) {
      return ValidationResult.invalid('فشل تحليل timestamps');
    }

    return ValidationResult.valid(warnings: warnings.isEmpty ? null : warnings);
  }

  int _estimateSize(dynamic data) {
    if (data == null) return 0;
    if (data is String) return data.length;
    if (data is int) return 8;
    if (data is double) return 8;
    if (data is bool) return 1;
    if (data is List) {
      return data.fold(0, (sum, item) => sum + _estimateSize(item));
    }
    if (data is Map) {
      int size = 0;
      data.forEach((key, value) {
        size += _estimateSize(key) + _estimateSize(value);
      });
      return size;
    }
    return data.toString().length;
  }

  void logValidationResult(String context, ValidationResult result) {
    if (result.isValid) {
      debugPrint('✅ [Validation] $context: صالح');
      if (result.warnings.isNotEmpty) {
        for (final warning in result.warnings) {
          debugPrint('⚠️ [Validation] تحذير: $warning');
        }
      }
    } else {
      debugPrint('❌ [Validation] $context: غير صالح - ${result.error}');
    }
  }
}
