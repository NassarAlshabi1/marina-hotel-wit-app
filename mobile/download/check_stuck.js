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

async function main() {
    for (const coll of ['bookings', 'payments', 'debts']) {
        console.log(`\n📦 ${coll.toUpperCase()}:`);
        const attrs = await databases.listAttributes(DATABASE_ID, coll);
        
        // Group by status
        const byStatus = {
            available: [],
            processing: [],
            stuck: [],
            other: []
        };
        
        attrs.attributes.forEach(a => {
            const status = a.status || 'available';
            if (status === 'available') byStatus.available.push(a.key);
            else if (status === 'processing') byStatus.processing.push(a.key);
            else if (status === 'stuck') byStatus.stuck.push(a.key);
            else byStatus.other.push(`${a.key}(${status})`);
        });
        
        console.log(`   Available: ${byStatus.available.length}`);
        console.log(`   Processing: ${byStatus.processing.length} - ${byStatus.processing.slice(0, 5).join(', ')}${byStatus.processing.length > 5 ? '...' : ''}`);
        console.log(`   Stuck: ${byStatus.stuck.length} - ${byStatus.stuck.slice(0, 5).join(', ')}`);
        console.log(`   Other: ${byStatus.other.length} - ${byStatus.other.slice(0, 5).join(', ')}`);
        console.log(`   Total: ${attrs.total}`);
        
        // Check for the specific fields we need
        const neededFields = ['createdAt', 'updatedAt', 'deletedAt', 'lastModified', 'version', 'origin', 'vectorClock'];
        console.log(`\n   Checking needed fields:`);
        for (const f of neededFields) {
            const attr = attrs.attributes.find(a => a.key === f);
            if (attr) {
                console.log(`      ${f}: ${attr.status || 'available'}`);
            }
        }
    }
}

main().catch(console.error);
