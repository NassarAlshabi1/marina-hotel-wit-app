#!/usr/bin/env node
/**
 * =============================================================================
 * سكربت شامل لإضافة جميع الحقول الناقصة إلى Appwrite Cloud
 * =============================================================================
 *
 * الحقول المضافة:
 *
 * 1. employees (إنهاء الخدمة):
 *    - terminationDate (string, size=50)
 *    - terminationReason (string, size=200)
 *
 * 2. salary_withdrawals (السحوبات - حقول متوافقة مع Adapter):
 *    - withdrawDate (string, size=50)
 *    - reason (string, size=500)
 *    - hotelDayKey (string, size=50)
 *    - withdrawalType (string, size=50)
 *    - description (string, size=500)
 *    - employeeUuid (string, size=100)
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node add_all_missing_fields.js
 *
 * أو مع متغيرات بيئة كاملة:
 *   APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
 *   APPWRITE_PROJECT=690ff0da0025518570c1 \
 *   APPWRITE_API_KEY=your_key \
 *   APPWRITE_DATABASE_ID=hotel_db \
 *   node add_all_missing_fields.js
 */

const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT || "https://fra.cloud.appwrite.io/v1";
const projectId = process.env.APPWRITE_PROJECT || "690ff0da0025518570c1";
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";

if (!apiKey) {
  console.error("❌ يرجى توفير APPWRITE_API_KEY كمتغير بيئة");
  console.error("   مثال: APPWRITE_API_KEY=your_key node add_all_missing_fields.js");
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// ═══════════════════════════════════════════════════════════════
// تعريف جميع الحقول الناقصة
// ═══════════════════════════════════════════════════════════════

const MISSING_FIELDS = {
  employees: [
    { key: "terminationDate", type: "string", size: 50, required: false },
    { key: "terminationReason", type: "string", size: 200, required: false },
  ],
  salary_withdrawals: [
    { key: "withdrawDate", type: "string", size: 50, required: false },
    { key: "reason", type: "string", size: 500, required: false },
    { key: "hotelDayKey", type: "string", size: 50, required: false },
    { key: "withdrawalType", type: "string", size: 50, required: false },
    { key: "description", type: "string", size: 500, required: false },
    { key: "employeeUuid", type: "string", size: 100, required: false },
  ],
};

// ═══════════════════════════════════════════════════════════════
// دوال مساعدة
// ═══════════════════════════════════════════════════════════════

async function attributeExists(dbId, collId, key) {
  try {
    const { attributes } = await databases.listAttributes(dbId, collId);
    return attributes?.some((attr) => attr.key === key) || false;
  } catch (error) {
    console.warn(`⚠️ فشل في فحص السمات لـ ${collId}: ${error.message}`);
    return false;
  }
}

async function waitForAttribute(dbId, collId, key, maxAttempts = 15, delayMs = 2000) {
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    try {
      const { attributes } = await databases.listAttributes(dbId, collId);
      const attr = attributes?.find((a) => a.key === key);
      if (attr && attr.status === "available") {
        return true;
      }
      if (attr && attr.status === "failed") {
        console.error(`❌ السمة ${key} فشلت في الإنشاء على ${collId}`);
        return false;
      }
    } catch (error) {
      console.warn(`⚠️ محاولة ${attempt + 1} فشلت: ${error.message}`);
    }
    await sleep(delayMs);
  }
  return false;
}

async function createAttribute(dbId, collId, attr) {
  const exists = await attributeExists(dbId, collId, attr.key);
  if (exists) {
    console.log(`   ℹ️  الحقل ${attr.key} موجود مسبقاً في ${collId}`);
    return true;
  }

  try {
    switch (attr.type) {
      case "string":
        await databases.createStringAttribute(
          dbId,
          collId,
          attr.key,
          attr.size || 255,
          attr.required || false,
          attr.default ?? null,
          false, // array
          false  // encrypt
        );
        break;
      case "integer":
        await databases.createIntegerAttribute(
          dbId,
          collId,
          attr.key,
          attr.required || false,
          attr.minimum ?? null,
          attr.maximum ?? null,
          attr.default ?? null,
          false // array
        );
        break;
      case "float":
        await databases.createFloatAttribute(
          dbId,
          collId,
          attr.key,
          attr.required || false,
          attr.minimum ?? null,
          attr.maximum ?? null,
          attr.default ?? null,
          false // array
        );
        break;
      case "boolean":
        await databases.createBooleanAttribute(
          dbId,
          collId,
          attr.key,
          attr.required || false,
          attr.default ?? false,
          false // array
        );
        break;
      default:
        console.warn(`⚠️ نوع غير مدعوم: ${attr.type} للحقل ${attr.key}`);
        return false;
    }
    console.log(`   ✅ تم إنشاء الحقل ${attr.key} (${attr.type}) في ${collId}`);
    return true;
  } catch (error) {
    if (error?.code === 409) {
      console.log(`   ℹ️  الحقل ${attr.key} موجود مسبقاً (409) في ${collId}`);
      return true;
    }
    console.error(`   ❌ فشل إنشاء ${attr.key} في ${collId}: ${error.message}`);
    return false;
  }
}

// ═══════════════════════════════════════════════════════════════
// الدالة الرئيسية
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log("🚀 إضافة جميع الحقول الناقصة إلى Appwrite Cloud");
  console.log("═══════════════════════════════════════════════════");
  console.log(`   Endpoint: ${endpoint}`);
  console.log(`   Project: ${projectId}`);
  console.log(`   Database: ${databaseId}`);
  console.log("");

  let totalCreated = 0;
  let totalSkipped = 0;
  let totalFailed = 0;

  for (const [collectionId, fields] of Object.entries(MISSING_FIELDS)) {
    console.log(`📋 معالجة Collection: ${collectionId}`);
    console.log("─────────────────────────────────────────────");

    for (const field of fields) {
      const success = await createAttribute(databaseId, collectionId, field);
      if (success) {
        // انتظار بين كل حقل لتجنب Rate Limit
        await sleep(1500);
      }
    }

    console.log("");
  }

  // ═══════════════════════════════════════════════════════════════
  // انتظار تجهيز جميع السمات
  // ═══════════════════════════════════════════════════════════════
  console.log("⏳ انتظار تجهيز السمات...");
  console.log("");

  for (const [collectionId, fields] of Object.entries(MISSING_FIELDS)) {
    console.log(`📋 فحص جاهزية ${collectionId}:`);
    for (const field of fields) {
      const ready = await waitForAttribute(databaseId, collectionId, field.key);
      if (ready) {
        totalCreated++;
        console.log(`   ✅ ${field.key} جاهز`);
      } else {
        totalFailed++;
        console.log(`   ⚠️ ${field.key} قد لا يكون جاهزاً بعد`);
      }
    }
    console.log("");
  }

  // ═══════════════════════════════════════════════════════════════
  // عرض السمات الحالية لكل Collection
  // ═══════════════════════════════════════════════════════════════
  for (const collectionId of Object.keys(MISSING_FIELDS)) {
    try {
      const { attributes } = await databases.listAttributes(databaseId, collectionId);
      console.log(`📋 السمات الحالية في ${collectionId}:`);
      for (const attr of attributes) {
        console.log(`   - ${attr.key} (${attr.type}) [${attr.status}]${attr.required ? " required" : ""}`);
      }
      console.log("");
    } catch (error) {
      console.warn(`⚠️ فشل في عرض سمات ${collectionId}: ${error.message}`);
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // الملخص
  // ═══════════════════════════════════════════════════════════════
  console.log("═══════════════════════════════════════════════════");
  console.log("📊 ملخص العملية:");
  console.log(`   ✅ سمات جاهزة: ${totalCreated}`);
  console.log(`   ⚠️ سمات متأخرة: ${totalFailed}`);
  console.log("");
  console.log("ملاحظات مهمة:");
  console.log("• السمات قد تحتاج 30-60 ثانية لتكون جاهزة (Indexing)");
  console.log("• لا تُجرِ مزامنة حتى تكتمل عملية الـ Indexing");
  console.log("• تحقق من Appwrite Console: https://cloud.appwrite.io/console");
  console.log("═══════════════════════════════════════════════════");
}

main().catch((error) => {
  console.error("❌ خطأ عام:", error);
  process.exit(1);
});
