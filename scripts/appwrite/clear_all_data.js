const { Client, Databases, Query } = require('node-appwrite');

const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1';
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

if (!apiKey) {
  console.error('❌ Missing APPWRITE_API_KEY');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

const collections = [
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
  'devices',
  'sync_logs',
];

async function deleteAllDocuments(collectionId) {
  let deletedCount = 0;
  let hasMore = true;

  while (hasMore) {
    try {
      const response = await databases.listDocuments(
        databaseId,
        collectionId,
        [Query.limit(100)]
      );

      if (response.documents.length === 0) {
        hasMore = false;
        break;
      }

      for (const doc of response.documents) {
        try {
          await databases.deleteDocument(databaseId, collectionId, doc.$id);
          deletedCount++;
        } catch (e) {
          console.error(`   ❌ Failed to delete document ${doc.$id}: ${e.message}`);
        }
      }

      hasMore = response.documents.length === 100;
    } catch (error) {
      if (error?.code === 404) {
        console.log(`   ⏭️  Collection not found: ${collectionId}`);
        return 0;
      }
      console.error(`   ❌ Error listing documents: ${error.message}`);
      hasMore = false;
    }
  }

  return deletedCount;
}

async function clearAllCollections() {
  console.log('═══════════════════════════════════════');
  console.log('🗑️  حذف جميع البيانات من Appwrite');
  console.log('═══════════════════════════════════════');
  console.log(`Database: ${databaseId}`);
  console.log(`Collections: ${collections.length}`);
  console.log('═══════════════════════════════════════\n');

  let totalDeleted = 0;

  for (const collectionId of collections) {
    process.stdout.write(`📋 ${collectionId.padEnd(25)} ... `);
    const count = await deleteAllDocuments(collectionId);
    totalDeleted += count;
    console.log(`${count} documents deleted`);
  }

  console.log('\n═══════════════════════════════════════');
  console.log('📊 Summary');
  console.log('═══════════════════════════════════════');
  console.log(`Total Deleted: ${totalDeleted} documents`);
  console.log('═══════════════════════════════════════\n');

  if (totalDeleted > 0) {
    console.log('✅ All data cleared successfully!');
  } else {
    console.log('ℹ️  No data to delete.');
  }
}

clearAllCollections().catch(console.error);
