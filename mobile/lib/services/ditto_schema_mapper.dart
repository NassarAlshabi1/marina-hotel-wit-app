import 'package:flutter/foundation.dart';
import 'local_db.dart';

/// خريطة تطابق بين قاعدة البيانات المحلية (Drift) و Ditto Collections
/// 
/// هذا الملف يحدد كيفية تحويل البيانات بين النظامين لضمان التطابق التام
class DittoSchemaMapper {
  /// أسماء المجموعات في Ditto - يجب أن تطابق أسماء الجداول في local_db.dart
  static const String roomsCollection = 'rooms';
  static const String bookingsCollection = 'bookings';
  static const String bookingNotesCollection = 'booking_notes';
  static const String employeesCollection = 'employees';
  static const String expensesCollection = 'expenses';
  static const String cashTransactionsCollection = 'cash_transactions';
  static const String paymentsCollection = 'payments';
  static const String debtsCollection = 'debts';
  static const String shiftNotesCollection = 'shift_notes';
  
  /// قائمة جميع المجموعات
  static const List<String> allCollections = [
    roomsCollection,
    bookingsCollection,
    bookingNotesCollection,
    employeesCollection,
    expensesCollection,
    cashTransactionsCollection,
    paymentsCollection,
    debtsCollection,
    shiftNotesCollection,
  ];

  // ========================================
  // تحويل من Drift إلى Ditto
  // ========================================

  /// تحويل Room من Drift إلى Ditto Document
  static Map<String, dynamic> roomToDitto(Room room) {
    return {
      '_id': room.localUuid,
      'id': room.id,
      'room_number': room.roomNumber,
      'type': room.type,
      'price': room.price,
      'status': room.status,
      'image_url': room.imageUrl,
      // حقول المزامنة
      'local_uuid': room.localUuid,
      'server_id': room.serverId,
      'created_at': room.createdAt,
      'updated_at': room.updatedAt,
      'deleted_at': room.deletedAt,
      'last_modified': room.lastModified,
      'version': room.version,
      'origin': room.origin,
    };
  }

  /// تحويل Booking من Drift إلى Ditto Document
  static Map<String, dynamic> bookingToDitto(Booking booking) {
    return {
      '_id': booking.localUuid,
      'id': booking.id,
      'server_booking_id': booking.serverBookingId,
      'room_number': booking.roomNumber,
      'guest_name': booking.guestName,
      'guest_phone': booking.guestPhone,
      'guest_id_type': booking.guestIdType,
      'guest_id_number': booking.guestIdNumber,
      'guest_id_issue_date': booking.guestIdIssueDate,
      'guest_id_issue_place': booking.guestIdIssuePlace,
      'guest_nationality': booking.guestNationality,
      'guest_email': booking.guestEmail,
      'guest_address': booking.guestAddress,
      'checkin_date': booking.checkinDate,
      'checkout_date': booking.checkoutDate,
      'actual_checkout': booking.actualCheckout,
      'status': booking.status,
      'notes': booking.notes,
      'expected_nights': booking.expectedNights,
      'calculated_nights': booking.calculatedNights,
      // حقول المزامنة
      'local_uuid': booking.localUuid,
      'server_id': booking.serverId,
      'created_at': booking.createdAt,
      'updated_at': booking.updatedAt,
      'deleted_at': booking.deletedAt,
      'last_modified': booking.lastModified,
      'version': booking.version,
      'origin': booking.origin,
    };
  }

  /// تحويل BookingNote من Drift إلى Ditto Document
  static Map<String, dynamic> bookingNoteToDitto(BookingNote note) {
    return {
      '_id': note.localUuid,
      'id': note.id,
      'booking_id': note.bookingId,
      'note_text': note.noteText,
      'alert_type': note.alertType,
      'alert_until': note.alertUntil,
      'is_active': note.isActive,
      // حقول المزامنة
      'local_uuid': note.localUuid,
      'server_id': note.serverId,
      'created_at': note.createdAt,
      'updated_at': note.updatedAt,
      'deleted_at': note.deletedAt,
      'last_modified': note.lastModified,
      'version': note.version,
      'origin': note.origin,
    };
  }

  /// تحويل Employee من Drift إلى Ditto Document
  static Map<String, dynamic> employeeToDitto(Employee employee) {
    return {
      '_id': employee.localUuid,
      'id': employee.id,
      'name': employee.name,
      'basic_salary': employee.basicSalary,
      'position': employee.position,
      'phone': employee.phone,
      'hire_date': employee.hireDate,
      'status': employee.status,
      // حقول المزامنة
      'local_uuid': employee.localUuid,
      'server_id': employee.serverId,
      'created_at': employee.createdAt,
      'updated_at': employee.updatedAt,
      'deleted_at': employee.deletedAt,
      'last_modified': employee.lastModified,
      'version': employee.version,
      'origin': employee.origin,
    };
  }

  /// تحويل Expense من Drift إلى Ditto Document
  static Map<String, dynamic> expenseToDitto(Expense expense) {
    return {
      '_id': expense.localUuid,
      'id': expense.id,
      'expense_type': expense.expenseType,
      'related_id': expense.relatedId,
      'description': expense.description,
      'amount': expense.amount,
      'date': expense.date,
      'cash_transaction_id': expense.cashTransactionId,
      // حقول المزامنة
      'local_uuid': expense.localUuid,
      'server_id': expense.serverId,
      'created_at': expense.createdAt,
      'updated_at': expense.updatedAt,
      'deleted_at': expense.deletedAt,
      'last_modified': expense.lastModified,
      'version': expense.version,
      'origin': expense.origin,
    };
  }

  /// تحويل CashTransaction من Drift إلى Ditto Document
  static Map<String, dynamic> cashTransactionToDitto(CashTransaction transaction) {
    return {
      '_id': transaction.localUuid,
      'id': transaction.id,
      'register_id': transaction.registerId,
      'transaction_type': transaction.transactionType,
      'amount': transaction.amount,
      'reference_type': transaction.referenceType,
      'reference_id': transaction.referenceId,
      'description': transaction.description,
      'transaction_time': transaction.transactionTime,
      'created_by': transaction.createdBy,
      // حقول المزامنة
      'local_uuid': transaction.localUuid,
      'server_id': transaction.serverId,
      'created_at': transaction.createdAt,
      'updated_at': transaction.updatedAt,
      'deleted_at': transaction.deletedAt,
      'last_modified': transaction.lastModified,
      'version': transaction.version,
      'origin': transaction.origin,
    };
  }

  /// تحويل Payment من Drift إلى Ditto Document
  static Map<String, dynamic> paymentToDitto(Payment payment) {
    return {
      '_id': payment.localUuid,
      'id': payment.id,
      'server_payment_id': payment.serverPaymentId,
      'booking_local_id': payment.bookingLocalId,
      'server_booking_id': payment.serverBookingId,
      'room_number': payment.roomNumber,
      'amount': payment.amount,
      'payment_date': payment.paymentDate,
      'notes': payment.notes,
      'payment_method': payment.paymentMethod,
      'revenue_type': payment.revenueType,
      'cash_transaction_local_id': payment.cashTransactionLocalId,
      'cash_transaction_server_id': payment.cashTransactionServerId,
      'reference_number': payment.referenceNumber,
      // حقول المزامنة
      'local_uuid': payment.localUuid,
      'server_id': payment.serverId,
      'created_at': payment.createdAt,
      'updated_at': payment.updatedAt,
      'deleted_at': payment.deletedAt,
      'last_modified': payment.lastModified,
      'version': payment.version,
      'origin': payment.origin,
    };
  }

  /// تحويل Debt من Drift إلى Ditto Document
  static Map<String, dynamic> debtToDitto(Debt debt) {
    return {
      '_id': debt.localUuid,
      'id': debt.id,
      'booking_local_id': debt.bookingLocalId,
      'guest_name': debt.guestName,
      'checkin_date': debt.checkinDate,
      'checkout_date': debt.checkoutDate,
      'date_recorded': debt.dateRecorded,
      'debt_reason': debt.debtReason,
      'total_amount': debt.totalAmount,
      'paid_amount': debt.paidAmount,
      'remaining_amount': debt.remainingAmount,
      'payment_date': debt.paymentDate,
      'is_settled': debt.isSettled,
      'pledge': debt.pledge,
      'pledge_type': debt.pledgeType,
      'note': debt.note,
      // حقول المزامنة
      'local_uuid': debt.localUuid,
      'server_id': debt.serverId,
      'created_at': debt.createdAt,
      'updated_at': debt.updatedAt,
      'deleted_at': debt.deletedAt,
      'last_modified': debt.lastModified,
      'version': debt.version,
      'origin': debt.origin,
    };
  }

  /// تحويل ShiftNote من Drift إلى Ditto Document
  static Map<String, dynamic> shiftNoteToDitto(ShiftNote note) {
    return {
      '_id': note.id.toString(),
      'id': note.id,
      'title': note.title,
      'content': note.content,
      'priority': note.priority,
      'shift_type': note.shiftType,
      'is_read': note.isRead,
      'created_at': note.createdAt,
      'expires_at': note.expiresAt,
      'created_by': note.createdBy,
    };
  }

  // ========================================
  // تحويل من Ditto إلى Drift
  // ========================================

  /// تحويل Ditto Document إلى Room Companion (للإدراج في Drift)
  static RoomsCompanion dittoToRoomCompanion(Map<String, dynamic> doc) {
    return RoomsCompanion.insert(
      localUuid: doc['local_uuid'] as String,
      roomNumber: doc['room_number'] as String,
      type: doc['type'] as String,
      price: doc['price'] as double,
      status: doc['status'] as String,
      imageUrl: Value(doc['image_url'] as String?),
      serverId: Value(doc['server_id'] as int?),
      createdAt: doc['created_at'] as int,
      updatedAt: doc['updated_at'] as int,
      deletedAt: Value(doc['deleted_at'] as int?),
      lastModified: doc['last_modified'] as int,
      version: Value(doc['version'] as int),
      origin: Value(doc['origin'] as String),
    );
  }

  // يمكن إضافة المزيد من دوال التحويل من Ditto إلى Drift حسب الحاجة

  /// التحقق من صحة البيانات قبل التحويل
  static bool validateDittoDocument(Map<String, dynamic> doc, String collection) {
    // التحقق من وجود الحقول الأساسية
    if (!doc.containsKey('_id')) {
      debugPrint('⚠️ مستند Ditto يفتقد _id في $collection');
      return false;
    }

    if (!doc.containsKey('local_uuid')) {
      debugPrint('⚠️ مستند Ditto يفتقد local_uuid في $collection');
      return false;
    }

    return true;
  }

  /// الحصول على اسم المجموعة من نوع الكيان
  static String? getCollectionName(Type entityType) {
    final typeName = entityType.toString();
    
    if (typeName == 'Room') return roomsCollection;
    if (typeName == 'Booking') return bookingsCollection;
    if (typeName == 'BookingNote') return bookingNotesCollection;
    if (typeName == 'Employee') return employeesCollection;
    if (typeName == 'Expense') return expensesCollection;
    if (typeName == 'CashTransaction') return cashTransactionsCollection;
    if (typeName == 'Payment') return paymentsCollection;
    if (typeName == 'Debt') return debtsCollection;
    if (typeName == 'ShiftNote') return shiftNotesCollection;
    
    return null;
  }
}

/// معلومات مخطط Ditto لكل مجموعة
class DittoCollectionSchema {
  final String name;
  final List<String> requiredFields;
  final List<String> indexedFields;

  const DittoCollectionSchema({
    required this.name,
    required this.requiredFields,
    required this.indexedFields,
  });

  /// مخطط مجموعة الغرف
  static const rooms = DittoCollectionSchema(
    name: 'rooms',
    requiredFields: ['_id', 'local_uuid', 'room_number', 'type', 'price', 'status'],
    indexedFields: ['room_number', 'status', 'last_modified'],
  );

  /// مخطط مجموعة الحجوزات
  static const bookings = DittoCollectionSchema(
    name: 'bookings',
    requiredFields: ['_id', 'local_uuid', 'room_number', 'guest_name', 'guest_phone', 'checkin_date', 'status'],
    indexedFields: ['room_number', 'guest_phone', 'status', 'checkin_date', 'last_modified'],
  );

  /// مخطط مجموعة المدفوعات
  static const payments = DittoCollectionSchema(
    name: 'payments',
    requiredFields: ['_id', 'local_uuid', 'amount', 'payment_date'],
    indexedFields: ['booking_local_id', 'payment_date', 'payment_method', 'last_modified'],
  );

  /// الحصول على جميع المخططات
  static const List<DittoCollectionSchema> allSchemas = [
    rooms,
    bookings,
    payments,
  ];
}
