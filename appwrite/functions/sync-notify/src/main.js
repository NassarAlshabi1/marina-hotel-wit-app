import { Client, Databases, Query } from 'node-appwrite';

export default async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const databases = new Databases(client);
  const databaseId = process.env.APPWRITE_DATABASE_ID || 'hotel_db';
  const fcmServerKey = process.env.FCM_SERVER_KEY;

  try {
    const event = req.headers['x-appwrite-event'];
    const payload = req.body;

    if (!event || !payload) {
      return res.json({ success: false, message: 'No event' });
    }

    const eventParts = event.split('.');
    const collection = eventParts[3] || 'unknown';
    const eventType = eventParts[5] || 'unknown';
    const sourceDevice = payload.device_id || payload.lastModifiedBy;

    log(`${eventType} on ${collection}`);

    let title, body;
    switch (collection) {
      case 'bookings':
        title = 'تحديث الحجوزات';
        body = eventType === 'create' 
          ? `حجز جديد - غرفة ${payload.roomNumber}` 
          : `تحديث حجز - غرفة ${payload.roomNumber}`;
        break;
      case 'rooms':
        title = 'تحديث الغرف';
        body = `غرفة ${payload.roomNumber} - ${payload.status}`;
        break;
      case 'payments':
        title = 'دفعة جديدة';
        body = `${payload.amount} ر.ي`;
        break;
      case 'expenses':
        title = 'مصروف جديد';
        body = `${payload.description}`;
        break;
      default:
        title = 'تحديث';
        body = collection;
    }

    const devices = await databases.listDocuments(databaseId, 'devices', [
      Query.isNotNull('fcmToken'),
      Query.limit(100),
    ]);

    const tokens = devices.documents
      .filter(d => d.fcmToken && d.localUuid !== sourceDevice)
      .map(d => d.fcmToken);

    if (tokens.length === 0) {
      return res.json({ success: true, sent: 0 });
    }

    const fcmRes = await fetch('https://fcm.googleapis.com/fcm/send', {
      method: 'POST',
      headers: {
        'Authorization': `key=${fcmServerKey}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        registration_ids: tokens,
        notification: { title, body, sound: 'default' },
        data: { collection, documentId: payload.$id, eventType },
        priority: 'high',
      }),
    });

    const result = await fcmRes.json();
    log(`Sent: ${result.success}/${tokens.length}`);

    return res.json({ success: true, sent: result.success });
  } catch (err) {
    error(err.message);
    return res.json({ success: false, error: err.message }, 500);
  }
};
