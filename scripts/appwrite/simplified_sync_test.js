/**
 * Simplified Sync Test for Marina Hotel
 * اختبار مبسط للمزامنة
 */

const { Client, Databases, ID, Query } = require('node-appwrite');

// Configuration
const CONFIG = {
  endpoint: 'https://fra.cloud.appwrite.io/v1',
  projectId: '690ff0da0025518570c1',
  databaseId: 'hotel_db',
  collections: {
    rooms: 'rooms',
    bookings: 'bookings',
    payments: 'payments',
    expenses: 'expenses',
    employees: 'employees',
    debts: 'debts',
    salary_withdrawals: 'salary_withdrawals',
    booking_price_adjustments: 'booking_price_adjustments',
  }
};

// Initialize client
const client = new Client()
  .setEndpoint(CONFIG.endpoint)
  .setProject(CONFIG.projectId);

const databases = new Databases(client);

// Results tracking
const results = {
  passed: [],
  failed: [],
  created: [],
  errors: []
};

function log(message, type = 'info') {
  const timestamp = new Date().toISOString();
  const prefix = {
    info: '📘',
    success: '✅',
    error: '❌',
    warning: '⚠️',
    test: '🧪'
  }[type] || '📘';
  console.log(`${prefix} [${timestamp}] ${message}`);
}

// Test creating a room with minimal required fields
async function testRoomCreation() {
  log('اختبار إنشاء غرفة 911...', 'test');
  const timestamp = Date.now();
  const roomData = {
    roomNumber: '911',
    type: 'عائلية',
    price: 500.0,
    basePrice: 500.0,
    floor: 9,
    status: 'available',
    localUuid: `test-room-911-${timestamp}`,
    createdAt: Math.floor(timestamp / 1000),
    updatedAt: Math.floor(timestamp / 1000),
    lastModified: Math.floor(timestamp / 1000),
    version: 1,
    origin: 'sync_test'
  };

  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.rooms,
      roomData.localUuid,
      roomData
    );
    log(`✓ تم إنشاء الغرفة 911: ${doc.$id}`, 'success');
    results.created.push({ collection: 'rooms', id: doc.$id });
    return doc;
  } catch (error) {
    log(`✗ فشل إنشاء الغرفة: ${error.message}`, 'error');
    results.failed.push({ test: 'rooms', error: error.message });
    return null;
  }
}

// Test salary_withdrawals
async function testSalaryWithdrawal() {
  log('اختبار salary_withdrawals...', 'test');
  const timestamp = Date.now();
  const data = {
    localUuid: `test-salary-withdrawal-${timestamp}`,
    id: Math.floor(Math.random() * 100000),
    employeeId: Math.floor(Math.random() * 10000),
    action: 'سحب راتب',
    amount: 500.0,
    note: 'اختبار المزامنة',
    date: new Date().toISOString().split('T')[0],
    vectorClock: '{}',
    createdAt: Math.floor(timestamp / 1000),
    updatedAt: Math.floor(timestamp / 1000),
    lastModified: Math.floor(timestamp / 1000),
    version: 1,
    origin: 'sync_test'
  };

  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.salary_withdrawals,
      data.localUuid,
      data
    );
    log(`✓ تم إنشاء سحب الراتب: ${doc.$id}`, 'success');
    results.created.push({ collection: 'salary_withdrawals', id: doc.$id });
    return doc;
  } catch (error) {
    log(`✗ فشل إنشاء سحب الراتب: ${error.message}`, 'error');
    results.failed.push({ test: 'salary_withdrawals', error: error.message });
    results.errors.push({ collection: 'salary_withdrawals', error: error.message });
    return null;
  }
}

// Test booking_price_adjustments
async function testBookingPriceAdjustment() {
  log('اختبار booking_price_adjustments...', 'test');
  const timestamp = Date.now();
  const data = {
    localUuid: `test-price-adj-${timestamp}`,
    bookingLocalUuid: `test-booking-${timestamp}`,
    bookingUuid: `test-booking-${timestamp}`,
    adjustmentType: 1,
    adjustmentMode: 'per_night',
    amount: 50.0,
    effectiveHotelDay: new Date().toISOString().split('T')[0],
    isActive: true,
    reason: 'اختبار المزامنة',
    appliedBy: 'sync_test',
    vectorClock: '{}',
    createdAt: Math.floor(timestamp / 1000),
    updatedAt: Math.floor(timestamp / 1000),
    lastModified: Math.floor(timestamp / 1000),
    version: 1,
    origin: 'sync_test'
  };

  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.booking_price_adjustments,
      data.localUuid,
      data
    );
    log(`✓ تم إنشاء تعديل السعر: ${doc.$id}`, 'success');
    results.created.push({ collection: 'booking_price_adjustments', id: doc.$id });
    return doc;
  } catch (error) {
    log(`✗ فشل إنشاء تعديل السعر: ${error.message}`, 'error');
    results.failed.push({ test: 'booking_price_adjustments', error: error.message });
    results.errors.push({ collection: 'booking_price_adjustments', error: error.message });
    return null;
  }
}

// Test reading all collections
async function testReadOperations() {
  log('اختبار عمليات القراءة...', 'test');
  const collections = Object.entries(CONFIG.collections);
  
  for (const [name, id] of collections) {
    try {
      const result = await databases.listDocuments(
        CONFIG.databaseId,
        id,
        [Query.limit(5)]
      );
      log(`✓ ${name}: ${result.total} مستند`, 'success');
      results.passed.push({ collection: name, count: result.total });
    } catch (error) {
      log(`✗ ${name}: ${error.message}`, 'error');
      results.failed.push({ test: `read_${name}`, error: error.message });
    }
  }
}

// Main test function
async function main() {
  console.log('\n' + '='.repeat(60));
  console.log('🧪 SIMPLIFIED SYNC TEST - Marina Hotel');
  console.log('Room 911 | Price 500 | Type: عائلية');
  console.log('='.repeat(60) + '\n');

  // Test read operations first
  await testReadOperations();

  console.log('\n--- اختبار الكتابة ---\n');

  // Test write operations
  await testRoomCreation();
  await testSalaryWithdrawal();
  await testBookingPriceAdjustment();

  // Final Report
  console.log('\n' + '='.repeat(60));
  console.log('📊 التقرير النهائي');
  console.log('='.repeat(60));
  console.log(`\n✅ ناجح: ${results.passed.length}`);
  console.log(`❌ فاشل: ${results.failed.length}`);
  console.log(`📝 مستندات منشأة: ${results.created.length}`);

  if (results.errors.length > 0) {
    console.log('\n⚠️ أخطاء تحتاج إصلاح:');
    results.errors.forEach(err => {
      console.log(`  - ${err.collection}: ${err.error}`);
    });
  }

  console.log('\n📋 المستندات المنشأة:');
  results.created.forEach(item => {
    console.log(`  ✓ ${item.collection}: ${item.id}`);
  });

  // Return results
  return {
    success: results.failed.length === 0,
    results
  };
}

main()
  .then(r => process.exit(r.success ? 0 : 1))
  .catch(e => {
    console.error('Fatal error:', e);
    process.exit(1);
  });
