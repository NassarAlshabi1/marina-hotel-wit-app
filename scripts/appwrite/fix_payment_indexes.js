#!/usr/bin/env node
/**
 * إصلاح فهارس Appwrite Cloud — استبدال bookingLocalId بـ bookingUuidCache.
 *
 * المشكلة: idx_booking_date في payments يفهرس bookingLocalId الذي توقفنا
 * عن إرساله للسيرفر. الفهرس عديم الفائدة الآن.
 *
 * الحل:
 *   1. حذف idx_booking_date (bookingLocalId + paymentDate)
 *   2. إنشاء idx_payments_bookingUuid (bookingUuidCache) — الفهرس الصحيح
 *   3. إنشاء idx_payments_paymentDate (paymentDate) — منفصل
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node fix_payment_indexes.js
 */

const { Client, Databases } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'payments';

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

async function main() {
  console.log('═'.repeat(60));
  console.log('  إصلاح فهارس payments — استبدال bookingLocalId بـ bookingUuidCache');
  console.log('═'.repeat(60) + '\n');

  // 1) اعرض الفهارس الحالية
  console.log('📋 Current indexes:');
  const current = await databases.listIndexes(databaseId, collectionId);
  for (const idx of current.indexes) {
    console.log('  ' + idx.key + ' (' + idx.type + '): ' + JSON.stringify(idx.attributes));
  }
  console.log('');

  // 2) احذف idx_booking_date (bookingLocalId + paymentDate)
  const oldIndexKey = 'idx_booking_date';
  const hasOld = current.indexes.find(i => i.key === oldIndexKey);
  if (hasOld) {
    console.log('🗑️  Deleting ' + oldIndexKey + ' (bookingLocalId + paymentDate)...');
    try {
      await databases.deleteIndex(databaseId, collectionId, oldIndexKey);
      console.log('   ✅ Deleted');
    } catch (e) {
      console.log('   ❌ ' + e.message);
    }
    await new Promise(r => setTimeout(r, 1000));
  } else {
    console.log('⏭️  ' + oldIndexKey + ' not found — skipping');
  }

  // 3) أنشئ idx_payments_bookingUuid (bookingUuidCache)
  const newUuidIndex = 'idx_payments_bookingUuid';
  const hasNewUuid = current.indexes.find(i => i.key === newUuidIndex);
  if (!hasNewUuid) {
    console.log('\n📝 Creating ' + newUuidIndex + ' (bookingUuidCache)...');
    try {
      await databases.createIndex(
        databaseId, collectionId, newUuidIndex, 'key', ['bookingUuidCache']
      );
      console.log('   ✅ Created');
    } catch (e) {
      console.log('   ❌ ' + e.message);
    }
    await new Promise(r => setTimeout(r, 1000));
  } else {
    console.log('\n⏭️  ' + newUuidIndex + ' already exists');
  }

  // 4) أنشئ idx_payments_paymentDate (paymentDate) — منفصل
  const newDateIndex = 'idx_payments_paymentDate';
  const hasNewDate = current.indexes.find(i => i.key === newDateIndex);
  if (!hasNewDate) {
    console.log('\n📝 Creating ' + newDateIndex + ' (paymentDate)...');
    try {
      await databases.createIndex(
        databaseId, collectionId, newDateIndex, 'key', ['paymentDate']
      );
      console.log('   ✅ Created');
    } catch (e) {
      console.log('   ❌ ' + e.message);
    }
    await new Promise(r => setTimeout(r, 1000));
  } else {
    console.log('\n⏭️  ' + newDateIndex + ' already exists');
  }

  // 5) اعرض الفهارس النهائية
  console.log('\n📋 Final indexes:');
  const final = await databases.listIndexes(databaseId, collectionId);
  for (const idx of final.indexes) {
    console.log('  ' + idx.key + ' (' + idx.type + '): ' + JSON.stringify(idx.attributes));
  }

  console.log('\n✅ Done!');
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
