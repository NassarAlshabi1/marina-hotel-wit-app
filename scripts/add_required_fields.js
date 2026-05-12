/**
 * سكربت لإضافة الحقول المطلوبة في Appwrite
 * تشغيل: node scripts/add_required_fields.js
 * 
 * ملاحظة: Appwrite لا يسمح بـ default value للحقول المطلوبة
 * لذلك سنضيفها كـ optional أولاً ثم تحديث المستندات
 */

const { Client, Databases } = require('node-appwrite');

// إعدادات Appwrite
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

// تهيئة العميل
const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

// الحقول المطلوبة لكل مجموعة (بدون default value للحقول المطلوبة)
const requiredFieldsByCollection = {
    // payments - حقول sync مطلوبة
    'payments': [
        { key: 'sync_version', type: 'integer', required: false, array: false },
        { key: 'sync_vector_clock', type: 'string', required: false, size: 65535, array: false },
    ],
    
    // debts - حقول sync مطلوبة
    'debts': [
        { key: 'vector_clock', type: 'string', required: false, size: 65535, array: false },
        { key: 'sync_version', type: 'integer', required: false, array: false },
        { key: 'sync_origin', type: 'string', required: false, size: 50, array: false },
        { key: 'sync_vector_clock', type: 'string', required: false, size: 65535, array: false },
    ],
    
    // salary_cycles - startDate و endDate مطلوبة
    'salary_cycles': [
        { key: 'startDate', type: 'string', required: false, size: 50, array: false },
        { key: 'endDate', type: 'string', required: false, size: 50, array: false },
    ],
    
    // salary_payments - employeeId و paymentDate مطلوبة
    'salary_payments': [
        { key: 'employeeId', type: 'integer', required: false, array: false },
        { key: 'paymentDate', type: 'string', required: false, size: 100, array: false },
    ],
    
    // rooms - basePrice و floor مطلوبة
    'rooms': [
        { key: 'basePrice', type: 'double', required: false, array: false },
        { key: 'floor', type: 'integer', required: false, array: false },
    ],
    
    // booking_notes - bookingUuid و note مطلوبة
    'booking_notes': [
        { key: 'bookingUuid', type: 'string', required: false, size: 100, array: false },
        { key: 'note', type: 'string', required: false, size: 65535, array: false },
    ],
    
    // shift_notes - shiftDate و note مطلوبة
    'shift_notes': [
        { key: 'shiftDate', type: 'string', required: false, size: 50, array: false },
        { key: 'note', type: 'string', required: false, size: 65535, array: false },
    ],
};

// IDs المجموعات
const collectionIds = {
    'payments': 'payments',
    'debts': 'debts',
    'salary_cycles': 'salary_cycles',
    'salary_payments': 'salary_payments',
    'rooms': 'rooms',
    'booking_notes': 'booking_notes',
    'shift_notes': 'shift_notes',
};

// القيم الافتراضية للتحديث
const defaultValues = {
    'sync_version': 1,
    'sync_vector_clock': '{}',
    'vector_clock': '{}',
    'sync_origin': 'mobile',
    'startDate': '',
    'endDate': '',
    'employeeId': 0,
    'paymentDate': new Date().toISOString(),
    'basePrice': 0.0,
    'floor': 1,
    'bookingUuid': '',
    'note': '',
    'shiftDate': new Date().toISOString().split('T')[0],
};

/**
 * إنشاء حقل في مجموعة
 */
async function createAttribute(collectionId, field) {
    try {
        console.log(`  📝 إضافة حقل: ${field.key} (${field.type})...`);
        
        let result;
        const key = field.key;
        const required = field.required;
        const size = field.size || 255;
        
        switch (field.type) {
            case 'string':
                result = await databases.createStringAttribute(
                    DATABASE_ID,
                    collectionId,
                    key,
                    size,
                    required,
                    undefined, // no default for required fields
                    field.array || false
                );
                break;
                
            case 'integer':
                result = await databases.createIntegerAttribute(
                    DATABASE_ID,
                    collectionId,
                    key,
                    required,
                    undefined, // no default
                    undefined, // no min
                    undefined, // no max
                    field.array || false
                );
                break;
                
            case 'double':
                result = await databases.createFloatAttribute(
                    DATABASE_ID,
                    collectionId,
                    key,
                    required,
                    undefined, // no default
                    undefined, // no min
                    undefined, // no max
                    field.array || false
                );
                break;
                
            case 'boolean':
                result = await databases.createBooleanAttribute(
                    DATABASE_ID,
                    collectionId,
                    key,
                    required,
                    undefined, // no default
                    field.array || false
                );
                break;
                
            default:
                console.log(`  ⚠️ نوع الحقل غير مدعوم: ${field.type}`);
                return null;
        }
        
        console.log(`  ✅ تمت إضافة الحقل: ${key}`);
        return result;
    } catch (error) {
        // إذا كان الحقل موجوداً بالفعل
        if (error.message && (
            error.message.includes('already exists') ||
            error.message.includes('Attribute already exists')
        )) {
            console.log(`  ℹ️ الحقل موجود مسبقاً: ${field.key}`);
            return null;
        }
        console.error(`  ❌ خطأ في إضافة الحقل ${field.key}: ${error.message}`);
        return null;
    }
}

/**
 * الحصول على الحقول الموجودة في مجموعة
 */
async function getExistingAttributes(collectionId) {
    try {
        const result = await databases.listAttributes(DATABASE_ID, collectionId);
        return result.attributes.map(attr => attr.key);
    } catch (error) {
        console.error(`خطأ في جلب الحقول: ${error.message}`);
        return [];
    }
}

/**
 * إضافة الحقول المطلوبة لمجموعة
 */
async function addRequiredFieldsToCollection(collectionName) {
    const collectionId = collectionIds[collectionName];
    if (!collectionId) {
        console.log(`⚠️ لا يوجد collectionId لـ: ${collectionName}`);
        return;
    }
    
    const requiredFields = requiredFieldsByCollection[collectionName];
    if (!requiredFields || requiredFields.length === 0) {
        console.log(`⚠️ لا توجد حقول مطلوبة لـ: ${collectionName}`);
        return;
    }
    
    console.log(`\n📦 معالجة المجموعة: ${collectionName} (${collectionId})`);
    
    // جلب الحقول الموجودة
    const existingFields = await getExistingAttributes(collectionId);
    console.log(`  الحقول الموجودة: ${existingFields.length}`);
    
    // إضافة الحقول المفقودة فقط
    for (const field of requiredFields) {
        if (existingFields.includes(field.key)) {
            console.log(`  ✓ الحقل موجود: ${field.key}`);
        } else {
            await createAttribute(collectionId, field);
            // انتظار قصير بين إنشاء الحقول
            await new Promise(resolve => setTimeout(resolve, 1000));
        }
    }
}

/**
 * تحديث المستندات الموجودة بقيم افتراضية
 */
async function updateExistingDocuments(collectionName) {
    const collectionId = collectionIds[collectionName];
    if (!collectionId) return;
    
    const requiredFields = requiredFieldsByCollection[collectionName];
    if (!requiredFields) return;
    
    console.log(`\n🔄 تحديث المستندات الموجودة في: ${collectionName}`);
    
    try {
        // جلب جميع المستندات
        let offset = 0;
        const limit = 50;
        let totalUpdated = 0;
        let hasMore = true;
        
        while (hasMore) {
            const result = await databases.listDocuments(
                DATABASE_ID, 
                collectionId,
                [],
                limit,
                offset
            );
            
            if (result.documents.length === 0) {
                hasMore = false;
                break;
            }
            
            for (const doc of result.documents) {
                const updates = {};
                let needsUpdate = false;
                
                for (const field of requiredFields) {
                    // التحقق مما إذا كان الحقل فارغاً أو غير موجود
                    if (doc[field.key] === undefined || doc[field.key] === null) {
                        updates[field.key] = defaultValues[field.key];
                        needsUpdate = true;
                    }
                }
                
                if (needsUpdate) {
                    try {
                        await databases.updateDocument(
                            DATABASE_ID, 
                            collectionId, 
                            doc.$id, 
                            updates
                        );
                        totalUpdated++;
                        process.stdout.write(`\r  📝 تم تحديث ${totalUpdated} مستند...`);
                    } catch (e) {
                        // تجاهل أخطاء التحديث الفردية
                    }
                }
            }
            
            offset += limit;
            if (result.documents.length < limit) {
                hasMore = false;
            }
        }
        
        if (totalUpdated > 0) {
            console.log(`\n  ✅ تم تحديث ${totalUpdated} مستند`);
        } else {
            console.log(`\n  ℹ️ جميع المستندات محدثة`);
        }
    } catch (error) {
        console.error(`  ❌ خطأ في تحديث المستندات: ${error.message}`);
    }
}

/**
 * التحقق من حالة الحقول
 */
async function checkAttributesStatus(collectionName) {
    const collectionId = collectionIds[collectionName];
    if (!collectionId) return;
    
    try {
        const result = await databases.listAttributes(DATABASE_ID, collectionId);
        console.log(`\n📋 حالة الحقول في ${collectionName}:`);
        
        for (const attr of result.attributes) {
            const status = attr.status === 'available' ? '✅' : '⏳';
            const required = attr.required ? 'مطلوب' : 'اختياري';
            console.log(`  ${status} ${attr.key} (${attr.type}) - ${required}`);
        }
    } catch (error) {
        console.error(`خطأ في جلب حالة الحقول: ${error.message}`);
    }
}

/**
 * الدالة الرئيسية
 */
async function main() {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('        إضافة الحقول المطلوبة في Appwrite');
    console.log('═══════════════════════════════════════════════════════════');
    console.log(`📡 Endpoint: ${ENDPOINT}`);
    console.log(`📊 Database: ${DATABASE_ID}`);
    console.log('');
    
    const collections = Object.keys(requiredFieldsByCollection);
    
    // المرحلة 1: إضافة الحقول
    console.log('\n🔵 المرحلة 1: إضافة الحقول المطلوبة');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    for (const collection of collections) {
        await addRequiredFieldsToCollection(collection);
    }
    
    // انتظار حتى تصبح الحقول متاحة
    console.log('\n⏳ انتظار 10 ثواني حتى تصبح الحقول متاحة...');
    await new Promise(resolve => setTimeout(resolve, 10000));
    
    // المرحلة 2: تحديث المستندات الموجودة
    console.log('\n🔵 المرحلة 2: تحديث المستندات الموجودة بقيم افتراضية');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    for (const collection of collections) {
        await updateExistingDocuments(collection);
    }
    
    // المرحلة 3: التحقق من حالة الحقول
    console.log('\n🔵 المرحلة 3: التحقق من حالة الحقول');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    
    for (const collection of collections) {
        await checkAttributesStatus(collection);
    }
    
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('                    ✅ اكتمل بنجاح');
    console.log('═══════════════════════════════════════════════════════════');
}

// تشغيل السكربت
main().catch(error => {
    console.error('❌ خطأ:', error);
    process.exit(1);
});
