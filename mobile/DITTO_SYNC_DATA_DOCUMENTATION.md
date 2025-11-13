# 📋 توثيق بيانات المزامنة مع Ditto

## نظرة عامة

هذا المستند يشرح بالتفصيل **جميع البيانات** التي يتم مزامنتها بين التطبيق المحلي (SQLite) وسحابة Ditto باستخدام خدمة `DittoLocalSyncService`.

---

## 🔄 آلية المزامنة

### Push (الرفع)
يتم **رفع البيانات المحلية** من قاعدة SQLite إلى Ditto Cloud باستخدام:
```dart
await pushLocalData();
```

### Pull (السحب)
يتم **سحب البيانات البعيدة** من Ditto Cloud إلى قاعدة SQLite المحلية باستخدام:
```dart
await pullRemoteData();
```

### Full Sync (المزامنة الكاملة)
تتم المزامنة الثنائية (Push ثم Pull) باستخدام:
```dart
await fullSync();
```

---

## 📊 البيانات التي يتم مزامنتها

يتم مزامنة **9 مجموعات (Collections)** من البيانات:

### 1️⃣ **Rooms (الغرف)** 🏨
**Collection Name:** `rooms`

#### البيانات المحفوظة:
- `room_number` - رقم الغرفة
- `type` - نوع الغرفة (مفردة، مزدوجة، جناح، إلخ)
- `price` - سعر الغرفة لليلة الواحدة
- `status` - حالة الغرفة (متاحة، محجوزة، قيد الصيانة)
- `image_url` - رابط صورة الغرفة (اختياري)

#### الاستخدام:
- إدارة الغرف المتاحة في الفندق
- متابعة حالة كل غرفة
- تحديد الأسعار

---

### 2️⃣ **Bookings (الحجوزات)** 📅
**Collection Name:** `bookings`

#### البيانات المحفوظة:
- `room_number` - رقم الغرفة المحجوزة
- `guest_name` - اسم النزيل
- `guest_phone` - رقم هاتف النزيل
- `guest_id_type` - نوع الهوية (جواز سفر، بطاقة شخصية، إلخ)
- `guest_id_number` - رقم الهوية
- `guest_id_issue_date` - تاريخ إصدار الهوية (اختياري)
- `guest_id_issue_place` - مكان إصدار الهوية (اختياري)
- `guest_nationality` - جنسية النزيل
- `guest_email` - البريد الإلكتروني (اختياري)
- `guest_address` - عنوان النزيل (اختياري)
- `check_in` - تاريخ ووقت تسجيل الدخول
- `check_out` - تاريخ ووقت تسجيل الخروج
- `nights` - عدد الليالي
- `num_guests` - عدد النزلاء
- `total_cost` - التكلفة الإجمالية
- `amount_paid` - المبلغ المدفوع
- `payment_method` - طريقة الدفع (نقدي، بطاقة، إلخ)
- `status` - حالة الحجز (confirmed, checked_in, checked_out, cancelled)
- `notes` - ملاحظات إضافية (اختياري)

#### الاستخدام:
- تتبع جميع الحجوزات
- إدارة معلومات النزلاء
- حساب المدفوعات والمتبقي

---

### 3️⃣ **Booking Notes (ملاحظات الحجز)** 📝
**Collection Name:** `booking_notes`

#### البيانات المحفوظة:
- `booking_local_uuid` - معرف الحجز المرتبط
- `note` - نص الملاحظة
- `author` - كاتب الملاحظة
- `note_type` - نوع الملاحظة (general, warning, important)
- `created_timestamp` - وقت إنشاء الملاحظة

#### الاستخدام:
- إضافة ملاحظات على الحجوزات
- تسجيل معلومات إضافية عن النزلاء
- التواصل بين الموظفين

---

### 4️⃣ **Employees (الموظفون)** 👥
**Collection Name:** `employees`

#### البيانات المحفوظة:
- `name` - اسم الموظف
- `phone` - رقم الهاتف
- `email` - البريد الإلكتروني (اختياري)
- `position` - المنصب الوظيفي
- `salary` - الراتب
- `hire_date` - تاريخ التعيين
- `status` - حالة الموظف (active, inactive)
- `notes` - ملاحظات إضافية (اختياري)

#### الاستخدام:
- إدارة بيانات الموظفين
- تتبع الرواتب
- إدارة السحوبات المالية للموظفين

---

### 5️⃣ **Expenses (المصروفات)** 💰
**Collection Name:** `expenses`

#### البيانات المحفوظة:
- `category` - فئة المصروف (صيانة، رواتب، كهرباء، إلخ)
- `amount` - مبلغ المصروف
- `description` - وصف المصروف
- `date` - تاريخ المصروف
- `payment_method` - طريقة الدفع
- `receipt_number` - رقم الإيصال (اختياري)
- `employee_id` - معرف الموظف المسؤول (اختياري)
- `notes` - ملاحظات إضافية (اختياري)

#### الاستخدام:
- تتبع جميع مصروفات الفندق
- إعداد التقارير المالية
- تحليل النفقات حسب الفئات

---

### 6️⃣ **Cash Transactions (المعاملات النقدية)** 💵
**Collection Name:** `cash_transactions`

#### البيانات المحفوظة:
- `type` - نوع المعاملة (deposit, withdrawal, transfer)
- `amount` - مبلغ المعاملة
- `description` - وصف المعاملة
- `reference` - مرجع المعاملة (رقم حجز، إيصال، إلخ)
- `timestamp` - وقت المعاملة
- `employee_id` - معرف الموظف الذي قام بالمعاملة
- `balance_before` - الرصيد قبل المعاملة
- `balance_after` - الرصيد بعد المعاملة
- `notes` - ملاحظات إضافية (اختياري)

#### الاستخدام:
- إدارة الخزنة (Cash Register)
- تتبع حركة الأموال
- مراجعة المعاملات المالية

---

### 7️⃣ **Payments (الدفعات)** 💳
**Collection Name:** `payments`

#### البيانات المحفوظة:
- `booking_local_uuid` - معرف الحجز المرتبط
- `amount` - مبلغ الدفعة
- `payment_method` - طريقة الدفع (cash, card, transfer)
- `payment_date` - تاريخ ووقت الدفع
- `receipt_number` - رقم الإيصال
- `employee_id` - معرف الموظف الذي استلم الدفعة
- `notes` - ملاحظات على الدفعة (اختياري)

#### الاستخدام:
- تتبع جميع الدفعات المستلمة
- ربط الدفعات بالحجوزات
- إصدار الإيصالات

---

### 8️⃣ **Debts (الديون)** 📊
**Collection Name:** `debts`

#### البيانات المحفوظة:
- `booking_local_uuid` - معرف الحجز المرتبط (اختياري)
- `guest_name` - اسم النزيل المدين
- `guest_phone` - رقم هاتف النزيل
- `total_amount` - المبلغ الإجمالي
- `paid_amount` - المبلغ المدفوع
- `remaining_amount` - المبلغ المتبقي
- `due_date` - تاريخ الاستحقاق (اختياري)
- `status` - حالة الدين (pending, partial, paid)
- `notes` - ملاحظات إضافية (اختياري)

#### الاستخدام:
- تتبع الديون المستحقة
- إدارة الذمم
- تحصيل المدفوعات المتأخرة

---

### 9️⃣ **Shift Notes (ملاحظات الوردية)** 🕐
**Collection Name:** `shift_notes`

#### البيانات المحفوظة:
- `employee_id` - معرف الموظف الذي كتب الملاحظة
- `shift_date` - تاريخ الوردية
- `shift_type` - نوع الوردية (morning, evening, night)
- `note` - نص الملاحظة
- `priority` - أولوية الملاحظة (normal, high, urgent)
- `created_timestamp` - وقت إنشاء الملاحظة

#### الاستخدام:
- تسجيل الأحداث خلال الوردية
- التواصل بين الورديات
- تتبع المشاكل والملاحظات الهامة

---

## 🔐 الحقول المشتركة (Sync Fields)

كل مستند في Ditto يحتوي على حقول مزامنة إضافية:

```dart
{
  "_id": "uuid",              // المعرف الفريد المحلي
  "server_id": 123,           // المعرف على السيرفر (اختياري)
  "created_at": 1699700000,   // وقت الإنشاء (Unix timestamp)
  "updated_at": 1699700000,   // وقت آخر تحديث
  "deleted_at": null,         // وقت الحذف (null = غير محذوف)
  "last_modified": 1699700000, // آخر تعديل
  "version": 1,               // رقم الإصدار للتتبع
  "origin": "local"           // مصدر البيانات (local/server)
}
```

### ما فائدة هذه الحقول؟
- **Conflict Resolution** - حل التعارضات عند المزامنة من أجهزة متعددة
- **Change Tracking** - تتبع التغييرات والتعديلات
- **Soft Delete** - الحذف الناعم (لا يتم حذف البيانات فعلياً)
- **Version Control** - التحكم في إصدارات البيانات

---

## 🚀 أمثلة عملية

### مثال 1: رفع غرفة جديدة (Push)

عند إضافة غرفة جديدة في التطبيق:

```dart
Room newRoom = Room(
  localUuid: 'uuid-123',
  roomNumber: '101',
  type: 'Single',
  price: 100.0,
  status: 'available',
  createdAt: DateTime.now().millisecondsSinceEpoch,
  updatedAt: DateTime.now().millisecondsSinceEpoch,
  lastModified: DateTime.now().millisecondsSinceEpoch,
  version: 1,
  origin: 'local',
);

// سيتم رفعها إلى Ditto كـ:
{
  "_id": "uuid-123",
  "room_number": "101",
  "type": "Single",
  "price": 100.0,
  "status": "available",
  "created_at": 1699700000,
  "updated_at": 1699700000,
  "last_modified": 1699700000,
  "version": 1,
  "origin": "local"
}
```

### مثال 2: سحب حجز جديد (Pull)

عند وجود حجز جديد في Ditto Cloud:

```dart
// البيانات من Ditto:
{
  "_id": "uuid-456",
  "room_number": "102",
  "guest_name": "أحمد محمد",
  "guest_phone": "0500000000",
  "check_in": 1699700000,
  "check_out": 1699786400,
  "nights": 1,
  "total_cost": 150.0,
  "status": "confirmed",
  ...
}

// سيتم حفظها في SQLite المحلية
```

### مثال 3: المزامنة الكاملة (Full Sync)

```dart
// 1. Push: رفع جميع البيانات المحلية إلى Ditto
await pushLocalData();
// ✅ تم رفع 5 غرف، 10 حجوزات، 3 موظفين، ...

// 2. Pull: سحب جميع البيانات من Ditto إلى المحلي
await pullRemoteData();
// ✅ تم سحب 2 غرف جديدة، 5 حجوزات محدثة، ...

// النتيجة: البيانات متطابقة على جميع الأجهزة! 🎉
```

---

## 🎯 متى تحدث المزامنة؟

### 1. **Auto Sync** - المزامنة التلقائية
يمكن تفعيل المزامنة التلقائية عند بدء التطبيق:
```dart
await DittoLocalSyncService().maybeAutoSync(database);
```

### 2. **Manual Sync** - المزامنة اليدوية
يمكن للمستخدم تشغيل المزامنة يدوياً من الإعدادات:
```dart
await DittoLocalSyncService().fullSync();
```

### 3. **Real-time Sync** - المزامنة الفورية
عند تشغيل `startSync()`:
```dart
await DittoLocalSyncService().startSync();
```
تصبح التغييرات **فورية** بين جميع الأجهزة المتصلة!

---

## ⚠️ ملاحظات هامة

### 1. الحذف الناعم (Soft Delete)
- عند حذف عنصر، **لا يُحذف فعلياً** من قاعدة البيانات
- يتم وضع قيمة في حقل `deleted_at`
- هذا يضمن مزامنة الحذف عبر جميع الأجهزة

### 2. حل التعارضات
- إذا تم تعديل نفس البيانات من جهازين مختلفين:
  - يتم الاعتماد على حقل `version`
  - البيانات الأحدث (أعلى version) تفوز
  - حقل `last_modified` يحدد أحدث تعديل

### 3. البيانات المستثناة
- **لا يتم مزامنة** البيانات المحذوفة (`deleted_at != null`)
- يتم استخدام filter في DQL: `WHERE !DELETED`

### 4. الأمان
- جميع البيانات مشفرة أثناء النقل
- يتم المصادقة عبر Ditto Authentication
- كل جهاز له identity فريد

---

## 📈 إحصائيات المزامنة

يمكن الحصول على إحصائيات المزامنة:

```dart
final stats = await DittoLocalSyncService().getSyncStats();

print(stats);
// {
//   'rooms_in_local': 15,
//   'bookings_in_local': 45,
//   'employees_in_local': 8,
//   'payments_in_local': 120,
//   'is_syncing': false,
//   'last_sync': 2024-11-11 17:30:00,
//   'last_error': null
// }
```

---

## 🔧 استكشاف الأخطاء

### خطأ في المزامنة
إذا فشلت المزامنة، يمكن التحقق من:
1. الاتصال بالإنترنت
2. صلاحيات Ditto (App ID, Token)
3. سجل الأخطاء في `last_error`

### سرعة المزامنة
- عدد البيانات يؤثر على السرعة
- استخدم `includeDeleted: false` لتسريع المزامنة
- المزامنة التلقائية قد تستهلك البيانات

---

## 📚 المراجع

- [Ditto SDK Documentation](https://docs.ditto.live/)
- [DQL Documentation](https://docs.ditto.live/dql/dql)
- [كود المصدر: ditto_local_sync_service.dart](lib/services/ditto_local_sync_service.dart)
- [كود المصدر: ditto_schema_mapper.dart](lib/services/ditto_schema_mapper.dart)

---

**آخر تحديث:** 13 نوفمبر 2025  
**الإصدار:** Ditto SDK 4.10.2
