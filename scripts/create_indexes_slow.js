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

async function createIndex(coll, key, type, attrs) {
  try {
    await databases.createIndex(DATABASE_ID, coll, key, type, attrs);
    console.log(`✅ ${coll}.${key}`);
    return true;
  } catch (error) {
    if (error.code === 409) {
      console.log(`⏭️  ${coll}.${key} (exists)`);
      return true;
    }
    console.log(`❌ ${coll}.${key}: ${error.message}`);
    return false;
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🏨 Marina Hotel - Creating Indexes (slow mode)');
  console.log('═══════════════════════════════════════════════════════════\n');

  const t = Date.now();

  const indexes = [
    // price_adjustments
    ['price_adjustments', `pa_localuuid_${t}`, IndexType.Unique, ['localUuid']],
    ['price_adjustments', `pa_target_${t}`, IndexType.Key, ['targetType', 'targetUuid']],
    ['price_adjustments', `pa_syncts_${t}`, IndexType.Key, ['syncTimestamp']],
    
    // audit_logs  
    ['audit_logs', `al_localuuid_${t}`, IndexType.Unique, ['localUuid']],
    ['audit_logs', `al_entity_${t}`, IndexType.Key, ['entityType', 'entityUuid']],
    ['audit_logs', `al_financial_${t}`, IndexType.Key, ['isFinancial', 'hotelDayKey']],
    ['audit_logs', `al_syncts_${t}`, IndexType.Key, ['syncTimestamp']],
    
    // payment_voids
    ['payment_voids', `pv_localuuid_${t}`, IndexType.Unique, ['localUuid']],
    ['payment_voids', `pv_origpay_${t}`, IndexType.Unique, ['originalPaymentUuid']],
    ['payment_voids', `pv_booking_${t}`, IndexType.Key, ['bookingUuid']],
    ['payment_voids', `pv_hotelday_${t}`, IndexType.Key, ['hotelDayKey']],
    ['payment_voids', `pv_syncts_${t}`, IndexType.Key, ['syncTimestamp']],
    
    // payments
    ['payments', `pay_voided_${t}`, IndexType.Key, ['isVoided']],
  ];

  let success = 0;
  let failed = 0;

  for (let i = 0; i < indexes.length; i++) {
    const [coll, key, type, attrs] = indexes[i];
    console.log(`[${i + 1}/${indexes.length}] Creating ${coll}.${key}...`);
    
    if (await createIndex(coll, key, type, attrs)) {
      success++;
    } else {
      failed++;
    }
    
    if (i < indexes.length - 1) {
      console.log('    ⏳ Waiting 5 seconds...\n');
      await sleep(5000);
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log(`✅ Complete: ${success} success, ${failed} failed`);
  console.log('═══════════════════════════════════════════════════════════\n');
}

main();
