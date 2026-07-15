#!/usr/bin/env node
/**
 * تنظيف المستندات المكررة في collection employees على Appwrite Cloud.
 *
 * المشكلة: 3 موظفين لكل منهم نسختان:
 *   - نسخة بـ localUuid قياسي (مع شرطات): 218da267-a3b3-4c40-ab96-a25101a8f161
 *   - نسخة بـ localUuid بدون شرطات: 218da267a3b34c40ab96a25101a8f161
 *
 * السبب: تاريخياً، بعض أجهزة المزامنة كانت تخزّن localUuid بدون شرطات
 * (من Google Drive sync أو backup قديم). عند الـ push:
 *   1. updateDocument(with-dashes) → 404 (السيرفر عنده بالشرطات فقط)
 *   2. createDocument(with-dashes) → 409 (موجود!)
 *   3. updateDocument(without-dashes) → 404 (السيرفر ما عنده بدون شرطات)
 *   → يفشل ويعيد المحاولة، لكن في نسخة سابقة من الكود كان يُنشئ بدون شرطات
 *
 * الحل:
 *   1. لكل مجموعة مكررة (بنفس الاسم):
 *      - إن وُجدت نسخة بالشرطات → احذف النسخة بدون شرطات
 *      - إن لم توجد نسخة بالشرطات → احذف النسخة الأحدث (الأقل بيانات)
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node cleanup_duplicate_employees.js
 */

const { Client, Databases, Query } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'employees';

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

const UUID_WITH_DASHES = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function listAllDocuments() {
  const allDocs = [];
  let cursor = null;
  while (true) {
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const r = await databases.listDocuments(databaseId, collectionId, queries);
    if (r.documents.length === 0) break;
    allDocs.push(...r.documents);
    if (r.documents.length < 100) break;
    cursor = r.documents[r.documents.length - 1].$id;
  }
  return allDocs;
}

async function main() {
  console.log('═'.repeat(80));
  console.log('  تنظيف المستندات المكررة في employees');
  console.log('═'.repeat(80) + '\n');

  // 1) اقرأ كل الموظفين
  console.log('📥 Reading all employees...');
  const docs = await listAllDocuments();
  console.log('   ✅ Found ' + docs.length + ' documents\n');

  // 2) صنّف حسب الاسم (مجموعات مكررة)
  const nameMap = {};
  for (const doc of docs) {
    const name = (doc.name || '').trim();
    if (!name) continue;
    if (!nameMap[name]) nameMap[name] = [];
    nameMap[name].push(doc);
  }

  // 3) ابحث عن المجموعات المكررة
  const duplicates = Object.entries(nameMap).filter(([k, v]) => v.length > 1);
  console.log('🔁 Duplicate groups: ' + duplicates.length + '\n');

  if (duplicates.length === 0) {
    console.log('✨ No duplicates found — collection is clean.');
    return;
  }

  // 4) لكل مجموعة، حدد النسخة التي يجب حذفها
  let deleted = 0;
  let kept = 0;
  let failed = 0;

  for (const [name, group] of duplicates) {
    console.log('─'.repeat(80));
    console.log('📋 Group: "' + name + '" (' + group.length + ' copies)');

    // صنّف: بالشرطات vs بدون شرطات
    const withDashes = group.filter(d => UUID_WITH_DASHES.test(d.localUuid || ''));
    const withoutDashes = group.filter(d => !UUID_WITH_DASHES.test(d.localUuid || ''));

    console.log('   With dashes (standard UUID): ' + withDashes.length);
    console.log('   Without dashes (legacy): ' + withoutDashes.length);

    let toDelete = [];

    if (withDashes.length > 0 && withoutDashes.length > 0) {
      // ✅ الحالة المثالية: احذف النسخ بدون شرطات (legacy)، أبقِ بالشرطات (standard)
      toDelete = withoutDashes;
      console.log('   → Strategy: delete without-dashes (legacy), keep with-dashes (standard)');
    } else if (withDashes.length > 1) {
      // عدة نسخ بالشرطات — احذف الأقدم (الأقل بيانات)
      // قارن بعدد الحقول غير الفارغة
      const scored = withDashes.map(d => ({
        doc: d,
        score: Object.values(d).filter(v => v != null && v !== '' && v !== 0).length,
      }));
      scored.sort((a, b) => b.score - a.score);
      toDelete = scored.slice(1).map(s => s.doc);
      console.log('   → Strategy: keep richest with-dashes, delete rest');
    } else if (withoutDashes.length > 1) {
      // عدة نسخ بدون شرطات — احذف الأقدم
      const scored = withoutDashes.map(d => ({
        doc: d,
        score: Object.values(d).filter(v => v != null && v !== '' && v !== 0).length,
      }));
      scored.sort((a, b) => b.score - a.score);
      toDelete = scored.slice(1).map(s => s.doc);
      console.log('   → Strategy: keep richest without-dashes, delete rest');
    }

    console.log('   🗑️  Will delete: ' + toDelete.length);
    console.log('   ✅ Will keep: ' + (group.length - toDelete.length));

    for (const doc of toDelete) {
      process.stdout.write('      Deleting ' + doc.$id + ' (' + doc.name + ')... ');
      try {
        await databases.deleteDocument(databaseId, collectionId, doc.$id);
        console.log('✅');
        deleted++;
      } catch (e) {
        console.log('❌ ' + e.message);
        failed++;
      }
      await new Promise(r => setTimeout(r, 300));
    }
    kept += group.length - toDelete.length;
    console.log('');
  }

  // 5) تحقق من العدد النهائي
  console.log('═'.repeat(80));
  console.log('  الملخص');
  console.log('═'.repeat(80));
  console.log('  📦 Total before: ' + docs.length);
  console.log('  🗑️  Deleted: ' + deleted);
  console.log('  ❌ Failed: ' + failed);
  console.log('  ✅ Kept: ' + kept);

  console.log('\n🔍 Verifying final count...');
  const finalDocs = await listAllDocuments();
  console.log('  📦 Total after: ' + finalDocs.length);

  // تحقق من عدم وجود تكرار
  const finalNameMap = {};
  for (const doc of finalDocs) {
    const name = (doc.name || '').trim();
    if (!name) continue;
    if (!finalNameMap[name]) finalNameMap[name] = 0;
    finalNameMap[name]++;
  }
  const remainingDupes = Object.entries(finalNameMap).filter(([k, v]) => v > 1);
  if (remainingDupes.length === 0) {
    console.log('\n✅ No remaining duplicates — collection is clean!');
  } else {
    console.log('\n⚠️  Remaining duplicates: ' + remainingDupes.length);
    for (const [name, count] of remainingDupes) {
      console.log('   - ' + name + ': ' + count);
    }
  }
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
