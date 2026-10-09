/**
 * Appwrite Cloud Function: notify-devices
 * 
 * يُرسل إشعار FCM لجميع الأجهزة الأخرى عند حدوث تغيير في البيانات
 * 
 * المتغيرات المطلوبة:
 * - FCM_SERVER_KEY: مفتاح سيرفر FCM من Firebase Console
 * - DATABASE_ID: معرف قاعدة البيانات
 */

const DATABASE_ID = process.env.DATABASE_ID || 'hotel_db';
const FCM_SERVER_KEY = process.env.FCM_SERVER_KEY;
const FCM_URL = 'https://fcm.googleapis.com/fcm/send';

// المجموعات التي نراقبها (محددة في appwrite.json)
const WATCHED_COLLECTIONS = [
  'rooms', 'bookings', 'payments', 'expenses', 'employees',
  'shift_notes', 'debts', 'guest_infos'
];

// حقول المزامنة التي تحدد الجهاز المُرسل
const DEVICE_ID_FIELDS = ['deviceId', 'device_id', 'device_id_field'];

export default async ({ req, res, log, error }) => {
  try {
    // التحقق من مفتاح FCM
    if (!FCM_SERVER_KEY) {
      error('❌ FCM_SERVER_KEY not configured');
      return res.json({ success: false, error: 'FCM_SERVER_KEY missing' }, 500);
    }

    // استخراج معلومات الحدث
    const payload = req.body;
    const events = payload?.events || [];

    // تحديد نوع العملية
    let operation = 'update';
    if (events.some(e => e.includes('.create'))) operation = 'create';
    else if (events.some(e => e.includes('.delete'))) operation = 'delete';

    // استخراج بيانات المستند
    const document = payload?.payload || {};
    const $id = document.$id;
    const collectionId = payload?.collection || '';
    
    // تجاهل المجموعات غير المراقبة
    if (!WATCHED_COLLECTIONS.includes(collectionId)) {
      log(`ℹ️ Ignoring change in unwatched collection: ${collectionId}`);
      return res.json({ success: true, skipped: true });
    }

    // تحديد معرف الجهاز المُرسل
    const senderDeviceId = 
      document.deviceId || 
      document.device_id || 
      document.lastModifiedBy || 
      null;

    log(`📡 Change detected: ${operation} in ${collectionId}/${$id} from device: ${senderDeviceId || 'unknown'}`);

    // جلب قائمة الأجهزة المسجلة
    const client = new Client()
      .setEndpoint(process.env.APPWRITE_ENDPOINT || 'https://fra.cloud.appwrite.io/v1')
      .setProject(process.env.APPWRITE_PROJECT_ID)
      .setKey(process.env.APPWRITE_API_KEY || '');

    const databases = new Databases(client);
    
    let devices = [];
    try {
      const response = await databases.listDocuments(
        DATABASE_ID,
        'devices',
        [
          Query.equal('status', 'active'),
          Query.limit(100)
        ]
      );
      devices = response.documents || [];
    } catch (e) {
      error(`Failed to fetch devices: ${e.message}`);
      return res.json({ success: false, error: 'Failed to fetch devices' }, 500);
    }

    if (devices.length === 0) {
      log('ℹ️ No active devices found');
      return res.json({ success: true, notified: 0 });
    }

    // تصفية الأجهزة (استبعاد الجهاز المُرسل + الأجهزة بدون FCM token)
    const targetDevices = devices.filter(device => {
      const fcmToken = document.fcmToken || '';
      const deviceId = document.localUuid || document.$id;
      
      // استبعاد الجهاز المُرسل
      if (senderDeviceId && deviceId === senderDeviceId) return false;
      
      // استبعاد الأجهزة بدون توكن FCM
      if (!fcmToken || fcmToken.trim() === '') return false;
      
      return true;
    });

    if (targetDevices.length === 0) {
      log('ℹ️ No target devices to notify');
      return res.json({ success: true, notified: 0 });
    }

    // إرسال FCM لكل جهاز مستهدف
    const results = [];
    for (const device of targetDevices) {
      const fcmToken = device.fcmToken;
      const deviceId = device.localUuid || device.$id;

      try {
        const fcmResult = await sendFCM(fcmToken, {
          type: 'marina_sync',
          source: 'appwrite_function',
          operation: operation,
          collection: collectionId,
          documentId: $id,
          senderDeviceId: senderDeviceId,
          timestamp: new Date().toISOString(),
        });

        results.push({
          deviceId,
          success: fcmResult.success,
          messageId: fcmResult.messageId,
        });

        log(`✅ Notification sent to device: ${deviceId}`);
      } catch (e) {
        error(`Failed to send to ${deviceId}: ${e.message}`);
        results.push({
          deviceId,
          success: false,
          error: e.message,
        });
      }
    }

    const successCount = results.filter(r => r.success).length;
    log(`✅ Notified ${successCount}/${targetDevices.length} devices`);

    return res.json({
      success: true,
      notified: successCount,
      total: targetDevices.length,
      operation,
      collection: collectionId,
      results,
    });

  } catch (e) {
    error(`Function error: ${e.message}`);
    return res.json({ success: false, error: e.message }, 500);
  }
};

/**
 * إرسال رسالة FCM
 */
async function sendFCM(token, data) {
  const response = await fetch(FCM_URL, {
    method: 'POST',
    headers: {
      'Authorization': `key=${FCM_SERVER_KEY}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      to: token,
      priority: 'high',
      data: {
        ...data,
        click_action: 'FLUTTER_NOTIFICATION_CLICK',
      },
      notification: {
        title: 'تحديث بيانات - مارينا',
        body: getNotificationBody(data),
        sound: 'default',
        android_channel_id: 'marina_sync',
      },
    }),
  });

  const result = await response.json();

  if (!response.ok || !result.success) {
    throw new Error(result.error || 'FCM send failed');
  }

  return {
    success: true,
    messageId: result.message_id,
  };
}

/**
 * الحصول على نص الإشعار حسب نوع العملية والمجموعة
 */
function getNotificationBody(data) {
  const collectionNames = {
    'rooms': 'الغرف',
    'bookings': 'الحجوزات',
    'payments': 'المدفوعات',
    'expenses': 'المصاريف',
    'employees': 'الموظفين',
    'shift_notes': 'ملاحظات الشيفت',
    'debts': 'الديون',
    'guest_infos': 'معلومات الضيوف',
  };

  const operationNames = {
    'create': 'إضافة جديد في',
    'update': 'تعديل في',
    'delete': 'حذف من',
  };

  const collectionName = collectionNames[data.collection] || data.collection;
  const operationName = operationNames[data.operation] || 'تغيير في';

  return `${operationName} ${collectionName}`;
}
