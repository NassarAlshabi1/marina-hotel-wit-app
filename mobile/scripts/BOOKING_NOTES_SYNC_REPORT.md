# 📋 تقرير مزامنة جدول Booking Notes - Appwrite Cloud

**تاريخ التقرير:** 2026-06-27  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** booking_notes

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `booking_notes` |
| **Rows على Cloud** | 0 سجل (فارغ حالياً) |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | ملاحظة |
|-------|------|------|--------|
| `localUuid` | string | 0/100 | **REQUIRED** — UUID فريد |
| `createdAt` | integer | - | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | - | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | - | **REQUIRED** — آخر تعديل |
| `bookingId` | integer | - | **REQUIRED** — معرف الحجز |
| `noteText` | string | 0/1000 | **REQUIRED** — نص الملاحظة |
| `alertType` | string | 0/20 | **REQUIRED** — نوع التنبيه |

### الحقول الاختيارية (OPTIONAL) على Cloud

| الحقل | النوع | الطول | ملاحظة |
|-------|------|------|--------|
| `serverId` | integer? | - | معرف السيرفر |
| `deletedAt` | integer? | - | تاريخ الحذف الناعم |
| `createdAtIso` | string? | 0/50 | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 0/50 | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | - | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | epoch التعديل |
| `version` | integer? | - | الإصدار |
| `origin` | string? | 0/20 | المصدر |
| `vectorClock` | string? | 0/500 | ساعة المتجهات |
| `alertUntil` | string? | 0/50 | حتى متى التنبيه |
| `isActive` | boolean? | - | هل الملاحظة نشطة |
| `deviceId` | string? | 0/100 | معرف الجهاز |
| `id` | integer? | - | ✅ معرف (أُضيف 2026-06-27) |
| `syncTimestamp` | integer? | - | طابع زمني للمزامنة |
| `sync_origin` | string? | 0/64 | مصدر المزامنة |
| `idempotencyKey` | string? | 0/255 | مفتاح Idempotency |

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
`validFieldsPerCollection['booking_notes']`:
- `id` — معرف (integer?, optional على Cloud)

### 2. ❌ حقول محذوفة من validFields (2026-06-27):

الحقول التالية كانت مُدرجة في `validFieldsPerCollection['booking_notes']`
لكنها **غير موجودة على Appwrite Cloud** — تم حذفها لمنع الأخطاء:
- `bookingUuid` — غير موجود على Cloud
- `note` — غير موجود على Cloud (استخدم `noteText` بدلاً منها)

### 3. ملاحظات عامة

- جدول `booking_notes` يُستخدم لتخزين **ملاحظات الحجوزات** (تنبيهات، ملاحظات خاصة)
- مرتبط بجدول `bookings` عبر `bookingId`
- `alertType` يحدد نوع التنبيه (مثل: "high", "medium", "low")
- `alertUntil` يحدد متى ينتهي التنبيه
- `isActive` يشير إلى ما إذا كانت الملاحظة نشطة

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Booking Notes Adapter | `lib/services/adapters/booking_notes_adapter.dart` | تحويل البيانات |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `BookingNotes` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إضافة `id` + إزالة `bookingUuid` و `note` (غير موجودة على Cloud) من `validFieldsPerCollection['booking_notes']` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**تاريخ الإنشاء:** 2026-06-27
