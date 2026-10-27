#!/usr/bin/env node
/**
 * مزامنة guest_infos من ملف CSV — فقط السجلات الموجودة في CSV.
 *
 * المنطق:
 *   1. قراءة CSV (42 سجل)
 *   2. لكل سجل في CSV: مطابقته مع مستند موجود في Appwrite Cloud
 *      (بـ idNumber + roomNumber) وتحديث بياناته بالاسم الصحيح من CSV
 *   3. حذف أي مستند في Appwrite Cloud غير موجود في CSV
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node sync_from_csv.js /path/to/guest_records.csv
 *
 * إن لم يُمرّر مسار الملف، يستخدم:
 *   /home/z/my-project/upload/guest_records.csv
 */

const { Client, Databases, Query } = require('node-appwrite');
const fs = require('fs');
const path = require('path');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'guest_infos';
const csvPath = process.argv[2] || '/home/z/my-project/upload/guest_records.csv';

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

if (!fs.existsSync(csvPath)) {
  console.error('❌ CSV file not found: ' + csvPath);
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

// ═══ قراءة CSV ═══════════════════════════════════════════════════════════════
function parseCSV(filePath) {
  const content = fs.readFileSync(filePath, 'utf-8');
  const lines = content.split('\n').filter(l => l.trim());
  if (lines.length < 2) return [];

  // تخطّي الـ header (السطر الأول)
  const records = [];
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    if (!line) continue;

    // تقسيم بفواصل، لكن نتعامل مع الحقول التي قد تحتوي على فواصل داخل علامات اقتباس
    const parts = parseCSVLine(line);
    if (parts.length < 10) {
      console.warn('⚠️  Skipping line ' + (i + 1) + ': expected 10 fields, got ' + parts.length);
      continue;
    }

    const [num, room, name, nationality, idType, idNumber, issueDate, issuePlace, governorate, notes] = parts;

    records.push({
      num: parseInt(num, 10),
      roomNumber: room.trim(),
      guestName: name.trim(),
      nationality: nationality.trim(),
      idType: idType.trim(),
      idNumber: idNumber.trim(),
      issueDate: issueDate.trim(),
      issuePlace: issuePlace.trim(),
      governorate: governorate.trim(),
      notes: notes.trim(),
    });
  }
  return records;
}

function parseCSVLine(line) {
  // تقسيم بسيط بفاصلة — الـ CSV لا يحتوي على فواصل داخل حقول
  return line.split(',');
}

function cleanOptional(value) {
  if (value === '-' || value === '' || value == null) return null;
  return value;
}

// ═══ قراءة كل المستندات من Appwrite Cloud ══════════════════════════════════
async function listAllDocuments() {
  const allDocs = [];
  let cursor = null;
  while (true) {
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const result = await databases.listDocuments(databaseId, collectionId, queries);
    if (result.documents.length === 0) break;
    allDocs.push(...result.documents);
    if (result.documents.length < 100) break;
    cursor = result.documents[result.documents.length - 1].$id;
  }
  return allDocs;
}

// ═══ بناء payload من سجل CSV ════════════════════════════════════════════════
function buildPayload(record, existingDoc) {
  const now = Math.floor(Date.now() / 1000);

  // نحافظ على UUID الحالي (localUuid = document ID)
  const data = {
    'localUuid': existingDoc.localUuid || existingDoc.$id,
    'roomNumber': record.roomNumber,
    'guestName': record.guestName,
    'nationality': record.nationality || 'غير محدد',
    'idNumber': record.idNumber,
    'createdAt': existingDoc.createdAt || now,
    'updatedAt': now,
    'lastModified': now,
    'version': (existingDoc.version || 1) + 1,
    'origin': existingDoc.origin || 'local',
    'vectorClock': existingDoc.vectorClock || '{}',
  };

  // الحقول الاختيارية
  if (record.idType && record.idType !== '-') data['idType'] = record.idType;
  const issueDate = cleanOptional(record.issueDate);
  if (issueDate) data['issueDate'] = issueDate;
  const issuePlace = cleanOptional(record.issuePlace);
  if (issuePlace) data['issuePlace'] = issuePlace;
  const governorate = cleanOptional(record.governorate);
  if (governorate) data['governorate'] = governorate;
  const notes = cleanOptional(record.notes);
  if (notes) data['notes'] = notes;

  // الحقول الاختيارية من المستند الحالي (لا نفقدها)
  if (existingDoc.serverId != null) data['serverId'] = existingDoc.serverId;
  if (existingDoc.deletedAt != null) data['deletedAt'] = existingDoc.deletedAt;
  if (existingDoc.createdAtIso) data['createdAtIso'] = existingDoc.createdAtIso;
  if (existingDoc.updatedAtIso) data['updatedAtIso'] = existingDoc.updatedAtIso;
  if (existingDoc.deletedAtIso) data['deletedAtIso'] = existingDoc.deletedAtIso;

  return data;
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  مزامنة guest_infos من CSV');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  CSV file: ' + csvPath);
  console.log('═══════════════════════════════════════════════════════════════\n');

  // 1) اقرأ CSV
  console.log('📥 Reading CSV...');
  const csvRecords = parseCSV(csvPath);
  console.log('   ✅ Parsed ' + csvRecords.length + ' records from CSV\n');

  // 2) اقرأ كل المستندات من Appwrite Cloud
  console.log('📦 Reading all documents from Appwrite Cloud...');
  const cloudDocs = await listAllDocuments();
  console.log('   ✅ Found ' + cloudDocs.length + ' documents\n');

  // 3) طابق كل سجل CSV مع مستند موجود (بـ idNumber + roomNumber + part of name)
  console.log('🔗 Matching CSV records to cloud documents...\n');

  // بناء index للمستندات بـ idNumber + roomNumber
  // كل مفتاح يحتوي على قائمة من المستندات (للسجلات المكررة)
  const docIndex = new Map();
  for (const doc of cloudDocs) {
    const key = (doc.idNumber || '') + '|' + (doc.roomNumber || '');
    if (!docIndex.has(key)) {
      docIndex.set(key, []);
    }
    docIndex.get(key).push(doc);
  }

  let updated = 0;
  let created = 0;
  let failed = 0;
  const matchedDocIds = new Set();

  // ✅ نتبع المستندات المستخدمة لكل مفتاح حتى لا نطابق نفس المستند مرتين
  const usedDocsPerKey = new Map(); // key → Set of doc.$id

  for (let i = 0; i < csvRecords.length; i++) {
    const record = csvRecords[i];
    process.stdout.write('  [' + (i + 1) + '/' + csvRecords.length + '] #' + record.num + ' ' + record.guestName.substring(0, 30) + '... ');

    const key = record.idNumber + '|' + record.roomNumber;
    const candidates = docIndex.get(key) || [];
    if (!usedDocsPerKey.has(key)) usedDocsPerKey.set(key, new Set());
    const usedSet = usedDocsPerKey.get(key);

    // ابحث عن مستند لم يُستخدم بعد
    let targetDoc = null;

    // 1) ابحث عن مطابقة بالاسم (أول 10 أحرف) في المرشحين غير المستخدمين
    for (const doc of candidates) {
      if (usedSet.has(doc.$id)) continue;
      const docName = (doc.guestName || '').trim();
      const csvName = record.guestName.trim();
      // مطابقة بـ substring (أول 10 أحرف)
      if (docName.substring(0, 10) === csvName.substring(0, 10)) {
        targetDoc = doc;
        break;
      }
    }

    // 2) إن لم نجد مطابقة بالاسم، خذ أول مستند غير مستخدم
    if (!targetDoc) {
      for (const doc of candidates) {
        if (!usedSet.has(doc.$id)) {
          targetDoc = doc;
          break;
        }
      }
    }

    if (targetDoc) {
      // ✅ تحديث المستند الموجود بالبيانات الصحيحة من CSV
      try {
        const payload = buildPayload(record, targetDoc);
        await databases.updateDocument(databaseId, collectionId, targetDoc.$id, payload);
        console.log('✏️  updated');
        updated++;
        matchedDocIds.add(targetDoc.$id);
        usedSet.add(targetDoc.$id);
      } catch (e) {
        console.log('❌ ' + e.message);
        failed++;
      }
    } else {
      // ❌ لا يوجد مستند مطابق متبقٍ — أنشئ جديداً بـ UUID عشوائي
      try {
        const newUuid = require('crypto').randomUUID();
        const now = Math.floor(Date.now() / 1000);
        const payload = {
          'localUuid': newUuid,
          'roomNumber': record.roomNumber,
          'guestName': record.guestName,
          'nationality': record.nationality || 'غير محدد',
          'idNumber': record.idNumber,
          'createdAt': now,
          'updatedAt': now,
          'lastModified': now,
          'version': 1,
          'origin': 'local',
          'vectorClock': '{}',
        };
        if (record.idType && record.idType !== '-') payload['idType'] = record.idType;
        const issueDate = cleanOptional(record.issueDate);
        if (issueDate) payload['issueDate'] = issueDate;
        const issuePlace = cleanOptional(record.issuePlace);
        if (issuePlace) payload['issuePlace'] = issuePlace;
        const governorate = cleanOptional(record.governorate);
        if (governorate) payload['governorate'] = governorate;
        const notes = cleanOptional(record.notes);
        if (notes) payload['notes'] = notes;

        await databases.createDocument(databaseId, collectionId, newUuid, payload);
        console.log('✨ created (new UUID)');
        created++;
        matchedDocIds.add(newUuid);
      } catch (e) {
        console.log('❌ create failed: ' + e.message);
        failed++;
      }
    }

    await new Promise(r => setTimeout(r, 200));
  }

  // 4) احذف المستندات غير الموجودة في CSV
  console.log('\n🗑️  Deleting documents NOT in CSV...');
  const toDelete = cloudDocs.filter(doc => !matchedDocIds.has(doc.$id));
  console.log('   ' + toDelete.length + ' documents to delete\n');

  let deleted = 0;
  let deleteFailed = 0;

  for (let i = 0; i < toDelete.length; i++) {
    const doc = toDelete[i];
    const name = doc.guestName || '?';
    process.stdout.write('  [' + (i + 1) + '/' + toDelete.length + '] ' + name.substring(0, 30) + '... ');
    try {
      await databases.deleteDocument(databaseId, collectionId, doc.$id);
      console.log('🗑️  deleted');
      deleted++;
    } catch (e) {
      console.log('❌ ' + e.message);
      deleteFailed++;
    }
    await new Promise(r => setTimeout(r, 200));
  }

  // 5) تحقق من العدد النهائي
  console.log('\n🔍 Verifying final count...');
  const finalDocs = await listAllDocuments();

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  الملخص النهائي');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  📥 CSV records:       ' + csvRecords.length);
  console.log('  📦 Cloud docs (was):  ' + cloudDocs.length);
  console.log('  ✏️  Updated:           ' + updated);
  console.log('  ✨ Created:           ' + created);
  console.log('  ❌ Update failed:     ' + failed);
  console.log('  🗑️  Deleted (not CSV): ' + deleted);
  console.log('  ❌ Delete failed:     ' + deleteFailed);
  console.log('  📦 العدد النهائي:      ' + finalDocs.length);
  console.log('');
  if (finalDocs.length === csvRecords.length) {
    console.log('  ✅ العدد مطابق للـ CSV (' + csvRecords.length + ' سجل)!');
  } else {
    console.log('  ⚠️  العدد غير مطابق. متوقّع: ' + csvRecords.length + '، فعلي: ' + finalDocs.length);
  }
}

main().catch(e => {
  console.error('Fatal:', e.message);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
