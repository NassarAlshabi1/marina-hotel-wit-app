const { Client, Databases, Permission, Role } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT;
const projectId = process.env.APPWRITE_PROJECT;
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";

if (!endpoint || !projectId || !apiKey) {
  console.error("Missing required environment variables. Please set APPWRITE_ENDPOINT, APPWRITE_PROJECT, and APPWRITE_API_KEY.");
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

const defaultPermissions = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

const WAIT_ATTEMPTS = parseInt(process.env.APPWRITE_WAIT_ATTEMPTS || "10", 10);
const WAIT_DELAY_MS = parseInt(process.env.APPWRITE_WAIT_DELAY_MS || "2000", 10);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForAttribute(databaseId, collectionId, attributeKey) {
  for (let attempt = 0; attempt < WAIT_ATTEMPTS; attempt++) {
    try {
      const { attributes } = await databases.listAttributes(databaseId, collectionId);
      if (attributes?.some((attr) => attr.key === attributeKey)) {
        return true;
      }
    } catch (error) {
      console.warn(`Failed to list attributes for ${collectionId} (attempt ${attempt + 1})`, error);
    }
    await sleep(WAIT_DELAY_MS);
  }
  return false;
}

async function ensureUniqueIndex(databaseId, collectionId, attributeKey) {
  try {
    const { indexes } = await databases.listIndexes(databaseId, collectionId);
    if (indexes?.some((idx) => idx.type === "unique" && idx.attributes?.length === 1 && idx.attributes[0] === attributeKey)) {
      return;
    }
    const indexKey = `idx_${collectionId}_${attributeKey}`;
    await databases.createIndex(databaseId, collectionId, indexKey, "unique", [attributeKey]);
    console.log(`✔ Created unique index ${indexKey}`);
  } catch (error) {
    if (error?.code === 409) {
      console.warn(`Index for ${attributeKey} already exists on ${collectionId}.`);
    } else {
      console.error(`Failed to create index on ${collectionId}.${attributeKey}:`, error);
    }
  }
}

const syncFields = [
  { key: "localUuid", type: "string", size: 100, required: true, unique: true },
  { key: "serverId", type: "integer" },
  { key: "createdAt", type: "integer", required: true },
  { key: "updatedAt", type: "integer", required: true },
  { key: "deletedAt", type: "integer" },
  { key: "lastModified", type: "integer", required: true },
  { key: "createdAtIso", type: "string", size: 50 },
  { key: "updatedAtIso", type: "string", size: 50 },
  { key: "deletedAtIso", type: "string", size: 50 },
  { key: "createdAtEpoch", type: "integer", default: 0 },
  { key: "lastModifiedEpoch", type: "integer", default: 0 },
  { key: "version", type: "integer", default: 1 },
  { key: "origin", type: "string", size: 20, default: "local" },
  { key: "vectorClock", type: "string", size: 500, default: "{}" },
];

const collections = [
  {
    id: "rooms",
    name: "الغرف",
    description: "جدول الغرف الفندقية",
    attributes: [
      ...syncFields,
      { key: "roomNumber", type: "string", size: 50, required: true, unique: true },
      { key: "type", type: "string", size: 100, required: true },
      { key: "price", type: "float", required: true },
      { key: "status", type: "string", size: 50, required: true },
      { key: "imageUrl", type: "string", size: 500 },
      { key: "cleaningStatus", type: "string", size: 20, default: "clean" },
      { key: "lastCleanedHotelDay", type: "string", size: 50 },
      { key: "lastOccupiedHotelDay", type: "string", size: 50 },
      { key: "requiresMaintenance", type: "boolean", default: false },
    ],
  },
  {
    id: "bookings",
    name: "الحجوزات",
    description: "جدول حجوزات الضيوف",
    attributes: [
      ...syncFields,
      { key: "serverBookingId", type: "integer" },
      { key: "roomNumber", type: "string", size: 50, required: true },
      { key: "guestName", type: "string", size: 200, required: true },
      { key: "guestPhone", type: "string", size: 20, required: true },
      { key: "guestIdType", type: "string", size: 100, default: "بطاقة شخصية" },
      { key: "guestIdNumber", type: "string", size: 50, default: "" },
      { key: "guestIdIssueDate", type: "string", size: 50 },
      { key: "guestIdIssuePlace", type: "string", size: 200 },
      { key: "guestNationality", type: "string", size: 100, required: true },
      { key: "guestEmail", type: "string", size: 200 },
      { key: "guestAddress", type: "string", size: 500 },
      { key: "checkinDate", type: "string", size: 50, required: true },
      { key: "checkoutDate", type: "string", size: 50 },
      { key: "actualCheckout", type: "string", size: 50 },
      { key: "status", type: "string", size: 50, required: true },
      { key: "notes", type: "string", size: 1000 },
      { key: "expectedNights", type: "integer", default: 1 },
      { key: "calculatedNights", type: "integer", default: 1 },
      { key: "totalNightsCached", type: "integer", default: 0 },
      { key: "stayDurationIso", type: "string", size: 50 },
      { key: "lastNightEpoch", type: "integer" },
      { key: "isOverdue", type: "boolean", default: false },
      { key: "needsCheckoutReview", type: "boolean", default: false },
      { key: "totalDueCached", type: "float", default: 0 },
      { key: "totalPaidCached", type: "float", default: 0 },
      { key: "remainingBalanceCached", type: "float", default: 0 },
      { key: "isFullyPaid", type: "boolean", default: false },
      { key: "hotelDayCheckin", type: "string", size: 50 },
      { key: "hotelDayCheckout", type: "string", size: 50 },
    ],
  },
  {
    id: "booking_notes",
    name: "ملاحظات الحجوزات",
    description: "جدول ملاحظات الحجوزات",
    attributes: [
      ...syncFields,
      { key: "bookingId", type: "integer", required: true },
      { key: "noteText", type: "string", size: 1000, required: true },
      { key: "alertType", type: "string", size: 20, required: true },
      { key: "alertUntil", type: "string", size: 50 },
      { key: "isActive", type: "integer", default: 1 },
    ],
  },
  {
    id: "shift_notes",
    name: "ملاحظات المناوبات",
    description: "جدول ملاحظات المناوبات",
    attributes: [
      { key: "title", type: "string", size: 200, required: true },
      { key: "content", type: "string", size: 2000, required: true },
      { key: "priority", type: "string", size: 20, default: "medium" },
      { key: "shiftType", type: "string", size: 20, default: "all" },
      { key: "isRead", type: "integer", default: 0 },
      { key: "createdAt", type: "string", size: 50, required: true },
      { key: "expiresAt", type: "string", size: 50 },
      { key: "createdBy", type: "string", size: 100, default: "user" },
    ],
  },
  {
    id: "booking_nights",
    name: "ليالي الحجوزات",
    description: "جدول ليالي الحجوزات",
    attributes: [
      ...syncFields,
      { key: "bookingLocalId", type: "integer", required: true },
      { key: "hotelDayKey", type: "string", size: 50, required: true },
      { key: "nightStart", type: "string", size: 50, required: true },
      { key: "nightEnd", type: "string", size: 50, required: true },
      { key: "nightlyRate", type: "float", default: 0 },
      { key: "sequence", type: "integer", default: 0 },
      { key: "isProcessedByAutoFix", type: "boolean", default: false },
    ],
  },
  {
    id: "employees",
    name: "الموظفون",
    description: "جدول الموظفين",
    attributes: [
      ...syncFields,
      { key: "name", type: "string", size: 200, required: true },
      { key: "basicSalary", type: "float", required: true },
      { key: "position", type: "string", size: 100, default: "موظف" },
      { key: "phone", type: "string", size: 20, default: "" },
      { key: "hireDate", type: "string", size: 50, default: "" },
      { key: "status", type: "string", size: 50, required: true },
    ],
  },
  {
    id: "expenses",
    name: "المصروفات",
    description: "جدول المصروفات",
    attributes: [
      ...syncFields,
      { key: "expenseType", type: "string", size: 100, required: true },
      { key: "relatedId", type: "integer" },
      { key: "description", type: "string", size: 500, required: true },
      { key: "amount", type: "float", required: true },
      { key: "date", type: "string", size: 50, required: true },
      { key: "cashTransactionId", type: "integer" },
      { key: "hotelDayKey", type: "string", size: 50 },
      { key: "categoryUuid", type: "string", size: 100 },
      { key: "cashFlowUuid", type: "string", size: 100 },
      { key: "isAutoGenerated", type: "boolean", default: false },
    ],
  },
  {
    id: "cash_transactions",
    name: "معاملات النقد",
    description: "جدول معاملات النقد",
    attributes: [
      ...syncFields,
      { key: "registerId", type: "integer" },
      { key: "transactionType", type: "string", size: 100, required: true },
      { key: "amount", type: "float", required: true },
      { key: "referenceType", type: "string", size: 100 },
      { key: "referenceId", type: "integer" },
      { key: "description", type: "string", size: 500 },
      { key: "transactionTime", type: "string", size: 50, required: true },
      { key: "createdBy", type: "integer" },
    ],
  },
  {
    id: "payments",
    name: "الدفعات",
    description: "جدول الدفعات",
    attributes: [
      ...syncFields,
      { key: "serverPaymentId", type: "integer" },
      { key: "bookingLocalId", type: "integer" },
      { key: "serverBookingId", type: "integer" },
      { key: "roomNumber", type: "string", size: 50 },
      { key: "amount", type: "float", required: true },
      { key: "paymentDate", type: "string", size: 50, required: true },
      { key: "notes", type: "string", size: 500 },
      { key: "paymentMethod", type: "string", size: 100, required: true },
      { key: "revenueType", type: "string", size: 100, required: true },
      { key: "cashTransactionLocalId", type: "integer" },
      { key: "cashTransactionServerId", type: "integer" },
      { key: "referenceNumber", type: "string", size: 100 },
      { key: "hotelDayKey", type: "string", size: 50 },
      { key: "isPendingBalance", type: "boolean", default: false },
      { key: "linkedDebtUuid", type: "string", size: 100 },
      { key: "bookingUuidCache", type: "string", size: 100 },
    ],
  },
  {
    id: "debts",
    name: "الديون",
    description: "جدول الديون",
    attributes: [
      ...syncFields,
      { key: "bookingLocalId", type: "integer" },
      { key: "guestName", type: "string", size: 200, required: true },
      { key: "checkinDate", type: "string", size: 50, required: true },
      { key: "checkoutDate", type: "string", size: 50, required: true },
      { key: "dateRecorded", type: "string", size: 50, default: "" },
      { key: "debtReason", type: "string", size: 500, default: "" },
      { key: "totalAmount", type: "float", required: true },
      { key: "paidAmount", type: "float", required: true },
      { key: "remainingAmount", type: "float", required: true },
      { key: "paymentDate", type: "string", size: 50, required: true },
      { key: "isSettled", type: "integer", default: 0 },
      { key: "pledge", type: "string", size: 500 },
      { key: "pledgeType", type: "string", size: 50 },
      { key: "note", type: "string", size: 500 },
      { key: "debtUuid", type: "string", size: 100 },
      { key: "hotelDayOpened", type: "string", size: 50 },
      { key: "hotelDayClosed", type: "string", size: 50 },
      { key: "isFromAutoFix", type: "boolean", default: false },
      { key: "settlementConfirmed", type: "boolean", default: false },
    ],
  },
  {
    id: "salary_cycles",
    name: "دورات الرواتب",
    description: "جدول دورات الرواتب",
    attributes: [
      ...syncFields,
      { key: "employeeId", type: "integer", required: true },
      { key: "cycleKey", type: "string", size: 50, required: true },
      { key: "hotelDayStart", type: "string", size: 50 },
      { key: "hotelDayEnd", type: "string", size: 50 },
      { key: "expectedAmount", type: "float", default: 0 },
      { key: "actualPaid", type: "float", default: 0 },
      { key: "remainingAmount", type: "float", default: 0 },
      { key: "status", type: "string", size: 20, default: "draft" },
    ],
  },
  {
    id: "salary_payments",
    name: "دفعات الرواتب",
    description: "جدول دفعات الرواتب",
    attributes: [
      ...syncFields,
      { key: "cycleId", type: "integer", required: true },
      { key: "amount", type: "float", default: 0 },
      { key: "hotelDayKey", type: "string", size: 50 },
      { key: "paymentDateIso", type: "string", size: 50, required: true },
      { key: "method", type: "string", size: 20 },
      { key: "isAutoGenerated", type: "boolean", default: false },
    ],
  },
  {
    id: "hotel_day_ledger",
    name: "سجل الأيام الفندقية",
    description: "جدول سجل الأيام الفندقية",
    attributes: [
      ...syncFields,
      { key: "hotelDayKey", type: "string", size: 50, required: true, unique: true },
      { key: "totalIncome", type: "float", default: 0 },
      { key: "totalExpenses", type: "float", default: 0 },
      { key: "pendingBalances", type: "float", default: 0 },
      { key: "occupancyRate", type: "float", default: 0 },
      { key: "bookingsProcessed", type: "integer", default: 0 },
      { key: "paymentsProcessed", type: "integer", default: 0 },
      { key: "debtsProcessed", type: "integer", default: 0 },
      { key: "expensesProcessed", type: "integer", default: 0 },
      { key: "status", type: "string", size: 20, default: "draft" },
    ],
  },
  {
    id: "devices",
    name: "الأجهزة المسجلة",
    description: "جدول الأجهزة المسجلة للمزامنة",
    attributes: [
      ...syncFields,
      { key: "deviceName", type: "string", size: 200, required: true },
      { key: "deviceType", type: "string", size: 50, required: true },
      { key: "deviceModel", type: "string", size: 100 },
      { key: "osVersion", type: "string", size: 50 },
      { key: "status", type: "string", size: 50 },
      { key: "lastActive", type: "integer", required: true },
      { key: "lastSeen", type: "string", size: 50, required: true },
    ],
  },
  {
    id: "sync_logs",
    name: "سجل المزامنة",
    description: "جدول سجلات المزامنة والأخطاء",
    attributes: [
      { key: "action", type: "string", size: 100 },
      { key: "status", type: "string", size: 50 },
      { key: "timestamp", type: "integer", required: true },
      { key: "details", type: "string", size: 1000 },
      { key: "deviceId", type: "string", size: 100 },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "syncType", type: "string", size: 50, required: true },
      { key: "startTime", type: "string", size: 50, required: true },
      { key: "endTime", type: "string", size: 50 },
      { key: "errorMessage", type: "string", size: 500 },
    ],
  },
];

async function createAttribute(databaseId, collectionId, attribute) {
  try {
    switch (attribute.type) {
      case "string":
        await databases.createStringAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.size || 255,
          attribute.required || false,
          attribute.default ?? null,
          attribute.array || false,
          attribute.encrypt ?? false
        );
        break;
      case "integer":
        await databases.createIntegerAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.required || false,
          attribute.minimum ?? null,
          attribute.maximum ?? null,
          attribute.default ?? null,
          attribute.array || false
        );
        break;
      case "float":
        await databases.createFloatAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.required || false,
          attribute.minimum ?? null,
          attribute.maximum ?? null,
          attribute.default ?? null,
          attribute.array || false
        );
        break;
      case "boolean":
        await databases.createBooleanAttribute(
          databaseId,
          collectionId,
          attribute.key,
          attribute.required || false,
          attribute.default ?? false,
          attribute.array || false
        );
        break;
      default:
        console.warn(`Unsupported attribute type ${attribute.type} for ${attribute.key}`);
    }

  } catch (error) {
    if (error?.code === 409) {
      console.warn(`Attribute ${attribute.key} already exists in ${collectionId}.`);
    } else {
      console.error(`Failed to create attribute ${attribute.key} in ${collectionId}:`, error);
      return;
    }
  }

  if (attribute.unique) {
    const ready = await waitForAttribute(databaseId, collectionId, attribute.key);
    if (!ready) {
      console.warn(`Attribute ${attribute.key} in ${collectionId} is not ready for indexing yet.`);
      return;
    }
    await ensureUniqueIndex(databaseId, collectionId, attribute.key);
  }
}

async function createCollection(collection) {
  try {
    console.log(`Creating collection ${collection.id}...`);
    await databases.createCollection(
      databaseId,
      collection.id,
      collection.name,
      collection.permissions || defaultPermissions,
      true,
      true
    );
    console.log(`✔ Collection ${collection.id} created`);
  } catch (error) {
    if (error?.code === 409) {
      console.warn(`Collection ${collection.id} already exists.`);
    } else {
      console.error(`Failed to create collection ${collection.id}:`, error);
      return;
    }
  }

  for (const attribute of collection.attributes) {
    await createAttribute(databaseId, collection.id, attribute);
  }
}

(async () => {
  try {
    for (const collection of collections) {
      await createCollection(collection);
    }
    console.log("✅ All collections processed.");
  } catch (error) {
    console.error("Failed to set up collections:", error);
    process.exit(1);
  }
})();
