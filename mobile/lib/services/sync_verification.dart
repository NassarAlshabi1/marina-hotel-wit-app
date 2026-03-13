/// ═══════════════════════════════════════════════════════════════════════════════
/// التحقق من المزامنة - Sync Verification
/// ═══════════════════════════════════════════════════════════════════════════════
/// 
/// يوفر دوال للتحقق من أن البيانات المرسلة إلى Appwrite تحتوي على
/// الحقول المطلوبة بصيغة camelCase.
///
/// ⭐ الاستخدام:
/// ```dart
/// final result = await SyncVerification.verifyBeforePush(payload, 'bookings');
/// if (!result.isValid) {
///   print('Missing fields: ${result.missingFields}');
/// }
/// ```
/// ═══════════════════════════════════════════════════════════════════════════════

import 'package:flutter/foundation.dart';
import 'adapters/key_converter.dart';

/// نتيجة التحقق من الـ payload
class VerificationResult {
  VerificationResult({
    required this.isValid,
    required this.missingFields,
    required this.snakeCaseFields,
    required this.fixedPayload,
    this.warnings = const [],
  });

  /// هل الـ payload صالح للإرسال
  final bool isValid;

  /// الحقول المفقودة (المطلوبة في Appwrite)
  final List<String> missingFields;

  /// الحقول بصيغة snake_case (يجب تحويلها)
  final List<String> snakeCaseFields;

  /// الـ payload بعد الإصلاح (إذا طُلب)
  final Map<String, dynamic> fixedPayload;

  /// تحذيرات إضافية
  final List<String> warnings;

  @override
  String toString() {
    if (isValid) return 'VerificationResult: Valid ✅';
    final buffer = StringBuffer('VerificationResult: Invalid ❌\n');
    if (missingFields.isNotEmpty) {
      buffer.writeln('  Missing fields: ${missingFields.join(', ')}');
    }
    if (snakeCaseFields.isNotEmpty) {
      buffer.writeln('  Snake case fields: ${snakeCaseFields.join(', ')}');
    }
    return buffer.toString();
  }
}

/// الحقول المطلوبة في كل collection
const kRequiredFieldsPerCollection = <String, Set<String>>{
  'bookings': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'roomNumber', 'guestName', 'checkinDate', 'status',
  },
  'rooms': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'roomNumber', 'roomType', 'basePrice',
  },
  'payments': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'amount', 'paymentDate', 'paymentMethod', 'revenueType',
  },
  'expenses': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'expenseType', 'amount', 'date',
  },
  'employees': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'name', 'basicSalary',
  },
  'debts': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'guestName', 'totalAmount', 'remainingAmount',
  },
  'salary_cycles': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'cycleKey',
  },
  'salary_payments': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'employeeId', 'amount',
  },
  'salary_withdrawals': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'employeeId', 'amount', 'date',
  },
  'shift_notes': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'noteText',
  },
  'booking_notes': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'bookingUuid', 'noteText',
  },
  'booking_nights': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'bookingUuid', 'nightDate',
  },
  'cash_transactions': {
    'localUuid', 'createdAt', 'updatedAt', 'lastModified',
    'vectorClock', 'deviceId', 'syncTimestamp',
    'transactionType', 'amount',
  },
};

/// الحقول المطلوبة في جميع collections
const kGlobalRequiredFields = {
  'localUuid',
  'createdAt',
  'updatedAt',
  'lastModified',
  'vectorClock',
  'deviceId',
  'syncTimestamp',
};

/// ═══════════════════════════════════════════════════════════════════════════════
/// دوال التحقق
/// ═══════════════════════════════════════════════════════════════════════════════

class SyncVerification {
  /// التحقق من payload قبل الإرسال إلى Appwrite
  ///
  /// [payload] - البيانات المراد إرسالها
  /// [collectionEntity] - اسم الـ collection (مثل 'bookings', 'rooms')
  /// [autoFix] - إذا كان true، يقوم بإصلاح المشاكل تلقائياً
  static VerificationResult verifyBeforePush(
    Map<String, dynamic> payload, {
    required String collectionEntity,
    bool autoFix = true,
    String? deviceId,
    int? syncTimestamp,
  }) {
    final missingFields = <String>[];
    final snakeCaseFields = <String>[];
    final warnings = <String>[];
    
    // التحقق من الحقول المطلوبة عالمياً
    for (final field in kGlobalRequiredFields) {
      if (!payload.containsKey(field) || payload[field] == null) {
        // التحقق من وجود snake_case alternative
        final snakeField = camelToSnakeCase(field);
        if (!payload.containsKey(snakeField) || payload[snakeField] == null) {
          missingFields.add(field);
        }
      }
    }
    
    // التحقق من الحقول المطلوبة للـ collection المحدد
    final collectionRequired = kRequiredFieldsPerCollection[collectionEntity];
    if (collectionRequired != null) {
      for (final field in collectionRequired) {
        if (!payload.containsKey(field) || payload[field] == null) {
          final snakeField = camelToSnakeCase(field);
          if (!payload.containsKey(snakeField) || payload[snakeField] == null) {
            if (!missingFields.contains(field)) {
              missingFields.add(field);
            }
          }
        }
      }
    }
    
    // اكتشاف الحقول بصيغة snake_case
    for (final key in payload.keys) {
      if (_isSnakeCase(key)) {
        snakeCaseFields.add(key);
      }
    }
    
    // بناء الـ fixed payload إذا طُلب
    Map<String, dynamic> fixedPayload = Map<String, dynamic>.from(payload);
    
    if (autoFix) {
      // تحويل snake_case إلى camelCase
      if (snakeCaseFields.isNotEmpty) {
        fixedPayload = convertKeysToCamelCase(fixedPayload);
        warnings.add('تم تحويل ${snakeCaseFields.length} حقل من snake_case إلى camelCase');
      }
      
      // إضافة الحقول المفقودة
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      
      fixedPayload['localUuid'] ??= payload['local_uuid'] ?? payload['localUuid'];
      fixedPayload['createdAt'] ??= payload['created_at'] ?? payload['createdAtEpoch'] ?? now;
      fixedPayload['updatedAt'] ??= now;
      fixedPayload['lastModified'] ??= payload['last_modified'] ?? now;
      fixedPayload['vectorClock'] ??= payload['vector_clock'] ?? '{}';
      fixedPayload['deviceId'] ??= deviceId ?? 'unknown';
      fixedPayload['syncTimestamp'] ??= syncTimestamp ?? now;
      fixedPayload['version'] ??= payload['version'] ?? 1;
      fixedPayload['origin'] ??= payload['origin'] ?? 'local';
      
      // إزالة حقول snake_case المكررة
      final keysToRemove = fixedPayload.keys
          .where((k) => _isSnakeCase(k))
          .toList();
      for (final key in keysToRemove) {
        fixedPayload.remove(key);
      }
    }
    
    final isValid = missingFields.isEmpty;
    
    return VerificationResult(
      isValid: isValid,
      missingFields: missingFields,
      snakeCaseFields: snakeCaseFields,
      fixedPayload: fixedPayload,
      warnings: warnings,
    );
  }
  
  /// التحقق من payload مستلم من Appwrite
  ///
  /// يجب أن تكون جميع الحقول camelCase
  static VerificationResult verifyAfterPull(
    Map<String, dynamic> payload, {
    required String collectionEntity,
  }) {
    final snakeCaseFields = <String>[];
    final warnings = <String>[];
    
    // اكتشاف أي حقول snake_case (غير متوقعة من Appwrite)
    for (final key in payload.keys) {
      if (_isSnakeCase(key)) {
        snakeCaseFields.add(key);
      }
    }
    
    // إضافة snake_case للتوافق المحلي
    final fixedPayload = Map<String, dynamic>.from(payload);
    for (final key in payload.keys) {
      if (!_isSnakeCase(key)) {
        final snakeKey = camelToSnakeCase(key);
        fixedPayload[snakeKey] ??= payload[key];
      }
    }
    
    if (snakeCaseFields.isNotEmpty) {
      warnings.add('تم استلام ${snakeCaseFields.length} حقل snake_case من Appwrite (غير متوقع)');
    }
    
    return VerificationResult(
      isValid: true, // Pull always succeeds
      missingFields: [],
      snakeCaseFields: snakeCaseFields,
      fixedPayload: fixedPayload,
      warnings: warnings,
    );
  }
  
  /// طباعة تقرير التحقق (للتطوير)
  static void printVerificationReport(
    VerificationResult result, {
    String? title,
  }) {
    if (!kDebugMode) return;
    
    debugPrint('═══════════════════════════════════════════');
    debugPrint(title ?? '📦 Sync Verification Report');
    debugPrint('═══════════════════════════════════════════');
    debugPrint('Valid: ${result.isValid ? "✅ Yes" : "❌ No"}');
    
    if (result.missingFields.isNotEmpty) {
      debugPrint('Missing Fields (${result.missingFields.length}):');
      for (final field in result.missingFields) {
        debugPrint('  - $field');
      }
    }
    
    if (result.snakeCaseFields.isNotEmpty) {
      debugPrint('Snake Case Fields (${result.snakeCaseFields.length}):');
      for (final field in result.snakeCaseFields) {
        debugPrint('  - $field → ${snakeToCamelCase(field)}');
      }
    }
    
    if (result.warnings.isNotEmpty) {
      debugPrint('Warnings:');
      for (final warning in result.warnings) {
        debugPrint('  ⚠️ $warning');
      }
    }
    
    debugPrint('═══════════════════════════════════════════');
  }
  
  /// التحقق من أن المفتاح بصيغة snake_case
  static bool _isSnakeCase(String input) {
    return input.contains('_') && input.toLowerCase() == input;
  }
  
  /// مقارنة payload محلي مع payload بعيد
  ///
  /// يعيد Map يحتوي على الفروقات
  static Map<String, dynamic> comparePayloads(
    Map<String, dynamic> local,
    Map<String, dynamic> remote,
  ) {
    final differences = <String, dynamic>{};
    
    // توحيد المفاتيح إلى camelCase للمقارنة
    final localCamel = convertKeysToCamelCase(local);
    final remoteCamel = convertKeysToCamelCase(remote);
    
    final allKeys = {...localCamel.keys, ...remoteCamel.keys};
    
    for (final key in allKeys) {
      final localVal = localCamel[key];
      final remoteVal = remoteCamel[key];
      
      if (localVal != remoteVal) {
        differences[key] = {
          'local': localVal,
          'remote': remoteVal,
        };
      }
    }
    
    return differences;
  }
}
