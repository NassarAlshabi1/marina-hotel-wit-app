<?php
/**
 * ملف الإعدادات الرئيسي للنظام
 * يحتوي على جميع الإعدادات الأساسية والثوابت
 */

// إعدادات قاعدة البيانات
define('DB_HOST', 'localhost');
define('DB_USER', 'root');
define('DB_PASS', '');
define('DB_NAME', 'hotel_db');

// إعدادات الترميز والمنطقة الزمنية
define('DB_CHARSET', 'utf8mb4');
define('DB_COLLATE', 'utf8mb4_unicode_ci');
define('TIMEZONE', 'Asia/Aden');

// إعدادات اللغة
define('LANG', 'ar');
define('LANG_DIR', 'rtl');

// إعدادات النظام
define('SYSTEM_NAME', 'نظام إدارة فندق مارينا بلازا');
define('SYSTEM_VERSION', '2.0.0');
define('DEBUG_MODE', true); // تغيير إلى false في الإنتاج

// إعدادات الأمان
define('SESSION_TIMEOUT', 1800); // 30 دقيقة
define('MAX_LOGIN_ATTEMPTS', 5);
define('LOCKOUT_TIME', 900); // 15 دقيقة

// إعدادات الملفات
define('UPLOAD_MAX_SIZE', 5 * 1024 * 1024); // 5 ميجابايت
define('ALLOWED_EXTENSIONS', ['jpg', 'jpeg', 'png', 'pdf', 'doc', 'docx']);

// إعدادات المسار الأساسي للتطبيق
define('BASE_URL', 'http://localhost/marina%20hotel/');

// مسارات النظام
define('ROOT_PATH', dirname(__DIR__));
define('INCLUDES_PATH', ROOT_PATH . '/includes');
define('UPLOADS_PATH', ROOT_PATH . '/uploads');
define('LOGS_PATH', ROOT_PATH . '/logs');

// تعيين الترميز الافتراضي
ini_set('default_charset', 'UTF-8');
mb_internal_encoding('UTF-8');
mb_http_output('UTF-8');

// تعيين المنطقة الزمنية
date_default_timezone_set(TIMEZONE);

// تعيين اللغة المحلية
setlocale(LC_ALL, 'ar_SA.UTF-8', 'ar_AE.UTF-8', 'ar.UTF-8');

// إعدادات عرض الأخطاء حسب وضع التطوير
if (DEBUG_MODE) {
    ini_set('display_errors', 1);
    ini_set('display_startup_errors', 1);
    error_reporting(E_ALL);
} else {
    ini_set('display_errors', 0);
    ini_set('display_startup_errors', 0);
    error_reporting(E_ERROR | E_WARNING | E_PARSE);
}

// إنشاء المجلدات المطلوبة إذا لم تكن موجودة
$required_dirs = [UPLOADS_PATH, LOGS_PATH];
foreach ($required_dirs as $dir) {
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }
}

// تحميل معالج الأخطاء
require_once INCLUDES_PATH . '/error_handler.php';
?>
