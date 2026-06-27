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
# 📋 تقرير مزامنة جدول Guest Infos - الكود المحلي

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
| **Collection ID** | `guest_infos` |

---

## 📊 الحقول الفعلية في الكود المحلي

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | Default | الوصف |
|---|-------|------|---------|-------|
| 1 | `id` | `integer` | - | معرف محلي (autoIncrement) |
| 2 | `localUuid` | `string` | - | UUID فريد عالمياً |
| 3 | `roomNumber` | `string` | - | رقم الغرفة |
| 4 | `guestName` | `string` | - | اسم النزيل |
| 5 | `nationality` | `string` | - | الجنسية |
| 6 | `idNumber` | `string` | - | رقم الهوية |
| 7 | `idType` | `string` | `"بطاقة شخصية"` | نوع الهوية |
| 8 | `issueDate` | `string?` | - | تاريخ إصدار الهوية |
| 9 | `issuePlace` | `string?` | - | مكان إصدار الهوية |
| 10 | `governorate` | `string?` | - | المحافظة |
| 11 | `notes` | `string?` | - | ملاحظات |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Default |
|---|-------|------|---------|
| 12 | `serverId` | `integer?` | - |
| 13 | `createdAt` | `integer` | - |
| 14 | `updatedAt` | `integer` | - |
| 15 | `deletedAt` | `integer?` | - |
| 16 | `lastModified` | `integer` | - |
| 17 | `origin` | `string` | `"local"` |
| 18 | `createdAtIso` | `string?` | - |
| 19 | `updatedAtIso` | `string?` | - |
| 20 | `deletedAtIso` | `string?` | - |
| 21 | `createdAtEpoch` | `integer` | `0` |
| 22 | `lastModifiedEpoch` | `integer` | `0` |
| 23 | `version` | `integer` | `1` |
| 24 | `vectorClock` | `string` | `"{}"` |
| 25 | `deviceId` | `string` | `""` |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول الأساسية** | 11 حقول |
| **إجمالي حقول المزامنة** | 14 حقل |
| **إجمالي الحقول على Cloud** | 27 حقل |
| **إجمالي السجلات على Cloud** | 75+ سجل (2 صفحة) |
| **المجموع** | **25 حقل محلياً** |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `roomNumber` | string | 3/50 | "204" | **REQUIRED** — رقم الغرفة |
| `guestName` | string | 13/255 | "يونس علي يحيى" | **REQUIRED** — اسم النزيل |
| `nationality` | string | 4/255 | "يمني" | **REQUIRED** — الجنسية |
| `idNumber` | string | 5/100 | "13183" | **REQUIRED** — رقم الهوية |
| `localUuid` | string | 36/255 | "0d96769d-e7fd-..." | **REQUIRED** — UUID فريد |
| `createdAt` | integer | - | 1782503736 | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | - | 1782503736 | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | - | 1782503736 | **REQUIRED** — آخر تعديل |
| `lastModifiedEpoch` | integer | - | 1782334586935 | **REQUIRED** — epoch التعديل |

### الحقول الاختيارية (OPTIONAL) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `issueDate` | string? | 10/50 | "2025-02-01" | تاريخ إصدار الهوية |
| `issuePlace` | string? | 3/255 | "حجة" | مكان الإصدار |
| `governorate` | string? | 3/255 | "حجة" | المحافظة |
| `idType` | string? | 11/100 | "شهادة ميلاد" | نوع الهوية |
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف الناعم |
| `createdAtIso` | string? | 0/50 | "2026-06-26T22:55:36..." | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 26/50 | "2026-06-26T22:55:36..." | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 26/50 | NULL | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | - | 1782334586935 | epoch الإنشاء |
| `version` | integer? | - | 2 | الإصدار |
| `origin` | string? | 6/50 | "server" | المصدر |
| `vectorClock` | string? | 2/65535 | "{}" | ساعة المتجهات |
| `notes` | string? | 11/100 | "شهادة ميلاد" | ملاحظات |
| `deviceId` | string? | 0/100 | NULL | معرف الجهاز |
| `sync_origin` | string? | 6/64 | "mobile" | ✅ مصدر المزامنة (أُضيف 2026-06-27) |
| `syncTimestamp` | integer? | - | NULL | ✅ طابع زمني للمزامنة (أُضيف 2026-06-27) |

### حقول Appwrite التلقائية (لا تُرسل من الكود)

| الحقل | الوصف |
|-------|--------|
| `$id` | معرف المستند التلقائي |
| `$createdAt` | تاريخ الإنشاء التلقائي |
| `$updatedAt` | تاريخ التحديث التلقائي |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['guest_infos']`:
- `sync_origin` — مصدر المزامنة (string?, 64)
- `syncTimestamp` — طابع زمني للمزامنة (integer?)

### 2. ملاحظات عامة

- جدول `guest_infos` يُستخدم لتخزين **معلومات النزلاء** (هوية، جنسية، etc.)
- مرتبط بالغرفة عبر `roomNumber`
- يحتوي على بيانات الهوية (رقم، نوع، تاريخ إصدار، مكان إصدار)
- **ملاحظة:** هذا الجدول منفصل عن جدول `bookings` - قد يكون مكرراً للبيانات

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Guest Infos Adapter | `lib/services/adapters/guest_infos_adapter.dart` | تحويل البيانات |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `GuestInfos` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إضافة `sync_origin` و `syncTimestamp` إلى `validFieldsPerCollection['guest_infos']` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**آخر تحديث:** 2026-06-27
