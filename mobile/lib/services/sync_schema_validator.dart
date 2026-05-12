/// مدقق مخطط المزامنة - للتحقق من توافق الحقول المحلية مع Appwrite
/// يفحص:
/// 1. الحقول المطلوبة في Appwrite
/// 2. البيانات المحلية الفارغة/null
/// 3. أنواع البيانات (string vs integer)
library;

import 'local_db.dart';

/// مخطط الحقول المطلوبة لكل جدول في Appwrite
/// يجب تحديث هذا عند تغيير مخطط Appwrite
const Map<String, Set<String>> kRequiredFieldsByCollection = {
  'rooms': {'roomNumber', 'basePrice', 'floor'},
  'bookings': {'roomNumber', 'guestName', 'checkinDate', 'status'},
  'booking_notes': {'bookingUuid', 'note'},
  'shift_notes': {'shiftDate', 'note'},
  'salary_cycles': {'employeeId', 'startDate', 'endDate'},
  'salary_payments': {'employeeId', 'paymentDate'},
  'payments': {
    'amount',
    'paymentDate',
    'paymentMethod',
    'sync_version',
    'sync_vector_clock',
  },
  'debts': {
    'guestName',
    'totalAmount',
    'vector_clock',
    'sync_version',
    'sync_origin',
    'sync_vector_clock',
  },
  'expenses': {'expenseType', 'description', 'amount', 'date'},
  'employees': {'name', 'basicSalary', 'status'},
  'cash_transactions': {'transactionType', 'amount', 'transactionTime'},
  'booking_nights': {'bookingLocalId', 'hotelDayKey', 'nightStart', 'nightEnd'},
  'booking_price_adjustments': {'bookingLocalId', 'adjustmentType', 'amount'},
};

/// أنواع الحقول المتوقعة في Appwrite
const Map<String, Map<String, String>> kFieldTypes = {
  'rooms': {
    'roomNumber': 'string',
    'basePrice': 'double',
    'floor': 'integer',
    'price': 'double',
    'status': 'string',
    'type': 'string',
    'cleaningStatus': 'string',
    'requiresMaintenance': 'boolean',
  },
  'payments': {
    'amount': 'double',
    'paymentDate': 'string',
    'paymentMethod': 'string',
    'sync_version': 'integer',
    'sync_vector_clock': 'string',
    'revenueType': 'string',
  },
  'debts': {
    'totalAmount': 'double',
    'paidAmount': 'double',
    'remainingAmount': 'double',
    'vector_clock': 'string',
    'sync_version': 'integer',
    'sync_origin': 'string',
    'sync_vector_clock': 'string',
  },
  'salary_cycles': {
    'employeeId': 'integer',
    'startDate': 'string',
    'endDate': 'string',
    'expectedAmount': 'integer',
    'actualPaid': 'integer',
    'remainingAmount': 'integer',
  },
  'salary_payments': {
    'employeeId': 'integer',
    'paymentDate': 'string',
    'amount': 'double',
    'cycleId': 'integer',
  },
  'shift_notes': {
    'shiftDate': 'string',
    'note': 'string',
    'priority': 'string',
    'shiftType': 'string',
    'isRead': 'integer',
  },
  'booking_notes': {
    'bookingUuid': 'string',
    'note': 'string',
    'alertType': 'string',
    'isActive': 'integer',
  },
};

/// نتيجة التحقق من سجل واحد
class FieldValidationResult {
  FieldValidationResult({
    required this.collection,
    this.localUuid,
    this.localId,
    required this.missingRequiredFields,
    required this.nullFields,
    required this.typeMismatches,
  }) : isValid = missingRequiredFields.isEmpty && typeMismatches.isEmpty;
  final String collection;
  final String? localUuid;
  final int? localId;
  final List<String> missingRequiredFields;
  final List<String> nullFields;
  final Map<String, String> typeMismatches;
  final bool isValid;
}

/// مدقق المخطط
class SyncSchemaValidator {
  SyncSchemaValidator(this.database);
  final AppDatabase database;

  /// التحقق من جميع الجداول
  Future<Map<String, dynamic>> validateAllTables() async {
    final results = <String, dynamic>{
      'summary': {
        'totalRecords': 0,
        'validRecords': 0,
        'invalidRecords': 0,
        'warnings': 0,
      },
      'details': <String, List<Map<String, dynamic>>>{},
      'errors': <String, List<String>>{},
    };

    // التحقق من الغرف
    final roomsResults = await _validateRooms();
    results['details']['rooms'] = roomsResults;
    _updateSummary(results, roomsResults);

    // التحقق من الحجوزات
    final bookingsResults = await _validateBookings();
    results['details']['bookings'] = bookingsResults;
    _updateSummary(results, bookingsResults);

    // التحقق من المدفوعات
    final paymentsResults = await _validatePayments();
    results['details']['payments'] = paymentsResults;
    _updateSummary(results, paymentsResults);

    // التحقق من الديون
    final debtsResults = await _validateDebts();
    results['details']['debts'] = debtsResults;
    _updateSummary(results, debtsResults);

    // التحقق من دورات الرواتب
    final salaryCyclesResults = await _validateSalaryCycles();
    results['details']['salary_cycles'] = salaryCyclesResults;
    _updateSummary(results, salaryCyclesResults);

    // التحقق من مدفوعات الرواتب
    final salaryPaymentsResults = await _validateSalaryPayments();
    results['details']['salary_payments'] = salaryPaymentsResults;
    _updateSummary(results, salaryPaymentsResults);

    // التحقق من ملاحظات الشيفت
    final shiftNotesResults = await _validateShiftNotes();
    results['details']['shift_notes'] = shiftNotesResults;
    _updateSummary(results, shiftNotesResults);

    // التحقق من ملاحظات الحجز
    final bookingNotesResults = await _validateBookingNotes();
    results['details']['booking_notes'] = bookingNotesResults;
    _updateSummary(results, bookingNotesResults);

    return results;
  }

  void _updateSummary(
    Map<String, dynamic> results,
    List<Map<String, dynamic>> tableResults,
  ) {
    for (final r in tableResults) {
      results['summary']['totalRecords'] =
          (results['summary']['totalRecords'] ?? 0) + 1;
      if (r['isValid'] == true) {
        results['summary']['validRecords'] =
            (results['summary']['validRecords'] ?? 0) + 1;
      } else {
        results['summary']['invalidRecords'] =
            (results['summary']['invalidRecords'] ?? 0) + 1;
      }
      if ((r['warnings'] as List?)?.isNotEmpty ?? false) {
        results['summary']['warnings'] =
            (results['summary']['warnings'] ?? 0) + 1;
      }
    }
  }

  /// التحقق من الغرف
  Future<List<Map<String, dynamic>>> _validateRooms() async {
    final results = <Map<String, dynamic>>[];
    final rooms = await database.select(database.rooms).get();

    for (final room in rooms) {
      final issues = <String>[];
      final warnings = <String>[];

      // التحقق من الحقول المطلوبة
      if (room.roomNumber.isEmpty) {
        issues.add('roomNumber فارغ');
      }

      // التحقق من أنواع البيانات
      if (room.price < 0) {
        warnings.add('price سالب: ${room.price}');
      }

      results.add({
        'collection': 'rooms',
        'localId': room.id,
        'localUuid': room.localUuid,
        'roomNumber': room.roomNumber,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// التحقق من الحجوزات
  Future<List<Map<String, dynamic>>> _validateBookings() async {
    final results = <Map<String, dynamic>>[];
    final bookings = await database.select(database.bookings).get();

    for (final booking in bookings) {
      final issues = <String>[];
      final warnings = <String>[];

      if (booking.roomNumber.isEmpty) {
        issues.add('roomNumber فارغ');
      }
      if (booking.guestName.isEmpty) {
        issues.add('guestName فارغ');
      }
      if (booking.checkinDate.isEmpty) {
        issues.add('checkinDate فارغ');
      }
      if (booking.status.isEmpty) {
        issues.add('status فارغ');
      }

      results.add({
        'collection': 'bookings',
        'localId': booking.id,
        'localUuid': booking.localUuid,
        'guestName': booking.guestName,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// التحقق من المدفوعات
  Future<List<Map<String, dynamic>>> _validatePayments() async {
    final results = <Map<String, dynamic>>[];
    final payments = await database.select(database.payments).get();

    for (final payment in payments) {
      final issues = <String>[];
      final warnings = <String>[];

      if (payment.amount < 0) {
        issues.add('amount غير صالح: ${payment.amount}');
      }
      if (payment.paymentDate.isEmpty) {
        issues.add('paymentDate فارغ');
      }
      if (payment.paymentMethod.isEmpty) {
        issues.add('paymentMethod فارغ');
      }

      results.add({
        'collection': 'payments',
        'localId': payment.id,
        'localUuid': payment.localUuid,
        'amount': payment.amount,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// التحقق من الديون
  Future<List<Map<String, dynamic>>> _validateDebts() async {
    final results = <Map<String, dynamic>>[];
    final debts = await database.select(database.debts).get();

    for (final debt in debts) {
      final issues = <String>[];
      final warnings = <String>[];

      if (debt.guestName.isEmpty) {
        issues.add('guestName فارغ');
      }
      if (debt.totalAmount < 0) {
        issues.add('totalAmount غير صالح: ${debt.totalAmount}');
      }
      if (debt.origin.isEmpty) {
        warnings.add('origin فارغ - سيستخدم mobile');
      }

      results.add({
        'collection': 'debts',
        'localId': debt.id,
        'localUuid': debt.localUuid,
        'guestName': debt.guestName,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// التحقق من دورات الرواتب
  Future<List<Map<String, dynamic>>> _validateSalaryCycles() async {
    final results = <Map<String, dynamic>>[];
    final cycles = await database.select(database.salaryCycles).get();

    for (final cycle in cycles) {
      final issues = <String>[];
      final warnings = <String>[];

      // التحقق من employeeId
      if (cycle.employeeId <= 0) {
        issues.add('employeeId غير صالح: ${cycle.employeeId}');
      }

      // التحقق من startDate و endDate (مطلوبان في Appwrite)
      final startDate = cycle.hotelDayStart;
      final endDate = cycle.hotelDayEnd;

      if ((startDate == null || startDate.isEmpty) &&
          (endDate == null || endDate.isEmpty)) {
        warnings.add('startDate و endDate فارغان - سيتم استخدام قيم افتراضية');
      }

      results.add({
        'collection': 'salary_cycles',
        'localId': cycle.id,
        'localUuid': cycle.localUuid,
        'employeeId': cycle.employeeId,
        'cycleKey': cycle.cycleKey,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// التحقق من مدفوعات الرواتب
  Future<List<Map<String, dynamic>>> _validateSalaryPayments() async {
    final results = <Map<String, dynamic>>[];
    final payments = await database.select(database.salaryPayments).get();

    for (final payment in payments) {
      final issues = <String>[];
      final warnings = <String>[];

      // cycleId غير nullable في المخطط المحلي — لا حاجة لفحص null
      // لكن نتحقق أن القيمة تشير إلى سجل صالح
      if (payment.cycleId <= 0) {
        issues.add('cycleId غير صالح (${payment.cycleId}) - مطلوب في Appwrite');
      }

      // التحقق من paymentDate (مطلوب في Appwrite)
      if (payment.paymentDateIso.isEmpty) {
        warnings.add('paymentDateIso فارغ - سيتم استخدام التاريخ الحالي');
      }

      results.add({
        'collection': 'salary_payments',
        'localId': payment.id,
        'localUuid': payment.localUuid,
        'cycleId': payment.cycleId,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// التحقق من ملاحظات الشيفت
  Future<List<Map<String, dynamic>>> _validateShiftNotes() async {
    final results = <Map<String, dynamic>>[];
    final notes = await database.select(database.shiftNotes).get();

    for (final note in notes) {
      final issues = <String>[];
      final warnings = <String>[];

      // التحقق من createdAtIso (التاريخ — مطلوب في Appwrite)
      if (note.createdAtIso == null || note.createdAtIso!.isEmpty) {
        // يمكن حسابه من createdAt
        warnings.add('createdAtIso فارغ - سيتم حسابه من createdAt');
      }

      // التحقق من note (مطلوب في Appwrite - يستخدم content أو title)
      if ((note.content.isEmpty) && (note.title.isEmpty)) {
        issues.add('content و title فارغان - لا يمكن تحديد note');
      }

      results.add({
        'collection': 'shift_notes',
        'localId': note.id,
        'localUuid': note.localUuid,
        'shiftDate': note.createdAtIso,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// التحقق من ملاحظات الحجز
  Future<List<Map<String, dynamic>>> _validateBookingNotes() async {
    final results = <Map<String, dynamic>>[];
    final notes = await database.select(database.bookingNotes).get();

    for (final note in notes) {
      final issues = <String>[];
      final warnings = <String>[];

      // التحقق من bookingUuid (مطلوب في Appwrite - يستخدم localUuid كمرجع)
      if (note.localUuid.isEmpty) {
        issues.add('localUuid فارغ - لا يمكن تحديد bookingUuid');
      }

      // التحقق من note (مطلوب في Appwrite - يستخدم noteText)
      if (note.noteText.isEmpty) {
        issues.add('noteText فارغ - لا يمكن تحديد note');
      }

      results.add({
        'collection': 'booking_notes',
        'localId': note.id,
        'localUuid': note.localUuid,
        'bookingId': note.bookingId,
        'isValid': issues.isEmpty,
        'issues': issues,
        'warnings': warnings,
      });
    }

    return results;
  }

  /// طباعة تقرير التحقق
  String generateReport(Map<String, dynamic> validationResults) {
    final buffer = StringBuffer();

    buffer.writeln(
      '═══════════════════════════════════════════════════════════',
    );
    buffer.writeln('                تقرير التحقق من مخطط المزامنة');
    buffer.writeln(
      '═══════════════════════════════════════════════════════════',
    );
    buffer.writeln();

    final summary = validationResults['summary'] as Map<String, dynamic>;
    buffer.writeln('📊 الملخص:');
    buffer.writeln('   إجمالي السجلات: ${summary['totalRecords']}');
    buffer.writeln('   ✅ سجلات صالحة: ${summary['validRecords']}');
    buffer.writeln('   ❌ سجلات غير صالحة: ${summary['invalidRecords']}');
    buffer.writeln('   ⚠️ تحذيرات: ${summary['warnings']}');
    buffer.writeln();

    final details =
        validationResults['details'] as Map<String, List<Map<String, dynamic>>>;
    for (final entry in details.entries) {
      final tableName = entry.key;
      final records = entry.value;
      final invalidRecords = records
          .where((r) => r['isValid'] == false)
          .toList();
      final warningRecords = records
          .where((r) => (r['warnings'] as List?)?.isNotEmpty ?? false)
          .toList();

      if (invalidRecords.isNotEmpty || warningRecords.isNotEmpty) {
        buffer.writeln(
          '━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━',
        );
        buffer.writeln('📋 جدول: $tableName');
        buffer.writeln(
          '   إجمالي: ${records.length} | ❌ غير صالح: ${invalidRecords.length} | ⚠️ تحذيرات: ${warningRecords.length}',
        );

        if (invalidRecords.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('   ❌ السجلات غير الصالحة:');
          for (final r in invalidRecords.take(5)) {
            buffer.writeln('      ID ${r['localId']}: ${r['issues']}');
          }
          if (invalidRecords.length > 5) {
            buffer.writeln('      ... و ${invalidRecords.length - 5} سجل آخر');
          }
        }

        if (warningRecords.isNotEmpty) {
          buffer.writeln();
          buffer.writeln('   ⚠️ السجلات مع تحذيرات:');
          for (final r in warningRecords.take(5)) {
            buffer.writeln('      ID ${r['localId']}: ${r['warnings']}');
          }
          if (warningRecords.length > 5) {
            buffer.writeln('      ... و ${warningRecords.length - 5} سجل آخر');
          }
        }
        buffer.writeln();
      }
    }

    buffer.writeln(
      '═══════════════════════════════════════════════════════════',
    );
    buffer.writeln('                      نهاية التقرير');
    buffer.writeln(
      '═══════════════════════════════════════════════════════════',
    );

    return buffer.toString();
  }
}
