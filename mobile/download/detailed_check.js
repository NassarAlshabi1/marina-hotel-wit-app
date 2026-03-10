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

// Expected field names (camelCase as in Dart code)
const expectedFields = {
    'bookings': ['localUuid', 'createdAt', 'updatedAt', 'deletedAt', 'lastModified', 'version', 'origin', 'vectorClock'],
    'payments': ['localUuid', 'version', 'vectorClock'],
    'debts': ['localUuid', 'version', 'origin', 'vectorClock']
};

async function main() {
    console.log('🔍 Detailed Field Name Check\n');
    
    for (const [collectionId, expected] of Object.entries(expectedFields)) {
        console.log(`\n📦 ${collectionId}:`);
        console.log('='.repeat(50));
        
        const attrs = await databases.listAttributes(DATABASE_ID, collectionId);
        const existingKeys = attrs.attributes.map(a => a.key);
        
        // Check each expected field
        for (const field of expected) {
            const exists = existingKeys.includes(field);
            const snakeCase = field.replace(/([A-Z])/g, '_$1').toLowerCase();
            const existsSnake = existingKeys.includes(snakeCase);
            
            if (exists) {
                console.log(`   ✅ ${field}`);
            } else if (existsSnake) {
                console.log(`   ⚠️  ${field} → found as "${snakeCase}" (snake_case)`);
            } else {
                console.log(`   ❌ ${field} - NOT FOUND`);
            }
        }
        
        // Show all attributes
        console.log(`\n   All attributes (${existingKeys.length}):`);
        console.log(`   ${existingKeys.slice(0, 15).join(', ')}`);
        if (existingKeys.length > 15) {
            console.log(`   ${existingKeys.slice(15).join(', ')}`);
        }
    }
}

main().catch(console.error);
