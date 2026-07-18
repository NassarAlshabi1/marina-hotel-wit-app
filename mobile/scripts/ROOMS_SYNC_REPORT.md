## ✅ تصحيح مهم - SyncFields

> **ملاحظة:** هذا التقرير السابق ذكر بعض الحقول كـ "مفقودة".
> **✅ تم التصحيح: جميع حقول SyncFields موجودة في Appwrite Cloud!**

### حقول SyncFields:

| الحقل | النوع | الوصف |
|-------|------|-------|
| `createdAt` | integer | تاريخ الإنشاء |
| `updatedAt` | integer | تاريخ التحديث |
| `deletedAt` | integer? | تاريخ الحذف |
| `lastModified` | integer | آخر تعديل |
| `createdAtIso` | string? | تاريخ ISO |
| `updatedAtIso` | string? | تحديث ISO |
| `createdAtEpoch` | integer? | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | epoch التعديل |
| `version` | integer? | الإصدار |
| `origin` | string? | المصدر |
| `vectorClock` | string? | ساعة المتجهات |
| `deviceId` | string? | معرف الجهاز |

---
# 📋 تقرير مزامنة جدول Rooms - Appwrite Cloud vs الكود المحلي

**تاريخ التقرير:** 2026-06-26  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `rooms` |

---

## 📊 الحقول الفعلية على Appwrite Cloud

### 🏠 الحقول الأساسية (Attributes)

| # | الحقل | النوع | Required | Default | الوصف |
|---|-------|------|----------|---------|-------|
| 1 | `localUuid` | `string(100)` | ✅ | - | UUID فريد (Document ID) |
| 2 | `roomNumber` | `string(50)` | ✅ | - | رقم الغرفة |
| 3 | `type` | `string(100)` | ✅ | - | نوع الغرفة |
| 4 | `price` | `double` | ✅ | - | السعر |
| 5 | `status` | `string(50)` | ✅ | - | الحالة |
| 6 | `imageUrl` | `string(500)` | ❌ | `null` | رابط الصورة |
| 7 | `cleaningStatus` | `string(50)` | ❌ | `"clean"` | حالة التنظيف |
| 8 | `lastCleanedHotelDay` | `string(50)` | ❌ | `null` | آخر يوم تنظيف |
| 9 | `lastOccupiedHotelDay` | `string(50)` | ❌ | `null` | آخر يوم إقامة |
| 10 | `requiresMaintenance` | `boolean` | ❌ | `false` | تحتاج صيانة |
| 11 | `roomType` | `string(255)` | ❌ | `null` | نوع الغرفة |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 12 | `serverId` | `integer` | ❌ | `null` |
| 13 | `createdAt` | `integer` | ✅ | `null` |
| 14 | `updatedAt` | `integer` | ✅ | `null` |
| 15 | `deletedAt` | `integer` | ❌ | `null` |
| 16 | `lastModified` | `integer` | ✅ | `null` |
| 17 | `origin` | `string(50)` | ❌ | `"local"` |
| 18 | `createdAtIso` | `string(50)` | ❌ | `null` |
| 19 | `updatedAtIso` | `string(50)` | ❌ | `null` |
| 20 | `deletedAtIso` | `string(50)` | ❌ | `null` |
| 21 | `createdAtEpoch` | `integer` | ❌ | `0` |
| 22 | `lastModifiedEpoch` | `integer` | ❌ | `0` |
| 23 | `vectorClock` | `string(500)` | ❌ | `"{}"` |
| 24 | `version` | `integer` | ❌ | `1` |
| 25 | `deviceId` | `string(100)` | ❌ | `""` |
| 26 | `id` | `integer` | ❌ | `null` |
| 27 | `syncTimestamp` | `integer` | ❌ | `0` |
| 28 | `sync_origin` | `string(64)` | ❌ | `"mobile"` |

---

## 📐 الفهارس (Indexes)

| # | الاسم | النوع | الحقول |
|---|-------|-------|--------|
| 1 | `idxLocalUuid` | unique | `localUuid` |
| 2 | `idxRoomNumber` | unique | `roomNumber` |
| 3 | `idxStatusCleaning` | key | `status, cleaningStatus` |
| 4 | `idxRequiresMaintenance` | key | `requiresMaintenance` |
| 5 | `idxStatus` | key | `status` |
| 6 | `idxType` | key | `type` |
| 7 | `idxLastModified` | key | `lastModified` |
| 8 | `idxServerId` | key | `serverId` |
| 9 | `idxOrigin` | key | `origin` |
| 10 | `idx_rooms_uuid` | unique | `localUuid` |
| 11 | `idx_rooms_number` | unique | `roomNumber` |

---

## 🔐 الصلاحيات (Permissions)

```
read("any")
create("any")
update("any")
delete("any")
```

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول** | 28 حقل |
| **تاريخ الإنشاء** | 2026-01-26 |
| **آخر تحديث** | 2026-02-01 |
| **الحجم المستخدم** | 9,450 bytes |
| **عدد الفهارس** | 13 index |

---

## ✅ مقارنة: الكود المحلي vs Appwrite Cloud

| الحقل | الكود المحلي | Appwrite Cloud | الحالة |
|-------|------------|----------------|--------|
| `localUuid` | ✅ | ✅ | ✅ مطابق |
| `roomNumber` | ✅ | ✅ | ✅ مطابق |
| `type` | ✅ | ✅ | ✅ مطابق |
| `price` | ✅ | ✅ | ✅ مطابق |
| `status` | ✅ | ✅ | ✅ مطابق |
| `imageUrl` | ✅ | ✅ | ✅ مطابق |
| `cleaningStatus` | ✅ | ✅ | ✅ مطابق |
| `lastCleanedHotelDay` | ✅ | ✅ | ✅ مطابق |
| `lastOccupiedHotelDay` | ✅ | ✅ | ✅ مطابق |
| `requiresMaintenance` | ✅ | ✅ | ✅ مطابق |
| `serverId` | ✅ | ✅ | ✅ مطابق |
| `createdAt` | ✅ | ✅ | ✅ مطابق |
| `updatedAt` | ✅ | ✅ | ✅ مطابق |
| `deletedAt` | ✅ | ✅ | ✅ مطابق |
| `lastModified` | ✅ | ✅ | ✅ مطابق |
| `origin` | ✅ | ✅ | ✅ مطابق |
| `createdAtIso` | ✅ | ✅ | ✅ مطابق |
| `updatedAtIso` | ✅ | ✅ | ✅ مطابق |
| `deletedAtIso` | ✅ | ✅ | ✅ مطابق |
| `createdAtEpoch` | ✅ | ✅ | ✅ مطابق |
| `lastModifiedEpoch` | ✅ | ✅ | ✅ مطابق |
| `vectorClock` | ✅ | ✅ | ✅ مطابق |
| `version` | ✅ | ✅ | ✅ مطابق |
| `deviceId` | ✅ | ✅ | ✅ مطابق |
| `roomType` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `sync_origin` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `syncTimestamp` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `id` | ✅ | ✅ | ✅ مطابق |

---

## ⚠️ ملاحظات

1. **حقول إضافية على Cloud:** 
   - `roomType` - نوع الغرفة (مكرر مع `type`)
   - `sync_origin` - أصل المزامنة
   - `syncTimestamp` - طابع زمني للمزامنة

2. **ملاحظة:** `sync_origin` و `syncTimestamp` يتم إرسالها أثناء المزامنة Push فقط (انظر `appwrite_delta_sync.dart`)

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `roomNumber` | string | 3/50 | "104" | **REQUIRED** — رقم الغرفة |
| `type` | string | 9/100 | "سرير فردي" | **REQUIRED** — نوع الغرفة |
| `price` | integer | - | 15000 | **REQUIRED** — السعر |
| `status` | string | 5/50 | "شاغرة" | **REQUIRED** — الحالة |
| `localUuid` | string | 32/100 | "3205842c508e..." | **REQUIRED** — UUID فريد |
| `createdAt` | integer | - | 1773812679000 | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | - | 1782504378 | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | - | 1782504378 | **REQUIRED** — آخر تعديل |

### الحقول الاختيارية (OPTIONAL) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `imageUrl` | string? | 0/500 | NULL | صورة الغرفة |
| `cleaningStatus` | string? | 5/50 | "clean" | حالة التنظيف |
| `lastCleanedHotelDay` | string? | 0/50 | NULL | آخر يوم تنظيف |
| `lastOccupiedHotelDay` | string? | 10/50 | "2026-06-14" | آخر يوم إشغال |
| `requiresMaintenance` | boolean? | - | false | يتطلب صيانة |
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف الناعم |
| `createdAtIso` | string? | 0/50 | NULL | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 27/50 | "2026-06-16T17:38:22..." | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | NULL | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | - | 0 | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | 1781631502 | epoch التعديل |
| `vectorClock` | string? | 2/500 | "{}" | ساعة المتجهات |
| `version` | integer? | - | 1000026 | الإصدار |
| `origin` | string? | 6/50 | "server" | المصدر |
| `deviceId` | string? | 36/100 | "da2c98b9-..." | معرف الجهاز |
| `id` | integer? | - | NULL | ✅ معرف (أُضيف 2026-06-27) |
| `roomType` | string? | 9/255 | "سرير فردي" | نوع الغرفة (مكرر مع type) |
| `syncTimestamp` | integer? | - | 0 | ✅ طابع زمني (أُضيف 2026-06-27) |
| `sync_origin` | string? | 6/64 | "mobile" | ✅ مصدر المزامنة (أُضيف 2026-06-27) |
| `idempotencyKey` | string? | - | NULL | مفتاح Idempotency |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['rooms']`:
- `id` — معرف (integer?, optional على Cloud)
- `syncTimestamp` — طابع زمني للمزامنة
- `sync_origin` — مصدر المزامنة (string?, 64)

### 2. ملاحظات عامة

- جدول `rooms` يُستخدم لتخزين **بيانات الغرف**
- `type` و `roomType` مكرران (نفس البيانات) — `roomType` للتوافق مع Legacy
- `price` على Cloud هو `integer`، محلياً `double` — يتم التحويل عبر `.round()`
- `status` يمكن أن يكون: "شاغرة"، "محجوزة"، "صيانة"

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Rooms Adapter | `lib/services/adapters/rooms_adapter.dart` | تحويل البيانات |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `Rooms` |
| Appwrite Config | `lib/services/appwrite_config.dart` | إعدادات المجموعات |
| Delta Sync Service | `lib/services/delta_sync_service.dart` | مزامنة تفاضلية |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إضافة `id`, `syncTimestamp`, `sync_origin` إلى `validFieldsPerCollection['rooms']` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**آخر تحديث:** 2026-06-27
