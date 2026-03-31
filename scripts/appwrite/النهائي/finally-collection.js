/**
 * ═══════════════════════════════════════════════════════════════════
 * Marina Hotel - Finally Collection (Appwrite)
 * ═══════════════════════════════════════════════════════════════════
 * جميع Collections الخاصة بتطبيق فندق مارينا - مجمعة في ملف واحد
 * 
 * الاستخدام:
 *   node finally-collection.js <API_KEY>
 * 
 * للمحصول على API Key:
 *   1. افتح Appwrite Console: https://cloud.appwrite.io/console
 *   2. اذهب إلى Settings -> API Keys
 *   3. انشئ API Key مع صلاحيات: databases.write, collections.write
 * ═══════════════════════════════════════════════════════════════════
 */

const https = require('https');

// ═══════════════════════════════════════════════════════════════════
// بيانات الاتصال
// ═══════════════════════════════════════════════════════════════════
const CONFIG = {
  endpoint: 'https://fra.cloud.appwrite.io/v1',
  projectId: '690ff0da0025518570c1',
  databaseId: 'hotel_db',
};

// ═══════════════════════════════════════════════════════════════════
// Sync Fields - حقول المزامنة المشتركة تضاف لكل Collection
// ═══════════════════════════════════════════════════════════════════
const SYNC_FIELDS = [
  { key: 'serverId', type: 'integer', required: false },
  { key: 'createdAt', type: 'integer', required: true },
  { key: 'updatedAt', type: 'integer', required: true },
  { key: 'deletedAt', type: 'integer', required: false },
  { key: 'lastModified', type: 'integer', required: true },
  { key: 'createdAtIso', type: 'string', size: 50, required: false },
  { key: 'updatedAtIso', type: 'string', size: 50, required: false },
  { key: 'deletedAtIso', type: 'string', size: 50, required: false },
  { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
  { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
  { key: 'syncTimestamp', type: 'integer', required: false, default: 0 },
  { key: 'deviceId', type: 'string', size: 100, required: false, default: '' },
  { key: 'version', type: 'integer', required: false, default: 1 },
  { key: 'origin', type: 'string', size: 20, required: false, default: 'local' },
  { key: 'vectorClock', type: 'string', size: 500, required: false, default: '{}' },
];

// ═══════════════════════════════════════════════════════════════════
// تعريف جميع Collections والـ Attributes
// ═══════════════════════════════════════════════════════════════════
const COLLECTIONS = {
  // ─────────────────────────────────────────────────────────────────
  // 1. Rooms - الغرف
  // ─────────────────────────────────────────────────────────────────
  rooms: {
    name: 'Rooms',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'roomNumber', type: 'string', size: 50, required: true, unique: true },
      { key: 'type', type: 'string', size: 50, required: true },
      { key: 'price', type: 'double', required: true },
      { key: 'status', type: 'string', size: 20, required: true },
      { key: 'imageUrl', type: 'string', size: 500, required: false },
      { key: 'cleaningStatus', type: 'string', size: 20, required: false, default: 'clean' },
      { key: 'lastCleanedHotelDay', type: 'string', size: 50, required: false },
      { key: 'lastOccupiedHotelDay', type: 'string', size: 50, required: false },
      { key: 'requiresMaintenance', type: 'boolean', required: false, default: false },
    ],
    indexes: [
      { key: 'idx_room_number', type: 'unique', attributes: ['roomNumber'] },
      { key: 'idx_status', type: 'key', attributes: ['status'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 2. Bookings - الحجوزات
  // ─────────────────────────────────────────────────────────────────
  bookings: {
    name: 'Bookings',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'serverBookingId', type: 'integer', required: false },
      { key: 'roomNumber', type: 'string', size: 50, required: true },
      { key: 'guestName', type: 'string', size: 100, required: true },
      { key: 'guestPhone', type: 'string', size: 50, required: true },
      { key: 'guestIdType', type: 'string', size: 50, required: false, default: '\u0628\u0637\u0627\u0642\u0629 \u0634\u062e\u0635\u064a\u0629' },
      { key: 'guestIdNumber', type: 'string', size: 100, required: false, default: '' },
      { key: 'guestIdIssueDate', type: 'string', size: 50, required: false },
      { key: 'guestIdIssuePlace', type: 'string', size: 100, required: false },
      { key: 'guestNationality', type: 'string', size: 50, required: true },
      { key: 'guestEmail', type: 'string', size: 100, required: false },
      { key: 'guestAddress', type: 'string', size: 200, required: false },
      { key: 'checkinDate', type: 'string', size: 50, required: true },
      { key: 'checkoutDate', type: 'string', size: 50, required: false },
      { key: 'actualCheckout', type: 'string', size: 50, required: false },
      { key: 'status', type: 'string', size: 20, required: true },
      { key: 'notes', type: 'string', size: 1000, required: false },
      { key: 'expectedNights', type: 'integer', required: false, default: 1 },
      { key: 'calculatedNights', type: 'integer', required: false, default: 1 },
      { key: 'totalNightsCached', type: 'integer', required: false, default: 0 },
      { key: 'stayDurationIso', type: 'string', size: 50, required: false },
      { key: 'lastNightEpoch', type: 'integer', required: false },
      { key: 'isOverdue', type: 'boolean', required: false, default: false },
      { key: 'needsCheckoutReview', type: 'boolean', required: false, default: false },
      { key: 'totalDueCached', type: 'double', required: false, default: 0 },
      { key: 'totalPaidCached', type: 'double', required: false, default: 0 },
      { key: 'remainingBalanceCached', type: 'double', required: false, default: 0 },
      { key: 'isFullyPaid', type: 'boolean', required: false, default: false },
      { key: 'discount', type: 'double', required: false, default: 0 },
      { key: 'discountType', type: 'string', size: 20, required: false, default: 'per_night' },
      { key: 'discountStartDate', type: 'string', size: 50, required: false },
      { key: 'hotelDayCheckin', type: 'string', size: 50, required: false },
      { key: 'hotelDayCheckout', type: 'string', size: 50, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_room_status', type: 'key', attributes: ['roomNumber', 'status'] },
      { key: 'idx_status_hotel_day', type: 'key', attributes: ['status', 'hotelDayCheckin'] },
      { key: 'idx_guest_name', type: 'fulltext', attributes: ['guestName'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 3. Payments - المدفوعات
  // ─────────────────────────────────────────────────────────────────
  payments: {
    name: 'Payments',
    permissions: ['read("any")', 'create("any")', 'update("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'serverPaymentId', type: 'integer', required: false },
      { key: 'bookingLocalId', type: 'integer', required: false },
      { key: 'serverBookingId', type: 'integer', required: false },
      { key: 'roomNumber', type: 'string', size: 50, required: false },
      { key: 'amount', type: 'double', required: true },
      { key: 'paymentDate', type: 'string', size: 50, required: true },
      { key: 'notes', type: 'string', size: 500, required: false },
      { key: 'paymentMethod', type: 'string', size: 20, required: true },
      { key: 'revenueType', type: 'string', size: 20, required: true },
      { key: 'cashTransactionLocalId', type: 'integer', required: false },
      { key: 'cashTransactionServerId', type: 'integer', required: false },
      { key: 'referenceNumber', type: 'string', size: 100, required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
      { key: 'isPendingBalance', type: 'boolean', required: false, default: false },
      { key: 'linkedDebtUuid', type: 'string', size: 50, required: false },
      { key: 'bookingUuidCache', type: 'string', size: 50, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_booking_date', type: 'key', attributes: ['bookingLocalId', 'paymentDate'] },
      { key: 'idx_hotel_day_type', type: 'key', attributes: ['hotelDayKey', 'revenueType'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 4. Expenses - المصروفات
  // ─────────────────────────────────────────────────────────────────
  expenses: {
    name: 'Expenses',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'expenseType', type: 'string', size: 50, required: true },
      { key: 'relatedId', type: 'integer', required: false },
      { key: 'description', type: 'string', size: 500, required: true },
      { key: 'amount', type: 'double', required: true },
      { key: 'date', type: 'string', size: 50, required: true },
      { key: 'cashTransactionId', type: 'integer', required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
      { key: 'categoryUuid', type: 'string', size: 50, required: false },
      { key: 'cashFlowUuid', type: 'string', size: 50, required: false },
      { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_hotel_day_type', type: 'key', attributes: ['hotelDayKey', 'expenseType'] },
      { key: 'idx_date', type: 'key', attributes: ['date'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 5. Employees - الموظفين
  // ─────────────────────────────────────────────────────────────────
  employees: {
    name: 'Employees',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'name', type: 'string', size: 100, required: true },
      { key: 'basicSalary', type: 'double', required: true },
      { key: 'position', type: 'string', size: 50, required: false, default: '\u0645\u0648\u0638\u0641' },
      { key: 'phone', type: 'string', size: 50, required: false, default: '' },
      { key: 'hireDate', type: 'string', size: 50, required: false, default: '' },
      { key: 'status', type: 'string', size: 20, required: true },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_name', type: 'key', attributes: ['name'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 6. Debts - الديون
  // ─────────────────────────────────────────────────────────────────
  debts: {
    name: 'Debts',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'bookingLocalId', type: 'integer', required: false },
      { key: 'guestName', type: 'string', size: 100, required: true },
      { key: 'checkinDate', type: 'string', size: 50, required: true },
      { key: 'checkoutDate', type: 'string', size: 50, required: true },
      { key: 'dateRecorded', type: 'string', size: 50, required: false, default: '' },
      { key: 'debtReason', type: 'string', size: 200, required: false, default: '' },
      { key: 'totalAmount', type: 'double', required: true },
      { key: 'paidAmount', type: 'double', required: true },
      { key: 'remainingAmount', type: 'double', required: true },
      { key: 'paymentDate', type: 'string', size: 50, required: true },
      { key: 'isSettled', type: 'integer', required: false, default: 0 },
      { key: 'pledge', type: 'string', size: 200, required: false },
      { key: 'pledgeType', type: 'string', size: 50, required: false },
      { key: 'note', type: 'string', size: 500, required: false },
      { key: 'debtUuid', type: 'string', size: 50, required: false },
      { key: 'hotelDayOpened', type: 'string', size: 50, required: false },
      { key: 'hotelDayClosed', type: 'string', size: 50, required: false },
      { key: 'isFromAutoFix', type: 'boolean', required: false, default: false },
      { key: 'settlementConfirmed', type: 'boolean', required: false, default: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_guest_name', type: 'key', attributes: ['guestName'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 7. Devices - الاجهزة
  // ─────────────────────────────────────────────────────────────────
  devices: {
    name: 'Devices',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'deviceName', type: 'string', size: 100, required: true },
      { key: 'deviceType', type: 'string', size: 50, required: false },
      { key: 'platform', type: 'string', size: 50, required: false },
      { key: 'appVersion', type: 'string', size: 20, required: false },
      { key: 'lastSeen', type: 'string', size: 50, required: false },
      { key: 'isActive', type: 'boolean', required: false, default: true },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 8. Sync Logs - سجلات المزامنة
  // ─────────────────────────────────────────────────────────────────
  sync_logs: {
    name: 'Sync Logs',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'operation', type: 'string', size: 50, required: true },
      { key: 'collection', type: 'string', size: 50, required: true },
      { key: 'documentId', type: 'string', size: 100, required: false },
      { key: 'status', type: 'string', size: 20, required: true },
      { key: 'errorMessage', type: 'string', size: 1000, required: false },
      { key: 'timestamp', type: 'integer', required: true },
      { key: 'timestampIso', type: 'string', size: 50, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_collection_status', type: 'key', attributes: ['collection', 'status'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 9. Booking Notes - ملاحظات الحجوزات
  // ─────────────────────────────────────────────────────────────────
  booking_notes: {
    name: 'Booking Notes',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'bookingId', type: 'integer', required: true },
      { key: 'noteText', type: 'string', size: 1000, required: true },
      { key: 'alertType', type: 'string', size: 20, required: true },
      { key: 'alertUntil', type: 'string', size: 50, required: false },
      { key: 'isActive', type: 'integer', required: false, default: 1 },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_booking_id', type: 'key', attributes: ['bookingId'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 10. Cash Transactions - المعاملات النقدية
  // ─────────────────────────────────────────────────────────────────
  cash_transactions: {
    name: 'Cash Transactions',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'registerId', type: 'integer', required: false },
      { key: 'transactionType', type: 'string', size: 20, required: true },
      { key: 'amount', type: 'double', required: true },
      { key: 'referenceType', type: 'string', size: 50, required: false },
      { key: 'referenceId', type: 'integer', required: false },
      { key: 'description', type: 'string', size: 500, required: false },
      { key: 'transactionTime', type: 'string', size: 50, required: true },
      { key: 'createdBy', type: 'integer', required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_transaction_type', type: 'key', attributes: ['transactionType'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 11. Booking Nights - ليالي الحجوزات
  // ─────────────────────────────────────────────────────────────────
  booking_nights: {
    name: 'Booking Nights',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'bookingLocalId', type: 'integer', required: true },
      { key: 'hotelDayKey', type: 'string', size: 50, required: true },
      { key: 'nightStart', type: 'string', size: 50, required: true },
      { key: 'nightEnd', type: 'string', size: 50, required: true },
      { key: 'nightlyRate', type: 'double', required: false, default: 0 },
      { key: 'sequence', type: 'integer', required: false, default: 0 },
      { key: 'isProcessedByAutoFix', type: 'boolean', required: false, default: false },
      { key: 'baseRate', type: 'double', required: false, default: 0 },
      { key: 'adjustment', type: 'double', required: false, default: 0 },
      { key: 'finalRate', type: 'double', required: false, default: 0 },
      { key: 'appliedAdjustmentUuid', type: 'string', size: 36, required: false },
      { key: 'appliedAdjustmentsJson', type: 'string', size: 5000, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_booking_id', type: 'key', attributes: ['bookingLocalId'] },
      { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 12. Salary Cycles - دورات الرواتب
  // ─────────────────────────────────────────────────────────────────
  salary_cycles: {
    name: 'Salary Cycles',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'employeeId', type: 'integer', required: true },
      { key: 'cycleKey', type: 'string', size: 50, required: true },
      { key: 'hotelDayStart', type: 'string', size: 50, required: false },
      { key: 'hotelDayEnd', type: 'string', size: 50, required: false },
      { key: 'expectedAmount', type: 'double', required: false, default: 0 },
      { key: 'actualPaid', type: 'double', required: false, default: 0 },
      { key: 'remainingAmount', type: 'double', required: false, default: 0 },
      { key: 'status', type: 'string', size: 20, required: false, default: 'draft' },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_employee_id', type: 'key', attributes: ['employeeId'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 13. Salary Payments - مدفوعات الرواتب
  // ─────────────────────────────────────────────────────────────────
  salary_payments: {
    name: 'Salary Payments',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'cycleId', type: 'integer', required: true },
      { key: 'amount', type: 'double', required: false, default: 0 },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
      { key: 'paymentDateIso', type: 'string', size: 50, required: true },
      { key: 'method', type: 'string', size: 50, required: false },
      { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_cycle_id', type: 'key', attributes: ['cycleId'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 14. Salary Withdrawals - سحوبات الرواتب
  // ─────────────────────────────────────────────────────────────────
  salary_withdrawals: {
    name: 'Salary Withdrawals',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'employeeId', type: 'integer', required: true },
      { key: 'amount', type: 'double', required: true },
      { key: 'withdrawDate', type: 'string', size: 50, required: true },
      { key: 'reason', type: 'string', size: 500, required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_employee_id', type: 'key', attributes: ['employeeId'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 15. Shift Notes - ملاحظات الورديات
  // ─────────────────────────────────────────────────────────────────
  shift_notes: {
    name: 'Shift Notes',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: false,
    attributes: [
      { key: 'title', type: 'string', size: 200, required: true },
      { key: 'content', type: 'string', size: 1000, required: true },
      { key: 'priority', type: 'string', size: 20, required: false, default: 'medium' },
      { key: 'shiftType', type: 'string', size: 20, required: false, default: 'all' },
      { key: 'isRead', type: 'integer', required: false, default: 0 },
      { key: 'createdAt', type: 'string', size: 50, required: true },
      { key: 'expiresAt', type: 'string', size: 50, required: false },
      { key: 'createdBy', type: 'string', size: 50, required: false, default: 'user' },
    ],
    indexes: [
      { key: 'idx_priority', type: 'key', attributes: ['priority'] },
      { key: 'idx_created_at', type: 'key', attributes: ['createdAt'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 16. Price Adjustments - تعديلات الاسعار
  // ─────────────────────────────────────────────────────────────────
  price_adjustments: {
    name: 'Price Adjustments',
    permissions: ['read("any")', 'create("any")', 'update("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'targetType', type: 'string', size: 20, required: true },
      { key: 'targetUuid', type: 'string', size: 36, required: true },
      { key: 'adjustmentType', type: 'string', size: 30, required: true },
      { key: 'previousValue', type: 'double', required: true },
      { key: 'newValue', type: 'double', required: true },
      { key: 'reason', type: 'string', size: 500, required: false },
      { key: 'effectiveDate', type: 'string', size: 30, required: true },
      { key: 'appliedBy', type: 'string', size: 100, required: true },
      { key: 'hotelDayKey', type: 'string', size: 10, required: true },
      { key: 'isReversed', type: 'boolean', required: false, default: false },
      { key: 'reversedAt', type: 'string', size: 30, required: false },
      { key: 'reversedBy', type: 'string', size: 100, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_target', type: 'key', attributes: ['targetType', 'targetUuid'] },
      { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
      { key: 'idx_effective_date', type: 'key', attributes: ['effectiveDate'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 17. Audit Logs - سجلات التدقيق
  // ─────────────────────────────────────────────────────────────────
  audit_logs: {
    name: 'Audit Logs',
    permissions: ['read("any")', 'create("any")'],
    includeSyncFields: false,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'operationType', type: 'string', size: 30, required: true },
      { key: 'entityType', type: 'string', size: 30, required: true },
      { key: 'entityUuid', type: 'string', size: 36, required: true },
      { key: 'entityId', type: 'integer', required: false },
      { key: 'previousState', type: 'string', size: 10000, required: false },
      { key: 'newState', type: 'string', size: 10000, required: false },
      { key: 'changedFields', type: 'string', size: 2000, required: false },
      { key: 'performedBy', type: 'string', size: 100, required: true },
      { key: 'deviceId', type: 'string', size: 100, required: true },
      { key: 'ipAddress', type: 'string', size: 45, required: false },
      { key: 'hotelDayKey', type: 'string', size: 10, required: true },
      { key: 'timestamp', type: 'integer', required: true },
      { key: 'timestampIso', type: 'string', size: 30, required: true },
      { key: 'isFinancial', type: 'boolean', required: false, default: false },
      { key: 'amountImpact', type: 'double', required: false },
      { key: 'createdAt', type: 'integer', required: true },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_entity', type: 'key', attributes: ['entityType', 'entityUuid'] },
      { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
      { key: 'idx_timestamp', type: 'key', attributes: ['timestamp'], orders: ['DESC'] },
      { key: 'idx_financial', type: 'key', attributes: ['isFinancial', 'hotelDayKey'] },
      { key: 'idx_operation', type: 'key', attributes: ['operationType', 'entityType'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 18. Payment Voids - المدفوعات الملغاة
  // ─────────────────────────────────────────────────────────────────
  payment_voids: {
    name: 'Payment Voids',
    permissions: ['read("any")', 'create("any")', 'update("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'originalPaymentUuid', type: 'string', size: 36, required: true },
      { key: 'originalPaymentId', type: 'integer', required: true },
      { key: 'bookingUuid', type: 'string', size: 36, required: true },
      { key: 'voidedAmount', type: 'integer', required: true },
      { key: 'voidReason', type: 'string', size: 500, required: true },
      { key: 'voidedBy', type: 'string', size: 100, required: true },
      { key: 'voidedAt', type: 'integer', required: true },
      { key: 'voidedAtIso', type: 'string', size: 30, required: true },
      { key: 'hotelDayKey', type: 'string', size: 20, required: true },
      { key: 'reversalPaymentUuid', type: 'string', size: 36, required: false },
      { key: 'approvedBy', type: 'string', size: 100, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_original_payment', type: 'unique', attributes: ['originalPaymentUuid'] },
      { key: 'idx_booking', type: 'key', attributes: ['bookingUuid'] },
      { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
    ],
  },

  // ─────────────────────────────────────────────────────────────────
  // 19. Booking Price Adjustments - تعديلات اسعار الحجوزات
  // ─────────────────────────────────────────────────────────────────
  booking_price_adjustments: {
    name: 'Booking Price Adjustments',
    permissions: ['read("any")', 'create("any")', 'update("any")', 'delete("any")'],
    includeSyncFields: true,
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true, unique: true },
      { key: 'bookingLocalUuid', type: 'string', size: 36, required: true },
      { key: 'bookingLocalId', type: 'integer', required: false },
      { key: 'adjustmentType', type: 'integer', required: true },
      { key: 'adjustmentMode', type: 'string', size: 20, required: false, default: 'per_night' },
      { key: 'amount', type: 'double', required: true },
      { key: 'effectiveHotelDay', type: 'string', size: 10, required: true },
      { key: 'endHotelDay', type: 'string', size: 10, required: false },
      { key: 'isActive', type: 'boolean', required: false, default: true },
      { key: 'reason', type: 'string', size: 500, required: false },
      { key: 'appliedBy', type: 'string', size: 100, required: false },
      { key: 'cancelledAt', type: 'string', size: 30, required: false },
      { key: 'cancelledBy', type: 'string', size: 100, required: false },
    ],
    indexes: [
      { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_booking_uuid', type: 'key', attributes: ['bookingLocalUuid', 'isActive'] },
      { key: 'idx_dates', type: 'key', attributes: ['effectiveHotelDay', 'endHotelDay'] },
    ],
  },
};

// ═══════════════════════════════════════════════════════════════════
// دوال مساعدة للاتصال بـ Appwrite API
// ═══════════════════════════════════════════════════════════════════

function appwriteRequest(method, path, body, apiKey) {
  return new Promise((resolve, reject) => {
    const url = new URL(CONFIG.endpoint + path);
    const postData = body ? JSON.stringify(body) : null;

    const options = {
      hostname: url.hostname,
      port: 443,
      path: url.pathname + url.search,
      method: method,
      headers: {
        'Content-Type': 'application/json',
        'X-Appwrite-Project': CONFIG.projectId,
        'X-Appwrite-Key': apiKey,
        ...(postData && { 'Content-Length': Buffer.byteLength(postData) }),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          const parsed = data ? JSON.parse(data) : {};
          resolve({ status: res.statusCode, data: parsed });
        } catch {
          resolve({ status: res.statusCode, data: data });
        }
      });
    });

    req.on('error', reject);
    if (postData) req.write(postData);
    req.end();
  });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// ═══════════════════════════════════════════════════════════════════
// دوال إنشاء Collections, Attributes, Indexes
// ═══════════════════════════════════════════════════════════════════

async function createCollection(collectionId, schema, apiKey) {
  const path = `/databases/${CONFIG.databaseId}/collections`;
  const body = {
    collectionId: collectionId,
    name: schema.name,
    permissions: schema.permissions,
    documentSecurity: false,
  };

  const res = await appwriteRequest('POST', path, body, apiKey);

  if (res.status === 201) {
    console.log(`   ✅ Collection: ${collectionId} (${schema.name})`);
    return 'created';
  } else if (res.status === 409) {
    console.log(`   ℹ️  Collection: ${collectionId} (موجود مسبقاً)`);
    return 'exists';
  } else {
    console.log(`   ❌ Collection: ${collectionId} (فشل: ${res.status})`);
    console.log(`      ${JSON.stringify(res.data)}`);
    return 'error';
  }
}

function getAttributePath(type) {
  switch (type) {
    case 'string': return 'string';
    case 'integer': return 'integer';
    case 'double': return 'float';
    case 'boolean': return 'boolean';
    default: return null;
  }
}

async function addAttribute(collectionId, attr, apiKey) {
  const typePath = getAttributePath(attr.type);
  if (!typePath) {
    console.log(`   ⚠️  نوع غير معروف: ${attr.key} (${attr.type})`);
    return 'skip';
  }

  const path = `/databases/${CONFIG.databaseId}/collections/${collectionId}/attributes/${typePath}`;
  const body = { key: attr.key, required: attr.required || false };

  if (attr.type === 'string') body.size = attr.size || 255;
  if (attr.default !== undefined) body.default = attr.default;
  if (attr.unique) body.array = false;

  const res = await appwriteRequest('POST', path, body, apiKey);

  if (res.status === 201 || res.status === 202) {
    return 'success';
  } else if (res.status === 409) {
    return 'exists';
  } else {
    console.log(`      ❌ ${attr.key}: ${res.status}`);
    return 'error';
  }
}

async function createIndex(collectionId, index, apiKey) {
  const path = `/databases/${CONFIG.databaseId}/collections/${collectionId}/indexes`;
  const body = {
    key: index.key,
    type: index.type,
    attributes: index.attributes,
    orders: index.orders || index.attributes.map(() => 'ASC'),
  };

  const res = await appwriteRequest('POST', path, body, apiKey);

  if (res.status === 201 || res.status === 202) {
    console.log(`      ✅ Index: ${index.key}`);
  } else if (res.status === 409) {
    console.log(`      ℹ️  Index: ${index.key} (موجود)`);
  } else {
    console.log(`      ❌ Index: ${index.key} (${res.status})`);
  }
}

// ═══════════════════════════════════════════════════════════════════
// الدالة الرئيسية
// ═══════════════════════════════════════════════════════════════════

async function setupAllCollections(apiKey) {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║   Marina Hotel - Appwrite Collections Setup                 ║');
  console.log('║   اعداد جميع Collections لتطبيق فندق مارينا               ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
  console.log('');
  console.log(`Endpoint:   ${CONFIG.endpoint}`);
  console.log(`Project ID: ${CONFIG.projectId}`);
  console.log(`Database:   ${CONFIG.databaseId}`);
  console.log(`Collections: ${Object.keys(COLLECTIONS).length}`);
  console.log('');

  let totalCreated = 0;
  let totalExisted = 0;
  let totalErrors = 0;
  let totalAttrs = 0;
  let totalIndexes = 0;

  for (const [collectionId, schema] of Object.entries(COLLECTIONS)) {
    console.log(`\n📋 ${collectionId} (${schema.name})`);
    console.log('─'.repeat(50));

    // 1. إنشاء Collection
    const result = await createCollection(collectionId, schema, apiKey);
    if (result === 'created') totalCreated++;
    else if (result === 'exists') totalExisted++;
    else totalErrors++;

    await sleep(500);

    // 2. إضافة Attributes
    const allAttrs = [
      ...schema.attributes,
      ...(schema.includeSyncFields ? SYNC_FIELDS : []),
    ];

    let attrSuccess = 0;
    let attrExists = 0;
    let attrError = 0;

    for (const attr of allAttrs) {
      const res = await addAttribute(collectionId, attr, apiKey);
      if (res === 'success') attrSuccess++;
      else if (res === 'exists') attrExists++;
      else if (res === 'error') attrError++;
      await sleep(300);
    }

    totalAttrs += attrSuccess;
    console.log(`   📝 Attributes: +${attrSuccess} جديدة | ${attrExists} موجودة | ${attrError} فاشلة`);

    // 3. إنشاء Indexes
    if (schema.indexes && schema.indexes.length > 0) {
      console.log(`   🔍 Indexes:`);
      for (const index of schema.indexes) {
        await createIndex(collectionId, index, apiKey);
        await sleep(300);
      }
      totalIndexes += schema.indexes.length;
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // الملخص النهائي
  // ═══════════════════════════════════════════════════════════════
  console.log('\n');
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║                    الملخص النهائي                           ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Collections: ✅ ${totalCreated} جديدة | ℹ️  ${totalExisted} موجودة | ❌ ${totalErrors} فاشلة`);
  console.log(`║  Attributes:  📝 ${totalAttrs} تمت اضافتها`);
  console.log(`║  Indexes:     🔍 ${totalIndexes} تم انشاؤها`);
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  جميع Collections:                                         ║');

  for (const [id, schema] of Object.entries(COLLECTIONS)) {
    const syncTag = schema.includeSyncFields ? '🔄' : '  ';
    console.log(`║    ${syncTag} ${id.padEnd(30)} ${schema.name}`);
  }

  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log('║  ⚠️  ملاحظات:                                               ║');
  console.log('║  • الحقول قد تحتاج بضع ثوانٍ لتكون جاهزة (Indexing)       ║');
  console.log('║  • تحقق من Appwrite Console للتأكد                         ║');
  console.log('║  • hotel_day_ledger = محلي فقط (غير متزامن)                ║');
  console.log('║  • audit_logs = بدون صلاحيات حذف/تعديل                     ║');
  console.log('╚══════════════════════════════════════════════════════════════╝');
}

// ═══════════════════════════════════════════════════════════════════
// نقطة الدخول
// ═══════════════════════════════════════════════════════════════════

const apiKey = process.argv[2];

if (!apiKey) {
  console.log('❌ الاستخدام: node finally-collection.js <API_KEY>');
  console.log('');
  console.log('للحصول على API Key:');
  console.log('  1. افتح https://cloud.appwrite.io/console');
  console.log('  2. اختر المشروع -> Settings -> API Keys');
  console.log('  3. انشئ API Key مع صلاحيات: databases.write, collections.write');
  console.log('');
  console.log('Collections المدعومة:');
  for (const [id, schema] of Object.entries(COLLECTIONS)) {
    console.log(`  • ${id}: ${schema.name} (${schema.attributes.length} حقل)`);
  }
  process.exit(1);
}

setupAllCollections(apiKey).catch((err) => {
  console.error('\n❌ خطأ:', err.message);
  process.exit(1);
});
