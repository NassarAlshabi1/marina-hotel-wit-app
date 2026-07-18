#!/usr/bin/env node
/**
 * يفحص الـ attributes الموجودة في كل collection على Appwrite Cloud.
 * يحاول إنشاء مستند وثم قراءته لاستخراج الحقول المتاحة.
 *
 * يستخدم وصول عام — لا يحتاج API key.
 */

const { Client, Databases, Query } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';

const client = new Client().setEndpoint(endpoint).setProject(projectId);
const databases = new Databases(client);

// الحقول المطلوبة لكل collection
const requiredFields = {
  'guest_infos': ['nationality', 'idNumber', 'issueDate', 'issuePlace', 'governorate'],
  'salary_withdrawals': ['amount', 'withdrawDate', 'employeeId', 'reason'],
  'salary_carry_over_logs': ['amount', 'employeeId', 'carriedAt'],
  'blacklist': ['name', 'nationalId', 'reason', 'active'],
  'app_settings': ['key', 'enabled'],
  'app_users': ['username', 'password', 'userType'],
  'sync_state': ['lastSyncTime', 'isSyncing'],
};

async function listCollectionAttributes(collectionId) {
  try {
    // listDocuments مع limit 1 — لو فيه مستند، نقرأ مفاتيحه
    const result = await databases.listDocuments(
      databaseId,
      collectionId,
      [Query.limit(1)]
    );
    if (result.documents.length === 0) {
      // الـ collection فارغ، لا يمكن استنتاج الـ attributes
      return { ok: true, fields: [], empty: true };
    }
    // استخراج المفاتيح من أول مستند (باستثناء الحقول النظامية)
    const doc = result.documents[0];
    const systemFields = new Set(['$id', '$createdAt', '$updatedAt', '$permissions', '$collectionId', '$databaseId']);
    const userFields = Object.keys(doc).filter((k) => !systemFields.has(k));
    return { ok: true, fields: userFields, empty: false };
  } catch (e) {
    return { ok: false, error: `${e.code}: ${e.message}`, fields: [] };
  }
}

async function main() {
  console.log('═══════════════════════════════════════════════════════════════');
  console.log('  فحص الـ attributes في الـ collections');
  console.log('═══════════════════════════════════════════════════════════════\n');

  for (const [collId, required] of Object.entries(requiredFields)) {
    console.log(`📋 ${collId}`);
    const result = await listCollectionAttributes(collId);
    if (!result.ok) {
      console.log(`   ❌ Error: ${result.error}`);
      continue;
    }
    if (result.empty) {
      console.log(`   ⚠️  Collection فارغة — لا يمكن استنتاج الحقول`);
      console.log(`   ℹ️  الحقول المطلوبة: ${required.join(', ')}`);
      continue;
    }
    const existing = new Set(result.fields);
    console.log(`   📦 الحقول الموجودة (${result.fields.length}): ${result.fields.join(', ')}`);
    const missing = required.filter((f) => !existing.has(f));
    if (missing.length === 0) {
      console.log(`   ✅ كل الحقول المطلوبة موجودة`);
    } else {
      console.log(`   ❌ حقول مفقودة: ${missing.join(', ')}`);
    }
    console.log('');
  }
}

main().catch((e) => {
  console.error('Fatal:', e);
  process.exit(1);
});
