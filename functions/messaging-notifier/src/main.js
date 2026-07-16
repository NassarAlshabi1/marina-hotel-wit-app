/**
 * Marina Hotel — Messaging Notifier Appwrite Function
 *
 * بديل محسّن لـ fcm-notifier: يستخدم Appwrite Messaging API بدلاً
 * من Firebase Admin SDK مباشرة، مما يُوفّر:
 *   - إدارة مركزية للأجهزة (Targets) عبر Appwrite
 *   - سجل تسليم كامل في Messaging → Messages
 *   - واجهة UI لإدارة الإشعارات
 *   - لا حاجة لـ serviceAccount.json في الـ Function
 *
 * متغيرات البيئة المطلوبة (Settings → Variables):
 *   - APPWRITE_API_KEY              : API key مع messaging.write + documents.read
 *   - APPWRITE_DATABASE_ID          : معرف قاعدة البيانات
 *   - APPWRITE_DEVICES_COLLECTION   : اسم collection الأجهزة (افتراضي: devices)
 *   - APPWRITE_MESSAGING_PROVIDER_ID: معرف FCM Provider من Console (يبدأ عادة بـ "fcm")
 *
 * الأحداث المُتابعة (Settings → Events):
 *   - databases.{dbId}.tables.bookings.rows.*.create|update|delete
 *   - databases.{dbId}.tables.payments.rows.*.create|update
 *   - databases.{dbId}.tables.expenses.rows.*.create|update
 *   - databases.{dbId}.tables.debtS.rows.*.create
 *   - databases.{dbId}.tables.rooms.rows.*.update
 */

import { Client, Databases, Messaging, Query } from 'node-appwrite';

// ═══════════════════════════════════════════════════════════════
//  1. تهيئة العملاء
// ═══════════════════════════════════════════════════════════════

const appwriteClient = new Client()
  .setEndpoint(process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1')
  .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID || '')
  .setKey(process.env.APPWRITE_API_KEY || '');

const databases = new Databases(appwriteClient);
const messaging = new Messaging(appwriteClient);

const DATABASE_ID = process.env.APPWRITE_DATABASE_ID || '';
const DEVICES_COLLECTION = process.env.APPWRITE_DEVICES_COLLECTION || 'devices';
const MESSAGING_PROVIDER_ID = process.env.APPWRITE_MESSAGING_PROVIDER_ID || '';

// ═══════════════════════════════════════════════════════════════
//  2. خريطة الجداول → أسماء عربية + Topics
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

// خريطة الجدول → Topic ID (يجب أن يكون موجوداً في Appwrite Messaging)
const TABLE_TO_TOPIC = {
  bookings: 'bookings_updates',
  payments: 'payments_updates',
  expenses: 'expenses_updates',
  rooms: 'rooms_updates',
};

// ═══════════════════════════════════════════════════════════════
//  3. قراءة جميع الأجهزة النشطة
// ═══════════════════════════════════════════════════════════════

/**
 * يجلب كل الأجهزة النشطة من collection "devices"
 * ويرجع list من { targetId, deviceId, fcmToken }
 *
 * targetId هو معرف الجهاز في Appwrite Messaging (نستخدم fcmToken أو localUuid)
 */
async function getActiveDevices(senderDeviceId) {
  if (!DATABASE_ID) {
    console.error('❌ APPWRITE_DATABASE_ID not set');
    return [];
  }

  try {
    const devices = [];
    let offset = 0;
    const limit = 100;

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
        const fcmToken = doc.fcmToken;
        const deviceId = doc.localUuid || doc.$id;

        // استثني جهاز المُرسِل
        if (senderDeviceId && deviceId === senderDeviceId) continue;

        if (fcmToken && fcmToken.length > 10) {
          devices.push({
            targetId: fcmToken, // Appwrite Messaging يستخدم FCM token كـ target
            deviceId,
            fcmToken,
          });
        }
      }

      if (response.documents.length < limit) break;
      offset += limit;
    }

    return devices;
  } catch (e) {
    console.error('❌ Failed to fetch devices:', e.message);
    return [];
  }
}

// ═══════════════════════════════════════════════════════════════
//  4. استخراج معلومات من Appwrite event payload
// ═══════════════════════════════════════════════════════════════

function parseEvent(payload, headers) {
  // Appwrite event triggers تُرسل نوع الحدث في header `x-appwrite-event`
  const headerEvent = headers?.['x-appwrite-event'] || headers?.['X-Appwrite-Event'] || '';

  const event = payload.event || payload.$trigger || payload;
  const eventType = headerEvent || event?.type || payload.type || '';
  const data = event?.data || payload.data || payload;

  // استخراج اسم الجدول
  const tableMatch = eventType.match(/(?:tables|collections)\.([^.]+)\.(?:rows|documents)/);
  const tableId = tableMatch ? tableMatch[1] : '';

  // استخراج نوع العملية
  const opMatch = eventType.match(/\.(?:rows|documents)\.[\w-]+\.(\w+)$/);
  const operation = opMatch ? opMatch[1] : '';

  // استخراج معرف الجهاز المُرسِل
  const senderDeviceId = data.deviceId || data.device_id || data.lastModifiedBy || '';

  return { tableId, operation, senderDeviceId, data, eventType };
}

// ═══════════════════════════════════════════════════════════════
//  5. بناء نص الإشعار
// ═══════════════════════════════════════════════════════════════

function buildNotification(tableId, operation, data) {
  const tableLabel = TABLE_LABELS[tableId] || 'سجل';
  const opLabel = EVENT_LABELS[operation] || operation;

  let title = `${opLabel} ${tableLabel}`;
  let body = '';

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
//  6. إرسال إشعار عبر Appwrite Messaging API
// ═══════════════════════════════════════════════════════════════

/**
 * يُرسل Push notification عبر Messaging API
 *
 * @param {Array<{targetId: string}>} targets - قائمة الأجهزة المستلمة
 * @param {string} title - عنوان الإشعار
 * @param {string} body - نص الإشعار
 * @param {Object} data - بيانات إضافية تُمرر مع الإشعار
 * @param {string} [topicId] - Topic اختياري لإرساله عبر Topic بدلاً من targets
 * @returns {Promise<{success: boolean, messageId?: string, error?: string}>}
 */
async function sendViaMessaging(targets, title, body, data, topicId) {
  if (!MESSAGING_PROVIDER_ID) {
    return {
      success: false,
      error: 'APPWRITE_MESSAGING_PROVIDER_ID not set',
    };
  }

  // إزالة الـ targets المكررة
  const uniqueTargetIds = [...new Set(targets.map((t) => t.targetId))].filter(Boolean);

  if (uniqueTargetIds.length === 0 && !topicId) {
    console.log('ℹ️ No targets and no topic — skipping send');
    return { success: false, error: 'no recipients' };
  }

  // البيانات الإضافية (data payload)
  const dataPayload = {
    type: 'marina_sync',
    tableId: data.tableId || '',
    operation: data.operation || '',
    senderDeviceId: data.senderDeviceId || '',
    title: title,
    body: body,
    timestamp: new Date().toISOString(),
    ...Object.fromEntries(
      Object.entries(data || {}).map(([k, v]) => [k, String(v)])
    ),
  };

  try {
    // إنشاء Push Message عبر Messaging API
    //
    // ملاحظة: createPush signature في node-appwrite v14:
    //   createPush(messageId, title, body, topics, users, targets, data, action, image, icon, sound, url, draft, scheduledAt)
    const message = await messaging.createPush(
      ID.unique(),         // messageId (auto-generated)
      title,               // title
      body,                // body
      topicId ? [topicId] : [],   // topics
      [],                  // users
      uniqueTargetIds,     // targets (FCM tokens)
      dataPayload,         // data
      undefined,           // action
      undefined,           // image
      undefined,           // icon
      'default',           // sound
      undefined,           // url
      false,               // draft = false → إرسال فوري
      undefined            // scheduledAt
    );

    console.log(`✅ Message sent via Messaging API: ${message.$id}`);

    return {
      success: true,
      messageId: message.$id,
      recipientCount: uniqueTargetIds.length,
    };
  } catch (e) {
    console.error('❌ Messaging send failed:', e.message);
    return { success: false, error: e.message };
  }
}

// ═══════════════════════════════════════════════════════════════
//  7. نقطة الدخول الرئيسية
// ═══════════════════════════════════════════════════════════════

export default async function main(context) {
  const { req, res, log, error } = context;
  log('🚀 Messaging Notifier function triggered');

  try {
    // قراءة payload
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

    const { tableId, operation, senderDeviceId, data, eventType } = parseEvent(
      payload,
      req.headers
    );

    log(`📋 Event: ${eventType}`);
    log(`   Table: ${tableId}, Operation: ${operation}`);
    log(`   Sender device: ${senderDeviceId || 'unknown'}`);

    if (!tableId || !operation) {
      log('⚠️ Could not parse table/operation from event — skipping');
      return res.json({ skipped: true, reason: 'unparseable event' });
    }

    // قراءة الأجهزة النشطة (عدا المُرسِل)
    const devices = await getActiveDevices(senderDeviceId);
    log(`📱 Found ${devices.length} recipient devices`);

    if (devices.length === 0) {
      log('ℹ️ No recipients — skipping send');
      return res.json({ skipped: true, reason: 'no recipients' });
    }

    // بناء الإشعار
    const { title, body } = buildNotification(tableId, operation, data);

    // إرسال عبر Messaging API
    const result = await sendViaMessaging(
      devices,
      title,
      body,
      { tableId, operation, senderDeviceId: senderDeviceId || '', ...data },
      null // يمكن تمرير topicId هنا لإرسال عبر topic
    );

    log(`✅ Done: ${result.success ? 'success' : 'failed'}`);

    return res.json({
      success: result.success,
      messageId: result.messageId,
      recipientCount: result.recipientCount || 0,
      error: result.error,
      title,
      body,
    });
  } catch (e) {
    error('❌ Function error: ' + e.message);
    return res.json({ error: e.message }, 500);
  }
}
