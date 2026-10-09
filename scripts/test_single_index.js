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

async function main() {
  console.log('Creating indexes one by one with 5s delay...\n');

  const indexes = [
    ['price_adjustments', 'pa_uuid_' + Date.now(), IndexType.Unique, ['localUuid']],
  ];

  for (const [coll, key, type, attrs] of indexes) {
    console.log(`Creating ${coll}.${key}...`);
    try {
      const result = await databases.createIndex(DATABASE_ID, coll, key, type, attrs);
      console.log(`✅ Created: ${key} (status: ${result.status})`);
    } catch (error) {
      console.log(`❌ Error creating ${key}:`);
      console.log(`   Code: ${error.code}`);
      console.log(`   Type: ${error.type}`);  
      console.log(`   Message: ${error.message}`);
      if (error.response) {
        console.log(`   Response: ${JSON.stringify(error.response)}`);
      }
    }
    await sleep(5000);
  }

  console.log('\nChecking collection...');
  const collection = await databases.getCollection(DATABASE_ID, 'price_adjustments');
  console.log(`Indexes in price_adjustments: ${collection.indexes.length}`);
  for (const idx of collection.indexes) {
    console.log(`  - ${idx.key}: ${idx.status} (${idx.attributes.join(', ')})`);
  }
}

main();
