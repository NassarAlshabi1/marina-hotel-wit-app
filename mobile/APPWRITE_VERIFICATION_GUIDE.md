# 🔍 التحقق من مطابقة جداول Appwrite Cloud

## 📚 الملفات المضافة:

1. **`APPWRITE_SCHEMA_VERIFICATION.md`** - دليل شامل لبنية جميع الجداول
2. **`lib/services/appwrite_schema_verifier.dart`** - سكريبت Dart للتحقق التلقائي

---

## 🚀 كيفية الاستخدام:

### الطريقة 1️⃣: التحقق اليدوي

1. افتح Appwrite Console:
   ```
   https://fra.cloud.appwrite.io/console/project-690ff0da0025518570c1
   ```

2. انتقل إلى:
   ```
   Database → hotel_db → Collections
   ```

3. تحقق من وجود جميع الـ Collections:
   ```
   ✓ rooms
   ✓ bookings
   ✓ booking_notes
   ✓ booking_nights
   ✓ employees
   ✓ expenses
   ✓ cash_transactions
   ✓ payments
   ✓ debts
   ✓ salary_cycles
   ✓ salary_payments
   ✓ hotel_day_ledger
   ```

4. لكل Collection، تأكد من:
   - ✅ Document ID = `localUuid` (Custom ID enabled)
   - ✅ جميع الحقول موجودة (راجع `APPWRITE_SCHEMA_VERIFICATION.md`)
   - ✅ الأنواع صحيحة (string, integer, double, boolean)
   - ✅ الحقول الفريدة محددة بشكل صحيح

---

### الطريقة 2️⃣: التحقق التلقائي (مستحسن)

#### من التطبيق:

```dart
import 'package:marina_hotel_mobile/services/appwrite_schema_verifier.dart';

void main() async {
  // تشغيل التحقق
  final results = await AppwriteSchemaVerifier.verifySchema();
  
  // عرض النتائج
  print('النتائج: ${results['summary']}');
  
  // طباعة سكريبتات الإنشاء للجداول الناقصة
  if (results['missing'].isNotEmpty) {
    print('\n📝 سكريبتات إنشاء الجداول الناقصة:\n');
    for (final collectionId in results['missing']) {
      AppwriteSchemaVerifier.printCreateCollectionScript(collectionId);
      print('\n---\n');
    }
  }
}
```

#### من Command Line:

```bash
cd mobile
dart run lib/services/appwrite_schema_verifier.dart
```

---

## 📋 مثال على النتائج:

```
🔍 بدء التحقق من مطابقة جداول Appwrite Cloud...

📋 التحقق من: rooms (Rooms)
   ✅ موجود: Rooms
   ✅ جميع الحقول موجودة

📋 التحقق من: bookings (Bookings)
   ✅ موجود: Bookings
   ⚠️  حقول ناقصة (3): guestIdType, expectedNights, totalDueCached

📋 التحقق من: booking_notes (Booking Notes)
   ❌ غير موجود: booking_notes

═══════════════════════════════════════
📊 ملخص التحقق
═══════════════════════════════════════
إجمالي الجداول المطلوبة: 12
✅ موجود: 10
❌ ناقص: 2
📈 نسبة الاكتمال: 83.3%
═══════════════════════════════════════

⚠️  الجداول الناقصة:
   - booking_notes
   - salary_cycles

💡 يرجى إنشاء الجداول الناقصة في Appwrite Console
   راجع: mobile/APPWRITE_SCHEMA_VERIFICATION.md
```

---

## 🛠️ إنشاء الجداول الناقصة:

### خيار 1: يدوياً في Console

1. افتح Appwrite Console
2. اذهب إلى Database → hotel_db
3. انقر **"Add Collection"**
4. اتبع المواصفات في `APPWRITE_SCHEMA_VERIFICATION.md`

### خيار 2: باستخدام Appwrite CLI

```bash
# تثبيت Appwrite CLI
npm install -g appwrite-cli

# تسجيل الدخول
appwrite login

# إنشاء collection
appwrite databases createCollection \
  --databaseId hotel_db \
  --collectionId rooms \
  --name "Rooms"

# إضافة attributes
appwrite databases createStringAttribute \
  --databaseId hotel_db \
  --collectionId rooms \
  --key localUuid \
  --size 36 \
  --required true

# ... إلخ (راجع APPWRITE_SCHEMA_VERIFICATION.md)
```

---

## ✅ قائمة التحقق النهائية:

### قبل المزامنة:

- [ ] جميع الـ 12 Collections موجودة في Appwrite
- [ ] كل Collection يستخدم `localUuid` كـ Document ID
- [ ] جميع الحقول الأساسية موجودة
- [ ] جميع حقول SyncFields (13 حقل) موجودة في كل جدول
- [ ] الحقول الفريدة (Unique) محددة بشكل صحيح
- [ ] الأذونات مضبوطة (Any أو API Keys)

### أثناء المزامنة:

- [ ] تفعيل مزامنة Appwrite في الإعدادات
- [ ] التحقق من الاتصال بالإنترنت
- [ ] مراقبة السجلات (Logs) للأخطاء

### بعد المزامنة:

- [ ] التحقق من عدد السجلات في كل Collection
- [ ] مطابقة البيانات بين Local DB و Appwrite
- [ ] اختبار استعادة البيانات من Google Drive

---

## 🐛 استكشاف الأخطاء:

### خطأ: "Collection not found"
**الحل:** أنشئ الـ Collection الناقص في Appwrite Console

### خطأ: "Document with the requested ID already exists"
**الحل:** هذا طبيعي - يعني أن السجل موجود بالفعل (سيتم التحديث)

### خطأ: "Attribute not found"
**الحل:** أضف الحقل الناقص في Appwrite Console → Collection → Attributes

### خطأ: "Invalid permissions"
**الحل:** تأكد من أذونات الـ Collection (Settings → Permissions)

---

## 📊 الإحصائيات:

- **عدد الجداول:** 12
- **متوسط عدد الحقول:** 23 حقل/جدول
- **إجمالي الحقول:** ~276 Attribute
- **حجم البيانات المتوقع:** يعتمد على الاستخدام

---

## 🔗 روابط مفيدة:

- [Appwrite Console](https://fra.cloud.appwrite.io/console/project-690ff0da0025518570c1)
- [Appwrite Docs - Databases](https://appwrite.io/docs/products/databases)
- [Appwrite Docs - Collections](https://appwrite.io/docs/products/databases/collections)
- [Appwrite CLI](https://appwrite.io/docs/command-line)

---

## 💡 نصائح:

1. **النسخ الاحتياطي:** احفظ نسخة من بنية الجداول دائماً
2. **الاختبار:** اختبر المزامنة على بيانات تجريبية أولاً
3. **المراقبة:** راقب السجلات عند أول مزامنة
4. **التوثيق:** حدّث `APPWRITE_SCHEMA_VERIFICATION.md` عند إضافة حقول جديدة

---

✅ **بعد التحقق من المطابقة، ستعمل المزامنة بشكل سلس: Google Drive ↔ Local DB ↔ Appwrite Cloud** 🚀
