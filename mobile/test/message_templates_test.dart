// ============================================================================
//  MessageTemplates — Unit Tests
//  ============================================================================
//  اختبارات قوالب الرسائل:
//    - whatsappPaymentTemplate يحتوي على placeholders الصحيحة
// ============================================================================

library marina_hotel_mobile.test.message_templates_test;

import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/utils/message_templates.dart';

void main() {
  group('whatsappPaymentTemplate', () {
    test('يحتوي على placeholder لاسم النزيل', () {
      expect(whatsappPaymentTemplate, contains('{name}'));
    });

    test('يحتوي على placeholder للمبلغ', () {
      expect(whatsappPaymentTemplate, contains('{amount}'));
    });

    test('يحتوي على placeholder لرقم الغرفة', () {
      expect(whatsappPaymentTemplate, contains('{room}'));
    });

    test('يحتوي على placeholder للمبلغ المتبقي', () {
      expect(whatsappPaymentTemplate, contains('{remaining}'));
    });

    test('يحتوي على placeholder لليالي الإضافية', () {
      expect(whatsappPaymentTemplate, contains('{extra_nights}'));
    });

    test('يحتوي على اسم الفندق', () {
      expect(whatsappPaymentTemplate, contains('مارينا'));
    });

    test('يحتوي على رقم الاستفسار', () {
      expect(whatsappPaymentTemplate, contains('9677734587456'));
    });

    test('يمكن استبدال placeholders بقيم فعلية', () {
      final message = whatsappPaymentTemplate
          .replaceAll('{name}', 'أحمد محمد')
          .replaceAll('{amount}', '5000')
          .replaceAll('{room}', '101')
          .replaceAll('{extra_nights}', '')
          .replaceAll('{remaining}', '10000');

      expect(message, contains('أحمد محمد'));
      expect(message, contains('5000'));
      expect(message, contains('101'));
      expect(message, contains('10000'));
      expect(message, isNot(contains('{name}')));
      expect(message, isNot(contains('{amount}')));
    });
  });
}
