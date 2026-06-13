const { Client, Databases, Permission, Role } = require('node-appwrite');

const endpoint = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const projectId = process.env.APPWRITE_PROJECT;
const apiKey = process.env.APPWRITE_API_KEY;
const databaseId = process.env.APPWRITE_DATABASE_ID || '6a2b030d000445596163';

if (!apiKey || !projectId) {
  console.error('❌ APPWRITE_API_KEY and APPWRITE_PROJECT required');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);
const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

const defaultPermissions = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

const mutablePermissions = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
];

async function createString(colId, key, size, required = false) {
  try { await databases.createStringAttribute(databaseId, colId, key, size, required); console.log(`  ✅ string: ${key}`); }
  catch (e) { if (e.code !== 409) console.error(`  ❌ ${key}: ${e.message}`); }
}
async function createInt(colId, key, required = false) {
  try { await databases.createIntegerAttribute(databaseId, colId, key, required); console.log(`  ✅ int: ${key}`); }
  catch (e) { if (e.code !== 409) console.error(`  ❌ ${key}: ${e.message}`); }
}
async function createFloat(colId, key, required = false) {
  try { await databases.createFloatAttribute(databaseId, colId, key, required); console.log(`  ✅ float: ${key}`); }
  catch (e) { if (e.code !== 409) console.error(`  ❌ ${key}: ${e.message}`); }
}
async function createBool(colId, key, required = false) {
  try { await databases.createBooleanAttribute(databaseId, colId, key, required); console.log(`  ✅ bool: ${key}`); }
  catch (e) { if (e.code !== 409) console.error(`  ❌ ${key}: ${e.message}`); }
}
async function createCol(colId, name) {
  try {
    await databases.createCollection(databaseId, colId, name, defaultPermissions);
    console.log(`✅ Created ${name} (${colId})`);
    return true;
  } catch (e) {
    if (e.code === 409) { console.log(`⏭️ ${name} exists`); return false; }
    console.error(`❌ ${name}: ${e.message}`);
    return false;
  }
}
async function createIndex(colId, key, type, attrs) {
  try { await databases.createIndex(databaseId, colId, key, type, attrs); console.log(`  📇 index: ${key}`); }
  catch (e) { if (e.code !== 409) console.error(`  ❌ index ${key}: ${e.message}`); }
}

async function retryFailedDevices() {
  console.log('\n🔧 Retrying failed Devices attributes...');
  await createBool('devices', 'isActive', true);
  await createInt('devices', 'serverId');
  await createInt('devices', 'createdAt', true);
  await createInt('devices', 'updatedAt', true);
}

async function addSyncFields() {
  console.log('\n🔧 Adding missing sync fields to all collections...');
  const syncCollections = [
    'rooms', 'bookings', 'booking_notes', 'booking_nights',
    'payments', 'expenses', 'cash_transactions', 'debts',
    'employees', 'salary_cycles', 'salary_payments',
    'hotel_day_ledger', 'shift_notes', 'devices', 'sync_logs'
  ];
  for (const col of syncCollections) {
    console.log(`  --- ${col} ---`);
    await createString(col, 'deviceId', 50);
    await createInt(col, 'syncTimestamp');
    await createString(col, 'origin', 20, false);
    await createString(col, 'vectorClock', 500, false);
    await createInt(col, 'version');
    await delay(300);
  }
}

async function setupPriceAdjustments() {
  console.log('\n📦 price_adjustments...');
  if (await createCol('price_adjustments', 'Price Adjustments')) await delay(1000);
  await createString('price_adjustments', 'localUuid', 36, true);
  await createInt('price_adjustments', 'serverId');
  await createInt('price_adjustments', 'createdAt', true);
  await createInt('price_adjustments', 'updatedAt', true);
  await createInt('price_adjustments', 'deletedAt');
  await createInt('price_adjustments', 'lastModified', true);
  await createInt('price_adjustments', 'version');
  await createString('price_adjustments', 'origin', 20);
  await createString('price_adjustments', 'vectorClock', 500);
  await createString('price_adjustments', 'targetType', 50, true);
  await createString('price_adjustments', 'targetUuid', 36, true);
  await createString('price_adjustments', 'adjustmentType', 50, true);
  await createFloat('price_adjustments', 'previousValue', true);
  await createFloat('price_adjustments', 'newValue', true);
  await createString('price_adjustments', 'reason', 500);
  await createString('price_adjustments', 'effectiveDate', 30, true);
  await createString('price_adjustments', 'appliedBy', 100, true);
  await createString('price_adjustments', 'hotelDayKey', 20, true);
  await createBool('price_adjustments', 'isReversed');
  await createString('price_adjustments', 'reversedAt', 30);
  await createString('price_adjustments', 'reversedBy', 100);
  await createString('price_adjustments', 'deviceId', 50);
  await createInt('price_adjustments', 'syncTimestamp');
  await delay(2000);
  await createIndex('price_adjustments', 'idx_pa_uuid', 'unique', ['localUuid']);
  await createIndex('price_adjustments', 'idx_pa_target', 'key', ['targetType', 'targetUuid']);
}

async function setupBookingPriceAdjustments() {
  console.log('\n📦 booking_price_adjustments...');
  if (await createCol('booking_price_adjustments', 'Booking Price Adjustments')) await delay(1000);
  await createString('booking_price_adjustments', 'localUuid', 36, true);
  await createString('booking_price_adjustments', 'bookingUuid', 36, true);
  await createString('booking_price_adjustments', 'adjustmentType', 50, true);
  await createFloat('booking_price_adjustments', 'amount', true);
  await createString('booking_price_adjustments', 'reason', 500);
  await createString('booking_price_adjustments', 'hotelDayKey', 20, true);
  await createString('booking_price_adjustments', 'createdBy', 100, true);
  await createInt('booking_price_adjustments', 'createdAt', true);
  await createString('booking_price_adjustments', 'deviceId', 50);
  await createInt('booking_price_adjustments', 'syncTimestamp');
  await delay(2000);
  await createIndex('booking_price_adjustments', 'idx_bpa_uuid', 'unique', ['localUuid']);
}

async function setupAuditLogs() {
  console.log('\n📦 audit_logs...');
  if (await createCol('audit_logs', 'Audit Logs')) await delay(1000);
  await createString('audit_logs', 'localUuid', 36, true);
  await createInt('audit_logs', 'createdAt', true);
  await createString('audit_logs', 'operationType', 50, true);
  await createString('audit_logs', 'entityType', 50, true);
  await createString('audit_logs', 'entityUuid', 36, true);
  await createInt('audit_logs', 'entityId');
  await createString('audit_logs', 'previousState', 10000);
  await createString('audit_logs', 'newState', 10000);
  await createString('audit_logs', 'changedFields', 2000);
  await createString('audit_logs', 'performedBy', 100, true);
  await createString('audit_logs', 'deviceId', 50, true);
  await createString('audit_logs', 'ipAddress', 50);
  await createString('audit_logs', 'hotelDayKey', 20, true);
  await createInt('audit_logs', 'timestamp', true);
  await createString('audit_logs', 'timestampIso', 30, true);
  await createBool('audit_logs', 'isFinancial');
  await createFloat('audit_logs', 'amountImpact');
  await createInt('audit_logs', 'syncTimestamp');
  await delay(2000);
  await createIndex('audit_logs', 'idx_al_uuid', 'unique', ['localUuid']);
}

async function setupPaymentVoids() {
  console.log('\n📦 payment_voids...');
  if (await createCol('payment_voids', 'Payment Voids')) await delay(1000);
  await createString('payment_voids', 'localUuid', 36, true);
  await createInt('payment_voids', 'serverId');
  await createInt('payment_voids', 'createdAt', true);
  await createInt('payment_voids', 'updatedAt', true);
  await createInt('payment_voids', 'deletedAt');
  await createInt('payment_voids', 'lastModified', true);
  await createInt('payment_voids', 'version');
  await createString('payment_voids', 'origin', 20);
  await createString('payment_voids', 'vectorClock', 500);
  await createString('payment_voids', 'originalPaymentUuid', 36, true);
  await createInt('payment_voids', 'originalPaymentId', true);
  await createString('payment_voids', 'bookingUuid', 36, true);
  await createFloat('payment_voids', 'voidedAmount', true);
  await createString('payment_voids', 'voidReason', 500, true);
  await createString('payment_voids', 'voidedBy', 100, true);
  await createInt('payment_voids', 'voidedAt', true);
  await createString('payment_voids', 'voidedAtIso', 30, true);
  await createString('payment_voids', 'hotelDayKey', 20, true);
  await createString('payment_voids', 'deviceId', 50);
  await createInt('payment_voids', 'syncTimestamp');
  await delay(2000);
  await createIndex('payment_voids', 'idx_pv_uuid', 'unique', ['localUuid']);
}

async function setupGuestInfos() {
  console.log('\n📦 guest_infos...');
  if (await createCol('guest_infos', 'Guest Infos')) await delay(1000);
  await createString('guest_infos', 'localUuid', 36, true);
  await createString('guest_infos', 'guestName', 100, true);
  await createString('guest_infos', 'guestPhone', 20, true);
  await createString('guest_infos', 'idType', 50);
  await createString('guest_infos', 'idNumber', 50);
  await createString('guest_infos', 'nationality', 50);
  await createString('guest_infos', 'notes', 500);
  await createInt('guest_infos', 'createdAt', true);
  await createString('guest_infos', 'deviceId', 50);
  await createInt('guest_infos', 'syncTimestamp');
  await delay(2000);
  await createIndex('guest_infos', 'idx_gi_uuid', 'unique', ['localUuid']);
}

async function setupSalaryWithdrawals() {
  console.log('\n📦 salary_withdrawals...');
  if (await createCol('salary_withdrawals', 'Salary Withdrawals')) await delay(1000);
  await createString('salary_withdrawals', 'localUuid', 36, true);
  await createInt('salary_withdrawals', 'employeeId', true);
  await createFloat('salary_withdrawals', 'amount', true);
  await createString('salary_withdrawals', 'date', 50, true);
  await createString('salary_withdrawals', 'notes', 255);
  await createString('salary_withdrawals', 'hotelDayKey', 20);
  await createString('salary_withdrawals', 'deviceId', 50);
  await createInt('salary_withdrawals', 'createdAt', true);
  await createInt('salary_withdrawals', 'syncTimestamp');
  await delay(2000);
  await createIndex('salary_withdrawals', 'idx_sw_uuid', 'unique', ['localUuid']);
}

async function setupAppSettings() {
  console.log('\n📦 app_settings...');
  if (await createCol('app_settings', 'App Settings')) await delay(1000);
  await createString('app_settings', 'localUuid', 36, true);
  await createString('app_settings', 'key', 100, true);
  await createString('app_settings', 'value', 5000, true);
  await createString('app_settings', 'deviceId', 50);
  await createInt('app_settings', 'createdAt', true);
  await createInt('app_settings', 'syncTimestamp');
  await delay(2000);
  await createIndex('app_settings', 'idx_as_uuid', 'unique', ['localUuid']);
  await createIndex('app_settings', 'idx_as_key', 'unique', ['key']);
}

async function main() {
  console.log('═══════════════════════════════════════════');
  console.log('🔄 Adding missing collections & attributes');
  console.log('═══════════════════════════════════════════\n');

  await retryFailedDevices();
  await addSyncFields();
  await setupPriceAdjustments();
  await setupBookingPriceAdjustments();
  await setupAuditLogs();
  await setupPaymentVoids();
  await setupGuestInfos();
  await setupSalaryWithdrawals();
  await setupAppSettings();

  console.log('\n✅ All missing collections & attributes added!');
}

main().catch(console.error);
