#!/usr/bin/env node
/**
 * إضافة الـ attributes المفقودة في collection guest_infos على Appwrite Cloud.
 *
 * المشكلة: التطبيق يرسل الحقول بـ camelCase (nationality, idNumber, issueDate,
 * issuePlace, governorate, roomNumber)، لكن الـ collection على السيرفر تحتوي
 * على حقول بأسماء مختلفة (guestNationality, guestIdNumber, guestIdIssueDate,
 * guestIdIssuePlace, guestIdType) — وليس فيها governorate إطلاقاً.
 *
 * السبب: الـ collection أُنشئت بـ schema قديم مختلف عن ما يستخدمه التطبيق
 * الآن. التطبيق الحديث (في lib/services/local_db.dart GuestInfos table)
 * يستخدم أسماء مختصرة.
 *
 * الحل: إضافة الـ attributes المفقودة بجانب الموجودة (بدون حذف القديمة).
 * هذا يسمح للتطبيق بدفع البيانات بنجاح، والحقول القديمة تبقى للاستخدام
 * المستقبلي إذا لزم.
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_appwrite_api_key node add_guest_infos_missing_attributes.js
 *
 * Idempotent: يفحص إن كان الـ attribute موجوداً قبل إنشائه.
 */

const { Client, Databases } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'guest_infos';

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  console.log('Usage: APPWRITE_API_KEY=your_key node add_guest_infos_missing_attributes.js');
  console.log('\nGet your API key from: Appwrite Console → Settings → API Keys');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

// الـ attributes المفقودة التي يحتاجها التطبيق
const missingAttributes = [
  // ✅ الحقول الخمسة التي ذكرها المستخدم
  { key: 'nationality', type: 'string', size: 100, required: false },
  { key: 'idNumber', type: 'string', size: 100, required: false },
  { key: 'issueDate', type: 'string', size: 30, required: false },
  { key: 'issuePlace', type: 'string', size: 100, required: false },
  { key: 'governorate', type: 'string', size: 100, required: false },
  // ✅ roomNumber — ضروري للتطبيق لكنه مفقود في الـ collection
  { key: 'roomNumber', type: 'string', size: 20, required: false },
  // ✅ idType — التطبيق يرسله لكن السيرفر يستخدم guestIdType
  { key: 'idType', type: 'string', size: 50, required: false },
  // ✅ notes — التطبيق يرسله (ولكن السيرفر عنده notes ✅)
  // ملحوظة: notes موجود بالفعل، سيتخطاه السكريبت
  { key: 'notes', type: 'string', size: 2000, required: false },
];

async function attributeExists(attrKey) {
  try {
    // محاولة listAttributes تحتاج API key — نستخدم محاولة create
    // ونلتقط خطأ "already exists"
    return false; // سنجرب الإنشاء ونلتقط الخطأ
  } catch (e) {
    return false;
  }
}

async function createAttribute(attr) {
  const { key, type, size, required } = attr;
  try {
    if (type === 'string') {
      await databases.createStringAttribute(
        databaseId,
        collectionId,
        key,
        size || 255,
        required || false
      );
    } else if (type === 'integer') {
      await databases.createIntegerAttribute(
        databaseId,
        collectionId,
        key,
        required || false
      );
    } else if (type === 'double') {
      await databases.createFloatAttribute(
        databaseId,
        collectionId,
        key,
        required || false
      );
    } else if (type === 'boolean') {
      await databases.createBooleanAttribute(
        databaseId,
        collectionId,
        key,
        required || false
      );
    }
    return { ok: true, created: true };
  } catch (e) {
    const code = e.code;
    const msg = e.message || '';
    // 409 = already exists
    if (code === 409 || msg.includes('already exists') || msg.includes('Duplicate')) {
      return { ok: true, created: false, alreadyExists: true };
    }
    return { ok: false, error: `${code}: ${msg}` };
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  إضافة الـ attributes المفقودة في collection guest_infos');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Endpoint:    ${endpoint}`);
  console.log(`  Project:     ${projectId}`);
  console.log(`  Database:    ${databaseId}`);
  console.log(`  Collection:  ${collectionId}`);
  console.log(`  Attributes:  ${missingAttributes.length} to add`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  // ✅ تحقق من وجود الـ collection نفسها
  try {
    await databases.getCollection(databaseId, collectionId);
    console.log(`✅ Collection '${collectionId}' exists\n`);
  } catch (e) {
    console.error(`❌ Collection '${collectionId}' not found: ${e.message}`);
    console.log('Run create_missing_collections.js first.');
    process.exit(1);
  }

  let created = 0;
  let alreadyExists = 0;
  let failed = 0;

  for (const attr of missingAttributes) {
    process.stdout.write(`  → ${attr.key} (${attr.type})... `);
    const result = await createAttribute(attr);
    if (result.ok) {
      if (result.created) {
        console.log('✅ created');
        created++;
      } else {
        console.log('✓ already exists');
        alreadyExists++;
      }
    } else {
      console.log(`❌ ${result.error}`);
      failed++;
    }
    // مهلة قصيرة بين الإضافات لتجنّب rate limiting
    await new Promise((r) => setTimeout(r, 300));
  }

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  الملخص');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  ✅ Created:        ${created}`);
  console.log(`  ✓ Already existed: ${alreadyExists}`);
  console.log(`  ❌ Failed:         ${failed}`);
  console.log('');

  // تعليمات للتحقق
  console.log('📝 بعد التشغيل، تحقق من:');
  console.log('   node check_collection_attributes.js');
  console.log('');
  console.log('🔄 ثم في التطبيق، اضغط زر "رفع التغييرات" — يجب أن تنجح');
  console.log('   مزامنة guest_infos الآن.');

  if (failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
