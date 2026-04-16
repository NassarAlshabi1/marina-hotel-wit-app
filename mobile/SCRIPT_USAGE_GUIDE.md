# دليل تشغيل Script إضافة الحقول 🚀

## الملفات المتوفرة

### 1️⃣ Bash Script (سريع وسهل) ✅ موصى به
📄 `scripts/add_discount_fields.sh`

### 2️⃣ Dart Script (للمطورين)
📄 `lib/scripts/add_discount_fields_to_appwrite.dart`

---

## الخطوة 1: الحصول على API Key 🔑

**قبل تشغيل Script، تحتاج API Key من Appwrite:**

1. **افتح Appwrite Console:**
   ```
   https://cloud.appwrite.io/console
   ```

2. **سجل الدخول** بحسابك

3. **اختر المشروع:**
   - Project: Marina Hotel (690ff0da0025518570c1)

4. **انتقل إلى API Keys:**
   - Settings → API Keys
   - أو مباشرة: https://cloud.appwrite.io/console/project-690ff0da0025518570c1/settings/keys

5. **أنشئ API Key جديد:**
   - اضغط "Create API Key"
   - Name: `Add Discount Fields` (أو أي اسم)
   - Expiration: اختر مدة (أو Never)
   - **Scopes/Permissions:** 
     - ✅ `databases.write` (مهم جداً!)
     - ✅ `collections.write` (اختياري)
   - اضغط "Create"

6. **انسخ API Key:**
   - سيظهر API Key مرة واحدة فقط
   - احفظه في مكان آمن

---

## الخطوة 2: تشغيل Script 🎯

### الطريقة 1: Bash Script (موصى به)

```bash
cd /home/marina-hotel-wit-app/mobile

# تشغيل مع API Key
./scripts/add_discount_fields.sh YOUR_API_KEY_HERE
```

**مثال:**
```bash
./scripts/add_discount_fields.sh 6a8e3f2b1c9d...
```

---

### الطريقة 2: Dart Script

```bash
cd /home/marina-hotel-wit-app/mobile

# التأكد من تثبيت dependencies
flutter pub get

# تشغيل مع API Key
dart run lib/scripts/add_discount_fields_to_appwrite.dart YOUR_API_KEY_HERE
```

**أو بدون معامل (سيطلب API Key):**
```bash
dart run lib/scripts/add_discount_fields_to_appwrite.dart
```

---

## الخطوة 3: التحقق من النجاح ✅

### من Appwrite Console:
1. افتح https://cloud.appwrite.io/console
2. اختر المشروع → Databases → hotel_db
3. افتح collection "bookings"
4. تبويب "Attributes"
5. **تأكد من وجود:**
   - ✅ `discountType` (String, 20, default: per_night)
   - ✅ `discountStartDate` (String, 50)

### الحالة:
- **Processing:** الحقل قيد الإنشاء (انتظر ثوانٍ)
- **Available:** ✅ جاهز للاستخدام

---

## رسائل النجاح المتوقعة

```
🚀 إضافة حقول التخفيض إلى Appwrite Cloud
═══════════════════════════════════════════════

📊 المعلومات:
Endpoint: https://fra.cloud.appwrite.io/v1
Project ID: 690ff0da0025518570c1
Database ID: hotel_db
Collection ID: bookings

1️⃣ إضافة حقل discountType...
   ✅ تم إضافة discountType بنجاح

2️⃣ إضافة حقل discountStartDate...
   ✅ تم إضافة discountStartDate بنجاح

═══════════════════════════════════════════════
✅ اكتمل التحديث!

ملاحظات:
• الحقول قد تحتاج بضع ثوانٍ لتكون جاهزة (Indexing)
• تحقق من Appwrite Console للتأكد
• يمكنك الآن استخدام التطبيق بشكل طبيعي
```

---

## حل المشاكل المحتملة 🔧

### ❌ "API Key مطلوب"
**السبب:** لم تمرر API Key للـ script
**الحل:** شغل مع API Key: `./script.sh YOUR_API_KEY`

### ❌ "خطأ HTTP 401"
**السبب:** API Key غير صحيح أو منتهي
**الحل:** 
- تأكد من نسخ API Key بشكل صحيح
- أنشئ API Key جديد

### ❌ "خطأ HTTP 403"
**السبب:** API Key ليس لديه صلاحيات `databases.write`
**الحل:**
- أنشئ API Key جديد
- تأكد من تفعيل `databases.write`

### ❌ "خطأ HTTP 404"
**السبب:** Database أو Collection غير موجود
**الحل:**
- تأكد من أن Database ID: `hotel_db`
- تأكد من أن Collection ID: `bookings`
- راجع Appwrite Console

### ℹ️ "الحقل موجود مسبقاً"
**ليس خطأ!** الحقل مضاف مسبقاً، كل شيء جيد ✅

### ❌ "curl: command not found"
**السبب:** curl غير مثبت
**الحل:**
```bash
# Ubuntu/Debian
sudo apt-get install curl

# أو استخدم Dart Script بدلاً منه
```

---

## الأمان 🔒

⚠️ **لا تشارك API Key مع أحد!**
⚠️ **لا تضعه في Git أو GitHub!**

بعد الانتهاء من تشغيل Script:
1. يمكنك حذف API Key من Appwrite Console
2. أو تعيين Expiration قصير (1 hour)

---

## الخطوات التالية

بعد تشغيل Script بنجاح:

1. ✅ **اختبر التطبيق:**
   ```bash
   cd /home/marina-hotel-wit-app/mobile
   flutter run
   ```

2. ✅ **جرب إنشاء حجز جديد** مع تخفيض

3. ✅ **اختبر المزامنة** مع Appwrite

4. ✅ **commit التعديلات:**
   ```bash
   git add .
   git commit -m "feat: add discount type support with date-based calculation"
   git push
   ```

---

تم الإنشاء: 7 فبراير 2026 🚀
