// البحث الدقيق عن المستند
const { Client, Databases, Query } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey(process.env.APPWRITE_API_KEY || '');

const databases = new Databases(client);

const DATABASE_ID = 'hotel_db';

async function findExactDocument() {
    const docId = 'real-808-1774143380867';
    
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`🔍 البحث الدقيق عن: ${docId}`);
    console.log('═══════════════════════════════════════════════════════════\n');

    // 1. محاولة جلب المستند مباشرة
    console.log('1️⃣ محاولة جلب المستند مباشرة من salary_cycles:');
    try {
        const doc = await databases.getDocument(DATABASE_ID, 'salary_cycles', docId);
        console.log(`   ✅ موجود!`);
        console.log(`   البيانات: ${JSON.stringify(doc, null, 2)}`);
    } catch (e) {
        console.log(`   ❌ غير موجود: ${e.message}`);
    }

    // 2. البحث بـ localUuid
    console.log('\n2️⃣ البحث بـ localUuid في salary_cycles:');
    try {
        const result = await databases.listDocuments(
            DATABASE_ID,
            'salary_cycles',
            [Query.equal('localUuid', docId)]
        );
        if (result.documents.length > 0) {
            console.log(`   ✅ وجدت ${result.documents.length} مستند`);
            for (const doc of result.documents) {
                console.log(`   Document ID: ${doc.$id}`);
                console.log(`   localUuid: ${doc.localUuid}`);
            }
        } else {
            console.log('   ❌ لم يتم العثور على مستندات');
        }
    } catch (e) {
        console.log(`   ❌ خطأ: ${e.message}`);
    }

    // 3. البحث في جميع المجموعات
    console.log('\n3️⃣ البحث في جميع المجموعات:');
    const collections = ['rooms', 'bookings', 'employees', 'expenses', 'payments', 
                         'debts', 'booking_notes', 'booking_nights', 'cash_transactions',
                         'salary_cycles', 'salary_payments', 'salary_withdrawals', 'shift_notes'];
    
    for (const coll of collections) {
        try {
            const doc = await databases.getDocument(DATABASE_ID, coll, docId);
            console.log(`   ✅ موجود في ${coll}!`);
        } catch (e) {
            // غير موجود
        }
    }

    // 4. فحص ما إذا كان هناك مشكلة في تنسيق ID
    console.log('\n4️⃣ فحص تنسيق ID:');
    const validIdPattern = /^[a-zA-Z_][a-zA-Z0-9_\-]{0,35}$/;
    console.log(`   ID: "${docId}"`);
    console.log(`   صالح لـ Appwrite: ${validIdPattern.test(docId)}`);
    console.log(`   الطول: ${docId.length} (الحد الأقصى: 36)`);
}

findExactDocument();
