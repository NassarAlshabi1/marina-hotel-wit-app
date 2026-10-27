# نظام المزامنة التلقائية - Hotel Management System

## نظرة عامة
نظام مزامنة تلقائية يرسل تحديثات كل دقيقتين (120 ثانية) إلى البريد الإلكتروني `adenmarina2@gmail.com` لضمان المزامنة بين الهاتف والكمبيوتر.

## الميزات الرئيسية
- ✅ مزامنة كل دقيقتين تلقائياً
- 📧 إرسال التحديثات عبر البريد الإلكتروني
- 🔄 مزامنة في الوقت الفعلي من المتصفح
- 📱 دعم العمل أونلاين وأوفلاين
- 📊 مراقبة حالة المزامنة
- 🔍 سجلات مفصلة للأخطاء

## البيانات المتزامنة
1. **الحجوزات الجديدة** - معلومات النزلاء والغرف
2. **المدفوعات** - جميع المعاملات المالية
3. **المصروفات** - مصروفات الفندق اليومية
4. **تغييرات حالة الغرف** - تحديثات الغرف (شاغرة/محجوزة)
5. **التنبيهات** - تنبيهات النظام المهمة

## ملفات النظام

### الملفات الأساسية
- `includes/email_sync.php` - وظائف المزامنة الأساسية
- `sync_cron.php` - ملف المزامنة التلقائية
- `api/email_sync.php` - API للمزامنة
- `assets/js/auto_sync.js` - مزامنة جانب العميل
- `../../scripts/php/maintenance/setup_sync.php` - صفحة إعداد النظام

### ملفات السجلات
- `logs/sync.log` - سجل عمليات المزامنة
- `logs/last_sync.txt` - وقت آخر مزامنة
- `logs/error.log` - سجل الأخطاء

## طريقة التشغيل

### 1. الإعداد الأولي
```bash
# افتح المتصفح وانتقل إلى:
http://localhost/marina-hotel/scripts/php/maintenance/setup_sync.php
```

### 2. إعداد المهمة المجدولة

#### لنظام Windows:
```cmd
# افتح Command Prompt كمدير
schtasks /create /tn "HotelSyncTask" /tr "php C:\xampp\htdocs\marina-hotel\sync_cron.php" /sc minute /mo 2 /f
```

#### لنظام Linux:
```bash
# أضف إلى crontab
crontab -e

# أضف السطر التالي:
*/2 * * * * /usr/bin/php /path/to/marina-hotel/sync_cron.php
```

#### استخدام خدمة Cron Job خارجية:
- انتقل إلى [cron-job.org](https://cron-job.org)
- أنشئ حساب مجاني
- أضف URL: `http://yoursite.com/marina-hotel/sync_cron.php?manual_run=1`
- اضبط التكرار: كل دقيقتين

### 3. اختبار النظام
```bash
# اختبار يدوي
php sync_cron.php test

# تشغيل مزامنة واحدة
php sync_cron.php
```

## إعدادات البريد الإلكتروني

### Gmail Setup
1. انتقل إلى [Google Account Settings](https://myaccount.google.com/)
2. اختر "Security" > "2-Step Verification"
3. أنشئ "App Password" للتطبيق
4. استخدم كلمة المرور هذه في الإعدادات

### تحديث إعدادات البريد
```php
// في ملف includes/email_sync.php
define('SMTP_HOST', 'smtp.gmail.com');
define('SMTP_PORT', 587);
define('SMTP_USERNAME', 'adenmarina2@gmail.com');
define('SMTP_PASSWORD', 'your-app-password-here'); // كلمة مرور التطبيق
```

## مراقبة النظام

### فحص حالة المزامنة
```bash
# عبر المتصفح
http://localhost/marina-hotel/api/email_sync.php?action=status

# عبر سطر الأوامر
curl "http://localhost/marina-hotel/api/email_sync.php?action=status"
```

### عرض السجلات
```bash
# سجل المزامنة
tail -f logs/sync.log

# آخر مزامنة
cat logs/last_sync.txt
```

## استكشاف الأخطاء

### مشاكل شائعة وحلولها

#### 1. فشل إرسال البريد الإلكتروني
```bash
# تحقق من إعدادات SMTP
# تأكد من كلمة مرور التطبيق
# تحقق من اتصال الإنترنت
```

#### 2. عدم تشغيل المهمة المجدولة
```bash
# Windows: تحقق من Task Scheduler
# Linux: تحقق من crontab -l
# تأكد من مسار PHP الصحيح
```

#### 3. مشاكل قاعدة البيانات
```sql
-- تحقق من الجداول المطلوبة
SHOW TABLES LIKE 'sync_events';
SHOW TABLES LIKE 'room_status_log';

-- إنشاء الجداول يدوياً إذا لزم الأمر
CREATE TABLE sync_events (
    id INT AUTO_INCREMENT PRIMARY KEY,
    event_type VARCHAR(50) NOT NULL,
    event_data TEXT,
    timestamp DATETIME NOT NULL,
    synced TINYINT(1) DEFAULT 0
);
```

## API المتاحة

### GET Requests
- `?action=status` - حالة المزامنة
- `?action=test` - اختبار شامل
- `?action=last_sync` - وقت آخر مزامنة
- `?action=run_sync` - تشغيل مزامنة يدوية

### POST Requests
```javascript
// إضافة حدث مزامنة
fetch('api/email_sync.php', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    body: JSON.stringify({
        action: 'add_sync_event',
        type: 'booking',
        data: {guest_name: 'أحمد محمد', room_number: '101'}
    })
});
```

## الأمان والخصوصية
- 🔒 جميع البيانات مشفرة في قاعدة البيانات
- 🛡️ التحقق من صحة جميع المدخلات
- 📧 البريد الإلكتروني محمي بكلمة مرور التطبيق
- 🔐 منع الوصول المباشر للملفات الحساسة

## الدعم والصيانة
- 📝 سجلات تفصيلية لجميع العمليات
- 🔄 إعادة المحاولة التلقائية عند الفشل
- 📊 إحصائيات الأداء والاستخدام
- 🚨 تنبيهات عند حدوث أخطاء

## ملاحظات مهمة
1. تأكد من أن PHP مثبت ومتاح في PATH
2. تحقق من صلاحيات الكتابة في مجلد logs
3. استخدم HTTPS في الإنتاج لحماية البيانات
4. راقب استهلاك البريد الإلكتروني لتجنب الحظر
5. احتفظ بنسخة احتياطية من إعدادات المزامنة

## الترقيات المستقبلية
- 📱 تطبيق موبايل للمزامنة
- ☁️ مزامنة مع التخزين السحابي
- 🔔 إشعارات فورية عبر Telegram/WhatsApp
- 📈 تقارير تحليلية للمزامنة
- 🌐 مزامنة متعددة الفروع
