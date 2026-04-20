const { Client, Databases, Query } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

async function main() {
  const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .addHeader('X-Appwrite-Key', API_KEY);

  const db = new Databases(client);

  // 1. List all rooms to find 203
  console.log('=== جلب الغرف ===');
  const rooms = await db.listDocuments(DATABASE_ID, 'rooms', [Query.limit(100)]);
  console.log('عدد الغرف:', rooms.total);
  
  let room203 = null;
  for (const room of rooms.documents) {
    const num = room.room_number || room.roomNumber || room.number || room.name || '';
    if (String(num).includes('203')) {
      room203 = room;
      break;
    }
  }
  
  if (!room203) {
    console.log('لم يتم العثور على غرفة 203');
    if (rooms.documents.length > 0) {
      console.log('أمثلة:', Object.keys(rooms.documents[0]));
    }
    return;
  }

  console.log('\n=== غرفة 203 ===');
  console.log('ID:', room203.$id);
  console.log('الحقول:', Object.keys(room203).join(', '));
  // Show all room data
  for (const [k, v] of Object.entries(room203)) {
    if (!k.startsWith('$')) console.log(`  ${k}: ${v}`);
  }

  // 2. Try different field combinations for bookings
  console.log('\n=== البحث عن حجوزات ===');
  
  const roomId = room203.$id;
  const localUuid = room203.local_uuid || '';
  const roomName = room203.name || '';
  
  // Try all possible room reference fields
  const queries = [
    ['room_id', roomId],
    ['room_id', localUuid],
    ['room_number', roomName],
    ['room_number', '203'],
  ];
  
  let foundBookings = false;
  for (const [field, value] of queries) {
    if (!value) continue;
    try {
      const bookings = await db.listDocuments(DATABASE_ID, 'bookings', [
        Query.equal(field, String(value)),
        Query.limit(20)
      ]);
      if (bookings.total > 0) {
        console.log(`\nحجوزات (${field}=${value}): ${bookings.total}`);
        for (const b of bookings.documents) {
          console.log(JSON.stringify({
            id: b.$id,
            guest: b.guest_name || b.guestName || b.name || '',
            checkin: b.check_in_date || b.checkInDate || '',
            checkout: b.check_out_date || b.checkOutDate || '',
            status: b.status || '',
            total: b.total_amount || b.totalAmount || 0,
            paid: b.amount_paid || b.amountPaid || 0,
            remaining: b.remaining_amount || b.remainingAmount || 0,
            nights: b.number_of_nights || b.numberOfNights || 0,
          }, null, 2));
        }
        foundBookings = true;
        break;
      }
    } catch (e) {
      // skip
    }
  }

  if (!foundBookings) {
    console.log('لم يتم العثور على حجوزات بالطرق المباشرة');
    console.log('\nحقول الحجز المتاحة:');
    try {
      const allBookings = await db.listDocuments(DATABASE_ID, 'bookings', [Query.limit(1)]);
      if (allBookings.documents.length > 0) {
        console.log(Object.keys(allBookings.documents[0]));
      }
    } catch(e) {
      console.log('خطأ:', e.message);
    }
  }
}

main().catch(console.error);
