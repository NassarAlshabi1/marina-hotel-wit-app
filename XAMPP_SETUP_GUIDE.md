# 🔧 دليل الإعداد على XAMPP المحلي

## المتطلبات

- ✅ XAMPP 8.0+ (PHP 7.4+, MySQL 5.7+, Apache 2.4+)
- ✅ Windows 10/11 أو Linux أو macOS

---

## 📥 خطوات التثبيت على XAMPP

### 1️⃣ تثبيت XAMPP

إذا لم يكن مثبتاً:
```
Windows: https://www.apachefriends.org/download.html
```

### 2️⃣ وضع المشروع في مجلد htdocs

```bash
# انسخ المشروع إلى:
C:\xampp\htdocs\marina-hotel-wit-app\

# أو في Linux/Mac:
/opt/lampp/htdocs/marina-hotel-wit-app/
```

### 3️⃣ تشغيل XAMPP

1. افتح **XAMPP Control Panel**
2. شغل **Apache** (اضغط Start)
3. شغل **MySQL** (اضغط Start)

✅ تأكد من ظهور اللون الأخضر بجانبهما

### 4️⃣ إنشاء قاعدة البيانات

**الطريقة 1: عبر phpMyAdmin**
1. افتح المتصفح: http://localhost/phpmyadmin
2. اضغط "New" أو "جديد"
3. اسم قاعدة البيانات: `hotel_db`
4. Collation: `utf8mb4_unicode_ci`
5. اضغط Create

**الطريقة 2: عبر SQL**
1. افتح phpMyAdmin → SQL
2. نفذ:
```sql
CREATE DATABASE hotel_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 5️⃣ تطبيق Migrations

**الطريقة السهلة (موصى بها):**
افتح المتصفح:
```
http://localhost/marina-hotel-wit-app/api/v1/setup.php
```

**الطريقة اليدوية:**
1. افتح phpMyAdmin
2. اختر قاعدة البيانات `hotel_db`
3. اذهب لتبويب "Import"
4. ارفع الملفات بالترتيب:
   - `sql/migrations/001_add_sync_tables.sql`
   - `sql/migrations/002_add_sync_fields.sql`
   - `sql/migrations/003_add_new_fields.sql`

### 6️⃣ اختبار API

**Test Health:**
```
http://localhost/marina-hotel-wit-app/api/v1/health.php
```

**Test Login:**
```
http://localhost/marina-hotel-wit-app/api/v1/auth/login.php
```

---

## 🔧 إعدادات XAMPP

### ملف التكوين (@includes/config.php)

التكوين الحالي جاهز لـ XAMPP:
```php
define('DB_HOST', 'localhost');      // ✅ صحيح لـ XAMPP
define('DB_USER', 'root');           // ✅ المستخدم الافتراضي
define('DB_PASS', '');               // ✅ بدون كلمة مرور افتراضياً
define('DB_NAME', 'hotel_db');       // ✅ اسم قاعدة البيانات
```

**⚠️ ملاحظة:** إذا غيرت كلمة مرور MySQL في XAMPP، عدل `DB_PASS`

---

## 📱 إعدادات Flutter للاتصال بـ XAMPP

### للمحاكي Android

في `mobile/lib/utils/env.dart`:
```dart
static String baseApiUrl = 'http://10.0.2.2/marina-hotel-wit-app/api/v1';
```

### للجهاز الحقيقي (نفس الشبكة)

1. اعرف IP جهازك:
```bash
# Windows
ipconfig
# ابحث عن IPv4 Address (مثال: 192.168.1.5)

# Linux/Mac
ifconfig
```

2. عدل في Flutter:
```dart
static String baseApiUrl = 'http://192.168.1.5/marina-hotel-wit-app/api/v1';
```

3. **مهم:** افتح Firewall للسماح بالاتصال:
   - Windows Firewall → Allow Apache في Private Networks

---

## 🐛 حل المشاكل الشائعة في XAMPP

### المشكلة 1: Apache لا يعمل (Port 80 مستخدم)

**الحل 1: تغيير Port Apache**
1. XAMPP Control Panel → Apache → Config → httpd.conf
2. ابحث عن:
```apache
Listen 80
```
3. غيره إلى:
```apache
Listen 8080
```
4. احفظ وأعد تشغيل Apache
5. الآن استخدم: `http://localhost:8080/marina-hotel-wit-app/`

**الحل 2: إيقاف البرنامج المستخدم للـ Port**
- غالباً Skype أو IIS
- أوقفه من Task Manager

### المشكلة 2: MySQL لا يعمل (Port 3306 مستخدم)

**الحل:**
1. XAMPP Control Panel → MySQL → Config → my.ini
2. ابحث عن:
```ini
port=3306
```
3. غيره إلى:
```ini
port=3307
```
4. عدل في `includes/config.php`:
```php
define('DB_HOST', 'localhost:3307');
```

### المشكلة 3: خطأ "Access denied for user 'root'@'localhost'"

**الحل:**
1. افتح phpMyAdmin
2. اذهب لـ "User accounts"
3. اختر root@localhost → Edit privileges
4. تأكد من كلمة المرور فارغة أو حدث `includes/config.php`

### المشكلة 4: خطأ 404 Not Found

**الحل:**
تأكد من:
1. المشروع في: `C:\xampp\htdocs\marina-hotel-wit-app\`
2. Apache يعمل (أخضر في XAMPP)
3. الرابط صحيح: `http://localhost/marina-hotel-wit-app/api/v1/health.php`

### المشكلة 5: "mysqli extension not loaded"

**الحل:**
1. افتح `C:\xampp\php\php.ini`
2. ابحث عن:
```ini
;extension=mysqli
```
3. أزل `;` ليصبح:
```ini
extension=mysqli
```
4. أعد تشغيل Apache

### المشكلة 6: CORS Errors من Flutter

**الحل:**
ملف `.htaccess` موجود ويحل المشكلة تلقائياً (تم إنشاؤه)

---

## 📊 اختبار سريع

### 1. Test Database Connection
```
http://localhost/marina-hotel-wit-app/api/v1/health.php
```

**النتيجة المتوقعة:**
```json
{
  "status": "healthy",
  "checks": {
    "database": {
      "status": "healthy"
    }
  }
}
```

### 2. Test Login
استخدم Postman أو:
```bash
# في Git Bash أو PowerShell
curl -X POST http://localhost/marina-hotel-wit-app/api/v1/auth/login.php ^
  -H "Content-Type: application/json" ^
  -d "{\"username\":\"admin\",\"password\":\"password\"}"
```

---

## 🎯 نصائح الأداء على XAMPP

### 1. تحسين PHP
عدل `C:\xampp\php\php.ini`:
```ini
memory_limit = 256M
max_execution_time = 300
upload_max_filesize = 20M
post_max_size = 20M
```

### 2. تحسين MySQL
عدل `C:\xampp\mysql\bin\my.ini`:
```ini
max_connections = 100
innodb_buffer_pool_size = 256M
```

### 3. تفعيل Opcache
في `php.ini`:
```ini
zend_extension=opcache
opcache.enable=1
opcache.memory_consumption=128
```

---

## 🔐 الأمان على XAMPP المحلي

**⚠️ مهم:** XAMPP معد للتطوير فقط، **لا تستخدمه في الإنتاج**

للأمان المحلي:
1. ضع كلمة مرور لـ MySQL root:
   ```sql
   SET PASSWORD FOR 'root'@'localhost' = PASSWORD('your_password');
   ```

2. عطل phpMyAdmin من الإنترنت:
   عدل `C:\xampp\phpMyAdmin\config.inc.php`:
   ```php
   $cfg['Servers'][$i]['AllowNoPassword'] = false;
   ```

---

## 📁 هيكل المجلدات على XAMPP

```
C:\xampp\
├── htdocs\
│   └── marina-hotel-wit-app\      ← المشروع هنا
│       ├── api\
│       ├── admin\
│       ├── mobile\
│       ├── includes\
│       └── ...
├── mysql\
│   └── data\
│       └── hotel_db\              ← قاعدة البيانات هنا
├── php\
│   └── php.ini                    ← إعدادات PHP
└── apache\
    └── conf\
        └── httpd.conf             ← إعدادات Apache
```

---

## ✅ Checklist - الإعداد على XAMPP

- [ ] تثبيت XAMPP
- [ ] نسخ المشروع إلى htdocs
- [ ] تشغيل Apache و MySQL
- [ ] إنشاء قاعدة البيانات hotel_db
- [ ] تطبيق migrations عبر setup.php
- [ ] اختبار health.php
- [ ] اختبار login.php
- [ ] تعديل env.dart في Flutter
- [ ] اختبار من Flutter app

---

## 🚀 البدء السريع (Quick Start)

```bash
# 1. تأكد من XAMPP يعمل
# 2. افتح المتصفح:

http://localhost/marina-hotel-wit-app/api/v1/setup.php

# 3. بعد Setup، اختبر:

http://localhost/marina-hotel-wit-app/api/v1/health.php

# 4. في Flutter:
flutter run --dart-define=BASE_API_URL=http://10.0.2.2/marina-hotel-wit-app/api/v1

# ✅ جاهز!
```

---

## 📞 دعم إضافي

إذا واجهت مشاكل:
1. تحقق من Logs:
   - Apache: `C:\xampp\apache\logs\error.log`
   - PHP: `C:\xampp\php\logs\php_error_log`
   - API: `logs/api_*.log`

2. تأكد من:
   - Apache يعمل (أخضر)
   - MySQL يعمل (أخضر)
   - Port 80 و 3306 غير مستخدمين

3. أعد تشغيل XAMPP بالكامل

---

**🎉 الآن XAMPP جاهز بالكامل للعمل مع API!**
