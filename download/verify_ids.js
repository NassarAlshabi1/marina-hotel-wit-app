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
    console.log('🔍 Checking Collection IDs (used by the app)...\n');
    
    const result = await databases.listCollections(DATABASE_ID);
    
    // Create map of $id => name
    const collectionsMap = {};
    result.collections.forEach(c => {
        collectionsMap[c.$id] = c.name;
    });
    
    // Required collection IDs from appwrite_config.dart
    const requiredIds = [
        'rooms', 'bookings', 'payments', 'expenses', 'employees', 'debts',
        'devices', 'sync_logs', 'booking_notes', 'booking_nights',
        'cash_transactions', 'hotel_day_ledger', 'price_adjustments',
        'booking_price_adjustments', 'salary_cycles', 'salary_payments',
        'salary_withdrawals', 'shift_notes', 'audit_logs', 'payment_voids'
    ];
    
    console.log('Collection ID'.padEnd(35) + 'Name'.padEnd(25) + 'Status');
    console.log('='.repeat(70));
    
    for (const id of requiredIds) {
        const exists = collectionsMap[id];
        const status = exists ? '✅ EXISTS' : '❌ MISSING';
        const name = exists || '-';
        console.log(`${id.padEnd(35)}${name.padEnd(25)}${status}`);
    }
    
    console.log('\n📋 All Collections in Database:');
    result.collections.forEach(c => {
        console.log(`   [$id: ${c.$id}] => ${c.name}`);
    });
}

main().catch(console.error);
