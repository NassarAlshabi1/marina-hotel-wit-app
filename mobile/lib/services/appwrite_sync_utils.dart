import '../utils/hotel_date_helper.dart';

/// فئة أدوات موحدة لمعالجة البيانات قبل إرسالها أو بعد سحبها من Appwrite
class AppwriteSyncUtils {
  /// الحقول التي يجب تحويلها إلى أعداد صحيحة (بناءً على قيود Appwrite الحالية)
  /// ملاحظة: يفضل مستقبلاً تغيير هذه الحقول في Appwrite إلى double
  static const Map<String, Set<String>> _intAmountFields = {
    'booking_price_adjustments': {'amount'},
    'cash_transactions': {'amount'},
    'salary_withdrawals': {'amount'},
    'debts': {'amount', 'remainingAmount'},
  };

  /// تطهير البيانات وإزالة الحقول غير المدعومة أو المحسوبة
  static Map<String, dynamic> sanitizePayload(
    String entity,
    Map<String, dynamic> payload, {
    String? collectionId,
  }) {
    var result = Map<String, dynamic>.from(payload);

    // 1. إزالة الحقول المحسوبة التي لا تُخزن في Appwrite
    result = HotelDateHelper.stripComputedFieldsForEntity(entity, result);

    // 2. إزالة الحقول التقنية الخاصة بـ Drift أو Appwrite metadata إذا وجدت
    result.remove('id'); // المعرف المحلي التلقائي
    result.remove('\u0024id');
    result.remove('\u0024createdAt');
    result.remove('\u0024updatedAt');
    result.remove('\u0024permissions');
    result.remove('\u0024databaseId');
    result.remove('\u0024collectionId');

    // 3. تحويل الأنواع المالية إذا لزم الأمر
    if (collectionId != null) {
      result = convertAmountTypesForAppwrite(collectionId, result);
    }

    return result;
  }

  /// تحويل حقول المبالغ إلى أعداد صحيحة للمجموعات التي تتطلب ذلك
  static Map<String, dynamic> convertAmountTypesForAppwrite(
    String collectionId,
    Map<String, dynamic> payload,
  ) {
    final intFields = _intAmountFields[collectionId];
    if (intFields == null || intFields.isEmpty) return payload;

    final result = Map<String, dynamic>.from(payload);
    for (final field in intFields) {
      if (result.containsKey(field) && result[field] is num) {
        result[field] = (result[field] as num).round();
      }
    }
    return result;
  }

  /// تحويل أسماء الحقول من snake_case إلى camelCase (للتوافق مع Appwrite)
  static String toCamelCase(String input) {
    if (!input.contains('_')) return input;
    final parts = input.split('_');
    final first = parts.first;
    final rest = parts
        .skip(1)
        .map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}');
    return '$first${rest.join()}';
  }
}
