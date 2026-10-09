#!/usr/bin/env node

const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);

async function checkPermissions() {
    try {
        console.log('🔍 فحص صلاحيات Collections...\n');
        
        const collections = await databases.listCollections('hotel_db');
        
        for (const col of collections.collections) {
            console.log(`📁 ${col.name} (${col.$id})`);
            console.log(`   Document Security: ${col.documentSecurity}`);
            console.log(`   Enabled: ${col.enabled}`);
            
            // Get one document to check permissions
            try {
                const docs = await databases.listDocuments('hotel_db', col.$id);
                if (docs.total > 0) {
                    const firstDoc = docs.documents[0];
                    console.log(`   Document Permissions: ${JSON.stringify(firstDoc.$permissions || [])}`);
                }
            } catch (e) {
                console.log(`   Cannot check document permissions: ${e.message}`);
            }
            console.log('');
        }
        
    } catch (error) {
        console.error('❌ Error:', error.message);
    }
}

checkPermissions();
