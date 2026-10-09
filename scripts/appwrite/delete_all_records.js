const { Client, Databases, Query } = require("node-appwrite");

const endpoint = "https://fra.cloud.appwrite.io/v1";
const projectId = "6a2b01d0000752ce97e7";
const apiKey = "standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d";
const databaseId = "hotel_db";

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

async function listCollections() {
  const collections = [];
  let offset = 0;
  while (true) {
    const res = await databases.listCollections(projectId, [
      Query.limit(100),
      Query.offset(offset),
    ]);
    collections.push(...res.collections);
    if (res.collections.length < 100) break;
    offset += res.collections.length;
  }
  return collections;
}

async function listDocumentIds(databaseId, collectionId) {
  const ids = [];
  let offset = 0;
  while (true) {
    const res = await databases.listDocuments(databaseId, collectionId, [
      Query.limit(100),
      Query.offset(offset),
      Query.select(["$id"]),
    ]);
    ids.push(...res.documents.map((d) => d.$id));
    if (res.documents.length < 100) break;
    offset += res.documents.length;
  }
  return ids;
}

async function deleteDocuments(databaseId, collectionId, ids) {
  let deleted = 0;
  let failed = 0;
  for (const id of ids) {
    try {
      await databases.deleteDocument(databaseId, collectionId, id);
      deleted++;
    } catch (e) {
      failed++;
      console.error(`  ✖ Failed to delete ${collectionId}/${id}: ${e.message || e}`);
    }
  }
  return { deleted, failed };
}

async function main() {
  console.log("=== Fetching collections ===");
  const collections = await listCollections();
  console.log(`Found ${collections.length} collections\n`);

  for (const col of collections) {
    const name = col.name || col.$id;
    console.log(`--- Collection: ${name} (${col.$id}) ---`);
    const ids = await listDocumentIds(databaseId, col.$id);
    console.log(`  Documents to delete: ${ids.length}`);
    if (ids.length === 0) {
      console.log("  (empty, skipping)\n");
      continue;
    }
    const { deleted, failed } = await deleteDocuments(databaseId, col.$id, ids);
    console.log(`  ✔ Deleted: ${deleted}, Failed: ${failed}\n`);
  }

  console.log("=== Done ===");
}

main().catch((e) => {
  console.error("Fatal:", e);
  process.exit(1);
});
