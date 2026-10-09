<?php
/**
 * تحديث مسارات الموارد للعمل بدون انترنت
 * يقوم بفحص وتحديث جميع الملفات لاستخدام الموارد المحلية
 */

require_once 'includes/config.php';

echo "<!DOCTYPE html>\n";
echo "<html lang='ar' dir='rtl'>\n";
echo "<head>\n";
echo "<meta charset='UTF-8'>\n";
echo "<meta name='viewport' content='width=device-width, initial-scale=1.0'>\n";
echo "<title>تحديث الموارد للعمل بدون انترنت</title>\n";
echo "<style>\n";
echo "body { font-family: Arial, sans-serif; direction: rtl; text-align: right; padding: 20px; background: #f8f9fa; }\n";
echo ".container { max-width: 800px; margin: 0 auto; background: white; padding: 20px; border-radius: 10px; box-shadow: 0 4px 15px rgba(0,0,0,0.1); }\n";
echo ".success { color: #28a745; }\n";
echo ".error { color: #dc3545; }\n";
echo ".warning { color: #ffc107; }\n";
echo ".info { color: #17a2b8; }\n";
echo "pre { background: #f8f9fa; padding: 10px; border-radius: 5px; overflow-x: auto; }\n";
echo "</style>\n";
echo "</head>\n";
echo "<body>\n";
echo "<div class='container'>\n";
echo "<h1>🔄 تحديث الموارد للعمل بدون انترنت</h1>\n";

// دوال المساعدة
function logMessage($message, $type = 'info') {
    $colors = [
        'success' => '#28a745',
        'error' => '#dc3545', 
        'warning' => '#ffc107',
        'info' => '#17a2b8'
    ];
    
    $color = $colors[$type] ?? $colors['info'];
    echo "<p style='color: $color;'><strong>[" . strtoupper($type) . "]</strong> $message</p>\n";
}

function updateFileContent($filePath, $replacements) {
    if (!file_exists($filePath)) {
        logMessage("الملف غير موجود: $filePath", 'error');
        return false;
    }
    
    $content = file_get_contents($filePath);
    $originalContent = $content;
    
    foreach ($replacements as $search => $replace) {
        $content = str_replace($search, $replace, $content);
    }
    
    if ($content !== $originalContent) {
        if (file_put_contents($filePath, $content)) {
            logMessage("تم تحديث الملف: $filePath", 'success');
            return true;
        } else {
            logMessage("فشل في كتابة الملف: $filePath", 'error');
            return false;
        }
    }
    
    logMessage("لا توجد تغييرات مطلوبة في: $filePath", 'info');
    return true;
}

// قائمة الملفات للتحديث
$filesToUpdate = [
    'includes/header.php',
    'includes/header2.php',
    'includes/simple-header.php',
    'includes/footer.php'
];

// التحديثات المطلوبة
$replacements = [
    // Bootstrap CSS
    'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' => 'assets/css/bootstrap-complete.css',
    'https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/css/bootstrap.min.css' => 'assets/css/bootstrap-complete.css',
    'https://stackpath.bootstrapcdn.com/bootstrap/5.3.0/css/bootstrap.min.css' => 'assets/css/bootstrap-complete.css',
    
    // Bootstrap RTL
    'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.rtl.min.css' => 'assets/css/bootstrap-complete.css',
    
    // Font Awesome
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css' => 'assets/css/fontawesome.min.css',
    'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css' => 'assets/css/fontawesome.min.css',
    'https://use.fontawesome.com/releases/v6.4.0/css/all.css' => 'assets/css/fontawesome.min.css',
    
    // Google Fonts
    'https://fonts.googleapis.com/css2?family=Tajawal:wght@200;300;400;500;700;800;900&display=swap' => 'assets/fonts/fonts.css',
    'https://fonts.googleapis.com/css?family=Tajawal:200,300,400,500,700,800,900' => 'assets/fonts/fonts.css',
    
    // Bootstrap JavaScript
    'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js' => 'assets/js/bootstrap-local.js',
    'https://cdn.jsdelivr.net/npm/bootstrap@5.2.3/dist/js/bootstrap.bundle.min.js' => 'assets/js/bootstrap-local.js',
    'https://stackpath.bootstrapcdn.com/bootstrap/5.3.0/js/bootstrap.bundle.min.js' => 'assets/js/bootstrap-local.js',
    
    // jQuery
    'https://code.jquery.com/jquery-3.6.0.min.js' => 'assets/js/jquery.min.js',
    'https://ajax.googleapis.com/ajax/libs/jquery/3.6.0/jquery.min.js' => 'assets/js/jquery.min.js'
];

logMessage("بدء عملية تحديث الملفات...", 'info');

$updatedFiles = 0;
$failedFiles = 0;

// تحديث الملفات
foreach ($filesToUpdate as $file) {
    $fullPath = __DIR__ . '/' . $file;
    
    if (updateFileContent($fullPath, $replacements)) {
        $updatedFiles++;
    } else {
        $failedFiles++;
    }
}

echo "<hr>\n";

// البحث عن ملفات إضافية تحتاج تحديث
logMessage("البحث عن ملفات إضافية تحتاج تحديث...", 'info');

$additionalFiles = [];
$directories = ['admin', 'api'];

foreach ($directories as $dir) {
    if (is_dir($dir)) {
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($dir),
            RecursiveIteratorIterator::LEAVES_ONLY
        );
        
        foreach ($iterator as $file) {
            if ($file->isFile() && $file->getExtension() === 'php') {
                $content = file_get_contents($file->getPathname());
                
                // فحص وجود روابط خارجية
                if (preg_match('/https:\/\/(cdn\.jsdelivr\.net|cdnjs\.cloudflare\.com|fonts\.googleapis\.com|stackpath\.bootstrapcdn\.com)/', $content)) {
                    $additionalFiles[] = $file->getPathname();
                }
            }
        }
    }
}

if (!empty($additionalFiles)) {
    logMessage("تم العثور على " . count($additionalFiles) . " ملف إضافي يحتاج تحديث", 'warning');
    
    foreach ($additionalFiles as $file) {
        if (updateFileContent($file, $replacements)) {
            $updatedFiles++;
        } else {
            $failedFiles++;
        }
    }
}

echo "<hr>\n";

// فحص الموارد المحلية
logMessage("فحص توفر الموارد المحلية...", 'info');

$requiredAssets = [
    'assets/fonts/fonts.css',
    'assets/css/bootstrap-complete.css',
    'assets/css/fontawesome.min.css',
    'assets/css/arabic-enhanced.css',
    'assets/js/bootstrap-local.js',
    'assets/js/enhanced-ui.js',
    'assets/js/jquery.min.js'
];

$missingAssets = [];
foreach ($requiredAssets as $asset) {
    if (!file_exists($asset)) {
        $missingAssets[] = $asset;
    }
}

if (empty($missingAssets)) {
    logMessage("✅ جميع الموارد المطلوبة متوفرة محلياً!", 'success');
} else {
    logMessage("⚠️ بعض الموارد المطلوبة مفقودة:", 'warning');
    foreach ($missingAssets as $asset) {
        echo "<div style='margin-right: 20px; color: #dc3545;'>❌ $asset</div>\n";
    }
}

echo "<hr>\n";

// إنشاء ملف تكوين للموارد المحلية
logMessage("إنشاء ملف تكوين الموارد المحلية...", 'info');

$configContent = "<?php\n";
$configContent .= "/**\n";
$configContent .= " * تكوين الموارد المحلية للعمل بدون انترنت\n";
$configContent .= " * تم إنشاؤه تلقائياً في: " . date('Y-m-d H:i:s') . "\n";
$configContent .= " */\n\n";
$configContent .= "// حالة الموارد المحلية\n";
$configContent .= "define('OFFLINE_MODE_ENABLED', true);\n";
$configContent .= "define('LOCAL_ASSETS_VERSION', '" . date('Y.m.d.His') . "');\n\n";
$configContent .= "// مسارات الموارد المحلية\n";
$configContent .= "define('LOCAL_BOOTSTRAP_CSS', 'assets/css/bootstrap-complete.css');\n";
$configContent .= "define('LOCAL_FONTAWESOME_CSS', 'assets/css/fontawesome.min.css');\n";
$configContent .= "define('LOCAL_FONTS_CSS', 'assets/fonts/fonts.css');\n";
$configContent .= "define('LOCAL_BOOTSTRAP_JS', 'assets/js/bootstrap-local.js');\n";
$configContent .= "define('LOCAL_JQUERY_JS', 'assets/js/jquery.min.js');\n\n";
$configContent .= "// إحصائيات التحديث\n";
$configContent .= "define('LAST_UPDATE_DATE', '" . date('Y-m-d H:i:s') . "');\n";
$configContent .= "define('UPDATED_FILES_COUNT', $updatedFiles);\n";
$configContent .= "define('FAILED_FILES_COUNT', $failedFiles);\n";
$configContent .= "?>";

if (file_put_contents('includes/offline_config.php', $configContent)) {
    logMessage("تم إنشاء ملف التكوين: includes/offline_config.php", 'success');
} else {
    logMessage("فشل في إنشاء ملف التكوين", 'error');
}

echo "<hr>\n";

// إنشاء ملف .htaccess للتحسين
logMessage("إنشاء ملف .htaccess للتحسين...", 'info');

$htaccessContent = "# تحسينات للعمل بدون انترنت\n";
$htaccessContent .= "# تم إنشاؤه تلقائياً في: " . date('Y-m-d H:i:s') . "\n\n";
$htaccessContent .= "# تفعيل الضغط\n";
$htaccessContent .= "<IfModule mod_deflate.c>\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE text/plain\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE text/html\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE text/xml\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE text/css\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE application/xml\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE application/xhtml+xml\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE application/rss+xml\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE application/javascript\n";
$htaccessContent .= "    AddOutputFilterByType DEFLATE application/x-javascript\n";
$htaccessContent .= "</IfModule>\n\n";
$htaccessContent .= "# تعيين انتهاء صلاحية الملفات الثابتة\n";
$htaccessContent .= "<IfModule mod_expires.c>\n";
$htaccessContent .= "    ExpiresActive on\n";
$htaccessContent .= "    ExpiresByType text/css \"access plus 1 month\"\n";
$htaccessContent .= "    ExpiresByType application/javascript \"access plus 1 month\"\n";
$htaccessContent .= "    ExpiresByType image/png \"access plus 1 month\"\n";
$htaccessContent .= "    ExpiresByType image/jpg \"access plus 1 month\"\n";
$htaccessContent .= "    ExpiresByType image/jpeg \"access plus 1 month\"\n";
$htaccessContent .= "    ExpiresByType font/woff \"access plus 1 month\"\n";
$htaccessContent .= "    ExpiresByType font/woff2 \"access plus 1 month\"\n";
$htaccessContent .= "</IfModule>\n";

if (file_put_contents('assets/.htaccess', $htaccessContent)) {
    logMessage("تم إنشاء ملف .htaccess: assets/.htaccess", 'success');
} else {
    logMessage("فشل في إنشاء ملف .htaccess", 'error');
}

echo "<hr>\n";

// النتائج النهائية
echo "<div style='background: #e9ecef; padding: 15px; border-radius: 5px; margin-top: 20px;'>\n";
echo "<h3>📊 ملخص النتائج</h3>\n";
echo "<ul>\n";
echo "<li><strong>الملفات المحدثة بنجاح:</strong> <span style='color: #28a745;'>$updatedFiles</span></li>\n";
echo "<li><strong>الملفات التي فشل تحديثها:</strong> <span style='color: #dc3545;'>$failedFiles</span></li>\n";
echo "<li><strong>الموارد المفقودة:</strong> <span style='color: #ffc107;'>" . count($missingAssets) . "</span></li>\n";
echo "<li><strong>حالة النظام:</strong> ";

if ($failedFiles == 0 && empty($missingAssets)) {
    echo "<span style='color: #28a745;'>جاهز للعمل بدون انترنت! ✅</span>";
} elseif ($failedFiles == 0) {
    echo "<span style='color: #ffc107;'>جاهز جزئياً (بعض الموارد مفقودة) ⚠️</span>";
} else {
    echo "<span style='color: #dc3545;'>يحتاج إلى إصلاح ❌</span>";
}

echo "</li>\n";
echo "</ul>\n";
echo "</div>\n";

// روابط للاختبار
echo "<div style='margin-top: 20px;'>\n";
echo "<h3>🔗 روابط مفيدة</h3>\n";
echo "<p>\n";
echo "<a href='test_offline.php' style='color: #007bff; text-decoration: none; margin-left: 15px;'>🧪 اختبار العمل بدون انترنت</a>\n";
echo "<a href='admin/dashboard.php' style='color: #007bff; text-decoration: none; margin-left: 15px;'>🏠 لوحة التحكم</a>\n";
echo "<a href='system_health_report.php' style='color: #007bff; text-decoration: none; margin-left: 15px;'>📊 تقرير صحة النظام</a>\n";
echo "</p>\n";
echo "</div>\n";

logMessage("انتهت عملية التحديث!", 'success');

echo "</div>\n";
echo "</body>\n";
echo "</html>\n";
?>