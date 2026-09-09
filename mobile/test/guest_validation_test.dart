import 'package:flutter_test/flutter_test.dart';

import '../lib/screens/payments/guest_validation_controller.dart';

void main() {
  group('GuestValidationController', () {
    group('validateGuestName', () {
      test('accepts valid name', () {
        expect(GuestValidationController.validateGuestName('Ahmed'), true);
      });

      test('rejects empty name', () {
        expect(GuestValidationController.validateGuestName(''), false);
      });

      test('rejects single character', () {
        expect(GuestValidationController.validateGuestName('A'), false);
      });

      test('accepts long names', () {
        expect(
          GuestValidationController.validateGuestName('Mohammed Abdullah'),
          true,
        );
      });
    });

    group('validatePhoneNumber', () {
      test('accepts valid 9-digit Yemeni number', () {
        expect(
          GuestValidationController.validatePhoneNumber('712345678'),
          true,
        );
      });

      test('accepts 10-digit Yemeni number', () {
        expect(
          GuestValidationController.validatePhoneNumber('7712345678'),
          true,
        );
      });

      test('rejects empty phone', () {
        expect(GuestValidationController.validatePhoneNumber(''), false);
      });

      test('rejects too short number', () {
        expect(GuestValidationController.validatePhoneNumber('123'), false);
      });

      test('rejects too long number', () {
        expect(
          GuestValidationController.validatePhoneNumber('123456789012345'),
          false,
        );
      });
    });

    group('validateEmail', () {
      test('accepts valid email', () {
        expect(
          GuestValidationController.validateEmail('guest@example.com'),
          true,
        );
      });

      test('accepts empty email (optional)', () {
        expect(GuestValidationController.validateEmail(''), true);
      });

      test('rejects invalid email format', () {
        expect(GuestValidationController.validateEmail('invalid@'), false);
      });

      test('rejects email without domain', () {
        expect(
          GuestValidationController.validateEmail('invalid@domain'),
          false,
        );
      });
    });

    group('sanitizePhone', () {
      test('removes leading +', () {
        expect(
          GuestValidationController.sanitizePhone('+967712345678'),
          '967712345678',
        );
      });

      test('removes 00 prefix', () {
        expect(
          GuestValidationController.sanitizePhone('00967712345678'),
          '967712345678',
        );
      });

      test('removes spaces', () {
        expect(
          GuestValidationController.sanitizePhone('971 2345 678'),
          '9712345678',
        );
      });

      test('handles Yemeni format', () {
        expect(
          GuestValidationController.sanitizePhone('712345678'),
          '712345678',
        );
      });
    });

    group('canPayViaMethod', () {
      test('cash payment is always allowed', () {
        expect(
          GuestValidationController.canPayViaMethod(
            paymentMethod: 'نقدي',
            amount: 100,
            guestPhone: '712345678',
          ),
          true,
        );
      });

      test('card payment requires valid phone', () {
        expect(
          GuestValidationController.canPayViaMethod(
            paymentMethod: 'بطاقة',
            amount: 100,
            guestPhone: '712345678',
          ),
          true,
        );
      });

      test('card payment fails with invalid phone', () {
        expect(
          GuestValidationController.canPayViaMethod(
            paymentMethod: 'بطاقة',
            amount: 100,
            guestPhone: 'invalid',
          ),
          false,
        );
      });

      test('bank transfer requires valid phone', () {
        expect(
          GuestValidationController.canPayViaMethod(
            paymentMethod: 'تحويل بنكي',
            amount: 100,
            guestPhone: '712345678',
          ),
          true,
        );
      });
    });

    group('validateGuestData', () {
      test('accepts complete valid data', () {
        final result = GuestValidationController.validateGuestData(
          name: 'Ahmed',
          phone: '712345678',
          email: 'ahmed@example.com',
          idNumber: '123456789',
          requirePhone: true,
          requireEmail: true,
        );

        expect(result.isValid, true);
        expect(result.error, '');
      });

      test('rejects invalid name', () {
        final result = GuestValidationController.validateGuestData(
          name: 'A',
          phone: '712345678',
          email: '',
          idNumber: '',
        );

        expect(result.isValid, false);
        expect(result.error, contains('Name'));
      });

      test('rejects invalid phone when required', () {
        final result = GuestValidationController.validateGuestData(
          name: 'Ahmed',
          phone: 'invalid',
          email: '',
          idNumber: '',
          requirePhone: true,
        );

        expect(result.isValid, false);
        expect(result.error, contains('Phone'));
      });

      test('allows empty phone when not required', () {
        final result = GuestValidationController.validateGuestData(
          name: 'Ahmed',
          phone: '',
          email: '',
          idNumber: '',
          requirePhone: false,
        );

        expect(result.isValid, true);
      });
    });
  });
}
