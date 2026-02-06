import { Client, Databases, ID, Query } from 'node-appwrite';

const SYNC_NOTIFICATIONS_COLLECTION = 'sync_notifications';
const MAX_NOTIFICATION_AGE_HOURS = 24;

export default async ({ req, res, log, error }) => {
  const client = new Client()
    .setEndpoint(process.env.APPWRITE_FUNCTION_API_ENDPOINT)
    .setProject(process.env.APPWRITE_FUNCTION_PROJECT_ID)
    .setKey(process.env.APPWRITE_API_KEY);

  const databases = new Databases(client);
  const databaseId = process.env.APPWRITE_DATABASE_ID || 'marina_hotel';

  try {
    const event = req.headers['x-appwrite-event'];
    const payload = req.body;

    if (!event || !payload) {
      return res.json({ success: false, message: 'No event data' });
    }

    log(`Received event: ${event}`);

    const eventParts = event.split('.');
    const collectionName = eventParts[3] || 'unknown';
    const eventType = eventParts[5] || 'unknown';
    const documentId = payload.$id;
    const deviceId = payload.device_id || payload.lastModifiedBy || null;

    const notification = {
      event_type: eventType,
      collection: collectionName,
      document_id: documentId,
      source_device_id: deviceId,
      timestamp: new Date().toISOString(),
      data_snapshot: JSON.stringify({
        id: payload.$id,
        updatedAt: payload.$updatedAt,
        collection: collectionName,
      }),
    };

    await databases.createDocument(
      databaseId,
      SYNC_NOTIFICATIONS_COLLECTION,
      ID.unique(),
      notification
    );

    log(`Sync notification created for ${collectionName}/${documentId}`);

    await cleanupOldNotifications(databases, databaseId, log);

    return res.json({
      success: true,
      message: 'Sync notification created',
      notification: {
        collection: collectionName,
        document_id: documentId,
        event_type: eventType,
      },
    });
  } catch (err) {
    error(`Error processing sync event: ${err.message}`);
    return res.json({
      success: false,
      error: err.message,
    }, 500);
  }
};

async function cleanupOldNotifications(databases, databaseId, log) {
  try {
    const cutoffTime = new Date();
    cutoffTime.setHours(cutoffTime.getHours() - MAX_NOTIFICATION_AGE_HOURS);

    const oldNotifications = await databases.listDocuments(
      databaseId,
      SYNC_NOTIFICATIONS_COLLECTION,
      [
        Query.lessThan('timestamp', cutoffTime.toISOString()),
        Query.limit(100),
      ]
    );

    for (const doc of oldNotifications.documents) {
      await databases.deleteDocument(
        databaseId,
        SYNC_NOTIFICATIONS_COLLECTION,
        doc.$id
      );
    }

    if (oldNotifications.documents.length > 0) {
      log(`Cleaned up ${oldNotifications.documents.length} old notifications`);
    }
  } catch (err) {
    log(`Cleanup skipped: ${err.message}`);
  }
}
