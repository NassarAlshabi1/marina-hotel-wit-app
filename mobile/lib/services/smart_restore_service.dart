import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import '../utils/debug_logs.dart';
import '../utils/time.dart';
import 'backup_serializers.dart';
import 'local_db.dart';

/// خدمة استعادة ذكية تدمج البيانات بدلاً من الحذف الكامل
/// تقلل من فقدان البيانات وتحسن الأداء
///
/// إصلاحات مهمة:
/// - استخدام localUuid للمطابقة بدلاً من id
/// - إعادة ربط العلاقات بين الجداول (مثل payments -> bookings)
/// - إعادة حساب الحقول المخزنة مؤقتاً بعد الاستعادة
class SmartRestoreService {
  final AppDatabase db;

  /// خريطة لتحويل localUuid الحجوزات إلى id المحلي
  final Map<String, int> _bookingUuidToLocalId = {};

  /// خريطة لتحويل localUuid المعاملات النقدية إلى id المحلي
  final Map<String, int> _cashTransactionUuidToLocalId = {};

  SmartRestoreService(this.db);

  void _log(String message) {
    DebugLogs.add('SmartRestore', message);
    debugPrint(message);
  }

  /// استراتيجية الدمج الذكي - تحدث البيانات الموجودة بدلاً من حذفها
  /// - أسرع من الحذف الكامل
  /// - أكثر أماناً
  /// - يحتفظ بالبيانات المحلية غير الموجودة في النسخة الاحتياطية
  /// - يعيد ربط العلاقات بشكل صحيح باستخدام localUuid
  Future<RestoreResult> smartMerge(Map<String, dynamic> backupData) async {
    final result = RestoreResult();

    try {
      _log('🧠 بدء الدمج الذكي للبيانات...');

      // مسح الخرائط قبل البدء
      _bookingUuidToLocalId.clear();
      _cashTransactionUuidToLocalId.clear();

      await db.transaction(() async {
        // 1. استعادة الغرف أولاً (لا تعتمد على جداول أخرى)
        if (backupData.containsKey('rooms')) {
          result.roomsUpdated = await _mergeRooms(backupData['rooms']);
        }

        // 2. استعادة الحجوزات وبناء خريطة UUID -> ID
        if (backupData.containsKey('bookings')) {
          result.bookingsUpdated = await _mergeBookings(backupData['bookings']);
        }

        // 3. استعادة ملاحظات الحجز
        if (backupData.containsKey('booking_notes')) {
          result.notesUpdated =
              await _mergeBookingNotes(backupData['booking_notes']);
        }

        // 4. استعادة ليالي الحجز
        if (backupData.containsKey('booking_nights')) {
          result.nightsUpdated =
              await _mergeBookingNights(backupData['booking_nights']);
        }

        // 5. استعادة دفتر اليومية
        if (backupData.containsKey('hotel_day_ledger')) {
          result.ledgerUpdated =
              await _mergeLedger(backupData['hotel_day_ledger']);
        }

        // 6. استعادة ملاحظات الشفت
        if (backupData.containsKey('shift_notes')) {
          result.shiftNotesUpdated =
              await _mergeShiftNotes(backupData['shift_notes']);
        }

        // 7. استعادة الموظفين
        if (backupData.containsKey('employees')) {
          result.employeesUpdated =
              await _mergeEmployees(backupData['employees']);
        }

        // 8. استعادة المصروفات
        if (backupData.containsKey('expenses')) {
          result.expensesUpdated = await _mergeExpenses(backupData['expenses']);
        }

        // 9. استعادة معاملات النقد وبناء خريطة UUID -> ID
        if (backupData.containsKey('cash_transactions')) {
          result.transactionsUpdated =
              await _mergeCashTransactions(backupData['cash_transactions']);
        }

        // 10. استعادة الدفعات مع إعادة ربط العلاقات
        if (backupData.containsKey('payments')) {
          result.paymentsUpdated = await _mergePayments(backupData['payments']);
        }

        // 11. استعادة الديون مع إعادة ربط العلاقات
        if (backupData.containsKey('debts')) {
          result.debtsUpdated = await _mergeDebts(backupData['debts']);
        }

        // 12. استعادة دورات الرواتب
        if (backupData.containsKey('salary_cycles')) {
          result.cyclesUpdated =
              await _mergeSalaryCycles(backupData['salary_cycles']);
        }

        // 13. استعادة مدفوعات الرواتب
        if (backupData.containsKey('salary_payments')) {
          result.salaryPaymentsUpdated =
              await _mergeSalaryPayments(backupData['salary_payments']);
        }
      });

      // إعادة حساب الحقول المخزنة مؤقتاً بعد الاستعادة
      _log('🔄 إعادة حساب الحقول المخزنة مؤقتاً...');
      await _recalculateAllCachedFields();

      result.success = true;
      _log('✅ الدمج الذكي مكتمل: ${result.summary}');
    } catch (e, stack) {
      result.success = false;
      result.error = e.toString();
      _log('❌ فشل الدمج الذكي: $e\n$stack');
    }

    return result;
  }

  /// دمج الغرف باستخدام localUuid
  Future<int> _mergeRooms(dynamic roomsData) async {
    if (roomsData is! List) return 0;

    int count = 0;
    for (final roomJson in roomsData) {
      try {
        final map = Map<String, dynamic>.from(roomJson as Map);
        final backupRoom =
            Room.fromJson(map, serializer: lenientValueSerializer);

        // البحث عن الغرفة باستخدام localUuid أو roomNumber
        final existingRoom = await (db.select(db.rooms)
              ..where((r) =>
                  r.localUuid.equals(backupRoom.localUuid) |
                  r.roomNumber.equals(backupRoom.roomNumber)))
            .getSingleOrNull();

        if (existingRoom != null) {
          // تحديث الغرفة الموجودة
          await (db.update(db.rooms)
                ..where((r) => r.id.equals(existingRoom.id)))
              .write(RoomsCompanion(
            type: Value(backupRoom.type),
            price: Value(backupRoom.price),
            status: Value(backupRoom.status),
            imageUrl: Value(backupRoom.imageUrl),
            cleaningStatus: Value(backupRoom.cleaningStatus),
            lastCleanedHotelDay: Value(backupRoom.lastCleanedHotelDay),
            lastOccupiedHotelDay: Value(backupRoom.lastOccupiedHotelDay),
            requiresMaintenance: Value(backupRoom.requiresMaintenance),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          // إدراج غرفة جديدة بدون id (سيتم توليده تلقائياً)
          await db.into(db.rooms).insert(RoomsCompanion.insert(
                localUuid: backupRoom.localUuid,
                roomNumber: backupRoom.roomNumber,
                type: backupRoom.type,
                price: backupRoom.price,
                status: backupRoom.status,
                imageUrl: Value(backupRoom.imageUrl),
                cleaningStatus: Value(backupRoom.cleaningStatus),
                lastCleanedHotelDay: Value(backupRoom.lastCleanedHotelDay),
                lastOccupiedHotelDay: Value(backupRoom.lastOccupiedHotelDay),
                requiresMaintenance: Value(backupRoom.requiresMaintenance),
                createdAt: backupRoom.createdAt,
                updatedAt: backupRoom.updatedAt,
                lastModified: backupRoom.lastModified,
              ));
        }
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج غرفة: $e');
      }
    }

    _log('📊 تم دمج $count غرفة');
    return count;
  }

  /// دمج الحجوزات مع بناء خريطة UUID -> ID
  Future<int> _mergeBookings(dynamic bookingsData) async {
    if (bookingsData is! List) return 0;

    int count = 0;
    for (final bookingJson in bookingsData) {
      try {
        final map = Map<String, dynamic>.from(bookingJson as Map);
        final backupBooking =
            Booking.fromJson(map, serializer: lenientValueSerializer);

        // التحقق من وجود الغرفة المرتبطة
        final roomExists = await _checkRoomExists(backupBooking.roomNumber);
        if (!roomExists) {
          _log(
              '⚠️ تخطي حجز ${backupBooking.localUuid} - الغرفة ${backupBooking.roomNumber} غير موجودة');
          continue;
        }

        // البحث عن الحجز باستخدام localUuid
        final existingBooking = await (db.select(db.bookings)
              ..where((b) => b.localUuid.equals(backupBooking.localUuid)))
            .getSingleOrNull();

        int localId;
        if (existingBooking != null) {
          localId = existingBooking.id;
          // تحديث الحجز الموجود
          await (db.update(db.bookings)
                ..where((b) => b.id.equals(existingBooking.id)))
              .write(BookingsCompanion(
            serverBookingId: Value(backupBooking.serverBookingId),
            roomNumber: Value(backupBooking.roomNumber),
            guestName: Value(backupBooking.guestName),
            guestPhone: Value(backupBooking.guestPhone),
            guestNationality: Value(backupBooking.guestNationality),
            guestIdType: Value(backupBooking.guestIdType),
            guestIdNumber: Value(backupBooking.guestIdNumber),
            checkinDate: Value(backupBooking.checkinDate),
            checkoutDate: Value(backupBooking.checkoutDate),
            actualCheckout: Value(backupBooking.actualCheckout),
            status: Value(backupBooking.status),
            notes: Value(backupBooking.notes),
            expectedNights: Value(backupBooking.expectedNights),
            calculatedNights: Value(backupBooking.calculatedNights),
            totalDueCached: Value(backupBooking.totalDueCached),
            totalPaidCached: Value(backupBooking.totalPaidCached),
            remainingBalanceCached: Value(backupBooking.remainingBalanceCached),
            isFullyPaid: Value(backupBooking.isFullyPaid),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          // إدراج حجز جديد
          localId = await db.into(db.bookings).insert(BookingsCompanion.insert(
                localUuid: backupBooking.localUuid,
                roomNumber: backupBooking.roomNumber,
                guestName: backupBooking.guestName,
                guestPhone: Value(backupBooking.guestPhone),
                guestNationality: Value(backupBooking.guestNationality),
                guestIdType: Value(backupBooking.guestIdType),
                guestIdNumber: Value(backupBooking.guestIdNumber),
                checkinDate: backupBooking.checkinDate,
                checkoutDate: Value(backupBooking.checkoutDate),
                actualCheckout: Value(backupBooking.actualCheckout),
                status: backupBooking.status,
                notes: Value(backupBooking.notes),
                expectedNights: Value(backupBooking.expectedNights),
                calculatedNights: Value(backupBooking.calculatedNights),
                totalDueCached: Value(backupBooking.totalDueCached),
                totalPaidCached: Value(backupBooking.totalPaidCached),
                remainingBalanceCached:
                    Value(backupBooking.remainingBalanceCached),
                isFullyPaid: Value(backupBooking.isFullyPaid),
                createdAt: backupBooking.createdAt,
                updatedAt: backupBooking.updatedAt,
                lastModified: backupBooking.lastModified,
              ));
        }

        // تخزين العلاقة في الخريطة
        _bookingUuidToLocalId[backupBooking.localUuid] = localId;
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج حجز: $e');
      }
    }

    _log(
        '📊 تم دمج $count حجز، خريطة UUID: ${_bookingUuidToLocalId.length} عنصر');
    return count;
  }

  /// دمج ملاحظات الحجز مع إعادة ربط bookingId
  Future<int> _mergeBookingNotes(dynamic notesData) async {
    if (notesData is! List) return 0;

    int count = 0;
    for (final noteJson in notesData) {
      try {
        final map = Map<String, dynamic>.from(noteJson as Map);
        final backupNote =
            BookingNote.fromJson(map, serializer: lenientValueSerializer);

        // البحث عن الملاحظة باستخدام localUuid
        final existingNote = await (db.select(db.bookingNotes)
              ..where((n) => n.localUuid.equals(backupNote.localUuid)))
            .getSingleOrNull();

        // إيجاد bookingId الصحيح من الخريطة
        int? correctBookingId = backupNote.bookingId;

        // البحث عن الحجز المرتبط باستخدام bookingUuidCache أو البحث المباشر
        if (map.containsKey('bookingUuidCache') &&
            map['bookingUuidCache'] != null) {
          final bookingUuid = map['bookingUuidCache'] as String;
          if (_bookingUuidToLocalId.containsKey(bookingUuid)) {
            correctBookingId = _bookingUuidToLocalId[bookingUuid];
          }
        }

        if (existingNote != null) {
          await (db.update(db.bookingNotes)
                ..where((n) => n.id.equals(existingNote.id)))
              .write(BookingNotesCompanion(
            bookingId: Value(correctBookingId ?? existingNote.bookingId),
            noteText: Value(backupNote.noteText),
            alertType: Value(backupNote.alertType),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          await db.into(db.bookingNotes).insert(BookingNotesCompanion.insert(
                localUuid: backupNote.localUuid,
                bookingId: correctBookingId ?? backupNote.bookingId,
                noteText: backupNote.noteText,
                alertType: backupNote.alertType,
                createdAt: backupNote.createdAt,
                updatedAt: backupNote.updatedAt,
                lastModified: backupNote.lastModified,
              ));
        }
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج ملاحظة: $e');
      }
    }

    _log('📊 تم دمج $count ملاحظة حجز');
    return count;
  }

  /// دمج ليالي الحجز مع إعادة ربط bookingLocalId
  Future<int> _mergeBookingNights(dynamic nightsData) async {
    if (nightsData is! List) return 0;

    int count = 0;
    for (final nightJson in nightsData) {
      try {
        final map = Map<String, dynamic>.from(nightJson as Map);
        final backupNight =
            BookingNight.fromJson(map, serializer: lenientValueSerializer);

        // البحث عن الليلة باستخدام localUuid
        final existingNight = await (db.select(db.bookingNights)
              ..where((n) => n.localUuid.equals(backupNight.localUuid)))
            .getSingleOrNull();

        // إيجاد bookingLocalId الصحيح
        int? correctBookingId = backupNight.bookingLocalId;
        if (map.containsKey('bookingUuidCache') &&
            map['bookingUuidCache'] != null) {
          final bookingUuid = map['bookingUuidCache'] as String;
          if (_bookingUuidToLocalId.containsKey(bookingUuid)) {
            correctBookingId = _bookingUuidToLocalId[bookingUuid];
          }
        }

        if (existingNight != null) {
          await (db.update(db.bookingNights)
                ..where((n) => n.id.equals(existingNight.id)))
              .write(BookingNightsCompanion(
            bookingLocalId:
                Value(correctBookingId ?? existingNight.bookingLocalId),
            hotelDayKey: Value(backupNight.hotelDayKey),
            nightStart: Value(backupNight.nightStart),
            nightEnd: Value(backupNight.nightEnd),
            nightlyRate: Value(backupNight.nightlyRate),
            sequence: Value(backupNight.sequence),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          await db.into(db.bookingNights).insert(BookingNightsCompanion.insert(
                localUuid: backupNight.localUuid,
                bookingLocalId: correctBookingId ?? backupNight.bookingLocalId,
                hotelDayKey: backupNight.hotelDayKey,
                nightStart: backupNight.nightStart,
                nightEnd: backupNight.nightEnd,
                nightlyRate: Value(backupNight.nightlyRate),
                sequence: Value(backupNight.sequence),
                createdAt: backupNight.createdAt,
                updatedAt: backupNight.updatedAt,
                lastModified: backupNight.lastModified,
              ));
        }
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
        final backupLedger = HotelDayLedgerEntry.fromJson(map,
            serializer: lenientValueSerializer);

        // البحث باستخدام localUuid أو hotelDayKey
        final existingLedger = await (db.select(db.hotelDayLedger)
              ..where((l) =>
                  l.localUuid.equals(backupLedger.localUuid) |
                  l.hotelDayKey.equals(backupLedger.hotelDayKey)))
            .getSingleOrNull();

        if (existingLedger != null) {
          await (db.update(db.hotelDayLedger)
                ..where((l) => l.id.equals(existingLedger.id)))
              .write(HotelDayLedgerCompanion(
            totalIncome: Value(backupLedger.totalIncome),
            totalExpenses: Value(backupLedger.totalExpenses),
            pendingBalances: Value(backupLedger.pendingBalances),
            occupancyRate: Value(backupLedger.occupancyRate),
            bookingsProcessed: Value(backupLedger.bookingsProcessed),
            paymentsProcessed: Value(backupLedger.paymentsProcessed),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          await db
              .into(db.hotelDayLedger)
              .insert(HotelDayLedgerCompanion.insert(
                localUuid: backupLedger.localUuid,
                hotelDayKey: backupLedger.hotelDayKey,
                totalIncome: Value(backupLedger.totalIncome),
                totalExpenses: Value(backupLedger.totalExpenses),
                pendingBalances: Value(backupLedger.pendingBalances),
                occupancyRate: Value(backupLedger.occupancyRate),
                bookingsProcessed: Value(backupLedger.bookingsProcessed),
                paymentsProcessed: Value(backupLedger.paymentsProcessed),
                createdAt: backupLedger.createdAt,
                updatedAt: backupLedger.updatedAt,
                lastModified: backupLedger.lastModified,
              ));
        }
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
        final data =
            ShiftNote.fromJson(map, serializer: lenientValueSerializer);
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
        final backupEmployee =
            Employee.fromJson(map, serializer: lenientValueSerializer);

        // البحث باستخدام localUuid
        final existingEmployee = await (db.select(db.employees)
              ..where((e) => e.localUuid.equals(backupEmployee.localUuid)))
            .getSingleOrNull();

        if (existingEmployee != null) {
          await (db.update(db.employees)
                ..where((e) => e.id.equals(existingEmployee.id)))
              .write(EmployeesCompanion(
            name: Value(backupEmployee.name),
            phone: Value(backupEmployee.phone),
            position: Value(backupEmployee.position),
            basicSalary: Value(backupEmployee.basicSalary),
            status: Value(backupEmployee.status),
            hireDate: Value(backupEmployee.hireDate),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          await db.into(db.employees).insertOnConflictUpdate(backupEmployee);
        }
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
        final backupExpense =
            Expense.fromJson(map, serializer: lenientValueSerializer);

        // البحث باستخدام localUuid
        final existingExpense = await (db.select(db.expenses)
              ..where((e) => e.localUuid.equals(backupExpense.localUuid)))
            .getSingleOrNull();

        if (existingExpense != null) {
          await (db.update(db.expenses)
                ..where((e) => e.id.equals(existingExpense.id)))
              .write(ExpensesCompanion(
            expenseType: Value(backupExpense.expenseType),
            amount: Value(backupExpense.amount),
            description: Value(backupExpense.description),
            date: Value(backupExpense.date),
            hotelDayKey: Value(backupExpense.hotelDayKey),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          await db.into(db.expenses).insertOnConflictUpdate(backupExpense);
        }
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج مصروف: $e');
      }
    }

    _log('📊 تم دمج $count مصروف');
    return count;
  }

  /// دمج معاملات النقد وبناء خريطة UUID -> ID
  Future<int> _mergeCashTransactions(dynamic transactionsData) async {
    if (transactionsData is! List) return 0;

    int count = 0;
    for (final transactionJson in transactionsData) {
      try {
        final map = Map<String, dynamic>.from(transactionJson as Map);
        final backupTransaction =
            CashTransaction.fromJson(map, serializer: lenientValueSerializer);

        // البحث باستخدام localUuid
        final existingTransaction = await (db.select(db.cashTransactions)
              ..where((t) => t.localUuid.equals(backupTransaction.localUuid)))
            .getSingleOrNull();

        int localId;
        if (existingTransaction != null) {
          localId = existingTransaction.id;
          await (db.update(db.cashTransactions)
                ..where((t) => t.id.equals(existingTransaction.id)))
              .write(CashTransactionsCompanion(
            registerId: Value(backupTransaction.registerId),
            transactionType: Value(backupTransaction.transactionType),
            amount: Value(backupTransaction.amount),
            referenceType: Value(backupTransaction.referenceType),
            referenceId: Value(backupTransaction.referenceId),
            description: Value(backupTransaction.description),
            transactionTime: Value(backupTransaction.transactionTime),
            createdBy: Value(backupTransaction.createdBy),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          localId = await db
              .into(db.cashTransactions)
              .insert(CashTransactionsCompanion.insert(
                localUuid: backupTransaction.localUuid,
                registerId: Value(backupTransaction.registerId),
                transactionType: backupTransaction.transactionType,
                amount: backupTransaction.amount,
                referenceType: Value(backupTransaction.referenceType),
                referenceId: Value(backupTransaction.referenceId),
                description: Value(backupTransaction.description),
                transactionTime: backupTransaction.transactionTime,
                createdBy: Value(backupTransaction.createdBy),
                createdAt: backupTransaction.createdAt,
                updatedAt: backupTransaction.updatedAt,
                lastModified: backupTransaction.lastModified,
              ));
        }

        // تخزين العلاقة في الخريطة
        _cashTransactionUuidToLocalId[backupTransaction.localUuid] = localId;
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج معاملة نقدية: $e');
      }
    }

    _log('📊 تم دمج $count معاملة نقدية');
    return count;
  }

  /// دمج الدفعات مع إعادة ربط العلاقات بشكل صحيح
  /// هذه الدالة حرجة - تضمن ربط الدفعات بالحجوزات الصحيحة
  Future<int> _mergePayments(dynamic paymentsData) async {
    if (paymentsData is! List) return 0;

    int count = 0;
    int skipped = 0;

    for (final paymentJson in paymentsData) {
      try {
        final map = Map<String, dynamic>.from(paymentJson as Map);
        final backupPayment =
            Payment.fromJson(map, serializer: lenientValueSerializer);

        // إيجاد bookingLocalId الصحيح باستخدام bookingUuidCache
        int? correctBookingId;

        // أولاً: محاولة استخدام bookingUuidCache
        if (backupPayment.bookingUuidCache != null &&
            _bookingUuidToLocalId.containsKey(backupPayment.bookingUuidCache)) {
          correctBookingId =
              _bookingUuidToLocalId[backupPayment.bookingUuidCache];
        }

        // ثانياً: البحث عن الحجز باستخدام localUuid من البيانات المخزنة
        if (correctBookingId == null &&
            map.containsKey('booking_uuid') &&
            map['booking_uuid'] != null) {
          final bookingUuid = map['booking_uuid'] as String;
          if (_bookingUuidToLocalId.containsKey(bookingUuid)) {
            correctBookingId = _bookingUuidToLocalId[bookingUuid];
          }
        }

        // ثالثاً: البحث عن الحجز في قاعدة البيانات باستخدام bookingLocalId الأصلي
        if (correctBookingId == null && backupPayment.bookingLocalId != null) {
          // البحث عن الحجز بنفس id (قد يكون نفسه في بعض الحالات)
          final booking = await (db.select(db.bookings)
                ..where((b) => b.id.equals(backupPayment.bookingLocalId!)))
              .getSingleOrNull();
          if (booking != null) {
            correctBookingId = booking.id;
          }
        }

        // إذا لم نجد الحجز، تخطي هذه الدفعة مع تسجيل تحذير
        if (correctBookingId == null && backupPayment.bookingLocalId != null) {
          _log(
              '⚠️ تخطي دفعة ${backupPayment.localUuid} - لم يُعثر على الحجز المرتبط');
          skipped++;
          continue;
        }

        // إيجاد cashTransactionLocalId الصحيح
        int? correctCashTransactionId;
        if (map.containsKey('cash_transaction_uuid') &&
            map['cash_transaction_uuid'] != null) {
          final cashUuid = map['cash_transaction_uuid'] as String;
          if (_cashTransactionUuidToLocalId.containsKey(cashUuid)) {
            correctCashTransactionId = _cashTransactionUuidToLocalId[cashUuid];
          }
        }

        // البحث عن الدفعة باستخدام localUuid
        final existingPayment = await (db.select(db.payments)
              ..where((p) => p.localUuid.equals(backupPayment.localUuid)))
            .getSingleOrNull();

        if (existingPayment != null) {
          // تحديث الدفعة الموجودة
          await (db.update(db.payments)
                ..where((p) => p.id.equals(existingPayment.id)))
              .write(PaymentsCompanion(
            serverPaymentId: Value(backupPayment.serverPaymentId),
            bookingLocalId:
                Value(correctBookingId ?? existingPayment.bookingLocalId),
            serverBookingId: Value(backupPayment.serverBookingId),
            roomNumber: Value(backupPayment.roomNumber),
            amount: Value(backupPayment.amount),
            paymentDate: Value(backupPayment.paymentDate),
            notes: Value(backupPayment.notes),
            paymentMethod: Value(backupPayment.paymentMethod),
            revenueType: Value(backupPayment.revenueType),
            cashTransactionLocalId: Value(correctCashTransactionId ??
                existingPayment.cashTransactionLocalId),
            cashTransactionServerId:
                Value(backupPayment.cashTransactionServerId),
            referenceNumber: Value(backupPayment.referenceNumber),
            hotelDayKey: Value(backupPayment.hotelDayKey),
            isPendingBalance: Value(backupPayment.isPendingBalance),
            linkedDebtUuid: Value(backupPayment.linkedDebtUuid),
            bookingUuidCache: Value(backupPayment.bookingUuidCache),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          // إدراج دفعة جديدة
          await db.into(db.payments).insert(PaymentsCompanion.insert(
                localUuid: backupPayment.localUuid,
                serverPaymentId: Value(backupPayment.serverPaymentId),
                bookingLocalId: Value(correctBookingId),
                serverBookingId: Value(backupPayment.serverBookingId),
                roomNumber: Value(backupPayment.roomNumber),
                amount: backupPayment.amount,
                paymentDate: backupPayment.paymentDate,
                notes: Value(backupPayment.notes),
                paymentMethod: backupPayment.paymentMethod,
                revenueType: backupPayment.revenueType,
                cashTransactionLocalId: Value(correctCashTransactionId),
                cashTransactionServerId:
                    Value(backupPayment.cashTransactionServerId),
                referenceNumber: Value(backupPayment.referenceNumber),
                hotelDayKey: Value(backupPayment.hotelDayKey),
                isPendingBalance: Value(backupPayment.isPendingBalance),
                linkedDebtUuid: Value(backupPayment.linkedDebtUuid),
                bookingUuidCache: Value(backupPayment.bookingUuidCache),
                createdAt: backupPayment.createdAt,
                updatedAt: backupPayment.updatedAt,
                lastModified: backupPayment.lastModified,
              ));
        }
        count++;
      } catch (e) {
        _log('⚠️ فشل دمج دفعة: $e');
      }
    }

    _log('📊 تم دمج $count دفعة، تم تخطي $skipped دفعة');
    return count;
  }

  /// دمج الديون مع إعادة ربط bookingLocalId
  Future<int> _mergeDebts(dynamic debtsData) async {
    if (debtsData is! List) return 0;

    int count = 0;
    for (final debtJson in debtsData) {
      try {
        final map = Map<String, dynamic>.from(debtJson as Map);
        final backupDebt =
            Debt.fromJson(map, serializer: lenientValueSerializer);

        // إيجاد bookingLocalId الصحيح
        int? correctBookingId;
        if (map.containsKey('booking_uuid') && map['booking_uuid'] != null) {
          final bookingUuid = map['booking_uuid'] as String;
          if (_bookingUuidToLocalId.containsKey(bookingUuid)) {
            correctBookingId = _bookingUuidToLocalId[bookingUuid];
          }
        }

        // البحث عن الدين باستخدام localUuid
        final existingDebt = await (db.select(db.debts)
              ..where((d) => d.localUuid.equals(backupDebt.localUuid)))
            .getSingleOrNull();

        if (existingDebt != null) {
          await (db.update(db.debts)
                ..where((d) => d.id.equals(existingDebt.id)))
              .write(DebtsCompanion(
            bookingLocalId:
                Value(correctBookingId ?? existingDebt.bookingLocalId),
            guestName: Value(backupDebt.guestName),
            checkinDate: Value(backupDebt.checkinDate),
            checkoutDate: Value(backupDebt.checkoutDate),
            dateRecorded: Value(backupDebt.dateRecorded),
            debtReason: Value(backupDebt.debtReason),
            totalAmount: Value(backupDebt.totalAmount),
            paidAmount: Value(backupDebt.paidAmount),
            remainingAmount: Value(backupDebt.remainingAmount),
            paymentDate: Value(backupDebt.paymentDate),
            isSettled: Value(backupDebt.isSettled),
            pledge: Value(backupDebt.pledge),
            pledgeType: Value(backupDebt.pledgeType),
            note: Value(backupDebt.note),
            debtUuid: Value(backupDebt.debtUuid),
            hotelDayOpened: Value(backupDebt.hotelDayOpened),
            hotelDayClosed: Value(backupDebt.hotelDayClosed),
            isFromAutoFix: Value(backupDebt.isFromAutoFix),
            settlementConfirmed: Value(backupDebt.settlementConfirmed),
            updatedAt: Value(Time.nowEpoch()),
            lastModified: Value(Time.nowEpoch()),
          ));
        } else {
          await db.into(db.debts).insertOnConflictUpdate(backupDebt);
        }
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
        final data =
            SalaryCycle.fromJson(map, serializer: lenientValueSerializer);
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
        final data =
            SalaryPayment.fromJson(map, serializer: lenientValueSerializer);
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
    final query = db.select(db.rooms)
      ..where((t) => t.roomNumber.equals(roomNumber));
    final result = await query.getSingleOrNull();
    return result != null;
  }

  /// إعادة حساب جميع الحقول المخزنة مؤقتاً لجميع الحجوزات
  /// هذه الدالة حرجة جداً - تضمن صحة المبالغ المعروضة
  Future<void> _recalculateAllCachedFields() async {
    try {
      // جلب جميع الحجوزات غير المحذوفة
      final allBookings = await (db.select(db.bookings)
            ..where((b) => b.deletedAt.isNull()))
          .get();

      _log('🔄 إعادة حساب ${allBookings.length} حجز...');

      for (final booking in allBookings) {
        try {
          // جلب جميع الدفعات المرتبطة بهذا الحجز
          final payments = await (db.select(db.payments)
                ..where((p) => p.bookingLocalId.equals(booking.id))
                ..where((p) => p.deletedAt.isNull()))
              .get();

          // حساب إجمالي المدفوع باستخدام السنتات لتجنب مشاكل الأرقام العشرية
          final totalPaidCents = payments.fold<int>(
              0, (sum, payment) => sum + (payment.amount * 100).round());
          final totalPaid = totalPaidCents / 100;

          // جلب سعر الغرفة لحساب الإجمالي المستحق
          final room = await (db.select(db.rooms)
                ..where((r) => r.roomNumber.equals(booking.roomNumber)))
              .getSingleOrNull();

          if (room == null) continue;

          final totalDue = booking.calculatedNights * room.price;
          final remainingBalance = totalDue - totalPaid;
          final isFullyPaid = remainingBalance <= 0;

          // تحديث الحقول المخزنة مؤقتاً فقط إذا كانت مختلفة
          if (booking.totalDueCached != totalDue ||
              booking.totalPaidCached != totalPaid ||
              booking.remainingBalanceCached != remainingBalance ||
              booking.isFullyPaid != isFullyPaid) {
            await (db.update(db.bookings)
                  ..where((b) => b.id.equals(booking.id)))
                .write(BookingsCompanion(
              totalDueCached: Value(totalDue),
              totalPaidCached: Value(totalPaid),
              remainingBalanceCached: Value(remainingBalance),
              isFullyPaid: Value(isFullyPaid),
              updatedAt: Value(Time.nowEpoch()),
              lastModified: Value(Time.nowEpoch()),
            ));

            _log(
                '💰 تحديث حجز #${booking.id}: المستحق=$totalDue، المدفوع=$totalPaid، المتبقي=$remainingBalance');
          }

          // تحديث الديون المرتبطة أيضاً
          final debts = await (db.select(db.debts)
                ..where((d) => d.bookingLocalId.equals(booking.id))
                ..where((d) => d.deletedAt.isNull()))
              .get();

          for (final debt in debts) {
            final isSettled = remainingBalance <= 0 ? 1 : 0;
            if (debt.totalAmount != totalDue ||
                debt.paidAmount != totalPaid ||
                debt.remainingAmount != remainingBalance ||
                debt.isSettled != isSettled) {
              await (db.update(db.debts)..where((d) => d.id.equals(debt.id)))
                  .write(DebtsCompanion(
                totalAmount: Value(totalDue),
                paidAmount: Value(totalPaid),
                remainingAmount: Value(remainingBalance),
                isSettled: Value(isSettled),
                updatedAt: Value(Time.nowEpoch()),
                lastModified: Value(Time.nowEpoch()),
              ));
            }
          }
        } catch (e) {
          _log('⚠️ فشل إعادة حساب الحجز #${booking.id}: $e');
        }
      }

      _log('✅ اكتمل إعادة حساب الحقول المخزنة');
    } catch (e) {
      _log('❌ فشل إعادة حساب الحقول المخزنة: $e');
    }
  }

  /// تنظيف السجلات اليتيمة (orphaned records)
  /// - سجلات تشير إلى سجلات رئيسية محذوفة
  Future<CleanupResult> cleanupOrphanedRecords() async {
    final result = CleanupResult();

    try {
      _log('🧹 بدء تنظيف السجلات اليتيمة...');

      await db.transaction(() async {
        // تنظيف الحجوزات بدون غرف
        final orphanedBookings = await db
            .customSelect(
              'SELECT id FROM bookings WHERE room_number NOT IN (SELECT room_number FROM rooms) AND deleted_at IS NULL',
            )
            .get();

        if (orphanedBookings.isNotEmpty) {
          for (final row in orphanedBookings) {
            final bookingId = row.data['id'] as int;
            // استخدام soft delete بدلاً من الحذف الفعلي
            await db.customStatement(
              'UPDATE bookings SET deleted_at = ? WHERE id = ?',
              [Time.nowEpoch(), bookingId],
            );
            result.bookingsDeleted++;
          }
        }

        // تنظيف الدفعات بدون حجوزات
        final orphanedPayments = await db
            .customSelect(
              'SELECT id FROM payments WHERE booking_local_id IS NOT NULL AND booking_local_id NOT IN (SELECT id FROM bookings WHERE deleted_at IS NULL) AND deleted_at IS NULL',
            )
            .get();

        if (orphanedPayments.isNotEmpty) {
          for (final row in orphanedPayments) {
            final paymentId = row.data['id'] as int;
            await db.customStatement(
              'UPDATE payments SET deleted_at = ? WHERE id = ?',
              [Time.nowEpoch(), paymentId],
            );
            result.paymentsDeleted++;
          }
        }

        // تنظيف الملاحظات بدون حجوزات
        final orphanedNotes = await db
            .customSelect(
              'SELECT id FROM booking_notes WHERE booking_id NOT IN (SELECT id FROM bookings WHERE deleted_at IS NULL) AND deleted_at IS NULL',
            )
            .get();

        if (orphanedNotes.isNotEmpty) {
          for (final row in orphanedNotes) {
            final noteId = row.data['id'] as int;
            await db.customStatement(
              'UPDATE booking_notes SET deleted_at = ? WHERE id = ?',
              [Time.nowEpoch(), noteId],
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
