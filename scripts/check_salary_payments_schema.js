// التحقق من schema جدول salary_payments في Appwrite
const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey(process.env.APPWRITE_API_KEY || '');

const databases = new Databases(client);

const DATABASE_ID = 'hotel_db';
const SALARY_PAYMENTS_COLLECTION_ID = 'salary_payments';

async function checkSchema() {
    try {
        console.log('═══════════════════════════════════════════════════════════');
        console.log('📋 التحقق من Schema جدول salary_payments');
        console.log('═══════════════════════════════════════════════════════════\n');

        // جلب بعض المستندات لفحص هيكل البيانات
        const result = await databases.listDocuments(
            DATABASE_ID,
            SALARY_PAYMENTS_COLLECTION_ID,
            []
        );

        console.log(`📦 إجمالي المستندات: ${result.total}\n`);

        if (result.documents.length > 0) {
            console.log('📄 نموذج مستند:');
            const doc = result.documents[0];
            console.log('───────────────────────────────────────────────────────────');
            
            for (const [key, value] of Object.entries(doc)) {
                if (key.startsWith('$')) continue; // تخطي الحقول الخاصة بـ Appwrite
                const type = typeof value;
                const displayValue = type === 'object' ? JSON.stringify(value) : value;
                console.log(`  ${key}: ${displayValue} (${type})`);
            }
            console.log('───────────────────────────────────────────────────────────');
            
            // التحقق من حقل amount بالتحديد
            console.log('\n🔍 فحص حقل amount:');
            for (const doc of result.documents.slice(0, 5)) {
                const amount = doc.amount;
                const amountType = typeof amount;
                const isInteger = Number.isInteger(amount);
                console.log(`  - Document ${doc.$id}: amount = ${amount} (${amountType}, integer: ${isInteger})`);
            }
        } else {
            console.log('⚠️ لا توجد مستندات في المجموعة');
        }

        // محاولة إنشاء مستند تجريبي لمعرفة الحقول المطلوبة
        console.log('\n🧪 اختبار إنشاء مستند تجريبي...');
        const testId = `test-${Date.now()}`;
        try {
            await databases.createDocument(
                DATABASE_ID,
                SALARY_PAYMENTS_COLLECTION_ID,
                testId,
                {
                    localUuid: testId,
                    employeeId: 1,
                    cycleId: 1,
                    amount: 100,  // integer
                    paymentDateIso: new Date().toISOString(),
                    paymentDate: new Date().toISOString(),
                    createdAt: Date.now(),
                    updatedAt: Date.now(),
                    lastModified: Date.now(),
                }
            );
            console.log('✅ نجح إنشاء مستند تجريبي بـ amount = 100 (integer)');
            
            // حذف المستند التجريبي
            await databases.deleteDocument(DATABASE_ID, SALARY_PAYMENTS_COLLECTION_ID, testId);
            console.log('🧹 تم حذف المستند التجريبي');
            
        } catch (createError) {
            console.log('❌ فشل إنشاء مستند تجريبي:');
            console.log(`   Error: ${createError.message}`);
            
            // محاولة بـ double
            if (createError.message.includes('amount')) {
                console.log('\n🧪 محاولة بـ amount كـ double...');
                try {
                    await databases.createDocument(
                        DATABASE_ID,
                        SALARY_PAYMENTS_COLLECTION_ID,
                        testId,
                        {
                            localUuid: testId,
                            employeeId: 1,
                            cycleId: 1,
                            amount: 100.50,  // double
                            paymentDateIso: new Date().toISOString(),
                            paymentDate: new Date().toISOString(),
                            createdAt: Date.now(),
                            updatedAt: Date.now(),
                            lastModified: Date.now(),
                        }
                    );
                    console.log('✅ نجح إنشاء مستند بـ amount = 100.50 (double)');
                    await databases.deleteDocument(DATABASE_ID, SALARY_PAYMENTS_COLLECTION_ID, testId);
                } catch (e2) {
                    console.log(`❌ فشل أيضاً: ${e2.message}`);
                }
            }
        }

    } catch (error) {
        console.error('❌ خطأ:', error.message);
    }
}

checkSchema();
