#!/usr/bin/env node
/**
 * سكربت: البحث عن آخر الحجوزات التي تم تسجيل خروجها
 * لمعرفة الحجز الذي تريد إرجاعه
 */
const { Client, Databases, Query } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

async function main() {
  const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
  const db = new Databases(client);

  console.log('🔍 البحث عن آخر الحجوزات بم حالة "مكتمل" (تم تسجيل الخروج)...\n');

  // جلب آخر 20 حجز مكتمل
  const result = await db.listDocuments(DATABASE_ID, 'bookings', [
    Query.equal('status', 'مكتمل'),
    Query.orderDesc('updatedAt'),
    Query.limit(20),
  ]);

  if (result.documents.length === 0) {
    console.log('لم يتم العثور على حجوزات مكتملة.');
    return;
  }

  console.log(`تم العثور على ${result.documents.length} حجز مكتمل:\n`);
  console.log('─'.repeat(100));

  for (const b of result.documents) {
    const name = b.guestName || 'بدون اسم';
    const room = b.roomNumber || '?';
    const checkin = b.checkinDate || '?';
    const checkout = b.actualCheckout || b.checkoutDate || '?';
    const nights = b.calculatedNights || '?';
    const total = b.totalDueCached || 0;
    const updated = b.updatedAtIso || '';
    const uuid = b.localUuid || '';
    const docId = b.$id || '';

    console.log(`📝 اسم النزيل: ${name}`);
    console.log(`🏠 رقم الغرفة: ${room}`);
    console.log(`📅 تاريخ الدخول: ${checkin}`);
    console.log(`🚪 تاريخ الخروج: ${checkout}`);
    console.log(`🌙 عدد الليالي: ${nights}`);
    console.log(`💰 المبلغ الإجمالي: ${total}`);
    console.log(`🕐 آخر تحديث: ${updated}`);
    console.log(`🆔 Document ID: ${docId}`);
    console.log(`🔗 localUuid: ${uuid}`);
    console.log('─'.repeat(100));
  }
}

main().catch(err => { console.error('❌ خطأ:', err.message); process.exit(1); });
