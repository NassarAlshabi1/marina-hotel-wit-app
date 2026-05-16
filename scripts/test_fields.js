/**
 * اختبار التحقق من الحقول المطلوبة
 * node scripts/test_fields.js
 */

const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

// المجموعات التي سيتم اختبارها
const collections = [
    'payments',
    'debts',
    'salary_cycles',
    'salary_payments',
    'rooms',
    'booking_notes',
    'shift_notes',
    'bookings',
    'booking_nights',
];

// الحقول المتوقع أن تكون مطلوبة لكل مجموعة (حسب الأخطاء)
const expectedRequiredFields = {
    'payments': ['sync_version', 'sync_vector_clock'],
    'debts': ['vector_clock', 'sync_version', 'sync_origin', 'sync_vector_clock'],
    'salary_cycles': ['startDate', 'endDate'],
    'salary_payments': ['employeeId', 'paymentDate'],
    'rooms': ['basePrice', 'floor'],
    'booking_notes': ['bookingUuid', 'note'],
    'shift_notes': ['shiftDate', 'note'],
};

// الحقول التي يجب ألا ترسل للمجموعات (لأنها غير موجودة)
const forbiddenFields = {
    'bookings': ['sync_version', 'sync_vector_clock'],
    'booking_nights': ['sync_version', 'sync_vector_clock'],
    'salary_payments': ['sync_version', 'sync_vector_clock'], // sync_version غير موجود هنا!
};

async function testCollectionAttributes(collectionId) {
    console.log(`\n📦 فحص المجموعة: ${collectionId}`);
    console.log('─'.repeat(50));
    
    try {
        const result = await databases.listAttributes(DATABASE_ID, collectionId);
        const attributes = result.attributes;
        
        const existing = attributes.filter(a => a.status === 'available').map(a => a.key);
        const required = attributes.filter(a => a.required === true).map(a => a.key);
        const processing = attributes.filter(a => a.status !== 'available').map(a => a.key);
        
        console.log(`  إجمالي الحقول: ${attributes.length}`);
        console.log(`  الحقول المتاحة: ${existing.length}`);
        console.log(`  الحقول المطلوبة: ${required.join(', ') || 'لا يوجد'}`);
        
        if (processing.length > 0) {
            console.log(`  ⚠️ حقول قيد المعالجة: ${processing.join(', ')}`);
        }
        
        // التحقق من الحقول المتوقعة
        const expected = expectedRequiredFields[collectionId] || [];
        const missing = expected.filter(f => !existing.includes(f));
        
        if (missing.length > 0) {
            console.log(`  ❌ حقول مفقودة: ${missing.join(', ')}`);
        } else if (expected.length > 0) {
            console.log(`  ✅ جميع الحقول المطلوبة موجودة`);
        }
        
        // التحقق من الحقول المحظورة
        const forbidden = forbiddenFields[collectionId] || [];
        const present = forbidden.filter(f => existing.includes(f));
        
        if (present.length > 0) {
            console.log(`  ⚠️ تحذير: حقول sync موجودة ولكن قد تسبب مشاكل: ${present.join(', ')}`);
        }
        
        return { existing, required, missing, present };
    } catch (error) {
        console.error(`  ❌ خطأ: ${error.message}`);
        return null;
    }
}

async function main() {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('        اختبار الحقول المطلوبة في Appwrite');
    console.log('═══════════════════════════════════════════════════════════');
    
    const results = {};
    
    for (const collection of collections) {
        results[collection] = await testCollectionAttributes(collection);
        await new Promise(r => setTimeout(r, 500)); // تجنب rate limiting
    }
    
    // ملخص النتائج
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('                        الملخص');
    console.log('═══════════════════════════════════════════════════════════');
    
    let totalIssues = 0;
    
    for (const [collection, result] of Object.entries(results)) {
        if (!result) continue;
        
        const issues = [];
        if (result.missing && result.missing.length > 0) {
            issues.push(`مفقود: ${result.missing.join(', ')}`);
        }
        if (result.present && result.present.length > 0) {
            issues.push(`تحذير sync: ${result.present.join(', ')}`);
        }
        
        if (issues.length > 0) {
            console.log(`❌ ${collection}: ${issues.join(' | ')}`);
            totalIssues++;
        } else {
            console.log(`✅ ${collection}: OK`);
        }
    }
    
    console.log('\n' + '─'.repeat(50));
    if (totalIssues === 0) {
        console.log('✅ جميع المجموعات في حالة جيدة!');
    } else {
        console.log(`⚠️ يوجد ${totalIssues} مجموعة بها مشاكل`);
    }
}

main().catch(console.error);
