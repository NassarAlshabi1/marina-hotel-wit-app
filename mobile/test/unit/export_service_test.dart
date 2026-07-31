import 'package:flutter_test/flutter_test.dart';
import 'package:marina_hotel_mobile/services/export_service.dart';

void main() {
  group('ExportService', () {
    test('should be a singleton', () {
      expect(ExportService.instance, same(ExportService.instance));
    });

    group('SalaryExportData', () {
      test('should create with required fields', () {
        final data = SalaryExportData(
          date: DateTime(2026, 7, 1),
          employeeName: 'Ahmed',
          role: 'Receptionist',
          type: 'سحب راتب',
          amount: 50000,
        );
        expect(data.employeeName, 'Ahmed');
        expect(data.amount, 50000);
        expect(data.type, 'سحب راتب');
      });

      test('should handle negative amounts (deductions)', () {
        final data = SalaryExportData(
          date: DateTime(2026, 7, 1),
          employeeName: 'Ahmed',
          role: 'Receptionist',
          type: 'خصم راتب',
          amount: -5000,
        );
        expect(data.amount, -5000);
      });
    });

    group('ExpenseExportData', () {
      test('should create with required fields', () {
        final data = ExpenseExportData(
          date: DateTime(2026, 7, 2),
          type: 'ديزل',
          description: 'وقود المولد',
          amount: 45000,
        );
        expect(data.type, 'ديزل');
        expect(data.description, 'وقود المولد');
        expect(data.amount, 45000);
      });
    });

    group('InvoiceItem', () {
      test('should create with required fields', () {
        final item = InvoiceItem(
          description: 'إيجار غرفة 101 (3 ليالٍ)',
          qty: 3,
          unitPrice: 15000,
          total: 45000,
        );
        expect(item.qty, 3);
        expect(item.total, 45000);
      });

      test('should handle negative amounts (discounts)', () {
        final item = InvoiceItem(
          description: 'خصم إقامة طويلة (10%)',
          qty: 1,
          unitPrice: -4500,
          total: -4500,
        );
        expect(item.total, -4500);
      });
    });

    group('InvoiceExportData', () {
      test('should calculate total correctly', () {
        final invoice = InvoiceExportData(
          invoiceNumber: 'INV-001',
          invoiceDate: DateTime(2026, 7, 26),
          guestName: 'Ahmed',
          guestPhone: '+967777123456',
          guestId: '01234567890',
          roomNumber: '101',
          checkinDate: DateTime(2026, 7, 25),
          checkoutDate: DateTime(2026, 7, 28),
          nights: 3,
          roomRate: 15000,
          items: [
            const InvoiceItem(
              description: 'إيجار',
              qty: 3,
              unitPrice: 15000,
              total: 45000,
            ),
            const InvoiceItem(
              description: 'خصم',
              qty: 1,
              unitPrice: -4500,
              total: -4500,
            ),
            const InvoiceItem(
              description: 'غسيل',
              qty: 2,
              unitPrice: 2000,
              total: 4000,
            ),
          ],
          paymentMethod: 'نقدي',
          receivedBy: 'Saeed',
        );

        expect(invoice.total, 44500); // 45000 - 4500 + 4000
      });

      test('should handle empty items list', () {
        final invoice = InvoiceExportData(
          invoiceNumber: 'INV-002',
          invoiceDate: DateTime(2026, 7, 26),
          guestName: 'Test',
          guestPhone: '',
          guestId: '',
          roomNumber: '102',
          checkinDate: DateTime(2026, 7, 25),
          checkoutDate: DateTime(2026, 7, 26),
          nights: 1,
          roomRate: 10000,
          items: const [],
          paymentMethod: 'نقدي',
          receivedBy: 'Test',
        );

        expect(invoice.total, 0);
      });
    });
  });
}
