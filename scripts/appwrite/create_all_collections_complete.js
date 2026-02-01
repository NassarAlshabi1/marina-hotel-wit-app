const { Client, Databases, Permission, Role } = require('node-appwrite');

// Load environment variables (fallback to hardcoded for testing if needed)
const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT || '690ff0da0025518570c1'; // Your Project ID
const apiKey = process.env.APPWRITE_API_KEY; // Must be provided as env var
const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';

if (!apiKey) {
    console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
    console.log('Usage: APPWRITE_API_KEY=your_key node create_all_collections_complete.js');
    process.exit(1);
}

const client = new Client()
    .setEndpoint(endpoint)
    .setProject(projectId)
    .setKey(apiKey);

const databases = new Databases(client);

// Default permissions for all collections (public access for demo, restrict in prod)
const defaultPermissions = [
    Permission.read(Role.any()),
    Permission.create(Role.any()),
    Permission.update(Role.any()),
    Permission.delete(Role.any()),
];

// Schema definitions based on local_db.dart
// Using drift types mapped to Appwrite types:
// text() -> string
// integer() -> integer
// real() -> double
// boolean() -> boolean

const collections = [
    {
        id: 'rooms',
        name: 'Rooms',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'roomNumber', type: 'string', size: 20, required: true },
            { key: 'roomType', type: 'string', size: 50, required: true },
            { key: 'status', type: 'string', size: 20, required: true },
            { key: 'cleaningStatus', type: 'string', size: 20, required: true },
            { key: 'requiresMaintenance', type: 'integer', required: false, min: 0, max: 1 },
            { key: 'lastCleaningTime', type: 'string', size: 50, required: false },
            { key: 'features', type: 'string', size: 500, required: false },
            { key: 'basePrice', type: 'double', required: true },
            { key: 'floor', type: 'integer', required: true },
            { key: 'bedsCount', type: 'integer', required: true },
            { key: 'serverId', type: 'integer', required: false }, // Sync field
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
        indexes: [
            { key: 'idx_rooms_uuid', type: 'unique', attributes: ['localUuid'] },
            { key: 'idx_rooms_number', type: 'unique', attributes: ['roomNumber'] },
        ]
    },
    {
        id: 'bookings',
        name: 'Bookings',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'roomNumber', type: 'string', size: 20, required: true },
            { key: 'guestName', type: 'string', size: 100, required: true },
            { key: 'guestPhone', type: 'string', size: 20, required: true },
            { key: 'guestIdType', type: 'string', size: 50, required: true },
            { key: 'guestIdNumber', type: 'string', size: 50, required: true },
            { key: 'guestNationality', type: 'string', size: 50, required: true },
            { key: 'checkinDate', type: 'string', size: 50, required: true },
            { key: 'checkoutDate', type: 'string', size: 50, required: false },
            { key: 'status', type: 'string', size: 20, required: true },
            { key: 'notes', type: 'string', size: 1000, required: false },
            { key: 'expectedNights', type: 'integer', required: true },
            { key: 'calculatedNights', type: 'integer', required: true },
            { key: 'totalDueCached', type: 'double', required: false },
            { key: 'totalPaidCached', type: 'double', required: false },
            { key: 'remainingBalanceCached', type: 'double', required: false },
            { key: 'isFullyPaid', type: 'boolean', required: false },
            { key: 'hotelDayCheckin', type: 'string', size: 20, required: false },
            { key: 'hotelDayCheckout', type: 'string', size: 20, required: false },
            { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
        indexes: [
            { key: 'idx_bookings_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'booking_notes',
        name: 'BookingNotes',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'bookingId', type: 'integer', required: true },
            { key: 'noteText', type: 'string', size: 1000, required: true },
            { key: 'alertType', type: 'string', size: 20, required: true },
            { key: 'isActive', type: 'integer', required: true },
            { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
        indexes: [
            { key: 'idx_bn_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'booking_nights',
        name: 'BookingNights',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'bookingLocalId', type: 'integer', required: true },
            { key: 'hotelDayKey', type: 'string', size: 20, required: true },
            { key: 'nightStart', type: 'string', size: 30, required: true },
            { key: 'nightEnd', type: 'string', size: 30, required: true },
            { key: 'nightlyRate', type: 'double', required: true },
            { key: 'sequence', type: 'integer', required: true },
            { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
        indexes: [
             { key: 'idx_bnight_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'payments',
        name: 'Payments',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'bookingLocalId', type: 'integer', required: false },
            { key: 'roomNumber', type: 'string', size: 20, required: false },
            { key: 'amount', type: 'double', required: true },
            { key: 'paymentDate', type: 'string', size: 50, required: true },
            { key: 'paymentMethod', type: 'string', size: 50, required: true },
            { key: 'revenueType', type: 'string', size: 50, required: true },
            { key: 'notes', type: 'string', size: 500, required: false },
            { key: 'hotelDayKey', type: 'string', size: 20, required: false },
            { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
        indexes: [
            { key: 'idx_payments_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'expenses',
        name: 'Expenses',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'expenseType', type: 'string', size: 50, required: true },
            { key: 'description', type: 'string', size: 500, required: true },
            { key: 'amount', type: 'double', required: true },
            { key: 'date', type: 'string', size: 50, required: true },
            { key: 'hotelDayKey', type: 'string', size: 20, required: false },
            { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
        indexes: [
            { key: 'idx_expenses_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'cash_transactions',
        name: 'CashTransactions',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'transactionType', type: 'string', size: 20, required: true },
            { key: 'amount', type: 'double', required: true },
            { key: 'transactionTime', type: 'string', size: 50, required: true },
            { key: 'description', type: 'string', size: 500, required: false },
            { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
         indexes: [
            { key: 'idx_cash_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'debts',
        name: 'Debts',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'guestName', type: 'string', size: 100, required: true },
            { key: 'totalAmount', type: 'double', required: true },
            { key: 'paidAmount', type: 'double', required: true },
            { key: 'remainingAmount', type: 'double', required: true },
            { key: 'isSettled', type: 'integer', required: true },
            { key: 'debtReason', type: 'string', size: 255, required: false },
            { key: 'checkinDate', type: 'string', size: 50, required: false },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
         indexes: [
            { key: 'idx_debts_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'employees',
        name: 'Employees',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'name', type: 'string', size: 100, required: true },
            { key: 'basicSalary', type: 'double', required: true },
            { key: 'position', type: 'string', size: 50, required: true },
            { key: 'phone', type: 'string', size: 20, required: false },
            { key: 'status', type: 'string', size: 20, required: true },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
         indexes: [
            { key: 'idx_emp_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'salary_cycles',
        name: 'SalaryCycles',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'employeeId', type: 'integer', required: true },
            { key: 'cycleKey', type: 'string', size: 20, required: true },
            { key: 'expectedAmount', type: 'double', required: true },
            { key: 'actualPaid', type: 'double', required: true },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
         indexes: [
            { key: 'idx_sal_cyc_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'salary_payments',
        name: 'SalaryPayments',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
             { key: 'employeeId', type: 'integer', required: true },
            { key: 'amount', type: 'double', required: true },
            { key: 'paymentDate', type: 'string', size: 50, required: true },
            { key: 'notes', type: 'string', size: 255, required: false },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
            { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
        ],
         indexes: [
            { key: 'idx_sal_pay_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'hotel_day_ledger',
        name: 'HotelDayLedger',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'hotelDayKey', type: 'string', size: 20, required: true },
            { key: 'totalIncome', type: 'double', required: true },
            { key: 'totalExpenses', type: 'double', required: true },
            { key: 'pendingBalances', type: 'double', required: true },
            { key: 'status', type: 'string', size: 20, required: true },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
        ],
         indexes: [
            { key: 'idx_ledger_uuid', type: 'unique', attributes: ['localUuid'] },
            { key: 'idx_ledger_key', type: 'unique', attributes: ['hotelDayKey'] },
        ]
    },
    {
         id: 'shift_notes',
         name: 'ShiftNotes',
         attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'title', type: 'string', size: 100, required: true },
            { key: 'content', type: 'string', size: 1000, required: true },
            { key: 'priority', type: 'string', size: 20, required: true },
            { key: 'shiftType', type: 'string', size: 20, required: true },
            { key: 'isRead', type: 'integer', required: true },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
             { key: 'createdAtIso', type: 'string', size: 30, required: false },
            { key: 'updatedAtIso', type: 'string', size: 30, required: false },
         ],
          indexes: [
            { key: 'idx_notes_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    },
    {
        id: 'devices',
        name: 'Devices',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'deviceId', type: 'string', size: 100, required: true },
            { key: 'deviceName', type: 'string', size: 100, required: true },
            { key: 'deviceType', type: 'string', size: 50, required: true },
            { key: 'fcmToken', type: 'string', size: 255, required: false },
            { key: 'lastSeen', type: 'string', size: 50, required: true },
            { key: 'isActive', type: 'boolean', required: true },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
        ],
         indexes: [
            { key: 'idx_devices_uuid', type: 'unique', attributes: ['localUuid'] },
            { key: 'idx_devices_id', type: 'unique', attributes: ['deviceId'] },
        ]
    },
    {
        id: 'sync_logs',
        name: 'SyncLogs',
        attributes: [
            { key: 'localUuid', type: 'string', size: 36, required: true },
            { key: 'deviceId', type: 'string', size: 100, required: true },
            { key: 'status', type: 'string', size: 50, required: true },
            { key: 'startTime', type: 'string', size: 50, required: true },
            { key: 'endTime', type: 'string', size: 50, required: false },
            { key: 'durationMs', type: 'integer', required: false },
            { key: 'changesUploaded', type: 'integer', required: false },
            { key: 'changesDownloaded', type: 'integer', required: false },
            { key: 'errors', type: 'string', size: 5000, required: false },
             { key: 'serverId', type: 'integer', required: false },
            { key: 'createdAt', type: 'integer', required: true },
            { key: 'updatedAt', type: 'integer', required: true },
            { key: 'deletedAt', type: 'integer', required: false },
            { key: 'lastModified', type: 'integer', required: true },
        ],
         indexes: [
            { key: 'idx_logs_uuid', type: 'unique', attributes: ['localUuid'] },
        ]
    }
];

// Helper to delay execution (to avoid rate limits)
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

async function createCollections() {
    console.log('🚀 Starting collection creation...');
    console.log(`Endpoint: ${endpoint}`);
    console.log(`Project: ${projectId}`);
    console.log(`Database: ${databaseId}`);

    try {
        // Ensure Database exists
        try {
            await databases.get(databaseId);
            console.log(`✅ Database ${databaseId} verified`);
        } catch (e) {
            if (e.code === 404) {
                 console.log(`ℹ️ Database ${databaseId} not found. Creating...`);
                 await databases.create(databaseId, 'Hotel DB');
                 console.log(`✅ Database ${databaseId} created`);
            } else {
                throw e;
            }
        }
        
        // Loop through collection definitions
        for (const col of collections) {
            console.log(`\n---------------------------------------`);
            console.log(`📂 Processing ${col.name} (${col.id})...`);
            
            // 1️⃣ Create Collection
            try {
                // Check if exists
                await databases.getCollection(databaseId, col.id);
                console.log(`   🔸 Collection already exists. Checking attributes...`);
            } catch (e) {
                if (e.code === 404) {
                    await databases.createCollection(
                        databaseId, 
                        col.id, 
                        col.name, 
                        defaultPermissions
                    );
                    console.log(`   ✅ Created collection: ${col.name}`);
                } else {
                    console.error(`   ❌ Error checking collection ${col.name}: ${e.message}`);
                    continue;
                }
            }

            // 2️⃣ Create Attributes
            for (const attr of col.attributes) {
                try {
                    // Try to get attribute (Appwrite doesn't have getAttribute, so we catch create error if exists)
                    // Actually, creating duplicate attribute throws 409
                    
                    if (attr.type === 'string') {
                         await databases.createStringAttribute(databaseId, col.id, attr.key, attr.size, attr.required);
                    } else if (attr.type === 'integer') {
                         await databases.createIntegerAttribute(databaseId, col.id, attr.key, attr.required, attr.min, attr.max);
                    } else if (attr.type === 'double') {
                         await databases.createFloatAttribute(databaseId, col.id, attr.key, attr.required, attr.min, attr.max);
                    } else if (attr.type === 'boolean') {
                         await databases.createBooleanAttribute(databaseId, col.id, attr.key, attr.required);
                    }
                    
                    console.log(`      ➕ Created attribute: ${attr.key}`);
                    await delay(200); // Small delay
                    
                } catch (e) {
                    if (e.code === 409) {
                         // Attribute already exists - ignore
                         // console.log(`      🔸 Attribute ${attr.key} exists.`);
                    } else {
                        console.error(`      ❌ Failed to create attribute ${attr.key}: ${e.message}`);
                    }
                }
            }
            
            // 3️⃣ Create Indexes
            if (col.indexes) {
                // Wait for attributes to be ready (attributes need to be available status)
                console.log(`   ⏳ Waiting for attributes to index...`);
                await delay(2000); 

                for (const idx of col.indexes) {
                    try {
                         await databases.createIndex(
                             databaseId, 
                             col.id, 
                             idx.key, 
                             idx.type, 
                             idx.attributes
                         );
                         console.log(`      📇 Created index: ${idx.key}`);
                    } catch (e) {
                        if (e.code === 409) {
                            // Index exists
                        } else {
                             console.error(`      ❌ Failed to create index ${idx.key}: ${e.message}`);
                        }
                    }
                }
            }
            
            console.log(`   ✨ ${col.name} Completed`);
        }
        
        console.log('\n✅ All operations finished successfully!');
        
    } catch (e) {
        console.error('💥 Fatal Error:', e);
    }
}

createCollections();
