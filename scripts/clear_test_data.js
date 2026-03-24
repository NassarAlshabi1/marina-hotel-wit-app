// مسح البيانات التجريبية من Appwrite (ماعدا employees, rooms, expenses)
const { Client, Databases, Query } = require('node-appwrite');

const API_KEY = process.env.APPWRITE_API_KEY || process.argv[2] || '';

if (!API_KEY) {
    console.error('❌ خطأ: يجب توفير API Key');
    console.error('الاستخدام: node clear_test_data.js YOUR_API_KEY');
    console.error('أو: APPWRITE_API_KEY=your_key node clear_test_data.js');
    process.exit(1);
}

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey(API_KEY);

const databases = new Databases(client);

const DATABASE_ID = 'hotel_db';

// الجداول التي لن يتم مسحها
const EXCLUDED_COLLECTIONS = ['employees', 'rooms', 'expenses'];

// جميع الجداول
const ALL_COLLECTIONS = [
    'rooms',
    'bookings',
    'employees',
    'expenses',
    'payments',
    'debts',
    'booking_notes',
    'booking_nights',
    'cash_transactions',
    'salary_cycles',
    'salary_payments',
    'salary_withdrawals',
    'shift_notes',
    'sync_logs',
    'devices',
    'booking_price_adjustments',
    'price_adjustments',
    'audit_logs',
    'payment_voids',
];

// الكلمات الدالة على البيانات التجريبية
const TEST_KEYWORDS = ['test', 'Test', 'TEST', 'demo', 'Demo', 'DEMO', 'real-808', 'real_808', 'اختبار'];

async function deleteAllDocuments(collectionId, collectionName) {
    let totalDeleted = 0;
    let hasMore = true;
    const batchSize = 100;

    console.log(`\n🗑️  بدء مسح ${collectionName} (${collectionId})...`);

    while (hasMore) {
        try {
            // جلب دفعة من المستندات
            const result = await databases.listDocuments(
                DATABASE_ID,
                collectionId,
                [Query.limit(batchSize)]
            );

            if (result.documents.length === 0) {
                hasMore = false;
                break;
            }

            // حذف كل مستند
            for (const doc of result.documents) {
                try {
                    await databases.deleteDocument(
                        DATABASE_ID,
                        collectionId,
                        doc.$id
                    );
                    totalDeleted++;
                    process.stdout.write(`\r   ✅ تم حذف ${totalDeleted} مستند...`);
                } catch (deleteError) {
                    console.log(`\n   ⚠️  فشل حذف ${doc.$id}: ${deleteError.message}`);
                }
            }

            // إذا كانت الدفعة أقل من الحجم الأقصى، انتهينا
            if (result.documents.length < batchSize) {
                hasMore = false;
            }

            // تأخير قصير لتجنب rate limiting
            await new Promise(resolve => setTimeout(resolve, 100));

        } catch (e) {
            if (e.code === 404) {
                console.log(`\n   ℹ️  المجموعة غير موجودة`);
            } else {
                console.log(`\n   ❌ خطأ: ${e.message}`);
            }
            hasMore = false;
        }
    }

    if (totalDeleted > 0) {
        console.log(`\n   ✅ إجمالي: ${totalDeleted} مستند محذوف`);
    } else {
        console.log(`\n   ℹ️  لا توجد مستندات للحذف`);
    }

    return totalDeleted;
}

async function clearTestData() {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('🧹 مسح البيانات التجريبية من Appwrite');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`📌 قاعدة البيانات: ${DATABASE_ID}`);
    console.log(`📌 الجداول المحتفظ بها: ${EXCLUDED_COLLECTIONS.join(', ')}`);
    console.log('═══════════════════════════════════════════════════════════');

    // تحديد الجداول التي سيتم مسحها
    const collectionsToClear = ALL_COLLECTIONS.filter(c => !EXCLUDED_COLLECTIONS.includes(c));

    console.log(`\n📋 الجداول التي سيتم مسحها (${collectionsToClear.length}):`);
    collectionsToClear.forEach((c, i) => console.log(`   ${i + 1}. ${c}`));

    console.log('\n⚠️  تحذير: سيتم حذف جميع البيانات من هذه الجداول!');
    console.log('⏳ بدء العملية...\n');

    let grandTotal = 0;
    const results = [];

    for (const collectionId of collectionsToClear) {
        const deleted = await deleteAllDocuments(collectionId, collectionId);
        results.push({ collection: collectionId, deleted });
        grandTotal += deleted;
    }

    // ملخص
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('📊 ملخص العملية');
    console.log('═══════════════════════════════════════════════════════════');

    for (const r of results) {
        const status = r.deleted > 0 ? '✅' : 'ℹ️ ';
        console.log(`   ${status} ${r.collection}: ${r.deleted} مستند`);
    }

    console.log('───────────────────────────────────────────────────────────');
    console.log(`   📊 الإجمالي: ${grandTotal} مستند محذوف`);
    console.log('═══════════════════════════════════════════════════════════');
    console.log('✅ تم الانتهاء!');
}

// تشغيل السكريبت
clearTestData().catch(console.error);
