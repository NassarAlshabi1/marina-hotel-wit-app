const { Client, Databases, ID, Query } = require('node-appwrite');

// Configuration
const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';
const DATABASE_ID = 'hotel_db';

// Initialize client
const client = new Client()
    .setEndpoint(ENDPOINT)
    .setProject(PROJECT_ID)
    .setKey(API_KEY);

const databases = new Databases(client);

// Collection configuration for salary_withdrawals
const COLLECTION_ID = 'salary_withdrawals';
const COLLECTION_NAME = 'Salary Withdrawals';

// Attributes to create
const attributes = [
    { key: 'id', type: 'integer', required: true },
    { key: 'expenseId', type: 'integer', required: false },
    { key: 'employeeId', type: 'integer', required: true },
    { key: 'action', type: 'string', size: 255, required: true },
    { key: 'amount', type: 'integer', required: true },
    { key: 'note', type: 'string', size: 1000, required: false },
    { key: 'date', type: 'string', size: 50, required: true },
    // SyncFields
    { key: 'localUuid', type: 'string', size: 255, required: true },
    { key: 'serverId', type: 'integer', required: false },
    { key: 'createdAt', type: 'integer', required: true },
    { key: 'updatedAt', type: 'integer', required: true },
    { key: 'deletedAt', type: 'integer', required: false },
    { key: 'lastModified', type: 'integer', required: true },
    { key: 'version', type: 'integer', required: true },
    { key: 'origin', type: 'string', size: 50, required: true },
    { key: 'vectorClock', type: 'string', size: 2000, required: true },
    // Additional sync fields
    { key: 'createdAtIso', type: 'string', size: 50, required: false },
    { key: 'updatedAtIso', type: 'string', size: 50, required: false },
    { key: 'deletedAtIso', type: 'string', size: 50, required: false },
    { key: 'createdAtEpoch', type: 'integer', required: false },
    { key: 'lastModifiedEpoch', type: 'integer', required: false },
    // Sync timestamp for Appwrite delta sync
    { key: 'syncTimestamp', type: 'integer', required: false },
    { key: 'deviceId', type: 'string', size: 255, required: false },
];

async function main() {
    console.log('🚀 Starting Appwrite Collections Setup...\n');
    
    // Step 1: Test connection
    console.log('📡 Testing connection...');
    try {
        const result = await databases.listCollections(DATABASE_ID);
        console.log('✅ Connected successfully!');
        console.log(`   Found ${result.total} existing collections\n`);
    } catch (error) {
        console.error('❌ Connection failed:', error.message);
        return;
    }

    // Step 2: Check if collection exists
    console.log(`🔍 Checking if collection '${COLLECTION_ID}' exists...`);
    let collectionExists = false;
    try {
        await databases.getCollection(DATABASE_ID, COLLECTION_ID);
        collectionExists = true;
        console.log('   Collection already exists\n');
    } catch (error) {
        if (error.code === 404) {
            console.log('   Collection does not exist, will create it\n');
        } else {
            console.error('   Error checking collection:', error.message);
        }
    }

    // Step 3: Create collection if needed
    if (!collectionExists) {
        console.log(`📦 Creating collection '${COLLECTION_ID}'...`);
        try {
            await databases.createCollection(
                DATABASE_ID,
                COLLECTION_ID,
                COLLECTION_NAME,
                [
                    'read("any")',
                    'write("any")'
                ],
                false  // documentSecurity
            );
            console.log('✅ Collection created successfully!\n');
        } catch (error) {
            console.error('❌ Failed to create collection:', error.message);
            console.error('   Code:', error.code);
            return;
        }
    }

    // Step 4: Get existing attributes
    console.log('📋 Fetching existing attributes...');
    let existingAttributes = [];
    try {
        const attrsResult = await databases.listAttributes(DATABASE_ID, COLLECTION_ID);
        existingAttributes = attrsResult.attributes.map(a => a.key);
        console.log(`   Found ${existingAttributes.length} existing attributes\n`);
    } catch (error) {
        console.error('   Error fetching attributes:', error.message);
    }

    // Step 5: Create missing attributes
    console.log('🔧 Creating missing attributes...');
    let createdCount = 0;
    let skippedCount = 0;
    let errorCount = 0;

    for (const attr of attributes) {
        if (existingAttributes.includes(attr.key)) {
            console.log(`   ⏭️  ${attr.key} - already exists, skipping`);
            skippedCount++;
            continue;
        }

        try {
            if (attr.type === 'string') {
                await databases.createStringAttribute(
                    DATABASE_ID,
                    COLLECTION_ID,
                    attr.key,
                    attr.size || 255,
                    attr.required
                );
            } else if (attr.type === 'integer') {
                await databases.createIntegerAttribute(
                    DATABASE_ID,
                    COLLECTION_ID,
                    attr.key,
                    attr.required
                );
            } else if (attr.type === 'boolean') {
                await databases.createBooleanAttribute(
                    DATABASE_ID,
                    COLLECTION_ID,
                    attr.key,
                    attr.required
                );
            }
            console.log(`   ✅ ${attr.key} - created`);
            createdCount++;
            // Small delay to avoid rate limiting
            await new Promise(resolve => setTimeout(resolve, 300));
        } catch (error) {
            if (error.code === 409 || error.message?.includes('already exists')) {
                console.log(`   ⏭️  ${attr.key} - already exists`);
                skippedCount++;
            } else {
                console.error(`   ❌ ${attr.key} - failed:`, error.message);
                errorCount++;
            }
        }
    }

    console.log('\n' + '='.repeat(50));
    console.log('📊 Summary:');
    console.log(`   Collection: ${COLLECTION_ID}`);
    console.log(`   Attributes created: ${createdCount}`);
    console.log(`   Attributes skipped: ${skippedCount}`);
    console.log(`   Errors: ${errorCount}`);
    console.log('='.repeat(50) + '\n');

    // Step 6: List final attributes
    console.log('📋 Final attribute list:');
    try {
        const finalAttrs = await databases.listAttributes(DATABASE_ID, COLLECTION_ID);
        finalAttrs.attributes.forEach(a => {
            const status = a.status || 'available';
            const req = a.required ? '✓ required' : 'optional';
            console.log(`   - ${a.key} (${a.type}) ${req} [${status}]`);
        });
    } catch (error) {
        console.error('   Could not fetch final attributes:', error.message);
    }

    console.log('\n✨ Setup complete!');
}

main().catch(console.error);
