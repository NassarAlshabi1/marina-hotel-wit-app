import '../utils/hotel_date_helper.dart';

/// فئة أدوات موحدة لمعالجة البيانات قبل إرسالها أو بعد سحبها من Appwrite
class AppwriteSyncUtils {
  /// الحقول التي يجب تحويلها إلى أعداد صحيحة (بناءً على قيود Appwrite الحالية)
  /// ⚠️ تم التحديث بناءً على فحص Appwrite Cloud الفعلي (2026-05-15)
  /// - cash_transactions.amount: integer على Cloud ✓
  /// - salary_withdrawals.amount: integer على Cloud ✓
  /// - payment_voids.voidedAmount: integer على Cloud ✓
  /// - booking_price_adjustments.amount: integer على Cloud ✓ (أُضيف 2026-05-15)
  /// - debts.remainingAmount: integer على Cloud ✓ (أُضيف 2026-05-15)
  /// - debts.totalAmount/paidAmount: double على Cloud (لا تحتاج تحويل)
  static const Map<String, Set<String>> _intAmountFields = {
    'cash_transactions': {'amount'},
    'salary_withdrawals': {'amount'},
    'payment_voids': {'voidedAmount'},
    'booking_price_adjustments': {'amount'},
    'debts': {'remainingAmount'},
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

    // 3. إزالة حقول Delta Sync الداخلية التي لا وجود لها في مخطط Appwrite
    //    هذه الحقول تُضاف بواسطة DeltaSyncService.compute() و _preparePayload()
    result.remove('row_hash');       // حقل داخلي — ليس في أي مجموعة Appwrite
    result.remove('client_ts');      // حقل داخلي

    // 4. تحويل أسماء الحقول من snake_case إلى camelCase
    //    ⚠️ حرج: Appwrite Cloud يستخدم camelCase في جميع المجموعات المتزامنة
    //    (deletedAt, lastModified, localUuid, إلخ)
    //    بينما Delta Sync Push يرسل snake_case (deleted_at, last_modified, local_uuid)
    //    بدون هذا التحويل، يتجاهل Appwrite الحقول مثل deleted_at → الجهاز الآخر
    //    لا يرى softDelete → يرى 30 بدلاً من 15
    result = _convertKeysToCamelCase(result);

    // 5. بعد التحويل: إزالة الحقول الداخلية بأسمائها camelCase
    result.remove('rowHash');        // من row_hash
    result.remove('clientTs');       // من client_ts

    // 6. تحويل الأنواع المالية إذا لزم الأمر
    if (collectionId != null) {
      result = convertAmountTypesForAppwrite(collectionId, result);
    }

    return result;
  }

  /// تحويل جميع مفاتيح الخريطة من snake_case إلى camelCase بشكل متكرر
  /// الحقول التي لا تحتوي على _ تُترك كما هي (مثل amount, notes)
  static Map<String, dynamic> _convertKeysToCamelCase(
    Map<String, dynamic> input,
  ) {
    final result = <String, dynamic>{};
    for (final entry in input.entries) {
      final camelKey = toCamelCase(entry.key);
      final value = entry.value;
      if (value is Map<String, dynamic>) {
        result[camelKey] = _convertKeysToCamelCase(value);
      } else if (value is List) {
        result[camelKey] = value.map((item) {
          if (item is Map<String, dynamic>) {
            return _convertKeysToCamelCase(item);
          }
          return item;
        }).toList();
      } else {
        result[camelKey] = value;
      }
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

  /// تحويل حقول المبالغ من أعداد صحيحة (Cloud) إلى double (محلي)
  /// يُستخدم عند سحب البيانات من Appwrite Cloud إلى قاعدة البيانات المحلية
  static Map<String, dynamic> convertAmountTypesFromAppwrite(
    String collectionId,
    Map<String, dynamic> payload,
  ) {
    final intFields = _intAmountFields[collectionId];
    if (intFields == null || intFields.isEmpty) return payload;

    final result = Map<String, dynamic>.from(payload);
    for (final field in intFields) {
      if (result.containsKey(field) && result[field] is num) {
        // تحويل integer إلى double للمحلي (مثلاً 5000 → 5000.0)
        result[field] = (result[field] as num).toDouble();
      }
    }
    return result;
  }

  /// الحقول التي يجب أن تبقى snake_case في Appwrite (لا تُحوّل إلى camelCase)
  /// ⚠️ هذه الحقول مطلوبة (required) في مخطط Appwrite بأسمائها snake_case
  /// تحويلها إلى camelCase يسبب خطأ "Missing required attribute"
  static const Set<String> _preserveSnakeCase = {
    'sync_origin',        // حقل مزامنة مطلوب في جميع المجموعات
    'sync_vector_clock',  // حقل مزامنة مطلوب في جميع المجموعات
  };

  /// تحويل أسماء الحقول من snake_case إلى camelCase (للتوافق مع Appwrite)
  /// ⚠️ الحقول في _preserveSnakeCase لا تُحوّل لأن Appwrite يتطلبها snake_case
  static String toCamelCase(String input) {
    if (!input.contains('_')) return input;
    if (_preserveSnakeCase.contains(input)) return input;
    final parts = input.split('_');
    final first = parts.first;
    final rest = parts
        .skip(1)
        .map((p) => p.isEmpty ? '' : '${p[0].toUpperCase()}${p.substring(1)}');
    return '$first${rest.join()}';
  }
}
