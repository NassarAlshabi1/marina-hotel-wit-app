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

// الحقول التي يجب أن تكون required=false (لأنها قد لا تكون موجودة في البيانات المحلية)
const fieldsToMakeOptional = {
  salary_cycles: ['startDate', 'endDate'],
  salary_payments: ['employeeId', 'paymentDate'],
  payments: ['sync_version', 'sync_vector_clock'],
  debts: ['vector_clock', 'sync_version', 'sync_origin', 'sync_vector_clock'],
  booking_notes: ['bookingUuid', 'note'],
  rooms: ['basePrice', 'floor'],
  shift_notes: ['shiftDate', 'note'],
};

// الحقول المطلوبة التي يجب أن تبقى required=true
const requiredFields = {
  salary_cycles: ['localUuid', 'createdAt', 'updatedAt', 'lastModified', 'employeeId', 'cycleKey'],
  salary_payments: ['localUuid', 'createdAt', 'updatedAt', 'lastModified', 'cycleId', 'paymentDateIso'],
  payments: ['localUuid', 'createdAt', 'updatedAt', 'lastModified', 'amount', 'paymentDate', 'paymentMethod', 'revenueType'],
  debts: ['localUuid', 'createdAt', 'updatedAt', 'lastModified', 'guestName', 'checkinDate', 'totalAmount', 'paidAmount'],
  booking_notes: ['localUuid', 'createdAt', 'updatedAt', 'lastModified', 'bookingId', 'noteText', 'alertType'],
  rooms: ['localUuid', 'createdAt', 'updatedAt', 'lastModified', 'roomNumber', 'type', 'price', 'status'],
  shift_notes: ['localUuid', 'createdAt', 'updatedAt', 'lastModified', 'isRead'],
};

async function analyzeAndFix() {
  console.log("🔍 بدء التحليل الشامل للحقول المطلوبة...\n");
  console.log("=" .repeat(80));

  try {
    const { collections } = await databases.listCollections(databaseId);
    
    for (const collection of collections) {
      const collectionId = collection.$id;
      
      // فقط الجداول التي حددناها
      if (!fieldsToMakeOptional[collectionId] && !requiredFields[collectionId]) {
        continue;
      }
      
      console.log(`\n📋 الجدول: ${collectionId}`);
      console.log("-".repeat(60));
      
      // الحصول على الحقول الحالية
      const attrs = collection.attributes || [];
      const problematicFields = [];
      
      for (const attr of attrs) {
        if (attr.required === true) {
          // تحقق إذا كان هذا الحقل يجب أن يكون optional
          if (fieldsToMakeOptional[collectionId]?.includes(attr.key)) {
            problematicFields.push({
              key: attr.key,
              type: attr.type,
              issue: 'should_be_optional',
              action: 'update_required_false'
            });
          }
        }
      }
      
      if (problematicFields.length === 0) {
        console.log("  ✅ جميع الحقول المطلوبة صحيحة");
      } else {
        console.log("  ⚠️ حقول تحتاج تعديل:");
        for (const field of problematicFields) {
          console.log(`     - ${field.key} (${field.type}) → يجب أن يكون required=false`);
        }
      }
    }
    
    console.log("\n" + "=".repeat(80));
    console.log("📝 ملخص التعديلات المطلوبة:");
    console.log("=".repeat(80));
    
    // لا يمكن تعديل required عبر API مباشرة، يجب حذف وإعادة إنشاء
    console.log("\n⚠️ ملاحظة: Appwrite لا يدعم تعديل required مباشرة.");
    console.log("الحل: إنشاء سكربت لحذف وإعادة إنشاء الحقول.\n");
    
  } catch (error) {
    console.error("❌ خطأ:", error.message);
  }
}

// دالة لإنشاء حقل جديد (إذا لم يكن موجوداً)
async function ensureAttribute(collectionId, key, type, required, defaultValue) {
  try {
    // محاولة إنشاء الحقل
    switch (type) {
      case 'string':
        await databases.createStringAttribute(
          databaseId,
          collectionId,
          key,
          500, // size
          required,
          defaultValue,
          false // array
        );
        console.log(`  ✅ تم إنشاء الحقل: ${key}`);
        break;
      case 'integer':
        await databases.createIntegerAttribute(
          databaseId,
          collectionId,
          key,
          required,
          defaultValue ? parseInt(defaultValue) : null,
          false // array
        );
        console.log(`  ✅ تم إنشاء الحقل: ${key}`);
        break;
      case 'boolean':
        await databases.createBooleanAttribute(
          databaseId,
          collectionId,
          key,
          required,
          defaultValue === 'true',
          false // array
        );
        console.log(`  ✅ تم إنشاء الحقل: ${key}`);
        break;
    }
  } catch (error) {
    if (error.message.includes('already exists')) {
      console.log(`  ℹ️ الحقل موجود مسبقاً: ${key}`);
    } else {
      console.log(`  ❌ خطأ في إنشاء ${key}: ${error.message}`);
    }
  }
}

// تشغيل التحليل
analyzeAndFix();
