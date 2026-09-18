# دليل إضافة الحقول الجديدة في Appwrite Cloud ☁️

## نظرة عامة
تحتاج إضافة حقلين جديدين في collection **Bookings** على Appwrite Cloud Console

---

## الحقول المطلوبة

### 1️⃣ حقل `discountType`
```json
{
  "key": "discountType",
  "type": "string",
  "size": 20,
  "required": false,
  "default": "per_night"
}
```

### 2️⃣ حقل `discountStartDate`
```json
{
  "key": "discountStartDate",
  "type": "string",
  "size": 50,
  "required": false
}
```

---

## خطوات الإضافة في Appwrite Console

### الطريقة 1: عبر واجهة Appwrite Console (موصى به)

1. **افتح Appwrite Console**
   - اذهب إلى: https://cloud.appwrite.io/console
   - سجل الدخول بحسابك

2. **اختر المشروع**
   - اختر مشروع "Marina Hotel"

3. **انتقل إلى Databases**
   - في القائمة الجانبية: Databases
   - اختر قاعدة البيانات الخاصة بالتطبيق

4. **افتح collection "Bookings"**
   - ابحث عن collection اسمها `bookings` أو `Bookings`
   - اضغط عليها

5. **أضف Attribute جديد**

   **أ) إضافة discountType:**
   - اضغط على "Create Attribute"
   - اختر Type: **String**
   - Key: `discountType`
   - Size: `20`
   - Required: **لا** (غير مفعل)
   - Default: `per_night`
   - اضغط "Create"

   **ب) إضافة discountStartDate:**
   - اضغط على "Create Attribute" مرة أخرى
   - اختر Type: **String**
   - Key: `discountStartDate`
   - Size: `50`
   - Required: **لا** (غير مفعل)
   - Default: (اتركه فارغ)
   - اضغط "Create"

6. **انتظر Indexing**
   - سيظهر الحقل بحالة "Processing"
   - انتظر حتى يصبح "Available" (عادة ثواني)

---

### الطريقة 2: عبر Appwrite CLI (للمطورين)

```bash
# تثبيت Appwrite CLI
npm install -g appwrite-cli

# تسجيل الدخول
appwrite login

# تعيين المشروع
appwrite client setProject <PROJECT_ID>

# إضافة discountType
appwrite databases createStringAttribute \
  --databaseId <DATABASE_ID> \
  --collectionId <BOOKINGS_COLLECTION_ID> \
  --key discountType \
  --size 20 \
  --required false \
  --default per_night

# إضافة discountStartDate
appwrite databases createStringAttribute \
  --databaseId <DATABASE_ID> \
  --collectionId <BOOKINGS_COLLECTION_ID> \
  --key discountStartDate \
  --size 50 \
  --required false
```

---

## التحقق من الإضافة

### من Appwrite Console:
1. افتح collection "Bookings"
2. اذهب إلى تبويب "Attributes"
3. تأكد من وجود:
   - ✅ `discountType` (String, 20)
   - ✅ `discountStartDate` (String, 50)

### من التطبيق:
```dart
// في ملف main.dart أو أي ملف initialization
import 'package:your_app/services/appwrite_schema_verifier.dart';

void main() async {
  // ... initialization code
  
  // التحقق من Schema
  final results = await AppwriteSchemaVerifier.verifySchema();
  
  if (results['missing'].isNotEmpty) {
    print('❌ Collections ناقصة: ${results['missing']}');
  }
  
  if (results['missingAttributes'].isNotEmpty) {
    print('❌ Attributes ناقصة:');
    results['missingAttributes'].forEach((collection, attrs) {
      print('  $collection: $attrs');
    });
  }
  
  if (results['missing'].isEmpty && results['missingAttributes'].isEmpty) {
    print('✅ Schema مطابق تماماً');
  }
}
```

---

## الحجوزات القديمة

### ماذا سيحدث للحجوزات الموجودة؟

**في قاعدة البيانات المحلية:**
- ✅ سيتم إضافة القيمة الافتراضية `per_night` تلقائياً
- ✅ عند Migration 23، سيتم إضافة العامود

**في Appwrite Cloud:**
- ⚠️ السجلات القديمة ستكون بدون هذه الحقول (null)
- ✅ عند أول sync، سيتم إرسال القيم من التطبيق
- ✅ أو ضع Default Value في Appwrite لتطبيقه تلقائياً

---

## حل المشاكل المحتملة

### ❌ "Attribute already exists"
- الحقل موجود مسبقاً
- تحقق من اسم الحقل (case-sensitive)

### ❌ "Collection not found"
- تأكد من اسم collection صحيح
- ابحث في Databases → Collections

### ❌ "Invalid attribute type"
- تأكد من اختيار Type: **String**
- وليس Text أو Integer

### ❌ مشاكل في المزامنة
```dart
// تأكد من تحديث adapters
// في bookings_adapter.dart يجب أن يكون:
discountType: _vStr(
  json,
  'discountType',
  src,
  altKey: 'discount_type',
  fallback: 'per_night',
),
discountStartDate: _vStr(
  json,
  'discountStartDate',
  src,
  altKey: 'discount_start_date',
),
```

---

## Permissions (الصلاحيات)

تأكد من أن collection "Bookings" لديها الصلاحيات المناسبة:

```
Read: 
  - role:all (أو حسب نظامك)

Create:
  - role:all (أو users فقط)

Update:
  - role:all (أو users فقط)

Delete:
  - role:all (أو admins فقط)
```

---

## خريطة الحقول (Field Mapping)

| اسم الحقل في Drift | اسم الحقل في Appwrite | النوع | الافتراضي |
|-------------------|----------------------|-------|----------|
| `discountType` | `discountType` | String(20) | `per_night` |
| `discountStartDate` | `discountStartDate` | String(50) | null |

---

## Checklist ✅

قبل تشغيل التطبيق، تأكد من:

- [ ] إضافة حقل `discountType` في Appwrite Console
- [ ] إضافة حقل `discountStartDate` في Appwrite Console
- [ ] الحقول بحالة "Available" (وليس Processing)
- [ ] تشغيل schema verifier للتأكد
- [ ] اختبار إنشاء حجز جديد
- [ ] اختبار المزامنة مع Cloud

---

## ملاحظات مهمة

⚠️ **لا تنس:**
- الحقول الجديدة **اختيارية** (not required)
- القيمة الافتراضية `per_night` ستطبق على الحجوزات الجديدة
- الحجوزات القديمة ستستمر بالعمل بشكل طبيعي

✅ **بعد الإضافة:**
- المزامنة ستعمل تلقائياً
- الحسابات ستكون دقيقة 100%
- يمكن تعديل نوع التخفيض من شاشة إدارة الضيوف

---

تم التحديث: 7 فبراير 2026 ☁️
