#!/usr/bin/env node
/**
 * إضافة حقول terminationDate و terminationReason إلى مجموعة employees في Appwrite Cloud
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node add_termination_fields.js
 *
 * أو مع متغيرات بيئة كاملة:
 *   APPWRITE_ENDPOINT=https://fra.cloud.appwrite.io/v1 \
 *   APPWRITE_PROJECT=690ff0da0025518570c1 \
 *   APPWRITE_API_KEY=your_key \
 *   APPWRITE_DATABASE_ID=hotel_db \
 *   node add_termination_fields.js
 */

const { Client, Databases } = require("node-appwrite");

const endpoint = process.env.APPWRITE_ENDPOINT || "https://fra.cloud.appwrite.io/v1";
const projectId = process.env.APPWRITE_PROJECT || "690ff0da0025518570c1";
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || "hotel_db";
const collectionId = "employees";

if (!apiKey) {
  console.error("❌ يرجى توفير APPWRITE_API_KEY كمتغير بيئة");
  console.error("   مثال: APPWRITE_API_KEY=your_key node add_termination_fields.js");
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

async function attributeExists(dbId, collId, key) {
  try {
    const { attributes } = await databases.listAttributes(dbId, collId);
    return attributes?.some((attr) => attr.key === key) || false;
  } catch (error) {
    console.warn(`⚠️ فشل في فحص السمات: ${error.message}`);
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
        console.error(`❌ السمة ${key} فشلت في الإنشاء`);
        return false;
      }
    } catch (error) {
      console.warn(`⚠️ محاولة ${attempt + 1} فشلت: ${error.message}`);
    }
    await sleep(delayMs);
  }
  return false;
}

async function addTerminationFields() {
  console.log("🔄 إضافة حقول إنهاء الخدمة إلى مجموعة employees...");
  console.log(`   Endpoint: ${endpoint}`);
  console.log(`   Project: ${projectId}`);
  console.log(`   Database: ${databaseId}`);
  console.log(`   Collection: ${collectionId}`);
  console.log("");

  // فحص السمات الموجودة
  const existingTerminationDate = await attributeExists(databaseId, collectionId, "terminationDate");
  const existingTerminationReason = await attributeExists(databaseId, collectionId, "terminationReason");

  // إضافة terminationDate
  if (existingTerminationDate) {
    console.log("✔ السمة terminationDate موجودة بالفعل");
  } else {
    try {
      await databases.createStringAttribute(
        databaseId,
        collectionId,
        "terminationDate",
        50,    // size
        false, // required
        null,  // default
        false, // array
        false  // encrypt
      );
      console.log("✔ تم إنشاء السمة terminationDate");
    } catch (error) {
      if (error?.code === 409) {
        console.log("✔ السمة terminationDate موجودة بالفعل (409)");
      } else {
        console.error(`❌ فشل إنشاء terminationDate: ${error.message}`);
      }
    }
  }

  // إضافة terminationReason
  if (existingTerminationReason) {
    console.log("✔ السمة terminationReason موجودة بالفعل");
  } else {
    try {
      await databases.createStringAttribute(
        databaseId,
        collectionId,
        "terminationReason",
        500,   // size
        false, // required
        null,  // default
        false, // array
        false  // encrypt
      );
      console.log("✔ تم إنشاء السمة terminationReason");
    } catch (error) {
      if (error?.code === 409) {
        console.log("✔ السمة terminationReason موجودة بالفعل (409)");
      } else {
        console.error(`❌ فشل إنشاء terminationReason: ${error.message}`);
      }
    }
  }

  // انتظار حتى تكون السمات جاهزة
  console.log("");
  console.log("⏳ انتظار تجهيز السمات...");

  const dateReady = await waitForAttribute(databaseId, collectionId, "terminationDate");
  const reasonReady = await waitForAttribute(databaseId, collectionId, "terminationReason");

  if (dateReady && reasonReady) {
    console.log("✅ جميع السمات جاهزة للاستخدام!");
  } else {
    console.log("⚠️ بعض السمات قد لا تكون جاهزة بعد. تحقق من لوحة تحكم Appwrite.");
  }

  // عرض السمات الحالية
  try {
    const { attributes } = await databases.listAttributes(databaseId, collectionId);
    console.log("");
    console.log("📋 السمات الحالية في مجموعة employees:");
    for (const attr of attributes) {
      console.log(`   - ${attr.key} (${attr.type}) [${attr.status}]${attr.required ? " required" : ""}`);
    }
  } catch (error) {
    console.warn(`⚠️ فشل في عرض السمات: ${error.message}`);
  }
}

addTerminationFields().catch((error) => {
  console.error("❌ خطأ عام:", error);
  process.exit(1);
});
