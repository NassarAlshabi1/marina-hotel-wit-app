const { Client, Databases, IndexType } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';

const API_KEY = process.env.APPWRITE_API_KEY;

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const databases = new Databases(client);

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function createIdx(collectionId, key, type, attributes, orders = null) {
  try {
    await databases.createIndex(DATABASE_ID, collectionId, key, type, attributes, orders);
    console.log(`✅ ${collectionId}.${key}`);
    return true;
  } catch (error) {
    if (error.code === 409) {
      console.log(`⏭️  ${collectionId}.${key} (exists)`);
      return true;
    }
    console.error(`❌ ${collectionId}.${key}: ${error.message}`);
    return false;
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🏨 Marina Hotel - Creating Indexes (v2)');
  console.log('═══════════════════════════════════════════════════════════\n');

  let success = 0;
  let failed = 0;

  // price_adjustments indexes - using collection prefix in name
  console.log('📦 price_adjustments indexes:');
  if (await createIdx('price_adjustments', 'priceadj_localuuid', IndexType.Unique, ['localUuid'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('price_adjustments', 'priceadj_target', IndexType.Key, ['targetType', 'targetUuid'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('price_adjustments', 'priceadj_hotelday', IndexType.Key, ['hotelDayKey'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('price_adjustments', 'priceadj_syncts', IndexType.Key, ['syncTimestamp'])) success++; else failed++;
  await sleep(2000);
  
  // audit_logs indexes
  console.log('\n📦 audit_logs indexes:');
  if (await createIdx('audit_logs', 'auditlog_localuuid', IndexType.Unique, ['localUuid'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('audit_logs', 'auditlog_entity', IndexType.Key, ['entityType', 'entityUuid'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('audit_logs', 'auditlog_financial', IndexType.Key, ['isFinancial', 'hotelDayKey'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('audit_logs', 'auditlog_syncts', IndexType.Key, ['syncTimestamp'])) success++; else failed++;
  await sleep(2000);
  
  // payment_voids indexes
  console.log('\n📦 payment_voids indexes:');
  if (await createIdx('payment_voids', 'pvoid_localuuid', IndexType.Unique, ['localUuid'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('payment_voids', 'pvoid_origpayment', IndexType.Unique, ['originalPaymentUuid'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('payment_voids', 'pvoid_booking', IndexType.Key, ['bookingUuid'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('payment_voids', 'pvoid_hotelday', IndexType.Key, ['hotelDayKey'])) success++; else failed++;
  await sleep(2000);
  if (await createIdx('payment_voids', 'pvoid_syncts', IndexType.Key, ['syncTimestamp'])) success++; else failed++;
  await sleep(2000);
  
  // payments index
  console.log('\n📦 payments indexes:');
  if (await createIdx('payments', 'payments_voided', IndexType.Key, ['isVoided'])) success++; else failed++;

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log(`✅ Done: ${success} success, ${failed} failed`);
  console.log('═══════════════════════════════════════════════════════════\n');
}

main();
