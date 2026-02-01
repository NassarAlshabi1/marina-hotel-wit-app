#!/usr/bin/env node

const { Client, Databases, Permission, Role } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);
const DATABASE_ID = 'hotel_db';

// Collections that need public write access
const COLLECTIONS = [
    'rooms',
    'bookings',
    'payments',
    'expenses',
    'employees',
    'debts',
    'cash_transactions',
    'shift_notes',
    'booking_notes',
    'booking_nights',
    'salary_cycles',
    'salary_payments',
    'hotel_day_ledger',
    'sync_logs',
    'devices',
    'outbox',
    'sync_state'
];

// Public permissions for testing (allow any user to read/write)
const publicPermissions = [
    Permission.read(Role.any()),
    Permission.create(Role.any()),
    Permission.update(Role.any()),
    Permission.delete(Role.any()),
];

async function updateCollectionPermissions() {
    try {
        console.log('🔧 تحديث صلاحيات Collections للسماح بالوصول العام...\n');
        console.log('⚠️  ملاحظة: هذا للاختبار فقط. في الإنتاج استخدم Auth!\n');
        
        for (const collectionId of COLLECTIONS) {
            try {
                console.log(`📁 ${collectionId}...`);
                
                await databases.updateCollection(
                    DATABASE_ID,
                    collectionId,
                    collectionId,
                    publicPermissions,
                    false, // documentSecurity = false (collection-level permissions)
                    true   // enabled
                );
                
                console.log(`   ✅ تم تحديث الصلاحيات\n`);
                
            } catch (e) {
                if (e.code === 404) {
                    console.log(`   ⚠️  Collection not found (skipped)\n`);
                } else {
                    console.error(`   ❌ Error: ${e.message}\n`);
                }
            }
        }
        
        console.log('=' .repeat(60));
        console.log('✅ تم تحديث الصلاحيات بنجاح!');
        console.log('\n💡 الآن التطبيق المحمول يستطيع:');
        console.log('   ✅ قراءة البيانات');
        console.log('   ✅ إنشاء مستندات جديدة');
        console.log('   ✅ تحديث المستندات');
        console.log('   ✅ حذف المستندات');
        console.log('\n⚠️  تحذير أمني:');
        console.log('   هذه الصلاحيات مفتوحة للجميع (للاختبار فقط)');
        console.log('   في الإنتاج، استخدم Appwrite Auth وصلاحيات محددة');
        console.log('=' .repeat(60) + '\n');
        
    } catch (error) {
        console.error('\n💥 خطأ فادح:', error.message);
        process.exit(1);
    }
}

updateCollectionPermissions();
