# 📋 تقرير مزامنة جدول Payments - Appwrite Cloud vs الكود المحلي

**تاريخ التقرير:** 2026-06-26  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  

---

## ✅ تصحيح مهم - SyncFields

> **ملاحظة:** هذا التقرير السابق ذكر بعض الحقول كـ "مفقودة". 
> **✅ تم التصحيح: جميع حقول SyncFields موجودة في Appwrite Cloud!**

### حقول SyncFields في Payments:

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
| **Collection ID** | `payments` |

---

## 📊 الحقول الفعلية على Appwrite Cloud

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | Required | Default | الوصف |
|---|-------|------|----------|---------|-------|
| 1 | `localUuid` | `string(100)` | ✅ | - | UUID فريد (Document ID) |
| 2 | `serverPaymentId` | `integer` | ❌ | - | معرف الدفع على السيرفر |
| 3 | `bookingLocalId` | `integer` | ❌ | - | معرف الحجز المحلي |
| 4 | `serverBookingId` | `integer` | ❌ | - | معرف الحجز على السيرفر |
| 5 | `roomNumber` | `string(50)` | ❌ | - | رقم الغرفة |
| 6 | `amount` | `double` | ✅ | - | المبلغ |
| 7 | `paymentDate` | `string(50)` | ✅ | - | تاريخ الدفع |
| 8 | `notes` | `string(500)` | ❌ | - | ملاحظات |
| 9 | `paymentMethod` | `string(100)` | ✅ | - | طريقة الدفع |
| 10 | `revenueType` | `string(100)` | ✅ | - | نوع الإيراد |

### 🔗 حقول المعاملات النقدية

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 11 | `cashTransactionLocalId` | `integer` | ❌ | - |
| 12 | `cashTransactionServerId` | `integer` | ❌ | - |
| 13 | `referenceNumber` | `string(100)` | ❌ | - |
| 14 | `hotelDayKey` | `string(50)` | ❌ | - |

### 💰 حقول مالية إضافية

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 15 | `isPendingBalance` | `boolean` | ❌ | `false` |
| 16 | `linkedDebtUuid` | `string(100)` | ❌ | - |
| 17 | `bookingUuidCache` | `string(100)` | ❌ | - |

### ❌ حقول الإلغاء (Void Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 18 | `isVoided` | `boolean` | ❌ | `false` |
| 19 | `voidedAt` | `integer` | ❌ | - |
| 20 | `voidedBy` | `string(100)` | ❌ | - |
| 21 | `voidReason` | `string(255)` | ❌ | - |
| 22 | `isImmutable` | `boolean` | ❌ | `false` |

### 💸 حقول الخصم

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 23 | `discountAmount` | `double` | ❌ | - |
| 24 | `discountStartDate` | `datetime` | ❌ | - |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 25 | `serverId` | `integer` | ❌ | - |
| 26 | `createdAt` | `integer` | ✅ | - |
| 27 | `updatedAt` | `integer` | ✅ | - |
| 28 | `deletedAt` | `integer` | ❌ | - |
| 29 | `lastModified` | `integer` | ✅ | - |
| 30 | `origin` | `string(50)` | ❌ | `"local"` |
| 31 | `lastModifiedEpoch` | `integer` | ❌ | `0` |
| 32 | `vectorClock` | `string(500)` | ❌ | `"{}"` |
| 33 | `version` | `integer` | ❌ | `1` |
| 34 | `syncTimestamp` | `integer` | ❌ | `0` |
| 35 | `deviceId` | `string(100)` | ❌ | `""` |
| 36 | `sync_version` | `integer` | ❌ | - |
| 37 | `sync_vector_clock` | `string(2000)` | ❌ | - |
| 38 | `sync_origin` | `string(64)` | ❌ | `"mobile"` |
| 39 | `id` | `integer` | ❌ | - |
| 40 | `createdAtIso` | `string(50)` | ❌ | - |
| 41 | `updatedAtIso` | `string(50)` | ❌ | - |
| 42 | `deletedAtIso` | `string(50)` | ❌ | - |
| 43 | `createdAtEpoch` | `integer` | ❌ | `0` |

---

## 📐 الفهارس (Indexes)

| # | الاسم | النوع | الحقول |
|---|-------|-------|--------|
| 1 | `idxLocalUuid` | unique | `localUuid` |
| 2 | `idxServerPaymentId` | unique | `serverPaymentId` |
| 3 | `idxBookingLocalIdHotelDay` | key | `bookingLocalId, hotelDayKey` |
| 4 | `idxRoomNumberHotelDay` | key | `roomNumber, hotelDayKey` |
| 5 | `idxBookingLocalId` | key | `bookingLocalId` |
| 6 | `idxServerBookingId` | key | `serverBookingId` |
| 7 | `idxRoomNumber` | key | `roomNumber` |
| 8 | `idxPaymentDate` | key | `paymentDate` |
| 9 | `idxPaymentMethod` | key | `paymentMethod` |
| 10 | `idxRevenueType` | key | `revenueType` |
| 11 | `idxHotelDayKey` | key | `hotelDayKey` |
| 12 | `idxIsPendingBalance` | key | `isPendingBalance` |
| 13 | `idxLinkedDebtUuid` | key | `linkedDebtUuid` |
| 14 | `idxCashTransactionLocalId` | key | `cashTransactionLocalId` |
| 15 | `idxLastModified` | key | `lastModified` |
| 16 | `idx_local_uuid` | unique | `localUuid` |
| 17 | `idx_booking_date` | key | `bookingLocalId, paymentDate` |
| 18 | `idx_hotel_day_type` | key | `hotelDayKey, revenueType` |
| 19 | `idx_payments_void` | key | `isVoided` |
| 20 | `idx_payments_uuid` | unique | `localUuid` |

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
| **إجمالي الحقول** | 43 حقل |
| **تاريخ الإنشاء** | 2026-01-26 |
| **آخر تحديث** | 2026-02-01 |
| **الحجم المستخدم** | 19,128 bytes |
| **عدد الفهارس** | 20 index |

---

## ✅ مقارنة: الكود المحلي vs Appwrite Cloud

| الحقل | الكود المحلي | Appwrite Cloud | الحالة |
|-------|------------|----------------|--------|
| `localUuid` | ✅ | ✅ | ✅ مطابق |
| `id` | ✅ | ✅ | ✅ مطابق |
| `serverPaymentId` | ✅ | ✅ | ✅ مطابق |
| `bookingLocalId` | ✅ | ✅ | ✅ مطابق |
| `serverBookingId` | ✅ | ✅ | ✅ مطابق |
| `roomNumber` | ✅ | ✅ | ✅ مطابق |
| `amount` | ✅ | ✅ | ✅ مطابق |
| `paymentDate` | ✅ | ✅ | ✅ مطابق |
| `notes` | ✅ | ✅ | ✅ مطابق |
| `paymentMethod` | ✅ | ✅ | ✅ مطابق |
| `revenueType` | ✅ | ✅ | ✅ مطابق |
| `cashTransactionLocalId` | ✅ | ✅ | ✅ مطابق |
| `cashTransactionServerId` | ✅ | ✅ | ✅ مطابق |
| `referenceNumber` | ✅ | ✅ | ✅ مطابق |
| `hotelDayKey` | ✅ | ✅ | ✅ مطابق |
| `isPendingBalance` | ✅ | ✅ | ✅ مطابق |
| `linkedDebtUuid` | ✅ | ✅ | ✅ مطابق |
| `bookingUuidCache` | ✅ | ✅ | ✅ مطابق |
| `discountAmount` | ✅ | ✅ | ✅ مطابق |
| `discountStartDate` | ✅ | ✅ | ✅ مطابق |
| `isVoided` | ✅ | ✅ | ✅ مطابق |
| `voidedAt` | ✅ | ✅ | ✅ مطابق |
| `voidedBy` | ✅ | ✅ | ✅ مطابق |
| `voidReason` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `isImmutable` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `serverId` | ✅ | ✅ | ✅ مطابق |
| `createdAt` | ✅ | ✅ | ✅ مطابق |
| `updatedAt` | ✅ | ✅ | ✅ مطابق |
| `deletedAt` | ✅ | ✅ | ✅ مطابق |
| `lastModified` | ✅ | ✅ | ✅ مطابق |
| `origin` | ✅ | ✅ | ✅ مطابق |
| `lastModifiedEpoch` | ✅ | ✅ | ✅ مطابق |
| `vectorClock` | ✅ | ✅ | ✅ مطابق |
| `version` | ✅ | ✅ | ✅ مطابق |
| `syncTimestamp` | ✅ | ✅ | ✅ مطابق |
| `deviceId` | ✅ | ✅ | ✅ مطابق |
| `sync_version` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `sync_vector_clock` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `sync_origin` | ❌ | ✅ | ⚠️ موجود فقط على Cloud |
| `createdAtIso` | ✅ | ✅ | ✅ مطابق |
| `updatedAtIso` | ✅ | ✅ | ✅ مطابق |
| `deletedAtIso` | ✅ | ✅ | ✅ مطابق |
| `createdAtEpoch` | ✅ | ✅ | ✅ مطابق |

---

## ⚠️ ملاحظات مهمة

### حقول إضافية على Cloud فقط:
- `voidReason` - سبب الإلغاء
- `isImmutable` - هل الدفع غير قابل للتعديل
- `sync_version` - إصدار المزامنة
- `sync_vector_clock` - ساعة المتجهات للمزامنة
- `sync_origin` - أصل المزامنة

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Payments Adapter | `lib/services/adapters/payments_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |
| Payment Voids Adapter | `lib/services/adapters/payment_voids_adapter.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
