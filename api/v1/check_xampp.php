<?php
/**
 * فحص إعدادات XAMPP والتأكد من جاهزية النظام
 * افتح: http://localhost/marina-hotel-wit-app/api/v1/check_xampp.php
 */

header('Content-Type: text/html; charset=utf-8');

echo "<!DOCTYPE html><html><head><meta charset='utf-8'><title>فحص XAMPP</title>";
echo "<style>
body{font-family:Arial,sans-serif;max-width:900px;margin:30px auto;padding:20px;direction:rtl;background:#f5f5f5;}
.card{background:white;padding:20px;margin:15px 0;border-radius:8px;box-shadow:0 2px 4px rgba(0,0,0,0.1);}
.success{color:green;} .error{color:red;} .warning{color:orange;} .info{color:blue;}
.check-item{padding:10px;margin:5px 0;border-left:4px solid #ddd;background:#fafafa;}
.check-item.pass{border-left-color:green;background:#f0f9f0;}
.check-item.fail{border-left-color:red;background:#fff0f0;}
.check-item.warn{border-left-color:orange;background:#fff8f0;}
h1{color:#333;border-bottom:3px solid #4CAF50;padding-bottom:10px;}
h2{color:#555;margin-top:25px;}
.status{font-weight:bold;float:left;padding:3px 10px;border-radius:3px;color:white;}
.status.ok{background:green;} .status.fail{background:red;} .status.warn{background:orange;}
table{width:100%;border-collapse:collapse;margin:15px 0;}
table td{padding:8px;border:1px solid #ddd;}
table tr:nth-child(even){background:#f9f9f9;}
code{background:#f4f4f4;padding:2px 6px;border-radius:3px;font-family:monospace;color:#d63384;}
.footer{text-align:center;margin-top:40px;padding:20px;color:#666;border-top:2px solid #eee;}
</style></head><body>";

echo "<h1>🔍 فحص إعدادات XAMPP</h1>";

$checks = [];
$errors = [];
$warnings = [];

// ====================================
// 1. فحص PHP
// ====================================
echo "<div class='card'>";
echo "<h2>1️⃣ فحص PHP</h2>";

$phpVersion = phpversion();
$phpOk = version_compare($phpVersion, '7.4.0', '>=');
echo "<div class='check-item " . ($phpOk ? 'pass' : 'fail') . "'>";
echo "<span class='status " . ($phpOk ? 'ok' : 'fail') . "'>" . ($phpOk ? '✓' : '✗') . "</span>";
echo "<strong>PHP Version:</strong> $phpVersion " . ($phpOk ? '(مناسب ✓)' : '(يجب 7.4 أو أعلى ✗)');
echo "</div>";

$extensions = ['mysqli', 'json', 'mbstring', 'openssl', 'fileinfo'];
foreach ($extensions as $ext) {
    $loaded = extension_loaded($ext);
    echo "<div class='check-item " . ($loaded ? 'pass' : 'fail') . "'>";
    echo "<span class='status " . ($loaded ? 'ok' : 'fail') . "'>" . ($loaded ? '✓' : '✗') . "</span>";
    echo "<strong>Extension $ext:</strong> " . ($loaded ? 'مفعّل ✓' : 'غير مفعّل ✗');
    echo "</div>";
    if (!$loaded) $errors[] = "Extension $ext غير مفعّل";
}

echo "<table>";
echo "<tr><td><strong>memory_limit</strong></td><td>" . ini_get('memory_limit') . "</td></tr>";
echo "<tr><td><strong>max_execution_time</strong></td><td>" . ini_get('max_execution_time') . "s</td></tr>";
echo "<tr><td><strong>upload_max_filesize</strong></td><td>" . ini_get('upload_max_filesize') . "</td></tr>";
echo "<tr><td><strong>post_max_size</strong></td><td>" . ini_get('post_max_size') . "</td></tr>";
echo "</table>";
echo "</div>";

// ====================================
// 2. فحص MySQL
// ====================================
echo "<div class='card'>";
echo "<h2>2️⃣ فحص MySQL</h2>";

try {
    require_once __DIR__ . '/../../includes/config.php';
    require_once __DIR__ . '/../../includes/db.php';
    
    echo "<div class='check-item pass'>";
    echo "<span class='status ok'>✓</span>";
    echo "<strong>اتصال MySQL:</strong> نجح ✓";
    echo "</div>";
    
    $version = $conn->server_info;
    echo "<div class='check-item pass'>";
    echo "<span class='status ok'>✓</span>";
    echo "<strong>MySQL Version:</strong> $version";
    echo "</div>";
    
    $charset = $conn->character_set_name();
    $charsetOk = ($charset === 'utf8mb4' || $charset === 'utf8');
    echo "<div class='check-item " . ($charsetOk ? 'pass' : 'warn') . "'>";
    echo "<span class='status " . ($charsetOk ? 'ok' : 'warn') . "'>" . ($charsetOk ? '✓' : '⚠') . "</span>";
    echo "<strong>Character Set:</strong> $charset " . ($charsetOk ? '✓' : '(يفضل utf8mb4)');
    echo "</div>";
    
    // فحص الجداول
    $tables = ['users', 'rooms', 'bookings', 'employees', 'expenses', 'payments', 'expense_categories', 'shift_notes', 'daily_closures'];
    echo "<h3>الجداول المطلوبة:</h3>";
    
    foreach ($tables as $table) {
        $result = $conn->query("SHOW TABLES LIKE '$table'");
        $exists = $result->num_rows > 0;
        echo "<div class='check-item " . ($exists ? 'pass' : 'fail') . "'>";
        echo "<span class='status " . ($exists ? 'ok' : 'fail') . "'>" . ($exists ? '✓' : '✗') . "</span>";
        echo "<strong>جدول $table:</strong> " . ($exists ? 'موجود ✓' : 'غير موجود ✗');
        echo "</div>";
        if (!$exists) $errors[] = "جدول $table غير موجود";
    }
    
} catch (Exception $e) {
    echo "<div class='check-item fail'>";
    echo "<span class='status fail'>✗</span>";
    echo "<strong>اتصال MySQL:</strong> فشل ✗";
    echo "<br><small>" . htmlspecialchars($e->getMessage()) . "</small>";
    echo "</div>";
    $errors[] = "فشل الاتصال بـ MySQL: " . $e->getMessage();
}

echo "</div>";

// ====================================
// 3. فحص الملفات والمجلدات
// ====================================
echo "<div class='card'>";
echo "<h2>3️⃣ فحص الملفات والمجلدات</h2>";

$paths = [
    'includes/config.php' => __DIR__ . '/../../includes/config.php',
    'includes/db.php' => __DIR__ . '/../../includes/db.php',
    'api/v1/config.php' => __DIR__ . '/config.php',
    'api/v1/core/errors.php' => __DIR__ . '/core/errors.php',
    'api/v1/core/validator.php' => __DIR__ . '/core/validator.php',
    'api/v1/core/middleware.php' => __DIR__ . '/core/middleware.php',
    'logs/' => __DIR__ . '/../../logs/'
];

foreach ($paths as $name => $path) {
    $exists = file_exists($path);
    $isDir = is_dir($path);
    $writable = is_writable($path);
    
    echo "<div class='check-item " . ($exists ? ($writable || !$isDir ? 'pass' : 'warn') : 'fail') . "'>";
    echo "<span class='status " . ($exists ? ($writable || !$isDir ? 'ok' : 'warn') : 'fail') . "'>" . ($exists ? ($writable || !$isDir ? '✓' : '⚠') : '✗') . "</span>";
    echo "<strong>$name:</strong> " . ($exists ? 'موجود ✓' : 'غير موجود ✗');
    
    if ($isDir && !$writable) {
        echo " <span class='warning'>(غير قابل للكتابة ⚠)</span>";
        $warnings[] = "$name غير قابل للكتابة";
    }
    echo "</div>";
    
    if (!$exists) $errors[] = "$name غير موجود";
}

echo "</div>";

// ====================================
// 4. فحص Apache Modules
// ====================================
echo "<div class='card'>";
echo "<h2>4️⃣ فحص Apache Modules</h2>";

if (function_exists('apache_get_modules')) {
    $modules = apache_get_modules();
    $required = ['mod_rewrite', 'mod_headers'];
    
    foreach ($required as $mod) {
        $loaded = in_array($mod, $modules);
        echo "<div class='check-item " . ($loaded ? 'pass' : 'warn') . "'>";
        echo "<span class='status " . ($loaded ? 'ok' : 'warn') . "'>" . ($loaded ? '✓' : '⚠') . "</span>";
        echo "<strong>$mod:</strong> " . ($loaded ? 'مفعّل ✓' : 'غير مفعّل (قد يؤثر على CORS) ⚠');
        echo "</div>";
        if (!$loaded) $warnings[] = "$mod غير مفعّل";
    }
} else {
    echo "<div class='check-item warn'>";
    echo "<span class='status warn'>⚠</span>";
    echo "<strong>Apache Modules:</strong> لا يمكن الفحص (php_sapi_name: " . php_sapi_name() . ")";
    echo "</div>";
}

echo "</div>";

// ====================================
// 5. فحص Endpoints
// ====================================
echo "<div class='card'>";
echo "<h2>5️⃣ فحص API Endpoints</h2>";

$baseUrl = 'http://' . ($_SERVER['HTTP_HOST'] ?? 'localhost') . '/marina-hotel-wit-app/api/v1/';

$endpoints = [
    'health.php' => 'Health Check',
    'auth/login.php' => 'Login',
    'auth/ping.php' => 'Ping',
    'sync/pull.php' => 'Pull Sync',
    'sync/push.php' => 'Push Sync',
    'entities/rooms.php' => 'Rooms API'
];

foreach ($endpoints as $endpoint => $name) {
    $url = $baseUrl . $endpoint;
    echo "<div class='check-item pass'>";
    echo "<span class='status ok'>ℹ</span>";
    echo "<strong>$name:</strong> <a href='$url' target='_blank'>$url</a>";
    echo "</div>";
}

echo "</div>";

// ====================================
// 6. النتيجة النهائية
// ====================================
echo "<div class='card'>";
echo "<h2>📊 النتيجة النهائية</h2>";

if (empty($errors)) {
    echo "<div class='check-item pass' style='font-size:18px;'>";
    echo "<span class='status ok'>✅</span>";
    echo "<strong>جميع الفحوصات نجحت! النظام جاهز للعمل 🎉</strong>";
    echo "</div>";
    
    echo "<h3>الخطوات التالية:</h3>";
    echo "<ol>";
    echo "<li>تشغيل setup.php: <a href='setup.php' target='_blank'>setup.php</a></li>";
    echo "<li>إنشاء مستخدم admin: <a href='create_admin.php' target='_blank'>create_admin.php</a></li>";
    echo "<li>اختبار API: <a href='health.php' target='_blank'>health.php</a></li>";
    echo "<li>استخدام Postman Collection</li>";
    echo "<li>تشغيل Flutter App</li>";
    echo "</ol>";
} else {
    echo "<div class='check-item fail' style='font-size:18px;'>";
    echo "<span class='status fail'>❌</span>";
    echo "<strong>هناك " . count($errors) . " خطأ يجب إصلاحه</strong>";
    echo "</div>";
    
    echo "<h3>الأخطاء:</h3>";
    echo "<ul>";
    foreach ($errors as $error) {
        echo "<li class='error'>$error</li>";
    }
    echo "</ul>";
}

if (!empty($warnings)) {
    echo "<h3>⚠ تحذيرات:</h3>";
    echo "<ul>";
    foreach ($warnings as $warning) {
        echo "<li class='warning'>$warning</li>";
    }
    echo "</ul>";
}

echo "</div>";

echo "<div class='footer'>";
echo "<p>Marina Hotel API v1.0 | Powered by XAMPP</p>";
echo "<p>لمزيد من المساعدة، راجع: <a href='../../XAMPP_SETUP_GUIDE.md'>XAMPP Setup Guide</a></p>";
echo "</div>";

echo "</body></html>";
