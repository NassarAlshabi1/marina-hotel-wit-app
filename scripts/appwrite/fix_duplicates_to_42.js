#!/usr/bin/env node
/**
 * تحديث guest_infos ليحتوي على **42 سجل فريد** (وليس 37).
 *
 * المشكلة السابقة: السكريبت السابق أعطى السجلات المكررة (بنفس idNumber
 * لكن بأسماء مختلفة قليلاً) نفس UUID، فتم دمجها بدل الحفاظ عليها كـ
 * سجلين منفصلين. النتيجة: 37 مستند بدل 42.
 *
 * السجلات المكررة في PDF (نفس idNumber، أسماء مختلفة):
 *   - سجل 1 (امجد هادي الجيشي) ≈ سجل 7 (امجد هلال الجبيشي) — idNumber 1011122527
 *   - سجل 2 (معتز هادي الجيشي) ≈ سجل 8 (معتز هلال الجبيشي) — idNumber 01210083756
 *   - سجل 4 (محمد بكيل) ≈ سجل 12 (محمد بكيل) — idNumber 11010335859
 *   - سجل 5 (نجيب) ≈ سجل 13 (نجيب) — idNumber 11010062424
 *   - سجل 3 (اسماعيل) ≈ سجل 10 (اسماعيل) — idNumber 11010334537
 *
 * الحل: إنشاء UUIDs جديدة للسجلات المتكررة (7, 8, 10, 12, 13) بحيث
 * يصبح لكل سجل UUID فريد، ثم upsert كـ create جديد.
 *
 * النتيجة المتوقّعة: 42 مستند في Appwrite Cloud.
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node fix_duplicates_to_42.js
 */

const { Client, Databases, Query } = require('node-appwrite');
const crypto = require('crypto');

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

// توليد UUID v4 عشوائي
function generateUuid() {
  return crypto.randomUUID();
}

// ═══ الـ 42 سجل من PDF (كل سجل بـ UUID فريد) ═══════════════════════════════
// الصيغة: [localUuid, roomNumber, guestName, nationality, idNumber, idType, issueDate, issuePlace, governorate, notes]
// ملاحظة: السجلات 7,8,10,12,13 ستأخذ UUIDs جديدة (لأنها كانت مكررة)
const pdfRecords = [
  // ─── الصفحة 1 (سجلات 1-23) ──────────────────────────────────────────────
  ['1dc137b8-e3f0-4a97-83e5-fe526228e8f3', '401', 'امجد عبدالعزيز احمد هادي الجيشي', 'يمني', '1011122527', 'بطاقة شخصية', '2021-12-04', 'الامانة', 'حجة', '-'],
  ['0b0d0d88-b460-4d71-9560-73b21c92bbe5', '401', 'معتز صالح احمد هادي الجيشي', 'يمني', '01210083756', 'بطاقة شخصية', '2025-01-26', 'الامانة', 'حجة', '-'],
  ['eef2c0ec-fc61-4e72-a90e-8c5442d29aa9', '402', 'اسماعيل ابراهيم صالح احمد العلفي', 'يمني', '11010334537', 'بطاقة شخصية', '2025-03-25', 'المجمع الخدمي الامانه', 'حجه', ''],
  ['428e4a77-9808-44f4-81f5-5e4c7c04fa63', '402', 'محمد بكيل ناصر علي العلفي', 'يمني', '11010335859', 'بطاقة شخصية', '2025-04-30', 'حجه', 'حجه', ''],
  ['2e42dadc-1c5b-4aa8-b44c-db15eaa41d6c', '402', 'نجيب حميد احمد العلفي', 'يمني', '11010062424', 'بطاقة شخصية', '2013-12-03', 'حجه', 'حجه', ''],
  ['5f547113-ea00-4c07-9653-8e1dc42a22ea', '401', 'جابر ابراهيم محمد الحيشي', 'يمني', '01010885287', 'بطاقة شخصية', '2016-12-10', 'الامانة', 'حجة', '-'],
  // ✅ سجل 7: امجد هلال الجبيشي (UUID جديد — كان مكرر مع سجل 1)
  [generateUuid(), '401', 'امجد عبدالعزيز احمد هلال الجبيشي', 'يمني', '1011122527', 'بطاقة شخصية', '2021-12-04', 'الامانة', 'حجة', '-'],
  // ✅ سجل 8: معتز هلال الجبيشي (UUID جديد — كان مكرر مع سجل 2)
  [generateUuid(), '401', 'معتز صالح احمد هلال الجبيشي', 'يمني', '01210083756', 'بطاقة شخصية', '2025-01-26', 'الامانة', 'حجة', '-'],
  ['3c55429b-9a7e-4cee-ac96-5d5824b07af4', '402', 'ابراهيم صالح احمد العلفي', 'يمني', '0111006976', 'بطاقة شخصية', '2025-03-23', 'الامانة', 'حجة', '-'],
  // ✅ سجل 10: اسماعيل (UUID جديد — كان مكرر مع سجل 3)
  [generateUuid(), '402', 'اسماعيل ابراهيم صالح احمد العلفي', 'يمني', '11010334537', 'بطاقة شخصية', '2025-03-25', 'المجمع الخدمي الامانه', 'حجة', '-'],
  ['9f0a2b12-e978-4152-9a98-bb30b8cbe87a', '402', 'محمد ابراهيم صالح احمد العلفي', 'يمني', '11010334665', 'بطاقة شخصية', '2025-03-26', 'مركز حجه', 'حجة', '-'],
  // ✅ سجل 12: محمد بكيل (UUID جديد — كان مكرر مع سجل 4)
  [generateUuid(), '402', 'محمد بكيل ناصر علي العلفي', 'يمني', '11010335859', 'بطاقة شخصية', '2025-04-30', 'حجة', 'حجة', '-'],
  // ✅ سجل 13: نجيب (UUID جديد — كان مكرر مع سجل 5)
  [generateUuid(), '402', 'نجيب حميد احمد العلفي', 'يمني', '11010062424', 'بطاقة شخصية', '2013-12-03', 'حجة', 'حجة', '-'],
  ['f102ab17-cc5b-4033-bf10-4c763f755544', '302', 'فايز صالح عبدالله ابوجعلان', 'يمني', '11010257418', 'بطاقة شخصية', '2021-08-07', 'حجة', 'حجة', '-'],
  ['743431fa-2091-4ac4-8907-498bd51814cf', '302', 'محمد عبدالله عثمان ابوجعلان', 'يمني', '11010132753', 'بطاقة شخصية', '2025-06-30', 'حجة', 'حجة', '-'],
  ['e36892de-0fd1-4f91-ad7d-3b2560a543ff', '302', 'صالح عادل صالح عبدالله', 'يمني', '11010141571', 'بطاقة شخصية', '2025-03-15', 'حجة', 'حجة', '-'],
  ['f1139284-d12d-4901-857f-2b7e35447d0f', '302', 'هيثم صالح عبدالله ابوجعلان', 'يمني', '11010116496', 'بطاقة شخصية', '2015-10-17', 'حجة', 'حجة', '-'],
  ['b9d082a9-f799-4b4e-8c62-c70f84afdc6e', '302', 'بشير محمد غالب احمد', 'يمني', '11010042290', 'بطاقة شخصية', '2012-09-03', 'حجة', 'حجة', '-'],
  ['7920e0bc-9383-4077-8c61-22c2fb002889', '302', 'عثمان عبدالله عثمان ابوجعلان', 'يمني', '1010115103', 'بطاقة شخصية', '2015-10-21', 'حجة', 'حجة', '-'],
  ['7546b8b1-2c2b-4b94-ba97-486f955fc0de', '403', 'مشير علي دحان جهلان', 'يمني', '11010247839', 'بطاقة شخصية', '2021-04-29', 'حجة', 'حجة', '-'],
  ['78933c7f-379f-442b-ae14-7fdd7824985d', '403', 'عصام دحان فرحان', 'يمني', '1010118832', 'بطاقة شخصية', '2015-12-28', 'حجة', 'حجة', '-'],
  ['899c0996-603c-437e-b484-0a2c438ae0fb', '403', 'فواز يحيى احمد العلفي', 'يمني', '11010125704', 'بطاقة شخصية', '2023-01-18', 'حجة', 'حجة', '-'],
  ['275c06e8-0315-4469-b942-8aa70a4df327', '201', 'وجدي كامل صالح يحيى', 'يمني', '01011228663', 'بطاقة شخصية', '2024-02-04', 'حجة', 'حجة', '-'],

  // ─── الصفحة 2 (سجلات 24-42) ─────────────────────────────────────────────
  ['6f7f5b9d-2a5c-4e2f-b233-d26ff2fed676', '201', 'امجد عبدالعزيز احمد', 'يمني', '01011122527', 'بطاقة شخصية', '2021-12-04', 'الامانة', 'حجة', '-'],
  ['111aab67-0869-4e69-9b10-33bbd05d2169', '201', 'شواف قائد صالح يحيى', 'يمني', '11210040259', 'بطاقة شخصية', '2025-07-08', 'عبس حجة', 'حجة', '-'],
  ['46d5b078-502b-4f77-ba9b-436aa0579d28', '303', 'شايف قائد صالح', 'يمني', '11210040263', 'بطاقة شخصية', '2025-07-08', 'حجة', 'حجة', '-'],
  ['cd263018-0a22-417c-b983-39db2ec534fc', '303', 'اسامه علي يحيى علي', 'يمني', '02410032099', 'بطاقة شخصية', '2024-02-20', 'صنعاء', 'حجة', '-'],
  ['befcc279-ce69-4efc-a24a-8eab3490c38a', '303', 'يحيى علي يحيى الجبيشي', 'يمني', '13181', 'شهادة ميلاد', '2025-02-01', 'حجة', 'حجة', '-'],
  ['a2cb45fd-c28b-4fe9-a4d3-189f94ea83fe', '304', 'عادل هبه علي يحيى كرد', 'يمني', '16534996', 'بطاقة شخصية', '2026-01-11', 'عدن', 'الحديدة', 'دخول 12/4/2026'],
  ['ddcaf59c-2678-410a-b1b3-6b3067639f15', '303', 'صالح احمد هلال الجبيشي', 'يمني', '01010867524', 'بطاقة شخصية', '2025-12-30', 'الامانة', 'حجة', '-'],
  ['0857a23d-12c5-4da5-83a5-8c95a0a3bbde', '401', 'جابر ابراهيم محمد الحبيشي', 'يمني', '01010885287', 'بطاقة شخصية', '2016-12-10', 'الامانة', 'حجة', '-'],
  ['fd322339-df02-4092-bd66-40bbad604c96', '404', 'احمد مبروك علي عثمان', 'يمني', '11723282', 'جواز سفر', '2022-01-01', 'عدن', 'الحديدة', '-'],
  ['2e212a7d-8fe1-4d63-bb98-d239234d48a5', '302', 'محمد عبدالله عثمان جهلان', 'يمني', '11010132783', 'بطاقة شخصية', '2025-06-30', 'حجه', 'حجه', ''],
  ['38e1fc9e-db47-4c64-a089-3fc8f5d7def2', '302', 'صالح عادل صالح عبدالله ابوجهلان', 'يمني', '11010141571', 'بطاقة شخصية', '2025-03-15', 'حجه', 'حجه', ''],
  ['1370483f-dcd6-4760-8b56-3781385f6c03', '402', 'فضل عبدالله يحيى يحيى العلفي', 'يمني', '11010306686', 'بطاقة شخصية', '2023-07-26', 'حجه', 'حجه', ''],
  ['483cfb3b-cc5b-43df-b278-8a849404b2c6', '402', 'ياسين سعد ناصر درهم جهلان', 'يمني', '11010343663', 'بطاقة شخصية', '2025-10-22', 'حجه', 'حجه', ''],
  ['b7b5e139-0767-409c-becd-bb0635cfaf5a', '303', 'نبيل علي صالح القح', 'يمني', '14181186', 'بطاقة شخصية', '2024-06-11', 'جيبوتي', 'اب', ''],
  ['c45f83ec-2722-433a-8b3f-183767402439', '101', 'زينب عبدالله صالح محمد الحميدي', 'يمني', '05000046823', 'بطاقة شخصية', '2025-07-23', 'الحديدة', 'الحديدة', ''],
  ['af035c6b-93ec-4cb1-bc70-6f4ed17ed9aa', '101', 'عبدالله صالح محمد الحميدي', 'يمني', '05110129518', 'بطاقة شخصية', '', 'الحديدة', 'الحديدة', 'استبيان'],
  ['4e2e9449-6637-43a7-a4b3-fb66f360d879', '201', 'زكريا ياسين عبدالرحمن احمد المشرقي', 'يمني', '531010443426', 'بطاقة شخصية', '2024-12-07', 'تعز', 'تعز', ''],
  ['00000000-0000-4000-8000-000000000041', '104', 'خالد عبدة علي مرعي', 'يمني', '15010036289', 'بطاقة شخصية', '2025-10-20', 'اب', 'اب', ''],
  ['00000000-0000-4000-8000-000000000042', '104', 'رياض عبدالسلام محمد ناصر الجيلاني', 'يمني', '504722953032', 'بطاقة شخصية', '2025-10-30', 'عدن', 'الضالع', ''],
];

function cleanOptional(value) {
  if (value === '-' || value === '' || value == null) return null;
  return value;
}

function buildPayload(row) {
  const [localUuid, roomNumber, guestName, nationality, idNumber, idType,
         issueDate, issuePlace, governorate, notes] = row;

  const now = Math.floor(Date.now() / 1000);

  const data = {
    'localUuid': localUuid,
    'roomNumber': roomNumber || 'N/A',
    'guestName': guestName,
    'nationality': nationality || 'غير محدد',
    'idNumber': idNumber || 'N/A',
    'createdAt': now,
    'updatedAt': now,
    'lastModified': now,
    'version': 1,
    'origin': 'local',
    'vectorClock': '{}',
  };

  const idTypeVal = cleanOptional(idType);
  if (idTypeVal) data['idType'] = idTypeVal;
  const issueDateVal = cleanOptional(issueDate);
  if (issueDateVal) data['issueDate'] = issueDateVal;
  const issuePlaceVal = cleanOptional(issuePlace);
  if (issuePlaceVal) data['issuePlace'] = issuePlaceVal;
  const governorateVal = cleanOptional(governorate);
  if (governorateVal) data['governorate'] = governorateVal;
  const notesVal = cleanOptional(notes);
  if (notesVal) data['notes'] = notesVal;

  return data;
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  إصلاح التكرارات — استعادة الـ 42 سجل كاملة');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  PDF records: ' + pdfRecords.length);
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('');

  // عرض الـ UUIDs الجديدة للسجلات المكررة
  console.log('📝 السجلات المكررة مع UUIDs جديدة:');
  for (let i = 0; i < pdfRecords.length; i++) {
    const row = pdfRecords[i];
    // السجلات 7,8,10,12,13 (indexes 6,7,9,11,12) — UUIDs جديدة
    if ([6, 7, 9, 11, 12].includes(i)) {
      console.log('  سجل #' + (i + 1) + ': ' + row[2] + ' → ' + row[0]);
    }
  }
  console.log('');

  // 1) Upsert كل سجل (السجلات المكررة ستُنشأ كـ create جديد لأن UUIDs جديدة)
  console.log('📥 Upserting ' + pdfRecords.length + ' records...');
  let updated = 0, created = 0, failed = 0;

  for (let i = 0; i < pdfRecords.length; i++) {
    const row = pdfRecords[i];
    const localUuid = row[0];
    const guestName = row[2];
    process.stdout.write('  [' + (i + 1) + '/' + pdfRecords.length + '] ' + guestName.substring(0, 30) + '... ');
    try {
      const data = buildPayload(row);
      // نحاول update أولاً، إن فشل (404) نحاول create
      try {
        await databases.updateDocument(databaseId, collectionId, localUuid, data);
        console.log('✏️  updated');
        updated++;
      } catch (e) {
        if (e.code !== 404) throw e;
        await databases.createDocument(databaseId, collectionId, localUuid, data);
        console.log('✨ created');
        created++;
      }
    } catch (e) {
      console.log('❌ ' + e.message);
      failed++;
    }
    await new Promise((r) => setTimeout(r, 200));
  }

  // 2) تحقق من العدد النهائي
  console.log('');
  console.log('🔍 Verifying final count...');
  let total = 0;
  let cursor = null;
  while (true) {
    const queries = [Query.limit(100)];
    if (cursor) queries.push(Query.cursorAfter(cursor));
    const result = await databases.listDocuments(databaseId, collectionId, queries);
    if (result.documents.length === 0) break;
    total += result.documents.length;
    if (result.documents.length < 100) break;
    cursor = result.documents[result.documents.length - 1].$id;
  }

  console.log('');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  الملخص النهائي');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  📥 PDF records:    ' + pdfRecords.length);
  console.log('  ✏️  Updated:        ' + updated);
  console.log('  ✨ Created:        ' + created);
  console.log('  ❌ Failed:         ' + failed);
  console.log('  📦 العدد النهائي:   ' + total);
  console.log('');
  if (total === 42) {
    console.log('  ✅ النتيجة مطابقة للمتوقّع (42 سجل)!');
  } else {
    console.log('  ⚠️  العدد غير مطابق. متوقّع: 42، فعلي: ' + total);
  }
}

main().catch((e) => {
  console.error('Fatal:', e.message || e);
  if (e.stack) console.error(e.stack);
  process.exit(1);
});
