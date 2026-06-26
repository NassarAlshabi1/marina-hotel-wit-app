# 📋 تقرير مزامنة جدول Blacklist - الكود المحلي

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
| **Collection ID** | `blacklist` |

---

## 📊 الحقول الفعلية في الكود المحلي

### ⚠️ ملاحظة مهمة

جدول `blacklist` **ليس له جدول منفصل** في قاعدة البيانات المحلية.
يتم تخزين البيانات في جدول `shift_notes` مع `createdBy = 'blacklist'`

---

### 🏠 الحقول الأساسية (BlacklistEntry)

| # | الحقل | النوع | الوصف |
|---|-------|------|-------|
| 1 | `id` | `integer` | معرف محلي (من shift_notes) |
| 2 | `localUuid` | `string` | UUID فريد عالمياً |
| 3 | `name` | `string` | اسم الشخص المحظور |
| 4 | `nationality` | `string?` | الجنسية |
| 5 | `nationalId` | `string?` | رقم الهوية |
| 6 | `phone` | `string?` | رقم الهاتف |
| 7 | `reason` | `string?` | سبب الحظر |
| 8 | `notes` | `string?` | ملاحظات |
| 9 | `reportedBy` | `string` | مُبلّغ (default: `"police"`) |
| 10 | `active` | `boolean` | هل هو نشط (default: `true`) |
| 11 | `createdAt` | `DateTime` | تاريخ الإنشاء |

---

### 📦 التخزين الفعلي (shift_notes)

| الحقل | القيمة |
|-------|-------|
| `title` | اسم الشخص (`name`) |
| `content` | JSON payload (nationality, nationalId, phone, reason, notes, reportedBy, active) |
| `createdBy` | `"blacklist"` |
| `priority` | `"high"` |
| `shiftType` | `"all"` |
| `isRead` | `0` (غير مقروء) |
| `expiresAt` | `null` |

---

## 🔍 آلية المزامنة

### Push (الرفع إلى Cloud):
```dart
await _outboxDao.merge(
  entity: 'blacklist',
  op: 'create',  // أو 'update'
  localUuid: uuid,
  payload: {
    'name': ...,
    'nationality': ...,
    'nationalId': ...,
    'phone': ...,
    'reason': ...,
    'notes': ...,
    'reportedBy': ...,
    'active': ...,
    'createdAt': now,
    'lastModified': now,
    'origin': 'mobile',
  },
  clientTs: now,
);
```

### Pull (السحب من Cloud):
```dart
case 'blacklist':
  // في sync_pull_service.dart
```

---

## 🔐 الصلاحيات على Appwrite

```
read("any")
create("any")
update("any")
delete("any")
```

---

## 📝 ملاحظات

- **التخزين:** يتم تخزين القائمة السوداء في جدول `shift_notes` مع تمييز `createdBy = 'blacklist'`
- **البحث:** يستخدم خوارزمية مطابقة عربية ذكية (إزالة التشكيل، التطويق، إلخ)
- **التطابق:** الاسم الكامل أو أول 3 كلمات متطابقة
- **الحذف:** حذف ناعم (soft delete) via `deletedAt`

---

## 📁 الملفات المتعلقة

| الملف | المسار |
|-------|--------|
| Blacklist Repository | `lib/services/repositories/blacklist_repository.dart` |
| Blacklist Screen | `lib/screens/security/blacklist_screen.dart` |
| Sync Pull Service | `lib/services/sync_core/sync_pull_service.dart` |
| Sync Push Service | `lib/services/sync_core/sync_push_service.dart` |

---

**تم إنشاء هذا التقرير بواسطة:** OpenHands AI Agent  
**التاريخ:** 2026-06-26
