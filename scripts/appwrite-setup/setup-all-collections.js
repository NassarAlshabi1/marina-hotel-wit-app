/**
 * سكريبت شامل لحذف المجموعات القديمة وإنشاء المجموعات والحقول الصحيحة
 * في Appwrite Cloud بناءً على هيكل local_db.dart
 * 
 * التشغيل: node setup-all-collections.js
 */

const { Client, Databases } = require('node-appwrite');

// ═══════════════════════════════════════════════════════════════
// إعدادات الاتصال
// ═══════════════════════════════════════════════════════════════
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6a2b01d0000752ce97e7';
const DATABASE_ID = '6a2b030d000445596163';
const API_KEY = 'standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d';

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const db = new Databases(client);

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

// ═══════════════════════════════════════════════════════════════
// حقول SyncFields المشتركة
// ═══════════════════════════════════════════════════════════════
const SYNC_FIELDS = [
  { key: 'localUuid', type: 'string', size: 64, required: true },
  { key: 'serverId', type: 'integer', required: false },
  { key: 'createdAt', type: 'integer', required: true },
  { key: 'updatedAt', type: 'integer', required: true },
  { key: 'deletedAt', type: 'integer', required: false },
  { key: 'lastModified', type: 'integer', required: true },
  { key: 'createdAtIso', type: 'string', size: 50, required: false },
  { key: 'updatedAtIso', type: 'string', size: 50, required: false },
  { key: 'deletedAtIso', type: 'string', size: 50, required: false },
  { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
  { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
  { key: 'version', type: 'integer', required: false, default: 1 },
  { key: 'origin', type: 'string', size: 50, required: false, default: 'local' },
  { key: 'vectorClock', type: 'string', size: 1024, required: false, default: '{}' },
  { key: 'deviceId', type: 'string', size: 128, required: false },
];

// ═══════════════════════════════════════════════════════════════
// جميع المجموعات مع حقولها
// ═══════════════════════════════════════════════════════════════
const COLLECTIONS = {
  rooms: {
    hasSyncFields: true,
    fields: [
      { key: 'roomNumber', type: 'string', size: 20, required: true },
      { key: 'type', type: 'string', size: 100, required: true },
      { key: 'price', type: 'double', required: true },
      { key: 'status', type: 'string', size: 50, required: true },
      { key: 'imageUrl', type: 'string', size: 2048, required: false },
      { key: 'cleaningStatus', type: 'string', size: 50, required: false, default: 'clean' },
      { key: 'lastCleanedHotelDay', type: 'string', size: 50, required: false },
      { key: 'lastOccupiedHotelDay', type: 'string', size: 50, required: false },
      { key: 'requiresMaintenance', type: 'boolean', required: false, default: false },
    ],
  },

  bookings: {
    hasSyncFields: true,
    fields: [
      { key: 'serverBookingId', type: 'integer', required: false },
      { key: 'roomNumber', type: 'string', size: 20, required: true },
      { key: 'guestName', type: 'string', size: 255, required: true },
      { key: 'guestPhone', type: 'string', size: 50, required: true },
      { key: 'guestIdType', type: 'string', size: 100, required: false, default: '\u0628\u0637\u0627\u0642\u0629 \u0634\u062e\u0635\u064a\u0629' },
      { key: 'guestIdNumber', type: 'string', size: 100, required: false, default: '' },
      { key: 'guestIdIssueDate', type: 'string', size: 50, required: false },
      { key: 'guestIdIssuePlace', type: 'string', size: 255, required: false },
      { key: 'guestNationality', type: 'string', size: 100, required: true },
      { key: 'guestEmail', type: 'string', size: 255, required: false },
      { key: 'guestAddress', type: 'string', size: 512, required: false },
      { key: 'checkinDate', type: 'string', size: 50, required: true },
      { key: 'checkoutDate', type: 'string', size: 50, required: false },
      { key: 'actualCheckout', type: 'string', size: 50, required: false },
      { key: 'status', type: 'string', size: 50, required: true },
      { key: 'notes', type: 'string', size: 4096, required: false },
      { key: 'discount', type: 'double', required: false, default: 0 },
      { key: 'discountType', type: 'string', size: 50, required: false, default: 'per_night' },
      { key: 'discountStartDate', type: 'string', size: 50, required: false },
      { key: 'expectedNights', type: 'integer', required: false, default: 1 },
      { key: 'calculatedNights', type: 'integer', required: false, default: 1 },
      { key: 'totalNightsCached', type: 'integer', required: false, default: 0 },
      { key: 'stayDurationIso', type: 'string', size: 50, required: false },
      { key: 'lastNightEpoch', type: 'integer', required: false },
      { key: 'isOverdue', type: 'boolean', required: false, default: false },
      { key: 'needsCheckoutReview', type: 'boolean', required: false, default: false },
      { key: 'totalDueCached', type: 'double', required: false, default: 0.0 },
      { key: 'totalPaidCached', type: 'double', required: false, default: 0.0 },
      { key: 'remainingBalanceCached', type: 'double', required: false, default: 0.0 },
      { key: 'isFullyPaid', type: 'boolean', required: false, default: false },
      { key: 'hotelDayCheckin', type: 'string', size: 50, required: false },
      { key: 'hotelDayCheckout', type: 'string', size: 50, required: false },
    ],
  },

  booking_notes: {
    hasSyncFields: true,
    fields: [
      { key: 'bookingId', type: 'integer', required: true },
      { key: 'noteText', type: 'string', size: 4096, required: true },
      { key: 'alertType', type: 'string', size: 50, required: true },
      { key: 'alertUntil', type: 'string', size: 50, required: false },
      { key: 'isActive', type: 'integer', required: false, default: 1 },
    ],
  },

  employees: {
    hasSyncFields: true,
    fields: [
      { key: 'name', type: 'string', size: 255, required: true },
      { key: 'basicSalary', type: 'double', required: true },
      { key: 'position', type: 'string', size: 100, required: false, default: '\u0645\u0648\u0638\u0641' },
      { key: 'phone', type: 'string', size: 50, required: false, default: '' },
      { key: 'hireDate', type: 'string', size: 50, required: false, default: '' },
      { key: 'status', type: 'string', size: 50, required: true },
      { key: 'terminationDate', type: 'string', size: 50, required: false },
      { key: 'terminationReason', type: 'string', size: 512, required: false },
    ],
  },

  expenses: {
    hasSyncFields: true,
    fields: [
      { key: 'expenseType', type: 'string', size: 100, required: true },
      { key: 'relatedId', type: 'integer', required: false },
      { key: 'description', type: 'string', size: 1024, required: true },
      { key: 'amount', type: 'double', required: true },
      { key: 'date', type: 'string', size: 50, required: true },
      { key: 'cashTransactionId', type: 'integer', required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
      { key: 'categoryUuid', type: 'string', size: 64, required: false },
      { key: 'cashFlowUuid', type: 'string', size: 64, required: false },
      { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
    ],
  },

  cash_transactions: {
    hasSyncFields: true,
    fields: [
      { key: 'registerId', type: 'integer', required: false },
      { key: 'transactionType', type: 'string', size: 50, required: true },
      { key: 'amount', type: 'double', required: true },
      { key: 'referenceType', type: 'string', size: 100, required: false },
      { key: 'referenceId', type: 'integer', required: false },
      { key: 'description', type: 'string', size: 1024, required: false },
      { key: 'transactionTime', type: 'string', size: 50, required: true },
      { key: 'createdBy', type: 'integer', required: false },
    ],
  },

  payments: {
    hasSyncFields: true,
    fields: [
      { key: 'serverPaymentId', type: 'integer', required: false },
      { key: 'bookingLocalId', type: 'integer', required: false },
      { key: 'serverBookingId', type: 'integer', required: false },
      { key: 'roomNumber', type: 'string', size: 20, required: false },
      { key: 'amount', type: 'double', required: true },
      { key: 'paymentDate', type: 'string', size: 50, required: true },
      { key: 'notes', type: 'string', size: 4096, required: false },
      { key: 'paymentMethod', type: 'string', size: 50, required: true },
      { key: 'revenueType', type: 'string', size: 50, required: true },
      { key: 'cashTransactionLocalId', type: 'integer', required: false },
      { key: 'cashTransactionServerId', type: 'integer', required: false },
      { key: 'referenceNumber', type: 'string', size: 100, required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
      { key: 'isPendingBalance', type: 'boolean', required: false, default: false },
      { key: 'linkedDebtUuid', type: 'string', size: 64, required: false },
      { key: 'bookingUuidCache', type: 'string', size: 64, required: false },
      { key: 'discountAmount', type: 'double', required: false },
      { key: 'discountStartDate', type: 'string', size: 50, required: false },
      { key: 'isVoided', type: 'boolean', required: false, default: false },
      { key: 'voidedAt', type: 'integer', required: false },
      { key: 'voidedBy', type: 'string', size: 128, required: false },
    ],
  },

  debts: {
    hasSyncFields: true,
    fields: [
      { key: 'bookingLocalId', type: 'integer', required: false },
      { key: 'guestName', type: 'string', size: 255, required: true },
      { key: 'checkinDate', type: 'string', size: 50, required: true },
      { key: 'checkoutDate', type: 'string', size: 50, required: true },
      { key: 'dateRecorded', type: 'string', size: 50, required: false, default: '' },
      { key: 'debtReason', type: 'string', size: 512, required: false, default: '' },
      { key: 'totalAmount', type: 'double', required: true },
      { key: 'paidAmount', type: 'double', required: true },
      { key: 'remainingAmount', type: 'double', required: true },
      { key: 'paymentDate', type: 'string', size: 50, required: true },
      { key: 'isSettled', type: 'integer', required: false, default: 0 },
      { key: 'pledge', type: 'string', size: 512, required: false },
      { key: 'pledgeType', type: 'string', size: 50, required: false },
      { key: 'note', type: 'string', size: 2048, required: false },
      { key: 'debtUuid', type: 'string', size: 64, required: false },
      { key: 'hotelDayOpened', type: 'string', size: 50, required: false },
      { key: 'hotelDayClosed', type: 'string', size: 50, required: false },
      { key: 'isFromAutoFix', type: 'boolean', required: false, default: false },
      { key: 'settlementConfirmed', type: 'boolean', required: false, default: false },
    ],
  },

  shift_notes: {
    hasSyncFields: true,
    fields: [
      { key: 'title', type: 'string', size: 255, required: true },
      { key: 'content', type: 'string', size: 8192, required: true },
      { key: 'priority', type: 'string', size: 20, required: false, default: 'medium' },
      { key: 'shiftType', type: 'string', size: 20, required: false, default: 'all' },
      { key: 'isRead', type: 'integer', required: false, default: 0 },
      { key: 'expiresAt', type: 'string', size: 50, required: false },
      { key: 'createdBy', type: 'string', size: 50, required: false, default: 'user' },
    ],
  },

  booking_nights: {
    hasSyncFields: true,
    fields: [
      { key: 'bookingLocalId', type: 'integer', required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: true },
      { key: 'nightStart', type: 'string', size: 50, required: true },
      { key: 'nightEnd', type: 'string', size: 50, required: true },
      { key: 'nightlyRate', type: 'double', required: false, default: 0.0 },
      { key: 'sequence', type: 'integer', required: false, default: 0 },
      { key: 'isProcessedByAutoFix', type: 'boolean', required: false, default: false },
      { key: 'baseRate', type: 'double', required: false, default: 0.0 },
      { key: 'adjustment', type: 'double', required: false, default: 0.0 },
      { key: 'finalRate', type: 'double', required: false, default: 0.0 },
      { key: 'appliedAdjustmentUuid', type: 'string', size: 64, required: false },
      { key: 'appliedAdjustmentsJson', type: 'string', size: 8192, required: false },
    ],
  },

  price_adjustments: {
    hasSyncFields: true,
    fields: [
      { key: 'targetType', type: 'string', size: 50, required: true },
      { key: 'targetUuid', type: 'string', size: 64, required: true },
      { key: 'adjustmentType', type: 'string', size: 50, required: true },
      { key: 'previousValue', type: 'integer', required: true },
      { key: 'newValue', type: 'integer', required: true },
      { key: 'reason', type: 'string', size: 1024, required: false },
      { key: 'effectiveDate', type: 'string', size: 50, required: true },
      { key: 'appliedBy', type: 'string', size: 128, required: true },
      { key: 'hotelDayKey', type: 'string', size: 50, required: true },
      { key: 'isReversed', type: 'boolean', required: false, default: false },
      { key: 'reversedAt', type: 'string', size: 50, required: false },
      { key: 'reversedBy', type: 'string', size: 128, required: false },
    ],
  },

  booking_price_adjustments: {
    hasSyncFields: true,
    fields: [
      { key: 'bookingLocalUuid', type: 'string', size: 64, required: true },
      { key: 'bookingLocalId', type: 'integer', required: false },
      { key: 'roomNumber', type: 'string', size: 20, required: false },
      { key: 'adjustmentType', type: 'integer', required: false, default: 0 },
      { key: 'adjustmentMode', type: 'string', size: 50, required: false, default: 'per_night' },
      { key: 'amount', type: 'double', required: false, default: 0.0 },
      { key: 'effectiveHotelDay', type: 'string', size: 50, required: true },
      { key: 'endHotelDay', type: 'string', size: 50, required: false },
      { key: 'isActive', type: 'boolean', required: false, default: true },
      { key: 'reason', type: 'string', size: 1024, required: false },
      { key: 'appliedBy', type: 'string', size: 128, required: false },
      { key: 'cancelledAt', type: 'string', size: 50, required: false },
      { key: 'cancelledBy', type: 'string', size: 128, required: false },
    ],
  },

  audit_logs: {
    hasSyncFields: false,
    fields: [
      { key: 'localUuid', type: 'string', size: 64, required: true },
      { key: 'operationType', type: 'string', size: 50, required: true },
      { key: 'entityType', type: 'string', size: 50, required: true },
      { key: 'entityUuid', type: 'string', size: 64, required: true },
      { key: 'entityId', type: 'integer', required: false },
      { key: 'previousState', type: 'string', size: 16384, required: false },
      { key: 'newState', type: 'string', size: 16384, required: false },
      { key: 'changedFields', type: 'string', size: 4096, required: false },
      { key: 'performedBy', type: 'string', size: 128, required: true },
      { key: 'deviceId', type: 'string', size: 128, required: true },
      { key: 'ipAddress', type: 'string', size: 50, required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: true },
      { key: 'timestamp', type: 'integer', required: true },
      { key: 'timestampIso', type: 'string', size: 50, required: true },
      { key: 'isFinancial', type: 'boolean', required: false, default: false },
      { key: 'amountImpact', type: 'integer', required: false },
      { key: 'createdAt', type: 'integer', required: true },
    ],
  },

  payment_voids: {
    hasSyncFields: true,
    fields: [
      { key: 'originalPaymentUuid', type: 'string', size: 64, required: true },
      { key: 'originalPaymentId', type: 'integer', required: true },
      { key: 'bookingUuid', type: 'string', size: 64, required: true },
      { key: 'voidedAmount', type: 'integer', required: true },
      { key: 'voidReason', type: 'string', size: 1024, required: true },
      { key: 'voidedBy', type: 'string', size: 128, required: true },
      { key: 'voidedAt', type: 'integer', required: true },
      { key: 'voidedAtIso', type: 'string', size: 50, required: true },
      { key: 'hotelDayKey', type: 'string', size: 50, required: true },
      { key: 'reversalPaymentUuid', type: 'string', size: 64, required: false },
      { key: 'approvedBy', type: 'string', size: 128, required: false },
    ],
  },

  guest_infos: {
    hasSyncFields: true,
    fields: [
      { key: 'roomNumber', type: 'string', size: 20, required: true },
      { key: 'guestName', type: 'string', size: 255, required: true },
      { key: 'nationality', type: 'string', size: 100, required: true },
      { key: 'idNumber', type: 'string', size: 100, required: true },
      { key: 'idType', type: 'string', size: 100, required: false, default: '\u0628\u0637\u0627\u0642\u0629 \u0634\u062e\u0635\u064a\u0629' },
      { key: 'issueDate', type: 'string', size: 50, required: false },
      { key: 'issuePlace', type: 'string', size: 255, required: false },
      { key: 'governorate', type: 'string', size: 100, required: false },
      { key: 'notes', type: 'string', size: 2048, required: false },
    ],
  },

  salary_cycles: {
    hasSyncFields: true,
    fields: [
      { key: 'employeeId', type: 'integer', required: true },
      { key: 'cycleKey', type: 'string', size: 50, required: true },
      { key: 'hotelDayStart', type: 'string', size: 50, required: false },
      { key: 'hotelDayEnd', type: 'string', size: 50, required: false },
      { key: 'expectedAmount', type: 'integer', required: false, default: 0 },
      { key: 'actualPaid', type: 'integer', required: false, default: 0 },
      { key: 'remainingAmount', type: 'integer', required: false, default: 0 },
      { key: 'status', type: 'string', size: 50, required: false, default: 'draft' },
    ],
  },

  salary_payments: {
    hasSyncFields: true,
    fields: [
      { key: 'cycleId', type: 'integer', required: true },
      { key: 'amount', type: 'integer', required: false, default: 0 },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
      { key: 'paymentDateIso', type: 'string', size: 50, required: true },
      { key: 'method', type: 'string', size: 50, required: false },
      { key: 'isAutoGenerated', type: 'boolean', required: false, default: false },
    ],
  },

  salary_withdrawals: {
    hasSyncFields: true,
    fields: [
      { key: 'employeeId', type: 'integer', required: true },
      { key: 'amount', type: 'double', required: true },
      { key: 'withdrawDate', type: 'string', size: 50, required: true },
      { key: 'reason', type: 'string', size: 512, required: false },
      { key: 'hotelDayKey', type: 'string', size: 50, required: false },
      { key: 'withdrawalType', type: 'string', size: 50, required: false },
      { key: 'description', type: 'string', size: 1024, required: false },
    ],
  },
};

// ═══════════════════════════════════════════════════════════════
// دوال مساعدة
// ═══════════════════════════════════════════════════════════════

async function safeCreateAttribute(collId, field) {
  try {
    switch (field.type) {
      case 'string': {
        const size = field.size ?? 255;
        const def = field.default !== undefined ? String(field.default) : undefined;
        await db.createStringAttribute(DATABASE_ID, collId, field.key, size, field.required ?? false, def);
        break;
      }
      case 'integer': {
        const def = field.default;
        await db.createIntegerAttribute(DATABASE_ID, collId, field.key, field.required ?? false, undefined, undefined, def);
        break;
      }
      case 'double': {
        const def = field.default;
        await db.createFloatAttribute(DATABASE_ID, collId, field.key, field.required ?? false, undefined, undefined, def);
        break;
      }
      case 'boolean': {
        const def = field.default;
        await db.createBooleanAttribute(DATABASE_ID, collId, field.key, field.required ?? false, def);
        break;
      }
      default:
        console.log(`    ⚠️ نوع غير معروف: ${field.type}`);
        return 'skipped';
    }
    return 'created';
  } catch (e) {
    if (e.message && (e.message.includes('already exists') || e.message.includes('Attribute already exists'))) {
      return 'exists';
    }
    console.log(`    ❌ خطأ ${field.key}: ${e.message}`);
    return 'error';
  }
}

// ═══════════════════════════════════════════════════════════════
// الدالة الرئيسية
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('🚀 إنشاء جميع المجموعات والحقول في Appwrite Cloud');
  console.log(`📡 Endpoint: ${ENDPOINT}`);
  console.log(`📁 Project: ${PROJECT_ID}`);
  console.log(`🗄️  Database: ${DATABASE_ID}`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  // الخطوة 1: حذف جميع المجموعات القديمة
  console.log('🗑️ الخطوة 1: حذف المجموعات القديمة...');
  try {
    const existingColls = await db.listCollections(DATABASE_ID);
    console.log(`  عدد المجموعات الحالية: ${existingColls.total}`);
    
    for (const coll of existingColls.collections) {
      try {
        await db.deleteCollection(DATABASE_ID, coll.$id);
        console.log(`  ✅ تم حذف: ${coll.$id}`);
        await delay(500);
      } catch (e) {
        console.log(`  ❌ فشل حذف ${coll.$id}: ${e.message}`);
      }
    }
  } catch (e) {
    console.log(`  ⚠️ تعذر قراءة المجموعات: ${e.message}`);
  }

  // انتظار حتى يتم حذف الكل
  console.log('\n  ⏳ انتظار اكتمال الحذف...');
  await delay(3000);

  // التحقق من الحذف
  let remaining = 0;
  try {
    const check = await db.listCollections(DATABASE_ID);
    remaining = check.total;
    console.log(`  المجموعات المتبقية: ${remaining}`);
  } catch(e) {}

  if (remaining > 0) {
    console.log('  ⏳ انتظار إضافي...');
    await delay(5000);
  }

  // الخطوة 2: إنشاء المجموعات الجديدة
  console.log('\n📦 الخطوة 2: إنشاء المجموعات الجديدة...');
  let totalCreated = 0;
  let totalExisting = 0;
  let totalErrors = 0;
  let collIndex = 0;

  for (const [collKey, collDef] of Object.entries(COLLECTIONS)) {
    collIndex++;
    console.log(`\n━━━ [${collIndex}/${Object.keys(COLLECTIONS).length}] ${collKey} ━━━`);

    // إنشاء المجموعة
    try {
      await db.createCollection(DATABASE_ID, collKey, collKey);
      console.log(`  ✅ تم إنشاء المجموعة: ${collKey}`);
    } catch (e) {
      if (e.message && e.message.includes('already exists')) {
        console.log(`  ℹ️ المجموعة موجودة: ${collKey}`);
      } else {
        console.log(`  ❌ خطأ إنشاء المجموعة: ${e.message}`);
        continue;
      }
    }

    await delay(800);

    // إضافة الحقول الخاصة
    const ownFields = collDef.fields;
    console.log(`  📝 إضافة ${ownFields.length} حقل خاص...`);
    for (const field of ownFields) {
      const result = await safeCreateAttribute(collKey, field);
      if (result === 'created') {
        totalCreated++;
        console.log(`    ✅ ${field.key} (${field.type})`);
      } else if (result === 'exists') {
        totalExisting++;
      } else {
        totalErrors++;
      }
      await delay(250);
    }

    // إضافة حقول SyncFields
    if (collDef.hasSyncFields) {
      console.log(`  🔄 إضافة ${SYNC_FIELDS.length} حقل SyncFields...`);
      for (const field of SYNC_FIELDS) {
        const result = await safeCreateAttribute(collKey, field);
        if (result === 'created') {
          totalCreated++;
          console.log(`    ✅ ${field.key} (${field.type}) [S]`);
        } else if (result === 'exists') {
          totalExisting++;
        } else {
          totalErrors++;
        }
        await delay(250);
      }
    }

    const syncCount = collDef.hasSyncFields ? SYNC_FIELDS.length : 0;
    console.log(`  📊 ${collKey}: ${ownFields.length} + ${syncCount} = ${ownFields.length + syncCount} حقل`);
  }

  // التقرير النهائي
  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('📊 التقرير النهائي');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`📦 المجموعات: ${Object.keys(COLLECTIONS).length}`);
  console.log(`✅ حقول تم إنشاؤها: ${totalCreated}`);
  console.log(`ℹ️  حقول موجودة مسبقاً: ${totalExisting}`);
  console.log(`❌ أخطاء: ${totalErrors}`);
  console.log(`📝 الإجمالي: ${totalCreated + totalExisting + totalErrors}`);
  console.log('═══════════════════════════════════════════════════════════════');

  // التحقق النهائي
  console.log('\n🔍 التحقق النهائي...');
  await delay(2000);
  try {
    const allColls = await db.listCollections(DATABASE_ID);
    console.log(`\nعدد المجموعات: ${allColls.total}`);
    for (const coll of allColls.collections) {
      const attrs = await db.listAttributes(DATABASE_ID, coll.$id);
      console.log(`  📁 ${coll.$id}: ${attrs.total} حقل`);
    }
  } catch (e) {
    console.log(`⚠️ تعذر التحقق: ${e.message}`);
  }
}

main().catch(console.error);
