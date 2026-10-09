# 📋 تقرير مزامنة جدول Bookings - Appwrite Cloud vs الكود المحلي

**تاريخ التقرير:** 2026-06-26  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  

---

## ✅ تصحيح مهم - SyncFields

> **ملاحظة:** هذا التقرير السابق ذكر بعض الحقول كـ "مفقودة". 
> **✅ تم التصحيح: جميع حقول SyncFields موجودة في Appwrite Cloud!**

### حقول SyncFields في Bookings:

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

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `bookings` |

---

## 📊 الحقول الفعلية على Appwrite Cloud

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | Required | Default | الوصف |
|---|-------|------|----------|---------|-------|
| 1 | `localUuid` | `string(100)` | ✅ | - | UUID فريد (Document ID) |
| 2 | `roomNumber` | `string(50)` | ✅ | - | رقم الغرفة |
| 3 | `guestName` | `string(200)` | ✅ | - | اسم النزيل |
| 4 | `guestPhone` | `string(20)` | ✅ | - | هاتف النزيل |
| 5 | `guestIdType` | `string(100)` | ✓ | `"بطاقة شخصية"` | نوع الهوية |
| 6 | `guestIdNumber` | `string(50)` | ✓ | `""` | رقم الهوية |
| 7 | `guestIdIssueDate` | `string(50)` | ✓ | - | تاريخ إصدار الهوية |
| 8 | `guestIdIssuePlace` | `string(200)` | ✓ | - | مكان إصدار الهوية |
| 9 | `guestNationality` | `string(100)` | ✅ | - | الجنسية |
| 10 | `guestEmail` | `string(200)` | ✓ | - | البريد الإلكتروني |
| 11 | `guestAddress` | `string(500)` | ✓ | - | العنوان |
| 12 | `checkinDate` | `string(50)` | ✅ | - | تاريخ تسجيل الدخول |
| 13 | `checkoutDate` | `string(50)` | ✓ | - | تاريخ تسجيل الخروج المتوقع |
| 14 | `actualCheckout` | `string(50)` | ✓ | - | تاريخ الخروج الفعلي |
| 15 | `status` | `string(50)` | ✅ | - | الحالة |
| 16 | `notes` | `string(1000)` | ✓ | - | ملاحظات |
| 17 | `stayDurationIso` | `string(50)` | ✓ | - | مدة الإقامة ISO |
| 18 | `lastNightEpoch` | `integer` | ✓ | - | آخر ليلة |
| 19 | `isOverdue` | `boolean` | ✓ | `false` | متأخر |
| 20 | `needsCheckoutReview` | `boolean` | ✓ | `false` | يحتاج مراجعة خروج |
| 21 | `isFullyPaid` | `boolean` | ✓ | `false` | مكتمل الدفع |
| 22 | `hotelDayCheckin` | `string(50)` | ✓ | - | يوم الفندق للدخول |
| 23 | `hotelDayCheckout` | `string(50)` | ✓ | - | يوم الفندق للخروج |
| 24 | `serverBookingId` | `integer` | ✓ | - | معرف الحجز على السيرفر |

### 💰 حقول الخصم (Discount Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 25 | `discount` | `double` | ✓ | `0` |
| 26 | `discountType` | `string(20)` | ✓ | `""` |
| 27 | `discountStartDate` | `string(255)` | ✓ | - |

### 💵 حقول مالية (Financial Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 28 | `financialFrozenAt` | `integer` | ✓ | - |
| 29 | `financialHash` | `string(64)` | ✓ | - |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 30 | `serverId` | `integer` | ✓ | - |
| 31 | `createdAt` | `integer` | ✅ | - |
| 32 | `updatedAt` | `integer` | ✅ | - |
| 33 | `deletedAt` | `integer` | ✓ | - |
| 34 | `lastModified` | `integer` | ✅ | - |
| 35 | `origin` | `string(50)` | ✓ | `"local"` |
| 36 | `createdAtIso` | `string(50)` | ✓ | - |
| 37 | `updatedAtIso` | `string(50)` | ✓ | - |
| 38 | `deletedAtIso` | `string(50)` | ✓ | - |
| 39 | `createdAtEpoch` | `integer` | ✓ | `0` |
| 40 | `lastModifiedEpoch` | `integer` | ✓ | `0` |
| 41 | `vectorClock` | `string(500)` | ✓ | `"{}"` |
| 42 | `version` | `integer` | ✓ | `1` |
| 43 | `deviceId` | `string(100)` | ✓ | `""` |
| 44 | `id` | `integer` | ✓ | - |
| 45 | `syncTimestamp` | `integer` | ✓ | `0` |
| 46 | `sync_origin` | `string(64)` | ✓ | `"mobile"` |

---

## 📐 الفهارس (Indexes)

| # | الاسم | النوع | الحقول |
|---|-------|-------|--------|
| 1 | `idxLocalUuid` | unique | `localUuid` |
| 2 | `idxServerBookingId` | unique | `serverBookingId` |
| 3 | `idxStatusHotelDay` | key | `status, hotelDayCheckin` |
| 4 | `idxRoomNumber` | key | `roomNumber` |
| 5 | `idxGuestName` | key | `guestName` |
| 6 | `idxCheckinDate` | key | `checkinDate` |
| 7 | `idxCheckoutDate` | key | `checkoutDate` |
| 8 | `idxActualCheckout` | key | `actualCheckout` |
| 9 | `idxIsOverdue` | key | `isOverdue` |
| 10 | `idxIsFullyPaid` | key | `isFullyPaid` |
| 11 | `idxNeedsCheckoutReview` | key | `needsCheckoutReview` |
| 12 | `idxLastModified` | key | `lastModified` |
| 13 | `idxCreatedAt` | key | `createdAt` |
| 14 | `idxUpdatedAt` | key | `updatedAt` |
| 15 | `idxDiscountType` | key | `discountType` |
| 16 | `idxDiscountStartDate` | key | `discountStartDate` |
| 17 | `idxFinancialHash` | key | `financialHash` |
| 18 | `idx_local_uuid` | unique | `localUuid` |
| 19 | `idx_room_status` | key | `roomNumber, status` |
| 20 | `idx_status_hotel_day` | key | `status, hotelDayCheckin` |
| 21 | `idx_guest_name` | fulltext | `guestName` |
| 22 | `idx_bookings_uuid` | unique | `localUuid` |

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
| **إجمالي الحقول** | 46 حقل |
| **تاريخ الإنشاء** | 2026-01-26 |
| **آخر تحديث** | 2026-02-01 |
| **الحجم المستخدم** | 17,754 bytes |
| **عدد الفهارس** | 22 index |

---

## ✅ مقارنة: الكود المحلي vs Appwrite Cloud

| الحقل | الكود المحلي | Appwrite Cloud | الحالة |
|-------|------------|----------------|--------|
| `localUuid` | ✅ | ✅ | ✅ مطابق |
| `roomNumber` | ✅ | ✅ | ✅ مطابق |
| `guestName` | ✅ | ✅ | ✅ مطابق |
| `guestPhone` | ✅ | ✅ | ✅ مطابق |
| `guestIdType` | ✅ | ✅ | ✅ مطابق |
| `guestIdNumber` | ✅ | ✅ | ✅ مطابق |
| `guestIdIssueDate` | ✅ | ✅ | ✅ مطابق |
| `guestIdIssuePlace` | ✅ | ✅ | ✅ مطابق |
| `guestNationality` | ✅ | ✅ | ✅ مطابق |
| `guestEmail` | ✅ | ✅ | ✅ مطابق |
| `guestAddress` | ✅ | ✅ | ✅ مطابق |
| `checkinDate` | ✅ | ✅ | ✅ مطابق |
| `checkoutDate` | ✅ | ✅ | ✅ مطابق |
| `actualCheckout` | ✅ | ✅ | ✅ مطابق |
| `status` | ✅ | ✅ | ✅ مطابق |
| `notes` | ✅ | ✅ | ✅ مطابق |
| `stayDurationIso` | ✅ | ✅ | ✅ مطابق |
| `lastNightEpoch` | ✅ | ✅ | ✅ مطابق |
| `isOverdue` | ✅ | ✅ | ✅ مطابق |
| `needsCheckoutReview` | ✅ | ✅ | ✅ مطابق |
| `isFullyPaid` | ✅ | ✅ | ✅ مطابق |
| `hotelDayCheckin` | ✅ | ✅ | ✅ مطابق |
| `hotelDayCheckout` | ✅ | ✅ | ✅ مطابق |
| `serverBookingId` | ✅ | ✅ | ✅ مطابق |
| `discount` | ✅ | ✅ | ✅ مطابق |
| `discountType` | ✅ | ✅ | ✅ مطابق |
| `discountStartDate` | ✅ | ✅ | ✅ مطابق |
| `expectedNights` | ✅ | ✓ | موجودة على cloud  |
| `calculatedNights` | ✅ | ✓ | موجودة على cloud  |
| `totalNightsCached` | ✅ | ✓ | موجودة على cloud  |
| `totalDueCached` | ✅ | ✓ | موجودة على cloud  |
| `totalPaidCached` | ✅ | ✓ | موجودة على cloud  |
| `remainingBalanceCached` | ✅ | ✓ | موجودة على cloud  |
| `financialFrozenAt` | ✓ | ✅ | موجودة على cloud |
| `financialHash` | ✓ | ✅ | موجود فقط على Cloud |
| `sync_origin` | ✓ | ✅ | موجود فقط على Cloud |
| `syncTimestamp` | ✓ | ✅ | موجود فقط على Cloud |
| `serverId` | ✅ | ✅ | ✅ مطابق |
| `createdAt` | ✅ | ✅ | ✅ مطابق |
| `updatedAt` | ✅ | ✅ | ✅ مطابق |
| `deletedAt` | ✅ | ✅ | ✅ مطابق |
| `lastModified` | ✅ | ✅ | ✅ مطابق |
| `origin` | ✅ | ✅ | ✅ مطابق |
| `deviceId` | ✅ | ✅ | ✅ مطابق |
| `version` | ✅ | ✅ | ✅ مطابق |
| `vectorClock` | ✅ | ✅ | ✅ مطابق |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['bookings']` في `appwrite_sync_utils.dart`.
هذا كان يسبب حذفها بواسطة `filterPayloadForCollection` قبل الرفع،
مما يُفقد البيانات الحساسة (مثل التتبّع المالي والمصدر).

**تم الإصلاح في Commit `751774b0`:**
- `financialFrozenAt` — تجميد مالي (integer?)
- `financialHash` — تجزئة مالية (string?, 64)
- `sync_origin` — أصل المزامنة (string?, 64, snake_case)
- `syncTimestamp` — طابع زمني للمزامنة (integer?)
- `idempotencyKey` — مفتاح Idempotency (string?, 255)
- `id` — معرف (integer?, optional على Cloud)

### 2. الحقول المحسوبة (`*Cached`)

الحقول التالية تُحسب محلياً عبر `BookingDerivedFieldsService` وتُزامن
مع Cloud (لكنها تُعاد حسابها محلياً عند السحب):
- `expectedNights`, `calculatedNights`, `totalNightsCached`
- `totalDueCached`, `totalPaidCached`, `remainingBalanceCached`

### 3. تحديث `_bookingToRemote()`

في Commit `751774b0`، تم تعديل `_bookingToRemote()` لتُرسل بنشاط:
- `sync_origin = booking.origin` — مصدر المزامنة
- `syncTimestamp = booking.lastModified` — طابع زمني

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Bookings Adapter | `lib/services/adapters/bookings_adapter.dart` | تحويل البيانات بين المحلي و Cloud |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `Bookings` |
| Booking Derived Fields Service | `lib/services/booking_derived_fields_service.dart` | حساب الحقول المحسوبة |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` + `filterPayloadForCollection` |
| Sync Manager | `lib/services/appwrite_sync_manager.dart` | `_processBookingEntry` + `_bookingToRemote` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | `751774b0` | إضافة `financialFrozenAt`, `financialHash`, `syncTimestamp`, `sync_origin`, `idempotencyKey`, `id` إلى `validFieldsPerCollection['bookings']` + تحديث `_bookingToRemote` لإرسال `sync_origin` و `syncTimestamp` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**آخر تحديث:** 2026-06-27
