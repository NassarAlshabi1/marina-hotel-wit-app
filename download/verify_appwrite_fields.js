/**
 * ============================================
 * ✅ سكربت التحقق من حالة الحقول في Appwrite
 * ============================================
 */

const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

const COLLECTIONS = [
    'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
    'booking_notes', 'booking_nights', 'cash_transactions',
    'salary_cycles', 'salary_payments', 'shift_notes', 
    'hotel_day_ledger', 'devices', 'sync_logs'
];

const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

async function main() {
    console.log('\n╔══════════════════════════════════════════════════════════════════════════════╗');
    console.log('║  📋 تقرير حالة الحقول في Appwrite Cloud                                      ║');
    console.log('╚══════════════════════════════════════════════════════════════════════════════╝\n');
    
    const report = {
        generatedAt: new Date().toISOString(),
        database: DATABASE_ID,
        project: PROJECT_ID,
        collections: []
    };
    
    for (const collectionId of COLLECTIONS) {
        try {
            const attrs = await databases.listAttributes(DATABASE_ID, collectionId);
            const available = attrs.attributes.filter(a => !a.status || a.status === 'available');
            const processing = attrs.attributes.filter(a => a.status === 'processing');
            
            // فصل الحقول حسب النوع
            const syncFields = available.filter(a => 
                ['localUuid', 'serverId', 'createdAt', 'updatedAt', 'deletedAt', 
                 'lastModified', 'vectorClock', 'version', 'origin'].includes(a.key)
            );
            
            const businessFields = available.filter(a => 
                !['localUuid', 'serverId', 'createdAt', 'updatedAt', 'deletedAt', 
                  'lastModified', 'vectorClock', 'version', 'origin', 'lastModifiedEpoch',
                  'createdAtIso', 'updatedAtIso', 'deletedAtIso', 'createdAtEpoch',
                  'idempotencyKey'].includes(a.key)
            );
            
            // التحقق من snake_case
            const snakeCaseFields = available.filter(a => a.key.includes('_') && a.key === a.key.toLowerCase());
            
            const collectionReport = {
                id: collectionId,
                totalFields: available.length,
                processingCount: processing.length,
                syncFieldsCount: syncFields.length,
                businessFieldsCount: businessFields.length,
                snakeCaseCount: snakeCaseFields.length,
                syncFields: syncFields.map(f => f.key).sort(),
                businessFields: businessFields.map(f => f.key).sort(),
                snakeCaseFields: snakeCaseFields.map(f => f.key),
                processingFields: processing.map(f => ({ key: f.key, status: f.status }))
            };
            
            report.collections.push(collectionReport);
            
            // عرض في الكونسول
            const statusIcon = snakeCaseFields.length === 0 ? '✅' : '⚠️';
            const procIcon = processing.length > 0 ? '⏳' : '  ';
            
            console.log(`${statusIcon}${procIcon} ${collectionId.padEnd(22)}`);
            console.log(`     الحقول: ${available.length} | Sync: ${syncFields.length} | Business: ${businessFields.length} | snake_case: ${snakeCaseFields.length}`);
            
            if (processing.length > 0) {
                console.log(`     ⏳ قيد المعالجة: ${processing.map(f => f.key).join(', ')}`);
            }
            
            if (snakeCaseFields.length > 0) {
                console.log(`     ⚠️  حقول snake_case: ${snakeCaseFields.map(f => f.key).join(', ')}`);
            }
            
            console.log('');
            
        } catch (error) {
            console.log(`❌ ${collectionId.padEnd(22)} - خطأ: ${error.message}\n`);
            report.collections.push({
                id: collectionId,
                error: error.message
            });
        }
    }
    
    // ملخص
    console.log('='.repeat(80));
    console.log('📊 الملخص النهائي:');
    console.log('='.repeat(80));
    
    const totalFields = report.collections.reduce((sum, c) => sum + (c.totalFields || 0), 0);
    const totalSnakeCase = report.collections.reduce((sum, c) => sum + (c.snakeCaseCount || 0), 0);
    const totalProcessing = report.collections.reduce((sum, c) => sum + (c.processingCount || 0), 0);
    const successCollections = report.collections.filter(c => !c.error).length;
    
    console.log(`   ✅ Collections ناجحة: ${successCollections}/${COLLECTIONS.length}`);
    console.log(`   📦 إجمالي الحقول: ${totalFields}`);
    console.log(`   🐍 حقول snake_case: ${totalSnakeCase}`);
    console.log(`   ⏳ حقول قيد المعالجة: ${totalProcessing}`);
    
    if (totalSnakeCase === 0) {
        console.log('\n   🎉 ممتاز! جميع الحقول بصيغة camelCase');
    } else {
        console.log('\n   ⚠️  يوجد حقول snake_case تحتاج تحويل');
    }
    
    // حفظ التقرير
    const fs = require('fs');
    const reportPath = '/home/z/my-project/download/appwrite_fields_report.json';
    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));
    console.log(`\n   📄 التقرير محفوظ في: ${reportPath}`);
    
    console.log('\n' + '='.repeat(80) + '\n');
}

main().catch(console.error);
