# 📋 تقرير مزامنة جدول Bookings - Appwrite Cloud vs الكود المحلي

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
| 5 | `guestIdType` | `string(100)` | ❌ | `"بطاقة شخصية"` | نوع الهوية |
| 6 | `guestIdNumber` | `string(50)` | ❌ | `""` | رقم الهوية |
| 7 | `guestIdIssueDate` | `string(50)` | ❌ | - | تاريخ إصدار الهوية |
| 8 | `guestIdIssuePlace` | `string(200)` | ❌ | - | مكان إصدار الهوية |
| 9 | `guestNationality` | `string(100)` | ✅ | - | الجنسية |
| 10 | `guestEmail` | `string(200)` | ❌ | - | البريد الإلكتروني |
| 11 | `guestAddress` | `string(500)` | ❌ | - | العنوان |
| 12 | `checkinDate` | `string(50)` | ✅ | - | تاريخ تسجيل الدخول |
| 13 | `checkoutDate` | `string(50)` | ❌ | - | تاريخ تسجيل الخروج المتوقع |
| 14 | `actualCheckout` | `string(50)` | ❌ | - | تاريخ الخروج الفعلي |
| 15 | `status` | `string(50)` | ✅ | - | الحالة |
| 16 | `notes` | `string(1000)` | ❌ | - | ملاحظات |
| 17 | `stayDurationIso` | `string(50)` | ❌ | - | مدة الإقامة ISO |
| 18 | `lastNightEpoch` | `integer` | ❌ | - | آخر ليلة |
| 19 | `isOverdue` | `boolean` | ❌ | `false` | متأخر |
| 20 | `needsCheckoutReview` | `boolean` | ❌ | `false` | يحتاج مراجعة خروج |
| 21 | `isFullyPaid` | `boolean` | ❌ | `false` | مكتمل الدفع |
| 22 | `hotelDayCheckin` | `string(50)` | ❌ | - | يوم الفندق للدخول |
| 23 | `hotelDayCheckout` | `string(50)` | ❌ | - | يوم الفندق للخروج |
| 24 | `serverBookingId` | `integer` | ❌ | - | معرف الحجز على السيرفر |

### 💰 حقول الخصم (Discount Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 25 | `discount` | `double` | ❌ | `0` |
| 26 | `discountType` | `string(20)` | ❌ | `""` |
| 27 | `discountStartDate` | `string(255)` | ❌ | - |

### 💵 حقول مالية (Financial Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 28 | `financialFrozenAt` | `integer` | ❌ | - |
| 29 | `financialHash` | `string(64)` | ❌ | - |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 30 | `serverId` | `integer` | ❌ | - |
| 31 | `createdAt` | `integer` | ✅ | - |
| 32 | `updatedAt` | `integer` | ✅ | - |
| 33 | `deletedAt` | `integer` | ❌ | - |
| 34 | `lastModified` | `integer` | ✅ | - |
| 35 | `origin` | `string(50)` | ❌ | `"local"` |
| 36 | `createdAtIso` | `string(50)` | ❌ | - |
| 37 | `updatedAtIso` | `string(50)` | ❌ | - |
| 38 | `deletedAtIso` | `string(50)` | ❌ | - |
| 39 | `createdAtEpoch` | `integer` | ❌ | `0` |
| 40 | `lastModifiedEpoch` | `integer` | ❌ | `0` |
| 41 | `vectorClock` | `string(500)` | ❌ | `"{}"` |
| 42 | `version` | `integer` | ❌ | `1` |
| 43 | `deviceId` | `string(100)` | ❌ | `""` |
| 44 | `id` | `integer` | ❌ | - |
| 45 | `syncTimestamp` | `integer` | ❌ | `0` |
| 46 | `sync_origin` | `string(64)` | ❌ | `"mobile"` |

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
| `expectedNights` | ✅ | ❌ | ⚠️ مفقود على Cloud |
| `calculatedNights` | ✅ | ❌ | ⚠️ مفقود على Cloud |
| `totalNightsCached` | ✅ | ❌ | ⚠️ مفقود على Cloud |
| `totalDueCached` | ✅ | ❌ | ⚠️ مفقود على Cloud |
| `totalPaidCached` | ✅ | ❌ | ⚠️ مفقود على Cloud |
| `remainingBalanceCached` | ✅ | ❌ | ⚠️ مفقود على Cloud |
| `financialFrozenAt` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `financialHash` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `sync_origin` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `syncTimestamp` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
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

### 1. حقول مفقودة على Appwrite Cloud:
- `expectedNights` - عدد الليالي المتوقعة
- `calculatedNights` - عدد الليالي المحسوب
- `totalNightsCached` - إجمالي الليالي (cache)
- `totalDueCached` - إجمالي المستحق (cache)
- `totalPaidCached` - إجمالي المدفوع (cache)
- `remainingBalanceCached` - الرصيد المتبقي (cache)

### 2. حقول إضافية على Cloud فقط:
- `financialFrozenAt` - تجميد مالي
- `financialHash` - تجزئة مالية
- `sync_origin` - أصل المزامنة
- `syncTimestamp` - طابع زمني للمزامنة

### 3. ملاحظة:
الحقول المحسوبة (`*Cached`) لا تُزامن لأنها تُحسب محلياً عبر `BookingDerivedFieldsService`

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Bookings Adapter | `lib/services/adapters/bookings_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |
| Booking Derived Fields Service | `lib/services/booking_derived_fields_service.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
