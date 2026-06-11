#!/usr/bin/env node
/**
 * ═══════════════════════════════════════════════════════════════════════════════
 * nassar.js  —  Marina Hotel Appwrite Cloud Schema (الكامل)
 * ═══════════════════════════════════════════════════════════════════════════════
 * يجمع كل السكربتات السابقة في ملف واحد:
 *   – create_all_collections_complete.js (19 collection)
 *   – add_missing_collections.js (sync fields + 7 collections)
 *   – Final_setup_all_collections.js (23 collection كاملة)
 *   – add_all_missing_fields.js (termination, salary_withdrawals)
 *   – add_all_missing_attrs.js (rooms, bookings, payments, debts, …)
 *   – add_all_missing_attrs_combined.js (النسخة المدمجة)
 *   – create_mobile_indexes.js + appwrite_collections_indexes.js (الفهارس)
 *   – create_appwrite_collections.js (Permission API v20)
 *   – run_final_setup.js (إصدار v20 المحدّث)
 *   – verify_collections.js (التحقق)
 *
 * الاستخدام:
 *   APPWRITE_API_KEY="sk-…" node nassar.js
 *
 * متغيرات البيئة الاختيارية:
 *   APPWRITE_ENDPOINT     (default: https://fra.cloud.appwrite.io/v1)
 *   APPWRITE_PROJECT      (default: 6a2b01d0000752ce97e7)
 *   APPWRITE_DATABASE_ID  (default: 6a2b030d000445596163)
 * ═══════════════════════════════════════════════════════════════════════════════
 */

const { Client, Databases, Permission, Role } = require('node-appwrite');

// ─── الإعدادات ─────────────────────────────────────────────────────────────────
const CFG = {
  endpoint:    process.env.APPWRITE_ENDPOINT    || 'https://fra.cloud.appwrite.io/v1',
  projectId:   process.env.APPWRITE_PROJECT     || '6a2b01d0000752ce97e7',
  databaseId:  process.env.APPWRITE_DATABASE_ID || '6a2b030d000445596163',
  apiKey:      process.env.APPWRITE_API_KEY,
};

if (!CFG.apiKey) {
  console.error('❌ APPWRITE_API_KEY مطلوب');
  console.error('   مثال: APPWRITE_API_KEY="sk-…" node nassar.js');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(CFG.endpoint)
  .setProject(CFG.projectId)
  .setKey(CFG.apiKey);
const db = new Databases(client);
const sleep = (ms) => new Promise(r => setTimeout(r, ms));

const PERMISSIONS = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

// ─── حقول المزامنة المشتركة ──────────────────────────────────────────────────
const SF = [
  { key: 'localUuid',      type: 'string',  required: true,  size: 64 },
  { key: 'serverId',       type: 'integer', required: false },
  { key: 'createdAt',      type: 'integer', required: true },
  { key: 'updatedAt',      type: 'integer', required: true },
  { key: 'deletedAt',      type: 'integer', required: false },
  { key: 'lastModified',   type: 'integer', required: true },
  { key: 'createdAtIso',   type: 'string',  required: false, size: 30 },
  { key: 'updatedAtIso',   type: 'string',  required: false, size: 30 },
  { key: 'deletedAtIso',   type: 'string',  required: false, size: 30 },
  { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
  { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
  { key: 'version',        type: 'integer', required: false, default: 1 },
  { key: 'origin',         type: 'string',  required: false, default: 'local', size: 20 },
  { key: 'vectorClock',    type: 'string',  required: false, default: '{}', size: 2000 },
  { key: 'deviceId',       type: 'string',  required: false, default: '', size: 100 },
  { key: 'syncTimestamp',  type: 'integer', required: false, default: 0 },
];

const SI = [
  { key: 'idx_sf_modified', type: 'key', attributes: ['lastModified'] },
];

// ═══════════════════════════════════════════════════════════════════════════════
// جميع Collections — الحقول والفهارس
// ═══════════════════════════════════════════════════════════════════════════════

const COLLECTIONS = {

  // ═══ 1. SYSTEM ═══════════════════════════════════════════════════════════════
  devices: {
    name: 'الأجهزة',
    attrs: [
      { key: 'deviceId',   type: 'string',  required: true,  size: 64 },
      { key: 'deviceName', type: 'string',  required: false, size: 200 },
      { key: 'platform',   type: 'string',  required: false, size: 30 },
      { key: 'appVersion', type: 'string',  required: false, size: 20 },
      { key: 'fcmToken',   type: 'string',  required: false, size: 500 },
      { key: 'lastSeen',   type: 'integer', required: false },
      { key: 'isActive',   type: 'boolean', required: false, default: true },
    ],
    indexes: [
      { key: 'idx_devices_id', type: 'unique', attributes: ['deviceId'] },
    ],
  },

  sync_logs: {
    name: 'سجل المزامنة',
    attrs: [
      { key: 'deviceId',   type: 'string',  required: true,  size: 64 },
      { key: 'syncType',   type: 'string',  required: true,  size: 20 },
      { key: 'status',     type: 'string',  required: true,  size: 20 },
      { key: 'records',    type: 'integer', required: false },
      { key: 'durationMs', type: 'integer', required: false },
      { key: 'error',      type: 'string',  required: false, size: 10000 },
      { key: 'timestamp',  type: 'integer', required: true },
    ],
    indexes: [
      { key: 'idx_sl_device', type: 'key', attributes: ['deviceId'] },
      { key: 'idx_sl_time',   type: 'key', attributes: ['timestamp'] },
    ],
  },

  app_settings: {
    name: 'إعدادات التطبيق',
    attrs: [
      { key: 'key',   type: 'string', required: true,  size: 100 },
      { key: 'value', type: 'string', required: true,  size: 5000 },
      { key: 'deviceId', type: 'string', required: false, size: 64 },
      { key: 'createdAt', type: 'integer', required: true },
    ],
    indexes: [
      { key: 'idx_as_key', type: 'unique', attributes: ['key'] },
    ],
  },

  app_users: {
    name: 'مستخدمو التطبيق',
    attrs: [
      { key: 'username',   type: 'string',  required: false, size: 100,  default: '' },
      { key: 'password',   type: 'string',  required: false, size: 500,  default: '' },
      { key: 'fullName',   type: 'string',  required: false, size: 200,  default: '' },
      { key: 'userType',   type: 'string',  required: false, size: 50,   default: 'employee' },
      { key: 'permissions', type: 'string', required: false, size: 2000, default: '[]' },
      { key: 'active',     type: 'boolean', required: false, default: true },
      { key: 'lastLogin',  type: 'integer', required: false, default: 0 },
      { key: 'version',    type: 'integer', required: false, default: 1 },
    ],
  },

  // ═══ 2. CORE ════════════════════════════════════════════════════════════════
  rooms: {
    name: 'الغرف',
    attrs: [
      ...SF,
      { key: 'roomNumber',          type: 'string',  required: true,  size: 20 },
      { key: 'type',                type: 'string',  required: true,  size: 50 },
      { key: 'price',               type: 'float',   required: true },
      { key: 'status',              type: 'string',  required: true,  size: 30 },
      { key: 'imageUrl',            type: 'string',  required: false, size: 2000 },
      { key: 'cleaningStatus',      type: 'string',  required: false, size: 30,  default: 'clean' },
      { key: 'lastCleanedHotelDay', type: 'string',  required: false, size: 20 },
      { key: 'lastOccupiedHotelDay', type: 'string', required: false, size: 20 },
      { key: 'requiresMaintenance', type: 'boolean', required: false, default: false },
      { key: 'basePrice',           type: 'float',   required: false },
      { key: 'floor',               type: 'integer', required: false },
      { key: 'bedsCount',           type: 'integer', required: false },
    ],
    indexes: [
      ...SI,
      { key: 'idx_rooms_number', type: 'unique', attributes: ['roomNumber'] },
      { key: 'idx_rooms_status', type: 'key',    attributes: ['status', 'cleaningStatus'] },
      { key: 'idx_rooms_type',   type: 'key',    attributes: ['type'] },
      { key: 'idx_rooms_serverId', type: 'key',  attributes: ['serverId'] },
    ],
  },

  bookings: {
    name: 'الحجوزات',
    attrs: [
      ...SF,
      { key: 'serverBookingId',  type: 'integer', required: false },
      { key: 'roomNumber',       type: 'string',  required: true,  size: 20 },
      { key: 'guestName',        type: 'string',  required: true,  size: 200 },
      { key: 'guestPhone',       type: 'string',  required: true,  size: 30 },
      { key: 'guestIdType',      type: 'string',  required: false, size: 50,  default: 'بطاقة شخصية' },
      { key: 'guestIdNumber',    type: 'string',  required: false, size: 50,  default: '' },
      { key: 'guestIdIssueDate', type: 'string',  required: false, size: 20 },
      { key: 'guestIdIssuePlace', type: 'string',  required: false, size: 100 },
      { key: 'guestNationality', type: 'string',  required: true,  size: 100 },
      { key: 'guestEmail',       type: 'string',  required: false, size: 255 },
      { key: 'guestAddress',     type: 'string',  required: false, size: 300 },
      { key: 'checkinDate',      type: 'string',  required: true,  size: 20 },
      { key: 'checkoutDate',     type: 'string',  required: false, size: 20 },
      { key: 'actualCheckout',   type: 'string',  required: false, size: 20 },
      { key: 'status',           type: 'string',  required: true,  size: 30 },
      { key: 'notes',            type: 'string',  required: false, size: 5000 },
      { key: 'expectedNights',   type: 'integer', required: false, default: 1 },
      { key: 'calculatedNights', type: 'integer', required: false, default: 1 },
      { key: 'totalNightsCached', type: 'integer', required: false, default: 0 },
      { key: 'discount',         type: 'float',   required: false, default: 0 },
      { key: 'discountType',     type: 'string',  required: false, size: 20,  default: 'per_night' },
      { key: 'discountStartDate', type: 'string', required: false, size: 20 },
      { key: 'totalDueCached',   type: 'float',   required: false, default: 0.0 },
      { key: 'totalPaidCached',  type: 'float',   required: false, default: 0.0 },
      { key: 'remainingBalanceCached', type: 'float', required: false, default: 0.0 },
      { key: 'isFullyPaid',      type: 'boolean', required: false, default: false },
      { key: 'hotelDayCheckin',  type: 'string',  required: false, size: 20 },
      { key: 'hotelDayCheckout', type: 'string',  required: false, size: 20 },
      { key: 'stayDurationIso',  type: 'string',  required: false, size: 30 },
      { key: 'lastNightEpoch',   type: 'integer', required: false },
      { key: 'isOverdue',        type: 'boolean', required: false, default: false },
      { key: 'needsCheckoutReview', type: 'boolean', required: false, default: false },
      { key: 'idempotencyKey',   type: 'string',  required: false, size: 200 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_bookings_status', type: 'key', attributes: ['status'] },
      { key: 'idx_bookings_room',   type: 'key', attributes: ['roomNumber', 'status'] },
      { key: 'idx_bookings_guest',  type: 'key', attributes: ['guestName'] },
      { key: 'idx_bookings_guestPhone', type: 'key', attributes: ['guestPhone'] },
      { key: 'idx_bookings_checkinDate', type: 'key', attributes: ['checkinDate'] },
      { key: 'idx_bookings_serverBookingId', type: 'key', attributes: ['serverBookingId'] },
      { key: 'idx_bookings_hotelDay', type: 'key', attributes: ['hotelDayCheckin'] },
    ],
  },

  employees: {
    name: 'الموظفون',
    attrs: [
      ...SF,
      { key: 'name',             type: 'string',  required: true,  size: 200 },
      { key: 'basicSalary',      type: 'float',   required: true },
      { key: 'position',         type: 'string',  required: false, size: 100, default: 'موظف' },
      { key: 'phone',            type: 'string',  required: false, size: 30,  default: '' },
      { key: 'hireDate',         type: 'string',  required: false, size: 20 },
      { key: 'status',           type: 'string',  required: true,  size: 30 },
      { key: 'terminationDate',  type: 'string',  required: false, size: 50 },
      { key: 'terminationReason', type: 'string', required: false, size: 500 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_employees_status', type: 'key', attributes: ['status'] },
      { key: 'idx_employees_name',   type: 'key', attributes: ['name'] },
      { key: 'idx_employees_phone',  type: 'key', attributes: ['phone'] },
    ],
  },

  guest_infos: {
    name: 'معلومات النزلاء',
    attrs: [
      ...SF,
      { key: 'roomNumber',  type: 'string', required: true,  size: 20 },
      { key: 'guestName',   type: 'string', required: true,  size: 200 },
      { key: 'nationality', type: 'string', required: true,  size: 100 },
      { key: 'idNumber',    type: 'string', required: true,  size: 50 },
      { key: 'idType',      type: 'string', required: false, size: 50,  default: 'بطاقة شخصية' },
      { key: 'issueDate',   type: 'string', required: false, size: 20 },
      { key: 'issuePlace',  type: 'string', required: false, size: 100 },
      { key: 'governorate', type: 'string', required: false, size: 100 },
      { key: 'notes',       type: 'string', required: false, size: 5000 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_gi_room', type: 'key', attributes: ['roomNumber'] },
      { key: 'idx_gi_name', type: 'key', attributes: ['guestName'] },
    ],
  },

  // ═══ 3. FINANCIAL ═══════════════════════════════════════════════════════════
  payments: {
    name: 'المدفوعات',
    attrs: [
      ...SF,
      { key: 'amount',                 type: 'float',   required: true },
      { key: 'paymentDate',            type: 'string',  required: true,  size: 20 },
      { key: 'paymentMethod',          type: 'string',  required: true,  size: 30 },
      { key: 'revenueType',            type: 'string',  required: true,  size: 30 },
      { key: 'bookingLocalId',         type: 'integer', required: false },
      { key: 'serverBookingId',        type: 'integer', required: false },
      { key: 'serverPaymentId',        type: 'integer', required: false },
      { key: 'roomNumber',             type: 'string',  required: false, size: 20 },
      { key: 'notes',                  type: 'string',  required: false, size: 5000 },
      { key: 'hotelDayKey',            type: 'string',  required: false, size: 20 },
      { key: 'cashTransactionLocalId', type: 'integer', required: false },
      { key: 'referenceNumber',        type: 'string',  required: false, size: 100 },
      { key: 'linkedDebtUuid',         type: 'string',  required: false, size: 64 },
      { key: 'bookingUuidCache',       type: 'string',  required: false, size: 64 },
      { key: 'discountAmount',         type: 'float',   required: false },
      { key: 'discountStartDate',      type: 'string',  required: false, size: 20 },
      { key: 'isPendingBalance',       type: 'boolean', required: false, default: false },
      { key: 'isVoided',               type: 'boolean', required: false, default: false },
      { key: 'voidedAt',               type: 'integer', required: false },
      { key: 'voidedBy',               type: 'string',  required: false, size: 100 },
      { key: 'idempotencyKey',         type: 'string',  required: false, size: 200 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_pay_booking', type: 'key', attributes: ['bookingLocalId'] },
      { key: 'idx_pay_day',     type: 'key', attributes: ['hotelDayKey'] },
      { key: 'idx_pay_room',    type: 'key', attributes: ['roomNumber'] },
      { key: 'idx_pay_date',    type: 'key', attributes: ['paymentDate'] },
    ],
  },

  expenses: {
    name: 'المصروفات',
    attrs: [
      ...SF,
      { key: 'expenseType',    type: 'string',  required: true,  size: 100 },
      { key: 'description',    type: 'string',  required: true,  size: 5000 },
      { key: 'amount',         type: 'float',   required: true },
      { key: 'date',           type: 'string',  required: true,  size: 20 },
      { key: 'relatedId',      type: 'integer', required: false },
      { key: 'cashTransactionId', type: 'integer', required: false },
      { key: 'hotelDayKey',    type: 'string',  required: false, size: 20 },
      { key: 'categoryUuid',   type: 'string',  required: false, size: 64 },
      { key: 'cashFlowUuid',   type: 'string',  required: false, size: 64 },
      { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
    ],
    indexes: [
      ...SI,
      { key: 'idx_exp_day',  type: 'key', attributes: ['hotelDayKey'] },
      { key: 'idx_exp_type', type: 'key', attributes: ['expenseType'] },
      { key: 'idx_exp_category', type: 'key', attributes: ['categoryUuid'] },
    ],
  },

  debts: {
    name: 'الديون',
    attrs: [
      ...SF,
      { key: 'amount',             type: 'float',   required: true },
      { key: 'guestName',          type: 'string',  required: true,  size: 200 },
      { key: 'bookingLocalId',     type: 'integer', required: false },
      { key: 'checkinDate',        type: 'string',  required: true,  size: 20 },
      { key: 'checkoutDate',       type: 'string',  required: false, size: 20 },
      { key: 'dateRecorded',       type: 'string',  required: false, size: 20 },
      { key: 'debtReason',         type: 'string',  required: false, size: 500 },
      { key: 'totalAmount',        type: 'float',   required: false },
      { key: 'paidAmount',         type: 'float',   required: false },
      { key: 'remainingAmount',    type: 'float',   required: false },
      { key: 'paymentDate',        type: 'string',  required: true,  size: 20 },
      { key: 'isSettled',          type: 'integer', required: false, default: 0 },
      { key: 'pledge',             type: 'string',  required: false, size: 500 },
      { key: 'pledgeType',         type: 'string',  required: false, size: 50 },
      { key: 'note',               type: 'string',  required: false, size: 5000 },
      { key: 'debtUuid',           type: 'string',  required: false, size: 64 },
      { key: 'hotelDayOpened',     type: 'string',  required: false, size: 20 },
      { key: 'hotelDayClosed',     type: 'string',  required: false, size: 20 },
      { key: 'isFromAutoFix',      type: 'boolean', required: false, default: false },
      { key: 'settlementConfirmed', type: 'boolean', required: false, default: false },
      { key: 'idempotencyKey',     type: 'string',  required: false, size: 200 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_debts_status', type: 'key', attributes: ['status'] },
      { key: 'idx_debts_settled', type: 'key', attributes: ['isSettled'] },
      { key: 'idx_debts_guest',  type: 'key', attributes: ['guestName'] },
      { key: 'idx_debts_booking', type: 'key', attributes: ['bookingLocalId'] },
    ],
  },

  cash_transactions: {
    name: 'المعاملات النقدية',
    attrs: [
      ...SF,
      { key: 'transactionType', type: 'string',  required: true,  size: 30 },
      { key: 'amount',          type: 'float',   required: true },
      { key: 'transactionTime', type: 'string',  required: true,  size: 30 },
      { key: 'registerId',      type: 'integer', required: false },
      { key: 'referenceId',     type: 'integer', required: false },
      { key: 'referenceType',   type: 'string',  required: false, size: 30 },
      { key: 'description',     type: 'string',  required: false, size: 5000 },
      { key: 'createdBy',       type: 'integer', required: false },
    ],
    indexes: [
      ...SI,
      { key: 'idx_ct_type', type: 'key', attributes: ['transactionType'] },
      { key: 'idx_ct_time', type: 'key', attributes: ['transactionTime'] },
    ],
  },

  // ═══ 4. BOOKING SUB ════════════════════════════════════════════════════════
  booking_nights: {
    name: 'ليالي الحجز',
    attrs: [
      ...SF,
      { key: 'bookingLocalId',        type: 'integer', required: true },
      { key: 'hotelDayKey',           type: 'string',  required: true,  size: 20 },
      { key: 'nightStart',            type: 'string',  required: true,  size: 20 },
      { key: 'nightEnd',              type: 'string',  required: true,  size: 20 },
      { key: 'nightlyRate',           type: 'float',   required: false, default: 0.0 },
      { key: 'sequence',              type: 'integer', required: false, default: 0 },
      { key: 'baseRate',              type: 'float',   required: false, default: 0.0 },
      { key: 'adjustment',            type: 'float',   required: false, default: 0.0 },
      { key: 'finalRate',             type: 'float',   required: false, default: 0.0 },
      { key: 'appliedAdjustmentUuid', type: 'string',  required: false, size: 64 },
      { key: 'appliedAdjustmentsJson', type: 'string', required: false, size: 5000 },
      { key: 'isProcessedByAutoFix',  type: 'boolean', required: false, default: false },
    ],
    indexes: [
      ...SI,
      { key: 'idx_night_booking', type: 'unique', attributes: ['bookingLocalId', 'hotelDayKey'] },
      { key: 'idx_night_day',     type: 'key',    attributes: ['hotelDayKey'] },
    ],
  },

  booking_notes: {
    name: 'ملاحظات الحجز',
    attrs: [
      ...SF,
      { key: 'bookingId',  type: 'integer', required: true },
      { key: 'noteText',   type: 'string',  required: true,  size: 10000 },
      { key: 'alertType',  type: 'string',  required: true,  size: 30 },
      { key: 'alertUntil', type: 'string',  required: false, size: 30 },
      { key: 'isActive',   type: 'integer', required: false, default: 1 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_bn_booking', type: 'key', attributes: ['bookingId'] },
    ],
  },

  booking_price_adjustments: {
    name: 'تعديلات أسعار الحجز',
    attrs: [
      ...SF,
      { key: 'bookingLocalUuid',  type: 'string',  required: true,  size: 64 },
      { key: 'bookingLocalId',    type: 'integer', required: false },
      { key: 'roomNumber',        type: 'string',  required: false, size: 20 },
      { key: 'adjustmentType',    type: 'integer', required: false, default: 0 },
      { key: 'adjustmentMode',    type: 'string',  required: false, size: 20,  default: 'per_night' },
      { key: 'amount',            type: 'integer', required: false, default: 0 },
      { key: 'effectiveHotelDay', type: 'string',  required: false, size: 20 },
      { key: 'endHotelDay',       type: 'string',  required: false, size: 20 },
      { key: 'isActive',          type: 'boolean', required: false, default: true },
      { key: 'reason',            type: 'string',  required: false, size: 5000 },
      { key: 'appliedBy',         type: 'string',  required: false, size: 100 },
      { key: 'cancelledAt',       type: 'string',  required: false, size: 30 },
      { key: 'cancelledBy',       type: 'string',  required: false, size: 100 },
      { key: 'idempotencyKey',    type: 'string',  required: false, size: 200 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_bpa_booking', type: 'key', attributes: ['bookingLocalUuid'] },
      { key: 'idx_bpa_day',     type: 'key', attributes: ['effectiveHotelDay'] },
    ],
  },

  // ═══ 5. SALARIES ═══════════════════════════════════════════════════════════
  salary_cycles: {
    name: 'دورات الرواتب',
    attrs: [
      ...SF,
      { key: 'employeeId',      type: 'integer', required: true },
      { key: 'cycleKey',        type: 'string',  required: true,  size: 20 },
      { key: 'hotelDayStart',   type: 'string',  required: false, size: 20 },
      { key: 'hotelDayEnd',     type: 'string',  required: false, size: 20 },
      { key: 'expectedAmount',  type: 'float',   required: false, default: 0 },
      { key: 'actualPaid',      type: 'float',   required: false, default: 0 },
      { key: 'remainingAmount', type: 'float',   required: false, default: 0 },
      { key: 'status',          type: 'string',  required: false, size: 20,  default: 'draft' },
      { key: 'employeeUuid',    type: 'string',  required: false, size: 100 },
      { key: 'employeeLocalUuid', type: 'string', required: false, size: 100 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_sc_employee', type: 'unique', attributes: ['employeeId', 'cycleKey'] },
      { key: 'idx_sc_cycle',    type: 'key',    attributes: ['cycleKey'] },
    ],
  },

  salary_payments: {
    name: 'دفعات الرواتب',
    attrs: [
      ...SF,
      { key: 'cycleId',         type: 'integer', required: true },
      { key: 'amount',          type: 'float',   required: false, default: 0 },
      { key: 'paymentDateIso',  type: 'string',  required: true,  size: 20 },
      { key: 'hotelDayKey',     type: 'string',  required: false, size: 20 },
      { key: 'method',          type: 'string',  required: false, size: 30 },
      { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
    ],
    indexes: [
      ...SI,
      { key: 'idx_sp_cycle', type: 'key', attributes: ['cycleId'] },
    ],
  },

  salary_withdrawals: {
    name: 'مسحوبات الرواتب',
    attrs: [
      ...SF,
      { key: 'employeeId',     type: 'integer', required: true },
      { key: 'amount',         type: 'float',   required: true },
      { key: 'withdrawDate',   type: 'string',  required: true,  size: 20 },
      { key: 'reason',         type: 'string',  required: false, size: 5000 },
      { key: 'hotelDayKey',    type: 'string',  required: false, size: 20 },
      { key: 'withdrawalType', type: 'string',  required: false, size: 30 },
      { key: 'description',    type: 'string',  required: false, size: 5000 },
      { key: 'employeeUuid',   type: 'string',  required: false, size: 100 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_sw_employee', type: 'key', attributes: ['employeeId'] },
      { key: 'idx_sw_date',     type: 'key', attributes: ['withdrawDate'] },
    ],
  },

  // ═══ 6. PRICING ════════════════════════════════════════════════════════════
  price_adjustments: {
    name: 'تعديلات الأسعار',
    attrs: [
      ...SF,
      { key: 'targetType',     type: 'string',  required: true,  size: 30 },
      { key: 'targetUuid',     type: 'string',  required: true,  size: 64 },
      { key: 'adjustmentType', type: 'integer', required: true },
      { key: 'previousValue',  type: 'float',   required: true },
      { key: 'newValue',       type: 'float',   required: true },
      { key: 'reason',         type: 'string',  required: false, size: 5000 },
      { key: 'effectiveDate',  type: 'string',  required: true,  size: 20 },
      { key: 'appliedBy',      type: 'string',  required: true,  size: 100 },
      { key: 'hotelDayKey',    type: 'string',  required: true,  size: 20 },
      { key: 'isReversed',     type: 'boolean', required: false, default: false },
      { key: 'reversedAt',     type: 'string',  required: false, size: 30 },
      { key: 'reversedBy',     type: 'string',  required: false, size: 100 },
      { key: 'idempotencyKey', type: 'string',  required: false, size: 200 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_pa_target', type: 'key', attributes: ['targetType'] },
      { key: 'idx_pa_day',    type: 'key', attributes: ['hotelDayKey'] },
    ],
  },

  // ═══ 7. SHIFT NOTES + BLACKLIST ═══════════════════════════════════════════
  shift_notes: {
    name: 'ملاحظات النوبة',
    attrs: [
      ...SF,
      { key: 'title',     type: 'string',  required: true,  size: 200 },
      { key: 'content',   type: 'string',  required: true,  size: 10000 },
      { key: 'priority',  type: 'string',  required: false, size: 10,  default: 'medium' },
      { key: 'shiftType', type: 'string',  required: false, size: 10,  default: 'all' },
      { key: 'isRead',    type: 'boolean', required: false, default: false },
      { key: 'createdBy', type: 'string',  required: false, size: 30,  default: 'user' },
      { key: 'shiftDate', type: 'string',  required: false, size: 20 },
      { key: 'expiresAt', type: 'string',  required: false, size: 30 },
      { key: 'note',      type: 'string',  required: false, size: 10000 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_sn_priority', type: 'key', attributes: ['priority'] },
      { key: 'idx_sn_read',     type: 'key', attributes: ['isRead'] },
    ],
  },

  blacklist: {
    name: 'القائمة السوداء',
    attrs: [
      { key: 'localUuid',    type: 'string',  required: true,  size: 64 },
      { key: 'serverId',     type: 'integer', required: false },
      { key: 'createdAt',    type: 'integer', required: true },
      { key: 'updatedAt',    type: 'integer', required: true },
      { key: 'deletedAt',    type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: true },
      { key: 'createdAtIso', type: 'string',  required: false, size: 30 },
      { key: 'updatedAtIso', type: 'string',  required: false, size: 30 },
      { key: 'deletedAtIso', type: 'string',  required: false, size: 30 },
      { key: 'origin',       type: 'string',  required: false, size: 20,  default: 'mobile' },
      { key: 'syncTimestamp', type: 'integer', required: false },
      { key: 'name',         type: 'string',  required: true,  size: 200 },
      { key: 'nationality',  type: 'string',  required: false, size: 100 },
      { key: 'nationalId',   type: 'string',  required: false, size: 50 },
      { key: 'phone',        type: 'string',  required: false, size: 30 },
      { key: 'reason',       type: 'string',  required: false, size: 5000 },
      { key: 'notes',        type: 'string',  required: false, size: 5000 },
      { key: 'reportedBy',   type: 'string',  required: false, size: 50,  default: 'police' },
      { key: 'active',       type: 'boolean', required: false, default: true },
    ],
    indexes: [
      { key: 'idx_bl_name',     type: 'key', attributes: ['name'] },
      { key: 'idx_bl_modified', type: 'key', attributes: ['lastModified'] },
    ],
  },

  // ═══ 8. AUDIT ══════════════════════════════════════════════════════════════
  audit_logs: {
    name: 'سجل المراجعة',
    attrs: [
      { key: 'localUuid',     type: 'string',  required: true,  size: 64 },
      { key: 'operationType', type: 'string',  required: true,  size: 30 },
      { key: 'entityType',    type: 'string',  required: true,  size: 30 },
      { key: 'entityUuid',    type: 'string',  required: true,  size: 64 },
      { key: 'entityId',      type: 'integer', required: false },
      { key: 'previousState', type: 'string',  required: false, size: 50000 },
      { key: 'newState',      type: 'string',  required: false, size: 50000 },
      { key: 'changedFields', type: 'string',  required: false, size: 5000 },
      { key: 'performedBy',   type: 'string',  required: true,  size: 100 },
      { key: 'deviceId',      type: 'string',  required: true,  size: 64 },
      { key: 'ipAddress',     type: 'string',  required: false, size: 50 },
      { key: 'hotelDayKey',   type: 'string',  required: true,  size: 20 },
      { key: 'timestamp',     type: 'integer', required: true },
      { key: 'timestampIso',  type: 'string',  required: true,  size: 30 },
      { key: 'isFinancial',   type: 'boolean', required: false, default: false },
      { key: 'amountImpact',  type: 'float',   required: false },
      { key: 'createdAt',     type: 'integer', required: true },
      { key: 'idempotencyKey', type: 'string', required: false, size: 200 },
    ],
    indexes: [
      { key: 'idx_al_entity',    type: 'key', attributes: ['entityType', 'entityUuid'] },
      { key: 'idx_al_timestamp', type: 'key', attributes: ['timestamp'] },
      { key: 'idx_al_hotelDay',  type: 'key', attributes: ['hotelDayKey'] },
      { key: 'idx_al_financial', type: 'key', attributes: ['isFinancial', 'hotelDayKey'] },
    ],
  },

  payment_voids: {
    name: 'إلغاءات المدفوعات',
    attrs: [
      ...SF,
      { key: 'originalPaymentUuid',  type: 'string',  required: true,  size: 64 },
      { key: 'originalPaymentId',    type: 'integer', required: true },
      { key: 'bookingUuid',          type: 'string',  required: true,  size: 64 },
      { key: 'voidedAmount',         type: 'integer', required: true },
      { key: 'voidReason',           type: 'string',  required: true,  size: 5000 },
      { key: 'voidedBy',             type: 'string',  required: true,  size: 100 },
      { key: 'voidedAt',             type: 'integer', required: true },
      { key: 'voidedAtIso',          type: 'string',  required: true,  size: 30 },
      { key: 'hotelDayKey',          type: 'string',  required: true,  size: 20 },
      { key: 'reversalPaymentUuid',  type: 'string',  required: false, size: 64 },
      { key: 'approvedBy',           type: 'string',  required: false, size: 100 },
      { key: 'idempotencyKey',       type: 'string',  required: false, size: 200 },
    ],
    indexes: [
      ...SI,
      { key: 'idx_pv_booking', type: 'key', attributes: ['bookingUuid'] },
      { key: 'idx_pv_day',     type: 'key', attributes: ['hotelDayKey'] },
    ],
  },

  // ═══ 9. LOCAL (hotel_day_ledger — محلي فقط) ═══════════════════════════════
  hotel_day_ledger: {
    name: 'دفتر اليومية',
    attrs: [
      { key: 'localUuid',          type: 'string',  required: true,  size: 64 },
      { key: 'serverId',           type: 'integer', required: false },
      { key: 'createdAt',          type: 'integer', required: true },
      { key: 'updatedAt',          type: 'integer', required: true },
      { key: 'deletedAt',          type: 'integer', required: false },
      { key: 'lastModified',       type: 'integer', required: true },
      { key: 'hotelDayKey',        type: 'string',  required: true,  size: 20 },
      { key: 'totalIncome',        type: 'float',   required: false, default: 0 },
      { key: 'totalExpenses',      type: 'float',   required: false, default: 0 },
      { key: 'pendingBalances',    type: 'float',   required: false, default: 0 },
      { key: 'occupancyRate',      type: 'float',   required: false, default: 0 },
      { key: 'bookingsProcessed',  type: 'integer', required: false, default: 0 },
      { key: 'paymentsProcessed',  type: 'integer', required: false, default: 0 },
      { key: 'expensesProcessed',  type: 'integer', required: false, default: 0 },
      { key: 'status',             type: 'string',  required: false, size: 20, default: 'draft' },
    ],
    indexes: [
      { key: 'idx_ledger_day', type: 'unique', attributes: ['hotelDayKey'] },
    ],
  },
};

// ═══════════════════════════════════════════════════════════════════════════════
// دوال مساعدة
// ═══════════════════════════════════════════════════════════════════════════════

async function collectionExists(collId) {
  try { await db.getCollection(CFG.databaseId, collId); return true; }
  catch (e) { if (e.code === 404) return false; throw e; }
}

async function getExistingAttrs(collId) {
  try {
    const { attributes } = await db.listAttributes(CFG.databaseId, collId);
    return new Set(attributes.filter(a => a.key && !a.key.startsWith('$')).map(a => a.key));
  } catch { return new Set(); }
}

async function getExistingIndexes(collId) {
  try {
    const { indexes } = await db.listIndexes(CFG.databaseId, collId);
    return new Set(indexes.map(i => i.key));
  } catch { return new Set(); }
}

async function createOneAttr(collId, attr) {
  try {
    const opts = { required: attr.required || false, default: attr.default !== undefined ? attr.default : undefined };
    switch (attr.type) {
      case 'string':  await db.createStringAttribute(CFG.databaseId, collId, attr.key, attr.size || 65535, opts.required, opts.default); break;
      case 'integer': await db.createIntegerAttribute(CFG.databaseId, collId, attr.key, opts.required, undefined, undefined, opts.default); break;
      case 'float':   await db.createFloatAttribute(CFG.databaseId, collId, attr.key, opts.required, undefined, undefined, opts.default); break;
      case 'boolean': await db.createBooleanAttribute(CFG.databaseId, collId, attr.key, opts.required, opts.default); break;
    }
    return '✅';
  } catch (e) {
    if (e.code === 409) return '⏭️';
    if (e.code === 400 && e.message?.includes('already exists')) return '⏭️';
    throw e;
  }
}

async function createOneIndex(collId, idx) {
  try {
    await db.createIndex(CFG.databaseId, collId, idx.key, idx.type, idx.attributes, idx.orders || []);
    return '📇';
  } catch (e) {
    if (e.code === 409) return '⏭️';
    if (e.message?.includes('already exists')) return '⏭️';
    console.warn(`      ⚠️ Index ${idx.key}: ${e.message}`);
    return '⚠️';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// الوظيفة الرئيسية
// ═══════════════════════════════════════════════════════════════════════════════

async function main() {
  console.log('╔══════════════════════════════════════════════════════════════╗');
  console.log('║     Marina Hotel — Appwrite Schema (nassar.js)              ║');
  console.log('╠══════════════════════════════════════════════════════════════╣');
  console.log(`║  Project:  ${CFG.projectId}`);
  console.log(`║  Database: ${CFG.databaseId}`);
  console.log(`║  Endpoint: ${CFG.endpoint}`);
  console.log('╚══════════════════════════════════════════════════════════════╝');

  let stats_col = 0, stats_attr = 0, stats_idx = 0;
  const entries = Object.entries(COLLECTIONS);

  for (const [collId, schema] of entries) {
    console.log(`\n📦 ${schema.name} (${collId})`);

    // Collection
    const exists = await collectionExists(collId);
    if (exists) {
      console.log(`   🏗️  موجود مسبقاً`);
    } else {
      try {
        await db.createCollection(CFG.databaseId, collId, schema.name, PERMISSIONS);
        console.log(`   🏗️  تم الإنشاء`);
        await sleep(1500);
      } catch (e) {
        console.error(`   ❌ ${e.message}`);
        continue;
      }
    }
    stats_col++;

    // Attributes
    const existingAttrs = await getExistingAttrs(collId);
    let attrAdded = 0, attrSkipped = 0;
    for (const attr of schema.attrs) {
      if (existingAttrs.has(attr.key)) { attrSkipped++; continue; }
      try {
        const r = await createOneAttr(collId, attr);
        if (r === '✅') { attrAdded++; }
        else { attrSkipped++; }
        await sleep(250);
      } catch (e) {
        console.warn(`      ⚠️ ${attr.key}: ${e.message}`);
        attrSkipped++;
      }
    }
    stats_attr += attrAdded;
    if (attrAdded > 0) console.log(`   📝 +${attrAdded} حقول جديدة (${attrSkipped} موجودة)`);

    // Indexes
    if (schema.indexes && schema.indexes.length > 0) {
      const existingIdx = await getExistingIndexes(collId);
      let idxAdded = 0, idxSkipped = 0;
      for (const idx of schema.indexes) {
        if (existingIdx.has(idx.key)) { idxSkipped++; continue; }
        const r = await createOneIndex(collId, idx);
        if (r === '📇') idxAdded++;
        else idxSkipped++;
        await sleep(100);
      }
      stats_idx += idxAdded;
      if (idxAdded > 0) console.log(`   📇 +${idxAdded} فهارس جديدة (${idxSkipped} موجودة)`);
    }
  }

  // ─── الملخص ──────────────────────────────────────────────────────────────
  console.log('\n' + '═'.repeat(60));
  console.log('🏁  اكتمل!');
  console.log(`   📦 Collections: ${stats_col}`);
  console.log(`   📝 Attributes:  +${stats_attr}`);
  console.log(`   📇 Indexes:     +${stats_idx}`);
  console.log('═'.repeat(60) + '\n');
}

main().catch(e => { console.error('\n❌', e); process.exit(1); });
