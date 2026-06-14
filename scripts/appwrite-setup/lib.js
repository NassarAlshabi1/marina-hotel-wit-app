/**
 * سكريبت إنشاء المجموعات - يعمل بالدفعات لتجنب timeout
 * الاستخدام: node create-collections-batch1.js (ثم batch2, batch3...)
 */
const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '6a2b01d0000752ce97e7';
const DATABASE_ID = '6a2b030d000445596163';
const API_KEY = 'standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d';

const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
const db = new Databases(client);
const DB = DATABASE_ID;
const d = ms => new Promise(r => setTimeout(r, ms));

const SYNC_FIELDS = [
  { key: 'localUuid', type: 'string', size: 64, required: true },
  { key: 'serverId', type: 'integer', required: false },
  { key: 'createdAt', type: 'integer', required: true },
  { key: 'updatedAt', type: 'integer', required: true },
  { key: 'deletedAt', type: 'integer', required: false },
  { key: 'lastModified', type: 'integer', required: true },
  { key: 'createdAtIso', type: 'string', size: 50, required: false },
  { key: 'updatedAtIso', type: 'string', size: 50, required: false },
  { key: 'deletedAtIso', type: 'string', size: 50, required: false },
  { key: 'createdAtEpoch', type: 'integer', required: false, default: 0 },
  { key: 'lastModifiedEpoch', type: 'integer', required: false, default: 0 },
  { key: 'version', type: 'integer', required: false, default: 1 },
  { key: 'origin', type: 'string', size: 50, required: false, default: 'local' },
  { key: 'vectorClock', type: 'string', size: 1024, required: false, default: '{}' },
  { key: 'deviceId', type: 'string', size: 128, required: false },
];

async function addAttr(collId, field) {
  try {
    switch (field.type) {
      case 'string':
        await db.createStringAttribute(DB, collId, field.key, field.size || 255, field.required || false, field.default !== undefined ? String(field.default) : undefined);
        break;
      case 'integer':
        await db.createIntegerAttribute(DB, collId, field.key, field.required || false, undefined, undefined, field.default);
        break;
      case 'double':
        await db.createFloatAttribute(DB, collId, field.key, field.required || false, undefined, undefined, field.default);
        break;
      case 'boolean':
        await db.createBooleanAttribute(DB, collId, field.key, field.required || false, field.default);
        break;
    }
    return 'ok';
  } catch (e) {
    if (e.message && e.message.includes('already exists')) return 'skip';
    console.log('    ERR ' + field.key + ': ' + e.message);
    return 'err';
  }
}

async function createCollection(name, fields, syncFields = true) {
  console.log(`\n📦 ${name}`);
  try {
    await db.createCollection(DB, name, name);
    console.log('  ✅ Collection created');
  } catch (e) {
    if (e.message.includes('already exists')) console.log('  ℹ️ Already exists');
    else { console.log('  ❌ ' + e.message); return; }
  }
  await d(500);

  let ok = 0, skip = 0, err = 0;
  for (const f of fields) {
    const r = await addAttr(name, f);
    if (r === 'ok') { ok++; process.stdout.write('.'); }
    else if (r === 'skip') skip++;
    else err++;
    await d(200);
  }
  
  if (syncFields) {
    for (const f of SYNC_FIELDS) {
      const r = await addAttr(name, f);
      if (r === 'ok') { ok++; process.stdout.write('+'); }
      else if (r === 'skip') skip++;
      else err++;
      await d(200);
    }
  }
  
  const total = fields.length + (syncFields ? SYNC_FIELDS.length : 0);
  console.log(`\n  📊 ${ok} created, ${skip} existed, ${err} errors (total: ${total})`);
  return { ok, skip, err };
}

module.exports = { createCollection, db, DB, d };
