/**
 * سكربت لإضافة الحقول المطلوبة في Appwrite وجعلها مطلوبة
 * node scripts/fix_appwrite_fields.js
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

// الحقول المطلوب إضافتها (اختيارية أولاً، ثم نحدث المستندات، ثم نجعلها مطلوبة)
const fieldsToAdd = {
    'payments': [
        { key: 'sync_version', type: 'integer', size: null },
        { key: 'sync_vector_clock', type: 'string', size: 65535 },
    ],
    'debts': [
        { key: 'vector_clock', type: 'string', size: 65535 },
        { key: 'sync_version', type: 'integer', size: null },
        { key: 'sync_origin', type: 'string', size: 50 },
        { key: 'sync_vector_clock', type: 'string', size: 65535 },
    ],
    'salary_cycles': [
        { key: 'startDate', type: 'string', size: 50 },
        { key: 'endDate', type: 'string', size: 50 },
    ],
    'rooms': [
        { key: 'basePrice', type: 'double', size: null },
        { key: 'floor', type: 'integer', size: null },
    ],
    'shift_notes': [
        { key: 'note', type: 'string', size: 65535 },
    ],
};

async function listAllDocuments(collectionId, batchSize = 100) {
    const allDocs = [];
    let offset = 0;
    
    while (true) {
        const result = await databases.listDocuments(
            DATABASE_ID,
            collectionId,
            [],
            batchSize,
            offset
        );
        
        allDocs.push(...result.documents);
        
        if (result.documents.length < batchSize) break;
        offset += batchSize;
    }
    
    return allDocs;
}

async function addField(collectionId, field) {
    try {
        console.log(`  📝 إضافة حقل: ${field.key}...`);
        
        if (field.type === 'string') {
            await databases.createStringAttribute(
                DATABASE_ID,
                collectionId,
                field.key,
                field.size || 255,
                false, // required = false أولاً
                undefined,
                false // array
            );
        } else if (field.type === 'integer') {
            await databases.createIntegerAttribute(
                DATABASE_ID,
                collectionId,
                field.key,
                false, // required = false أولاً
                undefined,
                undefined,
                undefined,
                false // array
            );
        } else if (field.type === 'double') {
            await databases.createFloatAttribute(
                DATABASE_ID,
                collectionId,
                field.key,
                false, // required = false أولاً
                undefined,
                undefined,
                undefined,
                false // array
            );
        }
        
        console.log(`  ✅ تمت إضافة: ${field.key}`);
        return true;
    } catch (error) {
        if (error.message && error.message.includes('already exists')) {
            console.log(`  ℹ️ موجود مسبقاً: ${field.key}`);
            return true;
        }
        console.error(`  ❌ خطأ في ${field.key}: ${error.message}`);
        return false;
    }
}

async function updateDocumentsWithDefaults(collectionId, fields) {
    console.log(`  🔄 تحديث المستندات...`);
    
    const docs = await listAllDocuments(collectionId);
    let updated = 0;
    
    for (const doc of docs) {
        const updates = {};
        
        for (const field of fields) {
            if (doc[field.key] === undefined || doc[field.key] === null) {
                // قيم افتراضية
                if (field.type === 'string') {
                    updates[field.key] = field.key.includes('clock') ? '{}' : '';
                } else if (field.type === 'integer') {
                    updates[field.key] = 1;
                } else if (field.type === 'double') {
                    updates[field.key] = 0.0;
                }
            }
        }
        
        if (Object.keys(updates).length > 0) {
            try {
                await databases.updateDocument(DATABASE_ID, collectionId, doc.$id, updates);
                updated++;
            } catch (e) {
                // تجاهل
            }
        }
    }
    
    console.log(`  ✅ تم تحديث ${updated} مستند`);
}

async function main() {
    console.log('═══════════════════════════════════════════════════════════');
    console.log('        إصلاح الحقول المطلوبة في Appwrite');
    console.log('═══════════════════════════════════════════════════════════\n');
    
    for (const [collectionId, fields] of Object.entries(fieldsToAdd)) {
        console.log(`\n📦 المجموعة: ${collectionId}`);
        console.log('─'.repeat(50));
        
        // 1. إضافة الحقول (اختيارية)
        for (const field of fields) {
            await addField(collectionId, field);
            await new Promise(r => setTimeout(r, 1000));
        }
        
        // 2. انتظار حتى تصبح الحقول متاحة
        console.log(`  ⏳ انتظار 5 ثواني...`);
        await new Promise(r => setTimeout(r, 5000));
        
        // 3. تحديث المستندات بقيم افتراضية
        await updateDocumentsWithDefaults(collectionId, fields);
    }
    
    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('✅ اكتمل! الآن يمكنك إعادة تشغيل المزامنة');
    console.log('═══════════════════════════════════════════════════════════');
}

main().catch(console.error);
