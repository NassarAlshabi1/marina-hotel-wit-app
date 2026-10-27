#!/usr/bin/env node
/**
 * إعادة إنشاء collection 'guest_infos' بـ schema نظيف ومختصر فقط.
 *
 * المشكلة: الـ collection الحالية على Appwrite Cloud تحتوي على حقول قديمة
 * بأسماء مختلفة (guestNationality, guestIdNumber, guestIdIssueDate,
 * guestIdIssuePlace, guestIdType) بالإضافة إلى حقول غير مستخدمة في التطبيق
 * (guestPhone, guestEmail, guestAddress, occupation, dateOfBirth, gender,
 * totalVisits, totalSpent, lastVisitDate, vipStatus). هذا يسبب فشل المزامنة
 * لأن التطبيق يرسل nationality لكن السيرفر لا يعرفه.
 *
 * الحل: حذف الـ collection بالكامل وإعادة إنشائها بـ schema نظيف يحتوي فقط على:
 *   - syncFields (12 attribute: localUuid, serverId, createdAt, updatedAt, ...)
 *   - 9 حقول عمل: roomNumber, guestName, nationality, idNumber, idType,
 *                  issueDate, issuePlace, governorate, notes
 *
 * ⚠️  تحذير: هذا يحذف كل المستندات الحالية في guest_infos. لا يمكن التراجع.
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node recreate_guest_infos_collection.js
 *
 * للحذف الآمن (مع تأكيد):
 *   APPWRITE_API_KEY=your_key node recreate_guest_infos_collection.js --force
 */

const { Client, Databases, Permission, Role } = require('node-appwrite');

// ─── إعدادات Appwrite Cloud ─────────────────────────────────────────────────
const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'guest_infos';
const force = process.argv.includes('--force');

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  console.log('Usage: APPWRITE_API_KEY=your_key node recreate_guest_infos_collection.js [--force]');
  console.log('\nGet your API key from: Appwrite Console → Settings → API Keys');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

// ─── الصلاحيات الافتراضية ────────────────────────────────────────────────────
const defaultPermissions = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

// ─── syncFields (12 attribute) ──────────────────────────────────────────────
// مطابقة لـ Final_setup_all_collections.js — حقول المزامنة الموحّدة
const syncFields = {
  attributes: [
    { key: 'localUuid',      type: 'string',  required: true,  size: 64 },
    { key: 'serverId',       type: 'integer', required: false },
    { key: 'createdAt',      type: 'integer', required: true  },  // epoch seconds
    { key: 'updatedAt',      type: 'integer', required: true  },  // epoch seconds
    { key: 'deletedAt',      type: 'integer', required: false },  // epoch seconds (soft delete)
    { key: 'lastModified',   type: 'integer', required: true  },  // epoch seconds (delta sync)
    { key: 'createdAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'updatedAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'deletedAtIso',   type: 'string',  required: false, size: 30 },
    { key: 'version',        type: 'integer', required: false, default: 1 },
    { key: 'origin',         type: 'string',  required: false, default: 'local', size: 20 },
    { key: 'vectorClock',    type: 'string',  required: false, default: '{}', size: 2000 },
  ],
  indexes: [
    { key: 'idx_last_modified', type: 'key', attributes: ['lastModified'] },
  ],
};

// ─── guest_infos schema النظيف ─────────────────────────────────────────────
// syncFields + 9 حقول عمل فقط (كما طلب المستخدم)
const guestInfosSchema = {
  attributes: [
    ...syncFields.attributes,
    // ─── حقول العمل (9) ─────────────────────────────────────────────────
    { key: 'roomNumber',    type: 'string',  required: true,  size: 20 },
    { key: 'guestName',     type: 'string',  required: true,  size: 200 },
    { key: 'nationality',   type: 'string',  required: true,  size: 100 },
    { key: 'idNumber',      type: 'string',  required: true,  size: 50 },
    { key: 'idType',        type: 'string',  required: false, default: 'بطاقة شخصية', size: 50 },
    { key: 'issueDate',     type: 'string',  required: false, size: 20 },
    { key: 'issuePlace',    type: 'string',  required: false, size: 100 },
    { key: 'governorate',   type: 'string',  required: false, size: 100 },
    { key: 'notes',         type: 'string',  required: false, size: 5000 },
  ],
  indexes: [
    ...syncFields.indexes,
    // ✅ فهارس إضافية للاستعلامات الشائعة
    { key: 'idx_room_number',  type: 'key', attributes: ['roomNumber'] },
    { key: 'idx_id_number',    type: 'key', attributes: ['idNumber'] },
    { key: 'idx_guest_name',   type: 'key', attributes: ['guestName'] },
  ],
};

// ─── المنطق الرئيسي ──────────────────────────────────────────────────────────

async function deleteCollectionIfExists() {
  try {
    await databases.getCollection(databaseId, collectionId);
  } catch (e) {
    if (e.code === 404) {
      console.log(`  ℹ️  Collection '${collectionId}' does not exist — skipping delete`);
      return;
    }
    throw e;
  }

  // الـ collection موجودة — احذفها
  console.log(`  🗑️  Deleting existing collection '${collectionId}'...`);
  try {
    await databases.deleteCollection(databaseId, collectionId);
    console.log(`  ✅ Deleted`);
  } catch (e) {
    // أحياناً الحذف يستغرق وقتاً (async) — نتحقق
    if (e.code === 409 || (e.message && e.message.includes('still'))) {
      console.log(`  ⏳ Delete in progress, waiting 5s...`);
      await new Promise((r) => setTimeout(r, 5000));
    } else {
      throw e;
    }
  }

  // انتظر حتى تنتهي عملية الحذف فعلاً
  console.log(`  ⏳ Waiting for delete to complete...`);
  for (let i = 0; i < 12; i++) { // حتى 60 ثانية
    await new Promise((r) => setTimeout(r, 5000));
    try {
      await databases.getCollection(databaseId, collectionId);
      // ما زالت موجودة — انتظر أكثر
      process.stdout.write('.');
    } catch (e) {
      if (e.code === 404) {
        console.log(`\n  ✅ Delete completed`);
        return;
      }
      throw e;
    }
  }
  throw new Error('Timeout waiting for collection deletion');
}

async function createCollection() {
  console.log(`\n  📝 Creating collection '${collectionId}' with clean schema...`);
  console.log(`     Total attributes: ${guestInfosSchema.attributes.length}`);
  console.log(`       - Sync fields: ${syncFields.attributes.length}`);
  console.log(`       - Business fields: 9`);
  console.log(`     Total indexes: ${guestInfosSchema.indexes.length}`);

  // 1) أنشئ الـ collection
  await databases.createCollection(
    databaseId,
    collectionId,
    'Guest Infos',
    defaultPermissions,
    false  // documentSecurity
  );
  console.log(`  ✅ Collection created`);

  // 2) أضف الـ attributes
  console.log(`\n  📝 Adding ${guestInfosSchema.attributes.length} attributes...`);
  let added = 0;
  let failed = 0;
  for (const attr of guestInfosSchema.attributes) {
    process.stdout.write(`     → ${attr.key} (${attr.type})... `);
    try {
      if (attr.type === 'string') {
        await databases.createStringAttribute(
          databaseId,
          collectionId,
          attr.key,
          attr.size || 255,
          attr.required || false,
          attr.default
        );
      } else if (attr.type === 'integer') {
        await databases.createIntegerAttribute(
          databaseId,
          collectionId,
          attr.key,
          attr.required || false,
          attr.min,
          attr.max,
          attr.default
        );
      } else if (attr.type === 'float' || attr.type === 'double') {
        await databases.createFloatAttribute(
          databaseId,
          collectionId,
          attr.key,
          attr.required || false,
          attr.min,
          attr.max,
          attr.default
        );
      } else if (attr.type === 'boolean') {
        await databases.createBooleanAttribute(
          databaseId,
          collectionId,
          attr.key,
          attr.required || false,
          attr.default
        );
      }
      console.log('✅');
      added++;
    } catch (e) {
      console.log(`❌ ${e.message}`);
      failed++;
    }
    // مهلة قصيرة بين الإضافات لتجنّب rate limiting
    await new Promise((r) => setTimeout(r, 400));
  }
  console.log(`  ✅ ${added} added, ${failed} failed`);

  // 3) أنشئ الـ indexes
  console.log(`\n  📝 Creating ${guestInfosSchema.indexes.length} indexes...`);
  let indexesCreated = 0;
  for (const idx of guestInfosSchema.indexes) {
    process.stdout.write(`     → ${idx.key} on [${idx.attributes.join(', ')}]... `);
    try {
      await databases.createIndex(
        databaseId,
        collectionId,
        idx.key,
        idx.type,           // 'key' or 'fulltext' or 'unique'
        idx.attributes,
        idx.orders          // optional, default ['ASC']
      );
      console.log('✅');
      indexesCreated++;
    } catch (e) {
      console.log(`❌ ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  console.log(`  ✅ ${indexesCreated}/${guestInfosSchema.indexes.length} indexes created`);

  return { added, failed, indexesCreated };
}

async function verifySchema() {
  console.log(`\n  🔍 Verifying schema...`);
  try {
    // listDocuments مع limit 0 للتحقق من إنشاء الـ collection بنجاح
    const result = await databases.listDocuments(
      databaseId,
      collectionId,
      []
    );
    console.log(`  ✅ Collection is live — ${result.total} documents`);
  } catch (e) {
    console.log(`  ⚠️  Verification failed: ${e.message}`);
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  إعادة إنشاء collection guest_infos بـ schema نظيف');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Endpoint:    ${endpoint}`);
  console.log(`  Project:     ${projectId}`);
  console.log(`  Database:    ${databaseId}`);
  console.log(`  Collection:  ${collectionId}`);
  console.log(`  Force:       ${force}`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  if (!force) {
    console.log('⚠️  تحذير: هذا السكريبت يحذف collection guest_infos بالكامل');
    console.log('   بما في ذلك كل المستندات الموجودة فيها. لا يمكن التراجع.');
    console.log('\n   للتأكيد، أعد التشغيل مع --force:');
    console.log('   APPWRITE_API_KEY=your_key node recreate_guest_infos_collection.js --force');
    process.exit(1);
  }

  console.log('✅ --force confirmed, proceeding...\n');

  // 1) احذف الـ collection الموجودة (إن وُجدت)
  await deleteCollectionIfExists();

  // 2) أنشئ الـ collection الجديدة بالـ schema النظيف
  const result = await createCollection();

  // 3) تحقق من النجاح
  await verifySchema();

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  الملخص');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  ✅ Attributes added:   ${result.added}`);
  console.log(`  ❌ Attributes failed:  ${result.failed}`);
  console.log(`  ✅ Indexes created:    ${result.indexesCreated}`);
  console.log('');
  console.log('📝 الخطوة التالية:');
  console.log('   1. في التطبيق، اضغط زر "رفع التغييرات"');
  console.log('   2. يجب أن تنجح مزامنة guest_infos الآن مع كل الحقول الخمسة:');
  console.log('      nationality, idNumber, issueDate, issuePlace, governorate');
  console.log('');

  if (result.failed > 0) process.exit(1);
}

main().catch((e) => {
  console.error('\n❌ Fatal error:', e.message || e);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
