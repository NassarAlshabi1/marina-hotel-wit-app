# 📋 تقرير مزامنة جدول Cash Transactions - Appwrite Cloud

**تاريخ التقرير:** 2026-06-27  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** cash_transactions

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `cash_transactions` |
| **Rows على Cloud** | 0 سجل (فارغ حالياً) |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | ملاحظة |
|-------|------|------|--------|
| `transactionType` | string | 0/100 | **REQUIRED** — نوع المعاملة |
| `transactionTime` | string | 0/50 | **REQUIRED** — وقت المعاملة |
| `localUuid` | string | 0/100 | **REQUIRED** — UUID فريد |
| `createdAt` | integer | - | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | - | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | - | **REQUIRED** — آخر تعديل |
| `vectorClock` | string | 0/500 | **REQUIRED** — ساعة المتجهات |
| `version` | integer | - | **REQUIRED** — الإصدار |

### الحقول الاختيارية (OPTIONAL) على Cloud

| الحقل | النوع | الطول | ملاحظة |
|-------|------|------|--------|
| `registerId` | integer? | - | معرف السجل النقدي |
| `referenceType` | string? | 0/100 | نوع المرجع |
| `referenceId` | integer? | - | معرف المرجع |
| `description` | string? | 0/500 | الوصف |
| `createdBy` | integer? | - | مُنشئ المعاملة |
| `amount` | integer? | - | المبلغ |
| `serverId` | integer? | - | معرف السيرفر |
| `deletedAt` | integer? | - | تاريخ الحذف الناعم |
| `createdAtIso` | string? | 0/50 | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 0/50 | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | - | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | epoch التعديل |
| `origin` | string? | 0/50 | المصدر |
| `deviceId` | string? | 0/100 | معرف الجهاز |
| `syncTimestamp` | integer? | - | طابع زمني للمزامنة |
| `sync_origin` | string? | 0/64 | ✅ مصدر المزامنة (أُضيف 2026-06-27) |
| `id` | integer? | - | ✅ معرف (أُضيف 2026-06-27) |
| `idempotencyKey` | string? | 0/255 | مفتاح Idempotency |

### حقول Legacy (snake_case)

| الحقل | النوع | ملاحظة |
|-------|------|--------|
| `vector_clock` | string? (500) | ✅ Legacy (أُضيف 2026-06-27) |
| `device_id` | string? (100) | ✅ Legacy (أُضيف 2026-06-27) |
| `sync_timestamp` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `last_modified` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `deleted_at` | integer? | ✅ Legacy (أُضيف 2026-06-27) |

### حقول Appwrite التلقائية

| الحقل | الوصف |
|-------|--------|
| `$id`, `$createdAt`, `$updatedAt` | حقول تلقائية |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27):

- `sync_origin` — مصدر المزامنة
- `id` — معرف
- `vector_clock`, `device_id`, `sync_timestamp`, `last_modified`, `deleted_at` — Legacy snake_case

### 2. ❌ حقول محذوفة (مكررة):

- `sync_version` — استخدم `version` بدلاً منها
- `sync_vector_clock` — استخدم `vectorClock` بدلاً منها

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Cash Transactions Adapter | `lib/services/adapters/cash_transactions_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**تاريخ الإنشاء:** 2026-06-27
