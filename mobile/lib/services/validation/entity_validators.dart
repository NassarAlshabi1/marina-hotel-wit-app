import '../local_db.dart';
import 'validation_error.dart';
import 'validation_rules.dart';

/// Validators لكيانات قاعدة البيانات
class EntityValidators {
  /// التحقق من صحة بيانات Booking
  static List<ValidationError> validateBooking(BookingsCompanion data) {
    final errors = <ValidationError>[];

    // التحقق من رقم الغرفة
    if (data.roomNumber.present) {
      final roomNumber = data.roomNumber.value;
      final err = ValidationRules.required('roomNumber', roomNumber);
      if (err != null) errors.add(err);
    }

    // التحقق من اسم النزيل
    if (data.guestName.present) {
      final guestName = data.guestName.value;
      var err = ValidationRules.required('guestName', guestName);
      if (err != null) {
        errors.add(err);
      } else {
        err = ValidationRules.minLength('guestName', guestName, 3);
        if (err != null) errors.add(err);
      }
    }

    // التحقق من رقم الهاتف
    if (data.guestPhone.present) {
      final guestPhone = data.guestPhone.value;
      var err = ValidationRules.required('guestPhone', guestPhone);
      if (err != null) {
        errors.add(err);
      } else {
        err = ValidationRules.phoneFormat('guestPhone', guestPhone);
        if (err != null) errors.add(err);
      }
    }

    // التحقق من تاريخ الدخول
    if (data.checkinDate.present) {
      final checkinDate = data.checkinDate.value;
      final err = ValidationRules.dateFormat('checkinDate', checkinDate);
      if (err != null) errors.add(err);
    }

    // التحقق من تاريخ الخروج
    if (data.checkoutDate.present && data.checkinDate.present) {
      final checkoutDate = data.checkoutDate.value;
      final checkinDate = data.checkinDate.value;
      
      if (checkoutDate != null && checkinDate.isNotEmpty) {
        final err = ValidationRules.dateBefore(
          'checkinDate',
          checkinDate,
          checkoutDate,
          'تاريخ الخروج',
        );
        if (err != null) errors.add(err);
      }
    }

    // التحقق من عدد الليالي
    if (data.expectedNights.present) {
      final expectedNights = data.expectedNights.value;
      final err = ValidationRules.greaterThan(
        'expectedNights',
        expectedNights,
        0,
        inclusive: true,
      );
      if (err != null) errors.add(err);
    }

    // التحقق من المبلغ المستحق
    if (data.totalDueCached.present) {
      final totalDue = data.totalDueCached.value;
      final err = ValidationRules.nonNegative('totalDueCached', totalDue);
      if (err != null) errors.add(err);
    }

    // التحقق من المبلغ المدفوع
    if (data.totalPaidCached.present) {
      final totalPaid = data.totalPaidCached.value;
      final err = ValidationRules.nonNegative('totalPaidCached', totalPaid);
      if (err != null) errors.add(err);
    }

    return errors;
  }

  /// التحقق من صحة بيانات Payment
  static List<ValidationError> validatePayment(PaymentsCompanion data) {
    final errors = <ValidationError>[];

    // التحقق من المبلغ
    if (data.amount.present) {
      final amount = data.amount.value;
      final err = ValidationRules.positive('amount', amount);
      if (err != null) errors.add(err);
    }

    // التحقق من تاريخ الدفع
    if (data.paymentDate.present) {
      final paymentDate = data.paymentDate.value;
      final err = ValidationRules.dateFormat('paymentDate', paymentDate);
      if (err != null) errors.add(err);
    }

    // التحقق من طريقة الدفع
    if (data.paymentMethod.present) {
      final paymentMethod = data.paymentMethod.value;
      final err = ValidationRules.required('paymentMethod', paymentMethod);
      if (err != null) errors.add(err);
    }

    return errors;
  }

  /// التحقق من صحة بيانات Expense
  static List<ValidationError> validateExpense(ExpensesCompanion data) {
    final errors = <ValidationError>[];

    // التحقق من المبلغ
    if (data.amount.present) {
      final amount = data.amount.value;
      final err = ValidationRules.positive('amount', amount);
      if (err != null) errors.add(err);
    }

    // التحقق من نوع المصروف
    if (data.expenseType.present) {
      final expenseType = data.expenseType.value;
      final err = ValidationRules.required('expenseType', expenseType);
      if (err != null) errors.add(err);
    }

    // التحقق من التاريخ
    if (data.date.present) {
      final date = data.date.value;
      final err = ValidationRules.dateFormat('date', date);
      if (err != null) errors.add(err);
    }

    return errors;
  }

  /// التحقق من صحة بيانات Employee
  static List<ValidationError> validateEmployee(EmployeesCompanion data) {
    final errors = <ValidationError>[];

    // التحقق من الاسم
    if (data.name.present) {
      final name = data.name.value;
      var err = ValidationRules.required('name', name);
      if (err != null) {
        errors.add(err);
      } else {
        err = ValidationRules.minLength('name', name, 3);
        if (err != null) errors.add(err);
      }
    }

    // التحقق من الراتب
    if (data.basicSalary.present) {
      final basicSalary = data.basicSalary.value;
      final err = ValidationRules.nonNegative('basicSalary', basicSalary);
      if (err != null) errors.add(err);
    }

    // التحقق من رقم الهاتف (اختياري)
    if (data.phone.present) {
      final phone = data.phone.value;
      if (phone.isNotEmpty) {
        final err = ValidationRules.phoneFormat('phone', phone);
        if (err != null) errors.add(err);
      }
    }

    return errors;
  }

  /// التحقق من صحة بيانات Room
  static List<ValidationError> validateRoom(RoomsCompanion data) {
    final errors = <ValidationError>[];

    // التحقق من رقم الغرفة
    if (data.roomNumber.present) {
      final roomNumber = data.roomNumber.value;
      final err = ValidationRules.required('roomNumber', roomNumber);
      if (err != null) errors.add(err);
    }

    // التحقق من السعر
    if (data.price.present) {
      final price = data.price.value;
      final err = ValidationRules.nonNegative('price', price);
      if (err != null) errors.add(err);
    }

    // التحقق من النوع
    if (data.type.present) {
      final type = data.type.value;
      final err = ValidationRules.required('type', type);
      if (err != null) errors.add(err);
    }

    // التحقق من الحالة
    if (data.status.present) {
      final status = data.status.value;
      final err = ValidationRules.required('status', status);
      if (err != null) errors.add(err);
    }

    return errors;
  }

  /// التحقق من صحة بيانات Debt
  static List<ValidationError> validateDebt(DebtsCompanion data) {
    final errors = <ValidationError>[];

    // التحقق من المبلغ
    if (data.totalAmount.present) {
      final totalAmount = data.totalAmount.value;
      final err = ValidationRules.positive('totalAmount', totalAmount);
      if (err != null) errors.add(err);
    }

    // التحقق من المبلغ المدفوع
    if (data.amountPaid.present) {
      final amountPaid = data.amountPaid.value;
      final err = ValidationRules.nonNegative('amountPaid', amountPaid);
      if (err != null) errors.add(err);
    }

    // التحقق من التاريخ
    if (data.createdDate.present) {
      final createdDate = data.createdDate.value;
      final err = ValidationRules.dateFormat('createdDate', createdDate);
      if (err != null) errors.add(err);
    }

    return errors;
  }
}
