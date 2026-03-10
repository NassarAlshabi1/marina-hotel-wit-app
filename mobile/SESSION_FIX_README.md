# إصلاح تحذيرات الجلسة (Session Warnings)

## المشكلة
كانت هناك تحذيرات PHP تظهر عند محاولة تغيير إعدادات الجلسة بعد بدء الجلسة:

```
Warning: ini_set(): A session is active. You cannot change the session module's ini settings at this time
```

## السبب
الكود كان يحاول تعديل إعدادات الجلسة باستخدام `ini_set()` بعد استدعاء `session_start()`. يجب تعيين إعدادات الجلسة **قبل** بدء الجلسة.

## الملفات التي تم إصلاحها

### 1. `includes/auth.php`
**قبل الإصلاح:**
```php
if (session_status() == PHP_SESSION_NONE) {
    session_start();
}

ini_set('session.cookie_httponly', 1);
ini_set('session.cookie_secure', 1);
ini_set('session.use_strict_mode', 1);
```

**بعد الإصلاح:**
```php
if (session_status() == PHP_SESSION_NONE) {
    ini_set('session.cookie_httponly', 1);
    ini_set('session.cookie_secure', 1);
    ini_set('session.use_strict_mode', 1);
    session_start();
}
```

### 2. `includes/auth_check_modified.php`
تم إصلاح نفس المشكلة مع إضافة تعليق توضيحي.

### 3. `includes/auth_check_finance.php`
تم إصلاح نفس المشكلة مع إضافة تعليق توضيحي.

## الملف الجديد: `includes/session_manager.php`

تم إنشاء مدير جلسات موحد يوفر:

### الميزات الرئيسية:
1. **بدء جلسة آمنة**: `start_secure_session()`
2. **التحقق من صحة الجلسة**: `validate_session()`
3. **تدمير الجلسة الآمن**: `destroy_secure_session()`
4. **إدارة تسجيل الدخول**: `login_user()` و `logout_user()`
5. **التحقق من الصلاحيات**: `check_user_permission()`
6. **حماية CSRF**: `generate_csrf_token()` و `validate_csrf_token()`

### إعدادات الأمان المطبقة:
- `session.cookie_httponly = 1` - منع الوصول للكوكيز عبر JavaScript
- `session.cookie_secure = 1` - إرسال الكوكيز عبر HTTPS فقط
- `session.use_strict_mode = 1` - رفض معرفات الجلسة غير المعروفة
- `session.use_only_cookies = 1` - استخدام الكوكيز فقط لتخزين معرف الجلسة
- انتهاء صلاحية الجلسة بعد فترة عدم نشاط
- تجديد معرف الجلسة لمنع session fixation

## كيفية الاستخدام

### للملفات الجديدة:
```php
<?php
require_once 'includes/config.php';
require_once 'includes/session_manager.php';

// الجلسة تبدأ تلقائياً عند تضمين session_manager.php

// التحقق من تسجيل الدخول
if (!is_user_logged_in()) {
    redirect_if_not_logged_in();
}

// التحقق من الصلاحيات
if (!check_user_permission('manage_users')) {
    die('ليس لديك صلاحية للوصول إلى هذه الصفحة');
}
?>
```

### لتسجيل الدخول:
```php
<?php
require_once 'includes/session_manager.php';

// بعد التحقق من بيانات المستخدم
$user_data = [
    'user_id' => $user['user_id'],
    'username' => $user['username'],
    'user_type' => $user['user_type'],
    'full_name' => $user['full_name'],
    'permissions' => $user_permissions // اختياري
];

login_user($user_data);
header('Location: admin/dash.php');
exit;
?>
```

### لتسجيل الخروج:
```php
<?php
require_once 'includes/session_manager.php';
logout_user('/login.php');
?>
```

## الفوائد

### 1. **إزالة التحذيرات**
- لا مزيد من تحذيرات `ini_set()` بعد بدء الجلسة

### 2. **أمان محسن**
- إعدادات أمان موحدة في جميع أنحاء النظام
- حماية من session fixation
- انتهاء صلاحية تلقائي للجلسات

### 3. **سهولة الصيانة**
- كود موحد لإدارة الجلسات
- تقليل التكرار في الكود
- سهولة إضافة ميزات أمان جديدة

### 4. **مرونة أكبر**
- دوال مساعدة للتحقق من الصلاحيات
- إدارة CSRF tokens
- تتبع عناوين IP

## التوافق مع النظام الحالي

الملفات الحالية ستستمر في العمل بدون تغيير، لكن يُنصح بـ:

1. **للملفات الجديدة**: استخدام `session_manager.php`
2. **للملفات الموجودة**: التحديث التدريجي عند الحاجة
3. **عدم خلط الطرق**: تجنب استخدام الطريقتين في نفس الملف

## اختبار الإصلاح

1. **تصفح أي صفحة في النظام**
2. **تحقق من عدم ظهور تحذيرات الجلسة**
3. **تأكد من عمل تسجيل الدخول والخروج**
4. **اختبر انتهاء صلاحية الجلسة**

## ملاحظات مهمة

- **البيئة المحلية**: `session.cookie_secure` قد يحتاج تعطيل في localhost
- **HTTPS**: في الإنتاج، تأكد من استخدام HTTPS لتفعيل الكوكيز الآمنة
- **المهلة الزمنية**: يمكن تعديل `SESSION_TIMEOUT` في `config.php`

## استكشاف الأخطاء

إذا واجهت مشاكل:

1. **تحقق من `config.php`**: تأكد من تعريف `SESSION_TIMEOUT`
2. **فحص السجلات**: راجع ملفات السجل للأخطاء
3. **اختبار الجلسة**: استخدم `var_dump($_SESSION)` للتشخيص
4. **مسح الكوكيز**: امسح كوكيز المتصفح وأعد المحاولة
