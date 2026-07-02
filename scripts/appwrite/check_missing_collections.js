#!/usr/bin/env node
/**
 * يفحص فقط (بدون API key) هل الـ collection موجودة على Appwrite Cloud.
 * يستخدم وصول عام (read-only) عبر مشروع SPA.
 */

const { Client, Databases, Query } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId);

const databases = new Databases(client);

const collectionsToCheck = [
  'rooms', 'bookings', 'payments', 'guest_infos', 'salary_withdrawals',
  'salary_carry_over_logs', 'blacklist', 'app_settings', 'app_users',
  'sync_state',
];

async function checkCollection(name) {
  try {
    // محاولة listDocuments مع limit 0 للتحقق من وجود الـ collection
    await databases.listDocuments(databaseId, name, [Query.limit(1)]);
    return { name, exists: true, error: null };
  } catch (e) {
    const code = e.code;
    const msg = e.message || '';
    if (code === 404 || msg.includes('not found') || msg.includes('Collection')) {
      return { name, exists: false, error: `404 — Collection not found` };
    }
    return { name, exists: true, error: `code=${code} (${msg.substring(0, 80)})` };
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  فحص وجود الـ collections على Appwrite Cloud (read-only)');
  console.log('═══════════════════════════════════════════════════════════════\n');

  const results = [];
  for (const name of collectionsToCheck) {
    const result = await checkCollection(name);
    results.push(result);
    const status = result.exists ? '✅ EXISTS' : '❌ MISSING';
    const err = result.error ? ` (${result.error})` : '';
    console.log(`  ${status}  ${name}${err}`);
  }

  const missing = results.filter((r) => !r.exists);
  console.log(`\n📊 Summary: ${results.length - missing.length}/${results.length} exist, ${missing.length} missing`);
  if (missing.length > 0) {
    console.log('\n⚠️  Missing collections:');
    missing.forEach((r) => console.log(`   - ${r.name}`));
    console.log('\n📝 Run this to fix:');
    console.log('   APPWRITE_API_KEY=your_appwrite_api_key node create_missing_collections.js');
  }
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
