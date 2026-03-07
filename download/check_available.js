const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);

async function main() {
    for (const coll of ['bookings', 'payments', 'debts']) {
        console.log(`\n📦 ${coll.toUpperCase()} - Available Sync Fields:`);
        const attrs = await databases.listAttributes('hotel_db', coll);
        
        const syncFields = ['localUuid', 'createdAt', 'updatedAt', 'deletedAt', 'lastModified', 
                           'version', 'origin', 'vectorClock',
                           'created_at', 'updated_at', 'deleted_at', 'last_modified',
                           'local_uuid'];
        
        attrs.attributes
            .filter(a => syncFields.includes(a.key))
            .forEach(a => console.log(`   ✅ ${a.key}`));
        
        // Show what's missing
        const found = attrs.attributes.map(a => a.key);
        const missing = ['localUuid', 'createdAt', 'updatedAt', 'deletedAt', 'lastModified', 
                        'version', 'origin', 'vectorClock']
            .filter(f => !found.includes(f) && !found.includes(f.toLowerCase()));
        
        if (missing.length > 0) {
            console.log(`\n   ❌ Missing: ${missing.join(', ')}`);
        }
    }
}

main().catch(console.error);
