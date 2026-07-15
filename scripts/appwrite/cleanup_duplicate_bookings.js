#!/usr/bin/env node
/**
 * تنظيف الحجوزات المكررة + إعادة ربط المدفوعات اليتيمة على Appwrite Cloud.
 *
 * المشكلة: 7 أزواج حجوزات مكررة (نفس النزيل + غرفة، UUID مختلف). المدفوعات
 * المرتبطة بأحد النسختين لا تجد الحجز عند السحب على جهاز آخر لأن
 * bookingUuidCache لا يطابق localUuid أي نسخة محلية.
 *
 * الحل:
 *   1. لكل زوج مكرر: احذف النسخة "الأسوأ" (أقل بيانات/أقدم)
 *   2. حدّث bookingUuidCache في المدفوعات المرتبطة بالنسخة المحذوفة
 *      لتشير إلى النسخة المُبقاة
 *   3. حدّث bookingLocalId في المدفوعات لتشير للنسخة المُبقاة
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node cleanup_duplicate_bookings.js
 */

const { Client, Databases, Query } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

async function listAll(coll) {
  const docs = [];
  let cursor = null;
  while (true) {
    const q = [Query.limit(100)];
    if (cursor) q.push(Query.cursorAfter(cursor));
    const r = await databases.listDocuments(databaseId, coll, q);
    if (r.documents.length === 0) break;
    docs.push(...r.documents);
    if (r.documents.length < 100) break;
    cursor = r.documents[r.documents.length - 1].$id;
  }
  return docs;
}

function score(doc) {
  // كلما زادScore، كان السجل "أفضل" (أكثر بيانات)
  let s = 0;
  if (doc.totalDueCached != null && doc.totalDueCached > 0) s += 5;
  if (doc.totalPaidCached != null && doc.totalPaidCached > 0) s += 5;
  if (doc.actualCheckout && doc.actualCheckout.length > 0) s += 3;
  if (doc.checkinDate && doc.checkinDate.length > 0) s += 2;
  if (doc.checkoutDate && doc.checkoutDate.length > 0) s += 2;
  if (doc.guestPhone && doc.guestPhone.length > 0) s += 1;
  if (doc.notes && doc.notes.length > 0) s += 1;
  if (doc.version) s += doc.version;
  if (doc.lastModified) s += 1;
  return s;
}

async function main() {
  console.log('═'.repeat(80));
  console.log('  تنظيف الحجوزات المكررة + إعادة ربط المدفوعات');
  console.log('═'.repeat(80) + '\n');

  // 1) اقرأ كل الحجوزات والمدفوعات
  console.log('📥 Reading bookings...');
  const bookings = await listAll('bookings');
  console.log('   ✅ ' + bookings.length + ' bookings');

  console.log('📥 Reading payments...');
  const payments = await listAll('payments');
  console.log('   ✅ ' + payments.length + ' payments\n');

  // 2) ابحث عن أزواج مكررة (نفس guestName + roomNumber)
  const byGuest = {};
  for (const b of bookings) {
    const key = (b.guestName || '') + '|' + (b.roomNumber || '');
    if (!byGuest[key]) byGuest[key] = [];
    byGuest[key].push(b);
  }
  const duplicates = Object.entries(byGuest).filter(([k, v]) => v.length > 1);
  console.log('🔁 Duplicate booking pairs: ' + duplicates.length + '\n');

  if (duplicates.length === 0) {
    console.log('✨ No duplicates found.');
    return;
  }

  // 3) لكل زوج، حدد أي نسخة نُبقي وأي نحذف
  let bookingsDeleted = 0;
  let paymentsRelinked = 0;
  let paymentsFailed = 0;

  for (const [key, group] of duplicates) {
    console.log('─'.repeat(80));
    console.log('📋 "' + key + '" (' + group.length + ' copies)');

    // رتّب حسب score (الأفضل أولاً)
    const scored = group.map(d => ({ doc: d, score: score(d) }));
    scored.sort((a, b) => b.score - a.score);

    const keep = scored[0].doc;
    const toDelete = scored.slice(1).map(s => s.doc);

    console.log('   ✅ Keep: ' + keep.$id + ' (score=' + scored[0].score + ', status=' + keep.status + ')');

    for (const del of toDelete) {
      console.log('   🗑️  Delete: ' + del.$id + ' (score=' + score(del) + ', status=' + del.status + ')');

      // ابحث عن مدفوعات تشير إلى النسخة المحذوفة
      const orphanPayments = payments.filter(p => {
        return p.bookingUuidCache === del.localUuid ||
               p.bookingUuidCache === del.$id ||
               (p.bookingUuidCache && p.bookingUuidCache.replace(/-/g, '') === del.localUuid.replace(/-/g, ''));
      });

      if (orphanPayments.length > 0) {
        console.log('   📎 Found ' + orphanPayments.length + ' payments to relink');

        for (const p of orphanPayments) {
          try {
            await databases.updateDocument(databaseId, 'payments', p.$id, {
              bookingUuidCache: keep.localUuid,
            });
            console.log('      ✅ Relinked payment ' + p.$id.substring(0, 12) + '...');
            paymentsRelinked++;
          } catch (e) {
            console.log('      ❌ Failed to relink payment ' + p.$id.substring(0, 12) + ': ' + e.message);
            paymentsFailed++;
          }
          await new Promise(r => setTimeout(r, 200));
        }
      }

      // احذف الحجز المكرر
      try {
        await databases.deleteDocument(databaseId, 'bookings', del.$id);
        console.log('   🗑️  Deleted booking ' + del.$id);
        bookingsDeleted++;
      } catch (e) {
        console.log('   ❌ Failed to delete: ' + e.message);
      }
      await new Promise(r => setTimeout(r, 300));
    }
    console.log('');
  }

  // 4) تحقق من المدفوعات اليتيمة المتبقية
  console.log('─'.repeat(80));
  console.log('🔍 Checking remaining orphan payments...');
  const remainingBookings = await listAll('bookings');
  const bookingUuids = new Set(remainingBookings.map(b => b.localUuid));
  const remainingPayments = await listAll('payments');
  const orphans = remainingPayments.filter(p => {
    if (!p.bookingUuidCache) return true;
    return !bookingUuids.has(p.bookingUuidCache);
  });
  console.log('   Remaining orphan payments: ' + orphans.length);

  // حاول إعادة ربط الأيتام المتبقية بمطابقة UUID بدون شرطات
  let relinkedOrphans = 0;
  for (const p of orphans) {
    if (!p.bookingUuidCache) continue;
    const noDash = p.bookingUuidCache.replace(/-/g, '');
    // ابحث عن حجز بـ UUID بدون شرطات يطابق
    for (const b of remainingBookings) {
      if (b.localUuid.replace(/-/g, '') === noDash) {
        try {
          await databases.updateDocument(databaseId, 'payments', p.$id, {
            bookingUuidCache: b.localUuid,
          });
          console.log('   ✅ Relinked orphan ' + p.$id.substring(0, 12) + ' → ' + b.localUuid.substring(0, 12));
          relinkedOrphans++;
        } catch (e) {
          console.log('   ❌ ' + e.message);
        }
        break;
      }
    }
    await new Promise(r => setTimeout(r, 200));
  }

  // الملخص
  console.log('\n═'.repeat(80));
  console.log('  الملخص');
  console.log('═'.repeat(80));
  console.log('  🗑️  Bookings deleted:    ' + bookingsDeleted);
  console.log('  📎 Payments relinked:   ' + paymentsRelinked);
  console.log('  🔧 Orphans relinked:    ' + relinkedOrphans);
  console.log('  ❌ Payments failed:     ' + paymentsFailed);
  console.log('  📦 Bookings remaining:  ' + remainingBookings.length);
  console.log('  📦 Payments remaining:  ' + remainingPayments.length);
  console.log('  🔍 Remaining orphans:   ' + (orphans.length - relinkedOrphans));
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
