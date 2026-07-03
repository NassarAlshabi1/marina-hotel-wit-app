#!/usr/bin/env node
/**
 * يفحص أبعاد الـ string attributes في مجموعة app_settings على Appwrite Cloud.
 * يستخدم API key للوصول إلى قائمة الـ attributes.
 *
 * الاستخدام: node check_app_settings_schema.js
 */

const { Client, Databases } = require('node-appwrite');

const endpoint = 'https://fra.cloud.appwrite.io/v1';
const projectId = '6a2b01d0000752ce97e7';
const databaseId = '6a2b030d000445596163';
const apiKey = 'standard_721adc4e95401dab9274bc2a7596ce0a61bfcdf7bbe37e7c64d52fb2113414e27c8d3e8f1977ebaafcf8ae63e7f3c873aad38c2a07e3ab93229cd7cd745a3ad2f6b9ec3fc407e8abfae2be3e5be00315f4d4a74cc07bc5ba5b0eda13e4569c8ee8ce2532a7bd43d827c7b83a84495974b9995d12f031e2bead685cebbe31aa3d';

const client = new Client()
  .setEndpoint(endpoint)
  .setProject(projectId)
  .setKey(apiKey);

const databases = new Databases(client);

async function main() {
  const collectionId = 'app_settings';
  console.log(`\n📦 Collection: ${collectionId}\n`);
  console.log('─'.repeat(80));

  try {
    // جلب قائمة الـ attributes عبر REST endpoint مباشرة
    // node-appwrite SDK لا يكشف listAttributes مباشرة، نستخدم fetch
    const url = `${endpoint}/databases/${databaseId}/collections/${collectionId}/attributes`;
    const res = await fetch(url, {
      headers: {
        'X-Appwrite-Project': projectId,
        'X-Appwrite-Key': apiKey,
      },
    });
    if (!res.ok) {
      console.error(`❌ HTTP ${res.status}: ${await res.text()}`);
      return;
    }
    const data = await res.json();
    console.log(`Total attributes: ${data.total}\n`);

    // اطبع كل attribute مع حجمه
    console.log('All attributes:');
    console.log('─'.repeat(80));
    console.log(
      'key'.padEnd(40) +
      'type'.padEnd(15) +
      'size'.padEnd(8) +
      'required'
    );
    console.log('─'.repeat(80));
    for (const a of data.attributes) {
      const size = a.size ?? a.length ?? '-';
      const formatType = a.format ?? a.type ?? '-';
      console.log(
        a.key.padEnd(40) +
        String(formatType).padEnd(15) +
        String(size).padEnd(8) +
        (a.required ? 'yes' : 'no')
      );
    }

    console.log('\n\n⚠️  Encrypted fields to check: telegram_bot_token, lark_app_secret, wa_api_token');
    console.log('   If size < 200, encrypted values (which are long ciphertexts) will be corrupted by truncation.');

  } catch (e) {
    console.error('❌ Error:', e.message);
  }
}

main();
