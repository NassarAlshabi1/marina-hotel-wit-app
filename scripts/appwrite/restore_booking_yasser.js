#!/usr/bin/env node
/**
 * سكربت: إرجاع نزيل بعد تسجيل الخروج بالخطأ
 * النزيل: ياسر هبه علي يحيى — غرفة 304
 * 
 * التعديلات:
 *   1. status → 'محجوزة'
 *   2. actualCheckout → null
 *   3. calculatedNights → إعادة حساب من checkinDate
 *   4. lastModified → الآن (لضمان المزامنة)
 *   5. حالة الغرفة 304 → 'محجوزة'
 */
const { Client, Databases, Query } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

const BOOKING_DOC_ID = 'e1669c94-7a61-48b5-92d5-88b5ff18ebc0';
const ROOM_NUMBER = '304';

async function main() {
  const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
  const db = new Databases(client);

  console.log('🔄 إرجاع النزيل: ياسر هبه علي يحيى — غرفة 304');
  console.log('='.repeat(60));

  // ─── 1. جلب بيانات الحجز الحالية ───
  console.log('\n📡 جلب بيانات الحجز...');
  const booking = await db.getDocument(DATABASE_ID, 'bookings', BOOKING_DOC_ID);

  console.log(`  الحالة الحالية: ${booking.status}`);
  console.log(`  تاريخ الدخول: ${booking.checkinDate}`);
  console.log(`  تاريخ الخروج الفعلي: ${booking.actualCheckout}`);
  console.log(`  عدد الليالي المحسوب: ${booking.calculatedNights}`);
  console.log(`  الغرفة: ${booking.roomNumber}`);

  if (booking.status !== 'مكتمل') {
    console.log(`\n⚠️ الحجز ليس بحالة "مكتمل" (حالته: ${booking.status})، لا حاجة للإرجاع.`);
    return;
  }

  // ─── 2. حساب عدد الليالي من تاريخ الدخول فقط ───
  const checkinDate = new Date(booking.checkinDate);
  const now = new Date();
  // حساب تقريبي لعدد الليالي (من تاريخ الدخول إلى الآن)
  const diffMs = now - checkinDate;
  const nights = Math.max(1, Math.ceil(diffMs / (1000 * 60 * 60 * 24)));
  
  console.log(`\n📊 إعادة حساب الليالي:`);
  console.log(`  من ${booking.checkinDate} إلى الآن = ${nights} ليلة`);

  const nowEpoch = Math.floor(Date.now() / 1000);
  const nowIso = new Date().toISOString();

  // ─── 3. تحديث الحجز في Appwrite ───
  console.log('\n⏳ جاري تحديث الحجز...');
  
  const updateData = {
    status: 'محجوزة',
    actualCheckout: null,           // مسح تاريخ الخروج الفعلي
    calculatedNights: nights,       // إعادة حساب الليالي
    needsCheckoutReview: false,
    lastModified: nowEpoch,
    updatedAt: nowEpoch,
    updatedAtIso: nowIso,
    lastModifiedEpoch: nowEpoch,
    version: (booking.version || 1) + 1,
  };

  const updatedBooking = await db.updateDocument(
    DATABASE_ID, 
    'bookings', 
    BOOKING_DOC_ID, 
    updateData
  );

  console.log('  ✅ تم تحديث الحجز:');
  console.log(`     status: مكتمل → محجوزة`);
  console.log(`     actualCheckout: ${booking.actualCheckout} → null`);
  console.log(`     calculatedNights: ${booking.calculatedNights} → ${nights}`);
  console.log(`     lastModified: ${nowEpoch}`);

  // ─── 4. تحديث حالة الغرفة 304 ───
  console.log('\n📡 البحث عن غرفة 304...');
  const roomsResult = await db.listDocuments(DATABASE_ID, 'rooms', [
    Query.equal('roomNumber', ROOM_NUMBER),
    Query.limit(1),
  ]);

  if (roomsResult.documents.length > 0) {
    const room = roomsResult.documents[0];
    console.log(`  حالة الغرفة الحالية: ${room.status}`);

    if (room.status === 'شاغرة' || room.status !== 'محجوزة') {
      console.log('\n⏳ جاري تحديث حالة الغرفة...');
      await db.updateDocument(DATABASE_ID, 'rooms', room.$id, {
        status: 'محجوزة',
        lastModified: nowEpoch,
        updatedAt: nowEpoch,
        updatedAtIso: nowIso,
        lastModifiedEpoch: nowEpoch,
        version: (room.version || 1) + 1,
      });
      console.log('  ✅ تم تحديث حالة الغرفة: شاغرة → محجوزة');
    } else {
      console.log('  ℹ️ الغرفة بالفعل بحالة محجوزة، لا حاجة للتحديث.');
    }
  } else {
    console.log('  ⚠️ لم يتم العثور على غرفة 304!');
  }

  console.log('\n' + '='.repeat(60));
  console.log('✅ تم إرجاع النزيل بنجاح!');
  console.log('');
  console.log('⚠️ ملاحظات مهمة:');
  console.log('  1. افتح التطبيق وقم بالمزامنة (Pull) لتحديث البيانات المحلية');
  console.log('  2. تأكد من أن الغرفة 304 تظهر كمحجوزة');
  console.log('  3. إذا كان هناك outbox معلق بالتطبيق، قد يعيد الخروج — احذفه من سجل المزامنة');
  console.log('='.repeat(60));
}

main().catch(err => { console.error('❌ خطأ:', err.message); process.exit(1); });
