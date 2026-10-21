/**
 * setup_messaging.js
 *
 * سكريبت إعداد Appwrite Messaging — فندق مارينا
 *
 * الوظائف:
 * 1. فحص حالة Messaging الحالية
 * 2. إنشاء Topics اللازمة (6 مواضيع)
 * 3. عرض Providers المُفعّلة
 * 4. عرض Targets (الأجهزة المسجّلة)
 * 5. إرسال رسالة اختبار
 * 6. إنشاء Message للحالة الحالية
 *
 * الاستخدام:
 *   export APPWRITE_API_KEY="standard_your_key"
 *   export APPWRITE_PROJECT_ID="6a2b01d0000752ce97e7"
 *   node setup_messaging.js [--check|--topics|--test|--status]
 *
 * الخيارات:
 *   --check    فحص الحالة فقط (default)
 *   --topics   إنشاء/تحديث Topics
 *   --test     إرسال رسالة اختبار
 *   --status   عرض إحصائيات مفصّلة
 */

import { Client, Messaging, Databases, Query } from 'node-appwrite';

// ═══════════════════════════════════════════════════════════════
//  إعدادات
// ═══════════════════════════════════════════════════════════════

const ENDPOINT = process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1';
const PROJECT_ID = process.env.APPWRITE_PROJECT_ID || '6a2b01d0000752ce97e7';
const API_KEY = process.env.APPWRITE_API_KEY || '';
const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || '6a2b030d000445596163';
const DEVICES_COLLECTION = process.env.APPWRITE_DEVICES_COLLECTION || 'devices';

if (!API_KEY) {
  console.error('❌ APPWRITE_API_KEY not set');
  console.error('   export APPWRITE_API_KEY="standard_your_key"');
  process.exit(1);
}

if (!API_KEY.startsWith('standard_')) {
  console.warn('⚠️  API key should start with "standard_" prefix');
}

const client = new Client()
  .setEndpoint(ENDPOINT)
  .setProject(PROJECT_ID)
  .setKey(API_KEY);

const messaging = new Messaging(client);
const databases = new Databases(client);

// الأوامر من CLI args
const args = process.argv.slice(2);
const cmd = args[0] || '--check';

// ═══════════════════════════════════════════════════════════════
//  Topics المطلوبة
// ═══════════════════════════════════════════════════════════════

const REQUIRED_TOPICS = [
  {
    topicId: 'bookings_updates',
    name: 'تحديثات الحجوزات',
    subscribe: ['users'],
  },
  {
    topicId: 'payments_updates',
    name: 'تحديثات الدفعات',
    subscribe: ['users'],
  },
  {
    topicId: 'expenses_updates',
    name: 'تحديثات المصروفات',
    subscribe: ['users'],
  },
  {
    topicId: 'rooms_updates',
    name: 'تحديثات الغرف',
    subscribe: ['users'],
  },
  {
    topicId: 'staff_alerts',
    name: 'تنبيهات الموظفين',
    subscribe: ['users'],
  },
  {
    topicId: 'sync_events',
    name: 'أحداث المزامنة',
    subscribe: ['users'],
  },
];

// ═══════════════════════════════════════════════════════════════
//  1. فحص الحالة
// ═══════════════════════════════════════════════════════════════

async function checkStatus() {
  console.log('\n📋 ═════════════════════════════════════════════');
  console.log('   فحص حالة Appwrite Messaging');
  console.log('═════════════════════════════════════════════\n');

  // 1. Providers
  console.log('🔹 1) Providers:');
  try {
    const providers = await messaging.listProviders();
    if (providers.providers.length === 0) {
      console.log('   ⚠️  لا يوجد Providers مُفعّلة');
      console.log('   👉 اذهب إلى Console → Messaging → Providers');
    } else {
      for (const p of providers.providers) {
        const status = p.enabled ? '✅ Active' : '❌ Disabled';
        console.log(`   ${status}  ${p._id} (${p.type || p.name})`);
      }
    }
  } catch (e) {
    console.log(`   ❌ خطأ في قراءة Providers: ${e.message}`);
    if (e.message.includes('missing scope')) {
      console.log('   👉 تحتاج صلاحية messaging.read في API key');
    }
  }

  // 2. Topics
  console.log('\n🔹 2) Topics:');
  try {
    const topics = await messaging.listTopics();
    if (topics.topics.length === 0) {
      console.log('   ⚠️  لا يوجد Topics');
    } else {
      console.log(`   ${topics.topics.length} Topics:`);
      for (const t of topics.topics) {
        console.log(`   - ${t._id}: ${t.name || '(بدون اسم)'} — ${t.subscribersCount || 0} مشترك`);
      }
    }
  } catch (e) {
    console.log(`   ❌ خطأ: ${e.message}`);
  }

  // 3. Messages (آخر 5)
  console.log('\n🔹 3) آخر الرسائل:');
  try {
    const msgs = await messaging.listMessages(undefined, 5);
    if (msgs.messages.length === 0) {
      console.log('   ℹ️  لا توجد رسائل مُرسلة بعد');
    } else {
      for (const m of msgs.messages) {
        const date = new Date(m.$createdAt).toLocaleString('ar-EG');
        console.log(`   - [${date}] ${m.title || '(بدون عنوان)'} — ${m.deliveryErrorsCount || 0} أخطاء`);
      }
    }
  } catch (e) {
    console.log(`   ❌ خطأ: ${e.message}`);
  }

  // 4. Devices في collection
  console.log('\n🔹 4) الأجهزة المسجّلة (devices collection):');
  try {
    let total = 0;
    let active = 0;
    let withFcm = 0;
    let offset = 0;
    const limit = 100;

    while (true) {
      const resp = await databases.listDocuments(
        DATABASE_ID,
        DEVICES_COLLECTION,
        [Query.limit(limit), Query.offset(offset)]
      );
      for (const d of resp.documents) {
        total++;
        if (d.status === 'active') active++;
        if (d.fcmToken && d.fcmToken.length > 10) withFcm++;
      }
      if (resp.documents.length < limit) break;
      offset += limit;
    }

    console.log(`   📱 الإجمالي: ${total}`);
    console.log(`   ✅ النشطة: ${active}`);
    console.log(`   🔑 مع FCM token: ${withFcm}`);
    if (withFcm === 0) {
      console.log('   ⚠️  لا يوجد أجهزة بـ FCM token — التطبيق لم يسجّل أي جهاز بعد');
    }
  } catch (e) {
    console.log(`   ❌ خطأ: ${e.message}`);
  }

  console.log('\n═════════════════════════════════════════════\n');
}

// ═══════════════════════════════════════════════════════════════
//  2. إنشاء/تحديث Topics
// ═══════════════════════════════════════════════════════════════

async function setupTopics() {
  console.log('\n🏷️  ═════════════════════════════════════════════');
  console.log('   إنشاء/تحديث Topics');
  console.log('═════════════════════════════════════════════\n');

  let created = 0;
  let updated = 0;
  let failed = 0;

  for (const t of REQUIRED_TOPICS) {
    try {
      // جرّب إنشاء
      try {
        await messaging.createTopic(
          t.topicId,
          t.name,
          t.subscribe
        );
        console.log(`✅ Created: ${t.topicId} — ${t.name}`);
        created++;
      } catch (e) {
        // إذا موجود، حدّثه
        if (e.message.includes('already exists') || e.code === 409) {
          await messaging.updateTopic(
            t.topicId,
            t.name,
            t.subscribe
          );
          console.log(`🔄 Updated: ${t.topicId} — ${t.name}`);
          updated++;
        } else {
          throw e;
        }
      }
    } catch (e) {
      console.log(`❌ Failed: ${t.topicId} — ${e.message}`);
      failed++;
    }
  }

  console.log(`\n📊 النتائج: ${created} جديد، ${updated} مُحدّث، ${failed} فشل\n`);
}

// ═══════════════════════════════════════════════════════════════
//  3. إرسال رسالة اختبار
// ═══════════════════════════════════════════════════════════════

async function sendTestMessage() {
  console.log('\n📨 ═════════════════════════════════════════════');
  console.log('   إرسال رسالة اختبار');
  console.log('═════════════════════════════════════════════\n');

  // قراءة كل FCM tokens من devices collection
  const tokens = [];
  try {
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
  } catch (e) {
    console.log(`❌ فشل قراءة الأجهزة: ${e.message}`);
    return;
  }

  if (tokens.length === 0) {
    console.log('⚠️  لا توجد أجهزة نشطة بـ FCM token');
    console.log('   شغّل التطبيق على الأقل مرة واحدة ليسجّل الجهاز');
    return;
  }

  console.log(`📱 عدد المستلمين: ${tokens.length}`);

  // إرسال
  const title = 'اختبار Appwrite Messaging';
  const body = `رسالة تجريبية — ${new Date().toLocaleString('ar-EG')}`;

  try {
    // جرّب Providers المتاحة أولاً
    const providers = await messaging.listProviders();
    const fcmProvider = providers.providers.find(p => p.enabled && (p.type === 'fcm' || p._id.toLowerCase().includes('fcm')));

    if (!fcmProvider) {
      console.log('❌ لا يوجد FCM Provider مُفعّل');
      console.log('   👉 اذهب إلى Console → Messaging → Providers → Enable FCM');
      return;
    }

    console.log(`📤 باستخدام Provider: ${fcmProvider._id}`);

    const message = await messaging.createPush(
      undefined, // messageId (auto)
      title,
      body,
      [{ targetId: tokens[0] }], // targets — نبدأ بأول جهاز للاختبار
      [], // topics
      [], // users
      [], // targets (هنا نستخدم data)
      undefined, // scheduledAt
      true, // draft
      fcmProvider._id
    );

    console.log(`✅ Message created: ${message.$id}`);
    console.log(`   العنوان: ${title}`);
    console.log(`   النص: ${body}`);
    console.log(`   👉 فعّل الإرسال من Console → Messaging → Messages → ${message.$id}`);

  } catch (e) {
    console.log(`❌ فشل الإرسال: ${e.message}`);
    if (e.message.includes('missing scope')) {
      console.log('   👉 تحتاج صلاحية messaging.write في API key');
    }
  }

  console.log('\n═════════════════════════════════════════════\n');
}

// ═══════════════════════════════════════════════════════════════
//  4. إحصائيات مفصّلة
// ═══════════════════════════════════════════════════════════════

async function detailedStatus() {
  console.log('\n📊 ═════════════════════════════════════════════');
  console.log('   إحصائيات مفصّلة');
  console.log('═════════════════════════════════════════════\n');

  // 1. جميع Providers مع تفاصيل
  console.log('🔹 Providers:');
  try {
    const providers = await messaging.listProviders();
    for (const p of providers.providers) {
      console.log(`\n   _id: ${p._id}`);
      console.log(`   type: ${p.type || 'n/a'}`);
      console.log(`   name: ${p.name || 'n/a'}`);
      console.log(`   enabled: ${p.enabled}`);
    }
  } catch (e) {
    console.log(`   ❌ ${e.message}`);
  }

  // 2. آخر 20 رسالة
  console.log('\n\n🔹 آخر 20 رسالة:');
  try {
    const msgs = await messaging.listMessages(undefined, 20);
    if (msgs.messages.length === 0) {
      console.log('   ℹ️  لا توجد رسائل');
    } else {
      for (const m of msgs.messages) {
        const date = new Date(m.$createdAt).toLocaleString('ar-EG');
        const errors = m.deliveryErrorsCount || 0;
        const status = errors > 0 ? '⚠️ ' : '✅';
        console.log(`   ${status} [${date}] ${m.title || '(no title)'} (${m.targetTotal || 0} targets, ${errors} errors)`);
      }
    }
  } catch (e) {
    console.log(`   ❌ ${e.message}`);
  }

  // 3. كل Topics
  console.log('\n\n🔹 جميع Topics:');
  try {
    const topics = await messaging.listTopics();
    if (topics.topics.length === 0) {
      console.log('   ℹ️  لا توجد Topics — شغّل: node setup_messaging.js --topics');
    } else {
      for (const t of topics.topics) {
        console.log(`   - ${t._id}: ${t.name || '(no name)'} — ${t.subscribersCount || 0} subscribers`);
      }
    }
  } catch (e) {
    console.log(`   ❌ ${e.message}`);
  }

  console.log('\n═════════════════════════════════════════════\n');
}

// ═══════════════════════════════════════════════════════════════
//  التنفيذ
// ═══════════════════════════════════════════════════════════════

async function main() {
  console.log(`🔗 Connected to: ${ENDPOINT}`);
  console.log(`📋 Project: ${PROJECT_ID}`);
  console.log(`🗄️  Database: ${DATABASE_ID}\n`);

  try {
    switch (cmd) {
      case '--check':
        await checkStatus();
        break;
      case '--topics':
        await setupTopics();
        break;
      case '--test':
        await sendTestMessage();
        break;
      case '--status':
        await detailedStatus();
        break;
      default:
        console.log(`❌ Unknown command: ${cmd}`);
        console.log('Usage: node setup_messaging.js [--check|--topics|--test|--status]');
        process.exit(1);
    }
  } catch (e) {
    console.error(`\n❌ Fatal error: ${e.message}`);
    if (e.stack) console.error(e.stack);
    process.exit(1);
  }
}

main();
