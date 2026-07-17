# 📋 تقرير مزامنة جدول Booking Price Adjustments - Appwrite Cloud

**تاريخ التقرير:** 2026-06-27  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** booking_price_adjustments

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `booking_price_adjustments` |
| **Rows على Cloud** | 56+ سجل (2 صفحة) |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `localUuid` | string | 36/36 | "a6cb6e8c-c194-..." | **REQUIRED** — UUID فريد |
| `bookingLocalUuid` | string | 36/36 | "79bb4f1c-e3ae-..." | **REQUIRED** — UUID الحجز |
| `effectiveHotelDay` | string | 10/10 | "2026-06-11" | **REQUIRED** — يوم بداية التطبيق |
| `adjustmentType` | string | - | "per_night" / "total" | **REQUIRED** — نوع التعديل |
| `createdAt` | integer | - | 1781488891 | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | - | 1781488891 | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | - | 1781488891 | **REQUIRED** — آخر تعديل |

### الحقول الاختيارية (OPTIONAL) على Cloud

#### 📅 حقول التواريخ والمدة

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `endHotelDay` | string? | 0/10 | "2026-06-07" | يوم نهاية التطبيق |
| `appliedAt` | string? | 0/50 | NULL | وقت التطبيق |
| `cancelledAt` | string? | 0/30 | "2026-06-04T23:08:36..." | وقت الإلغاء |
| `createdAtIso` | string? | 0/50 | NULL | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 0/50 | NULL | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | NULL | تاريخ ISO للحذف |

#### 💰 حقول التعديل

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `adjustmentMode` | string? | 5/20 | "total" / "per_night" | وضع التعديل |
| `amount` | integer? | - | 10000 | ✅ مبلغ التعديل (أُضيف 2026-06-27) |
| `reason` | string? | 25/500 | "تخفيض من شاشة تعديل الضيف" | سبب التعديل |
| `isActive` | boolean? | - | true | هل التعديل نشط |

#### 👤 حقول التطبيق والإلغاء

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `appliedBy` | string? | 5/100 | "admin" | مُطبّق بواسطة |
| `cancelledBy` | string? | 0/100 | "admin" | مُلغى بواسطة |

#### 🔗 حقول الربط

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `bookingLocalId` | integer? | - | 58 | معرف الحجز المحلي |
| `bookingUuid` | string? | 0/36 | NULL | ✅ UUID الحجز (أُضيف 2026-06-27) |
| `roomNumber` | string? | 3/20 | "102" | ✅ رقم الغرفة (أُضيف 2026-06-27) |

#### 🔄 حقول المزامنة (SyncFields)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف الناعم |
| `createdAtEpoch` | integer? | - | NULL | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | NULL | epoch التعديل |
| `version` | integer? | - | 1 | الإصدار |
| `origin` | string? | 5/20 | "server" / "local" | المصدر |
| `vectorClock` | string? | 2/1000 | "{}" | ساعة المتجهات |
| `deviceId` | string? | 0/100 | NULL | معرف الجهاز |
| `sync_origin` | string? | 6/64 | "mobile" | ✅ مصدر المزامنة (أُضيف 2026-06-27) |
| `syncTimestamp` | integer? | - | 0 | ✅ طابع زمني للمزامنة (أُضيف 2026-06-27) |
| `idempotencyKey` | string? | - | NULL | مفتاح Idempotency |

### حقول Appwrite التلقائية (لا تُرسل من الكود)

| الحقل | الوصف |
|-------|--------|
| `$id` | معرف المستند التلقائي |
| `$createdAt` | تاريخ الإنشاء التلقائي |
| `$updatedAt` | تاريخ التحديث التلقائي |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول على Cloud** | 32 حقل |
| **إجمالي السجلات على Cloud** | 56+ سجل |
| **آخر سجل مسجّل** | $id=a6cb6e8c-c194-... (2026-06-15) |

---

## ✅ مقارنة: الكود المحلي vs Appwrite Cloud (مُحدّث 2026-06-27)

| الحقل | الكود المحلي | Appwrite Cloud | validFields | الحالة |
|-------|------------|----------------|-------------|--------|
| `localUuid` | ✅ | ✅ | ✅ | ✅ مطابق |
| `bookingLocalUuid` | ✅ | ✅ | ✅ | ✅ مطابق |
| `bookingLocalId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `bookingUuid` | ❌ | ✅ | ✅ | ✅ أُضيف 2026-06-27 (legacy) |
| `effectiveHotelDay` | ✅ | ✅ | ✅ | ✅ مطابق |
| `endHotelDay` | ✅ | ✅ | ✅ | ✅ مطابق |
| `adjustmentMode` | ✅ | ✅ | ✅ | ✅ مطابق |
| `adjustmentType` | ✅ | ✅ | ✅ | ✅ مطابق |
| `amount` | ✅ | ✅ | ✅ | ✅ أُضيف 2026-06-27 |
| `reason` | ✅ | ✅ | ✅ | ✅ مطابق |
| `appliedBy` | ✅ | ✅ | ✅ | ✅ مطابق |
| `appliedAt` | ✅ | ✅ | ✅ | ✅ أُضيف 2026-06-27 |
| `cancelledAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `cancelledBy` | ✅ | ✅ | ✅ | ✅ مطابق |
| `isActive` | ✅ | ✅ | ✅ | ✅ مطابق |
| `roomNumber` | ✅ | ✅ | ✅ | ✅ أُضيف 2026-06-27 |
| `serverId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `createdAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `updatedAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `deletedAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lastModified` | ✅ | ✅ | ✅ | ✅ مطابق |
| `createdAtEpoch` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lastModifiedEpoch` | ✅ | ✅ | ✅ | ✅ مطابق |
| `version` | ✅ | ✅ | ✅ | ✅ مطابق |
| `origin` | ✅ | ✅ | ✅ | ✅ مطابق |
| `vectorClock` | ✅ | ✅ | ✅ | ✅ مطابق |
| `deviceId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `sync_origin` | ✅ | ✅ | ✅ | ✅ أُضيف 2026-06-27 |
| `syncTimestamp` | ✅ | ✅ | ✅ | ✅ أُضيف 2026-06-27 |
| `idempotencyKey` | ✅ | ✅ | ✅ | ✅ مطابق |
| `createdAtIso` | ✅ | ✅ | ✅ | ✅ مطابق |
| `updatedAtIso` | ✅ | ✅ | ✅ | ✅ مطابق |
| `deletedAtIso` | ✅ | ✅ | ✅ | ✅ مطابق |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['booking_price_adjustments']`:
- `amount` — مبلغ التعديل (integer?)
- `appliedAt` — وقت التطبيق (string?, 50)
- `bookingUuid` — UUID الحجز (string?, 36)
- `roomNumber` — رقم الغرفة (string?, 20)
- `sync_origin` — مصدر المزامنة (string?, 64)
- `syncTimestamp` — طابع زمني للمزامنة (integer?)

### 2. ملاحظات عامة

- جدول `booking_price_adjustments` يُستخدم لتسجيل **تعديلات الأسعار** على الحجوزات
- مرتبط بجدول `bookings` عبر `bookingLocalUuid` و `bookingLocalId`
- يدعم نوعين من التعديلات: `per_night` (لكل ليلة) و `total` (إجمالي)
- يمكن إلغاء التعديل عبر `cancelledAt` و `cancelledBy`
- `isActive` يشير إلى ما إذا كان التعديل نشطاً

### 3. تحويل النوع

- `amount` على Cloud هو `integer`، محلياً `double` — يتم التحويل عبر `.round()`

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Booking Price Adjustments Adapter | `lib/services/adapters/booking_price_adjustments_adapter.dart` | تحويل البيانات |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `BookingPriceAdjustments` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` |
| Sync Manager | `lib/services/appwrite_sync_manager.dart` | `_processBookingPriceAdjustmentEntry` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إضافة `amount`, `appliedAt`, `bookingUuid`, `roomNumber`, `sync_origin`, `syncTimestamp` إلى `validFieldsPerCollection['booking_price_adjustments']` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**تاريخ الإنشاء:** 2026-06-27
