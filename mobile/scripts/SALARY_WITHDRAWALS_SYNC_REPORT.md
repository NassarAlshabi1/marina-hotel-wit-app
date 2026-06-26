# 📋 تقرير مزامنة جدول Salary Withdrawals - الكود المحلي

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
| **Collection ID** | `salary_withdrawals` |

---

## 📊 الحقول الفعلية في الكود المحلي

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | الوصف |
|---|-------|------|-------|
| 1 | `id` | `integer` | معرف محلي (autoIncrement) |
| 2 | `localUuid` | `string` | UUID فريد عالمياً |
| 3 | `employeeId` | `integer` | FK إلى الموظف |
| 4 | `amount` | `double` | المبلغ المسحوب |
| 5 | `withdrawDate` | `string` | تاريخ السحب |
| 6 | `reason` | `string?` | سبب السحب |
| 7 | `hotelDayKey` | `string?` | مفتاح يوم الفندق |
| 8 | `withdrawalType` | `string?` | نوع السحب |
| 9 | `description` | `string?` | وصف إضافي |
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

## 📐 الفهارس (Indexes)

| # | الاسم | الحقول |
|---|-------|--------|
| 1 | `idx_salary_withdrawals_employee` | `employee_id` |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول الأساسية** | 10 حقول |
| **إجمالي حقول المزامنة** | 14 حقل |
| **المجموع** | **24 حقل** |

---

## 📝 ملاحظات

- جدول `salary_withdrawals` يُستخدم لتسجيل **سحب مبالغ من رواتب الموظفين**
- مرتبط بجدول `employees` عبر `employeeId`
- يمكن ربطه بجدول `expenses` عبر `expenseId`

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Salary Withdrawals Adapter | `lib/services/adapters/salary_withdrawals_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
