# 🧠 مرجع ذاكرة المشروع - Marina Hotel Mobile

**تاريخ الإنشاء:** 2026-06-27  
**آخر تحديث:** 2026-06-27  
**المسار:** `mobile/scripts/memory/`  
**الغرض:** مرجع شامل لكل القرارات المعمارية، الإصلاحات، والأنماط المتفق عليها

---

## 📋 فهرس المراجع

1. [بنية المشروع](#1-بنية-المشروع)
2. [نظام المزامنة](#2-نظام-المزامنة)
3. [قاعدة بيانات outbox](#3-قاعدة-بيانات-outbox)
4. [validFieldsPerCollection](#4-validfieldspercollection)
5. [الوجهة الثانوية Secondary Sync](#5-الوجهة-الثانوية-secondary-sync)
6. [Failover التلقائي](#6-failover-التلقائي)
7. [Appwrite Cloud Schema](#7-appwrite-cloud-schema)
8. [أنماط الكود المتفق عليها](#8-أنماط-الكود-المتفق-عليها)
9. [الأخطاء الشائعة وحلولها](#9-الأخطاء-الشائعة-وحلولها)
10. [التقارير المتوفرة](#10-التقارير-المتوفرة)
11. [سجل الالتزامات المهمة](#11-سجل-الالتزامات-المهمة)
12. [قواعد ذهبية](#12-قواعد-ذهبية)

---

## 1. بنية المشروع

### معلومات أساسية
- **المستودع:** `https://github.com/NassarAlshabi1/marina-hotel-wit-app`
- **الفرع النشط:** `marina`
- **Database ID:** `hotel_db`
- **Project ID:** `690ff0da0025518570c1`
- **Endpoint:** `https://fra.cloud.appwrite.io/v1`

### التقنيات
- **Flutter:** 3.35.7 (stable)
- **Dart:** 3.9.2
- **Drift:** 2.28.0 (قاعدة البيانات المحلية)
- **Appwrite SDK:** 21.0.0
- **Riverpod:** 2.6.1 (إدارة الحالة)
- **build_runner:** 2.4.13

### البنية المعمارية
```
mobile/
├── lib/
│   ├── main.dart                    ← نقطة الدخول
│   ├── components/                  ← مكوّنات UI مشتركة
│   ├── providers/                   ← Riverpod providers
│   ├── screens/                     ← شاشات التطبيق
│   ├── services/
│   │   ├── adapters/                ← محولات البيانات (Local ↔ Cloud)
│   │   ├── daos/                    ← كائنات الوصول للبيانات
│   │   ├── repositories/            ← المستودعات
│   │   ├── sync_core/               ← نواة المزامنة
│   │   ├── local_db.dart            ← تعريف قاعدة البيانات (Drift)
│   │   ├── appwrite_sync_manager.dart   ← مدير المزامنة الرئيسي
│   │   ├── appwrite_delta_sync.dart     ← المزامنة التفاضلية
│   │   ├── appwrite_sync_utils.dart     ← أدوات التصفية والتحويل
│   │   ├── appwrite_service.dart        ← خدمة Appwrite الأساسية
│   │   ├── appwrite_health_checker.dart ← فاحص صحة الوجهتين
│   │   ├── secondary_appwrite_config.dart  ← إعدادات الوجهة الثانوية
│   │   ├── secondary_appwrite_service.dart ← خدمة الوجهة الثانوية
│   │   └── secondary_sync_manager.dart    ← مدير المزامنة الثانوية
│   ├── sync/
│   │   └── providers/
│   │       └── sync_providers.dart  ← Riverpod providers للمزامنة
│   └── widgets/                     ← عناصر UI
└── scripts/                         ← سكربتات وتقارير
    ├── memory/                      ← هذا المرجع
    ├── appwrite_schema.py           ← مخطط Appwrite
    └── *_SYNC_REPORT.md             ← تقارير المزامنة لكل جدول
```

---

## 2. نظام المزامنة

### المكونات الرئيسية

| المكوّن | الملف | الوظيفة |
|---------|------|--------|
| **AppwriteSyncManager** | `appwrite_sync_manager.dart` | المدير الرئيسي للـ push/pull |
| **AppwriteDeltaSync** | `appwrite_delta_sync.dart` | مزامنة تفاضلية (التغييرات فقط) |
| **AppwriteRealtimeSync** | `appwrite_realtime_sync.dart` | مزامنة لحظية عبر Realtime |
| **AppwriteService** | `appwrite_service.dart` | عميل Appwrite SDK للـ CRUD |
| **AppwriteSyncUtils** | `appwrite_sync_utils.dart` | `validFieldsPerCollection` + `sanitizePayload` |
| **OutboxDao** | `daos/outbox_dao.dart` | إدارة جدول outbox |
| **AdapterRegistry** | `adapters/adapter_registry.dart` | تسجيل المحولات لكل كيان |

### تدفّق المزامنة

```
┌─────────────────────────────────────────────────────────────┐
│  تغيير محلي (إنشاء/تعديل/حذف)                              │
│       ↓                                                     │
│  DAO → outbox.merge()  (يضيف سجل لـ outbox)                │
│       ↓                                                     │
│  AppwriteSyncManager._pushAllEntities()                    │
│       ↓                                                     │
│  outboxDao.takeBatch()  (يأخذ سجلات غير مُسلّمة للرئيسي)   │
│       ↓                                                     │
│  _processOutboxEntry() → _processBookingEntry() etc.       │
│       ↓                                                     │
│  _bookingToRemote() / adapter.toJson()  (تحويل لـ Map)     │
│       ↓                                                     │
│  AppwriteSyncUtils.sanitizePayload()  (تصفية + تحويل)      │
│       ↓                                                     │
│  filterPayloadForCollection()  (إبقاء الحقول الصالحة فقط)  │
│       ↓                                                     │
│  appwriteService.upsertBooking()  (إرسال لـ Appwrite)      │
│       ↓                                                     │
│  outboxDao.markDeliveredToPrimary()  (وضع علامة تسليم)     │
│       ↓                                                     │
│  إذا delivered_to_primary && delivered_to_secondary → حذف  │
└─────────────────────────────────────────────────────────────┘
```

---

## 3. قاعدة بيانات outbox

### الحقول (Schema v44)

| الحقل | النوع | الوصف |
|------|------|--------|
| `id` | integer (PK) | معرف تلقائي |
| `entity` | string | اسم الكيان (bookings, payments, etc.) |
| `op` | string | العملية (create, update, delete) |
| `localUuid` | string | UUID المحلي |
| `serverId` | integer? | معرف السيرفر |
| `payload` | string (JSON) | بيانات العملية |
| `clientTs` | integer | طابع زمني للعميل |
| `attempts` | integer | عدد المحاولات |
| `lastError` | string? | آخر خطأ |
| `idempotencyKey` | string? | مفتاح Idempotency |
| `processingStatus` | string | pending/processing/completed/failed |
| `processingStartedAt` | integer? | وقت بدء المعالجة |
| `processingWorker` | string? | معرف العامل |
| `source` | string | 'local' أو 'restore' |
| `deliveredToPrimary` ✅ | boolean | تم التسليم للرئيسي |
| `deliveredToSecondary` ✅ | boolean | تم التسليم للثانوي |

### القاعدة الذهبية لتسليم outbox

> **السجل يُحذف فقط بعد نجاح كلا الوجهتين (Primary + Secondary)**

```
delivered_to_primary = true  AND  delivered_to_secondary = true  →  🗑️ حذف تلقائي
delivered_to_primary = true  AND  delivered_to_secondary = false →  ⏳ ينتظر Secondary
delivered_to_primary = false AND  delivered_to_secondary = true  →  ⏳ ينتظر Primary
delivered_to_primary = false AND  delivered_to_secondary = false →  ⏳ ينتظر كلاهما
```

### الدوال الرئيسية في OutboxDao

| الدالة | الوظيفة |
|--------|--------|
| `merge()` | إضافة/تحديث سجل في outbox |
| `takeBatch()` | أخذ سجلات غير مُسلّمة للرئيسي (atomic UPDATE...RETURNING) |
| `markDeliveredToPrimary(id)` | وضع علامة تسليم للرئيسي + حذف تلقائي إذا اكتمل |
| `markDeliveredToSecondary(id)` | وضع علامة تسليم للثانوي + حذف تلقائي إذا اكتمل |
| `markAllLocalAsUndeliveredToSecondary()` | تعليم كل السجلات كـ "غير مُسلّمة للثانوي" (عند تفعيل Secondary) |
| `markAllLocalAsDeliveredToSecondary()` | تعليم كل السجلات كـ "مُسلّمة للثانوي" (عند تعطيل Secondary) |
| `setError()` | تسجيل خطأ على سجل |
| `markCompleted()` | تعليم سجلات كمكتملة |
| `retryFailed()` | إعادة محاولة السجلات الفاشلة |

---

## 4. validFieldsPerCollection

### الموقع
`lib/services/appwrite_sync_utils.dart` → `AppwriteSyncUtils.validFieldsPerCollection`

### الوظيفة
خريطة (Map) تحدد الحقول الصالحة لكل مجموعة على Appwrite Cloud.  
أي حقل غير موجود في هذه القائمة يُحذف تلقائياً بواسطة `filterPayloadForCollection` قبل الإرسال.

### سلسلة الاستدعاءات
```
_processBookingEntry() / _processPaymentEntry() / etc.
  ↓
_bookingToRemote() / _paymentToRemote() / etc.
  ↓
AppwriteSyncUtils.sanitizePayload(entity, payload, collectionId)
  ↓ (الخطوة 7)
filterPayloadForCollection(collectionId, result)
  ↓
validFieldsPerCollection[collectionId]  ← ✅ المصدر الوحيد للحقيقة
```

### القواعد

1. **كل حقل على Cloud يجب أن يكون مُدرجاً** — وإلا يُحذف قبل الإرسال
2. **لا تُدرج حقول غير موجودة على Cloud** — ستسبب `document_invalid_structure`
3. **الحقول camelCase هي الأساس** — `createdAt` وليس `created_at`
4. **الحقول Legacy snake_case تُدرج للقراءة فقط** — مثل `created_at`, `vector_clock`
5. **❌ لا تستخدم `sync_version` أو `sync_vector_clock`** — استخدم `version` و `vectorClock`

### المجموعات المُحدّثة (2026-06-27)

| المجموعة | عدد الحقول | حالة |
|---------|-----------|------|
| `rooms` | 28 | ✅ مكتمل |
| `payments` | 38 | ✅ مكتمل |
| `bookings` | 39 | ✅ مكتمل |
| `expenses` | 28 | ✅ مكتمل |
| `employees` | 24 | ✅ مكتمل |
| `debts` | 43 | ✅ مكتمل |
| `booking_notes` | 24 | ✅ مكتمل |
| `booking_nights` | 23 | ✅ مكتمل |
| `cash_transactions` | 31 | ✅ مكتمل |
| `shift_notes` | 34 | ✅ مكتمل |
| `salary_cycles` | 25 | ✅ مكتمل |
| `salary_payments` | 30 | ✅ مكتمل |
| `salary_withdrawals` | 33 | ✅ مكتمل |
| `salary_carry_over_logs` | 23 | ✅ مكتمل |
| `blacklist` | 25 | ✅ مكتمل |
| `price_adjustments` | 27 | ✅ مكتمل |
| `booking_price_adjustments` | 32 | ✅ مكتمل |
| `audit_logs` | 24 | ✅ مكتمل |
| `payment_voids` | 40+ | ✅ مكتمل |
| `guest_infos` | 27 | ✅ مكتمل |
| `app_settings` | 50+ | ✅ مكتمل |

---

## 5. الوجهة الثانوية Secondary Sync

### الفلسفة التصميمية

> **outbox مشترك بين Primary و Secondary — لا فقدان بيانات، لا تكرار**

```
outbox (مصدر واحد)
   ├── delivered_to_primary → AppwriteSyncManager (Primary)
   └── delivered_to_secondary → SecondarySyncManager (Secondary)
```

### الملفات

| الملف | الوظيفة |
|------|--------|
| `secondary_appwrite_config.dart` | إعدادات SharedPreferences |
| `secondary_appwrite_service.dart` | عميل Appwrite SDK للثانوي |
| `secondary_sync_manager.dart` | مدير المزامنة (singleton) |
| `secondary_sync_provider.dart` | Riverpod state |
| `secondary_appwrite_settings_screen.dart` | شاشة الإعدادات |

### الإعدادات

| الإعداد | المفتاح | الافتراضي |
|---------|---------|----------|
| تفعيل Secondary | `secondary_appwrite_enabled` | `false` |
| Endpoint | `secondary_appwrite_endpoint` | `''` |
| Project ID | `secondary_appwrite_project_id` | `''` |
| Database ID | `secondary_appwrite_database_id` | `''` |
| API Key | `secondary_appwrite_api_key` | `''` |
| Push مُفعّل | `secondary_appwrite_push_enabled` | `true` |
| Pull مُفعّل | `secondary_appwrite_pull_enabled` | `false` |
| آخر مزامنة | `secondary_appwrite_last_sync` | `null` |

### المنطق

- **Push:** يستخدم `_takeUndeliveredBatch` (سجلات `delivered_to_secondary = 0`)
- **Pull:** غير مُدعوم في هذه النسخة (Failover فقط)
- **المزامنة التلقائية:** كل 15 دقيقة (إذا Push مُفعّل)
- **عند التفعيل:** `markAllLocalAsUndeliveredToSecondary()` لرفع كل السجلات القديمة
- **عند التعطيل:** `markAllLocalAsDeliveredToSecondary()` لمنع حجب السجلات

---

## 6. Failover التلقائي

### الملفات

| الملف | الوظيفة |
|------|--------|
| `appwrite_health_checker.dart` | فحص صحة Primary و Secondary كل 30 ثانية |
| `appwrite_service.dart` | `listDocumentsWithFailover` + `_listFromSecondary` |

### الحالات

| الحالة | المعنى |
|--------|--------|
| `unknown` | لم يُفحص بعد |
| `healthy` | الوجهة تعمل |
| `unreachable` | الوجهة لا تستجيب |
| `authError` | خطأ مصادقة (401/403) |
| `configError` | خطأ في الإعدادات |

### متى يُفعّل Failover؟

```
shouldFailover = (primaryHealth == unreachable) && (secondaryHealth == healthy)
```

### تدفّق Failover

```dart
// في _listAllDocumentsInternal:
try {
  // محاولة Primary
  return await _databases.listDocuments(...);
} catch (primaryError) {
  // إذا فشل Primary و Secondary مُفعّل للسحب (Pull)
  if (SecondaryAppwriteConfig.isEnabled &&
      SecondaryAppwriteConfig.isPullEnabled &&
      SecondaryAppwriteConfig.isConfigured) {
    return await _listFromSecondary(...);  // Failover
  }
  rethrow;  // لا Failover متاح
}
```

### مؤشر Failover في UI
- شارة برتقالية "وضع طوارئ: قراءة من الثانوي" تظهر في `dashboard_sync_button.dart`

---

## 7. Appwrite Cloud Schema

### معلومات الاتصال
- **Endpoint:** `https://fra.cloud.appwrite.io/v1`
- **Region:** Frankfurt (fra)
- **Project ID:** `690ff0da0025518570c1`
- **Database ID:** `hotel_db`

### المجموعات (Collections)

| # | Collection ID | السجلات | الحقول |
|---|--------------|---------|--------|
| 1 | `rooms` | 20 | 28 |
| 2 | `bookings` | 215 | 39 |
| 3 | `payments` | 689 | 38 |
| 4 | `expenses` | 1199 | 28 |
| 5 | `employees` | - | 24 |
| 6 | `debts` | 4 | 43 |
| 7 | `booking_notes` | 0 | 24 |
| 8 | `booking_nights` | - | 23 |
| 9 | `cash_transactions` | 0 | 31 |
| 10 | `shift_notes` | 1 | 34 |
| 11 | `salary_cycles` | - | 25 |
| 12 | `salary_payments` | 0 | 30 |
| 13 | `salary_withdrawals` | 371 | 33 |
| 14 | `salary_carry_over_logs` | - | 23 |
| 15 | `blacklist` | - | 25 |
| 16 | `price_adjustments` | - | 27 |
| 17 | `booking_price_adjustments` | 56 | 32 |
| 18 | `audit_logs` | - | 24 |
| 19 | `payment_voids` | 4 | 40+ |
| 20 | `guest_infos` | 75 | 27 |
| 21 | `app_settings` | 1 | 50+ |
| 22 | `devices` | - | - |
| 23 | `sync_logs` | - | - |

### تحويل الأنواع (Type Conversions)

| الحقل | محلياً | على Cloud | التحويل |
|------|--------|----------|---------|
| `amount` (payments, expenses) | `double` | `integer` | `.round()` |
| `price` (rooms) | `double` | `integer` | `.round()` |
| `totalAmount` (debts) | `double` | `integer` | `.round()` |
| `paidAmount` (debts) | `double` | `integer` | `.round()` |
| `remainingAmount` (debts) | `double` | `integer` | `.round()` |
| `voidedAmount` (payment_voids) | `double` | `integer` | `.round()` |
| `discountAmount` (payments) | `double` | `integer` | `.round()` |

### حقول مطلوبة (REQUIRED) شائعة

كل مجموعة تحتوي على:
- `localUuid` (string) — UUID فريد
- `createdAt` (integer) — تاريخ الإنشاء
- `updatedAt` (integer) — تاريخ التحديث
- `lastModified` (integer) — آخر تعديل

---

## 8. أنماط الكود المتفق عليها

### 8.1 تسمية الحقول
- **camelCase** في الكود المحلي وفي Appwrite Cloud: `localUuid`, `createdAt`, `lastModified`
- **snake_case** للحقول Legacy فقط: `created_at`, `vector_clock`
- ❌ **لا تستخدم** `sync_version` أو `sync_vector_clock` — استخدم `version` و `vectorClock`

### 8.2 Adapter Pattern
كل جدول له adapter يحوّل بين المحلي و Cloud:
```dart
class BookingsAdapter extends EntityAdapter<Booking, BookingsCompanion> {
  @override
  Map<String, dynamic> toJson(Booking model, {required Source src}) {
    // تحويل المحلي → Cloud
  }

  @override
  BookingsCompanion fromJson(Map<String, dynamic> json, {required Source src, required ResolveResult refs}) {
    // تحويل Cloud → المحلي
  }
}
```

### 8.3 _processXxxEntry Pattern
```dart
Future<bool> _processBookingEntry(OutboxData entry) async {
  if (entry.op == 'delete') {
    await _deleteSilently(() => appwriteService.deleteBooking(entry.localUuid));
    return true;
  }
  final booking = await _getBookingByLocalUuid(entry.localUuid);
  if (booking == null) {
    await _deleteSilently(() => appwriteService.deleteBooking(entry.localUuid));
    return true;
  }
  final payload = _bookingToRemote(booking);
  await appwriteService.upsertBooking(booking.localUuid, _filterPayload('bookings', _addIdempotencyKey(payload, entry)));
  return true;
}
```

### 8.4 _xxxToRemote Pattern
```dart
Map<String, dynamic> _bookingToRemote(Booking booking) {
  final data = <String, dynamic>{
    // الحقول المطلوبة
    'roomNumber': booking.roomNumber,
    'localUuid': booking.localUuid,
    // ...
  };
  // الحقول الاختيارية
  _putIfNotNull(data, 'serverId', booking.serverId);
  _putIfStringNotEmpty(data, 'notes', booking.notes);
  // إرسال sync_origin و syncTimestamp
  _putIfStringNotEmpty(data, 'sync_origin', booking.origin);
  _putIfNotNull(data, 'syncTimestamp', booking.lastModified);
  return AppwriteSyncUtils.sanitizePayload('bookings', data, collectionId: AppwriteConfig.bookingsCollectionId);
}
```

### 8.5 Upsert Pattern (في AppwriteService)
```dart
// محاولة updateDocument أولاً (Optimistic)
// إذا 404 → createDocument
// إذا createDocument 409 (race) → updateDocument مرة أخرى
```

### 8.6 flutter analyze
- **الهدف:** `No issues found!` دائماً
- **القواعد المهمة:**
  - لا `unused_import`
  - لا `unused_local_variable`
  - استخدم `const` حيثما أمكن
  - استخدم `?? false` بدلاً من `== true` للقيم null bool

---

## 9. الأخطاء الشائعة وحلولها

### 9.1 `document_invalid_structure` (400)
**السبب:** إرسال حقل غير موجود على Cloud  
**الحل:** أضف الحقل إلى `validFieldsPerCollection[collectionId]`

### 9.2 `Missing required attribute "xxx"` (400)
**السبب:** حقل REQUIRED على Cloud لكنه غير مُرسل  
**الحل:** تأكد أن `_xxxToRemote` يُرسل الحقل + أنه مُدرج في `validFieldsPerCollection`

### 9.3 `document_already_exists` (409)
**السبب:** محاولة createDocument لمستند موجود بالفعل  
**الحل:** `_upsertDocumentInternal` يتكفّل بهذا (state machine مع fallback)

### 9.4 تكرار السجلات في الشاشات
**السبب السابق:** SecondarySyncManager كان يحذف سجلات outbox قبل وصولها للرئيسي  
**الحل:** نظام dual-delivery (delivered_to_primary + delivered_to_secondary)

### 9.5 فقدان بيانات عند فشل Secondary
**السبب السابق:** `removeById` بعد نجاح Secondary فقط  
**الحل:** `markDeliveredToSecondary` — السجل يُحذف فقط بعد نجاح كلا الوجهتين

### 9.6 `Connection reset by peer` / `Timeout`
**السبب:** مشكلة شبكة مؤقتة من Appwrite Cloud  
**الحل:** `withRetryAndTimeout` يعيد المحاولة 3 مرات (exponential backoff)

### 9.7 `attribute_not_found`
**السبب:** إرسال حقل غير موجود في مخطط Appwrite  
**الحل:** `_filterPayload` يحذفه تلقائياً (إذا لم يكن في `validFieldsPerCollection`)

---

## 10. التقارير المتوفرة

جميع التقارير في `mobile/scripts/`:

| التقرير | الوصف |
|---------|------|
| `ROOMS_SYNC_REPORT.md` | حقول جدول الغرف |
| `BOOKINGS_SYNC_REPORT.md` | حقول جدول الحجوزات |
| `PAYMENTS_SYNC_REPORT.md` | حقول جدول المدفوعات |
| `EXPENSES_SYNC_REPORT.md` | حقول جدول المصروفات |
| `DEBTS_SYNC_REPORT.md` | حقول جدول الديون |
| `BOOKING_NOTES_SYNC_REPORT.md` | حقول جدول ملاحظات الحجوزات |
| `CASH_TRANSACTIONS_SYNC_REPORT.md` | حقول جدول المعاملات النقدية |
| `SHIFT_NOTES_SYNC_REPORT.md` | حقول جدول ملاحظات الورديات |
| `SALARY_WITHDRAWALS_SYNC_REPORT.md` | حقول جدول سحوبات الرواتب |
| `SALARY_PAYMENTS_SYNC_REPORT.md` | حقول جدول دفعات الرواتب |
| `BOOKING_PRICE_ADJUSTMENTS_SYNC_REPORT.md` | حقول جدول تعديلات الأسعار |
| `PAYMENT_VOIDS_SYNC_REPORT.md` | حقول جدول إلغاء الدفعات |
| `GUEST_INFOS_SYNC_REPORT.md` | حقول جدول معلومات النزلاء |
| `APP_SETTINGS_SYNC_REPORT.md` | حقول جدول الإعدادات |
| `APPWRITE_SYNC_REPORTS_INDEX.md` | فهرس كل التقارير |

---

## 11. سجل الالتزامات المهمة

| التاريخ | Commit | الوصف |
|---------|--------|------|
| 2026-06-27 | `b46109aa` | نقطة الاستقرار (آخر حالة جيدة قبل Secondary) |
| 2026-06-27 | `857e1ef0` | إصلاح جذري لـ document_already_exists (409) في upsert |
| 2026-06-27 | `1dcdb64c` | تنظيف 23 تحذير flutter analyze → 0 |
| 2026-06-27 | `a2bfe471` | Secondary Sync مع dual-delivery outbox |
| 2026-06-27 | `f7ec48c0` | Failover تلقائي + خيارات Push/Pull منفصلة |
| 2026-06-27 | `6ca530e4` | إضافة `withdrawDate` لـ salary_withdrawals |
| 2026-06-27 | `924df4bf` | إرسال `date` كاحتياطي دائم لـ salary_withdrawals |
| 2026-06-27 | `dd08b739` | تصحيح: `note = description` فقط، `reason` مستقل |
| 2026-06-27 | `751774b0` | إضافة حقول bookings المفقودة (financialFrozenAt إلخ) |
| 2026-06-27 | `acb35bfe` | إضافة 30+ حقل لـ app_settings |
| 2026-06-27 | `245ccebf` | إنشاء validFieldsPerCollection['payments'] كاملة |
| 2026-06-27 | `0b8e9d6b` | إضافة حقول guest_infos و booking_price_adjustments |
| 2026-06-27 | `fe253fb7` | إضافة حقول debts و expenses |
| 2026-06-27 | `41541f38` | إزالة sync_version/sync_vector_clock + booking_notes/rooms/payment_voids |
| 2026-06-27 | `91a3c219` | إزالة نهائية لـ sync_version/sync_vector_clock + cash_transactions/shift_notes/salary_payments |
| 2026-06-27 | - | ✨ دمج Vector Clock في حل التعارضات: `_isRemoteDataNewer` يستخدم Vector Clock لكشف التعارضات المتزامنة (concurrent) + تسجيلها في sync_conflicts |

---

## 12. قواعد ذهبية

### 🥇 القاعدة #1: لا تلمس outbox من SecondarySyncManager مباشرة
استخدم `markDeliveredToSecondary()` فقط — لا تستخدم `removeById()`.  
الحذف يحدث تلقائياً بعد نجاح كلا الوجهتين.

### 🥈 القاعدة #2: كل حقل على Cloud يجب أن يكون في validFieldsPerCollection
أي حقل غير مُدرج يُحذف بواسطة `filterPayloadForCollection` قبل الإرسال.

### 🥉 القاعدة #3: لا تستخدم sync_version أو sync_vector_clock
استخدم `version` و `vectorClock` — هما الأسماء الصحيحة.

### 🏅 القاعدة #4: flutter analyze يجب أن يكون نظيفاً دائماً
الهدف: `No issues found!` — لا تحذيرات، لا أخطاء.

### 🎖️ القاعدة #5: استخدم Adapter Pattern لكل جدول
`adapter.toJson()` للتحويل المحلي → Cloud  
`adapter.fromJson()` للتحويل Cloud → محلي

### 🏆 القاعدة #6: استخدم _putIfNotNull و _putIfStringNotEmpty
لإرسال الحقول الاختيارية بدون إرسال null فارغ.

### 💎 القاعدة #7: اختبر ضد Appwrite Cloud الفعلي
لا تخمن الحقول — افحص Cloud مباشرة ووثّقها في تقارير `*_SYNC_REPORT.md`.

### 🌟 القاعدة #8: وثّق كل تغيير في سجل التغييرات
كل تقرير يجب أن يحتوي على جدول `سجل التغييرات` يربط التواريخ بالـ commits.

---

## 📝 ملاحظات نهائية

- **هذا المرجع** هو المصدر الوحيد للحقيقة لكل القرارات المعمارية
- **عند الإضافة:** حدّث هذا المرجع أولاً، ثم نفّذ الكود
- **عند الشك:** ارجع لهذا المرجع قبل اتخاذ أي قرار
- **عند التعديل:** أضف سجل تغييرات في الأسفل

---

## 📜 سجل تحديثات المرجع

| التاريخ | التحديث |
|---------|---------|
| 2026-06-27 | إنشاء المرجع الأولي بكل القرارات حتى Commit `91a3c219` |

---

**آخر تحديث:** 2026-06-27  
**المُنسق:** Marina Hotel Agent
