# دليل حل المشاكل - نظام إدارة فندق مارينا بلازا

## 🔧 المشاكل الشائعة وحلولها

### 1. مشكلة قاعدة البيانات: "Query cache is globally disabled"

**الخطأ:**
```
فشل الاتصال بقاعدة البيانات: Query cache is globally disabled and you can't enable it only for this session
```

**الحل:**
✅ **تم إصلاحه تلقائياً** - النظام الآن يتحقق من توفر query cache قبل تفعيله.

**الملف المحدث:** `includes/db.php`

---

### 2. مشكلة الأمان: "Unknown column 'failed_login_attempts'"

**الخطأ:**
```
Unknown column 'failed_login_attempts' in 'field list'
```

**الحل:**
1. **تشغيل سكريبت إعداد الأمان:**
   ```
   زيارة: ../../scripts/php/maintenance/setup_security_tables.php
   ```

2. **أو إنشاء الأعمدة يدوياً:**
   ```sql
   ALTER TABLE users ADD COLUMN failed_login_attempts INT DEFAULT 0;
   ALTER TABLE users ADD COLUMN locked_until TIMESTAMP NULL;
   ALTER TABLE users ADD COLUMN last_login TIMESTAMP NULL;
   ```

**الملفات المحدثة:**
- `../../scripts/php/maintenance/setup_security_tables.php` (جديد)
- `includes/security.php` (محسن)
- `login.php` (محسن مع تحقق آمن)

---

### 3. مشاكل الخطوط والموارد الخارجية

**المشكلة:** عدم تحميل الخطوط أو الأيقونات بدون إنترنت

**الحل:**
1. **تحميل الخطوط المحلية:**
   ```
   زيارة: download_fonts.php
   ```

2. **تحديث مسارات الموارد:**
   ```
   زيارة: ../../scripts/php/maintenance/update_assets_paths.php
   ```

**الملفات الجديدة:**
- `assets/fonts/fonts.css`
- `assets/css/bootstrap-local.css`
- `assets/js/bootstrap-local.js`

---

### 4. مشاكل تصدير PDF

**المشكلة:** خطأ في إنشاء ملفات PDF

**الحل:**
1. **التأكد من وجود مكتبة FPDF:**
   ```php
   // الملف موجود في: includes/fpdf/fpdf.php
   ```

2. **التأكد من صلاحيات المجلدات:**
   ```bash
   chmod 755 uploads/reports/
   ```

3. **استخدام صفحة التقارير المحسنة:**
   ```
   زيارة: admin/reports.php
   ```

---

## 🚀 خطوات الإعداد السريع

### للمستخدمين الجدد:

1. **إعداد قاعدة البيانات:**
   ```sql
   CREATE DATABASE hotel_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   ```

2. **تحديث إعدادات الاتصال:**
   ```php
   // في ملف includes/config.php
   define('DB_HOST', 'localhost');
   define('DB_USER', 'your_username');
   define('DB_PASS', 'your_password');
   define('DB_NAME', 'hotel_db');
   ```

3. **إعداد جداول الأمان:**
   ```
   زيارة: ../../scripts/php/maintenance/setup_security_tables.php
   ```

4. **تحميل الموارد المحلية:**
   ```
   زيارة: download_fonts.php
   ثم: ../../scripts/php/maintenance/update_assets_paths.php
   ```

5. **تسجيل الدخول:**
   ```
   اسم المستخدم: admin
   كلمة المرور: 1234
   ```

### للمستخدمين الحاليين:

1. **تحديث النظام:**
   ```
   زيارة: ../../scripts/php/maintenance/setup_security_tables.php
   ```

2. **تحديث الموارد:**
   ```
   زيارة: download_fonts.php
   زيارة: ../../scripts/php/maintenance/update_assets_paths.php
   ```

---

## 🔍 تشخيص المشاكل

### فحص حالة النظام:
```
زيارة: system_health_report.php
```

### إصلاح مشاكل البيانات:
```
زيارة: ../../scripts/php/maintenance/fix_system_issues.php
```

### فحص سجلات الأخطاء:
```
مجلد: logs/error.log
```

---

## 📞 الدعم الفني

### رسائل الخطأ الشائعة:

1. **"Call to undefined method"**
   - **الحل:** تشغيل `../../scripts/php/maintenance/setup_security_tables.php`

2. **"Table doesn't exist"**
   - **الحل:** استيراد قاعدة البيانات أو تشغيل سكريبت الإعداد

3. **"Permission denied"**
   - **الحل:** تعيين صلاحيات المجلدات `chmod 755`

4. **"Font not loading"**
   - **الحل:** تشغيل `download_fonts.php`

### ملفات مهمة للفحص:

- `includes/config.php` - إعدادات النظام
- `includes/db.php` - اتصال قاعدة البيانات
- `includes/security.php` - نظام الأمان
- `logs/error.log` - سجل الأخطاء

---

## ✅ قائمة التحقق السريع

- [ ] قاعدة البيانات متصلة
- [ ] جداول الأمان موجودة
- [ ] الخطوط محملة محلياً
- [ ] صلاحيات المجلدات صحيحة
- [ ] ملفات CSS و JS تعمل
- [ ] تصدير PDF يعمل
- [ ] النظام يعمل بدون إنترنت

---

## 🔄 تحديثات مستقبلية

للحصول على آخر التحديثات والإصلاحات:

1. راجع ملف `README.md`
2. فحص `system_health_report.php`
3. تشغيل `../../scripts/php/maintenance/fix_system_issues.php` دورياً

---

**ملاحظة:** جميع المشاكل المذكورة أعلاه تم إصلاحها في الإصدار الحالي مع إضافة آليات حماية لمنع حدوثها مستقبلاً.
