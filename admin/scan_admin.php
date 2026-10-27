<?php


error_reporting(E_ALL);
ini_set('display_errors', 1);

echo '<pre>';
echo 'مسار المشروع: ' . __DIR__ . "\n";
echo 'هل paths.php موجود؟ ' . (file_exists(__DIR__.'/../paths.php') ? 'نعم' : 'لا') . "\n";
echo 'هل config.php موجود؟ ' . (file_exists(__DIR__.'/../config.php') ? 'نعم' : 'لا') . "\n";
echo '</pre>';


// تحميل مسارات المشروع
require __DIR__ . '/../paths.php';

// تحميل ملفات التهيئة
require BASE_DIR . '/config.php';
require INCLUDES_DIR . '/url_helper.php';

// بدء الجلسة
session_start();

// التحقق من تسجيل الدخول
if (!isset($_SESSION['user_id'])) {
    header('Location: ' . site_url('login.php'));
    exit();
}

// دالة مسح المجلدات (مبسطة)
function scanAdmin() {
    $items = [];
    $dir = ADMIN_DIR;
    
    foreach (new DirectoryIterator($dir) as $file) {
        if ($file->isDot()) continue;
        
        $items[] = [
            'name' => $file->getFilename(),
            'type' => $file->isDir() ? 'folder' : 'file',
            'path' => $file->getPathname()
        ];
    }
    
    return $items;
}

// جلب البيانات
$adminItems = scanAdmin();
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>هيكل المجلدات</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .item { padding: 8px; margin: 4px; border-radius: 4px; }
        .folder { background: #e3f2fd; color: #0d47a1; }
        .file { background: #e8f5e9; color: #2e7d32; }
    </style>
</head>
<body>
    <h1>محتويات مجلد Admin</h1>
    
    <?php foreach ($adminItems as $item): ?>
        <div class="item <?= $item['type'] ?>">
            <?= $item['type'] === 'folder' ? '📁' : '📄' ?>
            <?= htmlspecialchars($item['name']) ?>
        </div>
    <?php endforeach; ?>
</body>
</html>