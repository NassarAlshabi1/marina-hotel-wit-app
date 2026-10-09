const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';

const API_KEY = process.env.APPWRITE_API_KEY;

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const databases = new Databases(client);

async function checkCollection(collectionId) {
  try {
    const collection = await databases.getCollection(DATABASE_ID, collectionId);
    console.log(`\n📦 ${collection.name} (${collectionId})`);
    console.log(`   Attributes: ${collection.attributes.length}`);
    
    const byStatus = {};
    for (const attr of collection.attributes) {
      byStatus[attr.status] = (byStatus[attr.status] || 0) + 1;
    }
    
    for (const [status, count] of Object.entries(byStatus)) {
      const icon = status === 'available' ? '✅' : status === 'processing' ? '⏳' : '❌';
      console.log(`   ${icon} ${status}: ${count}`);
    }
    
    // Show processing/failed attributes
    const notReady = collection.attributes.filter(a => a.status !== 'available');
    if (notReady.length > 0) {
      console.log('   Not ready:');
      for (const attr of notReady) {
        console.log(`      - ${attr.key}: ${attr.status}`);
      }
    }
    
    // Show indexes
    console.log(`   Indexes: ${collection.indexes.length}`);
    for (const idx of collection.indexes) {
      const icon = idx.status === 'available' ? '✅' : '⏳';
      console.log(`      ${icon} ${idx.key}: ${idx.status}`);
    }
    
  } catch (error) {
    console.error(`❌ Error checking ${collectionId}: ${error.message}`);
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🔍 Checking Appwrite Collections Status');
  console.log('═══════════════════════════════════════════════════════════');

  await checkCollection('price_adjustments');
  await checkCollection('audit_logs');
  await checkCollection('payment_voids');
  await checkCollection('payments');
  await checkCollection('bookings');
  
  console.log('\n═══════════════════════════════════════════════════════════\n');
}

main();
