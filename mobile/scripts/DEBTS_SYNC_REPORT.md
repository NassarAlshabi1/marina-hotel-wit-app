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
# 📋 تقرير مزامنة جدول Debts - الكود المحلي

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
| **Collection ID** | `debts` |

---

## 📊 الحقول الفعلية في الكود المحلي

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | Default | الوصف |
|---|-------|------|---------|-------|
| 1 | `id` | `integer` | - | معرف محلي (autoIncrement) |
| 2 | `localUuid` | `string` | - | UUID فريد عالمياً |
| 3 | `bookingLocalId` | `integer?` | - | FK إلى الحجز |
| 4 | `guestName` | `string` | - | اسم النزيل |
| 5 | `checkinDate` | `string` | - | تاريخ تسجيل الدخول |
| 6 | `checkoutDate` | `string` | - | تاريخ تسجيل الخروج |
| 7 | `dateRecorded` | `string` | `""` | تاريخ التسجيل |
| 8 | `debtReason` | `string` | `""` | سبب الدين |
| 9 | `totalAmount` | `double` | - | المبلغ الإجمالي |
| 10 | `paidAmount` | `double` | - | المبلغ المدفوع |
| 11 | `remainingAmount` | `double` | - | المبلغ المتبقي |
| 12 | `paymentDate` | `string` | - | تاريخ الدفع |
| 13 | `isSettled` | `integer` | `0` | هل تم تسديد الدين (0/1) |
| 14 | `pledge` | `string?` | - | الرهن |
| 15 | `pledgeType` | `string?` | - | نوع الرهن |
| 16 | `note` | `string?` | - | ملاحظات |
| 17 | `debtUuid` | `string?` | - | UUID الدين |
| 18 | `hotelDayOpened` | `string?` | - | يوم الفندق للفتح |
| 19 | `hotelDayClosed` | `string?` | - | يوم الفندق للإغلاق |
| 20 | `isFromAutoFix` | `boolean` | `false` | من الإصلاح التلقائي |
| 21 | `settlementConfirmed` | `boolean` | `false` | تأكيد التسديد |

### 🔗 المفاتيح الأجنبية

| الحقل | يربط إلى |
|-------|----------|
| `bookingLocalId` | `Bookings.id` |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Default |
|---|-------|------|---------|
| 22 | `serverId` | `integer?` | - |
| 23 | `createdAt` | `integer` | - |
| 24 | `updatedAt` | `integer` | - |
| 25 | `deletedAt` | `integer?` | - |
| 26 | `lastModified` | `integer` | - |
| 27 | `origin` | `string` | `"local"` |
| 28 | `createdAtIso` | `string?` | - |
| 29 | `updatedAtIso` | `string?` | - |
| 30 | `deletedAtIso` | `string?` | - |
| 31 | `createdAtEpoch` | `integer` | `0` |
| 32 | `lastModifiedEpoch` | `integer` | `0` |
| 33 | `version` | `integer` | `1` |
| 34 | `vectorClock` | `string` | `"{}"` |
| 35 | `deviceId` | `string` | `""` |

---

## 📐 الفهارس (Indexes)

| # | الاسم | الحقول |
|---|-------|--------|
| 1 | `idx_debts_status` | `is_settled, is_from_auto_fix` |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول الأساسية** | 21 حقل |
| **إجمالي حقول المزامنة** | 14 حقل |
| **المجموع** | **35 حقل** |
| **عدد الفهارس** | 1 index |

---

## 📝 ملاحظات

- جدول `debts` يُستخدم لتسجيل **ديون النزلاء** عند تسجيل الخروج
- مرتبط بالحجز عبر `bookingLocalId`
- يحتوي على:
  - المبلغ الإجمالي والمدفوع والمتبقي
  - تاريخ الدفع
  - حالة التسديد (`isSettled`)
  - الرهون (`pledge`, `pledgeType`)
- يمكن أن يُنشأ تلقائياً عبر `AutoFix`

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | مثال | ملاحظة |
|-------|------|------|--------|
| `guestName` | string (200) | "jamal" | **REQUIRED** — اسم النزيل |
| `checkinDate` | string (50) | "2026-06-27 01:02:39" | **REQUIRED** — تاريخ تسجيل الدخول |
| `totalAmount` | integer | 15000 | **REQUIRED** — إجمالي المبلغ |
| `paidAmount` | integer | 0 | **REQUIRED** — المبلغ المدفوع |
| `localUuid` | string (100) | "c4c94231-db39-..." | **REQUIRED** — UUID فريد |
| `createdAt` | integer | 1782513533 | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | 1782513823 | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | 1782513823 | **REQUIRED** — آخر تعديل |

### الحقول الاختيارية (OPTIONAL) على Cloud

| الحقل | النوع | مثال | ملاحظة |
|-------|------|------|--------|
| `bookingLocalId` | integer? | 215 | معرف الحجز المحلي |
| `checkoutDate` | string? (50) | "2026-06-27T01:38:53..." | تاريخ الخروج |
| `dateRecorded` | string? (50) | NULL | تاريخ التسجيل |
| `debtReason` | string? (200) | "مبلغ متبقي من إقامة - غرفة 304" | سبب الدين |
| `paymentDate` | string? (50) | "2026-06-27T01:38:53..." | تاريخ الدفع |
| `isSettled` | boolean? | false | هل تم التسوية |
| `pledge` | string? (200) | NULL | الرهن |
| `pledgeType` | string? (100) | NULL | نوع الرهن |
| `note` | string? (500) | "تم إنشاء هذا الدين تلقائياً..." | ملاحظات |
| `debtUuid` | string? (100) | NULL | UUID الدين |
| `hotelDayOpened` | string? (50) | NULL | يوم فتح الدين |
| `hotelDayClosed` | string? (50) | NULL | يوم إغلاق الدين |
| `isFromAutoFix` | boolean? | false | من AutoFix |
| `settlementConfirmed` | boolean? | false | تأكيد التسوية |
| `serverId` | integer? | NULL | معرف السيرفر |
| `deletedAt` | integer? | NULL | تاريخ الحذف الناعم |
| `createdAtIso` | string? (50) | NULL | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? (50) | NULL | تاريخ ISO للتحديث |
| `deletedAtIso` | string? (50) | NULL | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | 0 | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | 0 | epoch التعديل |
| `version` | integer? | 1 | الإصدار |
| `origin` | string? (50) | "local" | المصدر |
| `vectorClock` | string? (500) | "{}" | ساعة المتجهات |
| `deviceId` | string? (100) | "6b8c6ab2-..." | معرف الجهاز |
| `syncTimestamp` | integer? | 0 | ✅ طابع زمني (أُضيف 2026-06-27) |
| `sync_origin` | string? (50) | NULL | ✅ مصدر المزامنة (أُضيف 2026-06-27) |
| `guestPhone` | string? (20) | NULL | ✅ هاتف النزيل (أُضيف 2026-06-27) |
| `description` | string? (500) | NULL | ✅ وصف إضافي (أُضيف 2026-06-27) |
| `status` | string? (50) | NULL | ✅ الحالة (أُضيف 2026-06-27) |
| `date` | string? (50) | NULL | ✅ التاريخ (أُضيف 2026-06-27) |
| `amount` | integer? | NULL | ✅ المبلغ (أُضيف 2026-06-27) |
| `remainingAmount` | integer? | 15000 | المبلغ المتبقي |
| `id` | integer? | NULL | ✅ معرف (أُضيف 2026-06-27) |
| `idempotencyKey` | string? (255) | "debts:update:..." | مفتاح Idempotency |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['debts']`:
- `syncTimestamp` — طابع زمني للمزامنة
- `sync_origin` — مصدر المزامنة
- `guestPhone` — هاتف النزيل
- `description` — وصف إضافي
- `status` — الحالة
- `date` — التاريخ
- `amount` — المبلغ
- `id` — معرف

### 2. ❌ حقول محذوفة من validFields (2026-06-27):

الحقول التالية كانت مُدرجة سابقاً لكنها **مكررة** — تم حذفها لأنها
تكرر `version` و `vectorClock`:
- `sync_version` — استخدم `version` بدلاً منها
- `sync_vector_clock` — استخدم `vectorClock` بدلاً منها

### 3. تحديث `_debtToRemote()`

تم تعديل `_debtToRemote()` لإرسال بنشاط:
- `sync_origin = debt.origin`
- `syncTimestamp = debt.lastModified`

### 4. تحويل النوع

- `totalAmount`, `paidAmount`, `amount`, `remainingAmount` على Cloud هي `integer`، محلياً `double` — يتم التحويل عبر `.round()`

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Debts Adapter | `lib/services/adapters/debts_adapter.dart` | تحويل البيانات |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `Debts` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` |
| Sync Manager | `lib/services/appwrite_sync_manager.dart` | `_processDebtEntry` + `_debtToRemote` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إضافة 8 حقول مفقودة + إزالة `sync_version` و `sync_vector_clock` (مكررة) من `validFieldsPerCollection['debts']` + تحديث `_debtToRemote` لإرسال `sync_origin` و `syncTimestamp` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**آخر تحديث:** 2026-06-27
