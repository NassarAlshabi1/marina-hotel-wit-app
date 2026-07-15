#!/usr/bin/env node
/**
 * إعادة إنشاء collection 'guest_infos' بـ schema نظيف مع الحفاظ على البيانات.
 *
 * الخطوات:
 *   1. تصدير كل المستندات الحالية إلى ملف backup JSON
 *   2. تحويل أسماء الحقول القديمة إلى الجديدة:
 *      guestNationality   → nationality
 *      guestIdNumber      → idNumber
 *      guestIdIssueDate   → issueDate
 *      guestIdIssuePlace  → issuePlace
 *      guestIdType        → idType
 *      guestName          → guestName (نفسه)
 *      notes              → notes (نفسه)
 *      (governorate غير موجودة في القديم → null)
 *      (roomNumber غير موجودة في القديم → '' فارغ، لكن required=true!)
 *   3. حذف الـ collection القديمة
 *   4. إنشاء collection جديدة بالـ schema النظيف
 *   5. استيراد البيانات المُحوّلة
 *
 * ⚠️  تحذير: الحقول القديمة التالية ستُفقد (غير موجودة في الـ schema الجديد):
 *   guestPhone, guestEmail, guestAddress, occupation, dateOfBirth, gender,
 *   totalVisits, totalSpent, lastVisitDate, vipStatus
 *   لكن البيانات محفوظة في ملف backup لو احتجتها لاحقاً.
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node recreate_guest_infos_with_backup.js --force
 */

const { Client, Databases, Permission, Role, Query } = require('node-appwrite');
const fs = require('fs');
const path = require('path');

// ─── إعدادات Appwrite Cloud ─────────────────────────────────────────────────
const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'guest_infos';
const force = process.argv.includes('--force');

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  console.log('Usage: APPWRITE_API_KEY=your_key node recreate_guest_infos_with_backup.js [--force]');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

const defaultPermissions = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

// ─── syncFields (12 attribute) ──────────────────────────────────────────────
const syncFieldsAttributes = [
  { key: 'localUuid',      type: 'string',  required: true,  size: 64 },
  { key: 'serverId',       type: 'integer', required: false },
  { key: 'createdAt',      type: 'integer', required: true  },
  { key: 'updatedAt',      type: 'integer', required: true  },
  { key: 'deletedAt',      type: 'integer', required: false },
  { key: 'lastModified',   type: 'integer', required: true  },
  { key: 'createdAtIso',   type: 'string',  required: false, size: 30 },
  { key: 'updatedAtIso',   type: 'string',  required: false, size: 30 },
  { key: 'deletedAtIso',   type: 'string',  required: false, size: 30 },
  { key: 'version',        type: 'integer', required: false, default: 1 },
  { key: 'origin',         type: 'string',  required: false, default: 'local', size: 20 },
  { key: 'vectorClock',    type: 'string',  required: false, default: '{}', size: 2000 },
];

// ─── guest_infos schema النظيف (syncFields + 9 حقول عمل) ───────────────────
const guestInfosAttributes = [
  ...syncFieldsAttributes,
  { key: 'roomNumber',    type: 'string',  required: true,  size: 20 },
  { key: 'guestName',     type: 'string',  required: true,  size: 200 },
  { key: 'nationality',   type: 'string',  required: true,  size: 100 },
  { key: 'idNumber',      type: 'string',  required: true,  size: 50 },
  { key: 'idType',        type: 'string',  required: false, default: 'بطاقة شخصية', size: 50 },
  { key: 'issueDate',     type: 'string',  required: false, size: 20 },
  { key: 'issuePlace',    type: 'string',  required: false, size: 100 },
  { key: 'governorate',   type: 'string',  required: false, size: 100 },
  { key: 'notes',         type: 'string',  required: false, size: 5000 },
];

const guestInfosIndexes = [
  { key: 'idx_last_modified', type: 'key', attributes: ['lastModified'] },
  { key: 'idx_room_number',   type: 'key', attributes: ['roomNumber'] },
  { key: 'idx_id_number',     type: 'key', attributes: ['idNumber'] },
  { key: 'idx_guest_name',    type: 'key', attributes: ['guestName'] },
];

// ─── تحويل الحقول القديمة → الجديدة ─────────────────────────────────────────
// يأخذ مستنداً قديماً ويُرجع مستنداً جديداً بـ schema النظيف
function migrateDocument(oldDoc) {
  // الحقول النظامية
  const $id = oldDoc.$id;
  const $createdAt = oldDoc.$createdAt;
  const $updatedAt = oldDoc.$updatedAt;

  // تحويل الحقول القديمة إلى الجديدة
  // ✅roomNumber: غير موجودة في القديم — نستخدم قيمة افتراضية 'N/A'
  //   (مطلوب required=true في الـ schema الجديد، لا يمكن تركه فارغاً)
  // ✅ nationality: من guestNationality (إن وُجدت) أو 'غير محدد'
  // ✅ idNumber: من guestIdNumber (إن وُجد) أو 'N/A'
  // ✅ guestName: من guestName (نفسه)
  // ✅ idType: من guestIdType أو 'بطاقة شخصية' (default)
  // ✅ issueDate: من guestIdIssueDate
  // ✅ issuePlace: من guestIdIssuePlace
  // ✅ governorate: غير موجودة في القديم → null (optional)
  // ✅ notes: من notes (نفسه)

  const nationality = oldDoc.guestNationality || oldDoc.nationality || 'غير محدد';
  const idNumber = oldDoc.guestIdNumber || oldDoc.idNumber || 'N/A';
  const guestName = oldDoc.guestName || 'غير معروف';
  const roomNumber = oldDoc.roomNumber || 'N/A'; // مطلوب، نضع افتراضي

  // الحقول المزامنة (sync fields)
  const localUuid = oldDoc.localUuid || $id;
  const serverId = oldDoc.serverId;
  const createdAt = oldDoc.createdAt || Math.floor(new Date($createdAt).getTime() / 1000);
  const updatedAt = oldDoc.updatedAt || Math.floor(new Date($updatedAt).getTime() / 1000);
  const deletedAt = oldDoc.deletedAt;
  const lastModified = oldDoc.lastModified || updatedAt;
  const createdAtIso = oldDoc.createdAtIso || $createdAt;
  const updatedAtIso = oldDoc.updatedAtIso || $updatedAt;
  const deletedAtIso = oldDoc.deletedAtIso;
  const version = oldDoc.version || 1;
  const origin = oldDoc.origin || 'local';
  const vectorClock = oldDoc.vectorClock || '{}';

  // الحقول الاختيارية
  const idType = oldDoc.guestIdType || oldDoc.idType || 'بطاقة شخصية';
  const issueDate = oldDoc.guestIdIssueDate || oldDoc.issueDate || null;
  const issuePlace = oldDoc.guestIdIssuePlace || oldDoc.issuePlace || null;
  const governorate = oldDoc.governorate || null;
  const notes = oldDoc.notes || null;

  // بناء المستند الجديد — فقط الحقول الموجودة في الـ schema الجديد
  const newDoc = {
    localUuid,
    roomNumber,
    guestName,
    nationality,
    idNumber,
    idType,
    createdAt,
    updatedAt,
    lastModified,
    version,
    origin,
    vectorClock,
  };

  // الحقول الاختيارية — نضيفها فقط إذا كانت لها قيمة
  if (serverId != null) newDoc.serverId = serverId;
  if (deletedAt != null) newDoc.deletedAt = deletedAt;
  if (createdAtIso) newDoc.createdAtIso = createdAtIso;
  if (updatedAtIso) newDoc.updatedAtIso = updatedAtIso;
  if (deletedAtIso) newDoc.deletedAtIso = deletedAtIso;
  if (issueDate) newDoc.issueDate = issueDate;
  if (issuePlace) newDoc.issuePlace = issuePlace;
  if (governorate) newDoc.governorate = governorate;
  if (notes) newDoc.notes = notes;

  return {
    documentId: localUuid, // نستخدم localUuid كـ document ID
    data: newDoc,
    // معلومات للسجل
    _meta: {
      originalId: $id,
      originalGuestName: oldDoc.guestName,
      originalNationality: oldDoc.guestNationality,
      originalIdNumber: oldDoc.guestIdNumber,
    },
  };
}

// ─── 1. تصدير المستندات الحالية ──────────────────────────────────────────────
async function exportExistingDocuments() {
  console.log('\n📤 Step 1: Exporting existing documents...');
  const allDocs = [];
  let cursor = null;
  let batch = 0;

  try {
    while (true) {
      batch++;
      const queries = [Query.limit(100)];
      if (cursor) queries.push(Query.cursorAfter(cursor));

      const result = await databases.listDocuments(
        databaseId,
        collectionId,
        queries
      );

      if (result.documents.length === 0) {
        break;
      }

      allDocs.push(...result.documents);
      console.log(`   Batch ${batch}: ${result.documents.length} docs (total: ${allDocs.length})`);

      if (result.documents.length < 100) {
        break;
      }
      cursor = result.documents[result.documents.length - 1].$id;
    }
  } catch (e) {
    if (e.code === 404) {
      console.log(`   ℹ️  Collection doesn't exist yet — nothing to export`);
      return [];
    }
    throw e;
  }

  // احفظ في ملف backup
  if (allDocs.length > 0) {
    const backupDir = path.join(__dirname, 'backups');
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir, { recursive: true });
    }
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const backupFile = path.join(backupDir, `guest_infos_backup_${timestamp}.json`);
    fs.writeFileSync(backupFile, JSON.stringify(allDocs, null, 2));
    console.log(`   💾 Backup saved: ${backupFile}`);
  }

  console.log(`   ✅ Exported ${allDocs.length} documents`);
  return allDocs;
}

// ─── 2. حذف الـ collection ───────────────────────────────────────────────────
async function deleteCollection() {
  console.log('\n🗑️  Step 2: Deleting existing collection...');
  try {
    await databases.getCollection(databaseId, collectionId);
  } catch (e) {
    if (e.code === 404) {
      console.log('   ℹ️  Collection does not exist — skipping delete');
      return;
    }
    throw e;
  }

  await databases.deleteCollection(databaseId, collectionId);
  console.log('   ⏳ Delete requested, waiting for completion...');

  // انتظر حتى تنتهي عملية الحذف (async في Appwrite)
  for (let i = 0; i < 24; i++) { // حتى 120 ثانية
    await new Promise((r) => setTimeout(r, 5000));
    try {
      await databases.getCollection(databaseId, collectionId);
      process.stdout.write('.');
    } catch (e) {
      if (e.code === 404) {
        console.log('\n   ✅ Collection deleted');
        return;
      }
      throw e;
    }
  }
  throw new Error('Timeout waiting for collection deletion');
}

// ─── 3. إنشاء collection جديدة بالـ schema النظيف ────────────────────────────
async function createCleanCollection() {
  console.log('\n📝 Step 3: Creating collection with clean schema...');
  console.log(`   Attributes: ${guestInfosAttributes.length} (12 sync + 9 business)`);
  console.log(`   Indexes: ${guestInfosIndexes.length}`);

  await databases.createCollection(
    databaseId,
    collectionId,
    'Guest Infos',
    defaultPermissions,
    false
  );
  console.log('   ✅ Collection created');

  // أضف الـ attributes
  console.log('\n   Adding attributes...');
  let added = 0;
  let failed = 0;
  for (const attr of guestInfosAttributes) {
    process.stdout.write(`      → ${attr.key} (${attr.type})... `);
    try {
      if (attr.type === 'string') {
        await databases.createStringAttribute(
          databaseId, collectionId, attr.key,
          attr.size || 255, attr.required || false, attr.default
        );
      } else if (attr.type === 'integer') {
        await databases.createIntegerAttribute(
          databaseId, collectionId, attr.key,
          attr.required || false, attr.min, attr.max, attr.default
        );
      }
      console.log('✅');
      added++;
    } catch (e) {
      console.log(`❌ ${e.message}`);
      failed++;
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  console.log(`   ✅ ${added} added, ${failed} failed`);

  // أضف الـ indexes
  console.log('\n   Creating indexes...');
  let idxCreated = 0;
  for (const idx of guestInfosIndexes) {
    process.stdout.write(`      → ${idx.key}... `);
    try {
      await databases.createIndex(
        databaseId, collectionId, idx.key,
        idx.type, idx.attributes
      );
      console.log('✅');
      idxCreated++;
    } catch (e) {
      console.log(`❌ ${e.message}`);
    }
    await new Promise((r) => setTimeout(r, 400));
  }
  console.log(`   ✅ ${idxCreated}/${guestInfosIndexes.length} indexes created`);

  return { added, failed, idxCreated };
}

// ─── 4. استيراد البيانات المُحوّلة ──────────────────────────────────────────
async function importMigratedDocuments(oldDocs) {
  if (oldDocs.length === 0) {
    console.log('\n📥 Step 4: No documents to import — skipping');
    return { imported: 0, failed: 0 };
  }

  console.log(`\n📥 Step 4: Importing ${oldDocs.length} migrated documents...`);

  // حوّل كل مستند قديم إلى الصيغة الجديدة
  const migrated = oldDocs.map(migrateDocument);

  let imported = 0;
  let failed = 0;
  const failures = [];

  for (let i = 0; i < migrated.length; i++) {
    const m = migrated[i];
    process.stdout.write(`   [${i + 1}/${migrated.length}] ${m.data.guestName}... `);
    try {
      await databases.createDocument(
        databaseId,
        collectionId,
        m.documentId,  // استخدم localUuid كـ document ID
        m.data
      );
      console.log('✅');
      imported++;
    } catch (e) {
      console.log(`❌ ${e.message}`);
      failures.push({
        meta: m._meta,
        error: e.message,
        data: m.data,
      });
      failed++;
    }
    await new Promise((r) => setTimeout(r, 300));
  }

  // احفظ الفشل في ملف للمراجعة
  if (failures.length > 0) {
    const backupDir = path.join(__dirname, 'backups');
    if (!fs.existsSync(backupDir)) {
      fs.mkdirSync(backupDir, { recursive: true });
    }
    const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
    const failFile = path.join(backupDir, `guest_infos_import_failures_${timestamp}.json`);
    fs.writeFileSync(failFile, JSON.stringify(failures, null, 2));
    console.log(`\n   ⚠️  ${failures.length} failures saved to: ${failFile}`);
  }

  console.log(`\n   ✅ Imported: ${imported}`);
  console.log(`   ❌ Failed: ${failed}`);
  return { imported, failed };
}

// ─── المنطق الرئيسي ──────────────────────────────────────────────────────────
async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  إعادة إنشاء guest_infos بـ schema نظيف + الحفاظ على البيانات');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Endpoint:    ${endpoint}`);
  console.log(`  Project:     ${projectId}`);
  console.log(`  Database:    ${databaseId}`);
  console.log(`  Collection:  ${collectionId}`);
  console.log(`  Force:       ${force}`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  if (!force) {
    console.log('⚠️  تحذير: هذا السكريبت يحذف ويعيد إنشاء collection guest_infos.');
    console.log('   البيانات القديمة ستُصدَّر أولاً ثم تُعاد استيرادها مع تحويل');
    console.log('   أسماء الحقول (guestNationality → nationality، إلخ).');
    console.log('\n   للتأكيد، أعد التشغيل مع --force:');
    console.log('   APPWRITE_API_KEY=your_key node recreate_guest_infos_with_backup.js --force');
    process.exit(1);
  }

  console.log('✅ --force confirmed, proceeding...\n');

  // 1) صدّر المستندات الحالية
  const oldDocs = await exportExistingDocuments();

  // 2) احذف الـ collection القديمة
  await deleteCollection();

  // 3) أنشئ الـ collection الجديدة بالـ schema النظيف
  const createResult = await createCleanCollection();

  // 4) استورد البيانات المُحوّلة
  const importResult = await importMigratedDocuments(oldDocs);

  // الملخص
  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  الملخص النهائي');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  📤 المستندات القديمة:     ${oldDocs.length}`);
  console.log(`  📝 Attributes أُنشئت:     ${createResult.added}`);
  console.log(`  📝 Indexes أُنشئت:        ${createResult.idxCreated}`);
  console.log(`  📥 مستندات أُعيد استيرادها: ${importResult.imported}`);
  console.log(`  ❌ فشل الاستيراد:        ${importResult.failed}`);
  console.log('');
  if (oldDocs.length > 0) {
    console.log('🔄 تحويل أسماء الحقول المُطبَّق:');
    console.log('   guestNationality   → nationality');
    console.log('   guestIdNumber      → idNumber');
    console.log('   guestIdIssueDate   → issueDate');
    console.log('   guestIdIssuePlace  → issuePlace');
    console.log('   guestIdType        → idType');
    console.log('   governorate        → (null — غير موجودة في القديم)');
    console.log('   roomNumber         → "N/A" (غير موجودة في القديم، مطلوبة)');
    console.log('');
  }
  console.log('📝 الخطوة التالية:');
  console.log('   في التطبيق، اضغط زر "رفع التغييرات" — يجب أن تنجح المزامنة الآن.');
  console.log('');

  if (createResult.failed > 0 || importResult.failed > 0) {
    console.log('⚠️  كانت هناك بعض الفشل — راجع الـ logs أعلاه.');
  }
}

main().catch((e) => {
  console.error('\n❌ Fatal error:', e.message || e);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
