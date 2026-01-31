const { Client, Databases } = require('node-appwrite');

const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1';
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

if (!apiKey) {
  console.error('❌ Missing APPWRITE_API_KEY');
  console.log('\nUsage:');
  console.log('  APPWRITE_API_KEY="your-key" node verify_collections.js');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

const requiredCollections = [
  'rooms',
  'bookings',
  'booking_notes',
  'booking_nights',
  'employees',
  'expenses',
  'cash_transactions',
  'payments',
  'debts',
  'salary_cycles',
  'salary_payments',
  'hotel_day_ledger',
  'shift_notes',
  'devices',
  'sync_logs',
];

const requiredSyncFields = [
  'localUuid',
  'serverId',
  'createdAt',
  'updatedAt',
  'deletedAt',
  'lastModified',
  'createdAtIso',
  'updatedAtIso',
  'deletedAtIso',
  'createdAtEpoch',
  'lastModifiedEpoch',
  'version',
  'origin',
  'vectorClock',
];

async function verifyCollections() {
  console.log('═══════════════════════════════════════');
  console.log('🔍 التحقق من جداول Appwrite');
  console.log('═══════════════════════════════════════');
  console.log(`Endpoint: ${endpoint}`);
  console.log(`Project: ${projectId}`);
  console.log(`Database: ${databaseId}`);
  console.log('═══════════════════════════════════════\n');

  const results = {
    found: [],
    missing: [],
    incomplete: [],
  };

  for (const collectionId of requiredCollections) {
    try {
      const collection = await databases.getCollection(databaseId, collectionId);
      const attributes = collection.attributes || [];
      const attributeKeys = attributes.map(a => a.key);

      const hasSyncFields = collectionId === 'sync_logs' || collectionId === 'devices' || collectionId === 'shift_notes'
        ? true
        : requiredSyncFields.every(field => attributeKeys.includes(field));

      if (hasSyncFields) {
        console.log(`✅ ${collectionId.padEnd(25)} - ${attributes.length} attributes`);
        results.found.push({
          id: collectionId,
          name: collection.name,
          attributesCount: attributes.length,
        });
      } else {
        const missingSyncFields = requiredSyncFields.filter(f => !attributeKeys.includes(f));
        console.log(`⚠️  ${collectionId.padEnd(25)} - missing ${missingSyncFields.length} sync fields`);
        console.log(`     Missing: ${missingSyncFields.join(', ')}`);
        results.incomplete.push({
          id: collectionId,
          missing: missingSyncFields,
        });
      }
    } catch (error) {
      if (error?.code === 404) {
        console.log(`❌ ${collectionId.padEnd(25)} - NOT FOUND`);
        results.missing.push(collectionId);
      } else {
        console.error(`❌ ${collectionId.padEnd(25)} - ERROR: ${error.message}`);
        results.missing.push(collectionId);
      }
    }
  }

  console.log('\n═══════════════════════════════════════');
  console.log('📊 Summary');
  console.log('═══════════════════════════════════════');
  console.log(`Total Required: ${requiredCollections.length}`);
  console.log(`✅ Found: ${results.found.length}`);
  console.log(`⚠️  Incomplete: ${results.incomplete.length}`);
  console.log(`❌ Missing: ${results.missing.length}`);
  console.log(`📈 Completion: ${((results.found.length / requiredCollections.length) * 100).toFixed(1)}%`);
  console.log('═══════════════════════════════════════\n');

  if (results.missing.length > 0) {
    console.log('⚠️  Missing collections:');
    results.missing.forEach(id => console.log(`   - ${id}`));
    console.log('\n💡 Run this to create them:');
    console.log('   node create_all_collections_complete.js\n');
  }

  if (results.incomplete.length > 0) {
    console.log('⚠️  Incomplete collections (missing sync fields):');
    results.incomplete.forEach(c => {
      console.log(`   - ${c.id}: ${c.missing.join(', ')}`);
    });
    console.log('\n💡 Re-run create script to add missing attributes\n');
  }

  if (results.found.length === requiredCollections.length && results.incomplete.length === 0) {
    console.log('🎉 Perfect! All collections are ready for sync.\n');
    console.log('✅ You can now:');
    console.log('   1. Restore backup from Google Drive');
    console.log('   2. Data will auto-sync to Appwrite');
    console.log('   3. All three sources will be identical:\n');
    console.log('      Google Drive → Local DB → Appwrite Cloud ✅\n');
  }

  return results;
}

verifyCollections().catch(console.error);
