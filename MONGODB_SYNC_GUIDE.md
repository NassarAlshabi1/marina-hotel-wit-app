# 🔥 دليل المزامنة المجانية 100٪ باستخدام MongoDB

## نظرة عامة
نظام مزامنة فوري بين جميع الأجهزة (هواتف + كمبيوتر) باستخدام **MongoDB Atlas المجاني**.

### ✅ المميزات
- 🆓 **مجاني تماماً** حتى 512 MB
- ⚡ **مزامنة فورية** كل 5 ثواني تلقائياً
- 📱 **يعمل من المنزل** - لا حاجة للتواجد في الفندق
- 🌐 **من أي مكان في العالم** طالما لديك إنترنت
- 🔄 **مزامنة ثنائية الاتجاه** بين PHP و Flutter

---

## 📋 المتطلبات

### 1. حساب MongoDB Atlas (مجاني)
- ✅ لديك حساب جاهز
- ✅ Connection String جاهز
- ⚠️ فقط احتفظ بكلمة المرور في مكان آمن

### 2. PHP على السيرفر
```bash
# تثبيت MongoDB PHP Driver
cd /path/to/marina-hotel-wit-app/api
composer install
```

### 3. Flutter على الهاتف
```bash
cd mobile
flutter pub get
```

---

## 🚀 خطوات التشغيل

### الخطوة 1️⃣: تحديث كلمة مرور MongoDB

في ملف `mongodb_auto_sync.php`:
```php
$password = 'YOUR_ACTUAL_PASSWORD_HERE';  // ضع كلمة مرورك هنا
```

### الخطوة 2️⃣: تشغيل المزامنة التلقائية من السيرفر

#### الطريقة 1: Cron Job (Linux)
```bash
# افتح crontab
crontab -e

# أضف هذا السطر (مزامنة كل دقيقة)
* * * * * php /path/to/marina-hotel-wit-app/mongodb_auto_sync.php
```

#### الطريقة 2: Windows Task Scheduler
```powershell
# افتح Task Scheduler
# Create Basic Task
# اسم المهمة: MongoDB Sync
# Trigger: كل دقيقة
# Action: php C:\xampp\htdocs\marina-hotel-wit-app\mongodb_auto_sync.php
```

#### الطريقة 3: خدمة Cron Job خارجية (الأسهل)
1. انتقل إلى [cron-job.org](https://cron-job.org) (مجاني)
2. أنشئ حساب
3. أضف Cron Job جديد:
   - URL: `http://your-domain.com/marina-hotel-wit-app/mongodb_auto_sync.php`
   - كل: 1 دقيقة
   - حفظ

### الخطوة 3️⃣: اختبار المزامنة يدوياً

```bash
# من Terminal/CMD
php mongodb_auto_sync.php

# أو من المتصفح
http://localhost/marina-hotel-wit-app/api/mongodb_sync.php?action=sync_all&password=YOUR_PASSWORD
```

### الخطوة 4️⃣: استخدام التطبيق

#### من الهاتف في الفندق:
1. افتح التطبيق
2. اذهب إلى **القائمة > النزلاء - المزامنة الفورية**
3. أدخل كلمة مرور MongoDB
4. اضغط **اتصل الآن**
5. ✅ ستظهر جميع النزلاء فوراً

#### من الهاتف في المنزل:
1. نفس الخطوات السابقة
2. سترى جميع النزلاء المضافين من الجهاز الآخر
3. ✅ يتم التحديث تلقائياً كل 5 ثواني

---

## 📱 إضافة الشاشة للقائمة الرئيسية

### في ملف `mobile/lib/components/admin_sidebar.dart`:

أضف في قائمة القوائم:
```dart
ListTile(
  leading: const Icon(Icons.cloud_sync, color: Colors.blue),
  title: const Text('النزلاء - المزامنة الفورية'),
  onTap: () {
    Navigator.pop(context);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const GuestsRealtimeScreen(),
      ),
    );
  },
),
```

### أضف الـ Import:
```dart
import '../screens/guests/guests_realtime_screen.dart';
```

---

## 🧪 اختبار النظام

### 1. اختبار PHP Sync
```bash
# من Terminal
php mongodb_auto_sync.php

# يجب أن ترى:
# ✅ مزامنة ناجحة: X نزيل، Y حجز
```

### 2. اختبار Flutter App
1. افتح التطبيق على **هاتفين مختلفين**
2. على **الهاتف 1**: أدخل كلمة المرور واتصل
3. على **الهاتف 2**: أدخل كلمة المرور واتصل
4. ✅ يجب أن تظهر نفس البيانات على الجهازين

### 3. اختبار المزامنة الفورية
1. في الـ PHP Admin Panel: أضف نزيل جديد
2. انتظر 60 ثانية (مدة المزامنة التلقائية)
3. على الهاتف: يجب أن يظهر النزيل الجديد خلال 5 ثواني
4. ✅ مزامنة ناجحة!

---

## 📊 مراقبة النظام

### عرض السجلات
```bash
# سجل المزامنة الناجحة
cat logs/mongodb_sync.log

# سجل الأخطاء
cat logs/mongodb_sync_error.log

# وقت آخر مزامنة
cat logs/last_mongo_sync.txt
```

### إحصائيات MongoDB
```bash
# من المتصفح
http://localhost/marina-hotel-wit-app/api/mongodb_sync.php?action=stats&password=YOUR_PASSWORD
```

الناتج:
```json
{
  "success": true,
  "stats": {
    "total_guests": 42,
    "total_bookings": 128,
    "last_sync": "2025-11-02 15:30:00"
  }
}
```

---

## 🎯 سيناريو الاستخدام الكامل

### السيناريو:
- **الهاتف 1** (في الفندق): موظف الاستقبال
- **الهاتف 2** (في المنزل): المدير

### الخطوات:

#### الهاتف 1 (في الفندق):
1. يفتح التطبيق
2. يضيف نزيل جديد: "أحمد محمد"
3. ✅ يُحفظ في قاعدة البيانات المحلية

#### السيرفر (كل دقيقة تلقائياً):
1. يقرأ البيانات من MySQL
2. يرسلها إلى MongoDB Atlas
3. ✅ "أحمد محمد" موجود الآن في السحابة

#### الهاتف 2 (في المنزل):
1. يفتح شاشة **النزلاء - المزامنة الفورية**
2. خلال 5 ثواني: يظهر "أحمد محمد"
3. ✅ المدير يرى النزلاء من المنزل!

---

## 🔧 استكشاف الأخطاء

### 1. خطأ: "Failed to connect to MongoDB"
**الحل:**
```bash
# تأكد من:
1. كلمة المرور صحيحة
2. الاتصال بالإنترنت متاح
3. MongoDB Atlas Cluster يعمل
```

### 2. خطأ: "Class 'MongoDB\Client' not found"
**الحل:**
```bash
cd api
composer install
```

### 3. التطبيق لا يظهر النزلاء
**الحل:**
```bash
# تأكد من:
1. المزامنة التلقائية تعمل: php mongodb_auto_sync.php
2. البيانات موجودة في MongoDB: افتح MongoDB Atlas Web UI
3. كلمة المرور صحيحة في التطبيق
```

### 4. المزامنة بطيئة
**الحل:**
```dart
// في ملف mongodb_sync_service.dart
// غيّر Timer من 5 ثواني إلى 2 ثانية:
Timer.periodic(const Duration(seconds: 2), ...);
```

---

## 💡 نصائح مهمة

### 1. أمان كلمة المرور
- ⚠️ لا تشارك كلمة المرور علناً
- ✅ احفظها في ملف `.env` أو خارج Git

### 2. الحد المجاني
- ✅ 512 MB مجاناً (كافي لآلاف النزلاء)
- 📊 راقب الاستخدام من MongoDB Atlas Dashboard

### 3. تحسين الأداء
- ✅ المزامنة كل دقيقة (مناسبة)
- ⚡ إذا أردت أسرع: غيّر إلى 30 ثانية
- 🔋 إذا أردت توفير Data: غيّر إلى 5 دقائق

---

## 🎉 المزايا

### ✅ ما تم تحقيقه:
- [x] مزامنة مجانية 100٪
- [x] مزامنة فورية بين الأجهزة
- [x] عرض النزلاء من أي مكان
- [x] سجلات وإحصائيات
- [x] سهل الإعداد والاستخدام

### 🚀 إمكانيات إضافية:
- [ ] مزامنة الغرف
- [ ] مزامنة المدفوعات
- [ ] إشعارات فورية
- [ ] تقارير في الوقت الفعلي

---

## 📞 الدعم

إذا واجهت أي مشكلة:
1. تحقق من السجلات في `logs/mongodb_sync_error.log`
2. راجع [MongoDB Atlas Documentation](https://www.mongodb.com/docs/atlas/)
3. تأكد من الاتصال بالإنترنت

---

## 🎊 تم بنجاح!

الآن لديك نظام مزامنة مجاني 100٪ يعمل في الوقت الفعلي بين جميع الأجهزة! 🎉

**الهاتف في الفندق** ⬅️ **MongoDB Atlas** ➡️ **الهاتف في المنزل**

✅ مجاني للأبد
✅ يعمل من أي مكان
✅ مزامنة فورية
