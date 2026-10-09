const { Client, Databases } = require('node-appwrite');

const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1';
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

if (!apiKey) {
  console.error('❌ Missing APPWRITE_API_KEY');
  console.log('export APPWRITE_API_KEY="your-api-key"');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

const collectionsWithSyncFields = [
  'rooms',
  'bookings',
  'booking_notes',
  'booking_nights',
  'employees',
  'expenses',
  'payments',
  'debts',
  'shift_notes',
  'cash_transactions',
  'salary_cycles',
  'salary_payments',
  'hotel_day_ledger',
];

async function addIdempotencyKey() {
  console.log('🔧 Adding idempotencyKey to collections...\n');

  for (const collectionId of collectionsWithSyncFields) {
    try {
      await databases.createStringAttribute(
        databaseId,
        collectionId,
        'idempotencyKey',
        200,
        false
      );
      console.log(`✅ ${collectionId}: idempotencyKey added`);
    } catch (e) {
      if (e.code === 409) {
        console.log(`⏭️  ${collectionId}: idempotencyKey already exists`);
      } else {
        console.log(`❌ ${collectionId}: ${e.message}`);
      }
    }
  }

  console.log('\n✨ Done!');
}

addIdempotencyKey();
