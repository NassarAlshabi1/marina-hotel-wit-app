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
    console.log('📦 BOOKINGS - Complete Attribute List:\n');
    const attrs = await databases.listAttributes(DATABASE_ID, 'bookings');
    
    console.log(`Total: ${attrs.total}\n`);
    
    // Sort by key
    const sorted = attrs.attributes.sort((a, b) => a.key.localeCompare(b.key));
    
    sorted.forEach((a, i) => {
        const status = a.status || 'available';
        const req = a.required ? '✓' : ' ';
        console.log(`${String(i+1).padStart(2)}. ${a.key.padEnd(25)} (${a.type.padEnd(7)}) ${status.padEnd(10)} [${req}]`);
    });
    
    // Check what's missing
    const needed = ['localUuid', 'createdAt', 'updatedAt', 'deletedAt', 'lastModified', 'version', 'origin', 'vectorClock'];
    const existing = sorted.map(a => a.key);
    const missing = needed.filter(f => !existing.includes(f));
    
    console.log('\n' + '='.repeat(60));
    console.log('Missing SyncFields:', missing.length > 0 ? missing.join(', ') : 'None');
}

main().catch(console.error);
