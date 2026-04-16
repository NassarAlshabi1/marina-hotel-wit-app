const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1';
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

if (!apiKey) {
  console.error("❌ Missing APPWRITE_API_KEY environment variable");
  console.error("Usage: APPWRITE_API_KEY=your_api_key node add_discount_field.js");
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

async function addDiscountField() {
  console.log("🔧 Adding discount field to bookings collection...");
  console.log(`   Endpoint: ${endpoint}`);
  console.log(`   Project: ${projectId}`);
  console.log(`   Database: ${databaseId}`);
  
  try {
    // Check if attribute already exists
    const { attributes } = await databases.listAttributes(databaseId, 'bookings');
    const discountExists = attributes.some(attr => attr.key === 'discount');
    
    if (discountExists) {
      console.log("✅ Discount field already exists in bookings collection");
      return;
    }
    
    // Add the discount attribute (float/double type)
    await databases.createFloatAttribute(
      databaseId,
      'bookings',
      'discount',
      false,  // required
      0,      // default value
      null,   // min
      null,   // max
      false   // array
    );
    
    console.log("✅ Successfully added 'discount' field to bookings collection");
    console.log("   Type: float");
    console.log("   Default: 0");
    console.log("   Required: false");
    
  } catch (error) {
    if (error.code === 409) {
      console.log("✅ Discount field already exists (conflict)");
    } else {
      console.error("❌ Error adding discount field:", error.message);
      if (error.response) {
        console.error("   Response:", JSON.stringify(error.response, null, 2));
      }
      process.exit(1);
    }
  }
}

addDiscountField();
