#!/usr/bin/env node

const { Client, Databases, ID } = require('node-appwrite');
const fs = require('fs');
const path = require('path');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);
const DATABASE_ID = 'hotel_db';
const BACKUP_FILE = path.join(__dirname, 'marina_full_backup_20260201_220856.json');

// Helper to clean data for Appwrite
function cleanDataForAppwrite(data) {
    const clean = { ...data };
    
    // Remove Appwrite auto-generated fields
    delete clean.$id;
    delete clean.$createdAt;
    delete clean.$updatedAt;
    delete clean.$permissions;
    delete clean.$collectionId;
    delete clean.$databaseId;
    
    // Remove Drift internal fields
    delete clean.id; // Auto-increment ID from SQLite
    
    return clean;
}

// Helper for delay
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function uploadBackup() {
    try {
        console.log('📖 قراءة ملف النسخة الاحتياطية...\n');
        
        const content = fs.readFileSync(BACKUP_FILE, 'utf-8');
        const backup = JSON.parse(content);
        
        console.log('📊 معلومات النسخة الاحتياطية:');
        console.log(`   Version: ${backup.metadata.version}`);
        console.log(`   Timestamp: ${backup.metadata.timestamp}`);
        console.log(`   Source: ${backup.metadata.source}`);
        console.log(`   Device ID: ${backup.metadata.deviceId}`);
        
        const collections = backup.collections;
        
        // Count total items
        let totalItems = 0;
        const summary = [];
        for (const [collectionId, items] of Object.entries(collections)) {
            if (items.length > 0) {
                totalItems += items.length;
                summary.push({ collection: collectionId, count: items.length });
            }
        }
        
        console.log('\n📦 المحتوى:');
        summary.forEach(s => {
            console.log(`   ${s.collection}: ${s.count} items`);
        });
        console.log(`\n📊 إجمالي السجلات: ${totalItems}\n`);
        
        console.log('=' .repeat(60));
        console.log('🚀 بدء عملية الرفع...\n');
        
        let processedItems = 0;
        let successCount = 0;
        let errorCount = 0;
        const errors = [];
        
        // Process each collection
        for (const [collectionId, items] of Object.entries(collections)) {
            if (items.length === 0) continue;
            
            console.log(`\n📁 معالجة ${collectionId} (${items.length} items)...`);
            
            for (const item of items) {
                try {
                    const cleanData = cleanDataForAppwrite(item);
                    
                    // Extract document ID
                    let documentId;
                    if (cleanData.localUuid) {
                        documentId = cleanData.localUuid;
                    } else if (item.$id) {
                        documentId = item.$id;
                    } else {
                        documentId = ID.unique();
                    }
                    
                    // Try to create document
                    try {
                        await databases.createDocument(
                            DATABASE_ID,
                            collectionId,
                            documentId,
                            cleanData
                        );
                        successCount++;
                    } catch (e) {
                        // If exists (409), try to update
                        if (e.code === 409) {
                            await databases.updateDocument(
                                DATABASE_ID,
                                collectionId,
                                documentId,
                                cleanData
                            );
                            successCount++;
                        } else {
                            throw e;
                        }
                    }
                    
                    processedItems++;
                    
                    // Progress indicator
                    if (processedItems % 10 === 0) {
                        process.stdout.write(`\r   تم رفع: ${processedItems}/${totalItems} (${Math.round(processedItems/totalItems*100)}%)`);
                    }
                    
                    // Small delay to avoid rate limits
                    await delay(100);
                    
                } catch (e) {
                    errorCount++;
                    errors.push({
                        collection: collectionId,
                        error: e.message,
                        code: e.code,
                        type: e.type
                    });
                    
                    // If unauthorized, stop immediately
                    if (e.code === 401) {
                        console.error(`\n\n❌ خطأ في الصلاحيات (401 Unauthorized)!`);
                        console.error('   API Key لا يملك صلاحيات الكتابة (documents.write)');
                        console.error('\n💡 الحل:');
                        console.error('   1. اذهب إلى Appwrite Console → API Keys');
                        console.error('   2. أنشئ مفتاحاً جديداً مع Select All scopes');
                        console.error('   3. تأكد من اختيار documents.write');
                        console.error('   4. حدّث المفتاح في السكريبت\n');
                        process.exit(1);
                    }
                }
            }
            
            console.log(`\r   ✅ تم رفع ${items.length} item من ${collectionId}     `);
        }
        
        console.log('\n' + '='.repeat(60));
        console.log('✅ اكتملت عملية الرفع!\n');
        console.log('📊 الملخص:');
        console.log(`   ✅ ناجح: ${successCount}`);
        console.log(`   ❌ فشل: ${errorCount}`);
        console.log(`   📦 الإجمالي: ${totalItems}`);
        
        if (errors.length > 0) {
            console.log(`\n⚠️  الأخطاء (${errors.length}):`);
            errors.slice(0, 5).forEach((err, i) => {
                console.log(`   ${i + 1}. ${err.collection}: ${err.error} (${err.code})`);
            });
            if (errors.length > 5) {
                console.log(`   ... و ${errors.length - 5} أخطاء أخرى`);
            }
        }
        
        console.log('='.repeat(60) + '\n');
        
    } catch (error) {
        console.error('\n💥 خطأ فادح:', error.message);
        if (error.code) console.error(`   Code: ${error.code}`);
        if (error.type) console.error(`   Type: ${error.type}`);
        process.exit(1);
    }
}

uploadBackup();
