#!/usr/bin/env node
/**
 * فحص + تصحيح أسماء guest_infos لتطابق PDF بدقة.
 *
 * يقرأ كل المستندات من Appwrite Cloud، يطابقها مع قائمة الأسماء الصحيحة
 * من PDF (بالتطابق على idNumber + roomNumber)، ويُحدّث الأسماء غير المطابقة.
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

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

// ═══ الأسماء الدقيقة من PDF (مطابقة بـ idNumber + roomNumber) ══════════════
// الصيغة: { idNumber, roomNumber, correctGuestName, correctIssuePlace, correctGovernorate }
const pdfCorrectData = [
  // الصفحة 1 (1-23)
  { id: '1011122527', room: '401', name: 'امجد عبدالعزيز احمد هادي الجيشي', place: 'الامانة', gov: 'حجة' },
  { id: '01210083756', room: '401', name: 'معتز صالح احمد هادي الجيشي', place: 'الامانة', gov: 'حجة' },
  { id: '11010334537', room: '402', name: 'اسماعيل ابراهيم صالح احمد العلفي', place: 'المجمع الخدمي الامانه', gov: 'حجه' },
  { id: '11010335859', room: '402', name: 'محمد بكيل ناصر علي العلفي', place: 'حجه', gov: 'حجه' },
  { id: '11010062424', room: '402', name: 'نجيب حميد احمد العلفي', place: 'حجه', gov: 'حجه' },
  { id: '01010885287', room: '401', name: 'جابر ابراهيم محمد الحيشي', place: 'الامانة', gov: 'حجة' },
  { id: '1011122527', room: '401', name: 'امجد عبدالعزيز احمد هلال الجبيشي', place: 'الامانة', gov: 'حجة' }, // 7
  { id: '01210083756', room: '401', name: 'معتز صالح احمد هلال الجبيشي', place: 'الامانة', gov: 'حجة' }, // 8
  { id: '0111006976', room: '402', name: 'ابراهيم صالح احمد العلفي', place: 'الامانة', gov: 'حجة' },
  { id: '11010334537', room: '402', name: 'اسماعيل ابراهيم صالح احمد العلفي', place: 'المجمع الخدمي الامانه', gov: 'حجة' }, // 10
  { id: '11010334665', room: '402', name: 'محمد ابراهيم صالح احمد العلفي', place: 'مركز حجه', gov: 'حجة' },
  { id: '11010335859', room: '402', name: 'محمد بكيل ناصر علي العلفي', place: 'حجة', gov: 'حجة' }, // 12
  { id: '11010062424', room: '402', name: 'نجيب حميد احمد العلفي', place: 'حجة', gov: 'حجة' }, // 13
  { id: '11010257418', room: '302', name: 'فايز صالح عبدالله ابوجعلان', place: 'حجة', gov: 'حجة' },
  { id: '11010132753', room: '302', name: 'محمد عبدالله عثمان ابوجعلان', place: 'حجة', gov: 'حجة' },
  { id: '11010141571', room: '302', name: 'صالح عادل صالح عبدالله', place: 'حجة', gov: 'حجة' },
  { id: '11010116496', room: '302', name: 'هيثم صالح عبدالله ابوجعلان', place: 'حجة', gov: 'حجة' },
  { id: '11010042290', room: '302', name: 'بشير محمد غالب احمد', place: 'حجة', gov: 'حجة' },
  { id: '1010115103', room: '302', name: 'عثمان عبدالله عثمان ابوجعلان', place: 'حجة', gov: 'حجة' },
  { id: '11010247839', room: '403', name: 'مشير علي دحان جهلان', place: 'حجة', gov: 'حجة' },
  { id: '1010118832', room: '403', name: 'عصام دحان فرحان', place: 'حجة', gov: 'حجة' },
  { id: '11010125704', room: '403', name: 'فواز يحيى احمد العلفي', place: 'حجة', gov: 'حجة' },
  { id: '01011228663', room: '201', name: 'وجدي كامل صالح يحيى', place: 'حجة', gov: 'حجة' },
  // الصفحة 2 (24-42)
  { id: '01011122527', room: '201', name: 'امجد عبدالعزيز احمد', place: 'الامانة', gov: 'حجة' },
  { id: '11210040259', room: '201', name: 'شواف قائد صالح يحيى', place: 'عبس حجة', gov: 'حجة' },
  { id: '11210040263', room: '303', name: 'شايف قائد صالح', place: 'حجة', gov: 'حجة' },
  { id: '02410032099', room: '303', name: 'اسامه علي يحيى علي', place: 'صنعاء', gov: 'حجة' },
  { id: '13181', room: '303', name: 'يحيى علي يحيى الجبيشي', place: 'حجة', gov: 'حجة' },
  { id: '16534996', room: '304', name: 'عادل هبه علي يحيى كرد', place: 'عدن', gov: 'الحديدة' },
  { id: '01010867524', room: '303', name: 'صالح احمد هلال الجبيشي', place: 'الامانة', gov: 'حجة' },
  { id: '01010885287', room: '401', name: 'جابر ابراهيم محمد الحبيشي', place: 'الامانة', gov: 'حجة' },
  { id: '11723282', room: '404', name: 'احمد مبروك علي عثمان', place: 'عدن', gov: 'الحديدة' },
  { id: '11010132783', room: '302', name: 'محمد عبدالله عثمان جهلان', place: 'حجه', gov: 'حجه' },
  { id: '11010141571', room: '302', name: 'صالح عادل صالح عبدالله ابوجهلان', place: 'حجه', gov: 'حجه' }, // 34 (نفس 16 لكن اسم مختلف)
  { id: '11010306686', room: '402', name: 'فضل عبدالله يحيى يحيى العلفي', place: 'حجه', gov: 'حجه' },
  { id: '11010343663', room: '402', name: 'ياسين سعد ناصر درهم جهلان', place: 'حجه', gov: 'حجه' },
  { id: '14181186', room: '303', name: 'نبيل علي صالح القح', place: 'جيبوتي', gov: 'اب' },
  { id: '05000046823', room: '101', name: 'زينب عبدالله صالح محمد الحميدي', place: 'الحديدة', gov: 'الحديدة' },
  { id: '05110129518', room: '101', name: 'عبدالله صالح محمد الحميدي', place: 'الحديدة', gov: 'الحديدة' },
  { id: '531010443426', room: '201', name: 'زكريا ياسين عبدالرحمن احمد المشرقي', place: 'تعز', gov: 'تعز' },
  { id: '15010036289', room: '104', name: 'خالد عبدة علي مرعي', place: 'اب', gov: 'اب' },
  { id: '504722953032', room: '104', name: 'رياض عبدالسلام محمد ناصر الجيلاني', place: 'عدن', gov: 'الضالع' },
];

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

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  فحص + تصحيح أسماء guest_infos لتطابق PDF');
  console.log('═══════════════════════════════════════════════════════════════\n');

  const docs = await listAllDocuments();
  console.log('📦 Found ' + docs.length + ' documents\n');

  let matched = 0;
  let corrected = 0;
  let unmatched = 0;
  const corrections = [];

  // لكل مستند، ابحث عن المطابقة في PDF
  for (const doc of docs) {
    const docId = doc.$id;
    const docName = doc.guestName || '';
    const docIdNumber = doc.idNumber || '';
    const docRoom = doc.roomNumber || '';
    const docPlace = doc.issuePlace || '';
    const docGov = doc.governorate || '';

    // ابحث عن سجل PDF مطابق (idNumber + roomNumber)
    // لكن بعض السجلات لها نفس idNumber لكن أسماء مختلفة (مثل 1 و 7)
    // في هذه الحالة نطابق بـ idNumber + roomNumber + part of name
    const candidates = pdfCorrectData.filter(p => p.id === docIdNumber && p.room === docRoom);

    let pdfMatch = null;
    if (candidates.length === 1) {
      pdfMatch = candidates[0];
    } else if (candidates.length > 1) {
      // ابحث عن الأقرب بالاسم
      pdfMatch = candidates.find(c => c.name === docName) || candidates[0];
    }

    if (!pdfMatch) {
      console.log('⚠️  No PDF match for: ' + docName + ' (id: ' + docIdNumber + ', room: ' + docRoom + ')');
      unmatched++;
      continue;
    }

    matched++;

    // تحقق من تطابق الاسم
    const needsNameFix = docName !== pdfMatch.name;
    const needsPlaceFix = docPlace !== pdfMatch.place && pdfMatch.place;
    const needsGovFix = docGov !== pdfMatch.gov && pdfMatch.gov;

    if (needsNameFix || needsPlaceFix || needsGovFix) {
      const updates = {};
      if (needsNameFix) updates.guestName = pdfMatch.name;
      if (needsPlaceFix) updates.issuePlace = pdfMatch.place;
      if (needsGovFix) updates.governorate = pdfMatch.gov;

      console.log('✏️  Correcting: ' + docName.substring(0, 30) + '...');
      if (needsNameFix) console.log('     name: "' + docName + '" → "' + pdfMatch.name + '"');
      if (needsPlaceFix) console.log('     place: "' + docPlace + '" → "' + pdfMatch.place + '"');
      if (needsGovFix) console.log('     gov: "' + docGov + '" → "' + pdfMatch.gov + '"');

      try {
        await databases.updateDocument(databaseId, collectionId, docId, updates);
        console.log('     ✅ Updated');
        corrected++;
        corrections.push({ docId, oldName: docName, newName: pdfMatch.name });
      } catch (e) {
        console.log('     ❌ ' + e.message);
      }
      await new Promise(r => setTimeout(r, 200));
    } else {
      console.log('✓ ' + docName.substring(0, 30) + ' — already correct');
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  الملخص');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  📦 Total documents: ' + docs.length);
  console.log('  ✅ Matched to PDF:  ' + matched);
  console.log('  ✏️  Corrected:       ' + corrected);
  console.log('  ⚠️  Unmatched:       ' + unmatched);
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
