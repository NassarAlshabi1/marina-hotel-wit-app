const sdk = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const COLLECTION_ID = 'rooms';

const ROOMS_DATA = [
  {"localUuid":"82f73ed9-7c51-4696-93a8-c3fa753725f7","roomNumber":"103","type":"سرير عائلي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1763073112,"updatedAt":1769558075},
  {"localUuid":"6f10eef5-f834-4415-9db3-2d9d6791ce14","roomNumber":"101","type":"سرير عائلي","price":14000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1764797304,"updatedAt":1769558072},
  {"localUuid":"fedc0bce-4b4f-48b2-87d2-e5a9a3a12168","roomNumber":"203","type":"سرير عائلي","price":20000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1763073187,"updatedAt":1769474110},
  {"localUuid":"23294cb8-f317-42c5-ab80-b3adc4c89b25","roomNumber":"402","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1763073317,"updatedAt":1769474246},
  {"localUuid":"e4d01db4-b6fd-4e6d-bcdc-80b5377a4a9b","roomNumber":"302","type":"سرير فردي","price":14300,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1763073233,"updatedAt":1769474232},
  {"localUuid":"1bb8f3de-a3e7-4b2b-baa3-ebea289dda8f","roomNumber":"501","type":"سرير فردي","price":6000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"google_drive_delta","version":1000,"createdAt":1763073372000,"updatedAt":1769558068},
  {"localUuid":"cc95aada-bd9f-4dc8-a3ed-a63b66c06d96","roomNumber":"102","type":"سرير عائلي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769641975,"updatedAt":1769641975},
  {"localUuid":"ad485411-9a2e-4aa0-b571-a245e9932ef3","roomNumber":"104","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642189,"updatedAt":1769642189},
  {"localUuid":"6e723b44-79d9-4bff-b9c4-e4a72996a9c6","roomNumber":"201","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642208,"updatedAt":1769642208},
  {"localUuid":"598fbc3f-4ca4-4818-9c0f-303c00c83750","roomNumber":"202","type":"سرير عائلي","price":10000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642234,"updatedAt":1769642234},
  {"localUuid":"cf47209b-7220-49f0-b8a3-b159e25db887","roomNumber":"204","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642267,"updatedAt":1769642267},
  {"localUuid":"5d2beb07-5253-46b3-a407-e74dc0eec880","roomNumber":"301","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642287,"updatedAt":1769642287},
  {"localUuid":"7ebe6dd7-0644-4e3a-bc79-cd081f1757a6","roomNumber":"303","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642317,"updatedAt":1769642317},
  {"localUuid":"ce686a8e-7e9b-452a-9908-7dbc8235b748","roomNumber":"304","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642335,"updatedAt":1769642335},
  {"localUuid":"c46defab-a53d-4366-832d-d85ced1f22fb","roomNumber":"401","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642371,"updatedAt":1769642371},
  {"localUuid":"9b7f6abb-af0c-4a92-a7f1-9d8ebadfc956","roomNumber":"403","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642393,"updatedAt":1769642393},
  {"localUuid":"7a82b56a-57a7-4032-8f8b-87a67f8f2186","roomNumber":"404","type":"سرير فردي","price":15000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642407,"updatedAt":1769642407},
  {"localUuid":"20acc60c-4d0b-4728-b010-9e8328c39587","roomNumber":"502","type":"سرير فردي","price":10000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642430,"updatedAt":1769642430},
  {"localUuid":"a68ffc2a-c9d8-4ecd-87ec-65ddc8acd8f1","roomNumber":"503","type":"سرير فردي","price":10000,"status":"شاغرة","imageUrl":null,"cleaningStatus":"clean","lastCleanedHotelDay":null,"lastOccupiedHotelDay":null,"requiresMaintenance":false,"origin":"local","version":1,"createdAt":1769642450,"updatedAt":1769642450}
];

async function importRooms() {
  const apiKey = process.env.APPWRITE_API_KEY;
  
  if (!apiKey) {
    console.error('❌ APPWRITE_API_KEY environment variable is required');
    console.log('\nUsage:');
    console.log('  APPWRITE_API_KEY=your_key node scripts/appwrite_import_rooms.js');
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
  console.log(`   Total Rooms: ${ROOMS_DATA.length}`);

  const mapping = [];
  const errors = [];
  let successCount = 0;

  console.log('\n🚀 Starting import...\n');

  for (let i = 0; i < ROOMS_DATA.length; i++) {
    const room = ROOMS_DATA[i];
    try {
      console.log(`[${i + 1}/${ROOMS_DATA.length}] Creating room ${room.roomNumber}...`);

      const roomData = {
        ...room,
        lastModified: room.updatedAt || room.createdAt || Date.now()
      };

      const document = await databases.createDocument(
        DATABASE_ID,
        COLLECTION_ID,
        sdk.ID.unique(),
        roomData
      );

      mapping.push({
        localUuid: room.localUuid,
        serverId: document.$id,
        roomNumber: room.roomNumber
      });

      successCount++;
      console.log(`   ✅ Created: ${room.roomNumber} → serverId: ${document.$id}`);
    } catch (error) {
      errors.push({
        localUuid: room.localUuid,
        roomNumber: room.roomNumber,
        error: error.message || error.toString()
      });
      console.error(`   ❌ Failed: ${room.roomNumber} - ${error.message}`);
    }
  }

  console.log('\n' + '='.repeat(60));
  console.log(`✅ Success: ${successCount}/${ROOMS_DATA.length}`);
  console.log(`❌ Failed: ${errors.length}/${ROOMS_DATA.length}`);
  console.log('='.repeat(60));

  if (mapping.length > 0) {
    const mappingFile = '/home/marina-hotel-wit-app/scripts/rooms_mapping.json';
    const fs = require('fs');
    fs.writeFileSync(mappingFile, JSON.stringify(mapping, null, 2));
    console.log(`\n📄 Mapping saved to: ${mappingFile}`);
  }

  if (errors.length > 0) {
    const errorsFile = '/home/marina-hotel-wit-app/scripts/rooms_import_errors.json';
    const fs = require('fs');
    fs.writeFileSync(errorsFile, JSON.stringify(errors, null, 2));
    console.log(`⚠️  Errors saved to: ${errorsFile}`);
  }

  console.log('\n✅ Import completed!\n');
  
  if (successCount === ROOMS_DATA.length) {
    console.log('🎉 All rooms imported successfully!');
  }
}

importRooms().catch(console.error);
