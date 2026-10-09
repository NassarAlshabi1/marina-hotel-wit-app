const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT;
const projectId = process.env.APPWRITE_PROJECT;
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";

if (!endpoint || !projectId || !apiKey) {
  console.error(
    "Please set APPWRITE_ENDPOINT, APPWRITE_PROJECT, APPWRITE_API_KEY (and optionally APPWRITE_DATABASE_ID)"
  );
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

const indexDefinitions = {
  rooms: [
    { key: "idx_rooms_status", attributes: ["status"] },
    { key: "idx_rooms_type", attributes: ["type"] },
    { key: "idx_rooms_serverId", attributes: ["serverId"] },
    { key: "idx_rooms_lastModified", attributes: ["lastModified"] },
  ],
  bookings: [
    { key: "idx_bookings_status", attributes: ["status"] },
    { key: "idx_bookings_roomNumber", attributes: ["roomNumber"] },
    { key: "idx_bookings_guestPhone", attributes: ["guestPhone"] },
    { key: "idx_bookings_checkinDate", attributes: ["checkinDate"] },
    { key: "idx_bookings_serverBookingId", attributes: ["serverBookingId"] },
  ],
  payments: [
    { key: "idx_payments_bookingLocalId", attributes: ["bookingLocalId"] },
    { key: "idx_payments_serverBookingId", attributes: ["serverBookingId"] },
    { key: "idx_payments_roomNumber", attributes: ["roomNumber"] },
    { key: "idx_payments_paymentDate", attributes: ["paymentDate"] },
  ],
  expenses: [
    { key: "idx_expenses_date", attributes: ["date"] },
    { key: "idx_expenses_expenseType", attributes: ["expenseType"] },
  ],
  employees: [
    { key: "idx_employees_status", attributes: ["status"] },
    { key: "idx_employees_phone", attributes: ["phone"] },
  ],
  debts: [
    { key: "idx_debts_status", attributes: ["status"] },
    { key: "idx_debts_debtorName", attributes: ["debtorName"] },
  ],
  devices: [
    { key: "idx_devices_deviceName", attributes: ["deviceName"] },
    { key: "idx_devices_status", attributes: ["status"] },
    { key: "idx_devices_deviceType", attributes: ["deviceType"] },
  ],
  sync_logs: [
    { key: "idx_sync_logs_deviceId", attributes: ["deviceId"] },
    { key: "idx_sync_logs_status", attributes: ["status"] },
    { key: "idx_sync_logs_timestamp", attributes: ["timestamp"] },
  ],
};

const WAIT_ATTEMPTS = parseInt(process.env.APPWRITE_WAIT_ATTEMPTS || "20", 10);
const WAIT_DELAY_MS = parseInt(process.env.APPWRITE_WAIT_DELAY_MS || "2000", 10);
const READY_STATUSES = new Set(["available", "active", "ready", "synced", "processed"]);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function waitForAttribute(collectionId, attributeKey) {
  for (let attempt = 0; attempt < WAIT_ATTEMPTS; attempt++) {
    try {
      const attribute = await databases.getAttribute(databaseId, collectionId, attributeKey);
      const status = String(attribute?.status ?? "available").toLowerCase();
      if (!attribute || READY_STATUSES.has(status)) {
        return true;
      }
      console.log(
        `Waiting for attribute ${collectionId}.${attributeKey} (status: ${status}) [attempt ${attempt + 1}/${WAIT_ATTEMPTS}]`
      );
    } catch (error) {
      if (error?.code === 404) {
        console.warn(
          `Attribute ${collectionId}.${attributeKey} not found yet [attempt ${attempt + 1}/${WAIT_ATTEMPTS}]`
        );
      } else {
        console.warn(
          `Cannot fetch attribute ${collectionId}.${attributeKey} [attempt ${attempt + 1}/${WAIT_ATTEMPTS}]:`,
          error.message || error
        );
      }
    }
    await sleep(WAIT_DELAY_MS);
  }
  return false;
}

async function ensureIndex(collectionId, { key, attributes, type = "key", orders = [], lengths = [] }) {
  try {
    const { indexes } = await databases.listIndexes(databaseId, collectionId);
    if (indexes?.some((idx) => idx.key === key)) {
      console.log(`✔ Index ${key} already exists on ${collectionId}`);
      return;
    }

    for (const attributeKey of attributes) {
      const ready = await waitForAttribute(collectionId, attributeKey);
      if (!ready) {
        console.warn(
          `⚠ Attribute ${collectionId}.${attributeKey} is not ready after waiting; skipping index ${key}.`
        );
        return;
      }
    }

    await databases.createIndex(
      databaseId,
      collectionId,
      key,
      type,
      attributes,
      orders,
      lengths
    );
    console.log(`✔ Created ${type} index ${key} on ${collectionId}`);
  } catch (error) {
    if (error?.code === 409) {
      console.warn(`⚠ Index ${key} already exists on ${collectionId}`);
    } else {
      console.error(`✖ Failed to create index ${key} on ${collectionId}:`, error.response || error);
    }
  }
}

(async () => {
  for (const [collectionId, indexes] of Object.entries(indexDefinitions)) {
    for (const index of indexes) {
      await ensureIndex(collectionId, index);
      await sleep(300);
    }
  }
  console.log("✅ Finished processing mobile indexes.");
})();
