#!/usr/bin/env node
/**
 * إصلاح شامل للفهارس على Appwrite Cloud — بدقة خارقة.
 *
 * المبادئ:
 *   1. لا حذف لأي فهرس unique (idx_local_uuid) — يحمي من التكرار
 *   2. لا حذف لأي فهرس lastModified — ضروري لـ delta sync
 *   3. إضافة فهارس مفقودة فقط (idempotent)
 *   4. استبدال idx_booking_id (bookingLocalId) في booking_nights بـ bookingUuidCache
 *   5. إضافة idx_local_uuid (unique) لـ guest_infos
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node fix_all_indexes.js
 */

const { Client, Databases } = require('node-appwrite');

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

// ═══ تعريف الفهارس المطلوبة لكل collection ═══════════════════════════
// كل فهرس: { key, type, attributes }
// type: 'key' (عادي), 'unique' (فريد), 'fulltext' (نص كامل)
const requiredIndexes = {
  'rooms': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_room_status', type: 'key', attributes: ['roomNumber', 'status'] },
    { key: 'idx_status_hotel_day', type: 'key', attributes: ['status', 'hotelDayCheckin'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'bookings': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_room_status', type: 'key', attributes: ['roomNumber', 'status'] },
    { key: 'idx_status_hotel_day', type: 'key', attributes: ['status', 'hotelDayCheckin'] },
    { key: 'idx_guest_name', type: 'fulltext', attributes: ['guestName'] },
    { key: 'idx_guest_phone', type: 'key', attributes: ['guestPhone'] },
    { key: 'idx_checkin_date', type: 'key', attributes: ['checkinDate'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'booking_notes': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_booking_uuid', type: 'key', attributes: ['bookingUuidCache'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'booking_nights': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    // ✅ إصلاح: استبدال bookingLocalId بـ bookingUuidCache
    { key: 'idx_booking_uuid', type: 'key', attributes: ['bookingUuidCache'] },
    { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'employees': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_name', type: 'key', attributes: ['name'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'expenses': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_hotel_day_type', type: 'key', attributes: ['hotelDayKey', 'expenseType'] },
    { key: 'idx_date', type: 'key', attributes: ['date'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'cash_transactions': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_transaction_type', type: 'key', attributes: ['transactionType'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'payments': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_hotel_day_type', type: 'key', attributes: ['hotelDayKey', 'revenueType'] },
    { key: 'idx_payments_bookingUuid', type: 'key', attributes: ['bookingUuidCache'] },
    { key: 'idx_payments_paymentDate', type: 'key', attributes: ['paymentDate'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'debts': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_guest_name', type: 'key', attributes: ['guestName'] },
    // ✅ جديد: فهرس bookingUuidCache للديون
    { key: 'idx_debts_bookingUuid', type: 'key', attributes: ['bookingUuidCache'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'shift_notes': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_priority', type: 'key', attributes: ['priority'] },
    { key: 'idx_created_at', type: 'key', attributes: ['createdAt'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'price_adjustments': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_target', type: 'key', attributes: ['targetType', 'targetUuid'] },
    { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
    { key: 'idx_effective_date', type: 'key', attributes: ['effectiveDate'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'booking_price_adjustments': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_booking_uuid', type: 'key', attributes: ['bookingLocalUuid', 'isActive'] },
    { key: 'idx_dates', type: 'key', attributes: ['effectiveHotelDay', 'endHotelDay'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'payment_voids': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_original_payment', type: 'unique', attributes: ['originalPaymentUuid'] },
    { key: 'idx_booking', type: 'key', attributes: ['bookingUuid'] },
    { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'guest_infos': [
    // ✅ إصلاح: إضافة idx_local_uuid (كانت مفقودة!)
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_last_modified', type: 'key', attributes: ['lastModified'] },
    { key: 'idx_room_number', type: 'key', attributes: ['roomNumber'] },
    { key: 'idx_id_number', type: 'key', attributes: ['idNumber'] },
    { key: 'idx_guest_name', type: 'key', attributes: ['guestName'] },
  ],
  'salary_cycles': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_employee_id', type: 'key', attributes: ['employeeId'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'salary_payments': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_cycle_id', type: 'key', attributes: ['cycleId'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'salary_withdrawals': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_employee_id', type: 'key', attributes: ['employeeId'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'salary_carry_over_logs': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_employee_id', type: 'key', attributes: ['employeeId'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'blacklist': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_guest_name', type: 'key', attributes: ['guestName'] },
    { key: 'idx_guest_phone', type: 'key', attributes: ['guestPhone'] },
    { key: 'idx_active', type: 'key', attributes: ['isActive'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'audit_logs': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_entity', type: 'key', attributes: ['entityType', 'entityUuid'] },
    { key: 'idx_hotel_day', type: 'key', attributes: ['hotelDayKey'] },
    { key: 'idx_timestamp', type: 'key', attributes: ['timestamp'] },
    { key: 'idx_financial', type: 'key', attributes: ['isFinancial', 'hotelDayKey'] },
    { key: 'idx_operation', type: 'key', attributes: ['operationType', 'entityType'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'devices': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
  'sync_logs': [
    { key: 'idx_local_uuid', type: 'unique', attributes: ['localUuid'] },
    { key: 'idx_collection_status', type: 'key', attributes: ['collection', 'status'] },
    { key: 'idx_lastModified', type: 'key', attributes: ['lastModified'] },
  ],
};

// فهارس قديمة يجب حذفها (آمنة للحذف — ليست unique ولا lastModified)
const indexesToDelete = {
  'booking_nights': ['idx_booking_id'],  // bookingLocalId → استبدال بـ bookingUuidCache
  'booking_notes': ['idx_booking_id'],   // bookingId → استبدال بـ bookingUuidCache
};

async function main() {
  console.log('═'.repeat(70));
  console.log('  إصلاح شامل للفهارس — بدقة خارقة');
  console.log('═'.repeat(70) + '\n');

  let totalCreated = 0;
  let totalDeleted = 0;
  let totalSkipped = 0;
  let totalFailed = 0;

  for (const [coll, indexes] of Object.entries(requiredIndexes)) {
    console.log('─'.repeat(70));
    console.log('📋 ' + coll);

    // 1) اقرأ الفهارس الحالية
    let currentIndexes = [];
    try {
      const result = await databases.listIndexes(databaseId, coll);
      currentIndexes = result.indexes;
    } catch (e) {
      console.log('  ❌ Cannot read indexes: ' + e.message.substring(0, 50));
      continue;
    }

    const currentKeys = new Set(currentIndexes.map(i => i.key));
    console.log('  Current: ' + currentIndexes.length + ' indexes');

    // 2) احذف الفهارس القديمة
    const toDelete = indexesToDelete[coll] || [];
    for (const oldKey of toDelete) {
      if (currentKeys.has(oldKey)) {
        process.stdout.write('  🗑️  Delete ' + oldKey + '... ');
        try {
          await databases.deleteIndex(databaseId, coll, oldKey);
          console.log('✅');
          totalDeleted++;
        } catch (e) {
          console.log('❌ ' + e.message.substring(0, 40));
          totalFailed++;
        }
        await new Promise(r => setTimeout(r, 500));
      }
    }

    // 3) أنشئ الفهارس المفقودة
    for (const idx of indexes) {
      if (currentKeys.has(idx.key)) {
        totalSkipped++;
        continue; // موجود بالفعل
      }

      process.stdout.write('  📝 Create ' + idx.key + ' [' + idx.type + '](' + idx.attributes.join(',') + ')... ');
      try {
        await databases.createIndex(
          databaseId, coll, idx.key, idx.type, idx.attributes
        );
        console.log('✅');
        totalCreated++;
      } catch (e) {
        console.log('❌ ' + e.message.substring(0, 50));
        totalFailed++;
      }
      await new Promise(r => setTimeout(r, 500));
    }
    console.log('');
  }

  console.log('═'.repeat(70));
  console.log('  الملخص');
  console.log('═'.repeat(70));
  console.log('  ✅ Created:  ' + totalCreated);
  console.log('  🗑️  Deleted:  ' + totalDeleted);
  console.log('  ⏭️  Skipped:  ' + totalSkipped + ' (already exist)');
  console.log('  ❌ Failed:   ' + totalFailed);
  console.log('\n✅ Done!');
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
