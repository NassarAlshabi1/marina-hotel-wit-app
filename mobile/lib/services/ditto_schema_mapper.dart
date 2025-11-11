import 'package:drift/drift.dart';

import 'local_db.dart';

class DittoSchemaMapper {
  static const roomsCollection = 'rooms';
  static const bookingsCollection = 'bookings';
  static const bookingNotesCollection = 'booking_notes';
  static const employeesCollection = 'employees';
  static const expensesCollection = 'expenses';
  static const cashTransactionsCollection = 'cash_transactions';
  static const paymentsCollection = 'payments';
  static const debtsCollection = 'debts';
  static const shiftNotesCollection = 'shift_notes';

  static const allCollections = [
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

  static bool validateDittoDocument(Map<String, dynamic> doc, List<String> requiredKeys) {
    for (final key in requiredKeys) {
      final value = doc[key];
      if (value == null) {
        return false;
      }
      if (value is String && value.isEmpty) {
        return false;
      }
    }
    return true;
  }

  static Map<String, dynamic> roomToDitto(Room room) {
    final map = _syncFieldsToMap(
      localUuid: room.localUuid,
      serverId: room.serverId,
      createdAt: room.createdAt,
      updatedAt: room.updatedAt,
      deletedAt: room.deletedAt,
      lastModified: room.lastModified,
      version: room.version,
      origin: room.origin,
      id: room.id,
    );
    map['_id'] = room.localUuid;
    map['room_number'] = room.roomNumber;
    map['type'] = room.type;
    map['price'] = room.price;
    map['status'] = room.status;
    if (room.imageUrl != null) {
      map['image_url'] = room.imageUrl;
    }
    return map;
  }

  static RoomsCompanion dittoToRoomCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'room_number', 'type', 'price', 'status', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid rooms document');
    }
    final localUuid = _requireString(doc, '_id');
    final price = _requireDouble(doc, 'price');
    return RoomsCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      roomNumber: Value(_requireString(doc, 'room_number')),
      type: Value(_requireString(doc, 'type')),
      price: Value(price),
      status: Value(_requireString(doc, 'status')),
      imageUrl: _optionalString(doc, 'image_url'),
    );
  }

  static Map<String, dynamic> bookingToDitto(Booking booking) {
    final map = _syncFieldsToMap(
      localUuid: booking.localUuid,
      serverId: booking.serverId,
      createdAt: booking.createdAt,
      updatedAt: booking.updatedAt,
      deletedAt: booking.deletedAt,
      lastModified: booking.lastModified,
      version: booking.version,
      origin: booking.origin,
      id: booking.id,
    );
    map['_id'] = booking.localUuid;
    if (booking.serverBookingId != null) {
      map['server_booking_id'] = booking.serverBookingId;
    }
    map['room_number'] = booking.roomNumber;
    map['guest_name'] = booking.guestName;
    map['guest_phone'] = booking.guestPhone;
    map['guest_id_type'] = booking.guestIdType;
    map['guest_id_number'] = booking.guestIdNumber;
    if (booking.guestIdIssueDate != null) {
      map['guest_id_issue_date'] = booking.guestIdIssueDate;
    }
    if (booking.guestIdIssuePlace != null) {
      map['guest_id_issue_place'] = booking.guestIdIssuePlace;
    }
    map['guest_nationality'] = booking.guestNationality;
    if (booking.guestEmail != null) {
      map['guest_email'] = booking.guestEmail;
    }
    if (booking.guestAddress != null) {
      map['guest_address'] = booking.guestAddress;
    }
    map['checkin_date'] = booking.checkinDate;
    if (booking.checkoutDate != null) {
      map['checkout_date'] = booking.checkoutDate;
    }
    if (booking.actualCheckout != null) {
      map['actual_checkout'] = booking.actualCheckout;
    }
    map['status'] = booking.status;
    if (booking.notes != null) {
      map['notes'] = booking.notes;
    }
    map['expected_nights'] = booking.expectedNights;
    map['calculated_nights'] = booking.calculatedNights;
    return map;
  }

  static BookingsCompanion dittoToBookingCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'room_number', 'guest_name', 'guest_phone', 'guest_nationality', 'checkin_date', 'status', 'expected_nights', 'calculated_nights', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid bookings document');
    }
    final localUuid = _requireString(doc, '_id');
    return BookingsCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      serverBookingId: _optionalInt(doc, 'server_booking_id'),
      roomNumber: Value(_requireString(doc, 'room_number')),
      guestName: Value(_requireString(doc, 'guest_name')),
      guestPhone: Value(_requireString(doc, 'guest_phone')),
      guestIdType: Value(_requireString(doc, 'guest_id_type', fallback: 'بطاقة شخصية')),
      guestIdNumber: Value(_requireString(doc, 'guest_id_number', fallback: '')),
      guestIdIssueDate: _optionalString(doc, 'guest_id_issue_date'),
      guestIdIssuePlace: _optionalString(doc, 'guest_id_issue_place'),
      guestNationality: Value(_requireString(doc, 'guest_nationality')),
      guestEmail: _optionalString(doc, 'guest_email'),
      guestAddress: _optionalString(doc, 'guest_address'),
      checkinDate: Value(_requireString(doc, 'checkin_date')),
      checkoutDate: _optionalString(doc, 'checkout_date'),
      actualCheckout: _optionalString(doc, 'actual_checkout'),
      status: Value(_requireString(doc, 'status')),
      notes: _optionalString(doc, 'notes'),
      expectedNights: Value(_requireInt(doc, 'expected_nights')),
      calculatedNights: Value(_requireInt(doc, 'calculated_nights')),
    );
  }

  static Map<String, dynamic> bookingNoteToDitto(BookingNote note) {
    final map = _syncFieldsToMap(
      localUuid: note.localUuid,
      serverId: note.serverId,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
      deletedAt: note.deletedAt,
      lastModified: note.lastModified,
      version: note.version,
      origin: note.origin,
      id: note.id,
    );
    map['_id'] = note.localUuid;
    map['booking_id'] = note.bookingId;
    map['note_text'] = note.noteText;
    map['alert_type'] = note.alertType;
    if (note.alertUntil != null) {
      map['alert_until'] = note.alertUntil;
    }
    map['is_active'] = note.isActive;
    return map;
  }

  static BookingNotesCompanion dittoToBookingNoteCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'booking_id', 'note_text', 'alert_type', 'is_active', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid booking_notes document');
    }
    final localUuid = _requireString(doc, '_id');
    return BookingNotesCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      bookingId: Value(_requireInt(doc, 'booking_id')),
      noteText: Value(_requireString(doc, 'note_text')),
      alertType: Value(_requireString(doc, 'alert_type')),
      alertUntil: _optionalString(doc, 'alert_until'),
      isActive: Value(_requireInt(doc, 'is_active')),
    );
  }

  static Map<String, dynamic> employeeToDitto(Employee employee) {
    final map = _syncFieldsToMap(
      localUuid: employee.localUuid,
      serverId: employee.serverId,
      createdAt: employee.createdAt,
      updatedAt: employee.updatedAt,
      deletedAt: employee.deletedAt,
      lastModified: employee.lastModified,
      version: employee.version,
      origin: employee.origin,
      id: employee.id,
    );
    map['_id'] = employee.localUuid;
    map['name'] = employee.name;
    map['basic_salary'] = employee.basicSalary;
    map['position'] = employee.position;
    map['phone'] = employee.phone;
    map['hire_date'] = employee.hireDate;
    map['status'] = employee.status;
    return map;
  }

  static EmployeesCompanion dittoToEmployeeCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'name', 'basic_salary', 'position', 'phone', 'hire_date', 'status', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid employees document');
    }
    final localUuid = _requireString(doc, '_id');
    return EmployeesCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      name: Value(_requireString(doc, 'name')),
      basicSalary: Value(_requireDouble(doc, 'basic_salary')),
      position: Value(_requireString(doc, 'position')),
      phone: Value(_requireString(doc, 'phone')),
      hireDate: Value(_requireString(doc, 'hire_date')),
      status: Value(_requireString(doc, 'status')),
    );
  }

  static Map<String, dynamic> expenseToDitto(Expense expense) {
    final map = _syncFieldsToMap(
      localUuid: expense.localUuid,
      serverId: expense.serverId,
      createdAt: expense.createdAt,
      updatedAt: expense.updatedAt,
      deletedAt: expense.deletedAt,
      lastModified: expense.lastModified,
      version: expense.version,
      origin: expense.origin,
      id: expense.id,
    );
    map['_id'] = expense.localUuid;
    map['expense_type'] = expense.expenseType;
    if (expense.relatedId != null) {
      map['related_id'] = expense.relatedId;
    }
    map['description'] = expense.description;
    map['amount'] = expense.amount;
    map['date'] = expense.date;
    if (expense.cashTransactionId != null) {
      map['cash_transaction_id'] = expense.cashTransactionId;
    }
    return map;
  }

  static ExpensesCompanion dittoToExpenseCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'expense_type', 'description', 'amount', 'date', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid expenses document');
    }
    final localUuid = _requireString(doc, '_id');
    return ExpensesCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      expenseType: Value(_requireString(doc, 'expense_type')),
      relatedId: _optionalInt(doc, 'related_id'),
      description: Value(_requireString(doc, 'description')),
      amount: Value(_requireDouble(doc, 'amount')),
      date: Value(_requireString(doc, 'date')),
      cashTransactionId: _optionalInt(doc, 'cash_transaction_id'),
    );
  }

  static Map<String, dynamic> cashTransactionToDitto(CashTransaction tx) {
    final map = _syncFieldsToMap(
      localUuid: tx.localUuid,
      serverId: tx.serverId,
      createdAt: tx.createdAt,
      updatedAt: tx.updatedAt,
      deletedAt: tx.deletedAt,
      lastModified: tx.lastModified,
      version: tx.version,
      origin: tx.origin,
      id: tx.id,
    );
    map['_id'] = tx.localUuid;
    if (tx.registerId != null) {
      map['register_id'] = tx.registerId;
    }
    map['transaction_type'] = tx.transactionType;
    map['amount'] = tx.amount;
    if (tx.referenceType != null) {
      map['reference_type'] = tx.referenceType;
    }
    if (tx.referenceId != null) {
      map['reference_id'] = tx.referenceId;
    }
    if (tx.description != null) {
      map['description'] = tx.description;
    }
    map['transaction_time'] = tx.transactionTime;
    if (tx.createdBy != null) {
      map['created_by'] = tx.createdBy;
    }
    return map;
  }

  static CashTransactionsCompanion dittoToCashTransactionCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'transaction_type', 'amount', 'transaction_time', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid cash_transactions document');
    }
    final localUuid = _requireString(doc, '_id');
    return CashTransactionsCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      registerId: _optionalInt(doc, 'register_id'),
      transactionType: Value(_requireString(doc, 'transaction_type')),
      amount: Value(_requireDouble(doc, 'amount')),
      referenceType: _optionalString(doc, 'reference_type'),
      referenceId: _optionalInt(doc, 'reference_id'),
      description: _optionalString(doc, 'description'),
      transactionTime: Value(_requireString(doc, 'transaction_time')),
      createdBy: _optionalInt(doc, 'created_by'),
    );
  }

  static Map<String, dynamic> paymentToDitto(Payment payment) {
    final map = _syncFieldsToMap(
      localUuid: payment.localUuid,
      serverId: payment.serverId,
      createdAt: payment.createdAt,
      updatedAt: payment.updatedAt,
      deletedAt: payment.deletedAt,
      lastModified: payment.lastModified,
      version: payment.version,
      origin: payment.origin,
      id: payment.id,
    );
    map['_id'] = payment.localUuid;
    if (payment.serverPaymentId != null) {
      map['server_payment_id'] = payment.serverPaymentId;
    }
    if (payment.bookingLocalId != null) {
      map['booking_local_id'] = payment.bookingLocalId;
    }
    if (payment.serverBookingId != null) {
      map['server_booking_id'] = payment.serverBookingId;
    }
    if (payment.roomNumber != null) {
      map['room_number'] = payment.roomNumber;
    }
    map['amount'] = payment.amount;
    map['payment_date'] = payment.paymentDate;
    if (payment.notes != null) {
      map['notes'] = payment.notes;
    }
    map['payment_method'] = payment.paymentMethod;
    map['revenue_type'] = payment.revenueType;
    if (payment.cashTransactionLocalId != null) {
      map['cash_transaction_local_id'] = payment.cashTransactionLocalId;
    }
    if (payment.cashTransactionServerId != null) {
      map['cash_transaction_server_id'] = payment.cashTransactionServerId;
    }
    if (payment.referenceNumber != null) {
      map['reference_number'] = payment.referenceNumber;
    }
    return map;
  }

  static PaymentsCompanion dittoToPaymentCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'amount', 'payment_date', 'payment_method', 'revenue_type', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid payments document');
    }
    final localUuid = _requireString(doc, '_id');
    return PaymentsCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      serverPaymentId: _optionalInt(doc, 'server_payment_id'),
      bookingLocalId: _optionalInt(doc, 'booking_local_id'),
      serverBookingId: _optionalInt(doc, 'server_booking_id'),
      roomNumber: _optionalString(doc, 'room_number'),
      amount: Value(_requireDouble(doc, 'amount')),
      paymentDate: Value(_requireString(doc, 'payment_date')),
      notes: _optionalString(doc, 'notes'),
      paymentMethod: Value(_requireString(doc, 'payment_method')),
      revenueType: Value(_requireString(doc, 'revenue_type')),
      cashTransactionLocalId: _optionalInt(doc, 'cash_transaction_local_id'),
      cashTransactionServerId: _optionalInt(doc, 'cash_transaction_server_id'),
      referenceNumber: _optionalString(doc, 'reference_number'),
    );
  }

  static Map<String, dynamic> debtToDitto(Debt debt) {
    final map = _syncFieldsToMap(
      localUuid: debt.localUuid,
      serverId: debt.serverId,
      createdAt: debt.createdAt,
      updatedAt: debt.updatedAt,
      deletedAt: debt.deletedAt,
      lastModified: debt.lastModified,
      version: debt.version,
      origin: debt.origin,
      id: debt.id,
    );
    map['_id'] = debt.localUuid;
    if (debt.bookingLocalId != null) {
      map['booking_local_id'] = debt.bookingLocalId;
    }
    map['guest_name'] = debt.guestName;
    map['checkin_date'] = debt.checkinDate;
    map['checkout_date'] = debt.checkoutDate;
    map['date_recorded'] = debt.dateRecorded;
    map['debt_reason'] = debt.debtReason;
    map['total_amount'] = debt.totalAmount;
    map['paid_amount'] = debt.paidAmount;
    map['remaining_amount'] = debt.remainingAmount;
    map['payment_date'] = debt.paymentDate;
    map['is_settled'] = debt.isSettled;
    if (debt.pledge != null) {
      map['pledge'] = debt.pledge;
    }
    if (debt.pledgeType != null) {
      map['pledge_type'] = debt.pledgeType;
    }
    if (debt.note != null) {
      map['note'] = debt.note;
    }
    return map;
  }

  static DebtsCompanion dittoToDebtCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'guest_name', 'checkin_date', 'checkout_date', 'date_recorded', 'debt_reason', 'total_amount', 'paid_amount', 'remaining_amount', 'payment_date', 'is_settled', 'created_at', 'updated_at', 'last_modified', 'version', 'origin'])) {
      throw FormatException('Invalid debts document');
    }
    final localUuid = _requireString(doc, '_id');
    return DebtsCompanion(
      localUuid: Value(localUuid),
      serverId: _optionalInt(doc, 'server_id'),
      createdAt: Value(_requireInt(doc, 'created_at')),
      updatedAt: Value(_requireInt(doc, 'updated_at')),
      deletedAt: _optionalInt(doc, 'deleted_at'),
      lastModified: Value(_requireInt(doc, 'last_modified')),
      version: Value(_requireInt(doc, 'version')),
      origin: Value(_requireString(doc, 'origin')),
      id: _optionalInt(doc, 'id'),
      bookingLocalId: _optionalInt(doc, 'booking_local_id'),
      guestName: Value(_requireString(doc, 'guest_name')),
      checkinDate: Value(_requireString(doc, 'checkin_date')),
      checkoutDate: Value(_requireString(doc, 'checkout_date')),
      dateRecorded: Value(_requireString(doc, 'date_recorded')),
      debtReason: Value(_requireString(doc, 'debt_reason')),
      totalAmount: Value(_requireDouble(doc, 'total_amount')),
      paidAmount: Value(_requireDouble(doc, 'paid_amount')),
      remainingAmount: Value(_requireDouble(doc, 'remaining_amount')),
      paymentDate: Value(_requireString(doc, 'payment_date')),
      isSettled: Value(_requireInt(doc, 'is_settled')),
      pledge: _optionalString(doc, 'pledge'),
      pledgeType: _optionalString(doc, 'pledge_type'),
      note: _optionalString(doc, 'note'),
    );
  }

  static Map<String, dynamic> shiftNoteToDitto(ShiftNote note) {
    final map = <String, dynamic>{};
    map['_id'] = note.id.toString();
    map['id'] = note.id;
    map['title'] = note.title;
    map['content'] = note.content;
    map['priority'] = note.priority;
    map['shift_type'] = note.shiftType;
    map['is_read'] = note.isRead;
    map['created_at'] = note.createdAt;
    if (note.expiresAt != null) {
      map['expires_at'] = note.expiresAt;
    }
    map['created_by'] = note.createdBy;
    return map;
  }

  static ShiftNotesCompanion dittoToShiftNoteCompanion(Map<String, dynamic> doc) {
    if (!validateDittoDocument(doc, ['_id', 'title', 'content', 'priority', 'shift_type', 'is_read', 'created_at', 'created_by'])) {
      throw FormatException('Invalid shift_notes document');
    }
    final rawId = _asInt(doc['id']) ?? _requireInt(doc, '_id');
    return ShiftNotesCompanion(
      id: Value(rawId),
      title: Value(_requireString(doc, 'title')),
      content: Value(_requireString(doc, 'content')),
      priority: Value(_requireString(doc, 'priority')),
      shiftType: Value(_requireString(doc, 'shift_type')),
      isRead: Value(_requireInt(doc, 'is_read')),
      createdAt: Value(_requireString(doc, 'created_at')),
      expiresAt: _optionalString(doc, 'expires_at'),
      createdBy: Value(_requireString(doc, 'created_by')),
    );
  }

  static Map<String, dynamic> _syncFieldsToMap({
    required String localUuid,
    required int createdAt,
    required int updatedAt,
    required int lastModified,
    required int version,
    required String origin,
    required int id,
    int? serverId,
    int? deletedAt,
  }) {
    final map = <String, dynamic>{
      'local_uuid': localUuid,
      'created_at': createdAt,
      'updated_at': updatedAt,
      'last_modified': lastModified,
      'version': version,
      'origin': origin,
      'id': id,
    };
    if (serverId != null) {
      map['server_id'] = serverId;
    }
    if (deletedAt != null) {
      map['deleted_at'] = deletedAt;
    }
    return map;
  }

  static Value<int>? _optionalInt(Map<String, dynamic> doc, String key) {
    final value = _asInt(doc[key]);
    if (value == null) {
      return const Value.absent();
    }
    return Value(value);
  }

  static Value<String>? _optionalString(Map<String, dynamic> doc, String key) {
    final value = _asString(doc[key]);
    if (value == null) {
      return const Value.absent();
    }
    return Value(value);
  }

  static String _requireString(Map<String, dynamic> doc, String key, {String? fallback}) {
    final value = _asString(doc[key]) ?? fallback;
    if (value == null) {
      throw FormatException('Missing $key');
    }
    return value;
  }

  static int _requireInt(Map<String, dynamic> doc, String key) {
    final value = _asInt(doc[key]);
    if (value == null) {
      throw FormatException('Missing $key');
    }
    return value;
  }

  static double _requireDouble(Map<String, dynamic> doc, String key) {
    final value = _asDouble(doc[key]);
    if (value == null) {
      throw FormatException('Missing $key');
    }
    return value;
  }

  static String? _asString(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    return value.toString();
  }

  static int? _asInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static double? _asDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }
}
