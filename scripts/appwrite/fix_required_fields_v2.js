const { Client, Databases } = require("node-appwrite");

const endpoint = "https://fra.cloud.appwrite.io/v1";
const projectId = "690ff0da0025518570c1";
const databaseId = "hotel_db";
const apiKey = "standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da";

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

// الحقول التي سنحذفها ونعيد إنشائها كـ optional (required=false)
const fieldsToFix = [
  // salary_cycles
  { collection: 'salary_cycles', key: 'startDate', type: 'string', default: '' },
  { collection: 'salary_cycles', key: 'endDate', type: 'string', default: '' },
  
  // salary_payments  
  { collection: 'salary_payments', key: 'employeeId', type: 'integer', default: 0 },
  { collection: 'salary_payments', key: 'paymentDate', type: 'string', default: '' },
  
  // payments
  { collection: 'payments', key: 'sync_version', type: 'integer', default: 1 },
  { collection: 'payments', key: 'sync_vector_clock', type: 'string', default: '{}' },
  
  // debts
  { collection: 'debts', key: 'vector_clock', type: 'string', default: '{}' },
  { collection: 'debts', key: 'sync_version', type: 'integer', default: 1 },
  { collection: 'debts', key: 'sync_origin', type: 'string', default: 'mobile' },
  { collection: 'debts', key: 'sync_vector_clock', type: 'string', default: '{}' },
  
  // booking_notes
  { collection: 'booking_notes', key: 'bookingUuid', type: 'string', default: '' },
  { collection: 'booking_notes', key: 'note', type: 'string', default: '' },
  
  // rooms
  { collection: 'rooms', key: 'basePrice', type: 'double', default: 0 },
  { collection: 'rooms', key: 'floor', type: 'integer', default: 0 },
  
  // shift_notes
  { collection: 'shift_notes', key: 'shiftDate', type: 'string', default: '' },
  { collection: 'shift_notes', key: 'note', type: 'string', default: '' },
];

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function fixFields() {
  console.log("🔧 بدء إصلاح الحقول المطلوبة...\n");
  console.log("⚠️ تحذير: سيتم حذف وإعادة إنشاء الحقول التالية:\n");
  
  for (const field of fieldsToFix) {
    console.log(`  - ${field.collection}.${field.key}`);
  }
  console.log("");
  
  let success = 0;
  let failed = 0;
  
  for (const field of fieldsToFix) {
    try {
      console.log(`\n📝 معالجة: ${field.collection}.${field.key}`);
      
      // 1. حذف الحقل
      console.log(`   🗑️ حذف الحقل...`);
      try {
        await databases.deleteAttribute(
          databaseId,
          field.collection,
          field.key
        );
        console.log(`   ✅ تم حذف الحقل`);
        await sleep(1000); // انتظار قبل إعادة الإنشاء
      } catch (deleteError) {
        if (!deleteError.message.includes('not found') && !deleteError.message.includes('attribute_not_found')) {
          console.log(`   ⚠️ لم يتم الحذف (ربما غير موجود): ${deleteError.message}`);
        } else {
          console.log(`   ℹ️ الحقل غير موجود مسبقاً`);
        }
      }
      
      // 2. إعادة إنشاء الحقل كـ optional
      console.log(`   ➕ إنشاء الحقل كـ optional...`);
      await sleep(500);
      
      switch (field.type) {
        case 'string':
          await databases.createStringAttribute(
            databaseId,
            field.collection,
            field.key,
            500, // size
            false, // required = false ✅
            field.default,
            false // array
          );
          break;
        case 'integer':
          await databases.createIntegerAttribute(
            databaseId,
            field.collection,
            field.key,
            false, // required = false ✅
            field.default ? parseInt(field.default) : null,
            false // array
          );
          break;
        case 'double':
          await databases.createFloatAttribute(
            databaseId,
            field.collection,
            field.key,
            false, // required = false ✅
            field.default ? parseFloat(field.default) : null,
            false // array
          );
          break;
        case 'boolean':
          await databases.createBooleanAttribute(
            databaseId,
            field.collection,
            field.key,
            false, // required = false ✅
            field.default === 'true',
            false // array
          );
          break;
      }
      
      console.log(`   ✅✅ تم إصلاح: ${field.collection}.${field.key} (required=false)`);
      success++;
      
    } catch (error) {
      console.log(`   ❌ فشل: ${error.message}`);
      failed++;
    }
    
    await sleep(500);
  }
  
  console.log("\n" + "=".repeat(60));
  console.log("📊 النتيجة النهائية:");
  console.log("=".repeat(60));
  console.log(`  ✅ نجح: ${success}`);
  console.log(`  ❌ فشل: ${failed}`);
  console.log("");
  
  if (failed === 0) {
    console.log("🎉 تم إصلاح جميع الحقول بنجاح!");
  } else {
    console.log("⚠️ بعض الحقول فشلت، تحقق من الأخطاء أعلاه.");
  }
}

// تأكيد قبل التنفيذ
console.log("⚠️⚠️⚠️ تنبيه هام ⚠️⚠️⚠️");
console.log("هذا السكربت سيحذف ويعيد إنشاء الحقول.");
console.log("إذا كانت هناك بيانات في هذه الحقول، قد تُفقد.");
console.log("");
console.log("ابدأ التنفيذ...");
console.log("");

fixFields();
