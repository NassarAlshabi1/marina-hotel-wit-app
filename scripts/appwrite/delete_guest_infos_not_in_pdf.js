#!/usr/bin/env node
/**
 * حذف مستندات guest_infos من Appwrite Cloud غير الموجودة في PDF.
 *
 * يُبقي فقط الـ 37 مستند (42 سجل في PDF - 5 مكررات بنفس UUID = 37 فريد)
 * التي تطابق الـ UUIDs المسموح بها.
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node delete_guest_infos_not_in_pdf.js
 */

const { Client, Databases, Query } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'guest_infos';

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);
const databases = new Databases(client);

// ═══ الـ 37 UUID المسموح بها (من PDF — 42 سجل - 5 مكررات) ═══════════════════
const allowedUuids = new Set([
  // الصفحة 1 (سجلات 1-23 من PDF)
  '1dc137b8-e3f0-4a97-83e5-fe526228e8f3',
  '0b0d0d88-b460-4d71-9560-73b21c92bbe5',
  'eef2c0ec-fc61-4e72-a90e-8c5442d29aa9',
  '428e4a77-9808-44f4-81f5-5e4c7c04fa63',
  '2e42dadc-1c5b-4aa8-b44c-db15eaa41d6c',
  '5f547113-ea00-4c07-9653-8e1dc42a22ea',
  '3c55429b-9a7e-4cee-ac96-5d5824b07af4',
  '9f0a2b12-e978-4152-9a98-bb30b8cbe87a',
  'f102ab17-cc5b-4033-bf10-4c763f755544',
  '743431fa-2091-4ac4-8907-498bd51814cf',
  'e36892de-0fd1-4f91-ad7d-3b2560a543ff',
  'f1139284-d12d-4901-857f-2b7e35447d0f',
  'b9d082a9-f799-4b4e-8c62-c70f84afdc6e',
  '7920e0bc-9383-4077-8c61-22c2fb002889',
  '7546b8b1-2c2b-4b94-ba97-486f955fc0de',
  '78933c7f-379f-442b-ae14-7fdd7824985d',
  '899c0996-603c-437e-b484-0a2c438ae0fb',
  '275c06e8-0315-4469-b942-8aa70a4df327',
  // الصفحة 2 (سجلات 24-42 من PDF)
  '6f7f5b9d-2a5c-4e2f-b233-d26ff2fed676',
  '111aab67-0869-4e69-9b10-33bbd05d2169',
  '46d5b078-502b-4f77-ba9b-436aa0579d28',
  'cd263018-0a22-417c-b983-39db2ec534fc',
  'befcc279-ce69-4efc-a24a-8eab3490c38a',
  'a2cb45fd-c28b-4fe9-a4d3-189f94ea83fe',
  'ddcaf59c-2678-410a-b1b3-6b3067639f15',
  '0857a23d-12c5-4da5-83a5-8c95a0a3bbde',
  'fd322339-df02-4092-bd66-40bbad604c96',
  '2e212a7d-8fe1-4d63-bb98-d239234d48a5',
  '38e1fc9e-db47-4c64-a089-3fc8f5d7def2',
  '1370483f-dcd6-4760-8b56-3781385f6c03',
  '483cfb3b-cc5b-43df-b278-8a849404b2c6',
  'b7b5e139-0767-409c-becd-bb0635cfaf5a',
  'c45f83ec-2722-433a-8b3f-183767402439',
  'af035c6b-93ec-4cb1-bc70-6f4ed17ed9aa',
  '4e2e9449-6637-43a7-a4b3-fb66f360d879',
  '00000000-0000-4000-8000-000000000041',
  '00000000-0000-4000-8000-000000000042',
]);

async function listAllDocuments() {
  const allDocs = [];
  let cursor = null;
  let batch = 0;

  while (true) {
    batch++;
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));

    const result = await databases.listDocuments(
      databaseId, collectionId, queries
    );
    if (result.documents.length === 0) break;

    allDocs.push(...result.documents);
    console.log(`   Batch ${batch}: ${result.documents.length} docs (total: ${allDocs.length})`);

    if (result.documents.length < 100) break;
    cursor = result.documents[result.documents.length - 1].$id;
  }

  return allDocs;
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  حذف مستندات guest_infos غير الموجودة في PDF');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Allowed UUIDs (from PDF): ${allowedUuids.size}`);
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('');

  // 1) اقرأ كل المستندات الحالية
  console.log('📥 Reading all documents from Appwrite Cloud...');
  const existing = await listAllDocuments();
  console.log(`   📦 Found ${existing.length} documents\n`);

  // 2) صنّفها: allowed vs to-delete
  const toDelete = [];
  const toKeep = [];
  for (const doc of existing) {
    const uuid = doc.$id;
    if (allowedUuids.has(uuid)) {
      toKeep.push(doc);
    } else {
      toDelete.push(doc);
    }
  }

  console.log(`✅ Will KEEP: ${toKeep.length} documents (in PDF allowlist)`);
  console.log(`🗑️  Will DELETE: ${toDelete.length} documents (not in PDF)\n`);

  if (toDelete.length === 0) {
    console.log('✨ Nothing to delete — collection already clean.');
    return;
  }

  // 3) اعرض السجلات التي ستُحذف
  console.log('📋 Documents to be deleted:');
  toDelete.forEach((doc, i) => {
    const name = doc.guestName || doc.localUuid || '?';
    const room = doc.roomNumber || '?';
    console.log(`   ${i + 1}. ${doc.$id} — ${name} (غرفة ${room})`);
  });
  console.log('');

  // 4) احذفها
  console.log('🗑️  Deleting...');
  let deleted = 0;
  let failed = 0;

  for (let i = 0; i < toDelete.length; i++) {
    const doc = toDelete[i];
    const name = doc.guestName || doc.localUuid || '?';
    process.stdout.write(`   [${i + 1}/${toDelete.length}] ${name.substring(0, 30)}... `);
    try {
      await databases.deleteDocument(databaseId, collectionId, doc.$id);
      console.log('✅');
      deleted++;
    } catch (e) {
      console.log(`❌ ${e.message}`);
      failed++;
    }
    await new Promise((r) => setTimeout(r, 200));
  }

  // 5) تحقق من العدد النهائي
  console.log('\n🔍 Verifying final count...');
  const finalDocs = await listAllDocuments();

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  الملخص النهائي');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  📦 كان موجوداً:        ${existing.length}`);
  console.log(`  🗑️  Deleted:          ${deleted}`);
  console.log(`  ❌ Delete failed:    ${failed}`);
  console.log(`  ✅ Kept (in PDF):    ${toKeep.length}`);
  console.log(`  📦 العدد النهائي:     ${finalDocs.length}`);
  console.log('');
  console.log('📝 النتيجة: collection guest_infos تحتوي الآن فقط على السجلات من PDF.');
}

main().catch((e) => {
  console.error('\n❌ Fatal error:', e.message || e);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
