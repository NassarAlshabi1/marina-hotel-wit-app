/**
 * ============================================================
 * Marina Hotel - Appwrite Collections & Indexes Setup
 * ============================================================
 * JavaScript script to create all collections with indexes
 * Run in Node.js or convert to Dart
 * ============================================================
 */

const APPWRITE_CONFIG = {
  endpoint: 'https://fra.cloud.appwrite.io/v1',
  projectId: '690ff0da0025518570c1',
  databaseId: 'hotel_db',
  apiKey: process.env.APPWRITE_API_KEY || 'YOUR_API_KEY_HERE'
};

// All Collections with their fields and indexes
const COLLECTIONS = {
  // ========== CORE TABLES (6) ==========
  
  rooms: {
    name: 'Rooms',
    description: 'Hotel rooms',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'createdAtIso', type: 'string', size: 64, required: false },
      { name: 'updatedAtIso', type: 'string', size: 64, required: false },
      { name: 'deletedAtIso', type: 'string', size: 64, required: false },
      { name: 'createdAtEpoch', type: 'integer', required: false },
      { name: 'lastModificationEpoch', type: 'integer', required: false },
      { name: 'version', type: 'integer', required: false },
      { name: 'origin', type: 'string', size: 16, required: false },
      { name: 'vectorClock', type: 'string', size: 256, required: false },
      // Business fields
      { name: 'roomNumber', type: 'string', size: 20, required: true },
      { name: 'type', type: 'string', size: 32, required: true },
      { name: 'price', type: 'double', required: true },
      { name: 'status', type: 'string', size: 16, required: true },
      { name: 'imageUrl', type: 'string', size: 256, required: false },
      { name: 'cleaningStatus', type: 'string', size: 16, required: false },
      { name: 'lastCleanedHotelDay', type: 'string', size: 16, required: false },
      { name: 'lastOccupiedHotelDay', type: 'string', size: 16, required: false },
      { name: 'requiresMaintenance', type: 'boolean', required: false },
    ],
    indexes: [
      { key: 'idx_rooms_number', type: 'key', attributes: ['roomNumber'], unique: true },
      { key: 'idx_rooms_status', type: 'key', attributes: ['status', 'cleaningStatus'] },
      { key: 'idx_rooms_maintenance', type: 'key', attributes: ['requiresMaintenance'] },
    ]
  },

  bookings: {
    name: 'Bookings',
    description: 'Hotel reservations',
    fields: [
      // Sync fields
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'origin', type: 'string', size: 16, required: false },
      { name: 'vectorClock', type: 'string', size: 256, required: false },
      // Business fields
      { name: 'serverBookingId', type: 'integer', required: false },
      { name: 'roomNumber', type: 'string', size: 20, required: true },
      { name: 'guestName', type: 'string', size: 128, required: true },
      { name: 'guestPhone', type: 'string', size: 32, required: true },
      { name: 'guestIdType', type: 'string', size: 32, required: false },
      { name: 'guestIdNumber', type: 'string', size: 64, required: false },
      { name: 'guestNationality', type: 'string', size: 32, required: true },
      { name: 'guestEmail', type: 'string', size: 128, required: false },
      { name: 'checkinDate', type: 'string', size: 16, required: true },
      { name: 'checkoutDate', type: 'string', size: 16, required: false },
      { name: 'actualCheckout', type: 'string', size: 16, required: false },
      { name: 'status', type: 'string', size: 16, required: true },
      { name: 'notes', type: 'string', size: 512, required: false },
      { name: 'discount', type: 'double', required: false },
      { name: 'discountType', type: 'string', size: 16, required: false, default: '' },  // مطابق لقيمة Appwrite الفعلية
      { name: 'expectedNights', type: 'integer', required: false },
      { name: 'calculatedNights', type: 'integer', required: false },
      { name: 'totalDueCached', type: 'double', required: false },
      { name: 'totalPaidCached', type: 'double', required: false },
      { name: 'remainingBalanceCached', type: 'double', required: false },
      { name: 'isFullyPaid', type: 'boolean', required: false },
      { name: 'hotelDayCheckin', type: 'string', size: 16, required: false },
      { name: 'hotelDayCheckout', type: 'string', size: 16, required: false },
    ],
    indexes: [
      { key: 'idx_bookings_room', type: 'key', attributes: ['roomNumber'] },
      { key: 'idx_bookings_guest', type: 'key', attributes: ['guestName'] },
      { key: 'idx_bookings_status', type: 'key', attributes: ['status', 'hotelDayCheckin'] },
      { key: 'idx_bookings_checkin', type: 'key', attributes: ['checkinDate'] },
      { key: 'idx_bookings_deleted', type: 'key', attributes: ['deletedAt'] },
    ]
  },

  payments: {
    name: 'Payments',
    description: 'Payment records',
    fields: [
      // Sync fields
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'origin', type: 'string', size: 16, required: false },
      // Business fields
      { name: 'serverPaymentId', type: 'integer', required: false },
      { name: 'bookingLocalId', type: 'integer', required: false },
      { name: 'serverBookingId', type: 'integer', required: false },
      { name: 'roomNumber', type: 'string', size: 20, required: false },
      { name: 'amount', type: 'double', required: true },
      { name: 'paymentDate', type: 'string', size: 16, required: true },
      { name: 'notes', type: 'string', size: 256, required: false },
      { name: 'paymentMethod', type: 'string', size: 16, required: true },
      { name: 'revenueType', type: 'string', size: 16, required: false },
      { name: 'cashTransactionLocalId', type: 'integer', required: false },
      { name: 'referenceNumber', type: 'string', size: 32, required: false },
      { name: 'hotelDayKey', type: 'string', size: 16, required: false },
      { name: 'discountAmount', type: 'double', required: false },
      { name: 'isVoided', type: 'boolean', required: false },
    ],
    indexes: [
      { key: 'idx_payments_booking', type: 'key', attributes: ['bookingLocalId', 'hotelDayKey'] },
      { key: 'idx_payments_room', type: 'key', attributes: ['roomNumber', 'hotelDayKey'] },
      { key: 'idx_payments_date', type: 'key', attributes: ['paymentDate'] },
      { key: 'idx_payments_revenue', type: 'key', attributes: ['revenueType', 'hotelDayKey'] },
      { key: 'idx_payments_void', type: 'key', attributes: ['isVoided'] },
    ]
  },

  expenses: {
    name: 'Expenses',
    description: 'Expense records',
    fields: [
      // Sync fields
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'origin', type: 'string', size: 16, required: false },
      // Business fields
      { name: 'expenseType', type: 'string', size: 32, required: true },
      { name: 'relatedId', type: 'integer', required: false },
      { name: 'description', type: 'string', size: 256, required: true },
      { name: 'amount', type: 'double', required: true },
      { name: 'date', type: 'string', size: 16, required: true },
      { name: 'cashTransactionId', type: 'integer', required: false },
      { name: 'hotelDayKey', type: 'string', size: 16, required: false },
      { name: 'categoryUuid', type: 'string', size: 64, required: false },
      { name: 'isAutoGenerated', type: 'boolean', required: false },
    ],
    indexes: [
      { key: 'idx_expenses_day', type: 'key', attributes: ['hotelDayKey'] },
      { key: 'idx_expenses_type', type: 'key', attributes: ['expenseType'] },
      { key: 'idx_expenses_category', type: 'key', attributes: ['categoryUuid'] },
    ]
  },

  employees: {
    name: 'Employees',
    description: 'Hotel employees',
    fields: [
      // Sync fields
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'origin', type: 'string', size: 16, required: false },
      // Business fields
      { name: 'name', type: 'string', size: 128, required: true },
      { name: 'basicSalary', type: 'double', required: true },
      { name: 'position', type: 'string', size: 32, required: false },
      { name: 'phone', type: 'string', size: 32, required: false },
      { name: 'hireDate', type: 'string', size: 16, required: false },
      { name: 'status', type: 'string', size: 16, required: true },
    ],
    indexes: [
      { key: 'idx_employees_status', type: 'key', attributes: ['status'] },
      { key: 'idx_employees_name', type: 'key', attributes: ['name'] },
    ]
  },

  debts: {
    name: 'Debts',
    description: 'Guest debts',
    fields: [
      // Sync fields
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'origin', type: 'string', size: 16, required: false },
      // Business fields
      { name: 'bookingLocalId', type: 'integer', required: false },
      { name: 'guestName', type: 'string', size: 128, required: true },
      { name: 'checkinDate', type: 'string', size: 16, required: true },
      { name: 'checkoutDate', type: 'string', size: 16, required: false },
      { name: 'dateRecorded', type: 'string', size: 16, required: false },
      { name: 'debtReason', type: 'string', size: 128, required: false },
      { name: 'totalAmount', type: 'double', required: true },
      { name: 'paidAmount', type: 'double', required: true },
      { name: 'remainingAmount', type: 'integer', required: true },  // Appwrite: integer
      { name: 'paymentDate', type: 'string', size: 16, required: false },
      { name: 'isSettled', type: 'integer', required: false },
      { name: 'pledge', type: 'string', size: 256, required: false },
      { name: 'note', type: 'string', size: 512, required: false },
      { name: 'debtUuid', type: 'string', size: 64, required: false },
      { name: 'hotelDayOpened', type: 'string', size: 16, required: false },
      { name: 'isFromAutoFix', type: 'boolean', required: false },
    ],
    indexes: [
      { key: 'idx_debts_status', type: 'key', attributes: ['isSettled', 'isFromAutoFix'] },
      { key: 'idx_debts_guest', type: 'key', attributes: ['guestName'] },
      { key: 'idx_debts_booking', type: 'key', attributes: ['bookingLocalId'] },
    ]
  },

  // ========== EXTENDED TABLES (13) ==========

  booking_notes: {
    name: 'Booking Notes',
    description: 'Booking notes and alerts',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'origin', type: 'string', size: 16, required: false },
      { name: 'bookingId', type: 'integer', required: true },
      { name: 'noteText', type: 'string', size: 1024, required: true },
      { name: 'alertType', type: 'string', size: 16, required: false },
      { name: 'alertUntil', type: 'string', size: 16, required: false },
      { name: 'isActive', type: 'integer', required: false },
    ],
    indexes: [
      { key: 'idx_booking_notes_booking', type: 'key', attributes: ['bookingId'] },
    ]
  },

  cash_transactions: {
    name: 'Cash Transactions',
    description: 'Cash transaction records',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'registerId', type: 'integer', required: false },
      { name: 'transactionType', type: 'string', size: 16, required: true },
      { name: 'amount', type: 'integer', required: true },  // Appwrite: integer
      { name: 'referenceType', type: 'string', size: 16, required: false },
      { name: 'referenceId', type: 'integer', required: false },
      { name: 'description', type: 'string', size: 256, required: false },
      { name: 'transactionTime', type: 'string', size: 16, required: true },
      { name: 'createdBy', type: 'integer', required: false },
    ],
    indexes: [
      { key: 'idx_cash_type', type: 'key', attributes: ['transactionType'] },
      { key: 'idx_cash_time', type: 'key', attributes: ['transactionTime'] },
    ]
  },

  booking_nights: {
    name: 'Booking Nights',
    description: 'Booking nights tracking',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'bookingLocalId', type: 'integer', required: true },
      { name: 'hotelDayKey', type: 'string', size: 16, required: true },
      { name: 'nightStart', type: 'string', size: 16, required: true },
      { name: 'nightEnd', type: 'string', size: 16, required: true },
      { name: 'nightlyRate', type: 'double', required: false },
      { name: 'sequence', type: 'integer', required: false },
      { name: 'isProcessedByAutoFix', type: 'boolean', required: false, default: true },  // مطابق لقيمة Appwrite الفعلية
      { name: 'baseRate', type: 'double', required: false },
      { name: 'adjustment', type: 'double', required: false },
      { name: 'finalRate', type: 'double', required: false },
      { name: 'appliedAdjustmentUuid', type: 'string', size: 64, required: false },
      { name: 'appliedAdjustmentsJson', type: 'string', size: 10000, required: false },
    ],
    indexes: [
      { key: 'idx_nights_booking', type: 'key', attributes: ['bookingLocalId', 'hotelDayKey'], unique: true },
    ]
  },

  hotel_day_ledger: {
    name: 'Hotel Day Ledger',
    description: 'Daily hotel ledger',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'hotelDayKey', type: 'string', size: 16, required: true },
      { name: 'totalIncome', type: 'double', required: false },
      { name: 'totalExpenses', type: 'double', required: false },
      { name: 'pendingBalances', type: 'double', required: false },
      { name: 'occupancyRate', type: 'double', required: false },
      { name: 'bookingsProcessed', type: 'integer', required: false },
      { name: 'paymentsProcessed', type: 'integer', required: false },
      { name: 'expensesProcessed', type: 'integer', required: false },
      { name: 'status', type: 'string', size: 16, required: false },
    ],
    indexes: [
      { key: 'idx_ledger_day', type: 'key', attributes: ['hotelDayKey'], unique: true },
    ]
  },

  salary_cycles: {
    name: 'Salary Cycles',
    description: 'Employee salary cycles',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'employeeId', type: 'integer', required: true },
      { name: 'cycleKey', type: 'string', size: 16, required: true },
      { name: 'hotelDayStart', type: 'string', size: 16, required: false },
      { name: 'hotelDayEnd', type: 'string', size: 16, required: false },
      { name: 'expectedAmount', type: 'double', required: false },  // Appwrite: double
      { name: 'actualPaid', type: 'double', required: false },  // Appwrite: double
      { name: 'remainingAmount', type: 'double', required: false },  // Appwrite: double
      { name: 'status', type: 'string', size: 16, required: false },
    ],
    indexes: [
      { key: 'idx_salary_cycle', type: 'key', attributes: ['employeeId', 'cycleKey'], unique: true },
    ]
  },

  salary_payments: {
    name: 'Salary Payments',
    description: 'Salary payment records',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'cycleId', type: 'integer', required: true },
      { name: 'amount', type: 'integer', required: false },  // Appwrite: integer
      { name: 'hotelDayKey', type: 'string', size: 16, required: false },
      { name: 'paymentDateIso', type: 'string', size: 16, required: true },
      { name: 'method', type: 'string', size: 16, required: false },
      { name: 'isAutoGenerated', type: 'boolean', required: false },
    ],
    indexes: [
      { key: 'idx_salary_pay_cycle', type: 'key', attributes: ['cycleId', 'hotelDayKey'] },
    ]
  },

  salary_withdrawals: {
    name: 'Salary Withdrawals',
    description: 'Salary withdrawals',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'employeeId', type: 'integer', required: true },
      { name: 'amount', type: 'integer', required: true },  // Appwrite: integer
      { name: 'withdrawDate', type: 'string', size: 16, required: true },
      { name: 'reason', type: 'string', size: 256, required: false },
      { name: 'hotelDayKey', type: 'string', size: 16, required: false },
      { name: 'withdrawalType', type: 'string', size: 16, required: false },
      { name: 'description', type: 'string', size: 256, required: false },
    ],
    indexes: [
      { key: 'idx_withdrawals_employee', type: 'key', attributes: ['employeeId'] },
      { key: 'idx_withdrawals_date', type: 'key', attributes: ['withdrawDate'] },
    ]
  },

  shift_notes: {
    name: 'Shift Notes',
    description: 'Shift notes',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'title', type: 'string', size: 128, required: true },
      { name: 'content', type: 'string', size: 2048, required: true },
      { name: 'priority', type: 'string', size: 16, required: false },
      { name: 'shiftType', type: 'string', size: 16, required: false },
      { name: 'isRead', type: 'boolean', required: false },  // Appwrite: boolean
      { name: 'expiresAt', type: 'string', size: 16, required: false },
      { name: 'createdBy', type: 'string', size: 32, required: false },
    ],
    indexes: [
      { key: 'idx_shift_priority', type: 'key', attributes: ['priority'] },
      { key: 'idx_shift_read', type: 'key', attributes: ['isRead'] },
    ]
  },

  blacklist: {
    name: 'Blacklist',
    description: 'Blacklisted guests',
    fields: [
      // حقول المزامنة المخصصة — createdAt/updatedAt/deletedAt نصية هنا
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'string', size: 30, required: true },  // ISO 8601 string في Appwrite
      { name: 'updatedAt', type: 'string', size: 30, required: true },  // ISO 8601 string في Appwrite
      { name: 'deletedAt', type: 'string', size: 30, required: false },  // ISO 8601 string في Appwrite
      { name: 'lastModified', type: 'integer', required: true },
      { name: 'origin', type: 'string', size: 20, required: false },
      { name: 'syncTimestamp', type: 'integer', required: false },
      { name: 'idempotencyKey', type: 'string', size: 128, required: false },  // Appwrite: varchar
      { name: 'createdatEpoch', type: 'string', size: 30, required: false },  // Appwrite: string (خطأ إملائي محفوظ)
      // حقول القائمة السوداء
      { name: 'name', type: 'string', size: 200, required: true },
      { name: 'nationality', type: 'string', size: 100, required: false },
      { name: 'nationalId', type: 'string', size: 50, required: false },
      { name: 'phone', type: 'string', size: 30, required: false },
      { name: 'reason', type: 'string', size: 5000, required: false },
      { name: 'notes', type: 'string', size: 5000, required: false },
      { name: 'reportedBy', type: 'string', size: 50, required: false },
      { name: 'active', type: 'boolean', required: false },
    ],
    indexes: [
      { key: 'idx_bl_name', type: 'key', attributes: ['name'] },
      { key: 'idx_bl_modified', type: 'key', attributes: ['lastModified'] },
    ]
  },

  price_adjustments: {
    name: 'Price Adjustments',
    description: 'Price adjustments',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'targetType', type: 'string', size: 16, required: true },
      { name: 'targetUuid', type: 'string', size: 64, required: true },
      { name: 'adjustmentType', type: 'string', size: 16, required: true },
      { name: 'previousValue', type: 'double', required: true },  // Appwrite: double
      { name: 'newValue', type: 'double', required: true },  // Appwrite: double
      { name: 'reason', type: 'string', size: 256, required: false },
      { name: 'effectiveDate', type: 'string', size: 16, required: true },
      { name: 'appliedBy', type: 'string', size: 32, required: false },
      { name: 'hotelDayKey', type: 'string', size: 16, required: false },
      { name: 'isReversed', type: 'boolean', required: false },
    ],
    indexes: [
      { key: 'idx_price_target', type: 'key', attributes: ['targetType', 'targetUuid'] },
      { key: 'idx_price_day', type: 'key', attributes: ['hotelDayKey'] },
    ]
  },

  booking_price_adjustments: {
    name: 'Booking Price Adjustments',
    description: 'Booking price adjustments',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'bookingLocalUuid', type: 'string', size: 64, required: true },
      { name: 'bookingLocalId', type: 'integer', required: false },
      { name: 'roomNumber', type: 'string', size: 20, required: false },
      { name: 'adjustmentType', type: 'integer', required: false },
      { name: 'adjustmentMode', type: 'string', size: 16, required: false },
      { name: 'amount', type: 'integer', required: false },  // Appwrite: integer
      { name: 'effectiveHotelDay', type: 'string', size: 16, required: true },
      { name: 'endHotelDay', type: 'string', size: 16, required: false },
      { name: 'isActive', type: 'boolean', required: false },
      { name: 'reason', type: 'string', size: 256, required: false },
      { name: 'appliedBy', type: 'string', size: 32, required: false },
    ],
    indexes: [
      { key: 'idx_bk_price_booking', type: 'key', attributes: ['bookingLocalUuid', 'isActive'] },
      { key: 'idx_bk_price_dates', type: 'key', attributes: ['effectiveHotelDay', 'endHotelDay'] },
    ]
  },

  audit_logs: {
    name: 'Audit Logs',
    description: 'System audit logs',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'operationType', type: 'string', size: 16, required: true },
      { name: 'entityType', type: 'string', size: 32, required: true },
      { name: 'entityUuid', type: 'string', size: 64, required: true },
      { name: 'entityId', type: 'integer', required: false },
      { name: 'previousState', type: 'string', size: 1024, required: false },
      { name: 'newState', type: 'string', size: 1024, required: false },
      { name: 'changedFields', type: 'string', size: 256, required: false },
      { name: 'performedBy', type: 'string', size: 32, required: true },
      { name: 'deviceId', type: 'string', size: 64, required: false },
      { name: 'ipAddress', type: 'string', size: 32, required: false },
      { name: 'hotelDayKey', type: 'string', size: 16, required: false },
      { name: 'timestamp', type: 'integer', required: true },
      { name: 'timestampIso', type: 'string', size: 32, required: true },
      { name: 'isFinancial', type: 'boolean', required: false },
      { name: 'amountImpact', type: 'double', required: false },  // Appwrite: double
      { name: 'createdAt', type: 'integer', required: true },
    ],
    indexes: [
      { key: 'idx_audit_entity', type: 'key', attributes: ['entityType', 'entityUuid'] },
      { key: 'idx_audit_timestamp', type: 'key', attributes: ['timestamp'] },
      { key: 'idx_audit_financial', type: 'key', attributes: ['isFinancial', 'hotelDayKey'] },
    ]
  },

  payment_voids: {
    name: 'Payment Voids',
    description: 'Payment void records',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'originalPaymentUuid', type: 'string', size: 64, required: true },
      { name: 'originalPaymentId', type: 'integer', required: true },
      { name: 'bookingUuid', type: 'string', size: 64, required: true },
      { name: 'voidedAmount', type: 'integer', required: true },  // Appwrite: integer ✓
      { name: 'voidReason', type: 'string', size: 256, required: true },
      { name: 'voidedBy', type: 'string', size: 32, required: true },
      { name: 'voidedAt', type: 'integer', required: true },
      { name: 'voidedAtIso', type: 'string', size: 32, required: true },
      { name: 'hotelDayKey', type: 'string', size: 16, required: true },
      { name: 'reversalPaymentUuid', type: 'string', size: 64, required: false },
      { name: 'approvedBy', type: 'string', size: 32, required: false },
    ],
    indexes: [
      { key: 'idx_void_booking', type: 'key', attributes: ['bookingUuid'] },
      { key: 'idx_void_day', type: 'key', attributes: ['hotelDayKey'] },
    ]
  },

  guest_infos: {
    name: 'Guest Infos',
    description: 'Guest information',
    fields: [
      { name: 'localUuid', type: 'string', size: 64, required: true },
      { name: 'serverId', type: 'integer', required: false },
      { name: 'createdAt', type: 'integer', required: true },
      { name: 'updatedAt', type: 'integer', required: true },
      { name: 'deletedAt', type: 'integer', required: false },
      { name: 'lastModification', type: 'integer', required: true },
      { name: 'version', type: 'integer', required: false },
      { name: 'roomNumber', type: 'string', size: 20, required: true },
      { name: 'guestName', type: 'string', size: 128, required: true },
      { name: 'nationality', type: 'string', size: 32, required: true },
      { name: 'idNumber', type: 'string', size: 64, required: true },
      { name: 'idType', type: 'string', size: 32, required: false },
      { name: 'issueDate', type: 'string', size: 16, required: false },
      { name: 'issuePlace', type: 'string', size: 64, required: false },
      { name: 'governorate', type: 'string', size: 64, required: false },
      { name: 'notes', type: 'string', size: 512, required: false },
    ],
    indexes: [
      { key: 'idx_guest_room', type: 'key', attributes: ['roomNumber'] },
      { key: 'idx_guest_name', type: 'key', attributes: ['guestName'] },
    ]
  },
};

// Sync fields template (added to all tables)
const SYNC_FIELDS = [
  { name: 'localUuid', type: 'string', size: 64, required: true },
  { name: 'serverId', type: 'integer', required: false },
  { name: 'createdAt', type: 'integer', required: true },
  { name: 'updatedAt', type: 'integer', required: true },
  { name: 'deletedAt', type: 'integer', required: false },
  { name: 'lastModification', type: 'integer', required: true },
  { name: 'createdAtIso', type: 'string', size: 64, required: false },
  { name: 'updatedAtIso', type: 'string', size: 64, required: false },
  { name: 'deletedAtIso', type: 'string', size: 64, required: false },
  { name: 'createdAtEpoch', type: 'integer', required: false },
  { name: 'lastModificationEpoch', type: 'integer', required: false },
  { name: 'version', type: 'integer', required: false },
  { name: 'origin', type: 'string', size: 16, required: false },
  { name: 'vectorClock', type: 'string', size: 256, required: false },
];

// Summary
function printSummary() {
  console.log('═'.repeat(60));
  console.log('🏨 Marina Hotel - Appwrite Collections & Indexes');
  console.log('═'.repeat(60));
  console.log('');
  
  const collectionNames = Object.keys(COLLECTIONS);
  console.log(`📦 Total Collections: ${collectionNames.length}`);
  console.log('');
  
  // Core + Extended
  console.log('━━ Core Tables (6) ━━');
  ['rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts']
    .forEach(c => console.log(`  ✓ ${c}`));
  console.log('');
  
  console.log('━━ Extended Tables (13) ━━');
  ['booking_notes', 'cash_transactions', 'booking_nights', 'hotel_day_ledger',
   'salary_cycles', 'salary_payments', 'salary_withdrawals', 'shift_notes',
   'price_adjustments', 'booking_price_adjustments', 'audit_logs', 'payment_voids', 'guest_infos']
    .forEach(c => console.log(`  ✓ ${c}`));
  console.log('');
  
  console.log('━ Summary ━');
  console.log(`  Sync Fields: ${SYNC_FIELDS.length} fields (auto-added)`);
  console.log(`  Total Fields: ~25-30 per collection`);
  console.log(`  Indexes: 2-5 per collection`);
  console.log('═'.repeat(60));
}

printSummary();

module.exports = { COLLECTIONS, SYNC_FIELDS, APPWRITE_CONFIG };