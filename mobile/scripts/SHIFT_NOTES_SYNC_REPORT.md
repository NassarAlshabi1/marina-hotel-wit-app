# 📋 تقرير مزامنة جدول Shift Notes - Appwrite Cloud

**تاريخ التقرير:** 2026-06-27  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** shift_notes

---

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `shift_notes` |
| **Rows على Cloud** | 1+ سجل |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `createdAt` | integer | - | 1782227252 | **REQUIRED** — تاريخ الإنشاء |
| `localUuid` | string | 32/100 | "93705b85ed7d..." | **REQUIRED** — UUID فريد |
| `shiftDate` | string | 10/50 | "2026-06-23" | **REQUIRED** — تاريخ الوردية |
| `note` | string | 5/1000 | "hdhdh" | **REQUIRED** — الملاحظة |

### الحقول الاختيارية (OPTIONAL) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `isRead` | boolean | - | false | هل قُرأت |
| `title` | string? | 3/200 | "gjf" | العنوان |
| `content` | string? | 5/1000 | "hdhdh" | المحتوى |
| `priority` | string? | 6/20 | "medium" | الأولوية |
| `shiftType` | string? | 3/20 | "all" | نوع الوردية |
| `expiresAt` | string? | 0/50 | NULL | تاريخ الانتهاء |
| `createdBy` | string? | 4/50 | "user" | مُنشئ الملاحظة |
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `updatedAt` | integer | - | 1782409006 | تاريخ التحديث |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف |
| `lastModified` | integer? | - | NULL | آخر تعديل |
| `createdAtIso` | string? | 26/50 | "2026-06-23T18:07:32..." | تاريخ ISO |
| `updatedAtIso` | string? | 0/50 | NULL | تحديث ISO |
| `deletedAtIso` | string? | 0/50 | NULL | حذف ISO |
| `createdAtEpoch` | integer? | - | 0 | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | 0 | epoch التعديل |
| `version` | integer? | - | 2 | الإصدار |
| `origin` | string? | 6/50 | "server" | المصدر |
| `vectorClock` | string? | 2/500 | "{}" | ساعة المتجهات |
| `deviceId` | string? | 0/100 | NULL | معرف الجهاز |
| `syncTimestamp` | integer? | - | NULL | طابع زمني |
| `sync_origin` | string? | 6/64 | "mobile" | ✅ مصدر المزامنة (أُضيف 2026-06-27) |
| `id` | integer? | - | NULL | ✅ معرف (أُضيف 2026-06-27) |
| `idempotencyKey` | string? | 0/255 | NULL | مفتاح Idempotency |

### حقول Legacy (snake_case)

| الحقل | النوع | ملاحظة |
|-------|------|--------|
| `created_at` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `updated_at` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `deleted_at` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `vector_clock` | string? (500) | ✅ Legacy (أُضيف 2026-06-27) |
| `device_id` | string? (100) | ✅ Legacy (أُضيف 2026-06-27) |
| `sync_timestamp` | integer? | ✅ Legacy (أُضيف 2026-06-27) |
| `last_modified` | integer? | ✅ Legacy (أُضيف 2026-06-27) |

### حقول Appwrite التلقائية

| الحقل | الوصف |
|-------|--------|
| `$id`, `$createdAt`, `$updatedAt` | حقول تلقائية |

---

## ⚠️ ملاحظات مهمة

### 1. ✅ حقول مُضافة حديثاً (2026-06-27):

- `note` — حقل الملاحظة (REQUIRED على Cloud، كان مفقوداً!)
- `sync_origin` — مصدر المزامنة
- `id` — معرف
- `created_at`, `updated_at`, `deleted_at`, `vector_clock`, `device_id`, `sync_timestamp`, `last_modified` — Legacy snake_case

### 2. ❌ حقول محذوفة (مكررة):

- `sync_version` — استخدم `version` بدلاً منها
- `sync_vector_clock` — استخدم `vectorClock` بدلاً منها

### 3. ملاحظات عامة

- جدول `shift_notes` يُستخدم لتخزين **ملاحظات الورديات**
- `note` هو الحقل الأساسي للملاحظة (REQUIRED)
- `content` حقل إضافي للتفاصيل
- `priority` يمكن أن يكون: "high", "medium", "low"
- `shiftType` يمكن أن يكون: "all", "morning", "evening", "night"

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Shift Notes Adapter | `lib/services/adapters/shift_notes_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** Marina Hotel Agent  
**تاريخ الإنشاء:** 2026-06-27
