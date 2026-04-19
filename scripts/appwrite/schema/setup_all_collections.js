/**
 * ============================================================================
 * Marina Hotel — Appwrite Collections Schema (كامل)
 * ============================================================================
 *
 * هذا الاسكربت ينشئ كل collections و attributes و indexes
 * المطلوبة لمزامنة تطبيق Marina Hotel Mobile.
 *
 * ❌ لا تقم بتشغيله إذا كانت الـ collections موجودة مسبقاً
 * ✅ استخدمه فقط لإنشاء قاعدة بيانات جديدة من الصفر
 *
 * المجموع: 19 collection + 3 system collections (devices, sync_logs, app_settings)
 * ============================================================================
 *
 * أنواع Appwrite المدعومة:
 *   string, integer, float, boolean, datetime, email, url, enum, ip
 *   relationship (مستخدمة فقط داخل Appwrite Console)
 *
 * ============================================================================
 */

import { Client, Databases, ID } from 'node-appwrite';

// ─── إعدادات ─────────────────────────────────────────────────────────────────
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(process.env.APPWRITE_API_KEY || '');

const db = new Databases(client);

// ─── أدوات مساعدة ─────────────────────────────────────────────────────────────

/** إنشاء collection مع attributeString/integer/boolean/float/datefmt */
async function createCollection(collectionId, name, schema) {
  console.log(`\n📝 إنشاء: ${name} (${collectionId})`);

  try {
    // التحقق من وجود الـ collection
    try {
      await db.getCollection(DATABASE_ID, collectionId);
      console.log(`   ⚠️  موجود مسبقاً — تخطي: ${collectionId}`);
      return;
    } catch (e) {
      // غير موجود — نتابع الإنشاء
    }

    // إنشاء الـ collection
    await db.createCollection(DATABASE_ID, collectionId, name, [
      // قراءة: أي مستخدم مسجل (تتحكم Permission API لاحقاً)
      { read: 'role:all' },
      { write: 'role:all' },
    ]);

    console.log(`   ✅ Collection تم إنشاؤه`);

    // إنشاء الحقول
    for (const attr of schema.attributes) {
      await createAttribute(collectionId, attr);
    }

    // إنشاء الفهارس
    if (schema.indexes) {
      for (const idx of schema.indexes) {
        await createIndex(collectionId, idx);
      }
    }

    console.log(`   ✅ تم بنجاح: ${name}`);
  } catch (error) {
    console.error(`   ❌ فشل إنشاء ${collectionId}:`, error.message);
  }
}

async function createAttribute(collectionId, attr) {
  const { key, type, required, size, default: defaultVal, array, elements } = attr;

  // Appwrite: max 255 attributes per collection
  try {
    switch (type) {
      case 'string':
        await db.createStringAttribute(
          DATABASE_ID, collectionId, key,
          size || 65535,     // max size
          required || false,
          defaultVal || undefined,
          array || false,
        );
        break;

      case 'integer':
        await db.createIntegerAttribute(
          DATABASE_ID, collectionId, key,
          required || false,
          defaultVal !== undefined ? defaultVal : undefined,
          array || false,
        );
        break;

      case 'float':
        await db.createFloatAttribute(
          DATABASE_ID, collectionId, key,
          required || false,
          defaultVal !== undefined ? defaultVal : undefined,
          array || false,
        );
        break;

      case 'boolean':
        await db.createBooleanAttribute(
          DATABASE_ID, collectionId, key,
          required || false,
          defaultVal !== undefined ? defaultVal : undefined,
          array || false,
        );
        break;

      case 'datetime':
        await db.createDatetimeAttribute(
          DATABASE_ID, collectionId, key,
          required || false,
          defaultVal || undefined,
          array || false,
        );
        break;

      case 'email':
        await db.createEmailAttribute(
          DATABASE_ID, collectionId, key,
          required || false,
          defaultVal || undefined,
          array || false,
        );
        break;

      case 'url':
        await db.createUrlAttribute(
          DATABASE_ID, collectionId, key,
          required || false,
          defaultVal || undefined,
          array || false,
        );
        break;

      case 'enum':
        await db.createEnumAttribute(
          DATABASE_ID, collectionId, key,
          elements || [],
          required || false,
          defaultVal || undefined,
          array || false,
        );
        break;

      case 'ip':
        await db.createIpAttribute(
          DATABASE_ID, collectionId, key,
          required || false,
          defaultVal || undefined,
          array || false,
        );
        break;

      default:
        console.warn(`   ⚠️  نوع غير مدعوم: ${type} (${key})`);
    }
    console.log(`      ✅ ${key}: ${type}${required ? ' (required)' : ''}${defaultVal !== undefined ? ` (default: ${defaultVal})` : ''}`);
  } catch (error) {
    console.warn(`      ⚠️  ${key}: ${error.message}`);
  }
}

async function createIndex(collectionId, idx) {
  const { key, type, attributes, orders } = idx;
  try {
    await db.createIndex(
      DATABASE_ID, collectionId, key, type,
      attributes || [],
      orders || [],
    );
    console.log(`      📇 Index: ${key} (${type})`);
  } catch (error) {
    console.warn(`      ⚠️  Index ${key}: ${error.message}`);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// ║                           تعريف الـ Collections                           ║
// ═══════════════════════════════════════════════════════════════════════════════

// ─── حقول مشتركة (SyncFields mixin) ──────────────────────────────────────────
const syncFields = {
  attributes: [
    { key: 'localUuid',      type: 'string',  required: true,  size: 64 },
    { key: 'serverId',       type: 'integer', required: false },
    { key: 'createdAt',      type: 'integer', required: true  },  // epoch seconds
    { key: 'updatedAt',      type: 'integer', required: true  },  // epoch seconds
    { key: 'deletedAt',      type: 'integer', required: false },  // epoch seconds (soft delete)
    { key: 'lastModified',   type: 'integer', required: true  },  // epoch seconds (delta sync)
    { key: 'createdAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'updatedAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'deletedAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'version',        type: 'integer', required: false, default: 1 },
    { key: 'origin',         type: 'string',  required: false, default: 'local', size: 20 },
    { key: 'vectorClock',    type: 'string',  required: false, default: '{}', size: 2000 },
  ],
  indexes: [
    { key: 'idx_last_modified', type: 'key', attributes: ['lastModified'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 1. ROOMS — الغرف
// ═══════════════════════════════════════════════════════════════════════════════
const rooms = {
  attributes: [
    ...syncFields.attributes,
    // حقول الغرف
    { key: 'roomNumber', type: 'string', required: true, size: 20 },
    { key: 'type',       type: 'string', required: true, size: 50 },
    { key: 'price',      type: 'float',  required: true },
    { key: 'status',     type: 'string', required: true, size: 30 },  // available, occupied, maintenance, cleaning
    { key: 'imageUrl',   type: 'string', required: false, size: 2000 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_rooms_number', type: 'unique', attributes: ['roomNumber'] },
    { key: 'idx_rooms_status', type: 'key',     attributes: ['status'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 2. BOOKINGS — الحجوزات
// ═══════════════════════════════════════════════════════════════════════════════
const bookings = {
  attributes: [
    ...syncFields.attributes,
    // حقول الحجز
    { key: 'roomNumber',          type: 'string',  required: true,  size: 20 },
    { key: 'guestName',           type: 'string',  required: true,  size: 200 },
    { key: 'guestPhone',          type: 'string',  required: true,  size: 30 },
    { key: 'guestIdType',         type: 'string',  required: false, default: 'بطاقة شخصية', size: 50 },
    { key: 'guestIdNumber',       type: 'string',  required: false, default: '', size: 50 },
    { key: 'guestIdIssueDate',    type: 'string',  required: false, size: 20 },
    { key: 'guestIdIssuePlace',   type: 'string',  required: false, size: 100 },
    { key: 'guestNationality',    type: 'string',  required: true,  size: 100 },
    { key: 'guestEmail',          type: 'email',   required: false },
    { key: 'guestAddress',        type: 'string',  required: false, size: 300 },
    { key: 'checkinDate',         type: 'string',  required: true,  size: 20 },  // YYYY-MM-DD
    { key: 'checkoutDate',        type: 'string',  required: false, size: 20 },
    { key: 'actualCheckout',      type: 'string',  required: false, size: 20 },
    { key: 'status',              type: 'string',  required: true,  size: 30 },  // confirmed, checked_in, checked_out, cancelled
    { key: 'notes',               type: 'string',  required: false, size: 5000 },
    { key: 'expectedNights',      type: 'integer', required: false, default: 1 },
    { key: 'calculatedNights',    type: 'integer', required: false, default: 1 },
    { key: 'totalNightsCached',   type: 'integer', required: false, default: 0 },
    { key: 'discount',            type: 'float',   required: false, default: 0 },
    { key: 'discountType',        type: 'string',  required: false, default: 'per_night', size: 20 },
    { key: 'discountStartDate',   type: 'string',  required: false, size: 20 },
    { key: 'totalDueCached',      type: 'float',   required: false, default: 0.0 },
    { key: 'totalPaidCached',     type: 'float',   required: false, default: 0.0 },
    { key: 'remainingBalanceCached', type: 'float', required: false, default: 0.0 },
    { key: 'serverBookingId',     type: 'integer', required: false },
    { key: 'hotelDayCheckin',     type: 'string',  required: false, size: 20 },
    { key: 'hotelDayCheckout',    type: 'string',  required: false, size: 20 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_bookings_status', type: 'key', attributes: ['status'] },
    { key: 'idx_bookings_room',   type: 'key', attributes: ['roomNumber'] },
    { key: 'idx_bookings_guest',  type: 'key', attributes: ['guestName'] },
    { key: 'idx_bookings_day',    type: 'key', attributes: ['hotelDayCheckin'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 3. EMPLOYEES — الموظفون
// ═══════════════════════════════════════════════════════════════════════════════
const employees = {
  attributes: [
    ...syncFields.attributes,
    { key: 'name',        type: 'string', required: true,  size: 200 },
    { key: 'basicSalary', type: 'float',  required: true },
    { key: 'position',    type: 'string', required: false, default: 'موظف', size: 100 },
    { key: 'phone',       type: 'string', required: false, default: '', size: 30 },
    { key: 'hireDate',    type: 'string', required: false, default: '', size: 20 },
    { key: 'status',      type: 'string', required: true,  size: 30 },  // active, inactive
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_employees_status', type: 'key', attributes: ['status'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 4. EXPENSES — المصروفات
// ═══════════════════════════════════════════════════════════════════════════════
const expenses = {
  attributes: [
    ...syncFields.attributes,
    { key: 'expenseType',        type: 'string',  required: true,  size: 100 },
    { key: 'description',        type: 'string',  required: true,  size: 5000 },
    { key: 'amount',             type: 'float',   required: true },
    { key: 'date',               type: 'string',  required: true,  size: 20 },
    { key: 'relatedId',          type: 'integer', required: false },
    { key: 'cashTransactionId',  type: 'integer', required: false },
    { key: 'hotelDayKey',        type: 'string',  required: false, size: 20 },
    { key: 'categoryUuid',       type: 'string',  required: false, size: 64 },
    { key: 'cashFlowUuid',       type: 'string',  required: false, size: 64 },
    { key: 'isAutoGenerated',    type: 'boolean', required: false, default: false },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_expenses_day',   type: 'key', attributes: ['hotelDayKey'] },
    { key: 'idx_expenses_type',  type: 'key', attributes: ['expenseType'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 5. PAYMENTS — المدفوعات
// ═══════════════════════════════════════════════════════════════════════════════
const payments = {
  attributes: [
    ...syncFields.attributes,
    { key: 'amount',                  type: 'float',   required: true },
    { key: 'paymentDate',             type: 'string',  required: true,  size: 20 },
    { key: 'paymentMethod',           type: 'string',  required: true,  size: 30 },  // cash, card, transfer, ...
    { key: 'revenueType',             type: 'string',  required: true,  size: 30 },
    { key: 'bookingLocalId',          type: 'integer', required: false },
    { key: 'serverBookingId',         type: 'integer', required: false },
    { key: 'serverPaymentId',         type: 'integer', required: false },
    { key: 'roomNumber',              type: 'string',  required: false, size: 20 },
    { key: 'notes',                   type: 'string',  required: false, size: 5000 },
    { key: 'hotelDayKey',             type: 'string',  required: false, size: 20 },
    { key: 'cashTransactionLocalId',  type: 'integer', required: false },
    { key: 'cashTransactionServerId', type: 'integer', required: false },
    { key: 'referenceNumber',         type: 'string',  required: false, size: 100 },
    { key: 'linkedDebtUuid',          type: 'string',  required: false, size: 64 },
    { key: 'bookingUuidCache',        type: 'string',  required: false, size: 64 },
    { key: 'discountAmount',          type: 'float',   required: false },
    { key: 'discountStartDate',       type: 'string',  required: false, size: 20 },
    { key: 'isPendingBalance',        type: 'boolean', required: false, default: false },
    { key: 'isVoided',                type: 'boolean', required: false, default: false },
    { key: 'voidedAt',                type: 'integer', required: false },
    { key: 'voidedBy',                type: 'string',  required: false, size: 100 },
    { key: 'sync_version',            type: 'integer', required: false, default: 1 },
    { key: 'sync_vector_clock',       type: 'string',  required: false, default: '{}', size: 2000 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_payments_booking', type: 'key', attributes: ['bookingLocalId'] },
    { key: 'idx_payments_day',     type: 'key', attributes: ['hotelDayKey'] },
    { key: 'idx_payments_room',    type: 'key', attributes: ['roomNumber'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 6. DEBTS — الديون
// ═══════════════════════════════════════════════════════════════════════════════
const debts = {
  attributes: [
    ...syncFields.attributes,
    { key: 'amount',              type: 'integer', required: true },  // مخزّن كـ integer (جنيهات)
    { key: 'debtorName',          type: 'string',  required: true,  size: 200 },
    { key: 'dueDate',             type: 'string',  required: true,  size: 20 },
    { key: 'status',              type: 'string',  required: true,  size: 20 },  // pending, settled
    { key: 'bookingLocalId',      type: 'integer', required: false },
    { key: 'sync_version',        type: 'integer', required: false, default: 1 },
    { key: 'sync_vector_clock',   type: 'string',  required: false, default: '{}', size: 2000 },
    { key: 'sync_origin',         type: 'string',  required: false, default: 'local', size: 20 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_debts_status', type: 'key', attributes: ['status'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 7. GUEST_INFOS — معلومات النزلاء
// ═══════════════════════════════════════════════════════════════════════════════
const guest_infos = {
  attributes: [
    ...syncFields.attributes,
    { key: 'roomNumber',    type: 'string', required: true,  size: 20 },
    { key: 'guestName',     type: 'string', required: true,  size: 200 },
    { key: 'nationality',   type: 'string', required: true,  size: 100 },
    { key: 'idNumber',      type: 'string', required: true,  size: 50 },
    { key: 'idType',        type: 'string', required: false, default: 'بطاقة شخصية', size: 50 },
    { key: 'issueDate',     type: 'string', required: false, size: 20 },
    { key: 'issuePlace',    type: 'string', required: false, size: 100 },
    { key: 'governorate',   type: 'string', required: false, size: 100 },
    { key: 'notes',         type: 'string', required: false, size: 5000 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_guest_room', type: 'key', attributes: ['roomNumber'] },
    { key: 'idx_guest_name', type: 'key', attributes: ['guestName'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 8. SALARY_WITHDRAWALS — مسحوبات الرواتب
// ═══════════════════════════════════════════════════════════════════════════════
const salary_withdrawals = {
  attributes: [
    ...syncFields.attributes,
    { key: 'employeeId',     type: 'integer', required: true },
    { key: 'amount',         type: 'integer', required: true },  // Appwrite: integer (جنيهات)
    { key: 'withdrawDate',   type: 'string',  required: true,  size: 20 },
    { key: 'reason',         type: 'string',  required: false, size: 5000 },
    { key: 'hotelDayKey',    type: 'string',  required: false, size: 20 },
    { key: 'withdrawalType', type: 'string',  required: false, size: 30 },
    { key: 'description',    type: 'string',  required: false, size: 5000 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_salary_w_employee', type: 'key', attributes: ['employeeId'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 9. BOOKING_PRICE_ADJUSTMENTS — تعديلات أسعار الحجوزات
// ═══════════════════════════════════════════════════════════════════════════════
const booking_price_adjustments = {
  attributes: [
    ...syncFields.attributes,
    { key: 'bookingLocalUuid', type: 'string',  required: true,  size: 64 },
    { key: 'bookingLocalId',  type: 'integer', required: false },
    { key: 'adjustmentType',  type: 'integer', required: false, default: 0 },
    { key: 'adjustmentMode',  type: 'string',  required: false, default: 'per_night', size: 20 },
    { key: 'amount',          type: 'integer', required: false, default: 0 },  // Appwrite: integer
    { key: 'effectiveHotelDay', type: 'string', required: false, size: 20 },
    { key: 'endHotelDay',     type: 'string',  required: false, size: 20 },
    { key: 'isActive',        type: 'boolean', required: false, default: true },
    { key: 'reason',          type: 'string',  required: false, size: 5000 },
    { key: 'appliedBy',       type: 'string',  required: false, size: 100 },
    { key: 'cancelledAt',     type: 'string',  required: false, size: 30 },
    { key: 'cancelledBy',     type: 'string',  required: false, size: 100 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_bpa_booking', type: 'key', attributes: ['bookingLocalUuid'] },
    { key: 'idx_bpa_dates',   type: 'key', attributes: ['effectiveHotelDay'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 10. BOOKING_NIGHTS — ليالي الحجز
// ═══════════════════════════════════════════════════════════════════════════════
const booking_nights = {
  attributes: [
    ...syncFields.attributes,
    { key: 'bookingLocalId',       type: 'integer', required: true },
    { key: 'hotelDayKey',          type: 'string',  required: true,  size: 20 },
    { key: 'nightStart',           type: 'string',  required: true,  size: 20 },
    { key: 'nightEnd',             type: 'string',  required: true,  size: 20 },
    { key: 'nightlyRate',          type: 'float',   required: false, default: 0.0 },
    { key: 'sequence',             type: 'integer', required: false, default: 0 },
    { key: 'isProcessedByAutoFix', type: 'boolean', required: false, default: false },
    { key: 'baseRate',             type: 'float',   required: false, default: 0.0 },
    { key: 'adjustment',           type: 'float',   required: false, default: 0.0 },
    { key: 'finalRate',            type: 'float',   required: false, default: 0.0 },
    { key: 'appliedAdjustmentUuid', type: 'string', required: false, size: 64 },
    { key: 'appliedAdjustmentsJson', type: 'string', required: false, size: 10000 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_bn_booking', type: 'key', attributes: ['bookingLocalId'] },
    { key: 'idx_bn_day',    type: 'key', attributes: ['hotelDayKey'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 11. BOOKING_NOTES — ملاحظات الحجز
// ═══════════════════════════════════════════════════════════════════════════════
const booking_notes = {
  attributes: [
    ...syncFields.attributes,
    { key: 'bookingId',  type: 'integer', required: true },
    { key: 'noteText',   type: 'string',  required: true,  size: 10000 },
    { key: 'alertType',  type: 'string',  required: true,  size: 30 },
    { key: 'alertUntil', type: 'string',  required: false, size: 30 },
    { key: 'isActive',   type: 'integer', required: false, default: 1 },  // 0 or 1
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_bnotes_booking', type: 'key', attributes: ['bookingId'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 12. CASH_TRANSACTIONS — المعاملات النقدية
// ═══════════════════════════════════════════════════════════════════════════════
const cash_transactions = {
  attributes: [
    ...syncFields.attributes,
    { key: 'transactionType', type: 'string',  required: true,  size: 30 },  // income, expense, ...
    { key: 'amount',          type: 'integer', required: true },  // Appwrite: integer (جنيهات)
    { key: 'transactionTime', type: 'string',  required: true,  size: 30 },
    { key: 'registerId',      type: 'integer', required: false },
    { key: 'referenceId',     type: 'integer', required: false },
    { key: 'referenceType',   type: 'string',  required: false, size: 30 },
    { key: 'description',     type: 'string',  required: false, size: 5000 },
    { key: 'createdBy',       type: 'integer', required: false },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_ct_type', type: 'key', attributes: ['transactionType'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 13. SHIFT_NOTES — ملاحظات النوبة
// ═══════════════════════════════════════════════════════════════════════════════
const shift_notes = {
  attributes: [
    ...syncFields.attributes,
    { key: 'title',     type: 'string',  required: true,  size: 200 },
    { key: 'content',   type: 'string',  required: true,  size: 10000 },
    { key: 'priority',  type: 'string',  required: false, default: 'medium', size: 10 },  // high, medium, low
    { key: 'shiftType', type: 'string',  required: false, default: 'all',    size: 10 },  // morning, evening, night, all
    { key: 'isRead',    type: 'boolean', required: false, default: false },
    { key: 'createdBy', type: 'string',  required: false, default: 'user',   size: 30 },
    { key: 'shiftDate', type: 'string',  required: false, size: 10 },  // YYYY-MM-DD مشتق من createdAt
    { key: 'note',      type: 'string',  required: false, size: 10000 },  // mirrors content
    { key: 'expiresAt', type: 'string',  required: false, size: 30 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_sn_priority', type: 'key', attributes: ['priority'] },
    { key: 'idx_sn_created',  type: 'key', attributes: ['createdBy'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 14. BLACKLIST — القائمة السوداء (منفصلة عن shift_notes)
// ═══════════════════════════════════════════════════════════════════════════════
const blacklist = {
  attributes: [
    // SyncFields لكن createdAt/updatedAt هما ISO string هنا
    { key: 'localUuid',       type: 'string',  required: true,  size: 64 },
    { key: 'serverId',        type: 'integer', required: false },
    { key: 'createdAt',       type: 'string',  required: true,  size: 30 },  // ISO 8601
    { key: 'createdAtIso',    type: 'string',  required: false, size: 30 },
    { key: 'updatedAt',       type: 'string',  required: true,  size: 30 },  // ISO 8601
    { key: 'updatedAtIso',    type: 'string',  required: false, size: 30 },
    { key: 'deletedAt',       type: 'string',  required: false, size: 30 },  // ISO 8601 أو null
    { key: 'lastModified',    type: 'integer', required: true },  // epoch seconds
    { key: 'origin',          type: 'string',  required: false, default: 'mobile', size: 20 },
    { key: 'syncTimestamp',   type: 'integer', required: false },
    // حقول القائمة السوداء
    { key: 'name',            type: 'string',  required: true,  size: 200 },
    { key: 'nationality',     type: 'string',  required: false, size: 100 },
    { key: 'nationalId',      type: 'string',  required: false, size: 50 },
    { key: 'phone',           type: 'string',  required: false, size: 30 },
    { key: 'reason',          type: 'string',  required: false, size: 5000 },
    { key: 'notes',           type: 'string',  required: false, size: 5000 },
    { key: 'reportedBy',      type: 'string',  required: false, default: 'police', size: 50 },
    { key: 'active',          type: 'boolean', required: false, default: true },
  ],
  indexes: [
    { key: 'idx_bl_name',     type: 'key', attributes: ['name'] },
    { key: 'idx_bl_modified', type: 'key', attributes: ['lastModified'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 15. SALARY_CYCLES — دورات الرواتب
// ═══════════════════════════════════════════════════════════════════════════════
const salary_cycles = {
  attributes: [
    ...syncFields.attributes,
    { key: 'employeeId',     type: 'integer', required: true },
    { key: 'cycleKey',       type: 'string',  required: true,  size: 20 },  // YYYY-MM
    { key: 'hotelDayStart',  type: 'string',  required: false, size: 20 },
    { key: 'hotelDayEnd',    type: 'string',  required: false, size: 20 },
    { key: 'expectedAmount', type: 'integer', required: false, default: 0 },
    { key: 'actualPaid',     type: 'integer', required: false, default: 0 },
    { key: 'remainingAmount', type: 'integer', required: false, default: 0 },
    { key: 'status',         type: 'string',  required: false, default: 'draft', size: 20 },  // draft, active, closed
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_sc_employee', type: 'key', attributes: ['employeeId'] },
    { key: 'idx_sc_cycle',    type: 'key', attributes: ['cycleKey'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 16. SALARY_PAYMENTS — دفعات الرواتب
// ═══════════════════════════════════════════════════════════════════════════════
const salary_payments = {
  attributes: [
    ...syncFields.attributes,
    { key: 'cycleId',        type: 'integer', required: true },
    { key: 'amount',         type: 'integer', required: false, default: 0 },
    { key: 'paymentDateIso', type: 'string',  required: true,  size: 20 },
    { key: 'hotelDayKey',    type: 'string',  required: false, size: 20 },
    { key: 'method',         type: 'string',  required: false, size: 30 },
    { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_sp_cycle', type: 'key', attributes: ['cycleId'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 17. PRICE_ADJUSTMENTS — تعديلات الأسعار العامة
// ═══════════════════════════════════════════════════════════════════════════════
const price_adjustments = {
  attributes: [
    ...syncFields.attributes,
    { key: 'targetType',   type: 'string',  required: true,  size: 30 },  // room, ...
    { key: 'targetUuid',   type: 'string',  required: true,  size: 64 },
    { key: 'adjustmentType', type: 'integer', required: true },
    { key: 'previousValue', type: 'integer', required: true },
    { key: 'newValue',     type: 'integer', required: true },
    { key: 'reason',       type: 'string',  required: false, size: 5000 },
    { key: 'effectiveDate', type: 'string', required: true,  size: 20 },
    { key: 'appliedBy',    type: 'string',  required: true,  size: 100 },
    { key: 'hotelDayKey',  type: 'string',  required: true,  size: 20 },
    { key: 'isReversed',   type: 'boolean', required: false, default: false },
    { key: 'reversedAt',   type: 'string',  required: false, size: 30 },
    { key: 'reversedBy',   type: 'string',  required: false, size: 100 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_pa_target', type: 'key', attributes: ['targetType'] },
    { key: 'idx_pa_day',    type: 'key', attributes: ['hotelDayKey'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 18. AUDIT_LOGS — سجل المراجعة (بدون SyncFields كاملة)
// ═══════════════════════════════════════════════════════════════════════════════
const audit_logs = {
  attributes: [
    { key: 'localUuid',     type: 'string',  required: true,  size: 64 },
    { key: 'operationType', type: 'string',  required: true,  size: 30 },  // create, update, delete
    { key: 'entityType',   type: 'string',  required: true,  size: 30 },  // booking, payment, ...
    { key: 'entityUuid',   type: 'string',  required: true,  size: 64 },
    { key: 'entityId',     type: 'integer', required: false },
    { key: 'previousState', type: 'string',  required: false, size: 50000 },
    { key: 'newState',     type: 'string',  required: false, size: 50000 },
    { key: 'changedFields', type: 'string',  required: false, size: 5000 },
    { key: 'performedBy',  type: 'string',  required: true,  size: 100 },
    { key: 'deviceId',     type: 'string',  required: true,  size: 64 },
    { key: 'ipAddress',    type: 'ip',      required: false },
    { key: 'hotelDayKey',  type: 'string',  required: true,  size: 20 },
    { key: 'timestamp',    type: 'integer', required: true },  // epoch seconds
    { key: 'timestampIso', type: 'string',  required: true,  size: 30 },
    { key: 'isFinancial',  type: 'boolean', required: false, default: false },
    { key: 'amountImpact', type: 'integer', required: false },
    { key: 'createdAt',    type: 'integer', required: true },  // epoch seconds
  ],
  indexes: [
    { key: 'idx_al_entity',     type: 'key', attributes: ['entityType', 'entityUuid'] },
    { key: 'idx_al_timestamp',  type: 'key', attributes: ['timestamp'] },
    { key: 'idx_al_financial',  type: 'key', attributes: ['isFinancial', 'hotelDayKey'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// 19. PAYMENT_VOIDS — إلغاءات المدفوعات
// ═══════════════════════════════════════════════════════════════════════════════
const payment_voids = {
  attributes: [
    ...syncFields.attributes,
    { key: 'originalPaymentUuid',  type: 'string',  required: true,  size: 64 },
    { key: 'originalPaymentId',    type: 'integer', required: true },
    { key: 'bookingUuid',          type: 'string',  required: true,  size: 64 },
    { key: 'voidedAmount',         type: 'integer', required: true },
    { key: 'voidReason',           type: 'string',  required: true,  size: 5000 },
    { key: 'voidedBy',             type: 'string',  required: true,  size: 100 },
    { key: 'voidedAt',             type: 'integer', required: true },  // epoch seconds
    { key: 'voidedAtIso',          type: 'string',  required: true,  size: 30 },
    { key: 'hotelDayKey',          type: 'string',  required: true,  size: 20 },
    { key: 'reversalPaymentUuid',  type: 'string',  required: false, size: 64 },
    { key: 'approvedBy',           type: 'string',  required: false, size: 100 },
  ],
  indexes: [
    ...syncFields.indexes,
    { key: 'idx_pv_booking', type: 'key', attributes: ['bookingUuid'] },
    { key: 'idx_pv_day',     type: 'key', attributes: ['hotelDayKey'] },
  ],
};


// ═══════════════════════════════════════════════════════════════════════════════
// SYSTEM COLLECTIONS — مجموعة النظام (لا تُزامن مع Drift)
// ═══════════════════════════════════════════════════════════════════════════════

// 20. DEVICES — الأجهزة المسجلة
const devices = {
  attributes: [
    { key: 'deviceId',    type: 'string', required: true,  size: 64 },
    { key: 'deviceName',  type: 'string', required: false, size: 200 },
    { key: 'platform',    type: 'string', required: false, size: 30 },  // android, ios
    { key: 'appVersion',  type: 'string', required: false, size: 20 },
    { key: 'fcmToken',    type: 'string', required: false, size: 500 },
    { key: 'lastSeen',    type: 'integer', required: false },  // epoch seconds
    { key: 'isActive',    type: 'boolean', required: false, default: true },
  ],
  indexes: [
    { key: 'idx_devices_id', type: 'unique', attributes: ['deviceId'] },
  ],
};

// 21. SYNC_LOGS — سجل المزامنة
const sync_logs = {
  attributes: [
    { key: 'deviceId',   type: 'string',  required: true,  size: 64 },
    { key: 'syncType',   type: 'string',  required: true,  size: 20 },  // push, pull
    { key: 'status',     type: 'string',  required: true,  size: 20 },  // success, partial, failed
    { key: 'records',    type: 'integer', required: false },
    { key: 'durationMs', type: 'integer', required: false },
    { key: 'error',      type: 'string',  required: false, size: 10000 },
    { key: 'timestamp',  type: 'integer', required: true },  // epoch seconds
  ],
  indexes: [
    { key: 'idx_sync_device', type: 'key', attributes: ['deviceId'] },
    { key: 'idx_sync_time',   type: 'key', attributes: ['timestamp'] },
  ],
};


// 22. APP_SETTINGS — إعدادات التطبيق (واتساب وغيرها — مزامنة بين الأجهزة)
const app_settings = {
  attributes: [
    // ── WhatsApp ──
    { key: 'wa_api_type',          type: 'string', required: false, size: 50,   default: 'greenapi' },
    { key: 'wa_api_base_url',      type: 'string', required: false, size: 500,  default: '' },
    { key: 'wa_api_instance_id',   type: 'string', required: false, size: 200,  default: '' },
    { key: 'wa_api_token',         type: 'string', required: false, size: 500,  default: '' },
    { key: 'wa_custom_url_template', type: 'string', required: false, size: 1000, default: '' },
    { key: 'wa_sendzen_api_key',   type: 'string', required: false, size: 500,  default: '' },
    { key: 'wa_sendzen_from_number', type: 'string', required: false, size: 30,  default: '' },
    { key: 'wa_template',          type: 'string', required: false, size: 5000, default: '' },
    // ── Telegram ──
    { key: 'telegram_enabled',             type: 'boolean', required: false, default: false },
    { key: 'telegram_bot_token',           type: 'string',  required: false, size: 500,  default: '' },
    { key: 'telegram_chat_id',             type: 'string',  required: false, size: 100,  default: '' },
    { key: 'telegram_notifications_enabled', type: 'boolean', required: false, default: true },
    { key: 'telegram_daily_report_enabled',  type: 'boolean', required: false, default: false },
    { key: 'telegram_daily_report_time',    type: 'string',  required: false, size: 10,   default: '08:00' },
  ],
};


// 23. APP_USERS — مستخدمو التطبيق (مزامنة بين الأجهزة)
const app_users = {
  attributes: [
    { key: 'username',   type: 'string',  required: false, size: 100,  default: '' },
    { key: 'password',   type: 'string',  required: false, size: 500,  default: '' },
    { key: 'full_name',  type: 'string',  required: false, size: 200,  default: '' },
    { key: 'user_type',  type: 'string',  required: false, size: 50,   default: 'employee' },
    { key: 'permissions', type: 'string', required: false, size: 2000, default: '[]' },
    { key: 'active',     type: 'boolean', required: false, default: true },
    { key: 'last_login', type: 'integer', required: false, default: 0 },
  ],
};


// ─── التشغيل الرئيسي ─────────────────────────────────────────────────────────

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  Marina Hotel — إنشاء كل Collections في Appwrite');
  console.log('  Database: ' + DATABASE_ID);
  console.log('═══════════════════════════════════════════════════════════════');

  // إنشاء الـ collections بالترتيب
  const collections = [
    // نظام
    ['devices',    'الأجهزة',                   devices],
    ['sync_logs',  'سجل المزامنة',              sync_logs],

    // بيانات أساسية
    ['rooms',                  'الغرف',                    rooms],
    ['employees',              'الموظفون',                 employees],
    ['bookings',               'الحجوزات',                  bookings],
    ['guest_infos',            'معلومات النزلاء',          guest_infos],

    // مالية
    ['payments',               'المدفوعات',                payments],
    ['expenses',               'المصروفات',                expenses],
    ['debts',                  'الديون',                   debts],
    ['cash_transactions',      'المعاملات النقدية',        cash_transactions],

    // حجوزات فرعية
    ['booking_notes',          'ملاحظات الحجز',            booking_notes],
    ['booking_nights',         'ليالي الحجز',              booking_nights],
    ['booking_price_adjustments', 'تعديلات أسعار الحجز',    booking_price_adjustments],

    // رواتب
    ['salary_cycles',          'دورات الرواتب',            salary_cycles],
    ['salary_payments',        'دفعات الرواتب',            salary_payments],
    ['salary_withdrawals',     'مسحوبات الرواتب',          salary_withdrawals],

    // أسعار
    ['price_adjustments',      'تعديلات الأسعار',          price_adjustments],

    // ملاحظات
    ['shift_notes',            'ملاحظات النوبة',           shift_notes],
    ['blacklist',              'القائمة السوداء',          blacklist],

    // مراجعة
    ['audit_logs',             'سجل المراجعة',             audit_logs],
    ['payment_voids',          'إلغاءات المدفوعات',        payment_voids],

    // إعدادات
    ['app_settings',           'إعدادات التطبيق',          app_settings],

    // مستخدمين
    ['app_users',              'مستخدمو التطبيق',          app_users],
  ];

  let success = 0;
  let skipped = 0;
  let failed = 0;

  for (const [collectionId, name, schema] of collections) {
    try {
      // تحقق من وجود الـ collection
      await db.getCollection(DATABASE_ID, collectionId);
      console.log(`⏭️  تخطي (موجود): ${name} (${collectionId})`);
      skipped++;
    } catch (e) {
      try {
        await createCollection(collectionId, name, schema);
        success++;
      } catch (err) {
        failed++;
      }
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log(`  ✅ تم إنشاء: ${success}`);
  console.log(`  ⏭️  تم تخطي: ${skipped}`);
  console.log(`  ❌ فشل: ${failed}`);
  console.log('═══════════════════════════════════════════════════════════════');
}

main().catch(console.error);
