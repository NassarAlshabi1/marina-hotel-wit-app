# 🚀 البدء السريع - MongoDB Sync

## التثبيت في 3 دقائق

### 1️⃣ تثبيت المكتبات

**Windows:**
```cmd
SETUP_MONGODB.bat
```

**Linux/Mac:**
```bash
cd api
composer install
mkdir -p logs
```

### 2️⃣ تعديل كلمة المرور

افتح `mongodb_auto_sync.php` وغيّر:
```php
$password = 'YOUR_PASSWORD_HERE';
```

### 3️⃣ اختبار المزامنة

```bash
php mongodb_auto_sync.php
```

### 4️⃣ تشغيل تلقائي

**Windows (Task Scheduler):**
- اسم: MongoDB Sync
- Trigger: كل دقيقة
- Action: `php C:\path\to\mongodb_auto_sync.php`

**Linux (Crontab):**
```bash
* * * * * php /path/to/mongodb_auto_sync.php
```

**خدمة خارجية (الأسهل):**
- [cron-job.org](https://cron-job.org)
- URL: `http://yoursite.com/api/mongodb_sync.php?action=sync_all&password=PASS`

### 5️⃣ استخدام التطبيق

1. افتح التطبيق
2. **القائمة > النزلاء - المزامنة الفورية**
3. أدخل كلمة المرور
4. ✅ شاهد النزلاء من جميع الأجهزة!

---

## 💰 التكلفة: صفر جنيه

✅ MongoDB Atlas مجاني حتى 512 MB
✅ كافي لآلاف النزلاء
✅ لا بطاقة ائتمان مطلوبة

---

## 📱 السيناريو

**الهاتف 1 (الفندق)** → يضيف نزيل "محمد"
↓ (60 ثانية)
**MongoDB Atlas** → يحفظ البيانات
↓ (5 ثواني)
**الهاتف 2 (المنزل)** → يظهر "محمد" تلقائياً ✅

---

## ⚠️ هام

- احفظ كلمة المرور في مكان آمن
- لا تشاركها مع أحد
- تحقق من السجلات في `logs/mongodb_sync.log`

---

## 🎉 انتهى!

الآن النظام يعمل. استمتع بالمزامنة المجانية! 🚀
