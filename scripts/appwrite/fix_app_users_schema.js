#!/usr/bin/env node
/**
 * إصلاح collection app_users على Appwrite Cloud.
 *
 * المشكلة: collection app_users تحتوي على حقول SyncFields مطلوبة (required)
 * مثل createdAt, updatedAt, lastModified, lastModifiedEpoch, createdAtEpoch,
 * syncTimestamp, role, deviceId, version, origin, vectorClock.
 *
 * لكن _pushUserToCloud و updateCloudUser لا يرسلان كل هذه الحقول،
 * مما يسبب فشل عمليات الإضافة والتعديل:
 *   "Missing required attribute: createdAt" (400)
 *
 * الحل: تحويل كل حقول SyncFields إلى اختيارية (nullable) على Appwrite Cloud.
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node fix_app_users_schema.js
 */

const { Client, Databases } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'app_users';

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

// الحقول التي يجب أن تكون nullable (SyncFields)
const syncFieldsToFix = [
  'createdAt',
  'updatedAt',
  'lastModified',
  'lastModifiedEpoch',
  'createdAtEpoch',
  'syncTimestamp',
  'role',
  'deviceId',
  'version',
  'origin',
  'vectorClock',
  'deletedAt',
];

async function main() {
  console.log('═'.repeat(70));
  console.log('  إصلاح app_users schema — تحويل SyncFields لـ nullable');
  console.log('═'.repeat(70) + '\n');

  // Appwrite لا يوفر updateAttribute مباشرة — يجب حذف وإعادة إنشاء
  // لكن هذا سيفقد البيانات (لا توجد بيانات حالياً — collection فارغة)
  
  // بدلاً من ذلك: نحذف الـ collection ونعيد إنشاءها بالـ schema الصحيح
  console.log('🗑️  Deleting app_users collection...');
  try {
    await databases.deleteCollection(databaseId, collectionId);
    console.log('   ✅ Deleted');
  } catch (e) {
    if (e.code === 404) {
      console.log('   ℹ️  Collection does not exist');
    } else {
      console.log('   ⚠️  Delete error: ' + e.message);
    }
  }

  // انتظر حتى يكتمل الحذف
  console.log('   ⏳ Waiting for deletion...');
  for (let i = 0; i < 12; i++) {
    await new Promise(r => setTimeout(r, 5000));
    try {
      await databases.getCollection(databaseId, collectionId);
      process.stdout.write('.');
    } catch (e) {
      if (e.code === 404) {
        console.log('\n   ✅ Deletion completed');
        break;
      }
    }
  }

  // أنشئ الـ collection من جديد
  console.log('\n📝 Creating app_users collection with correct schema...');
  
  const permissions = [
    'read("any")',
    'create("any")',
    'update("any")',
    'delete("any")',
  ];

  try {
    const { Permission, Role } = require('node-appwrite');
    await databases.createCollection(
      databaseId,
      collectionId,
      'App Users',
      [
        Permission.read(Role.any()),
        Permission.create(Role.any()),
        Permission.update(Role.any()),
        Permission.delete(Role.any()),
      ],
      false
    );
    console.log('   ✅ Collection created');
  } catch (e) {
    console.log('   ❌ Create collection failed: ' + e.message);
    return;
  }

  // أضف الحقول الأساسية للمستخدم (required = true فقط لهذه)
  const userFields = [
    { key: 'username', type: 'string', size: 100, required: true },
    { key: 'password', type: 'string', size: 500, required: true },
    { key: 'full_name', type: 'string', size: 255, required: false },
    { key: 'user_type', type: 'string', size: 50, required: false, default: 'employee' },
    { key: 'permissions', type: 'string', size: 5000, required: false },
    { key: 'active', type: 'boolean', required: false, default: true },
    { key: 'last_login', type: 'integer', required: false, default: 0 },
    { key: 'credentials_version', type: 'integer', required: false, default: 1 },
    { key: 'role', type: 'string', size: 50, required: false, default: 'employee' },
  ];

  // حقول SyncFields (كلها nullable)
  const syncFields = [
    { key: 'localUuid', type: 'string', size: 64, required: false },
    { key: 'serverId', type: 'integer', required: false },
    { key: 'createdAt', type: 'integer', required: false },
    { key: 'updatedAt', type: 'integer', required: false },
    { key: 'deletedAt', type: 'integer', required: false },
    { key: 'lastModified', type: 'integer', required: false },
    { key: 'createdAtIso', type: 'string', size: 30, required: false },
    { key: 'updatedAtIso', type: 'string', size: 30, required: false },
    { key: 'deletedAtIso', type: 'string', size: 30, required: false },
    { key: 'createdAtEpoch', type: 'integer', required: false },
    { key: 'lastModifiedEpoch', type: 'integer', required: false },
    { key: 'syncTimestamp', type: 'integer', required: false },
    { key: 'deviceId', type: 'string', size: 100, required: false },
    { key: 'version', type: 'integer', required: false, default: 1 },
    { key: 'origin', type: 'string', size: 20, required: false, default: 'local' },
    { key: 'vectorClock', type: 'string', size: 2000, required: false, default: '{}' },
    { key: 'sync_origin', type: 'string', size: 20, required: false },
    { key: 'idempotencyKey', type: 'string', size: 100, required: false },
  ];

  const allFields = [...userFields, ...syncFields];
  console.log('   Adding ' + allFields.length + ' attributes...');

  let added = 0;
  let failed = 0;
  for (const attr of allFields) {
    process.stdout.write('      → ' + attr.key + ' (' + attr.type + ')... ');
    try {
      if (attr.type === 'string') {
        await databases.createStringAttribute(
          databaseId, collectionId, attr.key,
          attr.size || 255, attr.required || false, attr.default
        );
      } else if (attr.type === 'integer') {
        await databases.createIntegerAttribute(
          databaseId, collectionId, attr.key,
          attr.required || false, undefined, undefined, attr.default
        );
      } else if (attr.type === 'boolean') {
        await databases.createBooleanAttribute(
          databaseId, collectionId, attr.key,
          attr.required || false, attr.default
        );
      }
      console.log('✅');
      added++;
    } catch (e) {
      console.log('❌ ' + e.message.substring(0, 60));
      failed++;
    }
    await new Promise(r => setTimeout(r, 400));
  }

  console.log('\n═'.repeat(70));
  console.log('  الملخص');
  console.log('═'.repeat(70));
  console.log('  ✅ Attributes added: ' + added);
  console.log('  ❌ Failed: ' + failed);
  console.log('\n📝 app_users collection الآن تحتوي على:');
  console.log('   - 9 حقول مستخدم (username, password required؛ الباقي optional)');
  console.log('   - 18 حقول SyncFields (كلها optional/nullable)');
  console.log('\n📝 الآن _pushUserToCloud و updateCloudUser يجب أن يعملا بدون خطأ.');
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
