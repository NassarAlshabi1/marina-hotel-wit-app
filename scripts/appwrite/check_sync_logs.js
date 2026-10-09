#!/usr/bin/env node

const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);

async function checkSyncLogs() {
    try {
        console.log('🔍 فحص سجلات المزامنة الجديدة...\n');
        
        const logs = await databases.listDocuments('hotel_db', 'sync_logs');
        
        console.log(`📊 إجمالي السجلات: ${logs.total}\n`);
        
        if (logs.total > 0) {
            logs.documents.forEach((log, i) => {
                console.log(`${i + 1}. Sync Log:`);
                console.log(`   Device ID: ${log.deviceId || 'N/A'}`);
                console.log(`   Status: ${log.status || 'N/A'}`);
                console.log(`   Start: ${log.startTime || 'N/A'}`);
                console.log(`   End: ${log.endTime || 'N/A'}`);
                console.log(`   Duration: ${log.durationMs || 0}ms`);
                console.log(`   Uploaded: ${log.changesUploaded || 0}`);
                console.log(`   Downloaded: ${log.changesDownloaded || 0}`);
                if (log.errors) console.log(`   Errors: ${log.errors}`);
                console.log('');
            });
        } else {
            console.log('⚪ لا توجد سجلات مزامنة');
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
}

checkSyncLogs();
