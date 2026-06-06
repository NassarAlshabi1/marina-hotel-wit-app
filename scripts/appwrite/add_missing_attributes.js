#!/usr/bin/env node
/**
 * سكربت لإضافة السمات المفقودة إلى مجموعة payments في Appwrite Cloud
 * 
 * هذه السمات ضرورية لمزامنة softDelete وبيانات الإلغاء والخصومات بشكل صحيح
 * بدونها، لا يمكن للأجهزة الأخرى رؤية:
 * - deletedAtIso: تاريخ الحذف المؤقت بصيغة ISO
 * - isVoided: هل الدفعة ملغاة
 * - voidedAt: وقت الإلغاء
 * - voidedBy: من ألغى الدفعة
 * - discountAmount: مبلغ الخصم
 * - discountStartDate: تاريخ بدء الخصم
 * - version: رقم إصدار السجل (لحل التعارضات)
 * - vectorClock: ساعة المتجهات (لحل التعارضات)
 * - createdAtEpoch: تاريخ الإنشاء بصيغة Epoch
 * - lastModifiedEpoch: تاريخ التعديل بصيغة Epoch
 */

const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const databases = new Databases(client);

/**
 * السمات المفقودة في مجموعة payments
 * النوع: 'integer' | 'string' | 'boolean' | 'double'
 */
const MISSING_PAYMENT_ATTRS = [
  { key: 'deletedAtIso', type: 'string', size: 50, required: false },
  { key: 'isVoided', type: 'boolean', required: false, default: false },
  { key: 'voidedAt', type: 'integer', required: false },
  { key: 'voidedBy', type: 'string', size: 200, required: false },
  { key: 'discountAmount', type: 'double', required: false },
  { key: 'discountStartDate', type: 'string', size: 50, required: false },
  { key: 'version', type: 'integer', required: false, default: 1 },
  { key: 'vectorClock', type: 'string', size: 500, required: false, default: '{}' },
  { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
  { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
];

/**
 * سمات SyncFields المفقودة في المجموعات الأخرى
 * يتم فحص كل مجموعة وإضافة ما ينقصها فقط
 */
const SYNC_FIELD_ATTRS = [
  { key: 'deletedAtIso', type: 'string', size: 50, required: false },
  { key: 'version', type: 'integer', required: false, default: 1 },
  { key: 'vectorClock', type: 'string', size: 500, required: false, default: '{}' },
  { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
  { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
];

async function getExistingAttrs(collectionId) {
  const { attributes } = await databases.listAttributes(DATABASE_ID, collectionId);
  return new Set(attributes.filter(a => a.key && !a.key.startsWith('$')).map(a => a.key));
}

async function addAttribute(collectionId, attr) {
  try {
    let result;
    switch (attr.type) {
      case 'integer':
        result = await databases.createIntegerAttribute(
          DATABASE_ID, collectionId, attr.key,
          attr.required || false,
          attr.default !== undefined ? attr.default : undefined
        );
        break;
      case 'string':
        result = await databases.createStringAttribute(
          DATABASE_ID, collectionId, attr.key,
          attr.size || 256,
          attr.required || false,
          attr.default !== undefined ? attr.default : undefined
        );
        break;
      case 'boolean':
        result = await databases.createBooleanAttribute(
          DATABASE_ID, collectionId, attr.key,
          attr.required || false,
          attr.default !== undefined ? attr.default : undefined
        );
        break;
      case 'double':
        result = await databases.createFloatAttribute(
          DATABASE_ID, collectionId, attr.key,
          attr.required || false,
          attr.default !== undefined ? attr.default : undefined
        );
        break;
    }
    console.log(`  ✅ تم إضافة ${attr.key} (${attr.type}) إلى ${collectionId}`);
    return true;
  } catch (error) {
    if (error.message && error.message.includes('already exists')) {
      console.log(`  ⏭️ ${attr.key} موجود بالفعل في ${collectionId}`);
      return false;
    }
    console.error(`  ❌ فشل إضافة ${attr.key} إلى ${collectionId}: ${error.message}`);
    return false;
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🔧 إضافة السمات المفقودة إلى Appwrite Cloud');
  console.log('═══════════════════════════════════════════════════════════\n');

  // ── 1. مجموعة payments: إضافة جميع السمات المفقودة ──
  console.log('📋 payments — إضافة السمات المفقودة...');
  const paymentAttrs = await getExistingAttrs('payments');
  for (const attr of MISSING_PAYMENT_ATTRS) {
    if (!paymentAttrs.has(attr.key)) {
      await addAttribute('payments', attr);
      // انتظار قصير بين الإضافات لتجنب rate limiting
      await new Promise(r => setTimeout(r, 500));
    } else {
      console.log(`  ⏭️ ${attr.key} موجود بالفعل في payments`);
    }
  }

  // ── 2. المجموعات الأخرى: إضافة سمات SyncFields المفقودة ──
  const otherCollections = [
    'bookings', 'debts', 'cash_transactions',
    'salary_cycles', 'salary_payments', 'salary_withdrawals',
    'booking_price_adjustments', 'payment_voids', 'guest_infos', 'blacklist',
  ];

  for (const collId of otherCollections) {
    console.log(`\n📋 ${collId} — فحص سمات SyncFields...`);
    const existing = await getExistingAttrs(collId);
    for (const attr of SYNC_FIELD_ATTRS) {
      if (!existing.has(attr.key)) {
        await addAttribute(collId, attr);
        await new Promise(r => setTimeout(r, 500));
      } else {
        console.log(`  ⏭️ ${attr.key} موجود بالفعل في ${collId}`);
      }
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('✅ اكتملت إضافة السمات المفقودة');
  console.log('═══════════════════════════════════════════════════════════');
}

main().catch(e => { console.error(e); process.exit(1); });
