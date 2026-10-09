#!/usr/bin/env node

const { Client, Databases, ID } = require('node-appwrite');

// Client WITHOUT API key (simulating mobile app)
const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1');
    // NO .setKey() - simulating Guest access like the mobile app

const databases = new Databases(client);

async function testGuestAccess() {
    try {
        console.log('🧪 اختبار الوصول بدون API Key (محاكاة التطبيق المحمول)...\n');
        
        // Test 1: Read
        console.log('1️⃣ اختبار القراءة...');
        const employees = await databases.listDocuments('hotel_db', 'employees');
        console.log(`   ✅ نجحت القراءة: ${employees.total} موظف\n`);
        
        // Test 2: Create
        console.log('2️⃣ اختبار الإنشاء...');
        const testEmployee = {
            localUuid: ID.unique(),
            name: 'موظف تجريبي',
            basicSalary: 5000.0,
            position: 'اختبار',
            status: 'active',
            createdAt: Date.now(),
            updatedAt: Date.now(),
            lastModified: Date.now(),
        };
        
        const created = await databases.createDocument(
            'hotel_db',
            'employees',
            testEmployee.localUuid,
            testEmployee
        );
        console.log(`   ✅ نجح الإنشاء: ${created.name} (${created.$id})\n`);
        
        // Test 3: Update
        console.log('3️⃣ اختبار التحديث...');
        const updated = await databases.updateDocument(
            'hotel_db',
            'employees',
            created.$id,
            { name: 'موظف محدّث' }
        );
        console.log(`   ✅ نجح التحديث: ${updated.name}\n`);
        
        // Test 4: Delete
        console.log('4️⃣ اختبار الحذف...');
        await databases.deleteDocument('hotel_db', 'employees', created.$id);
        console.log(`   ✅ نجح الحذف\n`);
        
        console.log('=' .repeat(60));
        console.log('✅ جميع الاختبارات نجحت!');
        console.log('\n💡 الآن ميزة "رفع نسخة إلى Appwrite" يجب أن تعمل من التطبيق');
        console.log('=' .repeat(60) + '\n');
        
    } catch (error) {
        console.error('\n❌ فشل الاختبار:');
        console.error(`   Code: ${error.code}`);
        console.error(`   Type: ${error.type}`);
        console.error(`   Message: ${error.message}`);
        
        if (error.code === 401) {
            console.log('\n💡 المشكلة: الصلاحيات غير كافية');
            console.log('   الحل: شغّل fix_permissions.js أولاً');
        }
        
        process.exit(1);
    }
}

testGuestAccess();
