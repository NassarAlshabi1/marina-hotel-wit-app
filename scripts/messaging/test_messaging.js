/**
 * test_messaging.js
 *
 * سكريبت اختبار شامل لـ Appwrite Messaging
 *
 * الوظائف:
 * 1. التحقق من الإعدادات (API key, project ID, etc.)
 * 2. فحص Providers
 * 3. قراءة كل الأجهزة من collection "devices"
 * 4. محاولة تسجيل جهاز تجريبي كـ Target
 * 5. إرسال إشعار فعلي للأجهزة
 * 6. التحقق من حالة التسليم
 * 7. تقرير شامل بنتائج الاختبار
 *
 * الاستخدام:
 *   export APPWRITE_API_KEY="standard_your_key"
 *   export APPWRITE_MESSAGING_PROVIDER_ID="fcm"
 *   node test_messaging.js
 */

import { Client, Messaging, Databases, Query } from 'node-appwrite';

// ═══════════════════════════════════════════════════════════════
//  الإعدادات
// ═══════════════════════════════════════════════════════════════

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = process.env.APPWRITE_PROJECT_ID || '6a2b01d0000752ce97e7';
const API_KEY = process.env.APPWRITE_API_KEY || '';
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || '6a2b030d000445596163';
const DEVICES_COLLECTION = process.env.APPWRITE_DEVICES_COLLECTION || 'devices';
const PROVIDER_ID = process.env.APPWRITE_MESSAGING_PROVIDER_ID || 'fcm';

// ═══════════════════════════════════════════════════════════════
//  نتائج الاختبار
// ═══════════════════════════════════════════════════════════════

const results = {
  config: { ok: false, msg: '' },
  provider: { ok: false, msg: '', data: null },
  devices: { ok: false, msg: '', count: 0, items: [] },
  targetCreation: { ok: false, msg: '' },
  messageSend: { ok: false, msg: '', messageId: '' },
  deliveryStatus: { ok: false, msg: '' },
};

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const messaging = new Messaging(client);
const databases = new Databases(client);

// ═══════════════════════════════════════════════════════════════
//  1. فحص الإعدادات
// ═══════════════════════════════════════════════════════════════

function checkConfig() {
  console.log('\n🔹 1) فحص الإعدادات...');

  const issues = [];
  if (!API_KEY) issues.push('APPWRITE_API_KEY not set');
  if (!PROJECT_ID) issues.push('APPWRITE_PROJECT_ID not set');
  if (!DATABASE_ID) issues.push('APPWRITE_DATABASE_ID not set');
  if (!PROVIDER_ID) issues.push('APPWRITE_MESSAGING_PROVIDER_ID not set');

  if (!API_KEY.startsWith('standard_')) {
    issues.push('API_KEY should start with "standard_"');
  }

  if (issues.length === 0) {
    results.config.ok = true;
    results.config.msg = 'الإعدادات صحيحة';
    console.log('   ✅ جميع الإعدادات صحيحة');
    console.log(`   Endpoint: ${ENDPOINT}`);
    console.log(`   Project: ${PROJECT_ID}`);
    console.log(`   Database: ${DATABASE_ID}`);
    console.log(`   Provider ID: ${PROVIDER_ID}`);
  } else {
    results.config.msg = issues.join('; ');
    console.log('   ❌ مشاكل:');
    issues.forEach((i) => console.log(`      - ${i}`));
  }
}

// ═══════════════════════════════════════════════════════════════
//  2. فحص Providers
// ═══════════════════════════════════════════════════════════════

async function checkProviders() {
  console.log('\n🔹 2) فحص Messaging Providers...');

  try {
    const providers = await messaging.listProviders();

    if (providers.providers.length === 0) {
      results.provider.msg = 'لا يوجد Providers مُفعّلة';
      console.log('   ❌ لا يوجد Providers');
      console.log('   👉 اذهب إلى Console → Messaging → Providers → Enable FCM');
      return;
    }

    console.log(`   📋 وُجد ${providers.providers.length} Provider(s):`);
    for (const p of providers.providers) {
      const status = p.enabled ? '✅ Active' : '❌ Disabled';
      console.log(`      ${status} ${p._id} (type: ${p.type || 'n/a'})`);

      if (p.enabled && (p._id === PROVIDER_ID || p.type === 'fcm')) {
        results.provider.ok = true;
        results.provider.data = p;
      }
    }

    if (results.provider.ok) {
      results.provider.msg = `FCM Provider مُفعّل: ${results.provider.data._id}`;
      console.log(`   ✅ Provider "${results.provider.data._id}" مُفعّل وجاهز`);
    } else {
      results.provider.msg = `Provider ${PROVIDER_ID} غير مُفعّل`;
      console.log(`   ⚠️  Provider "${PROVIDER_ID}" غير موجود أو غير مُفعّل`);
    }
  } catch (e) {
    results.provider.msg = e.message;
    console.log(`   ❌ خطأ: ${e.message}`);
    if (e.message.includes('missing scope')) {
      console.log('   👉 تحتاج صلاحية messaging.read في API key');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  3. قراءة الأجهزة من collection
// ═══════════════════════════════════════════════════════════════

async function checkDevices() {
  console.log('\n🔹 3) قراءة الأجهزة من collection "devices"...');

  try {
    const devices = [];
    let offset = 0;
    const limit = 100;

    while (true) {
      const resp = await databases.listDocuments(
        DATABASE_ID,
        DEVICES_COLLECTION,
        [Query.limit(limit), Query.offset(offset)]
      );
      for (const d of resp.documents) {
        devices.push({
          $id: d.$id,
          localUuid: d.localUuid,
          status: d.status,
          fcmToken: d.fcmToken ? `${d.fcmToken.substring(0, 20)}...` : null,
          hasFcmToken: !!(d.fcmToken && d.fcmToken.length > 10),
        });
      }
      if (resp.documents.length < limit) break;
      offset += limit;
    }

    results.devices.count = devices.length;
    results.devices.items = devices;

    const active = devices.filter((d) => d.status === 'active');
    const withFcm = devices.filter((d) => d.hasFcmToken);

    console.log(`   📱 إجمالي الأجهزة: ${devices.length}`);
    console.log(`   ✅ نشطة: ${active.length}`);
    console.log(`   🔑 مع FCM token: ${withFcm.length}`);

    if (devices.length > 0) {
      console.log('\n   التفاصيل:');
      devices.slice(0, 5).forEach((d, i) => {
        console.log(`      ${i + 1}. ${d.localUuid || d.$id}`);
        console.log(`         status: ${d.status}, fcmToken: ${d.hasFcmToken ? '✅' : '❌'}`);
      });
      if (devices.length > 5) {
        console.log(`      ... و ${devices.length - 5} جهاز آخر`);
      }
    }

    if (devices.length === 0) {
      results.devices.msg = 'لا توجد أجهزة مسجّلة';
      console.log('   ⚠️  لا توجد أجهزة — شغّل التطبيق على الأقل مرة ليسجّل جهاز');
    } else if (withFcm.length === 0) {
      results.devices.msg = 'لا يوجد أجهزة بـ FCM token';
      console.log('   ⚠️  لا يوجد أجهزة بـ FCM token صالح');
    } else {
      results.devices.ok = true;
      results.devices.msg = `${withFcm.length} جهاز جاهز للاستقبال`;
    }
  } catch (e) {
    results.devices.msg = e.message;
    console.log(`   ❌ خطأ: ${e.message}`);
  }
}

// ═══════════════════════════════════════════════════════════════
//  4. إنشاء Target تجريبي
// ═══════════════════════════════════════════════════════════════

async function testTargetCreation() {
  console.log('\n🔹 4) اختبار إنشاء Target...');

  // نأخذ أول FCM token حقيقي
  const realDevice = results.devices.items.find((d) => d.hasFcmToken);
  if (!realDevice) {
    results.targetCreation.msg = 'لا يوجد FCM token للاختبار';
    console.log('   ⚠️  تخطّي — لا يوجد FCM token');
    return;
  }

  try {
    // قراءة التوكن الكامل
    const doc = await databases.getDocument(
      DATABASE_ID,
      DEVICES_COLLECTION,
      realDevice.$id
    );
    const fullToken = doc.fcmToken;

    const testTargetId = `test_${Date.now()}`;

    try {
      // محاولة إنشاء target
      await messaging.createTarget(
        testTargetId,
        PROVIDER_ID,
        fullToken
      );
      console.log(`   ✅ Target created: ${testTargetId}`);
      results.targetCreation.ok = true;
      results.targetCreation.msg = `Target ${testTargetId} created successfully`;

      // نظافة: احذف الـ Target التجريبي
      try {
        await messaging.deleteTarget(testTargetId);
        console.log(`   🧹 Test target cleaned up`);
      } catch (e) {
        console.log(`   ⚠️  Could not clean up test target: ${e.message}`);
      }
    } catch (e) {
      if (e.message.includes('already exists') || e.code === 409) {
        console.log(`   ✅ Target already exists (expected for repeated tests)`);
        results.targetCreation.ok = true;
      } else {
        throw e;
      }
    }
  } catch (e) {
    results.targetCreation.msg = e.message;
    console.log(`   ❌ خطأ: ${e.message}`);
    if (e.message.includes('missing scope')) {
      console.log('   👉 تحتاج صلاحية messaging.write');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  5. إرسال رسالة اختبار
// ═══════════════════════════════════════════════════════════════

async function testSendMessage() {
  console.log('\n🔹 5) إرسال رسالة اختبار...');

  if (!results.provider.ok) {
    results.messageSend.msg = 'Skipping — no Provider';
    console.log('   ⚠️  تخطّي — لا يوجد Provider مُفعّل');
    return;
  }

  if (!results.devices.ok) {
    results.messageSend.msg = 'Skipping — no recipients';
    console.log('   ⚠️  تخطّي — لا يوجد مستلمين');
    return;
  }

  try {
    // نأخذ التوكنات الكاملة من collection
    const tokens = [];
    let offset = 0;
    const limit = 100;
    while (true) {
      const resp = await databases.listDocuments(
        DATABASE_ID,
        DEVICES_COLLECTION,
        [Query.equal('status', 'active'), Query.limit(limit), Query.offset(offset)]
      );
      for (const d of resp.documents) {
        if (d.fcmToken && d.fcmToken.length > 10) {
          tokens.push(d.fcmToken);
        }
      }
      if (resp.documents.length < limit) break;
      offset += limit;
    }

    if (tokens.length === 0) {
      results.messageSend.msg = 'No valid FCM tokens';
      console.log('   ⚠️  لا توجد توكنات صالحة');
      return;
    }

    const title = '🧪 اختبار Appwrite Messaging';
    const body = `رسالة تجريبية من setup script — ${new Date().toLocaleString('ar-EG')}`;
    const data = {
      type: 'marina_sync',
      test: 'true',
      timestamp: new Date().toISOString(),
    };

    console.log(`   📤 إرسال لـ ${tokens.length} جهاز...`);

    const message = await messaging.createPush(
      undefined, // messageId (auto)
      title,
      body,
      [],          // topics
      [],          // users
      tokens,      // targets
      data,        // data
      undefined, undefined, undefined,
      'default',   // sound
      undefined,
      false,       // draft = false → إرسال فوري
      undefined
    );

    results.messageSend.ok = true;
    results.messageSend.msg = `Message sent: ${message.$id}`;
    results.messageSend.messageId = message.$id;

    console.log(`   ✅ Message created & sent: ${message.$id}`);
    console.log(`   📋 العنوان: ${title}`);
    console.log(`   📋 النص: ${body}`);

    // انتظر قليلاً ثم تحقق من حالة التسليم
    console.log('\n   ⏳ انتظار 5 ثوانٍ للتسليم...');
    await new Promise((r) => setTimeout(r, 5000));

    await checkDeliveryStatus(message.$id);
  } catch (e) {
    results.messageSend.msg = e.message;
    console.log(`   ❌ خطأ في الإرسال: ${e.message}`);
    if (e.message.includes('missing scope')) {
      console.log('   👉 تحتاج صلاحية messaging.write');
    }
  }
}

// ═══════════════════════════════════════════════════════════════
//  6. فحص حالة التسليم
// ═══════════════════════════════════════════════════════════════

async function checkDeliveryStatus(messageId) {
  console.log('\n🔹 6) فحص حالة التسليم...');

  try {
    const msg = await messaging.getMessage(messageId);

    console.log(`   📊 Message ID: ${msg.$id}`);
    console.log(`   📊 Target Total: ${msg.targetTotal || 0}`);
    console.log(`   📊 Delivered: ${msg.deliveredTotal || 0}`);
    console.log(`   📊 Delivery Errors: ${msg.deliveryErrorsCount || 0}`);

    const delivered = msg.deliveredTotal || 0;
    const errors = msg.deliveryErrorsCount || 0;
    const total = msg.targetTotal || 0;

    if (delivered > 0) {
      results.deliveryStatus.ok = true;
      results.deliveryStatus.msg = `${delivered}/${total} delivered`;
      console.log(`   ✅ نجح التسليم لـ ${delivered} جهاز`);
    } else if (errors > 0) {
      results.deliveryStatus.msg = `${errors} errors`;
      console.log(`   ⚠️  ${errors} خطأ في التسليم`);
      console.log('   👉 تحقق من Logs في Console → Messaging → Messages');
    } else {
      results.deliveryStatus.msg = 'No delivery info yet';
      console.log('   ⏳ التسليم قيد المعالجة — تحقق لاحقاً في Console');
    }
  } catch (e) {
    results.deliveryStatus.msg = e.message;
    console.log(`   ❌ خطأ: ${e.message}`);
  }
}

// ═══════════════════════════════════════════════════════════════
//  7. التقرير النهائي
// ═══════════════════════════════════════════════════════════════

function printReport() {
  console.log('\n');
  console.log('═════════════════════════════════════════════');
  console.log('          📋 تقرير الاختبار النهائي');
  console.log('═════════════════════════════════════════════\n');

  const checks = [
    ['الإعدادات', results.config],
    ['Providers', results.provider],
    ['الأجهزة', results.devices],
    ['إنشاء Target', results.targetCreation],
    ['إرسال رسالة', results.messageSend],
    ['حالة التسليم', results.deliveryStatus],
  ];

  let passCount = 0;
  for (const [name, r] of checks) {
    const icon = r.ok ? '✅' : '❌';
    console.log(`${icon} ${name}: ${r.msg || (r.ok ? 'OK' : 'FAIL')}`);
    if (r.ok) passCount++;
  }

  console.log('\n═════════════════════════════════════════════');
  console.log(`   النتيجة: ${passCount}/${checks.length} فحوصات نجحت\n`);

  if (passCount === checks.length) {
    console.log('🎉 ممتاز! Appwrite Messaging يعمل بشكل صحيح.');
    console.log('   الخطوات التالية:');
    console.log('   1. انشر messaging-notifier Function');
    console.log('   2. اربط Events (bookings, payments, etc.)');
    console.log('   3. اختبر بإنشاء حجز جديد من التطبيق');
  } else {
    console.log('⚠️  يوجد مشاكل تحتاج إصلاح:');
    console.log('   1. اتبع دليل: docs/APPWRITE_MESSAGING_SETUP.md');
    console.log('   2. تأكد من تفعيل FCM Provider في Console');
    console.log('   3. تأكد من صلاحيات API Key');
    console.log('   4. أعد تشغيل هذا السكريبت للتأكد');
  }
  console.log('\n═════════════════════════════════════════════\n');
}

// ═══════════════════════════════════════════════════════════════
//  التنفيذ
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log('\n🧪 ═════════════════════════════════════════════');
  console.log('   اختبار Appwrite Messaging — فندق مارينا');
  console.log('═════════════════════════════════════════════\n');

  checkConfig();

  await checkProviders();
  await checkDevices();
  await testTargetCreation();
  await testSendMessage();

  printReport();
}

main().catch((e) => {
  console.error(`\n❌ Fatal: ${e.message}`);
  console.error(e.stack);
  process.exit(1);
});
