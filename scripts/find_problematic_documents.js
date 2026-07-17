// البحث عن المستند في جميع المجموعات
const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey(process.env.APPWRITE_API_KEY || '');

const databases = new Databases(client);

const DATABASE_ID = 'hotel_db';

// قائمة جميع المجموعات
const COLLECTIONS = [
    { name: 'rooms', id: 'rooms' },
    { name: 'bookings', id: 'bookings' },
    { name: 'employees', id: 'employees' },
    { name: 'expenses', id: 'expenses' },
    { name: 'payments', id: 'payments' },
    { name: 'debts', id: 'debts' },
    { name: 'booking_notes', id: 'booking_notes' },
    { name: 'booking_nights', id: 'booking_nights' },
    { name: 'cash_transactions', id: 'cash_transactions' },
    { name: 'salary_cycles', id: 'salary_cycles' },
    { name: 'salary_payments', id: 'salary_payments' },
    { name: 'salary_withdrawals', id: 'salary_withdrawals' },
    { name: 'shift_notes', id: 'shift_notes' },
    { name: 'sync_logs', id: 'sync_logs' },
    { name: 'devices', id: 'devices' },
];

// Document IDs من السجلات
const PROBLEMATIC_IDS = [
    'real-808-1774143380867',
    'test-1774146141921-11',
];

async function findDocuments() {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('🔍 البحث عن المستندات المشكلة في جميع المجموعات');
    console.log('═══════════════════════════════════════════════════════════\n');

    for (const docId of PROBLEMATIC_IDS) {
        console.log(`\n🔎 البحث عن: ${docId}`);
        console.log('───────────────────────────────────────────────────────────');
        
        for (const collection of COLLECTIONS) {
            try {
                const doc = await databases.getDocument(
                    DATABASE_ID,
                    collection.id,
                    docId
                );
                console.log(`  ✅ موجود في ${collection.name} (${collection.id})`);
                console.log(`     localUuid: ${doc.localUuid}`);
                console.log(`     البيانات: ${JSON.stringify(doc).substring(0, 200)}...`);
            } catch (e) {
                if (e.code === 404) {
                    // غير موجود - طبيعي
                } else {
                    console.log(`  ⚠️ خطأ في ${collection.name}: ${e.message}`);
                }
            }
        }
    }

    // فحص salary_cycles بالتفصيل
    console.log('\n\n═══════════════════════════════════════════════════════════');
    console.log('📋 فحص جدول salary_cycles');
    console.log('═══════════════════════════════════════════════════════════\n');

    try {
        const result = await databases.listDocuments(
            DATABASE_ID,
            'salary_cycles',
            []
        );

        console.log(`📦 إجمالي المستندات: ${result.total}\n`);

        for (const doc of result.documents) {
            console.log(`📄 ${doc.$id}:`);
            console.log(`   localUuid: ${doc.localUuid}`);
            console.log(`   employeeId: ${doc.employeeId}`);
            console.log(`   cycleKey: ${doc.cycleKey}`);
            console.log(`   startDate: ${doc.startDate}`);
            console.log(`   endDate: ${doc.endDate}`);
            console.log('');
        }
    } catch (e) {
        console.log(`❌ خطأ: ${e.message}`);
    }
}

findDocuments();
