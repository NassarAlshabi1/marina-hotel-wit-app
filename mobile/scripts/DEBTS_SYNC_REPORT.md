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
# 📋 تقرير مزامنة جدول Debts - الكود المحلي

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
| **Collection ID** | `debts` |

---

## 📊 الحقول الفعلية في الكود المحلي

### 🏠 الحقول الأساسية (Basic Attributes)

| # | الحقل | النوع | Default | الوصف |
|---|-------|------|---------|-------|
| 1 | `id` | `integer` | - | معرف محلي (autoIncrement) |
| 2 | `localUuid` | `string` | - | UUID فريد عالمياً |
| 3 | `bookingLocalId` | `integer?` | - | FK إلى الحجز |
| 4 | `guestName` | `string` | - | اسم النزيل |
| 5 | `checkinDate` | `string` | - | تاريخ تسجيل الدخول |
| 6 | `checkoutDate` | `string` | - | تاريخ تسجيل الخروج |
| 7 | `dateRecorded` | `string` | `""` | تاريخ التسجيل |
| 8 | `debtReason` | `string` | `""` | سبب الدين |
| 9 | `totalAmount` | `double` | - | المبلغ الإجمالي |
| 10 | `paidAmount` | `double` | - | المبلغ المدفوع |
| 11 | `remainingAmount` | `double` | - | المبلغ المتبقي |
| 12 | `paymentDate` | `string` | - | تاريخ الدفع |
| 13 | `isSettled` | `integer` | `0` | هل تم تسديد الدين (0/1) |
| 14 | `pledge` | `string?` | - | الرهن |
| 15 | `pledgeType` | `string?` | - | نوع الرهن |
| 16 | `note` | `string?` | - | ملاحظات |
| 17 | `debtUuid` | `string?` | - | UUID الدين |
| 18 | `hotelDayOpened` | `string?` | - | يوم الفندق للفتح |
| 19 | `hotelDayClosed` | `string?` | - | يوم الفندق للإغلاق |
| 20 | `isFromAutoFix` | `boolean` | `false` | من الإصلاح التلقائي |
| 21 | `settlementConfirmed` | `boolean` | `false` | تأكيد التسديد |

### 🔗 المفاتيح الأجنبية

| الحقل | يربط إلى |
|-------|----------|
| `bookingLocalId` | `Bookings.id` |

### 🔄 حقول المزامنة (Sync Fields)

| # | الحقل | النوع | Default |
|---|-------|------|---------|
| 22 | `serverId` | `integer?` | - |
| 23 | `createdAt` | `integer` | - |
| 24 | `updatedAt` | `integer` | - |
| 25 | `deletedAt` | `integer?` | - |
| 26 | `lastModified` | `integer` | - |
| 27 | `origin` | `string` | `"local"` |
| 28 | `createdAtIso` | `string?` | - |
| 29 | `updatedAtIso` | `string?` | - |
| 30 | `deletedAtIso` | `string?` | - |
| 31 | `createdAtEpoch` | `integer` | `0` |
| 32 | `lastModifiedEpoch` | `integer` | `0` |
| 33 | `version` | `integer` | `1` |
| 34 | `vectorClock` | `string` | `"{}"` |
| 35 | `deviceId` | `string` | `""` |

---

## 📐 الفهارس (Indexes)

| # | الاسم | الحقول |
|---|-------|--------|
| 1 | `idx_debts_status` | `is_settled, is_from_auto_fix` |

---

## 📊 إحصائيات الجدول

| البند | القيمة |
|-------|-------|
| **إجمالي الحقول الأساسية** | 21 حقل |
| **إجمالي حقول المزامنة** | 14 حقل |
| **المجموع** | **35 حقل** |
| **عدد الفهارس** | 1 index |

---

## 📝 ملاحظات

- جدول `debts` يُستخدم لتسجيل **ديون النزلاء** عند تسجيل الخروج
- مرتبط بالحجز عبر `bookingLocalId`
- يحتوي على:
  - المبلغ الإجمالي والمدفوع والمتبقي
  - تاريخ الدفع
  - حالة التسديد (`isSettled`)
  - الرهون (`pledge`, `pledgeType`)
- يمكن أن يُنشأ تلقائياً عبر `AutoFix`

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Debts Adapter | `lib/services/adapters/debts_adapter.dart` |
| Local DB Schema | `lib/services/local_db.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
