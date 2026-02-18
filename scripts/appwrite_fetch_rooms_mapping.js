const sdk = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const COLLECTION_ID = 'rooms';

async function fetchRoomsMapping() {
  const apiKey = process.env.APPWRITE_API_KEY;
  
  if (!apiKey) {
    console.error('❌ APPWRITE_API_KEY environment variable is required');
    process.exit(1);
  }

  console.log('🔧 Initializing Appwrite client...');
  const client = new sdk.Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(apiKey);

  const databases = new sdk.Databases(client);

  console.log(`\n📋 Configuration:`);
  console.log(`   Endpoint: ${ENDPOINT}`);
  console.log(`   Project: ${PROJECT_ID}`);
  console.log(`   Database: ${DATABASE_ID}`);
  console.log(`   Collection: ${COLLECTION_ID}`);

  try {
    console.log('\n🔍 Fetching all rooms from Appwrite...\n');
    
    let allDocuments = [];
    let offset = 0;
    const limit = 100;
    
    while (true) {
      const response = await databases.listDocuments(
        DATABASE_ID,
        COLLECTION_ID,
        [
          sdk.Query.limit(limit),
          sdk.Query.offset(offset)
        ]
      );

      allDocuments = allDocuments.concat(response.documents);
      console.log(`   Fetched ${response.documents.length} documents (offset: ${offset})`);
      
      if (response.documents.length < limit) {
        break;
      }
      offset += limit;
    }

    console.log(`\n✅ Total documents found: ${allDocuments.length}`);

    const mapping = allDocuments.map(doc => ({
      localUuid: doc.localUuid,
      serverId: doc.$id,
      roomNumber: doc.roomNumber,
      type: doc.type,
      price: doc.price
    }));

    const mappingFile = '/home/marina-hotel-wit-app/scripts/rooms_mapping.json';
    const fs = require('fs');
    fs.writeFileSync(mappingFile, JSON.stringify(mapping, null, 2));
    console.log(`\n📄 Mapping saved to: ${mappingFile}`);

    console.log('\n📊 Sample Mapping:');
    mapping.slice(0, 3).forEach(m => {
      console.log(`   ${m.roomNumber} → ${m.serverId.substring(0, 12)}...`);
    });

    const sqlFile = '/home/marina-hotel-wit-app/scripts/update_rooms_server_ids.sql';
    const sqlStatements = mapping.map(m => 
      `UPDATE rooms SET serverId = '${m.serverId}' WHERE localUuid = '${m.localUuid}';`
    ).join('\n');
    
    fs.writeFileSync(sqlFile, sqlStatements);
    console.log(`\n📝 SQL update script saved to: ${sqlFile}`);

    console.log('\n✅ Mapping extraction completed!\n');
    console.log('🔄 Next steps:');
    console.log('   1. Review rooms_mapping.json');
    console.log('   2. Execute update_rooms_server_ids.sql on local database');
    console.log('   3. Test sync again - 404 errors should be gone\n');

  } catch (error) {
    console.error('❌ Error:', error.message);
    console.error(error);
    process.exit(1);
  }
}

fetchRoomsMapping().catch(console.error);
