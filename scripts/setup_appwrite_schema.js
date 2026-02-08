const { Client, Databases, Permission, Role, IndexType } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';

const API_KEY = process.env.APPWRITE_API_KEY;

if (!API_KEY) {
  console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
  console.error('Usage: APPWRITE_API_KEY=your_api_key node setup_appwrite_schema.js');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const databases = new Databases(client);

async function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

async function createCollection(collectionId, name, permissions) {
  try {
    const collection = await databases.createCollection(
      DATABASE_ID,
      collectionId,
      name,
      permissions
    );
    console.log(`✅ Created collection: ${name}`);
    return collection;
  } catch (error) {
    if (error.code === 409) {
      console.log(`⏭️  Collection already exists: ${name}`);
      return null;
    }
    throw error;
  }
}

async function createStringAttribute(collectionId, key, size, required = false, defaultValue = null) {
  try {
    await databases.createStringAttribute(
      DATABASE_ID,
      collectionId,
      key,
      size,
      required,
      defaultValue
    );
    console.log(`  ✅ String attribute: ${key}`);
  } catch (error) {
    if (error.code === 409) {
      console.log(`  ⏭️  Attribute exists: ${key}`);
    } else {
      console.error(`  ❌ Failed ${key}: ${error.message}`);
    }
  }
}

async function createIntegerAttribute(collectionId, key, required = false, min = null, max = null, defaultValue = null) {
  try {
    await databases.createIntegerAttribute(
      DATABASE_ID,
      collectionId,
      key,
      required,
      min,
      max,
      defaultValue
    );
    console.log(`  ✅ Integer attribute: ${key}`);
  } catch (error) {
    if (error.code === 409) {
      console.log(`  ⏭️  Attribute exists: ${key}`);
    } else {
      console.error(`  ❌ Failed ${key}: ${error.message}`);
    }
  }
}

async function createFloatAttribute(collectionId, key, required = false, min = null, max = null, defaultValue = null) {
  try {
    await databases.createFloatAttribute(
      DATABASE_ID,
      collectionId,
      key,
      required,
      min,
      max,
      defaultValue
    );
    console.log(`  ✅ Float attribute: ${key}`);
  } catch (error) {
    if (error.code === 409) {
      console.log(`  ⏭️  Attribute exists: ${key}`);
    } else {
      console.error(`  ❌ Failed ${key}: ${error.message}`);
    }
  }
}

async function createBooleanAttribute(collectionId, key, required = false, defaultValue = null) {
  try {
    await databases.createBooleanAttribute(
      DATABASE_ID,
      collectionId,
      key,
      required,
      defaultValue
    );
    console.log(`  ✅ Boolean attribute: ${key}`);
  } catch (error) {
    if (error.code === 409) {
      console.log(`  ⏭️  Attribute exists: ${key}`);
    } else {
      console.error(`  ❌ Failed ${key}: ${error.message}`);
    }
  }
}

async function createIndex(collectionId, key, type, attributes, orders = null) {
  try {
    await databases.createIndex(
      DATABASE_ID,
      collectionId,
      key,
      type,
      attributes,
      orders
    );
    console.log(`  ✅ Index: ${key}`);
  } catch (error) {
    if (error.code === 409) {
      console.log(`  ⏭️  Index exists: ${key}`);
    } else {
      console.error(`  ❌ Failed index ${key}: ${error.message}`);
    }
  }
}

async function waitForAttributes(collectionId, expectedCount) {
  console.log(`  ⏳ Waiting for attributes to be ready...`);
  for (let i = 0; i < 30; i++) {
    await sleep(2000);
    try {
      const collection = await databases.getCollection(DATABASE_ID, collectionId);
      const availableAttrs = collection.attributes.filter(a => a.status === 'available').length;
      if (availableAttrs >= expectedCount) {
        console.log(`  ✅ All ${availableAttrs} attributes ready`);
        return;
      }
      console.log(`  ⏳ ${availableAttrs}/${expectedCount} attributes ready...`);
    } catch (e) {
      // ignore
    }
  }
  console.log(`  ⚠️ Timeout waiting for attributes, continuing anyway...`);
}

async function setupPriceAdjustments() {
  console.log('\n📦 Setting up price_adjustments collection...');
  
  await createCollection('price_adjustments', 'Price Adjustments', [
    Permission.read(Role.any()),
    Permission.create(Role.any()),
    Permission.update(Role.any()),
  ]);

  await sleep(1000);

  // Sync fields
  await createStringAttribute('price_adjustments', 'localUuid', 36, true);
  await createIntegerAttribute('price_adjustments', 'serverId', false);
  await createIntegerAttribute('price_adjustments', 'createdAt', true);
  await createIntegerAttribute('price_adjustments', 'updatedAt', true);
  await createIntegerAttribute('price_adjustments', 'deletedAt', false);
  await createIntegerAttribute('price_adjustments', 'lastModified', true);
  await createIntegerAttribute('price_adjustments', 'version', false, null, null, 1);
  await createStringAttribute('price_adjustments', 'origin', 50, false, 'local');
  await createStringAttribute('price_adjustments', 'vectorClock', 1000, false, '{}');

  // Business fields
  await createStringAttribute('price_adjustments', 'targetType', 50, true);
  await createStringAttribute('price_adjustments', 'targetUuid', 36, true);
  await createStringAttribute('price_adjustments', 'adjustmentType', 50, true);
  await createFloatAttribute('price_adjustments', 'previousValue', true);
  await createFloatAttribute('price_adjustments', 'newValue', true);
  await createStringAttribute('price_adjustments', 'reason', 500, false);
  await createStringAttribute('price_adjustments', 'effectiveDate', 30, true);
  await createStringAttribute('price_adjustments', 'appliedBy', 100, true);
  await createStringAttribute('price_adjustments', 'hotelDayKey', 20, true);
  await createBooleanAttribute('price_adjustments', 'isReversed', false, false);
  await createStringAttribute('price_adjustments', 'reversedAt', 30, false);
  await createStringAttribute('price_adjustments', 'reversedBy', 100, false);

  // Sync fields
  await createStringAttribute('price_adjustments', 'deviceId', 50, false);
  await createIntegerAttribute('price_adjustments', 'syncTimestamp', false);

  await waitForAttributes('price_adjustments', 20);

  // Indexes
  await createIndex('price_adjustments', 'idx_local_uuid', IndexType.Unique, ['localUuid']);
  await createIndex('price_adjustments', 'idx_target', IndexType.Key, ['targetType', 'targetUuid']);
  await createIndex('price_adjustments', 'idx_hotel_day', IndexType.Key, ['hotelDayKey']);
  await createIndex('price_adjustments', 'idx_sync_ts', IndexType.Key, ['syncTimestamp']);
}

async function setupAuditLogs() {
  console.log('\n📦 Setting up audit_logs collection...');
  
  // IMPORTANT: audit_logs has NO update/delete permissions - logs are immutable
  await createCollection('audit_logs', 'Audit Logs', [
    Permission.read(Role.any()),
    Permission.create(Role.any()),
    // NO update or delete permissions!
  ]);

  await sleep(1000);

  // Core fields
  await createStringAttribute('audit_logs', 'localUuid', 36, true);
  await createIntegerAttribute('audit_logs', 'createdAt', true);
  
  // Audit fields
  await createStringAttribute('audit_logs', 'operationType', 50, true);
  await createStringAttribute('audit_logs', 'entityType', 50, true);
  await createStringAttribute('audit_logs', 'entityUuid', 36, true);
  await createIntegerAttribute('audit_logs', 'entityId', false);
  await createStringAttribute('audit_logs', 'previousState', 10000, false);
  await createStringAttribute('audit_logs', 'newState', 10000, false);
  await createStringAttribute('audit_logs', 'changedFields', 2000, false);
  await createStringAttribute('audit_logs', 'performedBy', 100, true);
  await createStringAttribute('audit_logs', 'deviceId', 50, true);
  await createStringAttribute('audit_logs', 'ipAddress', 50, false);
  await createStringAttribute('audit_logs', 'hotelDayKey', 20, true);
  await createIntegerAttribute('audit_logs', 'timestamp', true);
  await createStringAttribute('audit_logs', 'timestampIso', 30, true);
  await createBooleanAttribute('audit_logs', 'isFinancial', false, false);
  await createFloatAttribute('audit_logs', 'amountImpact', false);

  // Sync field
  await createIntegerAttribute('audit_logs', 'syncTimestamp', false);

  await waitForAttributes('audit_logs', 18);

  // Indexes
  await createIndex('audit_logs', 'idx_local_uuid', IndexType.Unique, ['localUuid']);
  await createIndex('audit_logs', 'idx_entity', IndexType.Key, ['entityType', 'entityUuid']);
  await createIndex('audit_logs', 'idx_timestamp', IndexType.Key, ['timestamp'], ['DESC']);
  await createIndex('audit_logs', 'idx_financial', IndexType.Key, ['isFinancial', 'hotelDayKey']);
  await createIndex('audit_logs', 'idx_sync_ts', IndexType.Key, ['syncTimestamp']);
}

async function setupPaymentVoids() {
  console.log('\n📦 Setting up payment_voids collection...');
  
  await createCollection('payment_voids', 'Payment Voids', [
    Permission.read(Role.any()),
    Permission.create(Role.any()),
    Permission.update(Role.any()),
  ]);

  await sleep(1000);

  // Sync fields
  await createStringAttribute('payment_voids', 'localUuid', 36, true);
  await createIntegerAttribute('payment_voids', 'serverId', false);
  await createIntegerAttribute('payment_voids', 'createdAt', true);
  await createIntegerAttribute('payment_voids', 'updatedAt', true);
  await createIntegerAttribute('payment_voids', 'deletedAt', false);
  await createIntegerAttribute('payment_voids', 'lastModified', true);
  await createIntegerAttribute('payment_voids', 'version', false, null, null, 1);
  await createStringAttribute('payment_voids', 'origin', 50, false, 'local');
  await createStringAttribute('payment_voids', 'vectorClock', 1000, false, '{}');

  // Void fields
  await createStringAttribute('payment_voids', 'originalPaymentUuid', 36, true);
  await createIntegerAttribute('payment_voids', 'originalPaymentId', true);
  await createStringAttribute('payment_voids', 'bookingUuid', 36, true);
  await createFloatAttribute('payment_voids', 'voidedAmount', true);
  await createStringAttribute('payment_voids', 'voidReason', 500, true);
  await createStringAttribute('payment_voids', 'voidedBy', 100, true);
  await createIntegerAttribute('payment_voids', 'voidedAt', true);
  await createStringAttribute('payment_voids', 'voidedAtIso', 30, true);
  await createStringAttribute('payment_voids', 'hotelDayKey', 20, true);
  await createStringAttribute('payment_voids', 'reversalPaymentUuid', 36, false);
  await createStringAttribute('payment_voids', 'approvedBy', 100, false);

  // Sync fields
  await createStringAttribute('payment_voids', 'deviceId', 50, false);
  await createIntegerAttribute('payment_voids', 'syncTimestamp', false);

  await waitForAttributes('payment_voids', 22);

  // Indexes
  await createIndex('payment_voids', 'idx_local_uuid', IndexType.Unique, ['localUuid']);
  await createIndex('payment_voids', 'idx_original_payment', IndexType.Unique, ['originalPaymentUuid']);
  await createIndex('payment_voids', 'idx_booking', IndexType.Key, ['bookingUuid']);
  await createIndex('payment_voids', 'idx_hotel_day', IndexType.Key, ['hotelDayKey']);
  await createIndex('payment_voids', 'idx_sync_ts', IndexType.Key, ['syncTimestamp']);
}

async function addPaymentsImmutabilityFields() {
  console.log('\n📦 Adding immutability fields to payments collection...');
  
  await createBooleanAttribute('payments', 'isImmutable', false, false);
  await createBooleanAttribute('payments', 'isVoided', false, false);
  await createIntegerAttribute('payments', 'voidedAt', false);
  await createStringAttribute('payments', 'voidedBy', 100, false);
  
  console.log('  ⏳ Waiting for attributes...');
  await sleep(5000);
  
  await createIndex('payments', 'idx_voided', IndexType.Key, ['isVoided']);
}

async function addBookingsFinancialFields() {
  console.log('\n📦 Adding financial freeze fields to bookings collection...');
  
  await createIntegerAttribute('bookings', 'financialFrozenAt', false);
  await createStringAttribute('bookings', 'financialHash', 64, false);
  
  console.log('  ⏳ Waiting for attributes...');
  await sleep(5000);
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════');
  console.log('🏨 Marina Hotel - Appwrite Schema Setup');
  console.log('═══════════════════════════════════════════════════════════');
  console.log(`Endpoint: ${ENDPOINT}`);
  console.log(`Project: ${PROJECT_ID}`);
  console.log(`Database: ${DATABASE_ID}`);
  console.log('═══════════════════════════════════════════════════════════\n');

  try {
    // Phase 1: Create new collections
    await setupPriceAdjustments();
    await setupAuditLogs();
    await setupPaymentVoids();

    // Phase 2: Update existing collections
    await addPaymentsImmutabilityFields();
    await addBookingsFinancialFields();

    console.log('\n═══════════════════════════════════════════════════════════');
    console.log('✅ Schema setup complete!');
    console.log('═══════════════════════════════════════════════════════════');
    console.log('\nNext steps:');
    console.log('1. Run "flutter pub get && dart run build_runner build" in mobile/');
    console.log('2. Test sync with the app');
    console.log('═══════════════════════════════════════════════════════════\n');

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

main();
