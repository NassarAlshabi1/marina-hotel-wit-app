#!/usr/bin/env node
/**
 * إنشاء الـ collections السبع المفقودة على Appwrite Cloud.
 *
 * المشكلة: التطبيق يحاول مزامنة 7 collections غير موجودة على السيرفر،
 * مما يسبب فشل كل عملية push لهاذه الكيانات:
 *   - guest_infos (معلومات النزلاء: الجنسية، رقم الهوية، تاريخ/مكان الإصدار، المحافظة)
 *   - salary_withdrawals (سحوبات الرواتب)
 *   - salary_carry_over_logs (سجل ترحيل الرصيد)
 *   - blacklist (القائمة السوداء)
 *   - app_settings (إعدادات التطبيق)
 *   - app_users (مستخدمو التطبيق)
 *   - sync_state (حالة المزامنة)
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node create_missing_collections.js
 *
 * آمن: يفحص إن كانت الـ collection موجودة قبل إنشائها (idempotent).
 */

const { Client, Databases, Permission, Role } = require('node-appwrite');

// ─── إعدادات Appwrite Cloud ─────────────────────────────────────────────────
const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;

if (!apiKey) {
  console.error('❌ Error: APPWRITE_API_KEY environment variable is required');
  console.log('Usage: APPWRITE_API_KEY=your_key node create_missing_collections.js');
  process.exit(1);
}

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

// ─── الصلاحيات الافتراضية ────────────────────────────────────────────────────
const defaultPermissions = [
  Permission.read(Role.any()),
  Permission.create(Role.any()),
  Permission.update(Role.any()),
  Permission.delete(Role.any()),
];

// ─── تعريفات الـ collections المفقودة ─────────────────────────────────────────
// مبنية على local_db.dart + validFieldsPerCollection في appwrite_sync_utils.dart
// النوع: string (size 255 default), integer, double, boolean

const missingCollections = [
  // ─── 1. guest_infos (معلومات النزلاء) ───────────────────────────────────
  // المشكلة الأصلية: الجنسية، رقم الهوية، تاريخ/مكان الإصدار، المحافظة
  // لا تتم مزامنتها لأن الـ collection غير موجود على السيرفر.
  {
    id: 'guest_infos',
    name: 'Guest Infos',
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true },
      { key: 'roomNumber', type: 'string', size: 20, required: true },
      { key: 'guestName', type: 'string', size: 255, required: true },
      { key: 'nationality', type: 'string', size: 100, required: true },
      { key: 'idNumber', type: 'string', size: 100, required: true },
      { key: 'idType', type: 'string', size: 50, required: false },
      { key: 'issueDate', type: 'string', size: 30, required: false },
      { key: 'issuePlace', type: 'string', size: 100, required: false },
      { key: 'governorate', type: 'string', size: 100, required: false },
      { key: 'notes', type: 'string', size: 2000, required: false },
      // Sync fields
      { key: 'serverId', type: 'integer', required: false },
      { key: 'createdAt', type: 'integer', required: false },
      { key: 'updatedAt', type: 'integer', required: false },
      { key: 'deletedAt', type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: false },
      { key: 'createdAtIso', type: 'string', size: 30, required: false },
      { key: 'updatedAtIso', type: 'string', size: 30, required: false },
      { key: 'deletedAtIso', type: 'string', size: 30, required: false },
      { key: 'createdAtEpoch', type: 'integer', required: false },
      { key: 'lastModifiedEpoch', type: 'integer', required: false },
      { key: 'syncTimestamp', type: 'integer', required: false },
      { key: 'deviceId', type: 'string', size: 100, required: false },
      { key: 'version', type: 'integer', required: false },
      { key: 'origin', type: 'string', size: 20, required: false },
      { key: 'vectorClock', type: 'string', size: 500, required: false },
      { key: 'sync_origin', type: 'string', size: 20, required: false },
      { key: 'idempotencyKey', type: 'string', size: 100, required: false },
    ],
  },

  // ─── 2. salary_withdrawals (سحوبات الرواتب) ─────────────────────────────
  {
    id: 'salary_withdrawals',
    name: 'Salary Withdrawals',
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true },
      { key: 'employeeId', type: 'integer', required: false },
      { key: 'employeeLocalUuid', type: 'string', size: 36, required: false },
      { key: 'employeeUuid', type: 'string', size: 36, required: false },
      { key: 'name', type: 'string', size: 255, required: false },
      { key: 'amount', type: 'double', required: true },
      { key: 'date', type: 'string', size: 30, required: false },
      { key: 'withdrawDate', type: 'string', size: 30, required: false },
      { key: 'reason', type: 'string', size: 500, required: false },
      { key: 'note', type: 'string', size: 1000, required: false },
      { key: 'description', type: 'string', size: 1000, required: false },
      { key: 'action', type: 'string', size: 50, required: false },
      { key: 'withdrawalType', type: 'string', size: 50, required: false },
      { key: 'expenseId', type: 'integer', required: false },
      { key: 'hotelDayKey', type: 'string', size: 30, required: false },
      // Sync fields
      { key: 'serverId', type: 'integer', required: false },
      { key: 'createdAt', type: 'integer', required: false },
      { key: 'updatedAt', type: 'integer', required: false },
      { key: 'deletedAt', type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: false },
      { key: 'createdAtIso', type: 'string', size: 30, required: false },
      { key: 'updatedAtIso', type: 'string', size: 30, required: false },
      { key: 'deletedAtIso', type: 'string', size: 30, required: false },
      { key: 'createdAtEpoch', type: 'integer', required: false },
      { key: 'lastModifiedEpoch', type: 'integer', required: false },
      { key: 'syncTimestamp', type: 'integer', required: false },
      { key: 'deviceId', type: 'string', size: 100, required: false },
      { key: 'version', type: 'integer', required: false },
      { key: 'origin', type: 'string', size: 20, required: false },
      { key: 'vectorClock', type: 'string', size: 500, required: false },
      { key: 'sync_origin', type: 'string', size: 20, required: false },
      { key: 'idempotencyKey', type: 'string', size: 100, required: false },
    ],
  },

  // ─── 3. salary_carry_over_logs (سجل ترحيل الرصيد) ──────────────────────
  {
    id: 'salary_carry_over_logs',
    name: 'Salary Carry Over Logs',
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true },
      { key: 'employeeId', type: 'integer', required: false },
      { key: 'amount', type: 'double', required: true },
      { key: 'reason', type: 'string', size: 500, required: false },
      { key: 'carriedAt', type: 'integer', required: false },
      { key: 'previousCycleStart', type: 'string', size: 30, required: false },
      { key: 'previousCycleEnd', type: 'string', size: 30, required: false },
      { key: 'newCycleStart', type: 'string', size: 30, required: false },
      { key: 'newCycleEnd', type: 'string', size: 30, required: false },
      // Sync fields
      { key: 'serverId', type: 'integer', required: false },
      { key: 'createdAt', type: 'integer', required: false },
      { key: 'updatedAt', type: 'integer', required: false },
      { key: 'deletedAt', type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: false },
      { key: 'createdAtIso', type: 'string', size: 30, required: false },
      { key: 'updatedAtIso', type: 'string', size: 30, required: false },
      { key: 'deletedAtIso', type: 'string', size: 30, required: false },
      { key: 'createdAtEpoch', type: 'integer', required: false },
      { key: 'lastModifiedEpoch', type: 'integer', required: false },
      { key: 'syncTimestamp', type: 'integer', required: false },
      { key: 'deviceId', type: 'string', size: 100, required: false },
      { key: 'version', type: 'integer', required: false },
      { key: 'origin', type: 'string', size: 20, required: false },
      { key: 'vectorClock', type: 'string', size: 500, required: false },
      { key: 'sync_origin', type: 'string', size: 20, required: false },
      { key: 'idempotencyKey', type: 'string', size: 100, required: false },
    ],
  },

  // ─── 4. blacklist (القائمة السوداء) ────────────────────────────────────
  {
    id: 'blacklist',
    name: 'Blacklist',
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true },
      { key: 'name', type: 'string', size: 255, required: true },
      { key: 'nationalId', type: 'string', size: 100, required: false },
      { key: 'nationality', type: 'string', size: 100, required: false },
      { key: 'phone', type: 'string', size: 30, required: false },
      { key: 'reason', type: 'string', size: 1000, required: false },
      { key: 'notes', type: 'string', size: 2000, required: false },
      { key: 'reportedBy', type: 'string', size: 255, required: false },
      { key: 'active', type: 'boolean', required: false },
      // Sync fields
      { key: 'serverId', type: 'integer', required: false },
      { key: 'createdAt', type: 'integer', required: false },
      { key: 'updatedAt', type: 'integer', required: false },
      { key: 'deletedAt', type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: false },
      { key: 'createdAtIso', type: 'string', size: 30, required: false },
      { key: 'updatedAtIso', type: 'string', size: 30, required: false },
      { key: 'deletedAtIso', type: 'string', size: 30, required: false },
      { key: 'createdAtEpoch', type: 'integer', required: false },
      { key: 'lastModifiedEpoch', type: 'integer', required: false },
      { key: 'syncTimestamp', type: 'integer', required: false },
      { key: 'deviceId', type: 'string', size: 100, required: false },
      { key: 'version', type: 'integer', required: false },
      { key: 'origin', type: 'string', size: 20, required: false },
      { key: 'vectorClock', type: 'string', size: 500, required: false },
      { key: 'sync_origin', type: 'string', size: 20, required: false },
      { key: 'idempotencyKey', type: 'string', size: 100, required: false },
    ],
  },

  // ─── 5. app_settings (إعدادات التطبيق) ─────────────────────────────────
  {
    id: 'app_settings',
    name: 'App Settings',
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true },
      { key: 'key', type: 'string', size: 100, required: true },
      { key: 'endpoint', type: 'string', size: 500, required: false },
      { key: 'enabled', type: 'boolean', required: false },
      // Sync fields
      { key: 'serverId', type: 'integer', required: false },
      { key: 'createdAt', type: 'integer', required: false },
      { key: 'updatedAt', type: 'integer', required: false },
      { key: 'deletedAt', type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: false },
      { key: 'createdAtIso', type: 'string', size: 30, required: false },
      { key: 'updatedAtIso', type: 'string', size: 30, required: false },
      { key: 'deletedAtIso', type: 'string', size: 30, required: false },
      { key: 'createdAtEpoch', type: 'integer', required: false },
      { key: 'lastModifiedEpoch', type: 'integer', required: false },
      { key: 'syncTimestamp', type: 'integer', required: false },
      { key: 'deviceId', type: 'string', size: 100, required: false },
      { key: 'version', type: 'integer', required: false },
      { key: 'origin', type: 'string', size: 20, required: false },
      { key: 'vectorClock', type: 'string', size: 500, required: false },
      { key: 'sync_origin', type: 'string', size: 20, required: false },
      { key: 'idempotencyKey', type: 'string', size: 100, required: false },
    ],
  },

  // ─── 6. app_users (مستخدمو التطبيق) ────────────────────────────────────
  // ملاحظة: app_users لا يحتوي على كل حقول الـ sync لأنه جدول قديم.
  {
    id: 'app_users',
    name: 'App Users',
    attributes: [
      { key: 'username', type: 'string', size: 100, required: true },
      { key: 'password', type: 'string', size: 255, required: true },
      { key: 'fullName', type: 'string', size: 255, required: false },
      { key: 'userType', type: 'string', size: 50, required: false },
      { key: 'permissions', type: 'string', size: 2000, required: false },
      { key: 'active', type: 'boolean', required: false },
      { key: 'lastLogin', type: 'integer', required: false },
      { key: 'version', type: 'integer', required: false },
    ],
  },

  // ─── 7. sync_state (حالة المزامنة) ─────────────────────────────────────
  {
    id: 'sync_state',
    name: 'Sync State',
    attributes: [
      { key: 'localUuid', type: 'string', size: 36, required: true },
      { key: 'lastSyncTime', type: 'integer', required: false },
      { key: 'isSyncing', type: 'boolean', required: false },
      // Sync fields (مختصر — sync_state جدول مرجعي)
      { key: 'serverId', type: 'integer', required: false },
      { key: 'createdAt', type: 'integer', required: false },
      { key: 'updatedAt', type: 'integer', required: false },
      { key: 'deletedAt', type: 'integer', required: false },
      { key: 'lastModified', type: 'integer', required: false },
      { key: 'origin', type: 'string', size: 20, required: false },
      { key: 'version', type: 'integer', required: false },
    ],
  },
];

// ─── المنطق الرئيسي ──────────────────────────────────────────────────────────
async function collectionExists(collectionId) {
  try {
    await databases.getCollection(databaseId, collectionId);
    return true;
  } catch (e) {
    if (e.code === 404 || (e.message && e.message.includes('not found'))) {
      return false;
    }
    throw e;
  }
}

async function createCollection(def) {
  console.log(`\n📝 Creating collection: ${def.id} (${def.name})`);
  console.log(`   ${def.attributes.length} attributes`);

  // 1) أنشئ الـ collection
  await databases.createCollection(
    databaseId,
    def.id,           // collectionId (custom ID)
    def.name,         // name
    defaultPermissions,
    false             // documentSecurity
  );
  console.log(`   ✅ Collection created`);

  // 2) أضف الـ attributes
  let added = 0;
  let skipped = 0;
  for (const attr of def.attributes) {
    try {
      if (attr.type === 'string') {
        await databases.createStringAttribute(
          databaseId,
          def.id,
          attr.key,
          attr.size || 255,
          attr.required || false,
          attr.default
        );
      } else if (attr.type === 'integer') {
        await databases.createIntegerAttribute(
          databaseId,
          def.id,
          attr.key,
          attr.required || false,
          attr.min,
          attr.max,
          attr.default
        );
      } else if (attr.type === 'double') {
        await databases.createFloatAttribute(
          databaseId,
          def.id,
          attr.key,
          attr.required || false,
          attr.min,
          attr.max,
          attr.default
        );
      } else if (attr.type === 'boolean') {
        await databases.createBooleanAttribute(
          databaseId,
          def.id,
          attr.key,
          attr.required || false,
          attr.default
        );
      }
      added++;
    } catch (e) {
      if (e.code === 409 || (e.message && e.message.includes('already exists'))) {
        skipped++;
      } else {
        console.error(`   ⚠️  Failed to add attribute '${attr.key}': ${e.message}`);
      }
    }
  }
  console.log(`   ✅ ${added} attributes added, ${skipped} already existed`);
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  إنشاء الـ collections السبع المفقودة على Appwrite Cloud');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  Endpoint:   ${endpoint}`);
  console.log(`  Project:    ${projectId}`);
  console.log(`  Database:   ${databaseId}`);
  console.log(`  Collections to check: ${missingCollections.length}`);
  console.log('═══════════════════════════════════════════════════════════════\n');

  let created = 0;
  let alreadyExists = 0;
  let failed = 0;

  for (const def of missingCollections) {
    try {
      const exists = await collectionExists(def.id);
      if (exists) {
        console.log(`✓ ${def.id} — already exists, skipping`);
        alreadyExists++;
        continue;
      }
      await createCollection(def);
      created++;
    } catch (e) {
      console.error(`❌ Failed to create ${def.id}: ${e.message}`);
      failed++;
    }
  }

  console.log('\n═══════════════════════════════════════════════════════════════');
  console.log('  الملخص');
  console.log('═══════════════════════════════════════════════════════════════');
  console.log(`  ✅ Created:        ${created}`);
  console.log(`  ✓ Already existed: ${alreadyExists}`);
  console.log(`  ❌ Failed:         ${failed}`);
  console.log('');

  if (failed > 0) {
    process.exit(1);
  }
}

main().catch((e) => {
  console.error('Fatal error:', e);
  process.exit(1);
});
