#!/usr/bin/env node

const { Client, Databases, Query } = require('node-appwrite');
const readline = require('readline');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);
const DATABASE_ID = 'hotel_db';

// Collections to clear
const COLLECTIONS_TO_CLEAR = [
    { id: 'rooms', name: 'الغرف' },
    { id: 'bookings', name: 'الحجوزات' },
    { id: 'payments', name: 'الدفعات' },
    { id: 'expenses', name: 'المصروفات' },
    { id: 'employees', name: 'الموظفون' },
    { id: 'debts', name: 'الديون' },
    { id: 'cash_transactions', name: 'معاملات النقد' },
    { id: 'shift_notes', name: 'ملاحظات النوبة' },
    { id: 'booking_notes', name: 'ملاحظات الحجوزات' },
    { id: 'booking_nights', name: 'ليالي الحجوزات' },
    { id: 'salary_cycles', name: 'دورات الرواتب' },
    { id: 'salary_payments', name: 'دفعات الرواتب' },
    { id: 'hotel_day_ledger', name: 'سجل الأيام الفندقية' },
    { id: 'sync_logs', name: 'سجل المزامنة' },
    { id: 'outbox', name: 'الصندوق الصادر' },
    { id: 'sync_state', name: 'حالة المزامنة' },
    { id: 'devices', name: 'الأجهزة المسجلة' },
];

async function askForConfirmation(question) {
    const rl = readline.createInterface({
        input: process.stdin,
        output: process.stdout
    });

    return new Promise((resolve) => {
        rl.question(question, (answer) => {
            rl.close();
            resolve(answer.toLowerCase() === 'yes' || answer.toLowerCase() === 'y');
        });
    });
}

async function deleteAllDocuments(collectionId, collectionName) {
    try {
        let totalDeleted = 0;
        let hasMore = true;

        while (hasMore) {
            // Get documents (max 100 at a time due to Appwrite limits)
            const response = await databases.listDocuments(
                DATABASE_ID,
                collectionId,
                [Query.limit(100)]
            );

            if (response.documents.length === 0) {
                hasMore = false;
                break;
            }

            // Delete each document
            for (const doc of response.documents) {
                try {
                    await databases.deleteDocument(DATABASE_ID, collectionId, doc.$id);
                    totalDeleted++;
                    process.stdout.write(`\r   حذف: ${totalDeleted} مستند...`);
                } catch (e) {
                    console.error(`\n   ❌ فشل حذف ${doc.$id}: ${e.message}`);
                }
            }

            // Check if there are more
            hasMore = response.total > totalDeleted;
        }

        console.log(`\r   ✅ تم حذف ${totalDeleted} مستند من ${collectionName}`);
        return totalDeleted;

    } catch (error) {
        console.error(`   ❌ خطأ في ${collectionName}: ${error.message}`);
        return 0;
    }
}

async function clearAllData() {
    console.log('\n⚠️  تحذير: حذف جميع البيانات من Appwrite Cloud\n');
    console.log('هذا الإجراء سيحذف جميع المستندات من جميع المجموعات التالية:');
    COLLECTIONS_TO_CLEAR.forEach((col, i) => {
        console.log(`   ${i + 1}. ${col.name} (${col.id})`);
    });
    console.log('\n⚠️  هذا الإجراء لا يمكن التراجع عنه!\n');

    const confirmed = await askForConfirmation('هل تريد المتابعة؟ اكتب "yes" للتأكيد: ');

    if (!confirmed) {
        console.log('\n❌ تم الإلغاء. لم يتم حذف أي شيء.\n');
        process.exit(0);
    }

    console.log('\n🗑️  بدء عملية الحذف...\n');

    let totalDeleted = 0;

    for (const collection of COLLECTIONS_TO_CLEAR) {
        console.log(`📁 معالجة ${collection.name} (${collection.id})...`);
        const deleted = await deleteAllDocuments(collection.id, collection.name);
        totalDeleted += deleted;
    }

    console.log('\n' + '='.repeat(60));
    console.log(`✅ اكتملت عملية الحذف`);
    console.log(`📊 إجمالي المستندات المحذوفة: ${totalDeleted}`);
    console.log('='.repeat(60) + '\n');
}

clearAllData().catch((error) => {
    console.error('\n💥 خطأ فادح:', error);
    process.exit(1);
});
