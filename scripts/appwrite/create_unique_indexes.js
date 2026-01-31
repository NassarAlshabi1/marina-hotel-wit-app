const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT;
const projectId = process.env.APPWRITE_PROJECT;
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";

if (!endpoint || !projectId || !apiKey) {
  console.error("Please set APPWRITE_ENDPOINT, APPWRITE_PROJECT, APPWRITE_API_KEY (and optionally APPWRITE_DATABASE_ID)");
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

const collectionIndexes = {
  rooms: ["roomNumber", "localUuid"],
  bookings: ["localUuid"],
  booking_notes: ["localUuid"],
  booking_nights: ["localUuid"],
  payments: ["localUuid"],
  expenses: ["localUuid"],
  cash_transactions: ["localUuid"],
  employees: ["localUuid"],
  debts: ["localUuid"],
  salary_cycles: ["localUuid"],
  salary_payments: ["localUuid"],
  hotel_day_ledger: ["localUuid", "hotelDayKey"],
  devices: ["localUuid"],
  sync_logs: ["localUuid"],
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
      console.log(`Waiting for attribute ${collectionId}.${attributeKey} (status: ${status}) [attempt ${attempt + 1}/${WAIT_ATTEMPTS}]`);
    } catch (error) {
      if (error?.code === 404) {
        console.warn(`Attribute ${collectionId}.${attributeKey} not found yet [attempt ${attempt + 1}/${WAIT_ATTEMPTS}]`);
      } else {
        console.warn(`Cannot fetch attribute ${collectionId}.${attributeKey} [attempt ${attempt + 1}/${WAIT_ATTEMPTS}]:`, error.message || error);
      }
    }
    await sleep(WAIT_DELAY_MS);
  }
  return false;
}

async function ensureUniqueIndex(collectionId, attributeKey) {
  try {
    const { indexes } = await databases.listIndexes(databaseId, collectionId);
    if (indexes?.some((idx) => idx.type === "unique" && idx.attributes?.length === 1 && idx.attributes[0] === attributeKey)) {
      console.log(`✔ Unique index already exists on ${collectionId}.${attributeKey}`);
      return;
    }
    const indexKey = `idx_${collectionId}_${attributeKey}`;
    await databases.createIndex(databaseId, collectionId, indexKey, "unique", [attributeKey]);
    console.log(`✔ Created unique index ${indexKey}`);
  } catch (error) {
    if (error?.code === 409) {
      console.warn(`⚠ Unique index already exists on ${collectionId}.${attributeKey}`);
    } else {
      console.error(`✖ Failed to create unique index on ${collectionId}.${attributeKey}:`, error.response || error);
    }
  }
}

(async () => {
  for (const [collectionId, attributes] of Object.entries(collectionIndexes)) {
    for (const attributeKey of attributes) {
      const ready = await waitForAttribute(collectionId, attributeKey);
      if (!ready) {
        console.warn(`⚠ Attribute ${collectionId}.${attributeKey} is not ready after waiting; skipping index creation.`);
        continue;
      }
      await ensureUniqueIndex(collectionId, attributeKey);
      await sleep(500);
    }
  }
  console.log("✅ Finished processing unique indexes.");
})();
