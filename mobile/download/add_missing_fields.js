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

// Missing fields to add
const missingFields = {
    'bookings': [
        { key: 'createdAt', type: 'integer', required: true },
        { key: 'updatedAt', type: 'integer', required: true },
        { key: 'deletedAt', type: 'integer', required: false },
        { key: 'lastModified', type: 'integer', required: true },
        { key: 'version', type: 'integer', required: true },
        { key: 'origin', type: 'string', size: 50, required: true },
        { key: 'vectorClock', type: 'string', size: 2000, required: true },
        // Additional optional fields
        { key: 'discount', type: 'integer', required: false },
        { key: 'discountType', type: 'string', size: 50, required: false },
        { key: 'discountStartDate', type: 'string', size: 50, required: false },
        { key: 'expectedNights', type: 'integer', required: false },
        { key: 'calculatedNights', type: 'integer', required: false },
        { key: 'totalNightsCached', type: 'integer', required: false },
        { key: 'financialHash', type: 'string', size: 255, required: false },
        { key: 'financialFrozenAt', type: 'string', size: 50, required: false },
        { key: 'totalDueCached', type: 'integer', required: false },
        { key: 'totalPaidCached', type: 'integer', required: false },
        { key: 'remainingBalanceCached', type: 'integer', required: false },
        { key: 'createdAtIso', type: 'string', size: 50, required: false },
        { key: 'updatedAtIso', type: 'string', size: 50, required: false },
        { key: 'deletedAtIso', type: 'string', size: 50, required: false },
        { key: 'createdAtEpoch', type: 'integer', required: false },
        { key: 'lastModifiedEpoch', type: 'integer', required: false },
    ],
    'payments': [
        { key: 'version', type: 'integer', required: true },
        { key: 'vectorClock', type: 'string', size: 2000, required: true },
        { key: 'deletedAtIso', type: 'string', size: 50, required: false },
        { key: 'createdAtEpoch', type: 'integer', required: false },
        { key: 'lastModifiedEpoch', type: 'integer', required: false },
    ],
    'debts': [
        { key: 'version', type: 'integer', required: true },
        { key: 'origin', type: 'string', size: 50, required: true },
        { key: 'vectorClock', type: 'string', size: 2000, required: true },
        { key: 'createdAtIso', type: 'string', size: 50, required: false },
        { key: 'updatedAtIso', type: 'string', size: 50, required: false },
        { key: 'deletedAtIso', type: 'string', size: 50, required: false },
        { key: 'createdAtEpoch', type: 'integer', required: false },
        { key: 'lastModifiedEpoch', type: 'integer', required: false },
    ]
};

async function addAttribute(collectionId, attr) {
    if (attr.type === 'string') {
        return await databases.createStringAttribute(
            DATABASE_ID, collectionId, attr.key, attr.size || 255, attr.required
        );
    } else if (attr.type === 'integer') {
        return await databases.createIntegerAttribute(
            DATABASE_ID, collectionId, attr.key, attr.required
        );
    } else if (attr.type === 'boolean') {
        return await databases.createBooleanAttribute(
            DATABASE_ID, collectionId, attr.key, attr.required
        );
    }
}

async function main() {
    console.log('🔧 Adding Missing Attributes to Collections\n');
    console.log('='.repeat(60));
    
    let totalCreated = 0;
    let totalSkipped = 0;
    let totalFailed = 0;
    
    for (const [collectionId, fields] of Object.entries(missingFields)) {
        console.log(`\n📦 ${collectionId}:`);
        
        // Get existing attributes
        const existing = await databases.listAttributes(DATABASE_ID, collectionId);
        const existingKeys = existing.attributes.map(a => a.key);
        
        for (const attr of fields) {
            if (existingKeys.includes(attr.key)) {
                console.log(`   ⏭️  ${attr.key} - already exists`);
                totalSkipped++;
                continue;
            }
            
            try {
                await addAttribute(collectionId, attr);
                console.log(`   ✅ ${attr.key} - created`);
                totalCreated++;
                await new Promise(r => setTimeout(r, 300)); // Rate limit
            } catch (error) {
                if (error.code === 409 || error.message?.includes('already exists')) {
                    console.log(`   ⏭️  ${attr.key} - already exists`);
                    totalSkipped++;
                } else {
                    console.log(`   ❌ ${attr.key} - ERROR: ${error.message}`);
                    totalFailed++;
                }
            }
        }
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('📊 Summary:');
    console.log(`   Created: ${totalCreated}`);
    console.log(`   Skipped: ${totalSkipped}`);
    console.log(`   Failed: ${totalFailed}`);
    
    if (totalCreated > 0) {
        console.log('\n⏳ Note: Some attributes may be in "processing" state.');
        console.log('   Please wait a moment before testing sync.');
    }
}

main().catch(console.error);
