# توثيق استخدام serverId

## نظرة عامة

حقل `serverId` موجود في جميع الجداول الرئيسية (Bookings, Payments, Expenses, Employees, Rooms, Debts) لكنه **ليس المعرّف الأساسي** في النظام.

## المعرّف الأساسي الحقيقي

**`localUuid`** هو المعرّف الأساسي الفعلي للسجلات في النظام، وهو:

- نوعه: `String` (UUID v4)
- فريد عالمياً (Globally Unique)
- مستقر: لا يتغير أبداً
- يُستخدم في جميع العلاقات (Foreign Keys)
- يُستخدم في المزامنة بين الأجهزة

## دور serverId

`serverId` هو حقل **tracking فقط**، يُستخدم لـ:

1. **التتبع والربط مع Appwrite**: ربط السجل المحلي بمعرّف المستند في Appwrite
2. **Debugging**: تسهيل تتبع البيانات بين Local DB و Server
3. **Audit Trail**: معرفة ما إذا كان السجل تم مزامنته مع الخادم

### خصائص serverId

- **اختياري (nullable)**: يمكن أن يكون `null` قبل المزامنة
- **غير موثوق**: تاريخياً سبب مشاكل (UUID في حقل integer)
- **لا يُستخدم في Business Logic**: جميع القرارات والعلاقات تعتمد على `localUuid`
- **لا يُستخدم في Foreign Keys**: جميع العلاقات تستخدم `booking_local_id` وليس `booking_server_id`

## أمثلة الاستخدام

### ✅ استخدام صحيح

```dart
// البحث بـ localUuid (المعرّف الأساسي)
final booking = await bookingsDao.getByLocalUuid(localUuid);

// إنشاء payment مرتبط بـ booking
final payment = PaymentsCompanion(
  bookingLocalId: Value(booking.id),  // ✅ استخدام ID المحلي
  amount: Value(1000),
);

// التحقق من المزامنة
if (booking.serverId != null) {
  // السجل تمت مزامنته مع الخادم
}
```

### ❌ استخدام خاطئ

```dart
// ❌ لا تستخدم serverId في العلاقات
final payment = PaymentsCompanion(
  serverBookingId: Value(booking.serverId), // خطأ!
);

// ❌ لا تعتمد على serverId في منطق العمل
if (booking.serverId > 0) {  // خطأ! serverId قد يكون null
  // ...
}

// ❌ لا تستخدم serverId للبحث في الاستعلامات الحرجة
final booking = await bookingsDao.getByServerId(serverId);  // غير موثوق
```

## القواعد الهندسية

### 1. localUuid هو المعرّف الوحيد

جميع:
- عمليات البحث
- العلاقات (Foreign Keys)
- المزامنة
- Conflict Resolution

يجب أن تعتمد على `localUuid`.

### 2. serverId للتتبع فقط

استخدم `serverId` فقط لـ:
- Logging/Debugging
- ربط مع Appwrite في طبقة المزامنة
- معرفة حالة المزامنة (synced vs pending)

### 3. لا تفترض وجوده

```dart
// ✅ صحيح
final isSynced = booking.serverId != null;

// ❌ خطأ
final serverId = booking.serverId!;  // قد يسبب crash
```

## التأثير على المزامنة

### في Push (Local → Server)

```dart
// outbox_entry يحتوي على serverId للتتبع فقط
await outboxDao.merge(
  entity: 'bookings',
  localUuid: booking.localUuid,  // المعرّف الأساسي
  serverId: booking.serverId,     // للتتبع فقط
  payload: {...},
);
```

### في Pull (Server → Local)

```dart
// البحث عن السجل المحلي بـ localUuid
final existing = await bookingsDao.getByLocalUuid(remoteDoc.localUuid);

if (existing != null) {
  // تحديث (بما فيها serverId للتتبع)
  await bookingsDao.updateById(existing.id, ...);
} else {
  // إدراج جديد
  await bookingsDao.insertOne(..., originIsServer: true);
}
```

## الفوائد

### 1. تقليل المخاطر

- عدم الاعتماد على حقل سبب مشاكل تاريخياً
- منع UUID في حقل integer
- منع FK violations بسبب serverId غير صحيح

### 2. استقرار النظام

- `localUuid` مستقر ولا يتغير
- لا يوجد race conditions بسبب serverId
- سلوك متوقع في جميع الحالات

### 3. توافق Offline-First

- السجلات لها معرّف فريد حتى قبل المزامنة
- لا حاجة لانتظار serverId من الخادم
- يمكن إنشاء العلاقات فوراً

## ملخص

| الجانب | localUuid | serverId |
|--------|-----------|----------|
| **النوع** | String (UUID) | int? (nullable) |
| **الدور** | المعرّف الأساسي | Tracking فقط |
| **الاستخدام** | جميع العلاقات والمنطق | Debugging/Audit |
| **الموثوقية** | موثوق 100% | غير موثوق |
| **الإلزامية** | إلزامي | اختياري |
| **التغيير** | لا يتغير أبداً | يُملأ عند المزامنة |

---

**القاعدة الذهبية**: استخدم `localUuid` لكل شيء، و `serverId` للتتبع فقط.
