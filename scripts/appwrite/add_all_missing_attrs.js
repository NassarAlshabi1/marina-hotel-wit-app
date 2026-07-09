#!/usr/bin/env node
/**
 * إضافة جميع السمات المفقودة إلى Appwrite Cloud
 * بناءً على فحص مباشر من Appwrite API ومقارنة مع الكود
 */
const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = process.env.APPWRITE_API_KEY || '';

const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
const databases = new Databases(client);

// السمات المفقودة لكل مجموعة — فقط ما يحتاجه الكود
const MISSING = {
  rooms: [
    { key: 'basePrice', type: 'double', required: false },
    { key: 'floor', type: 'integer', required: false },
    { key: 'bedsCount', type: 'integer', required: false },
  ],
  employees: [
    { key: 'salary', type: 'double', required: false },
    { key: 'terminationDate', type: 'string', size: 50, required: false },
    { key: 'terminationReason', type: 'string', size: 200, required: false },
  ],
  bookings: [
    { key: 'expectedNights', type: 'integer', required: false },
    { key: 'discount', type: 'double', required: false },
    { key: 'discountType', type: 'string', size: 50, required: false },
    { key: 'discountStartDate', type: 'string', size: 50, required: false },
    { key: 'deletedAt', type: 'integer', required: false },
    { key: 'deletedAtIso', type: 'string', size: 50, required: false },
    { key: 'version', type: 'integer', required: false, default: 1 },
    { key: 'origin', type: 'string', size: 50, required: false, default: 'local' },
    { key: 'vectorClock', type: 'string', size: 500, required: false, default: '{}' },
    { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
    { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
    { key: 'idempotencyKey', type: 'string', size: 200, required: false },
    { key: 'updatedAtIso', type: 'string', size: 50, required: false },
  ],
  payments: [
    { key: 'version', type: 'integer', required: false, default: 1 },
    { key: 'origin', type: 'string', size: 50, required: false, default: 'local' },
    { key: 'vectorClock', type: 'string', size: 500, required: false, default: '{}' },
    { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
    { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
    { key: 'deletedAtIso', type: 'string', size: 50, required: false },
    { key: 'discountAmount', type: 'double', required: false },
    { key: 'discountStartDate', type: 'string', size: 50, required: false },
    { key: 'isVoided', type: 'boolean', required: false, default: false },
    { key: 'voidedAt', type: 'integer', required: false },
    { key: 'voidedBy', type: 'string', size: 200, required: false },
    { key: 'idempotencyKey', type: 'string', size: 200, required: false },
    { key: 'deviceId', type: 'string', size: 100, required: false, default: '' },
    { key: 'syncTimestamp', type: 'integer', required: false, default: 0 },
  ],
  debts: [
    { key: 'remainingAmount', type: 'double', required: false },
    { key: 'version', type: 'integer', required: false, default: 1 },
    { key: 'origin', type: 'string', size: 50, required: false, default: 'local' },
    { key: 'vectorClock', type: 'string', size: 500, required: false, default: '{}' },
    { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
    { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
    { key: 'deletedAtIso', type: 'string', size: 50, required: false },
    { key: 'idempotencyKey', type: 'string', size: 200, required: false },
    { key: 'deviceId', type: 'string', size: 100, required: false, default: '' },
    { key: 'syncTimestamp', type: 'integer', required: false, default: 0 },
  ],
  booking_nights: [
    { key: 'adjustment', type: 'double', required: false },
    { key: 'finalRate', type: 'double', required: false },
    { key: 'appliedAdjustmentUuid', type: 'string', size: 100, required: false },
    { key: 'appliedAdjustmentsJson', type: 'string', size: 2000, required: false },
    { key: 'nightNumber', type: 'integer', required: false },
  ],
  salary_withdrawals: [
    { key: 'withdrawDate', type: 'string', size: 50, required: false },
    { key: 'withdrawalType', type: 'string', size: 100, required: false },
    { key: 'description', type: 'string', size: 500, required: false },
    { key: 'reason', type: 'string', size: 200, required: false },
    { key: 'hotelDayKey', type: 'string', size: 50, required: false },
  ],
  salary_payments: [
    { key: 'amount', type: 'double', required: false },
    { key: 'paymentLocalId', type: 'integer', required: false },
  ],
  salary_cycles: [
    { key: 'expectedAmount', type: 'double', required: false, default: 0 },
    { key: 'employeeUuid', type: 'string', size: 100, required: false },
    { key: 'employeeLocalUuid', type: 'string', size: 100, required: false },
  ],
  booking_price_adjustments: [
    { key: 'amount', type: 'integer', required: false },
    { key: 'roomNumber', type: 'string', size: 50, required: false },
    { key: 'idempotencyKey', type: 'string', size: 200, required: false },
  ],
  price_adjustments: [
    { key: 'idempotencyKey', type: 'string', size: 200, required: false },
  ],
  audit_logs: [
    { key: 'idempotencyKey', type: 'string', size: 200, required: false },
  ],
  payment_voids: [
    { key: 'idempotencyKey', type: 'string', size: 200, required: false },
  ],
  shift_notes: [],
};

async function getExistingAttrs(collectionId) {
  const { attributes } = await databases.listAttributes(DATABASE_ID, collectionId);
  return new Set(attributes.filter(a => a.key && !a.key.startsWith('$')).map(a => a.key));
}

async function addAttribute(collectionId, attr) {
  try {
    switch (attr.type) {
      case 'integer':
        return await databases.createIntegerAttribute(DATABASE_ID, collectionId, attr.key, attr.required || false, attr.default);
      case 'string':
        return await databases.createStringAttribute(DATABASE_ID, collectionId, attr.key, attr.size || 256, attr.required || false, attr.default);
      case 'boolean':
        return await databases.createBooleanAttribute(DATABASE_ID, collectionId, attr.key, attr.required || false, attr.default);
      case 'double':
        return await databases.createFloatAttribute(DATABASE_ID, collectionId, attr.key, attr.required || false, attr.default);
    }
  } catch (error) {
    if (error.message && error.message.includes('already exists')) return 'exists';
    throw error;
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🔧 إضافة جميع السمات المفقودة إلى Appwrite Cloud');
  console.log('═══════════════════════════════════════════════════════════\n');

  let totalAdded = 0;
  let totalSkipped = 0;

  for (const [collId, attrs] of Object.entries(MISSING)) {
    if (attrs.length === 0) continue;
    console.log(`📋 ${collId} — فحص ${attrs.length} سمات...`);
    const existing = await getExistingAttrs(collId);
    
    for (const attr of attrs) {
      if (existing.has(attr.key)) {
        console.log(`  ⏭️ ${attr.key} موجود بالفعل`);
        totalSkipped++;
        continue;
      }
      try {
        await addAttribute(collId, attr);
        console.log(`  ✅ تم إضافة ${attr.key} (${attr.type})`);
        totalAdded++;
        await new Promise(r => setTimeout(r, 300)); // rate limiting
      } catch (error) {
        console.error(`  ❌ فشل ${attr.key}: ${error.message}`);
      }
    }
  }

  console.log(`\n═══════════════════════════════════════════════════════════`);
  console.log(`✅ اكتمل: ${totalAdded} إضافة، ${totalSkipped} موجود سابقاً`);
  console.log('═══════════════════════════════════════════════════════════');

  // عرض جميع السمات الحالية لكل Collection
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('📋 السمات الحالية في كل Collection:');
  console.log('═══════════════════════════════════════════════════════════\n');
  for (const [collId] of Object.entries(MISSING)) {
    try {
      const { attributes } = await databases.listAttributes(DATABASE_ID, collId);
      console.log(`📋 ${collId}:`);
      for (const attr of attributes) {
        if (!attr.key.startsWith('$')) {
          console.log(`   - ${attr.key} (${attr.type}) [${attr.status}]${attr.required ? ' required' : ''}`);
        }
      }
      console.log('');
    } catch (_) {}
  }
}

main().catch(e => { console.error(e); process.exit(1); });