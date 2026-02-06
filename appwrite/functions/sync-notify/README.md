# Appwrite Function: sync-notify

إرسال إشعارات FCM عند تغيير البيانات.

## الإعداد

### 1. أضف حقل fcmToken لجدول devices في Appwrite:
- **Key:** `fcmToken`
- **Type:** String  
- **Size:** 500
- **Required:** No

### 2. احصل على FCM Server Key:
- Firebase Console → Project Settings → Cloud Messaging
- انسخ **Server key**

### 3. أضف Environment Variables في Appwrite Console:
```
APPWRITE_API_KEY=your-appwrite-api-key
APPWRITE_DATABASE_ID=hotel_db
FCM_SERVER_KEY=your-fcm-server-key
```

### 4. Deploy:
```bash
npm install -g appwrite-cli
appwrite login
cd appwrite
appwrite deploy function
```

## الأحداث المدعومة:
- إنشاء/تعديل حجز
- تعديل غرفة
- إضافة دفعة
- إضافة مصروف
