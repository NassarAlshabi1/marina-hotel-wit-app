const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const COLLECTION_ID = 'booking_nights';

const API_KEY = process.env.APPWRITE_API_KEY;

if (!API_KEY) {
  console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
  console.error('Usage: APPWRITE_API_KEY=your_api_key node migrate_booking_nights_pricing.js');
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

async function createFloatAttribute(key, required = false, defaultValue = null) {
  try {
    await databases.createFloatAttribute(
      DATABASE_ID, COLLECTION_ID, key, required,
      defaultValue !== null ? undefined : undefined,
      defaultValue !== null ? undefined : undefined,
      defaultValue
    );
    console.log(`  ✅ Float attribute: ${key}`);
  } catch (error) {
    if (error.code === 409) {
      console.log(`  ⏭️  Attribute exists: ${key}`);
    } else {
      console.error(`  ❌ Failed ${key}: ${error.message}`);
    }
  }
}

async function createStringAttribute(key, size, required = false) {
  try {
    await databases.createStringAttribute(
      DATABASE_ID, COLLECTION_ID, key, size, required
    );
    console.log(`  ✅ String attribute: ${key}`);
  } catch (error) {
    if (error.code === 409) {
      console.log(`  ⏭️  Attribute exists: ${key}`);
    } else {
      console.error(`  ❌ Failed ${key}: ${error.message}`);
    }
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🏨 Marina Hotel - Migrate booking_nights pricing fields');
  console.log('═══════════════════════════════════════════════════════════\n');

  console.log('Adding pricing fields to booking_nights collection...\n');

  await createFloatAttribute('baseRate', false, 0);
  await sleep(1000);
  await createFloatAttribute('adjustment', false, 0);
  await sleep(1000);
  await createFloatAttribute('finalRate', false, 0);
  await sleep(1000);
  await createStringAttribute('appliedAdjustmentUuid', 36, false);
  await sleep(1000);
  await createStringAttribute('appliedAdjustmentsJson', 5000, false);

  console.log('\n⏳ Waiting for attributes to be ready...');
  for (let i = 0; i < 15; i++) {
    await sleep(2000);
    try {
      const collection = await databases.getCollection(DATABASE_ID, COLLECTION_ID);
      const available = collection.attributes.filter(a => a.status === 'available').length;
      const total = collection.attributes.length;
      console.log(`  ${available}/${total} attributes ready...`);
      if (available === total) {
        console.log('\n✅ All attributes ready!');
        break;
      }
    } catch (e) {
      // ignore
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════');
  console.log('✅ Migration complete!');
  console.log('═══════════════════════════════════════════════════════════');
  console.log('\nNext: Update _allowedFields in appwrite_delta_sync.dart');
  console.log('to include: baseRate, adjustment, finalRate,');
  console.log('appliedAdjustmentUuid, appliedAdjustmentsJson');
  console.log('═══════════════════════════════════════════════════════════\n');
}

main().catch(console.error);
