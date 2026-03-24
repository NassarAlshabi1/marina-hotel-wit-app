/**
 * اختبار شامل لجميع كيانات المزامنة التفاضلية
 * الإصدار الثاني - مطابق لبنية Appwrite الفعلية
 * 
 * غرفة الاختبار: 700 - السعر: 500 - النوع: عائلية
 */

const { Client, Databases, Query, ID } = require('node-appwrite');

// إعدادات الاتصال
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

// بيانات الغرفة للاختبار
const TEST_ROOM_NUMBER = '700';
const TEST_ROOM_PRICE = 500;
const TEST_ROOM_TYPE = 'عائلية';

// الوقت الحالي
const syncTimestamp = Math.floor(Date.now() / 1000);

// إنشاء العميل
const client = new Client();
client.setEndpoint(ENDPOINT);
client.setProject(PROJECT_ID);
client.setKey(API_KEY);

const db = new Databases(client);

// دوال مساعدة
function log(section, message, success = true) {
  const icon = success ? '✅' : '❌';
  console.log(`${icon} [${section}] ${message}`);
}

function logSection(title) {
  console.log('\n' + '═'.repeat(60));
  console.log(`📌 ${title}`);
  console.log('═'.repeat(60));
}

// نتائج الاختبار
const results = {
  success: 0,
  failed: 0,
  errors: [],
  created: {},
};

// ========================================
// 1. اختبار الغرف (Rooms)
// ========================================
async function testRoom() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'rooms',
      uuid,
      {
        roomNumber: TEST_ROOM_NUMBER,
        type: TEST_ROOM_TYPE,
        roomType: TEST_ROOM_TYPE,
        price: TEST_ROOM_PRICE,
        basePrice: TEST_ROOM_PRICE,
        status: 'available',
        floor: 7, // integer مطلوب
        bedsCount: 2,
        features: 'wifi,ac,tv', // string وليس array
        cleaningStatus: 'clean',
        requiresMaintenance: false,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('Room', `تم الإنشاء - رقم: ${doc.roomNumber} - السعر: ${doc.price} - النوع: ${doc.type}`);
    results.success++;
    results.created.room = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('Room', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'Room', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 2. اختبار الحجوزات (Bookings)
// ========================================
async function testBooking() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'bookings',
      uuid,
      {
        roomNumber: TEST_ROOM_NUMBER,
        guestName: 'أحمد محمد الاختباري',
        guestPhone: '0501234567',
        guestIdType: 'بطاقة شخصية',
        guestIdNumber: '1234567890',
        guestNationality: 'سعودي',
        checkinDate: '2026-03-22',
        checkoutDate: '2026-03-25',
        status: 'checked_in',
        expectedNights: 3,
        calculatedNights: 3,
        totalNightsCached: 3,
        totalDueCached: 1500,
        totalPaidCached: 0,
        remainingBalanceCached: 1500,
        isFullyPaid: false,
        hotelDayCheckin: '2026-03-22',
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('Booking', `تم الإنشاء - النزيل: ${doc.guestName} - الغرفة: ${doc.roomNumber}`);
    results.success++;
    results.created.booking = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('Booking', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'Booking', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 3. اختبار المدفوعات (Payments)
// ========================================
async function testPayment(bookingUuid) {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'payments',
      uuid,
      {
        roomNumber: TEST_ROOM_NUMBER,
        amount: 1000,
        paymentDate: '2026-03-22',
        paymentMethod: 'cash',
        revenueType: 'room',
        notes: 'دفعة اختبار للغرفة 700',
        bookingUuidCache: bookingUuid || uuid,
        hotelDayKey: '2026-03-22',
        isVoided: false,
        isPendingBalance: false,
        isImmutable: false,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        sync_version: 1,
        sync_vector_clock: '{}', // مطلوب
        syncTimestamp: syncTimestamp,
      }
    );
    log('Payment', `تم الإنشاء - المبلغ: ${doc.amount} - الغرفة: ${doc.roomNumber}`);
    results.success++;
    results.created.payment = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('Payment', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'Payment', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 4. اختبار المصروفات (Expenses)
// ========================================
async function testExpense() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'expenses',
      uuid,
      {
        expenseType: 'صيانة',
        description: 'إصلاح تكييف الغرفة 700',
        amount: 200,
        date: '2026-03-22',
        hotelDayKey: '2026-03-22',
        isAutoGenerated: false,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('Expense', `تم الإنشاء - المبلغ: ${doc.amount} - النوع: ${doc.expenseType}`);
    results.success++;
    results.created.expense = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('Expense', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'Expense', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 5. اختبار الديون (Debts)
// ========================================
async function testDebt() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'debts',
      uuid,
      {
        guestName: 'خالد الاختباري',
        checkinDate: '2026-03-20',
        checkoutDate: '2026-03-22',
        totalAmount: 500,
        paidAmount: 300,
        remainingAmount: 200,
        debtReason: 'تأخر في السداد',
        paymentDate: '2026-03-22',
        dateRecorded: '2026-03-22',
        isSettled: 0,
        isFromAutoFix: false,
        settlementConfirmed: false,
        debtUuid: uuid,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        sync_origin: 'test', // مطلوب للديون
        vectorClock: '{}',
        vector_clock: '{}', // مطلوب
        sync_vector_clock: '{}',
        sync_version: 1,
        syncTimestamp: syncTimestamp,
      }
    );
    log('Debt', `تم الإنشاء - المتبقي: ${doc.remainingAmount} - النزيل: ${doc.guestName}`);
    results.success++;
    results.created.debt = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('Debt', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'Debt', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 6. اختبار الموظفين (Employees)
// ========================================
async function testEmployee() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'employees',
      uuid,
      {
        name: 'محمد الموظف الاختباري',
        basicSalary: 5000,
        position: 'موظف استقبال',
        phone: '0509876543',
        hireDate: '2025-01-01',
        status: 'active',
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('Employee', `تم الإنشاء - الاسم: ${doc.name} - الراتب: ${doc.basicSalary}`);
    results.success++;
    results.created.employee = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('Employee', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'Employee', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 7. اختبار سحوبات الرواتب (Salary Withdrawals)
// ========================================
async function testSalaryWithdrawal() {
  const uuid = ID.unique();
  const testId = Date.now(); // integer ID
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'salary_withdrawals',
      uuid,
      {
        id: testId, // integer مطلوب
        employeeId: 1,
        action: 'سحب راتب',
        amount: 2500,
        note: 'سحب راتب جزئي - اختبار',
        date: '2026-03-22',
        localUuid: uuid,
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('SalaryWithdrawal', `تم الإنشاء - المبلغ: ${doc.amount} - النوع: ${doc.action}`);
    results.success++;
    results.created.salaryWithdrawal = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('SalaryWithdrawal', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'SalaryWithdrawal', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 8. اختبار تعديلات أسعار الحجوزات (Booking Price Adjustments)
// ========================================
async function testBookingPriceAdjustment(bookingUuid) {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'booking_price_adjustments',
      uuid,
      {
        bookingLocalUuid: bookingUuid || uuid,
        bookingUuid: bookingUuid || uuid,
        adjustmentType: 1,
        adjustmentMode: 'per_night',
        amount: 50,
        effectiveHotelDay: '2026-03-22',
        isActive: true,
        reason: 'خصم اختبار للغرفة 700',
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('BookingPriceAdjustment', `تم الإنشاء - المبلغ: ${doc.amount} - السبب: ${doc.reason}`);
    results.success++;
    results.created.bookingPriceAdjustment = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('BookingPriceAdjustment', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'BookingPriceAdjustment', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 9. اختبار ملاحظات الحجوزات (Booking Notes)
// ========================================
async function testBookingNote(bookingUuid) {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'booking_notes',
      uuid,
      {
        bookingId: 1,
        bookingUuid: bookingUuid || uuid,
        noteText: 'النزيل يطلب غرفة هادئة - اختبار للغرفة 700',
        note: 'النزيل يطلب غرفة هادئة - اختبار للغرفة 700', // مطلوب
        alertType: 'info',
        alertUntil: '2026-03-25',
        isActive: 1,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('BookingNote', `تم الإنشاء - النص: ${doc.noteText.substring(0, 30)}...`);
    results.success++;
    results.created.bookingNote = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('BookingNote', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'BookingNote', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 10. اختبار ملاحظات الوردية (Shift Notes)
// ========================================
async function testShiftNote() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'shift_notes',
      uuid,
      {
        title: 'تنبيه هام للوردية',
        content: 'يوجد صيانة للغرفة 700 غداً - اختبار',
        note: 'يوجد صيانة للغرفة 700 غداً - اختبار', // مطلوب
        priority: 'high',
        shiftType: 'morning',
        shiftDate: '2026-03-22', // مطلوب
        isRead: false,
        createdBy: 'admin',
        expiresAt: '2026-03-23',
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('ShiftNote', `تم الإنشاء - العنوان: ${doc.title} - الأولوية: ${doc.priority}`);
    results.success++;
    results.created.shiftNote = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('ShiftNote', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'ShiftNote', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 11. اختبار المعاملات النقدية (Cash Transactions)
// ========================================
async function testCashTransaction() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'cash_transactions',
      uuid,
      {
        transactionType: 'income',
        amount: 1500,
        referenceType: 'payment',
        referenceId: 1,
        description: 'استلام دفعة من الغرفة 700 - اختبار',
        transactionTime: '2026-03-22T10:30:00',
        registerId: 1,
        createdBy: 1,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('CashTransaction', `تم الإنشاء - المبلغ: ${doc.amount} - النوع: ${doc.transactionType}`);
    results.success++;
    results.created.cashTransaction = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('CashTransaction', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'CashTransaction', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 12. اختبار ليالي الحجز (Booking Nights)
// ========================================
async function testBookingNight() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'booking_nights',
      uuid,
      {
        bookingLocalId: 1,
        hotelDayKey: '2026-03-22',
        nightStart: '2026-03-22T14:00:00',
        nightEnd: '2026-03-23T12:00:00',
        nightlyRate: 500,
        sequence: 1,
        baseRate: 500,
        adjustment: 0,
        finalRate: 500,
        isProcessedByAutoFix: false,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('BookingNight', `تم الإنشاء - السعر: ${doc.nightlyRate} - التاريخ: ${doc.hotelDayKey}`);
    results.success++;
    results.created.bookingNight = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('BookingNight', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'BookingNight', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 13. اختبار سجل اليوم الفندقي (Hotel Day Ledger)
// ========================================
async function testHotelDayLedger() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'hotel_day_ledger',
      uuid,
      {
        hotelDayKey: '2026-03-22',
        totalIncome: 5000,
        totalExpenses: 500,
        pendingBalances: 200,
        occupancyRate: 85.5,
        bookingsProcessed: 10,
        paymentsProcessed: 8,
        debtsProcessed: 2,
        expensesProcessed: 3,
        status: 'closed',
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('HotelDayLedger', `تم الإنشاء - الدخل: ${doc.totalIncome} - المصروفات: ${doc.totalExpenses}`);
    results.success++;
    results.created.hotelDayLedger = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('HotelDayLedger', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'HotelDayLedger', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 14. اختبار دورات الرواتب (Salary Cycles)
// ========================================
async function testSalaryCycle() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'salary_cycles',
      uuid,
      {
        employeeId: 1,
        cycleKey: '2026-03',
        hotelDayStart: '2026-03-01',
        hotelDayEnd: '2026-03-31',
        startDate: '2026-03-01', // مطلوب
        endDate: '2026-03-31',
        expectedAmount: 5000,
        actualPaid: 2500,
        remainingAmount: 2500,
        basicSalary: 5000,
        netSalary: 5000,
        totalDeductions: 0,
        totalWithdrawals: 2500,
        status: 'partial',
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('SalaryCycle', `تم الإنشاء - المتوقع: ${doc.expectedAmount} - المدفوع: ${doc.actualPaid}`);
    results.success++;
    results.created.salaryCycle = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('SalaryCycle', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'SalaryCycle', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 15. اختبار مدفوعات الرواتب (Salary Payments)
// ========================================
async function testSalaryPayment() {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'salary_payments',
      uuid,
      {
        cycleId: 1,
        employeeId: 1,
        amount: 2500,
        hotelDayKey: '2026-03-22',
        paymentDateIso: '2026-03-22',
        paymentDate: '2026-03-22',
        method: 'cash',
        paymentMethod: 'cash',
        isAutoGenerated: false,
        status: 'completed',
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('SalaryPayment', `تم الإنشاء - المبلغ: ${doc.amount} - الطريقة: ${doc.method}`);
    results.success++;
    results.created.salaryPayment = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('SalaryPayment', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'SalaryPayment', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// 16. اختبار تعديلات الأسعار (Price Adjustments)
// ========================================
async function testPriceAdjustment(roomUuid) {
  const uuid = ID.unique();
  try {
    const doc = await db.createDocument(
      DATABASE_ID,
      'price_adjustments',
      uuid,
      {
        targetType: 'room',
        targetUuid: roomUuid || uuid,
        adjustmentType: 'increase',
        previousValue: 400,
        newValue: 500,
        reason: 'تحديث سعر الغرفة 700 - اختبار',
        effectiveDate: '2026-03-22',
        appliedBy: 'admin',
        hotelDayKey: '2026-03-22',
        roomNumber: TEST_ROOM_NUMBER,
        isReversed: false,
        localUuid: uuid,
        deviceId: 'test-device',
        createdAt: syncTimestamp,
        updatedAt: syncTimestamp,
        lastModified: syncTimestamp,
        version: 1,
        origin: 'test',
        vectorClock: '{}',
        syncTimestamp: syncTimestamp,
      }
    );
    log('PriceAdjustment', `تم الإنشاء - من ${doc.previousValue} إلى ${doc.newValue}`);
    results.success++;
    results.created.priceAdjustment = uuid;
    return { success: true, doc, uuid };
  } catch (error) {
    log('PriceAdjustment', `فشل: ${error.message}`, false);
    results.failed++;
    results.errors.push({ entity: 'PriceAdjustment', error: error.message });
    return { success: false, error };
  }
}

// ========================================
// تنظيف البيانات
// ========================================
async function cleanup() {
  logSection('🧹 تنظيف بيانات الاختبار');
  
  const toDelete = Object.entries(results.created).reverse();
  
  const collectionMap = {
    room: 'rooms',
    booking: 'bookings',
    payment: 'payments',
    expense: 'expenses',
    debt: 'debts',
    employee: 'employees',
    salaryWithdrawal: 'salary_withdrawals',
    bookingPriceAdjustment: 'booking_price_adjustments',
    bookingNote: 'booking_notes',
    shiftNote: 'shift_notes',
    cashTransaction: 'cash_transactions',
    bookingNight: 'booking_nights',
    hotelDayLedger: 'hotel_day_ledger',
    salaryCycle: 'salary_cycles',
    salaryPayment: 'salary_payments',
    priceAdjustment: 'price_adjustments',
  };
  
  for (const [entity, uuid] of toDelete) {
    const collection = collectionMap[entity];
    if (!collection || !uuid) continue;
    
    try {
      await db.deleteDocument(DATABASE_ID, collection, uuid);
      log('تنظيف', `تم حذف ${entity}`);
    } catch (error) {
      log('تنظيف', `فشل حذف ${entity}: ${error.message}`, false);
    }
  }
}

// ========================================
// تشغيل الاختبارات
// ========================================
async function runTests() {
  console.log('\n' + '═'.repeat(60));
  console.log('🚀 اختبار شامل لكيانات المزامنة التفاضلية');
  console.log('📅 التاريخ:', new Date().toISOString());
  console.log(`🏨 غرفة الاختبار: ${TEST_ROOM_NUMBER} - السعر: ${TEST_ROOM_PRICE} - النوع: ${TEST_ROOM_TYPE}`);
  console.log('═'.repeat(60));

  logSection('1️⃣ اختبار إنشاء المستندات');
  
  // اختبار كل كيان بالترتيب
  const roomResult = await testRoom();
  const bookingResult = await testBooking();
  await testPayment(bookingResult.uuid);
  await testExpense();
  await testDebt();
  await testEmployee();
  await testSalaryWithdrawal();
  await testBookingPriceAdjustment(bookingResult.uuid);
  await testBookingNote(bookingResult.uuid);
  await testShiftNote();
  await testCashTransaction();
  await testBookingNight();
  await testHotelDayLedger();
  await testSalaryCycle();
  await testSalaryPayment();
  await testPriceAdjustment(roomResult.uuid);

  // النتائج النهائية
  console.log('\n' + '═'.repeat(60));
  console.log('📊 النتائج النهائية');
  console.log('═'.repeat(60));
  console.log(`✅ ناجح: ${results.success}`);
  console.log(`❌ فاشل: ${results.failed}`);
  console.log(`📈 الإجمالي: 16`);
  
  if (results.errors.length > 0) {
    console.log('\n❌ الأخطاء:');
    results.errors.forEach((e, i) => {
      console.log(`  ${i + 1}. ${e.entity}: ${e.error}`);
    });
  }

  // تنظيف
  await cleanup();
  
  console.log('═'.repeat(60));
  
  if (results.failed === 0) {
    console.log('🎉 جميع الاختبارات نجحت!');
    console.log(`🏨 الغرفة ${TEST_ROOM_NUMBER} (${TEST_ROOM_TYPE}) - السعر ${TEST_ROOM_PRICE} تم اختبارها بنجاح`);
  } else {
    console.log('⚠️ بعض الاختبارات فشلت - راجع الأخطاء أعلاه');
  }
  
  process.exit(results.failed === 0 ? 0 : 1);
}

// تشغيل
runTests().catch(console.error);
