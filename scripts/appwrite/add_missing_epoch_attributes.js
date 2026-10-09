#!/usr/bin/env node
/**
 * إضافة attributes مفقودة في collection guest_infos على Appwrite Cloud.
 *
 * المشكلة: guestInfoToRemote يرسل lastModifiedEpoch و createdAtEpoch، لكن
 * collection guest_infos على Appwrite Cloud لا تحتوي على هذين الحقلين
 * → خطأ "Unknown attribute: lastModifiedEpoch" (400).
 *
 * الحل: إضافة الحقلين كـ integer (nullable).
 *
 * الاستخدام:
 *   APPWRITE_API_KEY=your_key node add_missing_epoch_attributes.js
 */

const { Client, Databases } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = process.env.APPWRITE_API_KEY;
const collectionId = 'guest_infos';

if (!apiKey) {
  console.error('❌ APPWRITE_API_KEY environment variable is required');
  process.exit(1);
}

const client = new Client().setEndpoint(endpoint).setProject(projectId).setKey(apiKey);
const databases = new Databases(client);

const missingAttributes = [
  { key: 'lastModifiedEpoch', type: 'integer', required: false },
  { key: 'createdAtEpoch', type: 'integer', required: false },
];

async function main() {
  console.log('═'.repeat(70));
  console.log('  إضافة attributes مفقودة في guest_infos');
  console.log('═'.repeat(70));
  console.log('  Collection: ' + collectionId);
  console.log('  Attributes to add: ' + missingAttributes.length);
  console.log('═'.repeat(70) + '\n');

  for (const attr of missingAttributes) {
    process.stdout.write('  → ' + attr.key + ' (' + attr.type + ')... ');
    try {
      if (attr.type === 'integer') {
        await databases.createIntegerAttribute(
          databaseId, collectionId, attr.key, attr.required || false
        );
      } else if (attr.type === 'string') {
        await databases.createStringAttribute(
          databaseId, collectionId, attr.key, attr.size || 255, attr.required || false
        );
      }
      console.log('✅ created');
    } catch (e) {
      if (e.code === 409 || (e.message && e.message.includes('already exists'))) {
        console.log('✓ already exists');
      } else {
        console.log('❌ ' + e.message);
      }
    }
    await new Promise(r => setTimeout(r, 500));
  }

  console.log('\n✅ Done! guest_infos الآن تحتوي على lastModifiedEpoch و createdAtEpoch.');
  console.log('📝 أعد محاولة الـ push من التطبيق — يجب أن تنجح الآن.');
}

main().catch(e => { console.error('Fatal:', e.message); process.exit(1); });
