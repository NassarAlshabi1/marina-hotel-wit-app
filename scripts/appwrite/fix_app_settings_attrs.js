#!/usr/bin/env node
/**
 * إضافة الحقول الناقصة في مجموعة app_settings في Appwrite Cloud
 * جميع الحقول الجديدة تكون اختيارية (required = false)
 */

const { Client, Databases } = require('node-appwrite');

const ENDPOINT = 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = '690ff0da0025518570c1';
const DATABASE_ID = 'hotel_db';
const COLLECTION_ID = 'app_settings';
const API_KEY = 'standard_4158f40bb3d2e370befc7df85f6f66dfa06dcc068036f60085b155e88d46546f57ffec6c9a6d4ea3b7ba11bf0e5dce276122ecb5aa20cd96bb8d08aa33eddd0d7a531171bf7d763509215657a3d138d1a9393228550ff14102903127bfade5ef0b93f87baa39d2850e7f7d4cedca6190d9179d2e5239a2c53c4d941a89ef84da';

async function main() {
  const client = new Client().setEndpoint(ENDPOINT).setProject(PROJECT_ID).setKey(API_KEY);
  const databases = new Databases(client);

  // الحقول الموجودة حالياً في Appwrite Cloud
  const existingAttrs = new Set();
  try {
    const { attributes } = await databases.listAttributes(DATABASE_ID, COLLECTION_ID);
    for (const attr of attributes) {
      if (attr.key && !attr.key.startsWith('$')) {
        existingAttrs.add(attr.key);
      }
    }
    console.log(`📋 الحقول الموجودة حالياً (${existingAttrs.size}):`);
    for (const key of [...existingAttrs].sort()) {
      console.log(`   ✅ ${key}`);
    }
  } catch (e) {
    console.error('❌ فشل قراءة الحقول:', e.message);
    process.exit(1);
  }

  // الحقول الناقصة التي يرسلها الكود وغير موجودة في المخطط
  // جميعها اختيارية (required = false)
  const missingAttrs = [
    // ── حقول أساسية ──
    { key: 'key', type: 'string', size: 200, required: false, default: '' },
    { key: 'value', type: 'string', size: 500, required: false, default: '' },
    { key: 'createdAt', type: 'integer', required: false, default: 0 },
    // ── حقول المزامنة ──
    { key: 'sync_origin', type: 'string', size: 64, required: false, default: 'mobile' },
    { key: 'sync_vector_clock', type: 'string', size: 2000, required: false, default: '{}' },
    // ── إعدادات إضافية ──
    { key: 'lark_notifications_enabled', type: 'boolean', required: false, default: true },
    { key: 'appwrite_auto_sync_on_connect', type: 'boolean', required: false, default: true },
    { key: 'conflict_strategy', type: 'string', size: 50, required: false, default: 'newerWins' },
    { key: 'sync_performance_profile', type: 'string', size: 50, required: false, default: 'balanced' },
    { key: 'wifi_only_sync', type: 'boolean', required: false, default: false },
    // ── نسخ احتياطي ──
    { key: 'scheduled_backup_enabled', type: 'boolean', required: false, default: true },
    { key: 'auto_backup_time', type: 'string', size: 10, required: false, default: '21:00' },
    { key: 'auto_backup_frequency', type: 'string', size: 20, required: false, default: 'daily' },
    // ── سجل ──
    { key: 'appwrite_log_level', type: 'string', size: 20, required: false, default: 'info' },
    { key: 'appwrite_log_console', type: 'boolean', required: false, default: true },
    { key: 'appwrite_log_file', type: 'boolean', required: false, default: false },
  ];

  // فلترة الحقول التي لا تزال ناقصة
  const toAdd = missingAttrs.filter(a => !existingAttrs.has(a.key));
  
  if (toAdd.length === 0) {
    console.log('\n✅ جميع الحقول موجودة مسبقاً - لا حاجة لإضافة شيء');
    return;
  }

  console.log(`\n📝 الحقول الناقصة التي ستُضاف (${toAdd.length}):`);
  for (const attr of toAdd) {
    console.log(`   ➕ ${attr.key} (${attr.type}) ${attr.required ? 'REQ' : 'OPT'}`);
  }

  // إضافة الحقول واحداً تلو الآخر
  let success = 0;
  let skipped = 0;
  let failed = 0;

  for (const attr of toAdd) {
    try {
      const payload = {
        key: attr.key,
        required: attr.required,
      };

      if (attr.type === 'string') {
        payload.size = attr.size || 255;
        if (attr.default !== undefined) payload.default = attr.default;
      } else if (attr.type === 'integer') {
        payload.min = -9223372036854776000;
        payload.max = 9223372036854776000;
        if (attr.default !== undefined) payload.default = attr.default;
      } else if (attr.type === 'boolean') {
        if (attr.default !== undefined) payload.default = attr.default;
      }

      const url = `${ENDPOINT}/databases/${DATABASE_ID}/collections/${COLLECTION_ID}/attributes/${attr.type}`;
      
      const resp = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'X-Appwrite-Project': PROJECT_ID,
          'X-Appwrite-Key': API_KEY,
        },
        body: JSON.stringify(payload),
      });

      if (resp.ok) {
        console.log(`   ✅ تم إضافة ${attr.key}`);
        success++;
      } else {
        const text = await resp.text();
        if (text.includes('already exists') || text.includes('409')) {
          console.log(`   ⏭️ ${attr.key} موجود مسبقاً`);
          skipped++;
        } else {
          console.log(`   ❌ ${attr.key}: ${resp.status} — ${text.substring(0, 150)}`);
          failed++;
        }
      }

      // انتظار قصير بين الطلبات لتجنب rate limiting
      await new Promise(r => setTimeout(r, 500));
    } catch (e) {
      console.log(`   ❌ ${attr.key}: ${e.message}`);
      failed++;
    }
  }

  console.log(`\n📊 النتيجة: ✅ ${success} أُضيف | ⏭️ ${skipped} موجود | ❌ ${failed} فشل`);
}

main().catch(e => { console.error(e); process.exit(1); });
