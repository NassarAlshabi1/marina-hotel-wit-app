#!/usr/bin/env node
/**
 * =============================================================================
 * سكربت شامل لإضافة جميع الحقول الناقصة — النسخة النهائية
 * =============================================================================
 * يجمع كل الحقول من السكربتات السابقة:
 *   - add_all_missing_fields.js (termination fields, salary_withdrawals)
 *   - add_all_missing_attrs.js (rooms, bookings, payments, debts, etc.)
 *   - finally-collection (1).js (extra fields: cleaningStatus, pledge, etc.)
 *   - create_appwrite_collections.js (original sync fields)
 *
 * يستخدم env vars أو القيم الجديدة الافتراضية.
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=... node add_all_missing_attrs_combined.js
 */

const { Client, Databases } = require("node-appwrite");

const ENDPOINT     = process.env.APPWRITE_ENDPOINT     || 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID   = process.env.APPWRITE_PROJECT      || '690ff0da0025518570c1';
const DATABASE_ID  = process.env.APPWRITE_DATABASE_ID  || 'hotel_db';
const API_KEY      = process.env.APPWRITE_API_KEY;

if (!API_KEY) { console.error("❌ APPWRITE_API_KEY مطلوب"); process.exit(1); }

const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
const db = new Databases(client);

const sleep = (ms) => new Promise(r => setTimeout(r, ms));

// ─── جميع الحقول المفقودة لكل Collection ─────────────────────────
const ALL_FIELDS = {
  rooms: [
    { key: 'basePrice',               type: 'float',   size: null, required: false },
    { key: 'floor',                    type: 'integer', size: null, required: false },
    { key: 'bedsCount',                type: 'integer', size: null, required: false },
    { key: 'cleaningStatus',           type: 'string',  size: 50,  required: false, default: 'clean' },
    { key: 'lastCleanedHotelDay',      type: 'string',  size: 50,  required: false },
    { key: 'lastOccupiedHotelDay',     type: 'string',  size: 50,  required: false },
    { key: 'requiresMaintenance',      type: 'boolean', size: null, required: false, default: false },
  ],
  bookings: [
    // ——— حقول من اضافتها السابقة ———
    { key: 'discountType',             type: 'string',  size: 50,  required: false, default: 'per_night' },
    { key: 'discountStartDate',        type: 'string',  size: 50,  required: false },
    { key: 'guestIdIssueDate',         type: 'string',  size: 50,  required: false },
    { key: 'guestIdIssuePlace',        type: 'string',  size: 200, required: false },
    { key: 'totalNightsCached',        type: 'integer', size: null, required: false, default: 0 },
    { key: 'actualCheckout',           type: 'string',  size: 50,  required: false },
    { key: 'serverBookingId',          type: 'integer', size: null, required: false },
    { key: 'idempotencyKey',           type: 'string',  size: 200, required: false },
    { key: 'deviceId',                 type: 'string',  size: 100, required: false, default: '' },
    { key: 'syncTimestamp',            type: 'integer', size: null, required: false, default: 0 },
    { key: 'stayDurationIso',          type: 'string',  size: 50,  required: false },
    { key: 'lastNightEpoch',           type: 'integer', size: null, required: false },
    { key: 'isOverdue',                type: 'boolean', size: null, required: false, default: false },
    { key: 'needsCheckoutReview',      type: 'boolean', size: null, required: false, default: false },
    { key: 'isFullyPaid',              type: 'boolean', size: null, required: false, default: false },
  ],
  payments: [
    { key: 'hotelDayKey',              type: 'string',  size: 50,  required: false },
    { key: 'cashTransactionLocalId',   type: 'integer', size: null, required: false },
    { key: 'cashTransactionServerId',  type: 'integer', size: null, required: false },
    { key: 'referenceNumber',          type: 'string',  size: 100, required: false },
    { key: 'serverPaymentId',          type: 'integer', size: null, required: false },
    { key: 'isPendingBalance',         type: 'boolean', size: null, required: false, default: false },
    { key: 'linkedDebtUuid',           type: 'string',  size: 64,  required: false },
    { key: 'bookingUuidCache',         type: 'string',  size: 64,  required: false },
    { key: 'discountAmount',           type: 'float',   size: null, required: false },
    { key: 'discountStartDate',        type: 'string',  size: 50,  required: false },
    { key: 'idempotencyKey',           type: 'string',  size: 200, required: false },
    { key: 'deviceId',                 type: 'string',  size: 100, required: false, default: '' },
    { key: 'syncTimestamp',            type: 'integer', size: null, required: false, default: 0 },
  ],
  expenses: [
    { key: 'hotelDayKey',              type: 'string',  size: 50,  required: false },
    { key: 'relatedId',                type: 'integer', size: null, required: false },
    { key: 'cashTransactionId',        type: 'integer', size: null, required: false },
    { key: 'categoryUuid',             type: 'string',  size: 64,  required: false },
    { key: 'cashFlowUuid',             type: 'string',  size: 64,  required: false },
    { key: 'isAutoGenerated',          type: 'boolean', size: null, required: false, default: false },
  ],
  employees: [
    { key: 'terminationDate',          type: 'string',  size: 50,  required: false },
    { key: 'terminationReason',        type: 'string',  size: 500, required: false },
  ],
  debts: [
    { key: 'remainingAmount',          type: 'float',   size: null, required: false },
    { key: 'idempotencyKey',           type: 'string',  size: 200, required: false },
    { key: 'deviceId',                 type: 'string',  size: 100, required: false, default: '' },
    { key: 'syncTimestamp',            type: 'integer', size: null, required: false, default: 0 },
  ],
  booking_nights: [
    { key: 'adjustment',               type: 'float',   size: null, required: false, default: 0.0 },
    { key: 'finalRate',                type: 'float',   size: null, required: false, default: 0.0 },
    { key: 'appliedAdjustmentUuid',     type: 'string', size: 64,  required: false },
    { key: 'appliedAdjustmentsJson',    type: 'string', size: 5000, required: false },
    { key: 'baseRate',                 type: 'float',   size: null, required: false, default: 0.0 },
    { key: 'isProcessedByAutoFix',     type: 'boolean', size: null, required: false, default: false },
    { key: 'deletedAtIso',             type: 'string',  size: 30,  required: false },
    { key: 'createdAtEpoch',           type: 'integer', size: null, required: false, default: 0 },
    { key: 'lastModifiedEpoch',        type: 'integer', size: null, required: false, default: 0 },
  ],
  booking_price_adjustments: [
    { key: 'adjustmentMode',           type: 'string',  size: 20,  required: false, default: 'per_night' },
    { key: 'idempotencyKey',           type: 'string',  size: 200, required: false },
    { key: 'roomNumber',               type: 'string',  size: 50,  required: false },
    { key: 'cancelledAt',              type: 'string',  size: 30,  required: false },
    { key: 'cancelledBy',              type: 'string',  size: 100, required: false },
  ],
  price_adjustments: [
    { key: 'idempotencyKey',           type: 'string',  size: 200, required: false },
    { key: 'reversedAt',               type: 'string',  size: 30,  required: false },
    { key: 'reversedBy',               type: 'string',  size: 100, required: false },
  ],
  salary_withdrawals: [
    { key: 'withdrawDate',             type: 'string',  size: 50,  required: false },
    { key: 'reason',                   type: 'string',  size: 500, required: false },
    { key: 'hotelDayKey',              type: 'string',  size: 50,  required: false },
    { key: 'withdrawalType',           type: 'string',  size: 50,  required: false },
    { key: 'description',              type: 'string',  size: 500, required: false },
    { key: 'employeeUuid',             type: 'string',  size: 100, required: false },
  ],
  salary_cycles: [
    { key: 'employeeUuid',             type: 'string',  size: 100, required: false },
    { key: 'employeeLocalUuid',        type: 'string',  size: 100, required: false },
    { key: 'hotelDayStart',            type: 'string',  size: 50,  required: false },
    { key: 'hotelDayEnd',              type: 'string',  size: 50,  required: false },
  ],
  salary_payments: [
    // amount موجود مسبقاً — فقط للتأكد
  ],
  shift_notes: [
    { key: 'expiresAt',                type: 'string',  size: 30,  required: false },
    { key: 'shiftDate',                type: 'string',  size: 30,  required: false },
    { key: 'note',                     type: 'string',  size: 10000, required: false },
  ],
  audit_logs: [
    { key: 'idempotencyKey',           type: 'string',  size: 200, required: false },
  ],
  payment_voids: [
    { key: 'idempotencyKey',           type: 'string',  size: 200, required: false },
  ],
};

// ─── دوال مساعدة ──────────────────────────────────────────────────
async function getExistingAttrs(collectionId) {
  try {
    const { attributes } = await db.listAttributes(DATABASE_ID, collectionId);
    return new Set(attributes.filter(a => a.key && !a.key.startsWith('$')).map(a => a.key));
  } catch (e) {
    console.warn(`⚠️  فشل جلب سمات ${collectionId}: ${e.message}`);
    return new Set();
  }
}

async function addOneAttr(collectionId, attr) {
  try {
    switch (attr.type) {
      case 'string':
        await db.createStringAttribute(DATABASE_ID, collectionId, attr.key, attr.size || 65535, attr.required || false, attr.default !== undefined ? attr.default : undefined);
        break;
      case 'integer':
        await db.createIntegerAttribute(DATABASE_ID, collectionId, attr.key, attr.required || false, undefined, undefined, attr.default !== undefined ? attr.default : undefined);
        break;
      case 'float':
        await db.createFloatAttribute(DATABASE_ID, collectionId, attr.key, attr.required || false, undefined, undefined, attr.default !== undefined ? attr.default : undefined);
        break;
      case 'boolean':
        await db.createBooleanAttribute(DATABASE_ID, collectionId, attr.key, attr.required || false, attr.default !== undefined ? attr.default : undefined);
        break;
    }
    return 'added';
  } catch (e) {
    if (e.code === 409) return 'exists';
    throw e;
  }
}

// ─── رئيسي ────────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  إضافة جميع الحقول الناقصة — النسخة المدمجة النهائية');
  console.log(`  Database: ${DATABASE_ID}`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  let totalAdded = 0, totalSkipped = 0, totalFailed = 0;

  for (const [collId, fields] of Object.entries(ALL_FIELDS)) {
    if (fields.length === 0) continue;
    console.log(`📋 ${collId} — ${fields.length} حقل`);
    const existing = await getExistingAttrs(collId);
    if (existing.size === 0) {
      console.log(`   ⚠️  تعذر فحص الحقول الموجودة — قد تكون مشكلة اتصال`);
    }

    for (const field of fields) {
      if (existing.has(field.key)) {
        console.log(`   ⏭️  ${field.key} موجود مسبقاً`);
        totalSkipped++;
        continue;
      }
      try {
        const result = await addOneAttr(collId, field);
        if (result === 'added') {
          console.log(`   ✅ ${field.key} (${field.type})`);
          totalAdded++;
          await sleep(500);
        } else {
          console.log(`   ⏭️  ${field.key} موجود (409)`);
          totalSkipped++;
        }
      } catch (e) {
        console.error(`   ❌ ${field.key}: ${e.message}`);
        totalFailed++;
      }
    }
    console.log('');
  }

  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  ✅ تمت الإضافة: ${totalAdded}`);
  console.log(`  ⏭️  موجود مسبقاً: ${totalSkipped}`);
  console.log(`  ❌ فشل: ${totalFailed}`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  if (totalFailed > 0) {
    console.log('⚠️  توجد أخطاء — قد تحتاج إلى فحص Appwrite Console');
    console.log('   للمشروع: https://cloud.appwrite.io/console');
  } else {
    console.log('🎉 جميع الحقول موجودة!');
  }
}

main().catch(e => { console.error('❌ خطأ عام:', e); process.exit(1); });
