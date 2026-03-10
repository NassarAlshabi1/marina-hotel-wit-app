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

// Missing attributes to add for each collection
const fixes = {
    'bookings': {
        required: [
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'version', type: 'integer', required: true },
            { key: 'origin', type: 'string', size: 50, required: true },
            { key: 'vectorClock', type: 'string', size: 2000, required: true },
        ],
        optional: [
            { key: 'discount', type: 'integer', required: false },
            { key: 'discountType', type: 'string', size: 50, required: false },
            { key: 'discountStartDate', type: 'string', size: 50, required: false },
            { key: 'expectedNights', type: 'integer', required: false },
            { key: 'calculatedNights', type: 'integer', required: false },
            { key: 'totalNightsCached', type: 'integer', required: false },
            { key: 'stayDurationIso', type: 'string', size: 100, required: false },
            { key: 'financialHash', type: 'string', size: 255, required: false },
            { key: 'financialFrozenAt', type: 'string', size: 50, required: false },
            { key: 'lastNightEpoch', type: 'integer', required: false },
            { key: 'isOverdue', type: 'boolean', required: false },
            { key: 'needsCheckoutReview', type: 'boolean', required: false },
            { key: 'totalDueCached', type: 'integer', required: false },
            { key: 'totalPaidCached', type: 'integer', required: false },
            { key: 'remainingBalanceCached', type: 'integer', required: false },
            { key: 'isFullyPaid', type: 'boolean', required: false },
            { key: 'hotelDayCheckin', type: 'string', size: 50, required: false },
            { key: 'hotelDayCheckout', type: 'string', size: 50, required: false },
            { key: 'createdAtIso', type: 'string', size: 50, required: false },
            { key: 'updatedAtIso', type: 'string', size: 50, required: false },
            { key: 'deletedAtIso', type: 'string', size: 50, required: false },
            { key: 'createdAtEpoch', type: 'integer', required: false },
            { key: 'lastModifiedEpoch', type: 'integer', required: false },
        ]
    },
    'payments': {
        required: [
            { key: 'version', type: 'integer', required: true },
            { key: 'vectorClock', type: 'string', size: 2000, required: true },
        ],
        optional: [
            { key: 'deletedAtIso', type: 'string', size: 50, required: false },
            { key: 'createdAtEpoch', type: 'integer', required: false },
            { key: 'lastModifiedEpoch', type: 'integer', required: false },
        ]
    },
    'debts': {
        required: [
            { key: 'version', type: 'integer', required: true },
            { key: 'origin', type: 'string', size: 50, required: true },
            { key: 'vectorClock', type: 'string', size: 2000, required: true },
        ],
        optional: [
            { key: 'createdAtIso', type: 'string', size: 50, required: false },
            { key: 'updatedAtIso', type: 'string', size: 50, required: false },
            { key: 'deletedAtIso', type: 'string', size: 50, required: false },
            { key: 'createdAtEpoch', type: 'integer', required: false },
            { key: 'lastModifiedEpoch', type: 'integer', required: false },
        ]
    }
};

async function addAttribute(collectionId, attr) {
    try {
        if (attr.type === 'string') {
            await databases.createStringAttribute(
                DATABASE_ID,
                collectionId,
                attr.key,
                attr.size || 255,
                attr.required
            );
        } else if (attr.type === 'integer') {
            await databases.createIntegerAttribute(
                DATABASE_ID,
                collectionId,
                attr.key,
                attr.required
            );
        } else if (attr.type === 'boolean') {
            await databases.createBooleanAttribute(
                DATABASE_ID,
                collectionId,
                attr.key,
                attr.required
            );
        }
        return { success: true, key: attr.key };
    } catch (error) {
        if (error.code === 409 || error.message?.includes('already exists')) {
            return { success: true, key: attr.key, skipped: true };
        }
        return { success: false, key: attr.key, error: error.message };
    }
}

async function main() {
    console.log('🔧 Fixing Missing Attributes...\n');
    console.log('='.repeat(60));
    
    for (const [collectionId, attrs] of Object.entries(fixes)) {
        console.log(`\n📦 Processing: ${collectionId}`);
        
        // Get existing attributes
        const existing = await databases.listAttributes(DATABASE_ID, collectionId);
        const existingKeys = existing.attributes.map(a => a.key);
        
        const allAttrs = [...attrs.required, ...attrs.optional];
        let created = 0, skipped = 0, failed = 0;
        
        for (const attr of allAttrs) {
            if (existingKeys.includes(attr.key)) {
                console.log(`   ⏭️  ${attr.key} - already exists`);
                skipped++;
                continue;
            }
            
            const result = await addAttribute(collectionId, attr);
            if (result.success) {
                if (result.skipped) {
                    console.log(`   ⏭️  ${attr.key} - already exists`);
                    skipped++;
                } else {
                    console.log(`   ✅ ${attr.key} - created`);
                    created++;
                }
            } else {
                console.log(`   ❌ ${attr.key} - failed: ${result.error}`);
                failed++;
            }
            
            // Delay to avoid rate limiting
            await new Promise(r => setTimeout(r, 200));
        }
        
        console.log(`   📊 Created: ${created}, Skipped: ${skipped}, Failed: ${failed}`);
    }
    
    console.log('\n' + '='.repeat(60));
    console.log('✅ Fix complete!\n');
    
    // Verify
    console.log('📋 Verification:');
    for (const collectionId of Object.keys(fixes)) {
        const attrs = await databases.listAttributes(DATABASE_ID, collectionId);
        const processing = attrs.attributes.filter(a => a.status === 'processing').length;
        const available = attrs.attributes.filter(a => a.status === 'available').length;
        console.log(`   ${collectionId}: ${available} available, ${processing} processing`);
    }
}

main().catch(console.error);
