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

// Required collections from the app
const requiredCollections = [
    'rooms',
    'bookings', 
    'payments',
    'expenses',
    'employees',
    'debts',
    'booking_notes',
    'booking_nights',
    'cash_transactions',
    'salary_cycles',
    'salary_payments',
    'salary_withdrawals',
    'shift_notes',
    'price_adjustments',
    'booking_price_adjustments',
    'audit_logs',
    'payment_voids',
    'hotel_day_ledger'
];

async function main() {
    console.log('🔍 Verifying Appwrite Collections...\n');
    
    // List all collections
    const result = await databases.listCollections(DATABASE_ID);
    const existingCollections = result.collections.map(c => c.name);
    
    console.log(`📦 Found ${result.total} collections in database:\n`);
    
    // Check each required collection
    let allPresent = true;
    for (const coll of requiredCollections) {
        const exists = existingCollections.includes(coll);
        const status = exists ? '✅' : '❌ MISSING';
        console.log(`   ${status} ${coll}`);
        if (!exists) allPresent = false;
    }
    
    console.log('\n' + '='.repeat(50));
    
    // Show extra collections (not in required list)
    const extraCollections = existingCollections.filter(c => !requiredCollections.includes(c));
    if (extraCollections.length > 0) {
        console.log('\n📋 Additional collections (not required by app):');
        extraCollections.forEach(c => console.log(`   - ${c}`));
    }
    
    // Get details for salary_withdrawals
    console.log('\n📊 salary_withdrawals details:');
    try {
        const attrs = await databases.listAttributes(DATABASE_ID, 'salary_withdrawals');
        const available = attrs.attributes.filter(a => a.status === 'available').length;
        const processing = attrs.attributes.filter(a => a.status === 'processing').length;
        console.log(`   Total attributes: ${attrs.total}`);
        console.log(`   Available: ${available}`);
        console.log(`   Processing: ${processing}`);
        
        if (processing > 0) {
            console.log('\n   ⏳ Some attributes are still processing...');
            console.log('   Please wait a moment and run this script again to verify.');
        }
    } catch (e) {
        console.error('   Error:', e.message);
    }
    
    console.log('\n' + '='.repeat(50));
    if (allPresent) {
        console.log('✅ All required collections are present!');
    } else {
        console.log('⚠️  Some collections are missing!');
    }
}

main().catch(console.error);
