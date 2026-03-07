const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);
const DB = 'hotel_db';

// Use sync_ prefix to avoid conflicts with deleted fields
const fieldsToAdd = {
    'bookings': [
        { key: 'sync_created_at', type: 'integer', required: true },
        { key: 'sync_updated_at', type: 'integer', required: true },
        { key: 'sync_deleted_at', type: 'integer', required: false },
        { key: 'sync_last_modified', type: 'integer', required: true },
        { key: 'sync_version', type: 'integer', required: true },
        { key: 'sync_origin', type: 'string', size: 50, required: true },
        { key: 'sync_vector_clock', type: 'string', size: 2000, required: true },
    ],
    'payments': [
        { key: 'sync_version', type: 'integer', required: true },
        { key: 'sync_vector_clock', type: 'string', size: 2000, required: true },
    ],
    'debts': [
        { key: 'sync_version', type: 'integer', required: true },
        { key: 'sync_origin', type: 'string', size: 50, required: true },
        { key: 'sync_vector_clock', type: 'string', size: 2000, required: true },
    ]
};

async function main() {
    console.log('🔧 Adding sync_ prefixed fields...\n');
    
    for (const [collectionId, fields] of Object.entries(fieldsToAdd)) {
        console.log(`\n📦 ${collectionId}:`);
        
        const existing = await databases.listAttributes(DB, collectionId);
        const existingKeys = existing.attributes.map(a => a.key);
        
        for (const attr of fields) {
            if (existingKeys.includes(attr.key)) {
                console.log(`   ⏭️  ${attr.key} - exists`);
                continue;
            }
            
            try {
                if (attr.type === 'integer') {
                    await databases.createIntegerAttribute(DB, collectionId, attr.key, attr.required);
                } else {
                    await databases.createStringAttribute(DB, collectionId, attr.key, attr.size, attr.required);
                }
                console.log(`   ✅ ${attr.key} - CREATED`);
                await new Promise(r => setTimeout(r, 800));
            } catch (error) {
                console.log(`   ❌ ${attr.key} - ${error.message}`);
            }
        }
    }
    
    console.log('\n✅ Done!');
}

main().catch(console.error);
