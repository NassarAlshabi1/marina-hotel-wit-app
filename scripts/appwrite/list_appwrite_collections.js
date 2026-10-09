const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT;
const projectId = process.env.APPWRITE_PROJECT;
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";

if (!endpoint || !projectId || !apiKey) {
  console.error("Please set APPWRITE_ENDPOINT, APPWRITE_PROJECT, APPWRITE_API_KEY(, APPWRITE_DATABASE_ID)");
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

(async () => {
  try {
    const { collections } = await databases.listCollections(databaseId);
    console.log(`Database: ${databaseId}`);
    for (const collection of collections) {
      const { indexes } = await databases.listIndexes(databaseId, collection.$id);
      const uniqueAttributes = new Set(
        indexes?.indexes
          ?.filter((idx) => idx.type === "unique")
          .flatMap((idx) => idx.attributes || []) ?? []
      );

      console.log(`\nCollection ID: ${collection.$id}`);
      console.log(`Name        : ${collection.name}`);
      console.log(`Attributes  : ${collection.attributes?.length || 0}`);
      if (collection.attributes) {
        collection.attributes.forEach((attr) => {
          console.log(
            `  - ${attr.key} (${attr.type}) required=${attr.required} array=${attr.array ?? false} unique=${uniqueAttributes.has(attr.key)}`
          );
        });
      }
      console.log(`Indexes     : ${indexes?.indexes?.length || 0}`);
      indexes?.indexes?.forEach((idx) => {
        console.log(`  - ${idx.key} (${idx.type}) -> [${idx.attributes.join(", ")}]`);
      });
    }
  } catch (error) {
    console.error("Failed to list collections/indexes:", error);
    process.exit(1);
  }
})();
