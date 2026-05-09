<?php
// إعدادات قاعدة البيانات للتطبيق المحول إلى EXE
// تستخدم SQLite لقاعدة بيانات محلية سريعة

// إعدادات قاعدة البيانات
define('DB_TYPE', 'sqlite');
define('DB_PATH', __DIR__ . '/../data/marina_hotel.db');
define('DB_HOST', 'localhost');
define('DB_NAME', 'marina_hotel');
define('DB_USER', 'root');
define('DB_PASS', '');

// إعدادات التطبيق
define('SITE_NAME', 'Marina Hotel Management System');
define('SITE_URL', 'http://localhost:8080');
define('UPLOAD_PATH', __DIR__ . '/../uploads/');
define('REPORTS_PATH', __DIR__ . '/../uploads/reports/');

// إعدادات الأمان
define('HASH_SALT', 'marina_hotel_security_2024');
define('SESSION_TIMEOUT', 7200); // 2 ساعة

// إعدادات الجلسة
ini_set('session.cookie_lifetime', SESSION_TIMEOUT);
ini_set('session.gc_maxlifetime', SESSION_TIMEOUT);
ini_set('session.cookie_httponly', 1);
ini_set('session.cookie_secure', 0); // محلي فقط
ini_set('session.use_strict_mode', 1);

// إعدادات الوقت
date_default_timezone_set('Asia/Riyadh');

// إعدادات الترميز
ini_set('default_charset', 'UTF-8');
mb_internal_encoding('UTF-8');

// إعدادات الأخطاء (إخفاء في الإنتاج)
error_reporting(E_ALL & ~E_NOTICE & ~E_STRICT & ~E_DEPRECATED);
ini_set('display_errors', 0);
ini_set('log_errors', 1);
ini_set('error_log', __DIR__ . '/../logs/error.log');

// إنشاء مجلدات مطلوبة
$required_dirs = [
    __DIR__ . '/../data',
    __DIR__ . '/../logs',
    __DIR__ . '/../uploads',
    __DIR__ . '/../uploads/reports'
];

foreach ($required_dirs as $dir) {
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
    }
}

// دالة للاتصال بقاعدة البيانات
function getDBConnection() {
    try {
        if (DB_TYPE == 'sqlite') {
            $db = new PDO('sqlite:' . DB_PATH);
            $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            $db->exec('PRAGMA foreign_keys = ON');
            return $db;
        } else {
            $dsn = "mysql:host=" . DB_HOST . ";dbname=" . DB_NAME . ";charset=utf8";
            $db = new PDO($dsn, DB_USER, DB_PASS);
            $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
            return $db;
        }
    } catch (PDOException $e) {
        error_log("Database connection failed: " . $e->getMessage());
        return false;
    }
}

// إنشاء قاعدة البيانات إذا لم تكن موجودة
function initializeDatabase() {
    if (!file_exists(DB_PATH)) {
        $db = getDBConnection();
        if ($db) {
            // إنشاء جداول قاعدة البيانات
            $sql = file_get_contents(__DIR__ . '/../hotel_db.sql');
            if ($sql) {
                $db->exec($sql);
            }
        }
    }
}

// تشغيل التهيئة
initializeDatabase();
?>