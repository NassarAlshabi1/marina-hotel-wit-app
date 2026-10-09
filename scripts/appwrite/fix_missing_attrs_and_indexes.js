#!/usr/bin/env node
/**
 * إصلاح شامل: إضافة attributes مفقودة + فهارس لكل collections.
 *
 * 1. إضافة lastModified attribute (integer) لـ:
 *    - bookings, payments, debts, sync_logs (مفقود كـ attribute رسمي)
 *
 * 2. إضافة localUuid فهرس unique لـ:
 *    - app_users (مفقود)
 *
 * 3. إضافة lastModified فهرس لـ:
 *    - app_users (مفقود)
 */

const { Client, Databases } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

async function main() {
  console.log('═'.repeat(70));
  console.log('  إضافة attributes + فهارس مفقودة');
  console.log('═'.repeat(70) + '\n');

  // ═══ 1. إضافة lastModified attribute ═══
  const needLastModAttr = ['bookings', 'payments', 'debts', 'sync_logs'];
  for (const coll of needLastModAttr) {
    process.stdout.write('📝 ' + coll + ': add lastModified attribute... ');
    try {
      await databases.createIntegerAttribute(databaseId, coll, 'lastModified', false);
      console.log('✅');
    } catch (e) {
      if (e.code === 409 || (e.message && e.message.includes('already exists'))) {
        console.log('✓ already exists');
      } else {
        console.log('❌ ' + e.message.substring(0, 50));
      }
    }
    await new Promise(r => setTimeout(r, 500));
  }

  // ═══ 2. إضافة localUuid فهرس unique لـ app_users ═══
  process.stdout.write('\n📝 app_users: add idx_local_uuid (unique)... ');
  try {
    await databases.createIndex(databaseId, 'app_users', 'idx_local_uuid', 'unique', ['localUuid']);
    console.log('✅');
  } catch (e) {
    if (e.code === 409 || (e.message && e.message.includes('already exists'))) {
      console.log('✓ already exists');
    } else {
      console.log('❌ ' + e.message.substring(0, 50));
    }
  }
  await new Promise(r => setTimeout(r, 500));

  // ═══ 3. إضافة lastModified فهرس لـ app_users ═══
  process.stdout.write('📝 app_users: add idx_lastModified... ');
  try {
    await databases.createIndex(databaseId, 'app_users', 'idx_lastModified', 'key', ['lastModified']);
    console.log('✅');
  } catch (e) {
    if (e.code === 409 || (e.message && e.message.includes('already exists'))) {
      console.log('✓ already exists');
    } else {
      console.log('❌ ' + e.message.substring(0, 50));
    }
  }
  await new Promise(r => setTimeout(r, 500));

  // ═══ 4. التحقق النهائي ═══
  console.log('\n' + '═'.repeat(70));
  console.log('  التحقق النهائي');
  console.log('═'.repeat(70));

  const allCollections = [
    'rooms', 'bookings', 'booking_notes', 'booking_nights',
    'employees', 'expenses', 'cash_transactions', 'payments',
    'debts', 'shift_notes', 'price_adjustments', 'booking_price_adjustments',
    'payment_voids', 'guest_infos', 'salary_cycles', 'salary_payments',
    'salary_withdrawals', 'salary_carry_over_logs', 'blacklist',
    'audit_logs', 'devices', 'sync_logs', 'app_settings', 'app_users', 'sync_state'
  ];

  let allGood = true;
  for (const coll of allCollections) {
    try {
      const attrs = await databases.listAttributes(databaseId, coll);
      const attrMap = {};
      for (const a of attrs.attributes) { attrMap[a.key] = a; }
      const hasLU = !!attrMap['localUuid'];
      const hasLM = !!attrMap['lastModified'];

      let hasLUIdx = false, hasLMIdx = false;
      try {
        const idxs = await databases.listIndexes(databaseId, coll);
        for (const i of idxs.indexes) {
          if (i.attributes.includes('localUuid')) hasLUIdx = true;
          if (i.attributes.includes('lastModified')) hasLMIdx = true;
        }
      } catch (e) {}

      const ok = hasLU && hasLM && hasLUIdx && hasLMIdx;
      if (!ok) allGood = false;
      const status = ok ? '✅' : '⚠️';
      const details = [];
      if (!hasLU) details.push('attr:localUuid');
      if (!hasLM) details.push('attr:lastModified');
      if (!hasLUIdx) details.push('idx:localUuid');
      if (!hasLMIdx) details.push('idx:lastModified');
      const detailStr = details.length > 0 ? ' ← ' + details.join(', ') : '';
      console.log('  ' + status + ' ' + coll.padEnd(30) + detailStr);
    } catch (e) {
      console.log('  ❌ ' + coll.padEnd(28) + ' ERROR');
      allGood = false;
    }
  }

  console.log('\n' + (allGood ? '✅ كل الـ collections جاهزة!' : '⚠️  بعض المشاكل ما زالت موجودة.'));
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
