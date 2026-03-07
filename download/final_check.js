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

// Check both camelCase and snake_case variants
const syncFieldVariants = [
    ['localUuid', 'local_uuid'],
    ['createdAt', 'created_at'],
    ['updatedAt', 'updated_at'],
    ['deletedAt', 'deleted_at'],
    ['lastModified', 'last_modified'],
    ['version', 'version'],
    ['origin', 'origin'],
    ['vectorClock', 'vector_clock'],
];

async function main() {
    console.log('✅ FINAL VERIFICATION\n');
    console.log('='.repeat(80));
    console.log('Collection'.padEnd(20) + 'SyncFields Status'.padEnd(40) + 'Result');
    console.log('='.repeat(80));
    
    for (const coll of ['bookings', 'payments', 'debts', 'rooms', 'expenses', 'employees']) {
        const attrs = await databases.listAttributes(DATABASE_ID, coll);
        const keys = attrs.attributes.map(a => a.key);
        
        const found = [];
        const missing = [];
        
        for (const [camel, snake] of syncFieldVariants) {
            if (keys.includes(camel)) {
                found.push(camel);
            } else if (keys.includes(snake)) {
                found.push(snake);
            } else {
                missing.push(camel);
            }
        }
        
        const status = `${found.length}/8 fields found`;
        const result = missing.length === 0 ? '✅ READY' : '⚠️ PARTIAL';
        
        console.log(`${coll.padEnd(20)}${status.padEnd(40)}${result}`);
        
        if (missing.length > 0) {
            console.log(`                     Missing: ${missing.join(', ')}`);
        }
    }
    
    console.log('='.repeat(80));
}

main().catch(console.error);
