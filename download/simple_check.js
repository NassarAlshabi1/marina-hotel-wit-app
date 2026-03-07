const { Client, Databases } = require('node-appwrite');

const client = new Client()
    .setEndpoint('https://fra.cloud.appwrite.io/v1')
    .setProject('690ff0da0025518570c1')
    .setKey('standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da');

const databases = new Databases(client);
const DB = 'hotel_db';

async function main() {
    console.log('📋 CURRENT STATE OF ALL COLLECTIONS\n');
    
    const collections = ['rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts', 
                         'booking_notes', 'booking_nights', 'cash_transactions',
                         'salary_cycles', 'salary_payments', 'salary_withdrawals', 
                         'shift_notes', 'hotel_day_ledger'];
    
    for (const coll of collections) {
        const attrs = await databases.listAttributes(DB, coll);
        const available = attrs.attributes.filter(a => !a.status || a.status === 'available');
        const processing = attrs.attributes.filter(a => a.status === 'processing');
        
        const syncFields = ['localUuid', 'createdAt', 'updatedAt', 'deletedAt', 'lastModified', 
                           'version', 'origin', 'vectorClock',
                           'created_at', 'updated_at', 'deleted_at', 'last_modified', 
                           'vector_clock'];
        
        const found = available.filter(a => syncFields.includes(a.key));
        
        console.log(`${coll.padEnd(22)} Available: ${String(available.length).padStart(2)}  Processing: ${String(processing.length).padStart(2)}  SyncFields: ${found.length}/8`);
        
        if (processing.length > 0) {
            console.log(`                        Processing: ${processing.map(a => a.key).join(', ')}`);
        }
    }
}

main().catch(console.error);
