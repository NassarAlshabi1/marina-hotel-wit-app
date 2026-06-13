/**
 * ============================================================================
 * Marina Hotel — Appwrite Collections Schema (كامل) — FIXED
 * ============================================================================
 * نسخة محدثة من Final_setup_all_collections.js مع:
 *   - دعم node-appwrite v20 (Permission API)
 *   - دعم env vars
 *   - معالجة "موجود مسبقاً"
 */

const { Client, Databases, Permission, Role } = require('node-appwrite');

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1';
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || 'hotel_db';
const API_KEY = process.env.APPWRITE_API_KEY;

if (!API_KEY) { console.error('❌ APPWRITE_API_KEY required'); process.exit(1); }

const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
const db = new Databases(client);
const delay = (ms) => new Promise(r => setTimeout(r, ms));

const perm = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

// ─── حقول مشتركة (SyncFields) ───
const syncFields = {
  attributes: [
    { key: 'localUuid',      type: 'string',  required: true,  size: 64 },
    { key: 'serverId',       type: 'integer', required: false },
    { key: 'createdAt',      type: 'integer', required: true  },
    { key: 'updatedAt',      type: 'integer', required: true  },
    { key: 'deletedAt',      type: 'integer', required: false },
    { key: 'lastModified',   type: 'integer', required: true  },
    { key: 'createdAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'updatedAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'deletedAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'version',        type: 'integer', required: false, default: 1 },
    { key: 'origin',         type: 'string',  required: false, default: 'local', size: 20 },
    { key: 'vectorClock',    type: 'string',  required: false, default: '{}', size: 2000 },
  ],
  indexes: [
    { key: 'idx_sf_modified', type: 'key', attributes: ['lastModified'] },
  ],
};

// ═══════════════════════════════════ COLLECTIONS ═══════════════════════════════
const collections = {
  devices: {
    name: 'الأجهزة',
    attrs: [
      { key: 'deviceId',   type: 'string', required: true,  size: 64 },
      { key: 'deviceName', type: 'string', required: false, size: 200 },
      { key: 'platform',   type: 'string', required: false, size: 30 },
      { key: 'appVersion', type: 'string', required: false, size: 20 },
      { key: 'fcmToken',   type: 'string', required: false, size: 500 },
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
};

// ─── دوال مساعدة ─────────────────────────────────────────────────────────────
async function ensureCollection(id, name, attrs, indexes) {
  console.log(`\n📦 ${name} (${id})`);
  try {
    await db.getCollection(DATABASE_ID, id);
    console.log(`   ⏭️  موجود مسبقاً`);
    return;
  } catch (e) {
    if (e.code !== 404) { console.error(`   ❌ ${e.message}`); return; }
  }

  try {
    await db.createCollection(DATABASE_ID, id, name, perm);
    console.log(`   ✅ Collection`);
    await delay(1000);

    for (const a of attrs) {
      try {
        switch (a.type) {
          case 'string':
            await db.createStringAttribute(DATABASE_ID, id, a.key, a.size || 65535, a.required || false, a.default);
            break;
          case 'integer':
            await db.createIntegerAttribute(DATABASE_ID, id, a.key, a.required || false, undefined, undefined, a.default);
            break;
          case 'float':
            await db.createFloatAttribute(DATABASE_ID, id, a.key, a.required || false, undefined, undefined, a.default);
            break;
          case 'boolean':
            await db.createBooleanAttribute(DATABASE_ID, id, a.key, a.required || false, a.default);
            break;
        }
        console.log(`      ✅ ${a.key}`);
      } catch (e2) {
        if (e2.code !== 409) console.warn(`      ⚠️  ${a.key}: ${e2.message}`);
      }
    }

    if (indexes) {
      await delay(2000);
      for (const idx of indexes) {
        try {
          await db.createIndex(DATABASE_ID, id, idx.key, idx.type, idx.attributes, idx.orders || []);
          console.log(`      📇 ${idx.key}`);
        } catch (e3) {
          if (e3.code !== 409) console.warn(`      ⚠️  Index ${idx.key}: ${e3.message}`);
        }
      }
    }
    console.log(`   ✅ ${name} اكتمل`);
  } catch (e) {
    console.error(`   ❌ فشل: ${e.message}`);
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Marina Hotel — إنشاء كل Collections (نسخة محدثة)');
  console.log(`  Database: ${DATABASE_ID}`);
  console.log('═══════════════════════════════════════════════════════════════');

  // 1. System collections
  await ensureCollection('devices', 'الأجهزة', collections.devices.attrs, collections.devices.indexes);
  await ensureCollection('sync_logs', 'سجل المزامنة', collections.sync_logs.attrs, collections.sync_logs.indexes);

  // 2. Core data
  await ensureCollection('rooms', 'الغرف', [
    ...syncFields.attributes,
    { key: 'roomNumber', type: 'string', required: true, size: 20 },
    { key: 'type',       type: 'string', required: true, size: 50 },
    { key: 'price',      type: 'float',  required: true },
    { key: 'status',     type: 'string', required: true, size: 30 },
    { key: 'imageUrl',   type: 'string', required: false, size: 2000 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_rooms_number', type: 'unique', attributes: ['roomNumber'] },
    { key: 'idx_rooms_status', type: 'key',    attributes: ['status'] },
  ]);

  await ensureCollection('bookings', 'الحجوزات', [
    ...syncFields.attributes,
    { key: 'roomNumber',     type: 'string',  required: true,  size: 20 },
    { key: 'guestName',      type: 'string',  required: true,  size: 200 },
    { key: 'guestPhone',     type: 'string',  required: true,  size: 30 },
    { key: 'guestIdType',    type: 'string',  required: false, size: 50,  default: 'بطاقة شخصية' },
    { key: 'guestIdNumber',  type: 'string',  required: false, size: 50,  default: '' },
    { key: 'guestNationality', type: 'string', required: true,  size: 100 },
    { key: 'guestEmail',     type: 'string',  required: false, size: 255 },
    { key: 'guestAddress',   type: 'string',  required: false, size: 300 },
    { key: 'checkinDate',    type: 'string',  required: true,  size: 20 },
    { key: 'checkoutDate',   type: 'string',  required: false, size: 20 },
    { key: 'status',         type: 'string',  required: true,  size: 30 },
    { key: 'notes',          type: 'string',  required: false, size: 5000 },
    { key: 'expectedNights',  type: 'integer', required: false, default: 1 },
    { key: 'calculatedNights', type: 'integer', required: false, default: 1 },
    { key: 'discount',       type: 'float',   required: false, default: 0 },
    { key: 'totalDueCached', type: 'float',   required: false, default: 0.0 },
    { key: 'totalPaidCached', type: 'float',  required: false, default: 0.0 },
    { key: 'remainingBalanceCached', type: 'float', required: false, default: 0.0 },
    { key: 'hotelDayCheckin',  type: 'string', required: false, size: 20 },
    { key: 'hotelDayCheckout', type: 'string', required: false, size: 20 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_bookings_status', type: 'key', attributes: ['status'] },
    { key: 'idx_bookings_room',   type: 'key', attributes: ['roomNumber'] },
    { key: 'idx_bookings_guest',  type: 'key', attributes: ['guestName'] },
  ]);

  await ensureCollection('employees', 'الموظفون', [
    ...syncFields.attributes,
    { key: 'name',        type: 'string', required: true,  size: 200 },
    { key: 'basicSalary', type: 'float',  required: true },
    { key: 'position',    type: 'string', required: false, size: 100, default: 'موظف' },
    { key: 'phone',       type: 'string', required: false, size: 30,  default: '' },
    { key: 'hireDate',    type: 'string', required: false, size: 20 },
    { key: 'status',      type: 'string', required: true,  size: 30 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_employees_status', type: 'key', attributes: ['status'] },
  ]);

  await ensureCollection('guest_infos', 'معلومات النزلاء', [
    ...syncFields.attributes,
    { key: 'roomNumber',  type: 'string', required: true,  size: 20 },
    { key: 'guestName',   type: 'string', required: true,  size: 200 },
    { key: 'nationality', type: 'string', required: true,  size: 100 },
    { key: 'idNumber',    type: 'string', required: true,  size: 50 },
    { key: 'idType',      type: 'string', required: false, size: 50,  default: 'بطاقة شخصية' },
    { key: 'notes',       type: 'string', required: false, size: 5000 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_gi_room', type: 'key', attributes: ['roomNumber'] },
    { key: 'idx_gi_name', type: 'key', attributes: ['guestName'] },
  ]);

  // 3. Financial
  await ensureCollection('payments', 'المدفوعات', [
    ...syncFields.attributes,
    { key: 'amount',        type: 'float',   required: true },
    { key: 'paymentDate',   type: 'string',  required: true,  size: 20 },
    { key: 'paymentMethod', type: 'string',  required: true,  size: 30 },
    { key: 'revenueType',   type: 'string',  required: true,  size: 30 },
    { key: 'bookingLocalId', type: 'integer', required: false },
    { key: 'roomNumber',    type: 'string',  required: false, size: 20 },
    { key: 'notes',         type: 'string',  required: false, size: 5000 },
    { key: 'hotelDayKey',   type: 'string',  required: false, size: 20 },
    { key: 'isVoided',      type: 'boolean', required: false, default: false },
    { key: 'voidedAt',      type: 'integer', required: false },
    { key: 'voidedBy',      type: 'string',  required: false, size: 100 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_pay_booking', type: 'key', attributes: ['bookingLocalId'] },
    { key: 'idx_pay_day',     type: 'key', attributes: ['hotelDayKey'] },
  ]);

  await ensureCollection('expenses', 'المصروفات', [
    ...syncFields.attributes,
    { key: 'expenseType',   type: 'string',  required: true,  size: 100 },
    { key: 'description',   type: 'string',  required: true,  size: 5000 },
    { key: 'amount',        type: 'float',   required: true },
    { key: 'date',          type: 'string',  required: true,  size: 20 },
    { key: 'hotelDayKey',   type: 'string',  required: false, size: 20 },
    { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
  ], [
    ...syncFields.indexes,
    { key: 'idx_exp_day',  type: 'key', attributes: ['hotelDayKey'] },
    { key: 'idx_exp_type', type: 'key', attributes: ['expenseType'] },
  ]);

  await ensureCollection('debts', 'الديون', [
    ...syncFields.attributes,
    { key: 'amount',     type: 'float',  required: true },
    { key: 'debtorName', type: 'string', required: true,  size: 200 },
    { key: 'dueDate',    type: 'string', required: true,  size: 20 },
    { key: 'status',     type: 'string', required: true,  size: 20 },
    { key: 'bookingLocalId', type: 'integer', required: false },
  ], [
    ...syncFields.indexes,
    { key: 'idx_debts_status', type: 'key', attributes: ['status'] },
  ]);

  await ensureCollection('cash_transactions', 'المعاملات النقدية', [
    ...syncFields.attributes,
    { key: 'transactionType', type: 'string',  required: true,  size: 30 },
    { key: 'amount',          type: 'float',   required: true },
    { key: 'transactionTime', type: 'string',  required: true,  size: 30 },
    { key: 'description',     type: 'string',  required: false, size: 5000 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_ct_type', type: 'key', attributes: ['transactionType'] },
  ]);

  // 4. Booking sub
  await ensureCollection('booking_notes', 'ملاحظات الحجز', [
    ...syncFields.attributes,
    { key: 'bookingId', type: 'integer', required: true },
    { key: 'noteText',  type: 'string',  required: true,  size: 10000 },
    { key: 'alertType', type: 'string',  required: true,  size: 30 },
    { key: 'isActive',  type: 'integer', required: false, default: 1 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_bn_booking', type: 'key', attributes: ['bookingId'] },
  ]);

  await ensureCollection('booking_nights', 'ليالي الحجز', [
    ...syncFields.attributes,
    { key: 'bookingLocalId',       type: 'integer', required: true },
    { key: 'hotelDayKey',          type: 'string',  required: true,  size: 20 },
    { key: 'nightStart',           type: 'string',  required: true,  size: 20 },
    { key: 'nightEnd',             type: 'string',  required: true,  size: 20 },
    { key: 'nightlyRate',          type: 'float',   required: false, default: 0.0 },
    { key: 'sequence',             type: 'integer', required: false, default: 0 },
    { key: 'baseRate',             type: 'float',   required: false, default: 0.0 },
    { key: 'adjustment',           type: 'float',   required: false, default: 0.0 },
    { key: 'finalRate',            type: 'float',   required: false, default: 0.0 },
    { key: 'appliedAdjustmentUuid', type: 'string', required: false, size: 64 },
    { key: 'isProcessedByAutoFix',  type: 'boolean', required: false, default: false },
  ], [
    ...syncFields.indexes,
    { key: 'idx_night_booking', type: 'key', attributes: ['bookingLocalId'] },
    { key: 'idx_night_day',     type: 'key', attributes: ['hotelDayKey'] },
  ]);

  await ensureCollection('booking_price_adjustments', 'تعديلات أسعار الحجز', [
    ...syncFields.attributes,
    { key: 'bookingLocalUuid',  type: 'string',  required: true,  size: 64 },
    { key: 'bookingLocalId',    type: 'integer', required: false },
    { key: 'adjustmentType',    type: 'integer', required: false, default: 0 },
    { key: 'amount',            type: 'float',   required: false, default: 0 },
    { key: 'effectiveHotelDay', type: 'string',  required: false, size: 20 },
    { key: 'endHotelDay',       type: 'string',  required: false, size: 20 },
    { key: 'isActive',          type: 'boolean', required: false, default: true },
    { key: 'reason',            type: 'string',  required: false, size: 5000 },
    { key: 'appliedBy',         type: 'string',  required: false, size: 100 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_bpa_booking', type: 'key', attributes: ['bookingLocalUuid'] },
    { key: 'idx_bpa_day',     type: 'key', attributes: ['effectiveHotelDay'] },
  ]);

  // 5. Salaries
  await ensureCollection('salary_cycles', 'دورات الرواتب', [
    ...syncFields.attributes,
    { key: 'employeeId',      type: 'integer', required: true },
    { key: 'cycleKey',        type: 'string',  required: true,  size: 20 },
    { key: 'expectedAmount',  type: 'float',   required: false, default: 0 },
    { key: 'actualPaid',      type: 'float',   required: false, default: 0 },
    { key: 'remainingAmount', type: 'float',   required: false, default: 0 },
    { key: 'status',          type: 'string',  required: false, size: 20, default: 'draft' },
  ], [
    ...syncFields.indexes,
    { key: 'idx_sc_employee', type: 'key', attributes: ['employeeId'] },
    { key: 'idx_sc_cycle',    type: 'key', attributes: ['cycleKey'] },
  ]);

  await ensureCollection('salary_payments', 'دفعات الرواتب', [
    ...syncFields.attributes,
    { key: 'cycleId',        type: 'integer', required: true },
    { key: 'amount',         type: 'float',   required: false, default: 0 },
    { key: 'paymentDateIso', type: 'string',  required: true,  size: 20 },
    { key: 'hotelDayKey',    type: 'string',  required: false, size: 20 },
    { key: 'method',         type: 'string',  required: false, size: 30 },
    { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
  ], [
    ...syncFields.indexes,
    { key: 'idx_sp_cycle', type: 'key', attributes: ['cycleId'] },
  ]);

  await ensureCollection('salary_withdrawals', 'مسحوبات الرواتب', [
    ...syncFields.attributes,
    { key: 'employeeId',   type: 'integer', required: true },
    { key: 'amount',       type: 'float',   required: true },
    { key: 'withdrawDate', type: 'string',  required: true,  size: 20 },
    { key: 'reason',       type: 'string',  required: false, size: 5000 },
    { key: 'hotelDayKey',  type: 'string',  required: false, size: 20 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_sw_employee', type: 'key', attributes: ['employeeId'] },
  ]);

  // 6. Pricing
  await ensureCollection('price_adjustments', 'تعديلات الأسعار', [
    ...syncFields.attributes,
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
  ], [
    ...syncFields.indexes,
    { key: 'idx_pa_target', type: 'key', attributes: ['targetType'] },
    { key: 'idx_pa_day',    type: 'key', attributes: ['hotelDayKey'] },
  ]);

  // 7. Shift notes + blacklist
  await ensureCollection('shift_notes', 'ملاحظات النوبة', [
    ...syncFields.attributes,
    { key: 'title',     type: 'string',  required: true,  size: 200 },
    { key: 'content',   type: 'string',  required: true,  size: 10000 },
    { key: 'priority',  type: 'string',  required: false, size: 10,  default: 'medium' },
    { key: 'shiftType', type: 'string',  required: false, size: 10,  default: 'all' },
    { key: 'isRead',    type: 'boolean', required: false, default: false },
    { key: 'createdBy', type: 'string',  required: false, size: 30,  default: 'user' },
  ], [
    ...syncFields.indexes,
    { key: 'idx_sn_priority', type: 'key', attributes: ['priority'] },
  ]);

  await ensureCollection('blacklist', 'القائمة السوداء', [
    { key: 'localUuid',    type: 'string',  required: true,  size: 64 },
    { key: 'serverId',     type: 'integer', required: false },
    { key: 'createdAt',    type: 'string',  required: true,  size: 30 },
    { key: 'createdAtIso', type: 'string',  required: false, size: 30 },
    { key: 'updatedAt',    type: 'string',  required: true,  size: 30 },
    { key: 'updatedAtIso', type: 'string',  required: false, size: 30 },
    { key: 'deletedAt',    type: 'string',  required: false, size: 30 },
    { key: 'lastModified', type: 'integer', required: true },
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
  ], [
    { key: 'idx_bl_name', type: 'key', attributes: ['name'] },
    { key: 'idx_bl_modified', type: 'key', attributes: ['lastModified'] },
  ]);

  // 8. Audit
  await ensureCollection('audit_logs', 'سجل المراجعة', [
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
  ], [
    { key: 'idx_al_entity',    type: 'key', attributes: ['entityType', 'entityUuid'] },
    { key: 'idx_al_timestamp', type: 'key', attributes: ['timestamp'] },
    { key: 'idx_al_financial', type: 'key', attributes: ['isFinancial', 'hotelDayKey'] },
  ]);

  await ensureCollection('payment_voids', 'إلغاءات المدفوعات', [
    ...syncFields.attributes,
    { key: 'originalPaymentUuid', type: 'string',  required: true,  size: 64 },
    { key: 'originalPaymentId',   type: 'integer', required: true },
    { key: 'bookingUuid',         type: 'string',  required: true,  size: 64 },
    { key: 'voidedAmount',        type: 'float',   required: true },
    { key: 'voidReason',          type: 'string',  required: true,  size: 5000 },
    { key: 'voidedBy',            type: 'string',  required: true,  size: 100 },
    { key: 'voidedAt',            type: 'integer', required: true },
    { key: 'voidedAtIso',         type: 'string',  required: true,  size: 30 },
    { key: 'hotelDayKey',         type: 'string',  required: true,  size: 20 },
    { key: 'reversalPaymentUuid', type: 'string',  required: false, size: 64 },
    { key: 'approvedBy',          type: 'string',  required: false, size: 100 },
  ], [
    ...syncFields.indexes,
    { key: 'idx_pv_booking', type: 'key', attributes: ['bookingUuid'] },
    { key: 'idx_pv_day',     type: 'key', attributes: ['hotelDayKey'] },
  ]);

  // 9. Settings
  await ensureCollection('app_settings', 'إعدادات التطبيق', [
    { key: 'key',   type: 'string', required: true,  size: 100 },
    { key: 'value', type: 'string', required: true,  size: 5000 },
    { key: 'deviceId', type: 'string', required: false, size: 64 },
    { key: 'createdAt', type: 'integer', required: true },
  ], [
    { key: 'idx_as_key', type: 'unique', attributes: ['key'] },
  ]);

  // 10. App users
  await ensureCollection('app_users', 'مستخدمو التطبيق', collections.app_users.attrs, collections.app_users.indexes);

  console.log('\n✅ تم الانتهاء من جميع المجموعات!');
}

main().catch(console.error);
