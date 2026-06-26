# 📋 تقرير مزامنة جدول Employees - Appwrite Cloud vs الكود المحلي

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
| **Collection ID** | `employees` |

---

## 📊 الحقول الفعلية على Appwrite Cloud

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | Required | Default | الوصف |
|---|-------|------|----------|---------|-------|
| 1 | `localUuid` | `string(100)` | ✅ | - | UUID فريد (Document ID) |
| 2 | `name` | `string(100)` | ✅ | - | اسم الموظف |
| 3 | `basicSalary` | `double` | ✅ | - | الراتب الأساسي |
| 4 | `position` | `string(50)` | ❌ | `"موظف"` | المنصب/الوظيفة |
| 5 | `phone` | `string(20)` | ❌ | `""` | رقم الهاتف |
| 6 | `hireDate` | `string(50)` | ❌ | `""` | تاريخ التعيين |
| 7 | `status` | `string(20)` | ✅ | - | الحالة |

### 📋 حقول الإنهاء

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 8 | `terminationDate` | `string(50)` | ❌ | - |
| 9 | `terminationReason` | `string(200)` | ❌ | - |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Required | Default |
|---|-------|------|----------|---------|
| 10 | `serverId` | `integer` | ❌ | - |
| 11 | `createdAt` | `integer` | ✅ | - |
| 12 | `updatedAt` | `integer` | ✅ | - |
| 13 | `deletedAt` | `integer` | ❌ | - |
| 14 | `lastModified` | `integer` | ✅ | - |
| 15 | `origin` | `string(50)` | ❌ | `"local"` |
| 16 | `createdAtIso` | `string(50)` | ❌ | - |
| 17 | `updatedAtIso` | `string(50)` | ❌ | - |
| 18 | `deletedAtIso` | `string(50)` | ❌ | - |
| 19 | `createdAtEpoch` | `integer` | ❌ | `0` |
| 20 | `lastModifiedEpoch` | `integer` | ❌ | `0` |
| 21 | `vectorClock` | `string(500)` | ❌ | `"{}"` |
| 22 | `version` | `integer` | ❌ | `1` |
| 23 | `deviceId` | `string(100)` | ❌ | `""` |
| 24 | `id` | `integer` | ❌ | - |
| 25 | `syncTimestamp` | `integer` | ❌ | `0` |
| 26 | `sync_origin` | `string(64)` | ❌ | `"mobile"` |

---

## 📐 الفهارس (Indexes)

| # | الاسم | النوع | الحقول |
|---|-------|-------|--------|
| 1 | `idxLocalUuid` | unique | `localUuid` |
| 2 | `idxName` | key | `name` |
| 3 | `idxStatus` | key | `status` |
| 4 | `idxPosition` | key | `position` |
| 5 | `idxHireDate` | key | `hireDate` |
| 6 | `idxTerminationDate` | key | `terminationDate` |
| 7 | `idxCreatedAt` | key | `createdAt` |
| 8 | `idxLastModified` | key | `lastModified` |
| 9 | `idx_local_uuid` | unique | `localUuid` |

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
| **إجمالي الحقول** | 26 حقل |
| **عدد الفهارس** | 9 index |

---

## ✅ مقارنة: الكود المحلي vs Appwrite Cloud

| الحقل | الكود المحلي | Appwrite Cloud | الحالة |
|-------|------------|----------------|--------|
| `localUuid` | ✅ | ✅ | ✅ مطابق |
| `name` | ✅ | ✅ | ✅ مطابق |
| `basicSalary` | ✅ | ✅ | ✅ مطابق |
| `position` | ✅ | ✅ | ✅ مطابق |
| `phone` | ✅ | ✅ | ✅ مطابق |
| `hireDate` | ✅ | ✅ | ✅ مطابق |
| `status` | ✅ | ✅ | ✅ مطابق |
| `terminationDate` | ✅ | ✅ | ✅ مطابق |
| `terminationReason` | ✅ | ✅ | ✅ مطابق |
| `serverId` | ✅ | ✅ | ✅ مطابق |
| `createdAt` | ✅ | ✅ | ✅ مطابق |
| `updatedAt` | ✅ | ✅ | ✅ مطابق |
| `deletedAt` | ✅ | ✅ | ✅ مطابق |
| `lastModified` | ✅ | ✅ | ✅ مطابق |
| `origin` | ✅ | ✅ | ✅ مطابق |
| `createdAtIso` | ✅ | ✅ | ✅ مطابق |
| `updatedAtIso` | ✅ | ✅ | ✅ مطابق |
| `deletedAtIso` | ✅ | ✅ | ✅ مطابق |
| `createdAtEpoch` | ✅ | ✅ | ✅ مطابق |
| `lastModifiedEpoch` | ✅ | ✅ | ✅ مطابق |
| `vectorClock` | ✅ | ✅ | ✅ مطابق |
| `version` | ✅ | ✅ | ✅ مطابق |
| `deviceId` | ✅ | ✅ | ✅ مطابق |
| `id` | ✅ | ✅ | ✅ مطابق |
| `syncTimestamp` | ✅ | ✅ | ✅ مطابق |
| `sync_origin` | ✅ | ✅ | ✅ مطابق |

---

## 📝 ملاحظات

- جدول `employees` **مطابق 100%** بين الكود المحلي و Appwrite Cloud
- لا توجد حقول مفقودة أو إضافية
- جميع حقول المزامنة موجودة ومتسقة

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Employees Adapter | `lib/services/adapters/employees_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
