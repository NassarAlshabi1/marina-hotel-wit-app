const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

// Use snake_case names which are commonly used by the adapters
const fieldsToAdd = {
    'bookings': [
        { key: 'created_at', type: 'integer', required: true },
        { key: 'updated_at', type: 'integer', required: true },
        { key: 'deleted_at', type: 'integer', required: false },
        { key: 'last_modified', type: 'integer', required: true },
        { key: 'version', type: 'integer', required: true },
        { key: 'origin', type: 'string', size: 50, required: true },
        { key: 'vector_clock', type: 'string', size: 2000, required: true },
    ],
    'payments': [
        { key: 'version', type: 'integer', required: true },
        { key: 'vector_clock', type: 'string', size: 2000, required: true },
    ],
    'debts': [
        { key: 'version', type: 'integer', required: true },
        { key: 'origin', type: 'string', size: 50, required: true },
        { key: 'vector_clock', type: 'string', size: 2000, required: true },
    ]
};

async function main() {
    console.log('🔧 Adding Sync Fields (snake_case versions)\n');
    console.log('='.repeat(60));
    
    let totalCreated = 0;
    
    for (const [collectionId, fields] of Object.entries(fieldsToAdd)) {
        console.log(`\n📦 ${collectionId}:`);
        
        // Check existing
        const existing = await databases.listAttributes(DATABASE_ID, collectionId);
        const existingKeys = existing.attributes.map(a => a.key);
        
        for (const attr of fields) {
            if (existingKeys.includes(attr.key)) {
                console.log(`   ⏭️  ${attr.key} - already exists`);
                continue;
            }
            
            try {
                if (attr.type === 'integer') {
                    await databases.createIntegerAttribute(
                        DATABASE_ID, collectionId, attr.key, attr.required
                    );
                } else if (attr.type === 'string') {
                    await databases.createStringAttribute(
                        DATABASE_ID, collectionId, attr.key, attr.size, attr.required
                    );
                }
                console.log(`   ✅ ${attr.key} - CREATED`);
                totalCreated++;
                await new Promise(r => setTimeout(r, 500));
            } catch (error) {
                console.log(`   ❌ ${attr.key} - ${error.message}`);
            }
        }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log(`📊 Total created: ${totalCreated}`);
    
    if (totalCreated > 0) {
        console.log('\n⏳ Wait a few seconds for attributes to become available...');
    }
}

main().catch(console.error);
