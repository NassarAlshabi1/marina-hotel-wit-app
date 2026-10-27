const { Client, Databases, Query } = require("node-appwrite");
const fs = require("fs");
const path = require("path");

const endpoint = "https://fra.cloud.appwrite.io/v1";
const projectId = "6a2b01d0000752ce97e7";
const apiKey = "standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d";
const databaseId = "6a2b030d000445596163";

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

const args = process.argv.slice(2);
const targetCollection = args.find((a) => !a.startsWith("--"));
const concurrency = parseInt(args.find((a) => a.startsWith("--concurrency="))?.split("=")[1] || "10", 10);
const SPLIT_DIR = "/home/daytona/project/scripts/appwrite/backup_splits";

async function fetchValidFields(collectionId) {
  const fields = new Set();
  let offset = 0;
  while (true) {
    const res = await databases.listAttributes(databaseId, collectionId, [
      Query.limit(100),
      Query.offset(offset),
    ]);
    for (const attr of res.attributes) {
      fields.add(attr.key);
    }
    if (res.attributes.length < 100) break;
    offset += res.attributes.length;
  }
  return fields;
}

function filterRecord(record, validFields) {
  const out = {};
  for (const key of Object.keys(record)) {
    if (key === "$id") continue;
    if (validFields.has(key)) {
      out[key] = record[key];
    }
  }
  return out;
}

async function createDocument(collectionId, documentId, data) {
  return await databases.createDocument(databaseId, collectionId, documentId, data);
}

async function processCollection(filePath, validFields) {
  const data = JSON.parse(fs.readFileSync(filePath, "utf8"));
  const collectionName = data.collection;
  const records = data.records || [];
  const collectionId = collectionName;

  console.log(`\n=== ${collectionName} (${records.length} records) ===`);

  if (records.length === 0) {
    console.log("  (empty, skipping)");
    return { created: 0, skipped: 0, failed: 0 };
  }

  let created = 0;
  let skipped = 0;
  let failed = 0;

  for (let i = 0; i < records.length; i += concurrency) {
    const chunk = records.slice(i, i + concurrency);
    const results = await Promise.allSettled(
      chunk.map(async (record) => {
        const documentId = record.$id || record.localUuid;
        if (!documentId) {
          throw new Error("No document ID found in record");
        }
        const payload = filterRecord(record, validFields);
        await createDocument(collectionId, documentId, payload);
      })
    );

    for (const r of results) {
      if (r.status === "fulfilled") {
        created++;
      } else {
        const msg = r.reason?.message || "";
        if (msg.includes("already exists") || msg.includes("409")) {
          skipped++;
        } else {
          failed++;
          if (failed <= 5) {
            console.error(`  ✖ Error: ${msg}`);
          }
        }
      }
    }

    if ((i + concurrency) % 1000 === 0 || i + concurrency >= records.length) {
      console.log(`  Progress: ${Math.min(i + concurrency, records.length)}/${records.length} (created: ${created}, skipped: ${skipped}, failed: ${failed})`);
    }
  }

  console.log(`  Done: created=${created}, skipped=${skipped}, failed=${failed}`);
  return { created, skipped, failed };
}

async function main() {
  if (!fs.existsSync(SPLIT_DIR)) {
    console.error("Split directory not found:", SPLIT_DIR);
    console.error("Run split_backup.js first.");
    process.exit(1);
  }

  let files = fs.readdirSync(SPLIT_DIR).filter((f) => f.endsWith(".json"));
  files.sort();

  if (targetCollection) {
    files = files.filter((f) => path.basename(f, ".json") === targetCollection);
    if (files.length === 0) {
      console.error("Collection not found:", targetCollection);
      process.exit(1);
    }
  }

  console.log(`Found ${files.length} collection file(s) in ${SPLIT_DIR}`);
  console.log(`Concurrency: ${concurrency}`);

  // Pre-fetch valid fields for all target collections
  const fieldCache = {};
  for (const file of files) {
    const collectionName = path.basename(file, ".json");
    console.log(`Fetching schema for ${collectionName}...`);
    try {
      fieldCache[collectionName] = await fetchValidFields(collectionName);
      console.log(`  ✔ ${fieldCache[collectionName].size} fields`);
    } catch (e) {
      console.error(`  ✖ Failed to fetch schema for ${collectionName}: ${e.message}`);
      process.exit(1);
    }
  }

  let totalCreated = 0;
  let totalSkipped = 0;
  let totalFailed = 0;

  for (const file of files) {
    const filePath = path.join(SPLIT_DIR, file);
    const collectionName = path.basename(file, ".json");
    const result = await processCollection(filePath, fieldCache[collectionName]);
    totalCreated += result.created;
    totalSkipped += result.skipped;
    totalFailed += result.failed;
  }

  console.log(`\n=== SUMMARY ===`);
  console.log(`Created:  ${totalCreated}`);
  console.log(`Skipped:  ${totalSkipped}`);
  console.log(`Failed:   ${totalFailed}`);
  console.log(`Total:    ${totalCreated + totalSkipped + totalFailed}`);
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
