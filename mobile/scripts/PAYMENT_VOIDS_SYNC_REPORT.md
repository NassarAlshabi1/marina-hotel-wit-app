# 📋 تقرير مزامنة جدول Payment Voids - Appwrite Cloud

**تاريخ التقرير:** 2026-06-27  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** payment_voids

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `payment_voids` |
| **Rows على Cloud** | 4+ سجل |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `localUuid` | string | 36/36 | "fcb6a4d7-dbc7-..." | **REQUIRED** — UUID فريد |
| `createdAt` | integer | - | 1782247392 | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | - | 1782247392 | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | - | 1782247392 | **REQUIRED** — آخر تعديل |
| `originalPaymentUuid` | string | 36/36 | "05206718-f1fc-..." | **REQUIRED** — UUID الدفع الأصلي |
| `originalPaymentId` | integer | - | 659 | **REQUIRED** — معرف الدفع الأصلي |
| `bookingUuid` | string | 36/36 | "5ea6b0be-fa2d-..." | **REQUIRED** — UUID الحجز |
| `voidReason` | string | 24/500 | "إلغاء دفعة اليوم الفندقي" | **REQUIRED** — سبب الإلغاء |
| `voidedBy` | string | 11/100 | "مدير النظام" | **REQUIRED** — مُلغى بواسطة |
| `voidedAt` | integer | - | 1782247392 | **REQUIRED** — وقت الإلغاء |
| `voidedAtIso` | string | 26/30 | "2026-06-23T23:43:12..." | **REQUIRED** — وقت الإلغاء ISO |
| `hotelDayKey` | string | 10/20 | "2026-06-23" | **REQUIRED** — مفتاح اليوم الفندقي |
| `voidedAmount` | integer | - | 2000 | **REQUIRED** — المبلغ المُلغى |
| `paymentUuid` | string | 36/36 | "05206718-f1fc-..." | **REQUIRED** — UUID الدفع |

### الحقول الاختيارية (OPTIONAL) على Cloud

#### 🔄 حقول المزامنة (SyncFields)

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف الناعم |
| `version` | integer? | - | 1 | الإصدار |
| `origin` | string? | 5/50 | "local" | المصدر |
| `vectorClock` | string? | 2/1000 | "{}" | ساعة المتجهات |
| `deviceId` | string? | 0/50 | NULL | معرف الجهاز |
| `syncTimestamp` | integer? | - | NULL | طابع زمني للمزامنة |
| `sync_origin` | string? | 6/64 | "mobile" | ✅ مصدر المزامنة (أُضيف 2026-06-27) |
| `createdAtIso` | string? | 0/50 | NULL | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 0/50 | NULL | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | NULL | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | - | NULL | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | 0 | epoch التعديل |
| `idempotencyKey` | string? | - | NULL | مفتاح Idempotency |

#### 💰 حقول إضافية

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `reversalPaymentUuid` | string? | 0/36 | NULL | UUID دفع العكس |
| `approvedBy` | string? | 0/100 | NULL | مُعتمد بواسطة |
| `note` | string? | 24/500 | "إلغاء دفعة اليوم الفندقي" | ملاحظة |
| `originalAmount` | integer? | - | NULL | المبلغ الأصلي |

#### 📜 حقول Legacy (snake_case)

> **ملاحظة:** هذه الحقول موجودة على Cloud بصيغة snake_case (قديمة).
> الكود يُرسل camelCase، لكن `filterPayloadForCollection` يُمرّر كلاهما.

| الحقل | النوع | ملاحظة |
|-------|------|--------|
| `created_at` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `updated_at` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `deleted_at` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `vector_clock` | string? (500) | ✅ Legacy (أُضيف 2026-06-27) |
| `device_id` | string? (100) | ✅ Legacy (أُضيف 2026-06-27) |
| `sync_timestamp` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `last_modified` | integer? | ✅ Legacy (أُضيف 2026-06-27) |

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
| **إجمالي السجلات على Cloud** | 4+ سجل |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27) — تم حلها:

الحقول التالية كانت موجودة على Appwrite Cloud لكن **لم تكن مُدرجة** في
`validFieldsPerCollection['payment_voids']`:

**camelCase:**
- `sync_origin` — مصدر المزامنة

**snake_case (Legacy):**
- `created_at` — تاريخ الإنشاء (Legacy)
- `updated_at` — تاريخ التحديث (Legacy)
- `deleted_at` — تاريخ الحذف (Legacy)
- `vector_clock` — ساعة المتجهات (Legacy)
- `device_id` — معرف الجهاز (Legacy)
- `sync_timestamp` — طابع زمني (Legacy)
- `last_modified` — آخر تعديل (Legacy)

### 2. ملاحظات عامة

- جدول `payment_voids` يُستخدم لتسجيل **إلغاء الدفعات**
- مرتبط بجدول `payments` عبر `originalPaymentUuid` و `originalPaymentId`
- مرتبط بجدول `bookings` عبر `bookingUuid`
- `voidedAmount` هو المبلغ المُلغى
- `reversalPaymentUuid` يربط بدفعة العكس (إن وجدت)
- `voidedAtIso` يخزّن وقت الإلغاء بصيغة ISO

### 3. حقول snake_case (Legacy)

الـ Cloud يحتوي على نسختين من نفس الحقول:
- **camelCase**: `createdAt`, `updatedAt`, `deletedAt`, `vectorClock`, `deviceId`
- **snake_case**: `created_at`, `updated_at`, `deleted_at`, `vector_clock`, `device_id`

الكود يُرسل camelCase فقط، لكن `validFieldsPerCollection` يسمح بكلاهما
لمنع أخطاء التصفية عند القراءة من Cloud.

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Payment Voids Adapter | `lib/services/adapters/payment_voids_adapter.dart` | تحويل البيانات |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `PaymentVoids` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` |
| Sync Manager | `lib/services/appwrite_sync_manager.dart` | `_processPaymentVoidEntry` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | - | إضافة `sync_origin` + 7 حقول snake_case Legacy إلى `validFieldsPerCollection['payment_voids']` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**تاريخ الإنشاء:** 2026-06-27
