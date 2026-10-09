#!/usr/bin/env node
/**
 * سكربت مقارنة شامل: ي سحب كل سمات كل collection من Appwrite Cloud
 * ويطبعها بشكل منظم للمقارنة مع الـ DB المحلي
 */

const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

const SYNCED_COLLECTIONS = [
  'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
  'booking_notes', 'booking_nights', 'cash_transactions', 'shift_notes',
  'salary_cycles', 'salary_payments', 'salary_withdrawals',
  'price_adjustments', 'booking_price_adjustments',
  'audit_logs', 'payment_voids', 'guest_infos', 'blacklist',
  // non-synced but exist
  'devices', 'sync_logs', 'app_settings', 'outbox', 'sync_state', 'app_users',
];

async function main() {
  const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
  const databases = new Databases(client);

  console.log('═══════════════════════════════════════════════════════════');
  console.log('🔍 فحص شامل لكل سمات Appwrite Cloud');
  console.log('═══════════════════════════════════════════════════════════\n');

  const results = {};

  for (const collId of SYNCED_COLLECTIONS) {
    try {
      const { attributes } = await databases.listAttributes(DATABASE_ID, collId);
      const attrs = attributes
        .filter(a => a.key && !a.key.startsWith('$'))
        .map(a => ({
          key: a.key,
          type: a.type,
          size: a.size || null,
          required: a.required,
          default: a.default ?? null,
          status: a.status,
          array: a.array || false,
        }))
        .sort((a, b) => a.key.localeCompare(b.key));

      results[collId] = attrs;
      console.log(`📋 ${collId} (${attrs.length} attributes):`);
      for (const a of attrs) {
        const req = a.required ? 'REQ' : 'OPT';
        const arr = a.array ? '[ARR]' : '';
        const sz = a.size ? `(${a.size})` : '';
        const def = a.default !== null ? ` def=${JSON.stringify(a.default)}` : '';
        const st = a.status !== 'available' ? ` [${a.status}]` : '';
        console.log(`   ${a.key}: ${a.type}${sz} ${req}${arr}${def}${st}`);
      }
      console.log('');
    } catch (error) {
      console.log(`📋 ${collId}: ❌ خطأ - ${error.message}\n`);
    }
  }

  // Output JSON for programmatic comparison
  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('📊 ملخص: عدد السمات لكل collection');
  console.log('═══════════════════════════════════════════════════════════');
  for (const [coll, attrs] of Object.entries(results)) {
    const available = attrs.filter(a => a.status === 'available').length;
    const failed = attrs.filter(a => a.status === 'failed').length;
    const processing = attrs.filter(a => a.status === 'processing').length;
    let status = '✅';
    if (failed > 0) status = '❌';
    else if (processing > 0) status = '⏳';
    console.log(`   ${status} ${coll}: ${available} جاهز${processing > 0 ? `, ${processing} قيد المعالجة` : ''}${failed > 0 ? `, ${failed} فاشل` : ''}`);
  }
}

main().catch(e => { console.error(e); process.exit(1); });
