const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT;
const projectId = process.env.APPWRITE_PROJECT;
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";
const roomsCollectionId = process.env.APPWRITE_ROOMS_COLLECTION_ID || "rooms";
const targetStatus = process.env.APPWRITE_ROOM_STATUS || "شاغرة";

if (!endpoint || !projectId || !apiKey) {
  console.error(
    "Please set APPWRITE_ENDPOINT, APPWRITE_PROJECT, APPWRITE_API_KEY (and optionally APPWRITE_DATABASE_ID, APPWRITE_ROOMS_COLLECTION_ID, APPWRITE_ROOM_STATUS)"
  );
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

async function updateAllRooms() {
  let cursor = undefined;
  let totalUpdated = 0;
  while (true) {
    const page = await databases.listDocuments(databaseId, roomsCollectionId, {
      limit: 100,
      cursor,
    });

    if (!page.documents.length) break;

    for (const doc of page.documents) {
      try {
        await databases.updateDocument(databaseId, roomsCollectionId, doc.$id, {
          status: targetStatus,
        });
        totalUpdated += 1;
        console.log(`✅ Updated room ${doc.$id} -> status='${targetStatus}'`);
      } catch (err) {
        console.error(`❌ Failed to update room ${doc.$id}:`, err?.message || err);
      }
    }

    if (!page.cursor) break;
    cursor = page.cursor;
  }
  console.log(`Done. Total rooms updated: ${totalUpdated}`);
}

updateAllRooms().catch((err) => {
  console.error("Unexpected error:", err?.message || err);
  process.exit(1);
});
