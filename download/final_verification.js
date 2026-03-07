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

// Required sync fields
const syncFields = ['localUuid', 'createdAt', 'updatedAt', 'deletedAt', 'lastModified', 'version', 'origin', 'vectorClock'];

const collections = [
    'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
    'booking_notes', 'booking_nights', 'cash_transactions',
    'salary_cycles', 'salary_payments', 'salary_withdrawals',
    'shift_notes', 'hotel_day_ledger'
];

async function main() {
    console.log('✅ FINAL VERIFICATION - All Collections\n');
    console.log('='.repeat(80));
    console.log('Collection'.padEnd(25) + 'SyncFields'.padEnd(15) + 'Total Attrs'.padEnd(12) + 'Status');
    console.log('='.repeat(80));
    
    let allOk = true;
    
    for (const coll of collections) {
        try {
            const attrs = await databases.listAttributes(DATABASE_ID, coll);
            const keys = attrs.attributes.map(a => a.key);
            
            // Check sync fields
            const missing = syncFields.filter(f => !keys.includes(f));
            const status = missing.length === 0 ? '✅ READY' : '❌ MISSING';
            const syncStatus = `${8 - missing.length}/8`;
            
            console.log(`${coll.padEnd(25)}${syncStatus.padEnd(15)}${attrs.total.toString().padEnd(12)}${status}`);
            
            if (missing.length > 0) {
                console.log(`   Missing: ${missing.join(', ')}`);
                allOk = false;
            }
        } catch (error) {
            console.log(`${coll.padEnd(25)}ERROR: ${error.message}`);
            allOk = false;
        }
    }
    
    console.log('='.repeat(80));
    
    if (allOk) {
        console.log('\n✅ ALL COLLECTIONS ARE READY FOR SYNC!\n');
        console.log('📌 Next steps:');
        console.log('   1. cd /path/to/mobile');
        console.log('   2. flutter pub run build_runner build --delete-conflicting-outputs');
        console.log('   3. Restart app and test sync');
    } else {
        console.log('\n⚠️  Some collections need attention. See details above.');
    }
}

main().catch(console.error);
