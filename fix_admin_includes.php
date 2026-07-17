<?php
/**
 * سكريبت بسيط لإصلاح مسارات includes في ملفات admin
 */

echo "<h2>إصلاح مسارات includes في ملفات admin</h2>";

$admin_dir = __DIR__ . '/admin';
$fixed_files = 0;
$total_fixes = 0;

// دالة للحصول على جميع ملفات PHP
function getAllPhpFiles($dir) {
    $files = [];
    $iterator = new RecursiveIteratorIterator(
        new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS)
    );
    
    foreach ($iterator as $file) {
        if ($file->isFile() && $file->getExtension() === 'php') {
            $files[] = $file->getPathname();
        }
    }
    
    return $files;
}

// دالة لإصلاح مسارات include في ملف واحد
function fixIncludesInFile($file_path) {
    $content = file_get_contents($file_path);
    $original_content = $content;
    
    // تحديد عمق المجلد لحساب المسار الصحيح
    $admin_pos = strpos($file_path, '/admin/');
    $relative_path = substr($file_path, $admin_pos + 7); // +7 لـ '/admin/'
    $depth = substr_count($relative_path, '/');
    $prefix = str_repeat('../', $depth + 1);
    
    $fixes = [
        // إصلاح include و require
        "include '../includes/" => "include_once '{$prefix}includes/",
        'include "../includes/' => "include_once '{$prefix}includes/",
        "include '../../includes/" => "include_once '{$prefix}includes/",
        'include "../../includes/' => "include_once '{$prefix}includes/",
        
        "require '../includes/" => "require_once '{$prefix}includes/",
        'require "../includes/' => "require_once '{$prefix}includes/",
        "require '../../includes/" => "require_once '{$prefix}includes/",
        'require "../../includes/' => "require_once '{$prefix}includes/",
        
        "include_once '../includes/" => "include_once '{$prefix}includes/",
        'include_once "../includes/' => "include_once '{$prefix}includes/",
        "include_once '../../includes/" => "include_once '{$prefix}includes/",
        'include_once "../../includes/' => "include_once '{$prefix}includes/",
        
        "require_once '../includes/" => "require_once '{$prefix}includes/",
        'require_once "../includes/' => "require_once '{$prefix}includes/",
        "require_once '../../includes/" => "require_once '{$prefix}includes/",
        'require_once "../../includes/' => "require_once '{$prefix}includes/",
    ];
    
    $file_fixes = 0;
    foreach ($fixes as $search => $replace) {
        $count = 0;
        $content = str_replace($search, $replace, $content, $count);
        $file_fixes += $count;
    }
    
    // حفظ الملف إذا تم تطبيق إصلاحات
    if ($file_fixes > 0) {
        file_put_contents($file_path, $content);
        return $file_fixes;
    }
    
    return 0;
}

// الحصول على جميع ملفات PHP في admin
$php_files = getAllPhpFiles($admin_dir);

echo "<p>تم العثور على " . count($php_files) . " ملف PHP</p>";

foreach ($php_files as $file) {
    $relative_path = str_replace(__DIR__, '', $file);
    $fixes = fixIncludesInFile($file);
    
    if ($fixes > 0) {
        echo "<div style='color: green;'>✓ {$relative_path} - تم إصلاح {$fixes} مسار</div>";
        $fixed_files++;
        $total_fixes += $fixes;
    } else {
        echo "<div style='color: gray;'>- {$relative_path} - لا يحتاج إصلاح</div>";
    }
}

echo "<hr>";
echo "<h3>ملخص النتائج:</h3>";
echo "<p>الملفات المُصلحة: {$fixed_files}</p>";
echo "<p>إجمالي الإصلاحات: {$total_fixes}</p>";

if ($total_fixes > 0) {
    echo "<div style='color: green; font-weight: bold;'>تم إكمال الإصلاحات بنجاح!</div>";
} else {
    echo "<div style='color: blue;'>جميع الملفات سليمة ولا تحتاج إصلاح.</div>";
}

// إضافة فحص config.php في بداية الملفات التي تستخدم BASE_URL
echo "<hr>";
echo "<h3>إضافة فحص config.php:</h3>";

$config_added = 0;
foreach ($php_files as $file) {
    $content = file_get_contents($file);
    $relative_path = str_replace(__DIR__, '', $file);
    
    // التحقق من استخدام BASE_URL
    if (strpos($content, 'BASE_URL') !== false) {
        // التحقق من عدم وجود config.php بالفعل
        if (strpos($content, 'config.php') === false && strpos($content, "<?php") === 0) {
            // إضافة require config.php
            $config_require = "\nif (!defined('BASE_URL')) {\n    require_once __DIR__ . '/../includes/config.php';\n}\n";
            $content = str_replace('<?php', '<?php' . $config_require, $content);
            file_put_contents($file, $content);
            echo "<div style='color: blue;'>+ {$relative_path} - تم إضافة فحص config.php</div>";
            $config_added++;
        }
    }
}

echo "<p>تم إضافة فحص config.php إلى {$config_added} ملف</p>";
?>

<style>
body { font-family: Arial, sans-serif; margin: 20px; direction: rtl; }
</style>

<hr>
<p><strong>تم إكمال جميع الإصلاحات!</strong></p>
<p>الآن يمكنك تصفح لوحة الإدارة والتأكد من عمل جميع الملفات والقوائم بشكل صحيح.</p>