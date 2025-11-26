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
      const { attributes } = await databases.listAttributes(databaseId, collectionId, ["limit(100)"]);
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
    const { indexes } = await databases.listIndexes(databaseId, collectionId, ["limit(100)"]);
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

const collections = [
  {
    id: "rooms",
    name: "الغرف",
    description: "جدول الغرف الفندقية",
    attributes: [
      { key: "roomNumber", type: "string", size: 50, required: true, unique: true },
      { key: "type", type: "string", size: 100, required: true },
      { key: "price", type: "float", required: true },
      { key: "status", type: "string", size: 50, required: true },
      { key: "imageUrl", type: "string", size: 500 },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
    ],
  },
  {
    id: "bookings",
    name: "الحجوزات",
    description: "جدول حجوزات الضيوف",
    attributes: [
      { key: "serverBookingId", type: "integer" },
      { key: "roomNumber", type: "string", size: 50, required: true },
      { key: "guestName", type: "string", size: 200, required: true },
      { key: "guestPhone", type: "string", size: 20, required: true },
      { key: "guestIdType", type: "string", size: 100, required: true },
      { key: "guestIdNumber", type: "string", size: 50, required: true },
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
      { key: "expectedNights", type: "integer", required: true },
      { key: "calculatedNights", type: "integer", required: true },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
    ],
  },
  {
    id: "payments",
    name: "الدفعات",
    description: "جدول الدفعات",
    attributes: [
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
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
    ],
  },
  {
    id: "expenses",
    name: "المصروفات",
    description: "جدول المصروفات",
    attributes: [
      { key: "expenseType", type: "string", size: 100, required: true },
      { key: "relatedId", type: "integer" },
      { key: "description", type: "string", size: 500, required: true },
      { key: "amount", type: "float", required: true },
      { key: "date", type: "string", size: 50, required: true },
      { key: "cashTransactionId", type: "integer" },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
    ],
  },
  {
    id: "employees",
    name: "الموظفون",
    description: "جدول الموظفين",
    attributes: [
      { key: "name", type: "string", size: 200, required: true },
      { key: "basicSalary", type: "float", required: true },
      { key: "position", type: "string", size: 100, required: true },
      { key: "phone", type: "string", size: 20, required: true },
      { key: "hireDate", type: "string", size: 50, required: true },
      { key: "status", type: "string", size: 50, required: true },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
    ],
  },
  {
    id: "debts",
    name: "الديون",
    description: "جدول الديون",
    attributes: [
      { key: "amount", type: "float", required: true },
      { key: "debtorName", type: "string", size: 200, required: true },
      { key: "dueDate", type: "string", size: 50, required: true },
      { key: "status", type: "string", size: 50, required: true },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
    ],
  },
  {
    id: "devices",
    name: "الأجهزة المسجلة",
    description: "جدول الأجهزة المسجلة للمزامنة",
    attributes: [
      { key: "deviceName", type: "string", size: 200, required: true },
      { key: "deviceType", type: "string", size: 50, required: true },
      { key: "deviceModel", type: "string", size: 100 },
      { key: "osVersion", type: "string", size: 50 },
      { key: "status", type: "string", size: 50 },
      { key: "lastActive", type: "integer", required: true },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
    ],
  },
  {
    id: "sync_logs",
    name: "سجل المزامنة",
    description: "جدول سجلات المزامنة والأخطاء",
    attributes: [
      { key: "action", type: "string", size: 100, required: true },
      { key: "status", type: "string", size: 50 },
      { key: "timestamp", type: "integer", required: true },
      { key: "details", type: "string", size: 1000 },
      { key: "deviceId", type: "string", size: 100 },
      { key: "localUuid", type: "string", size: 100, required: true, unique: true },
      { key: "serverId", type: "integer" },
      { key: "createdAt", type: "integer", required: true },
      { key: "updatedAt", type: "integer", required: true },
      { key: "deletedAt", type: "integer" },
      { key: "lastModified", type: "integer", required: true },
      { key: "version", type: "integer", required: true },
      { key: "origin", type: "string", size: 50 },
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
