const { Client, Databases, Query } = require("node-appwrite");

const endpoint = "https://fra.cloud.appwrite.io/v1";
const projectId = "690ff0da0025518570c1";
const databaseId = "hotel_db";
const apiKey = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da";

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

// جميع الجداول التي نريد التحقق منها
const collectionsToCheck = [
  'salary_cycles',
  'salary_payments', 
  'payments',
  'debts',
  'booking_notes',
  'rooms',
  'shift_notes',
  'bookings',
  'employees',
  'expenses',
  'cash_transactions',
  'booking_nights',
];

async function checkData() {
  console.log("🔍 التحقق من البيانات والحقول المطلوبة...\n");
  console.log("=".repeat(80));
  
  for (const collectionId of collectionsToCheck) {
    try {
      console.log(`\n📋 ${collectionId}:`);
      
      // جلب بعض المستندات
      const result = await databases.listDocuments(
        databaseId,
        collectionId,
        [Query.limit(3)]
      );
      
      console.log(`   📊 إجمالي المستندات: ${result.total}`);
      
      if (result.documents.length > 0) {
        console.log(`   📝 عينة من الحقول:`);
        const doc = result.documents[0];
        const keys = Object.keys(doc).filter(k => !k.startsWith('$')).sort();
        
        // تحديد الحقول المطلوبة (required) المحتملة
        const requiredFields = [];
        for (const key of keys) {
          const value = doc[key];
          // الحقول التي قد تكون مطلوبة
          if (key.includes('Date') || key.includes('Uuid') || key.includes('Id') || 
              key.includes('version') || key.includes('clock') || key.includes('origin')) {
            if (value === null || value === '' || value === undefined) {
              requiredFields.push(key);
            }
          }
        }
        
        console.log(`      الحقول: ${keys.slice(0, 15).join(', ')}`);
        if (requiredFields.length > 0) {
          console.log(`      ⚠️ حقول قد تكون مطلوبة وفارغة: ${requiredFields.join(', ')}`);
        }
      } else {
        console.log(`   ℹ️ لا توجد مستندات`);
      }
      
    } catch (error) {
      console.log(`   ❌ خطأ: ${error.message}`);
    }
  }
  
  console.log("\n" + "=".repeat(80));
  console.log("✅ انتهى الفحص");
}

checkData().catch(console.error);
