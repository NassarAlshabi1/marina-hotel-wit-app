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
# 📋 تقرير مزامنة جدول Guest Infos - الكود المحلي

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
| **Collection ID** | `guest_infos` |

---

## 📊 الحقول الفعلية في الكود المحلي

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | Default | الوصف |
|---|-------|------|---------|-------|
| 1 | `id` | `integer` | - | معرف محلي (autoIncrement) |
| 2 | `localUuid` | `string` | - | UUID فريد عالمياً |
| 3 | `roomNumber` | `string` | - | رقم الغرفة |
| 4 | `guestName` | `string` | - | اسم النزيل |
| 5 | `nationality` | `string` | - | الجنسية |
| 6 | `idNumber` | `string` | - | رقم الهوية |
| 7 | `idType` | `string` | `"بطاقة شخصية"` | نوع الهوية |
| 8 | `issueDate` | `string?` | - | تاريخ إصدار الهوية |
| 9 | `issuePlace` | `string?` | - | مكان إصدار الهوية |
| 10 | `governorate` | `string?` | - | المحافظة |
| 11 | `notes` | `string?` | - | ملاحظات |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Default |
|---|-------|------|---------|
| 12 | `serverId` | `integer?` | - |
| 13 | `createdAt` | `integer` | - |
| 14 | `updatedAt` | `integer` | - |
| 15 | `deletedAt` | `integer?` | - |
| 16 | `lastModified` | `integer` | - |
| 17 | `origin` | `string` | `"local"` |
| 18 | `createdAtIso` | `string?` | - |
| 19 | `updatedAtIso` | `string?` | - |
| 20 | `deletedAtIso` | `string?` | - |
| 21 | `createdAtEpoch` | `integer` | `0` |
| 22 | `lastModifiedEpoch` | `integer` | `0` |
| 23 | `version` | `integer` | `1` |
| 24 | `vectorClock` | `string` | `"{}"` |
| 25 | `deviceId` | `string` | `""` |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول الأساسية** | 11 حقول |
| **إجمالي حقول المزامنة** | 14 حقل |
| **المجموع** | **25 حقل** |

---

## 📝 ملاحظات

- جدول `guest_infos` يُستخدم لتخزين **معلومات النزلاء** (هوية، جنسية، etc.)
- مرتبط بالغرفة عبر `roomNumber`
- يحتوي على بيانات الهوية (رقم، نوع، تاريخ إصدار، مكان إصدار)
- **ملاحظة:** هذا الجدول منفصل عن جدول `bookings` - قد يكون مكرراً للبيانات

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Guest Infos Adapter | `lib/services/adapters/guest_infos_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
