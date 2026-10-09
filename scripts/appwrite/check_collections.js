#!/usr/bin/env node

const { Client, Databases } = require('node-appwrite');

// Configuration from appwrite_config.dart
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';

// Try different keys provided - INCLUDING the "standard_" prefix!
const API_KEYS = [
    'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da',
];

async function checkWithKey(apiKey, index) {
    console.log(`\n${'='.repeat(60)}`);
    console.log(`Testing Key ${index + 1}/${API_KEYS.length}`);
    console.log(`Key: ${apiKey.substring(0, 20)}...${apiKey.substring(apiKey.length - 20)}`);
    console.log(`${'='.repeat(60)}`);

    const client = new Client()
        .setEndpoint(ENDPOINT)
        .setProject(PROJECT_ID)
        .setKey(apiKey);

    const databases = new Databases(client);

    try {
        console.log('1️⃣ Testing Database Access...');
        const db = await databases.get(DATABASE_ID);
        console.log(`   ✅ Database found: ${db.name} (${db.$id})`);
        console.log(`   Created: ${db.$createdAt}`);
        
        console.log('\n2️⃣ Listing Collections...');
        const collections = await databases.listCollections(DATABASE_ID);
        console.log(`   ✅ Found ${collections.total} collection(s):\n`);
        
        if (collections.total === 0) {
            console.log('   ℹ️  No collections exist yet. Need to create them.\n');
        } else {
            for (const col of collections.collections) {
                console.log(`   📁 ${col.name} (${col.$id})`);
                console.log(`      - Attributes: ${col.attributes?.length || 0}`);
                console.log(`      - Documents: ${col.documentSecurity ? 'Document-level' : 'Collection-level'} security`);
                
                // Try to count documents
                try {
                    const docs = await databases.listDocuments(DATABASE_ID, col.$id, []);
                    console.log(`      - Total documents: ${docs.total}`);
                } catch (e) {
                    console.log(`      - Documents: Cannot count (${e.type})`);
                }
            }
        }
        
        console.log('\n✅ SUCCESS: API Key is valid and has proper permissions!\n');
        return true;
        
    } catch (error) {
        console.error(`\n❌ FAILED with this key:`);
        console.error(`   Error Code: ${error.code}`);
        console.error(`   Error Type: ${error.type}`);
        console.error(`   Message: ${error.message}`);
        
        if (error.code === 401) {
            console.log(`\n💡 This key is INVALID or lacks proper scopes.`);
            console.log(`   Required scopes:`);
            console.log(`   - databases.read, databases.write`);
            console.log(`   - collections.read, collections.write`);
            console.log(`   - attributes.read, attributes.write`);
            console.log(`   - documents.read, documents.write`);
        } else if (error.code === 404) {
            console.log(`\n💡 Resource not found (database or collection doesn't exist)`);
        }
        
        return false;
    }
}

async function main() {
    console.log('\n🔍 Appwrite Connection & Collections Checker');
    console.log(`📍 Endpoint: ${ENDPOINT}`);
    console.log(`📦 Project: ${PROJECT_ID}`);
    console.log(`🗄️  Database: ${DATABASE_ID}`);
    
    let successKey = null;
    
    for (let i = 0; i < API_KEYS.length; i++) {
        const success = await checkWithKey(API_KEYS[i], i);
        if (success) {
            successKey = API_KEYS[i];
            break;
        }
    }
    
    console.log('\n' + '='.repeat(60));
    if (successKey) {
        console.log('✅ Found working API key!');
        console.log('\n📋 Next steps:');
        console.log('   1. Collections are listed above');
        console.log('   2. If no collections exist, run create_all_collections_complete.js');
        console.log('   3. Update mobile app if needed');
    } else {
        console.log('❌ None of the provided keys work!');
        console.log('\n🔧 Please:');
        console.log('   1. Go to Appwrite Console → API Keys');
        console.log('   2. Create a NEW key with ALL scopes selected');
        console.log('   3. Copy the ENTIRE key (usually 200+ characters)');
        console.log('   4. Make sure it\'s for the correct project');
    }
    console.log('='.repeat(60) + '\n');
}

main();
