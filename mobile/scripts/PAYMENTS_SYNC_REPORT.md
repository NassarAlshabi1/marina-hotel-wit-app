# 📋 تقرير مزامنة جدول Payments - Appwrite Cloud

**تاريخ التقرير:** 2026-06-27 (مُحدّث)  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** payments

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `payments` |
| **Rows على Cloud** | 689+ سجل (14 صفحة) |

---

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

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `amount` | integer | - | 3750 | **REQUIRED** — المبلغ (integer على Cloud) |
| `paymentDate` | string | 0/50 | "2026-06-27T01:18:24.767430" | **REQUIRED** — تاريخ الدفع |
| `paymentMethod` | string | 0/100 | "نقدي" | **REQUIRED** — طريقة الدفع |
| `revenueType` | string | 0/100 | "room" | **REQUIRED** — نوع الإيراد |
| `localUuid` | string | 0/100 | "4386188a-506c-..." | **REQUIRED** — UUID فريد |

### الحقول الاختيارية (OPTIONAL) على Cloud

#### 💰 الحقول الأساسية للدفع

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `serverPaymentId` | integer? | - | NULL | معرف الدفع على السيرفر |
| `bookingLocalId` | integer? | - | 215 | FK محلي للحجز |
| `serverBookingId` | integer? | - | NULL | معرف الحجز على السيرفر |
| `roomNumber` | string? | 0/50 | "304" | رقم الغرفة |
| `notes` | string? | 0/500 | NULL | ملاحظات |
| `cashTransactionLocalId` | integer? | - | NULL | FK لمعاملة نقدية محلية |
| `cashTransactionServerId` | integer? | - | NULL | معرف المعاملة النقدية على السيرفر |
| `referenceNumber` | string? | 0/100 | NULL | رقم المرجع |
| `hotelDayKey` | string? | 0/50 | "2026-06-26" | مفتاح يوم الفندق |
| `isPendingBalance` | boolean? | - | false | رصيد معلّق |
| `linkedDebtUuid` | string? | 0/100 | NULL | UUID للدين المرتبط |
| `bookingUuidCache` | string? | 0/100 | "bd79818a-c328-..." | UUID الحجز (cache) |

#### ❌ حقول الإلغاء (Void)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `isVoided` | boolean? | - | false | هل الدفع مُلغى |
| `voidedAt` | integer? | - | NULL | وقت الإلغاء |
| `voidedBy` | string? | 0/100 | NULL | مُلغي بواسطة |
| `voidReason` | string? | 0/255 | NULL | سبب الإلغاء |

#### 💵 حقول الخصم

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `discountAmount` | integer? | - | NULL | مبلغ الخصم |
| `discountStartDate` | string? | - | NULL | تاريخ بداية الخصم |

#### 🔒 حقول التجميد

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `isImmutable` | boolean? | - | false | هل الدفع مُجمّد (لا يمكن تعديله) |

#### 🔄 حقول المزامنة (SyncFields)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `createdAt` | integer | - | 1782512304 | تاريخ الإنشاء |
| `updatedAt` | integer | - | 1782513529 | تاريخ التحديث |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف الناعم |
| `lastModified` | integer | - | 1782513529 | آخر تعديل |
| `origin` | string? | 0/50 | "local" | المصدر |
| `lastModifiedEpoch` | integer? | - | 0 | epoch التعديل |
| `vectorClock` | string? | 0/500 | "{}" | ساعة المتجهات |
| `version` | integer? | - | 1 | الإصدار |
| `syncTimestamp` | integer? | - | NULL | طابع زمني للمزامنة |
| `deviceId` | string? | 0/100 | "6b8c6ab2-..." | معرف الجهاز |
| `sync_origin` | string? | 0/64 | "mobile" | مصدر المزامنة (snake_case) |
| `createdAtIso` | string? | 0/50 | NULL | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 0/50 | NULL | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | NULL | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | - | NULL | epoch الإنشاء |
| `idempotencyKey` | string? | 0/255 | "payments:update:..." | مفتاح Idempotency |

#### 📜 حقول قديمة (Legacy / Deprecated)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `sync_version` | integer? | - | NULL | إصدار قديم (deprecated) |
| `sync_vector_clock` | string? | 0/2000 | NULL | ساعة متجهات قديمة (deprecated) |
| `id` | integer? | - | NULL | معرف (optional) |

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
| **إجمالي الحقول على Cloud** | 40+ حقل |
| **إجمالي السجلات على Cloud** | 689+ سجل |
| **آخر دفعة مسجّلة** | $id=4386188a-506c-... (2026-06-27) |

---

## ✅ مقارنة: الكود المحلي vs Appwrite Cloud (مُحدّث 2026-06-27)

| الحقل | الكود المحلي | Appwrite Cloud | validFields | الحالة |
|-------|------------|----------------|-------------|--------|
| `amount` | ✅ | ✅ | ✅ | ✅ مطابق |
| `paymentDate` | ✅ | ✅ | ✅ | ✅ مطابق |
| `paymentMethod` | ✅ | ✅ | ✅ | ✅ مطابق |
| `revenueType` | ✅ | ✅ | ✅ | ✅ مطابق |
| `localUuid` | ✅ | ✅ | ✅ | ✅ مطابق |
| `serverPaymentId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `bookingLocalId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `serverBookingId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `roomNumber` | ✅ | ✅ | ✅ | ✅ مطابق |
| `notes` | ✅ | ✅ | ✅ | ✅ مطابق |
| `cashTransactionLocalId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `cashTransactionServerId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `referenceNumber` | ✅ | ✅ | ✅ | ✅ مطابق |
| `hotelDayKey` | ✅ | ✅ | ✅ | ✅ مطابق |
| `isPendingBalance` | ✅ | ✅ | ✅ | ✅ مطابق |
| `linkedDebtUuid` | ✅ | ✅ | ✅ | ✅ مطابق |
| `bookingUuidCache` | ✅ | ✅ | ✅ | ✅ مطابق |
| `isVoided` | ✅ | ✅ | ✅ | ✅ مطابق |
| `voidedAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `voidedBy` | ✅ | ✅ | ✅ | ✅ مطابق |
| `voidReason` | ❌ | ✅ | ✅ | ⚠️ على Cloud فقط — غير موجود في النموذج المحلي |
| `discountAmount` | ✅ | ✅ | ✅ | ✅ مطابق |
| `discountStartDate` | ✅ | ✅ | ✅ | ✅ مطابق |
| `isImmutable` | ❌ | ✅ | ✅ | ⚠️ على Cloud فقط — غير موجود في النموذج المحلي |
| `serverId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `createdAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `updatedAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `deletedAt` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lastModified` | ✅ | ✅ | ✅ | ✅ مطابق |
| `origin` | ✅ | ✅ | ✅ | ✅ مطابق |
| `lastModifiedEpoch` | ✅ | ✅ | ✅ | ✅ مطابق |
| `vectorClock` | ✅ | ✅ | ✅ | ✅ مطابق |
| `version` | ✅ | ✅ | ✅ | ✅ مطابق |
| `syncTimestamp` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `deviceId` | ✅ | ✅ | ✅ | ✅ مطابق |
| `sync_origin` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `sync_version` | ❌ | ✅ | ✅ | ⚠️ Legacy — غير مُرسل من الكود |
| `sync_vector_clock` | ❌ | ✅ | ✅ | ⚠️ Legacy — غير مُرسل من الكود |
| `createdAtIso` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `updatedAtIso` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `deletedAtIso` | ✅ | ✅ | ✅ | ✅ مطابق |
| `createdAtEpoch` | ✅ | ✅ | ✅ | ✅ مطابق |
| `idempotencyKey` | ✅ | ✅ | ✅ | ✅ مطابق (أُضيف 2026-06-27) |
| `id` | ❌ | ✅ | ✅ | ⚠️ Legacy — غير مُرسل من الكود |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['payments']` في `appwrite_sync_utils.dart`
(في الواقع، `payments` لم تكن موجودة إطلاقاً في `validFieldsPerCollection`
مما كان يعني أن `_filterPayload` لا يُصفّي شيئاً — يُرسل كل الحقول).

**تم الإصلاح:**
- إنشاء `validFieldsPerCollection['payments']` كاملة بـ 40+ حقل
- تصنيف الحقول إلى: أساسية، إلغاء، خصم، تجميد، SyncFields، Legacy

### 2. تحديث `_paymentToRemote()`

تم تعديل `_paymentToRemote()` لإرسال بنشاط:
- `sync_origin = payment.origin` — مصدر المزامنة
- `syncTimestamp = payment.lastModified` — طابع زمني
- `createdAtIso`, `updatedAtIso` — تواريخ ISO

### 3. حقول على Cloud فقط (غير موجودة في النموذج المحلي)

الحقلان التاليان موجودان على Appwrite Cloud لكن **ليسا في نموذج Payment المحلي**:
- `voidReason` (string?, 255) — سبب إلغاء الدفع
- `isImmutable` (boolean?) — هل الدفع مُجمّد

يمكن إضافتهما لاحقاً إلى جدول `Payments` في `local_db.dart` عند الحاجة.

### 4. حقول Legacy (Deprecated)

الحقول التالية موجودة على Cloud لكنها قديمة وغير مُستخدمة:
- `sync_version` — استخدم `version` بدلاً منها
- `sync_vector_clock` — استخدم `vectorClock` بدلاً منها
- `id` — معرف قديم، استخدم `localUuid` بدلاً منها

### 5. تحويل النوع

- `amount` على Cloud هو `integer`، محلياً `double` — يتم التحويل عبر `.round()`
- `discountAmount` على Cloud هو `integer`، محلياً `double`

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Payments Adapter | `lib/services/adapters/payments_adapter.dart` | تحويل البيانات بين المحلي و Cloud |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `Payments` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` + `filterPayloadForCollection` |
| Sync Manager | `lib/services/appwrite_sync_manager.dart` | `_processPaymentEntry` + `_paymentToRemote` |
| Payment Voids | `lib/services/local_db.dart` (`PaymentVoids`) | جدول عمليات الإلغاء المرتبط |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إنشاء `validFieldsPerCollection['payments']` كاملة (40+ حقل) + تحديث `_paymentToRemote` لإرسال `sync_origin`, `syncTimestamp`, `createdAtIso`, `updatedAtIso` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**آخر تحديث:** 2026-06-27
