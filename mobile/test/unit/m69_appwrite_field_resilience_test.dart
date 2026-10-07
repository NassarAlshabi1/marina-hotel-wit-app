// test/unit/m69_appwrite_field_resilience_test.dart
//
// ✅ (2026-10-07 — م-2) صلابة حقول عقد m69 على مسار Appwrite.
//
// الخطر الموثّق (تقرير الفرع الأول §8): `expenseKind` و`employeeLinkCleared`
// يُرسلان دائماً في حمولة المصروف. إن لم يكونا موجودين على مخطط مجموعة
// `expenses` على السحابة، ترفض Appwrite المستند بـ
//   document_invalid_structure: Unknown attribute: "X" (400)
// فلا تصل أي مصروفات.
//
// الحماية القائمة في الكود (مُثبتة بقراءة، ولم تكن مُختبرة): حلقة إعادة
// المحاولة في AppwriteService._upsertDocumentInternal تُزيل **الحقل المذكور
// فقط** وتُعيد الإرسال — بلا إسقاط السجل ولا الحقول الأخرى. هذا الاختبار
// يثبّت السياسة على الدالتين النقيتين (بلا شبكة) + يقفل أسماء الحقول في
// قوائم السماح ومخطط التحقق.
import 'package:flutter_test/flutter_test.dart';

import 'package:marina_hotel_mobile/services/appwrite_schema_verifier.dart';
import 'package:marina_hotel_mobile/services/appwrite_sync_utils.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('استخراج الحقل غير المعروف من خطأ Appwrite', () {
    test('الصيغة القياسية: document_invalid_structure + Unknown attribute', () {
      expect(
        AppwriteSyncUtils.unknownAttributeFromError(
          code: 400,
          type: 'general_argument_invalid',
          message:
              'Invalid document structure: Unknown attribute: '
              '"employeeLinkCleared"',
        ),
        equals('employeeLinkCleared'),
      );
      expect(
        AppwriteSyncUtils.unknownAttributeFromError(
          code: 400,
          type: 'document_invalid_structure',
          message: 'Unknown attribute: "expenseKind"',
        ),
        equals('expenseKind'),
      );
    });

    test('غير هذا النوع من الأخطاء ⇒ null (لا إزالة حقول بلا دليل)', () {
      expect(
        AppwriteSyncUtils.unknownAttributeFromError(
          code: 500,
          type: 'general_error',
          message: 'Unknown attribute: "expenseKind"',
        ),
        isNull,
        reason: 'رمز غير 400 لا يُفعّل سياسة الإزالة',
      );
      expect(
        AppwriteSyncUtils.unknownAttributeFromError(
          code: 400,
          type: 'general_argument_invalid',
          message: 'Missing required attribute: "amount"',
        ),
        isNull,
      );
    });
  });

  group('سياسة إعادة المحاولة: يُزال الحقل المذكور فقط', () {
    Map<String, dynamic> expensesPayload() => <String, dynamic>{
      'localUuid': 'exp-uuid-1',
      'expenseType': 'سلفة',
      'amount': 1500,
      'date': '2026-10-01',
      'employeeUuid': 'emp-uuid-1',
      'withdrawalUuid': 'wd-uuid-1',
      'expenseKind': 'salary_advance',
      'employeeLinkCleared': false,
    };

    test('إزالة employeeLinkCleared تُبقي expenseKind وبقية الحمولة حرفياً', () {
      final payload = expensesPayload();
      final retry = AppwriteSyncUtils.withoutField(
        payload,
        'employeeLinkCleared',
      );
      expect(retry.containsKey('employeeLinkCleared'), isFalse);
      expect(retry['expenseKind'], equals('salary_advance'));
      expect(retry['employeeUuid'], equals('emp-uuid-1'));
      expect(retry['withdrawalUuid'], equals('wd-uuid-1'));
      expect(retry['amount'], equals(1500));
      expect(retry.length, equals(payload.length - 1));
      // الحمولة الأصلية لا تُمَس (نسخة جديدة دائماً)
      expect(payload.containsKey('employeeLinkCleared'), isTrue);
    });

    test('تتابع محاولات: إزالة الحقلين المعطّلين معاً تُبقي البيانات المالية',
        () {
      var data = expensesPayload();
      final firstUnknown = AppwriteSyncUtils.unknownAttributeFromError(
        code: 400,
        type: 'document_invalid_structure',
        message: 'Unknown attribute: "expenseKind"',
      );
      expect(firstUnknown, isNotNull);
      data = AppwriteSyncUtils.withoutField(data, firstUnknown!);
      final secondUnknown = AppwriteSyncUtils.unknownAttributeFromError(
        code: 400,
        type: 'document_invalid_structure',
        message: 'Unknown attribute: "employeeLinkCleared"',
      );
      expect(secondUnknown, isNotNull);
      data = AppwriteSyncUtils.withoutField(data, secondUnknown!);

      expect(data.containsKey('expenseKind'), isFalse);
      expect(data.containsKey('employeeLinkCleared'), isFalse);
      expect(data['amount'], equals(1500));
      expect(data['expenseType'], equals('سلفة'));
      expect(data['employeeUuid'], equals('emp-uuid-1'));
      expect(data['localUuid'], equals('exp-uuid-1'));
    });

    test('حقل غير موجود في الحمولة ⇒ لا تغيير إطلاقاً', () {
      final payload = expensesPayload();
      final same = AppwriteSyncUtils.withoutField(payload, 'notThere');
      expect(same, equals(payload));
    });
  });

  group('أقفال عقد m69 في مسار Appwrite', () {
    test('أسماء الحقول في قوائم السماح camelCase (تُرفع لا تُقص)', () {
      final expenses = AppwriteSyncUtils.validFieldsPerCollection['expenses'];
      expect(expenses, isNotNull);
      expect(expenses, contains('expenseKind'));
      expect(expenses, contains('employeeLinkCleared'));
      expect(expenses, contains('withdrawalUuid'));
      expect(
        expenses,
        isNot(contains('expense_kind')),
        reason: 'صيغة Appwrite camelCase — snake_case لمخطط D1 فقط',
      );

      final payments =
          AppwriteSyncUtils.validFieldsPerCollection['salary_payments'];
      expect(payments, contains('cycleUuid'));
      expect(payments, contains('cycleLocalUuid'));

      final withdrawals =
          AppwriteSyncUtils.validFieldsPerCollection['salary_withdrawals'];
      expect(withdrawals, contains('expenseUuid'));
    });

    test('مخطط التحقق يطالب بالحقلين على مجموعة expenses (تنبيه المشغّل)', () {
      final schema = AppwriteSchemaVerifier.requiredCollections['expenses'];
      expect(schema, isNotNull);
      final attributes = (schema['attributes'] as List)
          .cast<Map<String, dynamic>>();
      final keys = attributes.map((a) => a['key'] as String).toSet();
      expect(keys, contains('expenseKind'));
      expect(keys, contains('employeeLinkCleared'));
      final kindAttr = attributes.firstWhere((a) => a['key'] == 'expenseKind');
      expect(kindAttr['type'], equals('string'));
      final clearedAttr = attributes.firstWhere(
        (a) => a['key'] == 'employeeLinkCleared',
      );
      expect(clearedAttr['type'], equals('boolean'));
    });
  });
}
