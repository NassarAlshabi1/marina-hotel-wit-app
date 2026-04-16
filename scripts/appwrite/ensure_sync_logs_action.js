const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT;
const projectId = process.env.APPWRITE_PROJECT;
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";
const collectionId = process.env.APPWRITE_SYNC_LOGS_COLLECTION || "sync_logs";

if (!endpoint || !projectId || !apiKey) {
  console.error("Please set APPWRITE_ENDPOINT, APPWRITE_PROJECT, APPWRITE_API_KEY (and optionally APPWRITE_DATABASE_ID)");
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

async function ensureActionAttribute() {
  try {
    const { attributes } = await databases.listAttributes(databaseId, collectionId);
    const actionAttr = attributes?.find((attr) => attr.key === "action");

    if (actionAttr) {
      if (actionAttr.required) {
        await databases.updateStringAttribute(
          databaseId,
          collectionId,
          "action",
          actionAttr.size || 255,
          false,
          actionAttr.default ?? null,
          actionAttr.array || false
        );
        console.log("✔ Attribute 'action' marked as optional");
      } else {
        console.log("✔ Attribute 'action' already exists and is optional");
      }
      return;
    }
  } catch (error) {
    if (error?.code !== 404) {
      console.error("✖ Failed to inspect existing attributes:", error.response || error);
      process.exit(1);
    }
  }

  try {
    await databases.createStringAttribute(
      databaseId,
      collectionId,
      "action",
      255,
      false,
      null,
      false,
      false
    );
    console.log("✔ Created attribute 'action' on sync_logs collection");
  } catch (error) {
    console.error("✖ Failed to create attribute 'action':", error.response || error);
    process.exit(1);
  }
}

ensureActionAttribute()
  .then(() => console.log("✓ Sync logs attribute check complete."))
  .catch((error) => {
    console.error("✖ Unexpected error:", error.response || error);
    process.exit(1);
  });
