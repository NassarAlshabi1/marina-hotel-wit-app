# ملخص جلسة إصلاح أخطاء Appwrite Sync

**التاريخ:** 2026-03-07
**الفرع:** `feature/sync-reports-improvements`

---

## المشروع
تطبيق Flutter لإدارة فندق (Marina Hotel) مع مزامنة Appwrite

---

## المشاكل المحددة من السجلات

### المشكلة 1: Unknown attribute "rowHash"
```
Invalid document structure: Unknown attribute: "rowHash"
```
**السبب:** حقل `rowHash` يُرسل لـ Appwrite لكنه غير موجود في المخطط

**الحل:** إضافة `rowHash` و `row_hash` لقائمة الحقول المستثناة في `_sanitizePayload`

### المشكلة 2: Missing required attribute "created_at"
```
Invalid document structure: Missing required attribute "created_at"
```
**السبب:** تحويل snake_case إلى camelCase بينما Appwrite يتطلب snake_case

**الحل الجذري:** إزالة تحويل snake_case → camelCase وإبقاء الحقول كما هي

### المشكلة 3: Missing required attribute "id"
```
Invalid document structure: Missing required attribute "id"
```
**السبب:** collection `salary_withdrawals` تتطلب حقل `id` صريح

**الحل:** إضافة `id` تلقائياً داخل `_sanitizePayload` للجداول التي تتطلبه

---

## الملفات المعدلة

### `mobile/lib/services/appwrite_delta_sync.dart`

#### 1. دالة `_sanitizePayload` (السطر 804-867)
**قبل:**
```dart
// تحويل snake_case → camelCase
final camelKey = _toCamelCase(key);
sanitized[camelKey] = value;
```

**بعد:**
```dart
// إبقاء snake_case كما هو
sanitized[key] = value;

// إضافة الحقول المطلوبة تلقائياً
final requiredDefaults = {
  'created_at': nowEpoch,
  'updated_at': nowEpoch,
  'last_modified': nowEpoch,
};

// إضافة id للجداول الخاصة
if (requiresExplicitId.contains(collectionEntity)) {
  sanitized['id'] = nowEpoch + (DateTime.now().microsecond % 1000);
}
```

#### 2. دالة `_pushSingleChange` (السطر 399-426)
```dart
// استخدام snake_case
payload['device_id'] = _deviceId;
payload['sync_timestamp'] = Time.nowEpoch();
payload['local_uuid'] = change.localUuid;
```

#### 3. دالة `_pullEntityChanges` (السطر 720-768)
```dart
// تصحيح الاستعلامات لـ snake_case
Query.greaterThan('sync_timestamp', sinceEpoch),
Query.orderDesc('sync_timestamp'),

// دعم كلا الصيغتين عند السحب
data['local_uuid'] ??= data['localUuid'] ?? doc.$id;
```

---

## Commits المنفذة

```
119bf0b fix: إصلاح جذري لأخطاء Appwrite sync - استخدام snake_case بشكل متسق
2120c2b9 fix: إصلاح أخطاء Appwrite sync - إزالة rowHash وإضافة id لـ salary_withdrawals
```

---

## الحل الجذري

### المشكلة الأساسية
كان هناك تناقض في تحويل أسماء الحقول:
- `delta_sync_service._preparePayload` → يحول إلى snake_case
- `appwrite_delta_sync._sanitizePayload` → يحول إلى camelCase
- Appwrite schema → يتطلب snake_case

### الحل
**إزالة التحويل تماماً** لأن:
1. البيانات تأتي من `delta_sync_service` محولة لـ snake_case بالفعل
2. Appwrite schema يستخدم snake_case
3. لا حاجة لأي تحويل إضافي

---

## معلومات Appwrite

| الإعداد | القيمة |
|---------|--------|
| Endpoint | `https://fra.cloud.appwrite.io/v1` |
| Project ID | `690ff0da0025518570c1` |
| Database | `hotel_db` |

---

## الخطوة التالية

**اختبار المزامنة:**
1. تشغيل التطبيق على جهاز
2. الانتقال لـ الإعدادات → Appwrite
3. الضغط على زر المزامنة (Push)
4. التحقق من السجلات

---

## الحالة: في انتظار الاختبار

يرجى تشغيل التطبيق ومشاركة سجلات Appwrite للتحقق من نجاح الإصلاحات.
