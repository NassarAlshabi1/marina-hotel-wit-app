# 📋 تقرير مزامنة جدول Salary Withdrawals

**تاريخ التقرير:** 2026-06-27 (مُحدّث)  
**المشروع:** Marina Hotel Mobile  
**الفرع:** marina  
**Database:** hotel_db  
**Collection:** salary_withdrawals

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

## 🔗 إعدادات الاتصال

| البند | القيمة |
|-------|-------|
| **Endpoint** | `https://fra.cloud.appwrite.io/v1` |
| **Project ID** | `690ff0da0025518570c1` |
| **Database ID** | `hotel_db` |
| **Collection ID** | `salary_withdrawals` |
| **Rows على Cloud** | 371+ سجل (7 صفحات) |

---

## 📊 الحقول الفعلية في الكود المحلي

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | الوصف |
|---|-------|------|-------|
| 1 | `id` | `integer` | معرف محلي (autoIncrement) |
| 2 | `localUuid` | `string` | UUID فريد عالمياً |
| 3 | `employeeId` | `integer` | FK إلى الموظف |
| 4 | `amount` | `double` | المبلغ المسحوب |
| 5 | `withdrawDate` | `string` | تاريخ السحب (REQUIRED على Cloud) |
| 6 | `reason` | `string?` | سبب السحب (مثل "exp_629") |
| 7 | `hotelDayKey` | `string?` | مفتاح يوم الفندق |
| 8 | `withdrawalType` | `string?` | نوع السحب |
| 9 | `description` | `string?` | وصف إضافي (ملاحظة المستخدم) |
| 10 | `expenseId` | `integer?` | معرف المصروف المرتبط |

### 🔗 المفاتيح الأجنبية

| الحقل | يربط إلى |
|-------|----------|
| `employeeId` | `Employees.id` |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Default |
|---|-------|------|---------|
| 11 | `serverId` | `integer?` | - |
| 12 | `createdAt` | `integer` | - |
| 13 | `updatedAt` | `integer` | - |
| 14 | `deletedAt` | `integer?` | - |
| 15 | `lastModified` | `integer` | - |
| 16 | `origin` | `string` | `"local"` |
| 17 | `createdAtIso` | `string?` | - |
| 18 | `updatedAtIso` | `string?` | - |
| 19 | `deletedAtIso` | `string?` | - |
| 20 | `createdAtEpoch` | `integer` | `0` |
| 21 | `lastModifiedEpoch` | `integer` | `0` |
| 22 | `version` | `integer` | `1` |
| 23 | `vectorClock` | `string` | `"{}"` |
| 24 | `deviceId` | `string` | `""` |

---

## ☁️ الحقول الموجودة على Appwrite Cloud (مُحدّث 2026-06-27)

> **مهم:** تم اكتشاف هذه الحقول من فحص فعلي لـ Appwrite Cloud.
> بعضها لم يكن مُدرجاً في `validFieldsPerCollection` مما كان يسبب
> خطأ `document_invalid_structure` عند الرفع.

### الحقول المطلوبة (REQUIRED) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `action` | string | 8/255 | "سحب راتب" | **REQUIRED** — نوع العملية |
| `amount` | integer | - | 2000 | **REQUIRED** — المبلغ (integer على Cloud) |
| `date` | string | 10/50 | "2026-06-26" | **REQUIRED** — تاريخ السحب (legacy) |
| `withdrawDate` | string | 10/50 | "2026-06-26" | **REQUIRED** — تاريخ السحب (جديد) |
| `employeeId` | integer | - | 15 | **REQUIRED** — FK للموظف |
| `localUuid` | string | 36/255 | "f68c245a-c4c3-..." | **REQUIRED** — UUID فريد |
| `createdAt` | integer | - | 1782502797 | **REQUIRED** — تاريخ الإنشاء |
| `updatedAt` | integer | - | 1782502797 | **REQUIRED** — تاريخ التحديث |
| `lastModified` | integer | - | 1782502797 | **REQUIRED** — آخر تعديل |
| `version` | integer | - | 1 | **REQUIRED** — الإصدار |
| `origin` | string | 6/50 | "server" | **REQUIRED** — المصدر |
| `vectorClock` | string | 2/2000 | "{}" | **REQUIRED** — ساعة المتجهات |

### الحقول الاختيارية (OPTIONAL) على Cloud

| الحقل | النوع | الطول | مثال | ملاحظة |
|-------|------|------|------|--------|
| `expenseId` | integer? | - | 629 | معرف المصروف المرتبط |
| `note` | string? | 7/1000 | NULL | ملاحظة المستخدم (من description) |
| `name` | string? | 0/255 | NULL | اسم (غير مُستخدم حالياً) |
| `serverId` | integer? | - | NULL | معرف السيرفر |
| `deletedAt` | integer? | - | NULL | تاريخ الحذف الناعم |
| `createdAtIso` | string? | 0/50 | NULL | تاريخ ISO للإنشاء |
| `updatedAtIso` | string? | 0/50 | NULL | تاريخ ISO للتحديث |
| `deletedAtIso` | string? | 0/50 | NULL | تاريخ ISO للحذف |
| `createdAtEpoch` | integer? | - | 1782502797 | epoch الإنشاء |
| `lastModifiedEpoch` | integer? | - | 1782502797 | epoch التعديل |
| `syncTimestamp` | integer? | - | 1782502855 | طابع زمني للمزامنة |
| `deviceId` | string? | 0/255 | NULL | معرف الجهاز |
| `reason` | string? | 7/500 | "exp_629" | سبب السحب |
| `hotelDayKey` | string? | 10/50 | "2026-06-26" | مفتاح يوم الفندق |
| `withdrawalType` | string? | 8/30 | "سحب راتب" | نوع السحب |
| `description` | string? | 0/5000 | NULL | وصف إضافي |
| `employeeUuid` | string? | 32/255 | "3fff6cd4..." | UUID الموظف (للربط عبر الأجهزة) |
| `employeeLocalUuid` | string? | 0/128 | NULL | UUID الموظف المحلي |
| `sync_origin` | string? | 6/64 | "mobile" | مصدر المزامنة |

### حقول Appwrite التلقائية (لا تُرسل من الكود)

| الحقل | الوصف |
|-------|--------|
| `$id` | معرف المستند التلقائي |
| `$createdAt` | تاريخ الإنشاء التلقائي |
| `$updatedAt` | تاريخ التحديث التلقائي |

---

## 📐 الفهارس (Indexes)

| # | الاسم | الحقول |
|---|-------|--------|
| 1 | `idx_salary_withdrawals_employee` | `employee_id` |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول الأساسية (محلياً)** | 10 حقول |
| **إجمالي حقول المزامنة (محلياً)** | 14 حقل |
| **إجمالي الحقول على Cloud** | 30+ حقل |
| **إجمالي السجلات على Cloud** | 371+ سجل |

---

## 🔄 خرائط التحويل (Field Mapping)

### من المحلي → Cloud (Push via `toJson`)

| الحقل المحلي | الحقل على Cloud | ملاحظة |
|-------------|----------------|--------|
| `withdrawDate` | `withdrawDate` | مباشر |
| `withdrawDate` | `date` | **احتياطي** (legacy) |
| `withdrawalType` | `withdrawalType` | مباشر |
| `withdrawalType` | `action` | **احتياطي** (legacy) |
| `description` | `description` | مباشر |
| `description` | `note` | **احتياطي** (ملاحظة المستخدم) |
| `reason` | `reason` | مباشر (مثل "exp_629") |
| `reason` → extract | `expenseId` | استخراج الرقم من "exp_XXX" |
| `origin` | `origin` | مباشر |
| `origin` | `sync_origin` | **احتياطي** (snake_case) |
| `employeeId` (FK) | `employeeId` | مباشر |
| — (يُضاف في sync_manager) | `employeeUuid` | UUID الموظف للربط عبر الأجهزة |
| — (يُضاف في sync_manager) | `employeeLocalUuid` | UUID الموظف المحلي |
| `amount` (double) | `amount` (integer) | **تحويل النوع**: double → int via `.round()` |

### من Cloud → المحلي (Pull via `fromJson`)

| الحقل على Cloud | الحقل المحلي | ملاحظة |
|----------------|-------------|--------|
| `withdrawDate` | `withdrawDate` | مباشر |
| `date` (legacy) | `withdrawDate` | احتياطي إذا `withdrawDate` فارغ |
| `withdrawalType` | `withdrawalType` | مباشر |
| `action` (legacy) | `withdrawalType` | احتياطي |
| `description` | `description` | مباشر |
| `note` (legacy) | `description` | احتياطي |
| `reason` | `reason` | مباشر |
| `expenseId` | `reason` | تحويل لـ "exp_XXX" للتوافق |
| `amount` (integer) | `amount` (double) | تحويل النوع: int → double |
| `employeeUuid` | `employeeId` (FK) | حل عبر `IdResolver.resolveEmployee` |

---

## ⚠️ أخطاء شائعة وحلولها

### خطأ: `Missing required attribute "withdrawDate"` (400)

**السبب:** `_filterPayload` كان يحذف `withdrawDate` لأنه لم يكن مُدرجاً في `validFieldsPerCollection`.

**الحل:** تم إضافة `withdrawDate`, `withdrawalType`, `description`, `hotelDayKey`, `reason` إلى `validFieldsPerCollection['salary_withdrawals']` في `appwrite_sync_utils.dart`.

### خطأ: `document_invalid_structure` (400)

**السبب:** إرسال حقول غير موجودة في مخطط Cloud.

**الحل:** `_filterPayload` يحتفظ فقط بالحقول المُدرجة في `validFieldsPerCollection`.

---

## 📝 ملاحظات

- جدول `salary_withdrawals` يُستخدم لتسجيل **سحب مبالغ من رواتب الموظفين**
- مرتبط بجدول `employees` عبر `employeeId`
- يمكن ربطه بجدول `expenses` عبر `expenseId` (يُستخرج من `reason` بصيغة "exp_XXX")
- `note` = ملاحظة المستخدم (من `description`)، **لا يُخلط مع `reason`**
- `reason` = سبب السحب (مثل "exp_629" للربط مع المصروف)
- `amount` على Cloud هو `integer`، محلياً `double` — يتم التحويل عبر `.round()`
- الحقول الاحتياطية (`date`, `action`, `note`) تُرسل دائماً للتوافق مع جميع إصدارات المخطط

---

## 📁 الملفات المتعلقة

| الملف | المسار | الوظيفة |
|-------|--------|---------|
| Salary Withdrawals Adapter | `lib/services/adapters/salary_withdrawals_adapter.dart` | تحويل البيانات بين المحلي و Cloud |
| Local DB Schema | `lib/services/local_db.dart` | تعريف جدول `SalaryWithdrawals` |
| Sync Utils | `lib/services/appwrite_sync_utils.dart` | `validFieldsPerCollection` + `filterPayloadForCollection` |
| Sync Manager | `lib/services/appwrite_sync_manager.dart` | `_processSalaryWithdrawalEntry` + إضافة `employeeUuid` |

---

## 📜 سجل التغييرات

| التاريخ | Commit | التغيير |
|---------|--------|---------|
| 2026-06-27 | `6ca530e4` | إضافة `withdrawDate`, `withdrawalType`, `description`, `hotelDayKey`, `reason` إلى `validFieldsPerCollection` |
| 2026-06-27 | `924df4bf` | إرسال `date`, `action`, `note` كاحتياطي دائماً (لكل المصادر) |
| 2026-06-27 | `dd08b739` | تصحيح: `note = description` فقط (ملاحظة المستخدم)، `reason` مستقل |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**آخر تحديث:** 2026-06-27
