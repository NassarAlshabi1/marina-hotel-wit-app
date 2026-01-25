import 'package:flutter/foundation.dart';
import '../utils/debug_logs.dart';
import 'backup_serializers.dart';
import 'local_db.dart';

/// خدمة استعادة ذكية تدمج البيانات بدلاً من الحذف الكامل
/// تقلل من فقدان البيانات وتحسن الأداء
class SmartRestoreService {
  final DatabaseManager db;
  
  SmartRestoreService(this.db);
  
  void _log(String message) {
    DebugLogs.add('SmartRestore', message);
    debugPrint(message);
  }

  /// استراتيجية الدمج الذكي - تحدث البيانات الموجودة بدلاً من حذفها
  /// - أسرع من الحذف الكامل
  /// - أكثر أماناً
  /// - يحتفظ بالبيانات المحلية غير الموجودة في النسخة الاحتياطية
  Future<RestoreResult> smartMerge(Map<String, dynamic> backupData) async {
    final result = RestoreResult();
    
    try {
      _log('🧠 بدء الدمج الذكي للبيانات...');
      
      await db.transaction(() async {
        // استعادة الجداول الرئيسية أولاً
        if (backupData.containsKey('rooms')) {
          result.roomsUpdated = await _mergeRooms(backupData['rooms']);
        }
        
        if (backupData.containsKey('bookings')) {
          result.bookingsUpdated = await _mergeBookings(backupData['bookings']);
        }
        
        if (backupData.containsKey('booking_notes')) {
          result.notesUpdated = await _mergeBookingNotes(backupData['booking_notes']);
        }
        
        if (backupData.containsKey('booking_nights')) {
          result.nightsUpdated = await _mergeBookingNights(backupData['booking_nights']);
        }
        
        if (backupData.containsKey('hotel_day_ledger')) {
          result.ledgerUpdated = await _mergeLedger(backupData['hotel_day_ledger']);
        }
        
        if (backupData.containsKey('shift_notes')) {
          result.shiftNotesUpdated = await _mergeShiftNotes(backupData['shift_notes']);
        }
        
        if (backupData.containsKey('employees')) {
          result.employeesUpdated = await _mergeEmployees(backupData['employees']);
        }
        
        if (backupData.containsKey('expenses')) {
          result.expensesUpdated = await _mergeExpenses(backupData['expenses']);
        }
        
        if (backupData.containsKey('cash_transactions')) {
          result.transactionsUpdated = await _mergeCashTransactions(backupData['cash_transactions']);
        }
        
        if (backupData.containsKey('payments')) {
          result.paymentsUpdated = await _mergePayments(backupData['payments']);
        }
        
        if (backupData.containsKey('debts')) {
          result.debtsUpdated = await _mergeDebts(backupData['debts']);
        }
        
        if (backupData.containsKey('salary_cycles')) {
          result.cyclesUpdated = await _mergeSalaryCycles(backupData['salary_cycles']);
        }
        
        if (backupData.containsKey('salary_payments')) {
          result.salaryPaymentsUpdated = await _mergeSalaryPayments(backupData['salary_payments']);
        }
      });
      
      result.success = true;
      _log('✅ الدمج الذكي مكتمل: ${result.summary}');
      
    } catch (e) {
      result.success = false;
      result.error = e.toString();
      _log('❌ فشل الدمج الذكي: $e');
    }
    
    return result;
  }

  /// دمج الغرف - استخدام insertOnConflictUpdate
  Future<int> _mergeRooms(dynamic roomsData) async {
    if (roomsData is! List) return 0;
    
    int count = 0;
    for (final roomJson in roomsData) {
      try {
        final map = Map<String, dynamic>.from(roomJson as Map);
        final data = Room.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.rooms).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج غرفة: $e');
      }
    }
    
    _log('📊 تم دمج $count غرفة');
    return count;
  }

  /// دمج الحجوزات مع التحقق من الصلاحية
  Future<int> _mergeBookings(dynamic bookingsData) async {
    if (bookingsData is! List) return 0;
    
    int count = 0;
    for (final bookingJson in bookingsData) {
      try {
        final map = Map<String, dynamic>.from(bookingJson as Map);
        final data = Booking.fromJson(map, serializer: lenientValueSerializer);
        
        // التحقق من وجود الغرفة المرتبطة
        final roomExists = await _checkRoomExists(data.roomNumber);
        if (!roomExists) {
          _log('⚠️ تخطي حجز ${data.id} - الغرفة ${data.roomNumber} غير موجودة');
          continue;
        }
        
        await db.into(db.bookings).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج حجز: $e');
      }
    }
    
    _log('📊 تم دمج $count حجز');
    return count;
  }

  /// دمج ملاحظات الحجز
  Future<int> _mergeBookingNotes(dynamic notesData) async {
    if (notesData is! List) return 0;
    
    int count = 0;
    for (final noteJson in notesData) {
      try {
        final map = Map<String, dynamic>.from(noteJson as Map);
        final data = BookingNote.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.bookingNotes).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج ملاحظة: $e');
      }
    }
    
    _log('📊 تم دمج $count ملاحظة حجز');
    return count;
  }

  /// دمج ليالي الحجز
  Future<int> _mergeBookingNights(dynamic nightsData) async {
    if (nightsData is! List) return 0;
    
    int count = 0;
    for (final nightJson in nightsData) {
      try {
        final map = Map<String, dynamic>.from(nightJson as Map);
        final data = BookingNight.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.bookingNights).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج ليلة: $e');
      }
    }
    
    _log('📊 تم دمج $count ليلة');
    return count;
  }

  /// دمج دفتر اليومية
  Future<int> _mergeLedger(dynamic ledgerData) async {
    if (ledgerData is! List) return 0;
    
    int count = 0;
    for (final ledgerJson in ledgerData) {
      try {
        final map = Map<String, dynamic>.from(ledgerJson as Map);
        final data = HotelDayLedgerEntry.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.hotelDayLedger).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج قيد: $e');
      }
    }
    
    _log('📊 تم دمج $count قيد يومي');
    return count;
  }

  /// دمج ملاحظات الشفت
  Future<int> _mergeShiftNotes(dynamic notesData) async {
    if (notesData is! List) return 0;
    
    int count = 0;
    for (final noteJson in notesData) {
      try {
        final map = Map<String, dynamic>.from(noteJson as Map);
        final data = ShiftNote.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.shiftNotes).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج ملاحظة شفت: $e');
      }
    }
    
    _log('📊 تم دمج $count ملاحظة شفت');
    return count;
  }

  /// دمج الموظفين
  Future<int> _mergeEmployees(dynamic employeesData) async {
    if (employeesData is! List) return 0;
    
    int count = 0;
    for (final employeeJson in employeesData) {
      try {
        final map = Map<String, dynamic>.from(employeeJson as Map);
        final data = Employee.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.employees).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج موظف: $e');
      }
    }
    
    _log('📊 تم دمج $count موظف');
    return count;
  }

  /// دمج المصروفات
  Future<int> _mergeExpenses(dynamic expensesData) async {
    if (expensesData is! List) return 0;
    
    int count = 0;
    for (final expenseJson in expensesData) {
      try {
        final map = Map<String, dynamic>.from(expenseJson as Map);
        final data = Expense.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.expenses).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج مصروف: $e');
      }
    }
    
    _log('📊 تم دمج $count مصروف');
    return count;
  }

  /// دمج معاملات النقد
  Future<int> _mergeCashTransactions(dynamic transactionsData) async {
    if (transactionsData is! List) return 0;
    
    int count = 0;
    for (final transactionJson in transactionsData) {
      try {
        final map = Map<String, dynamic>.from(transactionJson as Map);
        final data = CashTransaction.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.cashTransactions).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج معاملة نقدية: $e');
      }
    }
    
    _log('📊 تم دمج $count معاملة نقدية');
    return count;
  }

  /// دمج الدفعات
  Future<int> _mergePayments(dynamic paymentsData) async {
    if (paymentsData is! List) return 0;
    
    int count = 0;
    for (final paymentJson in paymentsData) {
      try {
        final map = Map<String, dynamic>.from(paymentJson as Map);
        final data = Payment.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.payments).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج دفعة: $e');
      }
    }
    
    _log('📊 تم دمج $count دفعة');
    return count;
  }

  /// دمج الديون
  Future<int> _mergeDebts(dynamic debtsData) async {
    if (debtsData is! List) return 0;
    
    int count = 0;
    for (final debtJson in debtsData) {
      try {
        final map = Map<String, dynamic>.from(debtJson as Map);
        final data = Debt.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.debts).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج دين: $e');
      }
    }
    
    _log('📊 تم دمج $count دين');
    return count;
  }

  /// دمج دورات الرواتب
  Future<int> _mergeSalaryCycles(dynamic cyclesData) async {
    if (cyclesData is! List) return 0;
    
    int count = 0;
    for (final cycleJson in cyclesData) {
      try {
        final map = Map<String, dynamic>.from(cycleJson as Map);
        final data = SalaryCycle.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.salaryCycles).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج دورة رواتب: $e');
      }
    }
    
    _log('📊 تم دمج $count دورة رواتب');
    return count;
  }

  /// دمج مدفوعات الرواتب
  Future<int> _mergeSalaryPayments(dynamic paymentsData) async {
    if (paymentsData is! List) return 0;
    
    int count = 0;
    for (final paymentJson in paymentsData) {
      try {
        final map = Map<String, dynamic>.from(paymentJson as Map);
        final data = SalaryPayment.fromJson(map, serializer: lenientValueSerializer);
        await db.into(db.salaryPayments).insertOnConflictUpdate(data);
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج دفعة راتب: $e');
      }
    }
    
    _log('📊 تم دمج $count دفعة راتب');
    return count;
  }

  /// التحقق من وجود غرفة
  Future<bool> _checkRoomExists(String roomNumber) async {
    final query = db.select(db.rooms)..where((t) => t.roomNumber.equals(roomNumber));
    final result = await query.getSingleOrNull();
    return result != null;
  }

  /// تنظيف السجلات اليتيمة (orphaned records)
  /// - سجلات تشير إلى سجلات رئيسية محذوفة
  Future<CleanupResult> cleanupOrphanedRecords() async {
    final result = CleanupResult();
    
    try {
      _log('🧹 بدء تنظيف السجلات اليتيمة...');
      
      await db.transaction(() async {
        // تنظيف الحجوزات بدون غرف
        final orphanedBookings = await db.customSelect(
          'SELECT id FROM bookings WHERE room_number NOT IN (SELECT room_number FROM rooms)',
        ).get();
        
        if (orphanedBookings.isNotEmpty) {
          for (final row in orphanedBookings) {
            final bookingId = row.data['id'] as int;
            await db.customStatement(
              'DELETE FROM bookings WHERE id = ?',
              [bookingId],
            );
            result.bookingsDeleted++;
          }
        }
        
        // تنظيف الدفعات بدون حجوزات
        final orphanedPayments = await db.customSelect(
          'SELECT id FROM payments WHERE booking_id NOT IN (SELECT id FROM bookings)',
        ).get();
        
        if (orphanedPayments.isNotEmpty) {
          for (final row in orphanedPayments) {
            final paymentId = row.data['id'] as int;
            await db.customStatement(
              'DELETE FROM payments WHERE id = ?',
              [paymentId],
            );
            result.paymentsDeleted++;
          }
        }
        
        // تنظيف الملاحظات بدون حجوزات
        final orphanedNotes = await db.customSelect(
          'SELECT id FROM booking_notes WHERE booking_id NOT IN (SELECT id FROM bookings)',
        ).get();
        
        if (orphanedNotes.isNotEmpty) {
          for (final row in orphanedNotes) {
            final noteId = row.data['id'] as int;
            await db.customStatement(
              'DELETE FROM booking_notes WHERE id = ?',
              [noteId],
            );
            result.notesDeleted++;
          }
        }
      });
      
      result.success = true;
      _log('✅ تم تنظيف ${result.totalDeleted} سجل يتيم');
      
    } catch (e) {
      result.success = false;
      result.error = e.toString();
      _log('❌ فشل التنظيف: $e');
    }
    
    return result;
  }
}

/// نتيجة عملية الاستعادة الذكية
class RestoreResult {
  bool success = false;
  String? error;
  
  int roomsUpdated = 0;
  int bookingsUpdated = 0;
  int notesUpdated = 0;
  int nightsUpdated = 0;
  int ledgerUpdated = 0;
  int shiftNotesUpdated = 0;
  int employeesUpdated = 0;
  int expensesUpdated = 0;
  int transactionsUpdated = 0;
  int paymentsUpdated = 0;
  int debtsUpdated = 0;
  int cyclesUpdated = 0;
  int salaryPaymentsUpdated = 0;
  
  int get totalUpdated =>
      roomsUpdated +
      bookingsUpdated +
      notesUpdated +
      nightsUpdated +
      ledgerUpdated +
      shiftNotesUpdated +
      employeesUpdated +
      expensesUpdated +
      transactionsUpdated +
      paymentsUpdated +
      debtsUpdated +
      cyclesUpdated +
      salaryPaymentsUpdated;
  
  String get summary => '''
الغرف: $roomsUpdated | الحجوزات: $bookingsUpdated | الدفعات: $paymentsUpdated
الملاحظات: $notesUpdated | الليالي: $nightsUpdated | الموظفين: $employeesUpdated
المصروفات: $expensesUpdated | المعاملات: $transactionsUpdated | الديون: $debtsUpdated
إجمالي: $totalUpdated سجل''';
}

/// نتيجة عملية التنظيف
class CleanupResult {
  bool success = false;
  String? error;
  
  int bookingsDeleted = 0;
  int paymentsDeleted = 0;
  int notesDeleted = 0;
  
  int get totalDeleted => bookingsDeleted + paymentsDeleted + notesDeleted;
}
