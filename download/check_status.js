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

const checkFields = ['createdAt', 'updatedAt', 'deletedAt', 'lastModified', 'version', 'origin', 'vectorClock'];

async function main() {
    for (const coll of ['bookings', 'payments', 'debts']) {
        console.log(`\n📦 ${coll.toUpperCase()}:`);
        const attrs = await databases.listAttributes(DATABASE_ID, coll);
        
        for (const field of checkFields) {
            const attr = attrs.attributes.find(a => a.key === field);
            if (attr) {
                const status = attr.status || 'available';
                const required = attr.required ? 'required' : 'optional';
                console.log(`   ✅ ${field.padEnd(20)} status=${status} ${required}`);
            } else {
                console.log(`   ❌ ${field.padEnd(20)} NOT FOUND`);
            }
        }
        
        // Show total counts
        const available = attrs.attributes.filter(a => a.status === 'available' || !a.status).length;
        const processing = attrs.attributes.filter(a => a.status === 'processing').length;
        const failed = attrs.attributes.filter(a => a.status === 'failed').length;
        console.log(`   \n   Total: ${attrs.total}, Available: ${available}, Processing: ${processing}, Failed: ${failed}`);
    }
}

main().catch(console.error);
