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

async function testIndex() {
  console.log('Testing single index creation...\n');
  
  try {
    const result = await databases.createIndex(
      DATABASE_ID,
      'price_adjustments',
      'idx_test_' + Date.now(),
      IndexType.Key,
      ['hotelDayKey']
    );
    console.log('✅ Success:', JSON.stringify(result, null, 2));
  } catch (error) {
    console.log('❌ Error details:');
    console.log('   Code:', error.code);
    console.log('   Type:', error.type);
    console.log('   Message:', error.message);
    console.log('   Response:', error.response);
    console.log('   Full error:', JSON.stringify(error, null, 2));
  }
}

testIndex();
