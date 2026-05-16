/**
 * Comprehensive Sync Test for Marina Hotel
 * اختبار شامل للمزامنة - رفع بيانات حقيقية لجميع الجداول
 * 
 * Room 911 - Price 500 - Type: عائلية
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
    devices: 'devices',
    sync_logs: 'sync_logs',
    booking_notes: 'booking_notes',
    cash_transactions: 'cash_transactions',
    booking_nights: 'booking_nights',
    hotel_day_ledger: 'hotel_day_ledger',
    salary_cycles: 'salary_cycles',
    salary_payments: 'salary_payments',
    salary_withdrawals: 'salary_withdrawals',
    shift_notes: 'shift_notes',
    price_adjustments: 'price_adjustments',
    booking_price_adjustments: 'booking_price_adjustments',
    audit_logs: 'audit_logs',
    payment_voids: 'payment_voids',
  }
};

// Test data - بيانات اختبار حقيقية
const TEST_DATA = {
  room: {
    localUuid: 'test-room-911-' + Date.now(),
    roomNumber: '911',
    type: 'عائلية',
    price: 500.0,
    basePrice: 500.0,
    floor: '9',
    status: 'available',
    cleaningStatus: 'clean',
    requiresMaintenance: false,
    sync_version: 1,
    sync_vector_clock: '{}',
    sync_origin: 'sync_test',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  employee: {
    localUuid: 'test-employee-' + Date.now(),
    name: 'موظف اختبار المزامنة',
    basicSalary: 1500.0,
    position: 'موظف استقبال',
    phone: '07712345678',
    hireDate: new Date().toISOString().split('T')[0],
    status: 'active',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  booking: null, // Will be created after room
  payment: null, // Will be created after booking
  expense: {
    localUuid: 'test-expense-' + Date.now(),
    expenseType: 'رواتب',
    description: 'مصروف اختبار المزامنة',
    amount: 250.0,
    date: new Date().toISOString().split('T')[0],
    hotelDayKey: new Date().toISOString().split('T')[0],
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  debt: {
    localUuid: 'test-debt-' + Date.now(),
    guestName: 'نزيل اختبار المزامنة',
    checkinDate: new Date().toISOString().split('T')[0],
    checkoutDate: new Date(Date.now() + 86400000).toISOString().split('T')[0],
    dateRecorded: new Date().toISOString().split('T')[0],
    debtReason: 'اختبار المزامنة',
    totalAmount: 300.0,
    paidAmount: 100.0,
    remainingAmount: 200.0,
    paymentDate: new Date().toISOString().split('T')[0],
    isSettled: 0,
    sync_version: 1,
    sync_vector_clock: '{}',
    sync_origin: 'sync_test',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  shiftNote: {
    localUuid: 'test-shift-note-' + Date.now(),
    title: 'ملاحظة اختبار المزامنة',
    content: 'هذه ملاحظة اختبار للمزامنة الشاملة',
    note: 'هذه ملاحظة اختبار للمزامنة الشاملة',
    priority: 'high',
    shiftType: 'morning',
    shiftDate: new Date().toISOString().split('T')[0],
    isRead: 0,
    createdBy: 'sync_test',
    sync_version: 1,
    sync_vector_clock: '{}',
    sync_origin: 'sync_test',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  cashTransaction: {
    localUuid: 'test-cash-trans-' + Date.now(),
    transactionType: 'income',
    amount: 500.0,
    referenceType: 'payment',
    description: 'معاملة نقدية اختبار المزامنة',
    transactionTime: new Date().toISOString(),
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  salaryWithdrawal: {
    localUuid: 'test-salary-withdrawal-' + Date.now(),
    id: Math.floor(Math.random() * 10000),
    employeeId: 'test-employee-reference',
    action: 'سحب راتب',
    amount: 500.0,
    note: 'سحب راتب اختبار المزامنة',
    date: new Date().toISOString().split('T')[0],
    sync_version: 1,
    sync_vector_clock: '{}',
    sync_origin: 'sync_test',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  bookingPriceAdjustment: {
    localUuid: 'test-price-adj-' + Date.now(),
    bookingUuid: 'test-booking-reference',
    bookingLocalUuid: 'test-booking-reference',
    bookingLocalId: null,
    adjustmentType: 1,
    adjustmentMode: 'per_night',
    amount: 50.0,
    effectiveHotelDay: new Date().toISOString().split('T')[0],
    isActive: true,
    reason: 'تعديل سعر اختبار المزامنة',
    appliedBy: 'sync_test',
    sync_version: 1,
    sync_vector_clock: '{}',
    sync_origin: 'sync_test',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  },
  hotelDayLedger: {
    localUuid: 'test-ledger-' + Date.now(),
    hotelDayKey: new Date().toISOString().split('T')[0],
    totalIncome: 1000.0,
    totalExpenses: 200.0,
    pendingBalances: 100.0,
    occupancyRate: 75.0,
    bookingsProcessed: 5,
    paymentsProcessed: 3,
    debtsProcessed: 1,
    expensesProcessed: 2,
    status: 'finalized',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
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

// Helper functions
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

function generateUuid() {
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
    const r = Math.random() * 16 | 0;
    const v = c === 'x' ? r : (r & 0x3 | 0x8);
    return v.toString(16);
  });
}

// Test functions
async function testConnection() {
  log('اختبار الاتصال بـ Appwrite...', 'test');
  try {
    const result = await databases.listDocuments(
      CONFIG.databaseId,
      CONFIG.collections.rooms,
      [Query.limit(1)]
    );
    log('الاتصال ناجح!', 'success');
    results.passed.push('connection');
    return true;
  } catch (error) {
    log(`فشل الاتصال: ${error.message}`, 'error');
    results.failed.push({ test: 'connection', error: error.message });
    return false;
  }
}

async function createRoom() {
  log('إنشاء غرفة اختبار (911)...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.rooms,
      TEST_DATA.room.localUuid,
      TEST_DATA.room
    );
    log(`تم إنشاء الغرفة: ${doc.$id}`, 'success');
    results.created.push({ collection: 'rooms', id: doc.$id, data: TEST_DATA.room });
    return doc;
  } catch (error) {
    // Try with unique() ID if document ID conflicts
    if (error.code === 409 || error.message.includes('already exists')) {
      log('الغرفة موجودة، جاري التحديث...', 'warning');
      try {
        const doc = await databases.updateDocument(
          CONFIG.databaseId,
          CONFIG.collections.rooms,
          TEST_DATA.room.localUuid,
          { ...TEST_DATA.room, price: 500, type: 'عائلية' }
        );
        log(`تم تحديث الغرفة: ${doc.$id}`, 'success');
        results.created.push({ collection: 'rooms', id: doc.$id, data: TEST_DATA.room });
        return doc;
      } catch (updateError) {
        log(`فشل تحديث الغرفة: ${updateError.message}`, 'error');
        results.failed.push({ test: 'rooms', error: updateError.message });
        return null;
      }
    }
    log(`فشل إنشاء الغرفة: ${error.message}`, 'error');
    results.failed.push({ test: 'rooms', error: error.message });
    return null;
  }
}

async function createEmployee() {
  log('إنشاء موظف اختبار...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.employees,
      TEST_DATA.employee.localUuid,
      TEST_DATA.employee
    );
    log(`تم إنشاء الموظف: ${doc.$id}`, 'success');
    results.created.push({ collection: 'employees', id: doc.$id, data: TEST_DATA.employee });
    TEST_DATA.salaryWithdrawal.employeeLocalUuid = TEST_DATA.employee.localUuid;
    return doc;
  } catch (error) {
    log(`فشل إنشاء الموظف: ${error.message}`, 'error');
    results.failed.push({ test: 'employees', error: error.message });
    return null;
  }
}

async function createBooking(roomDoc) {
  log('إنشاء حجز اختبار...', 'test');
  const bookingData = {
    localUuid: 'test-booking-' + Date.now(),
    roomNumber: '911',
    guestName: 'نزيل اختبار المزامنة',
    guestPhone: '07798765432',
    guestIdType: 'بطاقة شخصية',
    guestIdNumber: 'A12345678',
    guestNationality: 'عراقي',
    checkinDate: new Date().toISOString().split('T')[0],
    status: 'checked_in',
    expectedNights: 3,
    calculatedNights: 3,
    hotelDayCheckin: new Date().toISOString().split('T')[0],
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  };
  
  TEST_DATA.booking = bookingData;
  
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.bookings,
      bookingData.localUuid,
      bookingData
    );
    log(`تم إنشاء الحجز: ${doc.$id}`, 'success');
    results.created.push({ collection: 'bookings', id: doc.$id, data: bookingData });
    return doc;
  } catch (error) {
    log(`فشل إنشاء الحجز: ${error.message}`, 'error');
    results.failed.push({ test: 'bookings', error: error.message });
    return null;
  }
}

async function createPayment(bookingDoc) {
  log('إنشاء دفعة اختبار...', 'test');
  const paymentData = {
    localUuid: 'test-payment-' + Date.now(),
    roomNumber: '911',
    amount: 500.0,
    paymentDate: new Date().toISOString().split('T')[0],
    paymentMethod: 'cash',
    revenueType: 'room',
    notes: 'دفعة اختبار المزامنة',
    hotelDayKey: new Date().toISOString().split('T')[0],
    bookingLocalUuid: TEST_DATA.booking?.localUuid || 'unknown',
    sync_version: 1,
    sync_vector_clock: '{}',
    sync_origin: 'sync_test',
    createdAt: Math.floor(Date.now() / 1000),
    updatedAt: Math.floor(Date.now() / 1000),
    lastModified: Math.floor(Date.now() / 1000),
    version: 1,
    origin: 'sync_test'
  };
  
  TEST_DATA.payment = paymentData;
  
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.payments,
      paymentData.localUuid,
      paymentData
    );
    log(`تم إنشاء الدفعة: ${doc.$id}`, 'success');
    results.created.push({ collection: 'payments', id: doc.$id, data: paymentData });
    return doc;
  } catch (error) {
    log(`فشل إنشاء الدفعة: ${error.message}`, 'error');
    results.failed.push({ test: 'payments', error: error.message });
    return null;
  }
}

async function createExpense() {
  log('إنشاء مصروف اختبار...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.expenses,
      TEST_DATA.expense.localUuid,
      TEST_DATA.expense
    );
    log(`تم إنشاء المصروف: ${doc.$id}`, 'success');
    results.created.push({ collection: 'expenses', id: doc.$id, data: TEST_DATA.expense });
    return doc;
  } catch (error) {
    log(`فشل إنشاء المصروف: ${error.message}`, 'error');
    results.failed.push({ test: 'expenses', error: error.message });
    return null;
  }
}

async function createDebt() {
  log('إنشاء دين اختبار...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.debts,
      TEST_DATA.debt.localUuid,
      TEST_DATA.debt
    );
    log(`تم إنشاء الدين: ${doc.$id}`, 'success');
    results.created.push({ collection: 'debts', id: doc.$id, data: TEST_DATA.debt });
    return doc;
  } catch (error) {
    log(`فشل إنشاء الدين: ${error.message}`, 'error');
    results.failed.push({ test: 'debts', error: error.message });
    return null;
  }
}

async function createShiftNote() {
  log('إنشاء ملاحظة ورديات اختبار...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.shift_notes,
      TEST_DATA.shiftNote.localUuid,
      TEST_DATA.shiftNote
    );
    log(`تم إنشاء ملاحظة الورديات: ${doc.$id}`, 'success');
    results.created.push({ collection: 'shift_notes', id: doc.$id, data: TEST_DATA.shiftNote });
    return doc;
  } catch (error) {
    log(`فشل إنشاء ملاحظة الورديات: ${error.message}`, 'error');
    results.failed.push({ test: 'shift_notes', error: error.message });
    return null;
  }
}

async function createCashTransaction() {
  log('إنشاء معاملة نقدية اختبار...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.cash_transactions,
      TEST_DATA.cashTransaction.localUuid,
      TEST_DATA.cashTransaction
    );
    log(`تم إنشاء المعاملة النقدية: ${doc.$id}`, 'success');
    results.created.push({ collection: 'cash_transactions', id: doc.$id, data: TEST_DATA.cashTransaction });
    return doc;
  } catch (error) {
    log(`فشل إنشاء المعاملة النقدية: ${error.message}`, 'error');
    results.failed.push({ test: 'cash_transactions', error: error.message });
    return null;
  }
}

async function createSalaryWithdrawal() {
  log('إنشاء سحب راتب اختبار (salary_withdrawals)...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.salary_withdrawals,
      TEST_DATA.salaryWithdrawal.localUuid,
      TEST_DATA.salaryWithdrawal
    );
    log(`تم إنشاء سحب الراتب: ${doc.$id}`, 'success');
    results.created.push({ collection: 'salary_withdrawals', id: doc.$id, data: TEST_DATA.salaryWithdrawal });
    return doc;
  } catch (error) {
    log(`فشل إنشاء سحب الراتب: ${error.message}`, 'error');
    results.failed.push({ test: 'salary_withdrawals', error: error.message });
    results.errors.push({ collection: 'salary_withdrawals', error: error.message, code: error.code });
    return null;
  }
}

async function createBookingPriceAdjustment() {
  log('إنشاء تعديل سعر حجز اختبار (booking_price_adjustments)...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.booking_price_adjustments,
      TEST_DATA.bookingPriceAdjustment.localUuid,
      TEST_DATA.bookingPriceAdjustment
    );
    log(`تم إنشاء تعديل السعر: ${doc.$id}`, 'success');
    results.created.push({ collection: 'booking_price_adjustments', id: doc.$id, data: TEST_DATA.bookingPriceAdjustment });
    return doc;
  } catch (error) {
    log(`فشل إنشاء تعديل السعر: ${error.message}`, 'error');
    results.failed.push({ test: 'booking_price_adjustments', error: error.message });
    results.errors.push({ collection: 'booking_price_adjustments', error: error.message, code: error.code });
    return null;
  }
}

async function createHotelDayLedger() {
  log('إنشاء سجل يوم الفندق اختبار...', 'test');
  try {
    const doc = await databases.createDocument(
      CONFIG.databaseId,
      CONFIG.collections.hotel_day_ledger,
      TEST_DATA.hotelDayLedger.localUuid,
      TEST_DATA.hotelDayLedger
    );
    log(`تم إنشاء سجل اليوم: ${doc.$id}`, 'success');
    results.created.push({ collection: 'hotel_day_ledger', id: doc.$id, data: TEST_DATA.hotelDayLedger });
    return doc;
  } catch (error) {
    log(`فشل إنشاء سجل اليوم: ${error.message}`, 'error');
    results.failed.push({ test: 'hotel_day_ledger', error: error.message });
    return null;
  }
}

async function verifyDocuments() {
  log('التحقق من المستندات المنشأة...', 'test');
  const verificationResults = [];
  
  for (const item of results.created) {
    try {
      const doc = await databases.getDocument(
        CONFIG.databaseId,
        item.collection,
        item.id
      );
      verificationResults.push({
        collection: item.collection,
        id: item.id,
        verified: true,
        data: doc
      });
      log(`✓ تم التحقق من ${item.collection}/${item.id}`, 'success');
    } catch (error) {
      verificationResults.push({
        collection: item.collection,
        id: item.id,
        verified: false,
        error: error.message
      });
      log(`✗ فشل التحقق من ${item.collection}/${item.id}: ${error.message}`, 'error');
    }
  }
  
  return verificationResults;
}

async function testReadOperations() {
  log('اختبار عمليات القراءة...', 'test');
  const readTests = [];
  
  const collections = [
    { name: 'rooms', id: CONFIG.collections.rooms },
    { name: 'bookings', id: CONFIG.collections.bookings },
    { name: 'payments', id: CONFIG.collections.payments },
    { name: 'expenses', id: CONFIG.collections.expenses },
    { name: 'employees', id: CONFIG.collections.employees },
    { name: 'debts', id: CONFIG.collections.debts },
    { name: 'salary_withdrawals', id: CONFIG.collections.salary_withdrawals },
    { name: 'booking_price_adjustments', id: CONFIG.collections.booking_price_adjustments },
  ];
  
  for (const coll of collections) {
    try {
      const result = await databases.listDocuments(
        CONFIG.databaseId,
        coll.id,
        [Query.limit(5)]
      );
      readTests.push({
        collection: coll.name,
        success: true,
        count: result.total
      });
      log(`✓ قراءة ${coll.name}: ${result.total} مستند`, 'success');
    } catch (error) {
      readTests.push({
        collection: coll.name,
        success: false,
        error: error.message
      });
      log(`✗ فشل قراءة ${coll.name}: ${error.message}`, 'error');
    }
  }
  
  return readTests;
}

async function main() {
  console.log('\n' + '='.repeat(60));
  console.log('🧪 COMPREHENSIVE SYNC TEST - Marina Hotel');
  console.log('اختبار شامل للمزامنة - فندق مارينا');
  console.log('Room 911 | Price 500 | Type: عائلية');
  console.log('='.repeat(60) + '\n');

  // Step 1: Test connection
  const connected = await testConnection();
  if (!connected) {
    log('لا يمكن المتابعة بدون اتصال', 'error');
    return;
  }

  // Step 2: Create all test documents
  console.log('\n--- إنشاء المستندات ---\n');
  
  const roomDoc = await createRoom();
  const employeeDoc = await createEmployee();
  const bookingDoc = await createBooking(roomDoc);
  const paymentDoc = await createPayment(bookingDoc);
  const expenseDoc = await createExpense();
  const debtDoc = await createDebt();
  const shiftNoteDoc = await createShiftNote();
  const cashTransDoc = await createCashTransaction();
  const salaryWithdrawalDoc = await createSalaryWithdrawal();
  const priceAdjustmentDoc = await createBookingPriceAdjustment();
  const ledgerDoc = await createHotelDayLedger();

  // Step 3: Verify all created documents
  console.log('\n--- التحقق من المستندات ---\n');
  const verificationResults = await verifyDocuments();

  // Step 4: Test read operations
  console.log('\n--- اختبار القراءة ---\n');
  const readResults = await testReadOperations();

  // Final Report
  console.log('\n' + '='.repeat(60));
  console.log('📊 تقرير الاختبار النهائي');
  console.log('='.repeat(60));
  console.log(`\n✅ ناجح: ${results.passed.length + results.created.length}`);
  console.log(`❌ فاشل: ${results.failed.length}`);
  console.log(`📝 مستندات منشأة: ${results.created.length}`);
  console.log(`🔍 تم التحقق من: ${verificationResults.filter(r => r.verified).length}`);
  
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

  if (results.failed.length > 0) {
    console.log('\n❌ الاختبارات الفاشلة:');
    results.failed.forEach(item => {
      console.log(`  ✗ ${item.test}: ${item.error}`);
    });
  }

  // Check for collections that need to be created
  const missingCollections = results.failed.filter(f => 
    f.error && (f.error.includes('Collection not found') || f.error.includes('404'))
  );
  
  if (missingCollections.length > 0) {
    console.log('\n🚧 المجموعات المفقودة التي تحتاج إنشاء في Appwrite:');
    missingCollections.forEach(item => {
      console.log(`  - ${item.test}`);
    });
  }

  console.log('\n' + '='.repeat(60));
  console.log('انتهى الاختبار');
  console.log('='.repeat(60) + '\n');
  
  // Return results for programmatic use
  return {
    success: results.failed.length === 0,
    passed: results.passed,
    failed: results.failed,
    created: results.created,
    verified: verificationResults,
    readTests: readResults,
    errors: results.errors,
    testData: TEST_DATA
  };
}

// Run the test
main()
  .then(results => {
    process.exit(results.success ? 0 : 1);
  })
  .catch(error => {
    console.error('Fatal error:', error);
    process.exit(1);
  });
