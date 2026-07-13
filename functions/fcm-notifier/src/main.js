/**
 * Marina Hotel — FCM Notifier Appwrite Function
 *
 * يُطلق عند أي تغيير في قاعدة البيانات (create/update/delete rows).
 * يقرأ fcmToken لكل الأجهزة النشطة من collection "devices"،
 * يستثني جهاز المُرسِل، ويُرسل إشعار FCM عبر Firebase Admin SDK.
 *
 * متغيرات البيئة المطلوبة (تُعيين في Appwrite Console → Settings → Variables):
 * - APPWRITE_API_KEY          : API key مع صلاحية documents.read
 * - APPWRITE_DATABASE_ID      : معرف قاعدة البيانات
 * - APPWRITE_DEVICES_COLLECTION: اسم collection الأجهزة (افتراضي: devices)
 * - FIREBASE_PROJECT_ID       : من serviceAccount.json
 * - FIREBASE_CLIENT_EMAIL     : من serviceAccount.json
 * - FIREBASE_PRIVATE_KEY      : من serviceAccount.json (مع \n escapes)
 *
 * الأحداث المُتابعة:
 * - databases.*.tables.*.rows.*.create
 * - databases.*.tables.*.rows.*.update
 * - databases.*.tables.*.rows.*.delete
 */

import { Client, Databases, Query } from 'node-appwrite';
import { initializeApp, cert, getApps } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';

// ═══════════════════════════════════════════════════════════════
//  1. تهيئة Appwrite Client
// ═══════════════════════════════════════════════════════════════

const appwriteClient = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_API_KEY || '');

const databases = new Databases(appwriteClient);

const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || '';
const DEVICES_COLLECTION = process.env.APPWRITE_DEVICES_COLLECTION || 'devices';

// ═══════════════════════════════════════════════════════════════
//  2. تهيئة Firebase Admin SDK
// ═══════════════════════════════════════════════════════════════

let messaging;

function initializeFirebase() {
  if (getApps().length > 0) {
    messaging = getMessaging();
    return;
  }

  const serviceAccount = {
    projectId: process.env.FIREBASE_PROJECT_ID,
    clientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    // المفتاح الخاص يحتوي على \n escapes — نُحوّلها لأسطر فعلية
    privateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
  };

  if (!serviceAccount.projectId || !serviceAccount.privateKey) {
    console.error('❌ Firebase env vars not configured. Set FIREBASE_PROJECT_ID, FIREBASE_CLIENT_EMAIL, FIREBASE_PRIVATE_KEY');
    return;
  }

  try {
    initializeApp({
      credential: cert(serviceAccount),
    });
    messaging = getMessaging();
    console.log('✅ Firebase Admin SDK initialized');
  } catch (e) {
    console.error('❌ Firebase init failed:', e.message);
  }
}

// ═══════════════════════════════════════════════════════════════
//  3. خريطة الجداول → أسماء عربية للإشعارات
// ═══════════════════════════════════════════════════════════════

const TABLE_LABELS = {
  bookings: 'حجز',
  payments: 'دفعة',
  expenses: 'مصروف',
  rooms: 'غرفة',
  booking_notes: 'ملاحظة',
  debts: 'دين',
  employees: 'موظف',
  shift_notes: 'ملاحظة وردية',
  cash_transactions: 'معاملة نقدية',
  salary_payments: 'دفعة راتب',
  salary_withdrawals: 'سحب راتب',
};

const EVENT_LABELS = {
  create: 'إضافة',
  update: 'تعديل',
  delete: 'حذف',
};

// ═══════════════════════════════════════════════════════════════
//  4. قراءة جميع FCM tokens من collection devices
// ═══════════════════════════════════════════════════════════════

async function getDeviceTokens(senderDeviceId) {
  if (!DATABASE_ID) {
    console.error('❌ APPWRITE_DATABASE_ID not set');
    return [];
  }

  try {
    const tokens = [];
    let offset = 0;
    const limit = 100;

    // pagination — اجلب كل الأجهزة النشطة
    while (true) {
      const response = await databases.listDocuments(
        DATABASE_ID,
        DEVICES_COLLECTION,
        [
          Query.equal('status', 'active'),
          Query.limit(limit),
          Query.offset(offset),
        ]
      );

      for (const doc of response.documents) {
        const token = doc.fcmToken;
        const deviceUuid = doc.localUuid || doc.$id;

        // استثني جهاز المُرسِل
        if (senderDeviceId && deviceUuid === senderDeviceId) continue;

        if (token && token.length > 10) {
          tokens.push({ token, deviceId: deviceUuid });
        }
      }

      if (response.documents.length < limit) break;
      offset += limit;
    }

    return tokens;
  } catch (e) {
    console.error('❌ Failed to fetch devices:', e.message);
    return [];
  }
}

// ═══════════════════════════════════════════════════════════════
//  5. إرسال FCM متعدد المستلمين
// ═══════════════════════════════════════════════════════════════

async function sendFcmNotification(tokens, title, body, data) {
  if (!messaging) {
    console.error('❌ Firebase messaging not initialized');
    return { success: 0, failure: 0 };
  }

  if (tokens.length === 0) {
    console.log('ℹ️ No tokens to send to');
    return { success: 0, failure: 0 };
  }

  // إزالة الـ tokens الفارغة أو المكررة
  const uniqueTokens = [...new Set(tokens.map((t) => t.token))].filter(Boolean);

  if (uniqueTokens.length === 0) {
    console.log('ℹ️ No valid tokens after dedup');
    return { success: 0, failure: 0 };
  }

  const message = {
    notification: {
      title: title,
      body: body,
    },
    data: {
      type: 'marina_sync',
      ...Object.fromEntries(
        Object.entries(data || {}).map(([k, v]) => [k, String(v)])
      ),
    },
    tokens: uniqueTokens,
    android: {
      priority: 'high',
      notification: {
        sound: 'default',
        clickAction: 'FLUTTER_NOTIFICATION_CLICK',
      },
    },
    apns: {
      payload: {
        aps: {
          sound: 'default',
          contentAvailable: true,
        },
      },
    },
  };

  try {
    const response = await messaging.sendEachForMulticast(message);
    console.log(`✅ FCM sent: ${response.successCount} success, ${response.failureCount} failure`);

    // سجّل الـ tokens الفاشلة (لإزالتها لاحقاً)
    if (response.failureCount > 0) {
      const failedTokens = [];
      response.responses.forEach((resp, idx) => {
        if (!resp.success) {
          failedTokens.push({
            token: uniqueTokens[idx],
            error: resp.error?.message,
          });
        }
      });
      console.log('⚠️ Failed tokens:', JSON.stringify(failedTokens.slice(0, 5)));
    }

    return { success: response.successCount, failure: response.failureCount };
  } catch (e) {
    console.error('❌ FCM send failed:', e.message);
    return { success: 0, failure: uniqueTokens.length };
  }
}

// ═══════════════════════════════════════════════════════════════
//  6. استخراج معلومات من Appwrite event payload
// ═══════════════════════════════════════════════════════════════

function parseEvent(payload, headers) {
  // ✅ Appwrite event triggers تُرسل نوع الحدث في header `x-appwrite-event`
  // مثال: "databases.6a2b030d000445596163.tables.bookings.rows.create"
  const headerEvent = headers?.['x-appwrite-event'] || headers?.['X-Appwrite-Event'] || '';

  // للمقارنة: اختبار HTTP اليدوي يضع نوع الحدث في payload.event.type
  const event = payload.event || payload.$trigger || payload;
  const eventType = headerEvent || event?.type || payload.type || '';
  const data = event?.data || payload.data || payload;

  // استخراج اسم الجدول من event type
  // مثال: databases.6a2b.tables.6a2b030d000445596163.rows.bookings.rows.create
  // أو: databases.6a2b030d000445596163.tables.bookings.rows.create
  const tableMatch = eventType.match(/tables\.([^.]+)\.rows/);
  const tableId = tableMatch ? tableMatch[1] : '';

  // استخراج نوع العملية (create/update/delete)
  const opMatch = eventType.match(/\.rows\.\w+\.(\w+)$/);
  const operation = opMatch ? opMatch[1] : '';

  // استخراج معرف الجهاز المُرسِل
  const senderDeviceId = data.deviceId || data.device_id || data.lastModifiedBy || '';

  return {
    tableId,
    operation,
    senderDeviceId,
    data,
    eventType,
  };
}

// ═══════════════════════════════════════════════════════════════
//  7. بناء نص الإشعار
// ═══════════════════════════════════════════════════════════════

function buildNotification(tableId, operation, data) {
  const tableLabel = TABLE_LABELS[tableId] || 'سجل';
  const opLabel = EVENT_LABELS[operation] || operation;

  let title = `${opLabel} ${tableLabel}`;
  let body = '';

  // بناء نص مخصص حسب نوع الجدول
  switch (tableId) {
    case 'bookings':
      if (operation === 'create') {
        title = 'حجز جديد';
        body = `غرفة ${data.roomNumber || '?'} — ${data.guestName || ''}`;
      } else if (operation === 'update') {
        title = 'تعديل حجز';
        body = `غرفة ${data.roomNumber || '?'} — ${data.guestName || ''}`;
      } else if (operation === 'delete') {
        title = 'حذف حجز';
        body = `غرفة ${data.roomNumber || '?'}`;
      }
      break;

    case 'payments':
      if (operation === 'create') {
        title = 'دفعة جديدة';
        body = `${data.amount || 0} — غرفة ${data.roomNumber || '?'}`;
      }
      break;

    case 'expenses':
      if (operation === 'create') {
        title = 'مصروف جديد';
        body = `${data.expenseType || ''} — ${data.amount || 0}`;
      }
      break;

    case 'debts':
      if (operation === 'create') {
        title = 'دين جديد';
        body = `${data.guestName || ''} — ${data.totalAmount || 0}`;
      }
      break;

    default:
      body = `${opLabel} في ${tableLabel}`;
  }

  return { title, body };
}

// ═══════════════════════════════════════════════════════════════
//  8. نقطة الدخول الرئيسية
// ═══════════════════════════════════════════════════════════════

export default async function main(context) {
  const { req, res, log, error } = context;
  log('🚀 FCM Notifier function triggered');

  // تهيئة Firebase
  initializeFirebase();
  if (!messaging) {
    log('❌ Firebase messaging not initialized');
    return res.json({ error: 'Firebase not initialized' }, 500);
  }

  try {
    // قراءة payload من req.bodyJson (Appwrite v2 OpenRuntimes)
    let payload = {};
    try {
      if (typeof req.bodyJson === 'string') {
        payload = JSON.parse(req.bodyJson);
      } else if (req.bodyJson) {
        payload = req.bodyJson;
      } else if (req.body) {
        payload = typeof req.body === 'string' ? JSON.parse(req.body) : req.body;
      }
    } catch (e) {
      log('⚠️ Could not parse body as JSON: ' + e.message);
    }

    log('📥 Event payload keys: ' + Object.keys(payload));

    const { tableId, operation, senderDeviceId, data, eventType } = parseEvent(payload, req.headers);

    log(`📋 Event: ${eventType}`);
    log(`   Table: ${tableId}, Operation: ${operation}`);
    log(`   Sender device: ${senderDeviceId || 'unknown'}`);

    if (!tableId || !operation) {
      log('⚠️ Could not parse table/operation from event — skipping');
      return res.json({ skipped: true, reason: 'unparseable event' });
    }

    // قراءة FCM tokens لكل الأجهزة (عدا المُرسِل)
    const tokens = await getDeviceTokens(senderDeviceId);
    log(`📱 Found ${tokens.length} recipient devices`);

    if (tokens.length === 0) {
      log('ℹ️ No recipients — skipping send');
      return res.json({ skipped: true, reason: 'no recipients' });
    }

    // بناء الإشعار
    const { title, body } = buildNotification(tableId, operation, data);

    // إرسال FCM
    const result = await sendFcmNotification(tokens, title, body, {
      tableId,
      operation,
      senderDeviceId: senderDeviceId || '',
    });

    log(`✅ Done: ${result.success} sent, ${result.failure} failed`);

    return res.json({
      success: true,
      recipients: tokens.length,
      sent: result.success,
      failed: result.failure,
      title,
      body,
    });
  } catch (e) {
    error('❌ Function error: ' + e.message);
    return res.json({ error: e.message }, 500);
  }
}
