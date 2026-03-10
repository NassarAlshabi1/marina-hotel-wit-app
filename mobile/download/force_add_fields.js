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

// Fields that are actually missing (from check_status.js)
const fieldsToAdd = {
    'bookings': [
        { key: 'createdAt', type: 'integer', required: true },
        { key: 'updatedAt', type: 'integer', required: true },
        { key: 'deletedAt', type: 'integer', required: false },
        { key: 'lastModified', type: 'integer', required: true },
        { key: 'version', type: 'integer', required: true },
        { key: 'origin', type: 'string', size: 50, required: true },
        { key: 'vectorClock', type: 'string', size: 2000, required: true },
    ],
    'payments': [
        { key: 'version', type: 'integer', required: true },
        { key: 'vectorClock', type: 'string', size: 2000, required: true },
    ],
    'debts': [
        { key: 'version', type: 'integer', required: true },
        { key: 'origin', type: 'string', size: 50, required: true },
        { key: 'vectorClock', type: 'string', size: 2000, required: true },
    ]
};

async function main() {
    console.log('🔧 Force Adding Missing Sync Fields\n');
    console.log('='.repeat(60));
    
    for (const [collectionId, fields] of Object.entries(fieldsToAdd)) {
        console.log(`\n📦 ${collectionId}:`);
        
        // First check existing
        const existing = await databases.listAttributes(DATABASE_ID, collectionId);
        const existingKeys = existing.attributes.filter(a => a.status === 'available').map(a => a.key);
        
        for (const attr of fields) {
            // Check if already exists and available
            if (existingKeys.includes(attr.key)) {
                console.log(`   ⏭️  ${attr.key} - already available`);
                continue;
            }
            
            try {
                console.log(`   🔄 Creating ${attr.key}...`);
                
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
                await new Promise(r => setTimeout(r, 1000)); // Wait for processing
                
            } catch (error) {
                if (error.code === 409) {
                    console.log(`   ⚠️  ${attr.key} - Already exists (possibly stuck in processing)`);
                } else {
                    console.log(`   ❌ ${attr.key} - ERROR: ${error.message} (code: ${error.code})`);
                }
            }
        }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('Done. Check status again with verify script.\n');
}

main().catch(console.error);
