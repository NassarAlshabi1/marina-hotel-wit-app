const { Client, Databases, IndexType } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';

const API_KEY = process.env.APPWRITE_API_KEY;

if (!API_KEY) {
  console.error('❌ APPWRITE_API_KEY required');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const databases = new Databases(client);

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function createIndexWithRetry(collectionId, key, type, attributes, orders = null, retries = 3) {
  for (let i = 0; i < retries; i++) {
    try {
      await databases.createIndex(DATABASE_ID, collectionId, key, type, attributes, orders);
      console.log(`  ✅ ${collectionId}.${key}`);
      return true;
    } catch (error) {
      if (error.code === 409) {
        console.log(`  ⏭️  ${collectionId}.${key} (exists)`);
        return true;
      }
      if (i < retries - 1) {
        console.log(`  ⏳ Retry ${i + 2}/${retries} for ${key}...`);
        await sleep(3000);
      } else {
        console.error(`  ❌ ${collectionId}.${key}: ${error.message}`);
        return false;
      }
    }
  }
  return false;
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🏨 Marina Hotel - Creating Indexes');
  console.log('═══════════════════════════════════════════════════════════\n');

  console.log('⏳ Waiting 10s for attributes to be fully ready...\n');
  await sleep(10000);

  const indexes = [
    // price_adjustments indexes
    ['price_adjustments', 'idx_local_uuid', IndexType.Unique, ['localUuid']],
    ['price_adjustments', 'idx_target', IndexType.Key, ['targetType', 'targetUuid']],
    ['price_adjustments', 'idx_hotel_day', IndexType.Key, ['hotelDayKey']],
    ['price_adjustments', 'idx_sync_ts', IndexType.Key, ['syncTimestamp']],
    
    // audit_logs indexes
    ['audit_logs', 'idx_local_uuid', IndexType.Unique, ['localUuid']],
    ['audit_logs', 'idx_entity', IndexType.Key, ['entityType', 'entityUuid']],
    ['audit_logs', 'idx_timestamp', IndexType.Key, ['timestamp'], ['DESC']],
    ['audit_logs', 'idx_financial', IndexType.Key, ['isFinancial', 'hotelDayKey']],
    ['audit_logs', 'idx_sync_ts', IndexType.Key, ['syncTimestamp']],
    
    // payment_voids indexes
    ['payment_voids', 'idx_local_uuid', IndexType.Unique, ['localUuid']],
    ['payment_voids', 'idx_original_payment', IndexType.Unique, ['originalPaymentUuid']],
    ['payment_voids', 'idx_booking', IndexType.Key, ['bookingUuid']],
    ['payment_voids', 'idx_hotel_day', IndexType.Key, ['hotelDayKey']],
    ['payment_voids', 'idx_sync_ts', IndexType.Key, ['syncTimestamp']],
    
    // payments index
    ['payments', 'idx_voided', IndexType.Key, ['isVoided']],
  ];

  let success = 0;
  let failed = 0;

  for (const [collection, key, type, attrs, orders] of indexes) {
    const result = await createIndexWithRetry(collection, key, type, attrs, orders);
    if (result) success++;
    else failed++;
    await sleep(1500); // Rate limiting
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log(`✅ Done: ${success} indexes created, ${failed} failed`);
  console.log('═══════════════════════════════════════════════════════════\n');
}

main();
