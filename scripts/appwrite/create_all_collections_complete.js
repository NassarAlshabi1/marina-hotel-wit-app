const { Client, Databases, Permission, Role } = require('node-appwrite');

const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1';
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

if (!apiKey) {
  console.error('❌ Missing APPWRITE_API_KEY environment variable');
  console.log('\n💡 Set it with:');
  console.log('   export APPWRITE_API_KEY="your-api-key-here"');
  console.log('\n📖 Get your API key from:');
  console.log(`   ${endpoint.replace('/v1', '')}/console/project-${projectId}/settings`);
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

const defaultPermissions = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

const syncFields = [
  { key: 'localUuid', type: 'string', size: 100, required: true, unique: true },
  { key: 'serverId', type: 'integer' },
  { key: 'createdAt', type: 'integer', required: true },
  { key: 'updatedAt', type: 'integer', required: true },
  { key: 'deletedAt', type: 'integer' },
  { key: 'lastModified', type: 'integer', required: true },
  { key: 'createdAtIso', type: 'string', size: 50 },
  { key: 'updatedAtIso', type: 'string', size: 50 },
  { key: 'deletedAtIso', type: 'string', size: 50 },
  { key: 'createdAtEpoch', type: 'integer', default: 0 },
  { key: 'lastModifiedEpoch', type: 'integer', default: 0 },
  { key: 'version', type: 'integer', default: 1 },
  { key: 'origin', type: 'string', size: 20, default: 'local' },
  { key: 'vectorClock', type: 'string', size: 500, default: '{}' },
];

const collections = [
  {
    id: 'rooms',
    name: 'الغرف',
    description: 'جدول الغرف الفندقية',
    attributes: [
      ...syncFields,
      { key: 'roomNumber', type: 'string', size: 50, required: true, unique: true },
      { key: 'type', type: 'string', size: 100, required: true },
      { key: 'price', type: 'float', required: true },
      { key: 'status', type: 'string', size: 50, required: true },
      { key: 'imageUrl', type: 'string', size: 500 },
      { key: 'cleaningStatus', type: 'string', size: 20, default: 'clean' },
      { key: 'lastCleanedHotelDay', type: 'string', size: 50 },
      { key: 'lastOccupiedHotelDay', type: 'string', size: 50 },
      { key: 'requiresMaintenance', type: 'boolean', default: false },
    ],
  },
  {
    id: 'bookings',
    name: 'الحجوزات',
    description: 'جدول حجوزات الضيوف',
    attributes: [
      ...syncFields,
      { key: 'serverBookingId', type: 'integer' },
      { key: 'roomNumber', type: 'string', size: 50, required: true },
      { key: 'guestName', type: 'string', size: 200, required: true },
      { key: 'guestPhone', type: 'string', size: 20, required: true },
      { key: 'guestIdType', type: 'string', size: 100, default: 'بطاقة شخصية' },
      { key: 'guestIdNumber', type: 'string', size: 50, default: '' },
      { key: 'guestIdIssueDate', type: 'string', size: 50 },
      { key: 'guestIdIssuePlace', type: 'string', size: 200 },
      { key: 'guestNationality', type: 'string', size: 100, required: true },
      { key: 'guestEmail', type: 'string', size: 200 },
      { key: 'guestAddress', type: 'string', size: 500 },
      { key: 'checkinDate', type: 'string', size: 50, required: true },
      { key: 'checkoutDate', type: 'string', size: 50 },
      { key: 'actualCheckout', type: 'string', size: 50 },
      { key: 'status', type: 'string', size: 50, required: true },
      { key: 'notes', type: 'string', size: 1000 },
      { key: 'expectedNights', type: 'integer', default: 1 },
      { key: 'calculatedNights', type: 'integer', default: 1 },
      { key: 'totalNightsCached', type: 'integer', default: 0 },
      { key: 'stayDurationIso', type: 'string', size: 50 },
      { key: 'lastNightEpoch', type: 'integer' },
      { key: 'isOverdue', type: 'boolean', default: false },
      { key: 'needsCheckoutReview', type: 'boolean', default: false },
      { key: 'totalDueCached', type: 'float', default: 0 },
      { key: 'totalPaidCached', type: 'float', default: 0 },
      { key: 'remainingBalanceCached', type: 'float', default: 0 },
      { key: 'isFullyPaid', type: 'boolean', default: false },
      { key: 'hotelDayCheckin', type: 'string', size: 50 },
      { key: 'hotelDayCheckout', type: 'string', size: 50 },
    ],
  },
  {
    id: 'booking_notes',
    name: 'ملاحظات الحجوزات',
    description: 'جدول ملاحظات الحجوزات',
    attributes: [
      ...syncFields,
      { key: 'bookingId', type: 'integer', required: true },
      { key: 'noteText', type: 'string', size: 1000, required: true },
      { key: 'alertType', type: 'string', size: 20, required: true },
      { key: 'alertUntil', type: 'string', size: 50 },
      { key: 'isActive', type: 'integer', default: 1 },
    ],
  },
  {
    id: 'booking_nights',
    name: 'ليالي الحجوزات',
    description: 'جدول ليالي الحجوزات',
    attributes: [
      ...syncFields,
      { key: 'bookingLocalId', type: 'integer', required: true },
      { key: 'hotelDayKey', type: 'string', size: 50, required: true },
      { key: 'nightStart', type: 'string', size: 50, required: true },
      { key: 'nightEnd', type: 'string', size: 50, required: true },
      { key: 'nightlyRate', type: 'float', default: 0 },
      { key: 'sequence', type: 'integer', default: 0 },
      { key: 'isProcessedByAutoFix', type: 'boolean', default: false },
    ],
  },
  {
    id: 'employees',
    name: 'الموظفون',
    description: 'جدول الموظفين',
    attributes: [
      ...syncFields,
      { key: 'name', type: 'string', size: 200, required: true },
      { key: 'basicSalary', type: 'float', required: true },
      { key: 'position', type: 'string', size: 100, default: 'موظف' },
      { key: 'phone', type: 'string', size: 20, default: '' },
      { key: 'hireDate', type: 'string', size: 50, default: '' },
      { key: 'status', type: 'string', size: 50, required: true },
    ],
  },
  {
    id: 'expenses',
    name: 'المصروفات',
    description: 'جدول المصروفات',
    attributes: [
      ...syncFields,
      { key: 'expenseType', type: 'string', size: 100, required: true },
      { key: 'relatedId', type: 'integer' },
      { key: 'description', type: 'string', size: 500, required: true },
      { key: 'amount', type: 'float', required: true },
      { key: 'date', type: 'string', size: 50, required: true },
      { key: 'cashTransactionId', type: 'integer' },
      { key: 'hotelDayKey', type: 'string', size: 50 },
      { key: 'categoryUuid', type: 'string', size: 100 },
      { key: 'cashFlowUuid', type: 'string', size: 100 },
      { key: 'isAutoGenerated', type: 'boolean', default: false },
    ],
  },
  {
    id: 'cash_transactions',
    name: 'معاملات النقد',
    description: 'جدول معاملات النقد',
    attributes: [
      ...syncFields,
      { key: 'registerId', type: 'integer' },
      { key: 'transactionType', type: 'string', size: 100, required: true },
      { key: 'amount', type: 'float', required: true },
      { key: 'referenceType', type: 'string', size: 100 },
      { key: 'referenceId', type: 'integer' },
      { key: 'description', type: 'string', size: 500 },
      { key: 'transactionTime', type: 'string', size: 50, required: true },
      { key: 'createdBy', type: 'integer' },
    ],
  },
  {
    id: 'payments',
    name: 'الدفعات',
    description: 'جدول الدفعات',
    attributes: [
      ...syncFields,
      { key: 'serverPaymentId', type: 'integer' },
      { key: 'bookingLocalId', type: 'integer' },
      { key: 'serverBookingId', type: 'integer' },
      { key: 'roomNumber', type: 'string', size: 50 },
      { key: 'amount', type: 'float', required: true },
      { key: 'paymentDate', type: 'string', size: 50, required: true },
      { key: 'notes', type: 'string', size: 500 },
      { key: 'paymentMethod', type: 'string', size: 100, required: true },
      { key: 'revenueType', type: 'string', size: 100, required: true },
      { key: 'cashTransactionLocalId', type: 'integer' },
      { key: 'cashTransactionServerId', type: 'integer' },
      { key: 'referenceNumber', type: 'string', size: 100 },
      { key: 'hotelDayKey', type: 'string', size: 50 },
      { key: 'isPendingBalance', type: 'boolean', default: false },
      { key: 'linkedDebtUuid', type: 'string', size: 100 },
      { key: 'bookingUuidCache', type: 'string', size: 100 },
    ],
  },
  {
    id: 'debts',
    name: 'الديون',
    description: 'جدول الديون',
    attributes: [
      ...syncFields,
      { key: 'bookingLocalId', type: 'integer' },
      { key: 'guestName', type: 'string', size: 200, required: true },
      { key: 'checkinDate', type: 'string', size: 50, required: true },
      { key: 'checkoutDate', type: 'string', size: 50, required: true },
      { key: 'dateRecorded', type: 'string', size: 50, default: '' },
      { key: 'debtReason', type: 'string', size: 500, default: '' },
      { key: 'totalAmount', type: 'float', required: true },
      { key: 'paidAmount', type: 'float', required: true },
      { key: 'remainingAmount', type: 'float', required: true },
      { key: 'paymentDate', type: 'string', size: 50, required: true },
      { key: 'isSettled', type: 'integer', default: 0 },
      { key: 'pledge', type: 'string', size: 500 },
      { key: 'pledgeType', type: 'string', size: 50 },
      { key: 'note', type: 'string', size: 500 },
      { key: 'debtUuid', type: 'string', size: 100 },
      { key: 'hotelDayOpened', type: 'string', size: 50 },
      { key: 'hotelDayClosed', type: 'string', size: 50 },
      { key: 'isFromAutoFix', type: 'boolean', default: false },
      { key: 'settlementConfirmed', type: 'boolean', default: false },
    ],
  },
  {
    id: 'salary_cycles',
    name: 'دورات الرواتب',
    description: 'جدول دورات الرواتب',
    attributes: [
      ...syncFields,
      { key: 'employeeId', type: 'integer', required: true },
      { key: 'cycleKey', type: 'string', size: 50, required: true },
      { key: 'hotelDayStart', type: 'string', size: 50 },
      { key: 'hotelDayEnd', type: 'string', size: 50 },
      { key: 'expectedAmount', type: 'float', default: 0 },
      { key: 'actualPaid', type: 'float', default: 0 },
      { key: 'remainingAmount', type: 'float', default: 0 },
      { key: 'status', type: 'string', size: 20, default: 'draft' },
    ],
  },
  {
    id: 'salary_payments',
    name: 'دفعات الرواتب',
    description: 'جدول دفعات الرواتب',
    attributes: [
      ...syncFields,
      { key: 'cycleId', type: 'integer', required: true },
      { key: 'amount', type: 'float', default: 0 },
      { key: 'hotelDayKey', type: 'string', size: 50 },
      { key: 'paymentDateIso', type: 'string', size: 50, required: true },
      { key: 'method', type: 'string', size: 20 },
      { key: 'isAutoGenerated', type: 'boolean', default: false },
    ],
  },
  {
    id: 'hotel_day_ledger',
    name: 'سجل الأيام الفندقية',
    description: 'جدول سجل الأيام الفندقية',
    attributes: [
      ...syncFields,
      { key: 'hotelDayKey', type: 'string', size: 50, required: true, unique: true },
      { key: 'totalIncome', type: 'float', default: 0 },
      { key: 'totalExpenses', type: 'float', default: 0 },
      { key: 'pendingBalances', type: 'float', default: 0 },
      { key: 'occupancyRate', type: 'float', default: 0 },
      { key: 'bookingsProcessed', type: 'integer', default: 0 },
      { key: 'paymentsProcessed', type: 'integer', default: 0 },
      { key: 'debtsProcessed', type: 'integer', default: 0 },
      { key: 'expensesProcessed', type: 'integer', default: 0 },
      { key: 'status', type: 'string', size: 20, default: 'draft' },
    ],
  },
  {
    id: 'devices',
    name: 'الأجهزة المسجلة',
    description: 'جدول الأجهزة المسجلة',
    attributes: [
      ...syncFields,
      { key: 'deviceName', type: 'string', size: 200, required: true },
      { key: 'deviceType', type: 'string', size: 50, required: true },
      { key: 'deviceModel', type: 'string', size: 100 },
      { key: 'osVersion', type: 'string', size: 50 },
      { key: 'status', type: 'string', size: 50 },
      { key: 'lastActive', type: 'integer', required: true },
      { key: 'lastSeen', type: 'string', size: 50, required: true },
    ],
  },
  {
    id: 'shift_notes',
    name: 'Shift Notes',
    description: 'ملاحظات الشيفت',
    attributes: [
      { key: 'localUuid', type: 'string', size: 100, required: true },
      { key: 'serverId', type: 'integer', required: false },
      { key: 'title', type: 'string', size: 500, required: true },
      { key: 'content', type: 'string', size: 5000, required: true },
      { key: 'priority', type: 'string', size: 50, required: true, default: 'medium' },
      { key: 'shiftType', type: 'string', size: 50, required: true, default: 'all' },
      { key: 'isRead', type: 'integer', required: true, default: 0 },
      { key: 'expiresAt', type: 'string', size: 50, required: false },
      { key: 'createdBy', type: 'string', size: 100, required: true, default: 'user' },
      { key: 'createdAt', type: 'integer', required: true },
      { key: 'updatedAt', type: 'integer', required: true },
      { key: 'deletedAt', type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: true },
      { key: 'createdAtIso', type: 'string', size: 50, required: false },
      { key: 'updatedAtIso', type: 'string', size: 50, required: false },
      { key: 'version', type: 'integer', required: true, default: 1 },
      { key: 'origin', type: 'string', size: 50, required: true, default: 'local' },
    ],
    indexes: [
      { key: 'idx_localUuid', type: 'unique', attributes: ['localUuid'] },
      { key: 'idx_serverId', type: 'key', attributes: ['serverId'] },
      { key: 'idx_isRead', type: 'key', attributes: ['isRead'] },
      { key: 'idx_priority', type: 'key', attributes: ['priority'] },
      { key: 'idx_shiftType', type: 'key', attributes: ['shiftType'] },
      { key: 'idx_createdAt', type: 'key', attributes: ['createdAt'], orders: ['DESC'] },
    ],
  },
  {
    id: 'sync_logs',
    name: 'سجل المزامنة',
    description: 'جدول سجل المزامنة',
    attributes: [
      { key: 'localUuid', type: 'string', size: 100, required: true, unique: true },
      { key: 'syncId', type: 'string', size: 100 },
      { key: 'direction', type: 'string', size: 20 },
      { key: 'deviceId', type: 'string', size: 100 },
      { key: 'metadata', type: 'string', size: 2000 },
      { key: 'operations', type: 'string', size: 2000 },
      { key: 'checksumMatched', type: 'integer', default: 0 },
      { key: 'status', type: 'string', size: 50, default: 'success' },
      { key: 'createdAt', type: 'string', size: 50, required: true },
      { key: 'syncType', type: 'string', size: 50, required: true },
      { key: 'startTime', type: 'string', size: 50, required: true },
      { key: 'endTime', type: 'string', size: 50 },
      { key: 'errorMessage', type: 'string', size: 500 },
    ],
  },
];

async function createAttribute(databaseId, collectionId, attribute) {
  try {
    console.log(`   → Creating attribute: ${attribute.key}`);
    
    switch (attribute.type) {
      case 'string':
        await databases.createStringAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.size || 255,
          attribute.required || false,
          attribute.default ?? undefined,
          attribute.array || false,
          attribute.encrypt ?? false
        );
        break;
      case 'integer':
        await databases.createIntegerAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.required || false,
          attribute.minimum ?? undefined,
          attribute.maximum ?? undefined,
          attribute.default ?? undefined,
          attribute.array || false
        );
        break;
      case 'float':
        await databases.createFloatAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.required || false,
          attribute.minimum ?? undefined,
          attribute.maximum ?? undefined,
          attribute.default ?? undefined,
          attribute.array || false
        );
        break;
      case 'boolean':
        await databases.createBooleanAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.required || false,
          attribute.default ?? undefined,
          attribute.array || false
        );
        break;
      default:
        console.warn(`   ⚠️  Unsupported type: ${attribute.type} for ${attribute.key}`);
    }
    console.log(`   ✅ Created: ${attribute.key}`);
  } catch (error) {
    if (error?.code === 409) {
      console.log(`   ⏭️  Exists: ${attribute.key}`);
    } else {
      console.error(`   ❌ Failed: ${attribute.key}`, error.message || error);
    }
  }
}

async function ensureCollection(collection) {
  console.log(`\n📋 Processing collection: ${collection.id} (${collection.name})`);
  
  try {
    await databases.createCollection(
      databaseId,
      collection.id,
      collection.name,
      collection.permissions || defaultPermissions,
      true,
      true
    );
    console.log(`✅ Created collection: ${collection.id}`);
  } catch (error) {
    if (error?.code === 409) {
      console.log(`⏭️  Collection exists: ${collection.id}`);
    } else {
      console.error(`❌ Failed to create collection ${collection.id}:`, error.message || error);
      return false;
    }
  }

  console.log(`\n   Creating ${collection.attributes.length} attributes...`);
  for (const attr of collection.attributes) {
    await createAttribute(databaseId, collection.id, attr);
  }
  
  return true;
}

(async () => {
  console.log('═══════════════════════════════════════');
  console.log('🚀 Appwrite Collections Setup');
  console.log('═══════════════════════════════════════');
  console.log(`Endpoint: ${endpoint}`);
  console.log(`Project: ${projectId}`);
  console.log(`Database: ${databaseId}`);
  console.log(`Collections: ${collections.length}`);
  console.log('═══════════════════════════════════════\n');

  let successCount = 0;
  let failCount = 0;

  for (const collection of collections) {
    const success = await ensureCollection(collection);
    if (success !== false) {
      successCount++;
    } else {
      failCount++;
    }
  }

  console.log('\n═══════════════════════════════════════');
  console.log('📊 Summary');
  console.log('═══════════════════════════════════════');
  console.log(`✅ Success: ${successCount}/${collections.length}`);
  if (failCount > 0) {
    console.log(`❌ Failed: ${failCount}`);
  }
  console.log('═══════════════════════════════════════\n');

  if (successCount === collections.length) {
    console.log('🎉 All collections created successfully!');
    console.log('\n💡 Next steps:');
    console.log('   1. Verify collections in Appwrite Console');
    console.log('   2. Test sync from Flutter app');
    console.log('   3. Monitor sync logs');
  } else {
    console.log('⚠️  Some collections failed. Check the logs above.');
  }
})();
