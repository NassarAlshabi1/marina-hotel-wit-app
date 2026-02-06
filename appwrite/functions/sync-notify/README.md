# Appwrite Sync Function

وظيفة Appwrite للمزامنة الفورية بين الأجهزة.

## كيف تعمل؟

1. عند إنشاء/تعديل/حذف أي مستند في Collections المحددة
2. تُنشئ الوظيفة إشعار في `sync_notifications` collection
3. الأجهزة الأخرى تستخدم Realtime للاستماع للتغييرات
4. عند استلام إشعار، يسحب الجهاز البيانات المحدثة

## الإعداد

### 1. إنشاء Collection للإشعارات

أنشئ collection باسم `sync_notifications` مع الـ attributes التالية:

| Attribute | Type | Required | Description |
|-----------|------|----------|-------------|
| event_type | string(20) | ✅ | create/update/delete |
| collection | string(50) | ✅ | اسم الـ collection |
| document_id | string(36) | ✅ | ID المستند |
| source_device_id | string(50) | ❌ | الجهاز المصدر |
| timestamp | datetime | ✅ | وقت الحدث |
| data_snapshot | string(1000) | ❌ | بيانات مختصرة |

### 2. إنشاء Index

```
Attribute: timestamp
Type: key
Order: DESC
```

### 3. Environment Variables

في Appwrite Console → Functions → sync-notify → Settings:

```
APPWRITE_API_KEY=your-api-key
APPWRITE_DATABASE_ID=marina_hotel
```

### 4. Deploy الوظيفة

```bash
# تثبيت Appwrite CLI
npm install -g appwrite-cli

# تسجيل الدخول
appwrite login

# Deploy
cd appwrite
appwrite deploy function
```

## استخدام في Flutter

```dart
// الاستماع للإشعارات باستخدام Realtime
final realtime = Realtime(client);
final subscription = realtime.subscribe([
  'databases.marina_hotel.collections.sync_notifications.documents'
]);

subscription.stream.listen((response) {
  final notification = response.payload;
  final collection = notification['collection'];
  final documentId = notification['document_id'];
  
  // سحب المستند المحدث
  await syncManager.pullDocument(collection, documentId);
});
```

## Collections المدعومة

- `rooms` - الغرف
- `bookings` - الحجوزات
- `employees` - الموظفين
- `expenses` - المصروفات
- `payments` - المدفوعات
- `debts` - الديون
- `notes` - الملاحظات

## التنظيف التلقائي

الوظيفة تحذف الإشعارات الأقدم من 24 ساعة تلقائياً.
