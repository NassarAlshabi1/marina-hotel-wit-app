<?php
/**
 * سكريبت تحميل الخطوط المطلوبة للنظام
 * يقوم بتحميل خطوط Tajawal و Font Awesome محلياً
 */

// إنشاء المجلدات المطلوبة
$fonts_dir = 'assets/fonts';
$tajawal_dir = $fonts_dir . '/tajawal';
$fontawesome_dir = $fonts_dir . '/fontawesome';

if (!is_dir($fonts_dir)) mkdir($fonts_dir, 0755, true);
if (!is_dir($tajawal_dir)) mkdir($tajawal_dir, 0755, true);
if (!is_dir($fontawesome_dir)) mkdir($fontawesome_dir, 0755, true);

echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>تحميل الخطوط</title>
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; direction: rtl; }
        .success { color: green; background: #d4edda; padding: 10px; border-radius: 5px; margin: 5px 0; }
        .info { color: blue; background: #d1ecf1; padding: 10px; border-radius: 5px; margin: 5px 0; }
        .warning { color: orange; background: #fff3cd; padding: 10px; border-radius: 5px; margin: 5px 0; }
        .error { color: red; background: #f8d7da; padding: 10px; border-radius: 5px; margin: 5px 0; }
        .progress { background: #f0f0f0; border-radius: 5px; padding: 3px; margin: 5px 0; }
        .progress-bar { background: #007bff; height: 20px; border-radius: 3px; transition: width 0.3s; }
    </style>
</head>
<body>";

echo "<h1>تحميل الخطوط المطلوبة للنظام</h1>";

// دالة تحميل ملف
function downloadFile($url, $destination) {
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, $url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_FOLLOWLOCATION, true);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
    curl_setopt($ch, CURLOPT_USERAGENT, 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36');
    curl_setopt($ch, CURLOPT_TIMEOUT, 30);
    
    $data = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode === 200 && $data !== false) {
        file_put_contents($destination, $data);
        return true;
    }
    
    return false;
}

// قائمة خطوط Tajawal
$tajawal_fonts = [
    'Tajawal-ExtraLight.woff2' => 'https://fonts.gstatic.com/s/tajawal/v9/Iura6YBj_oCad4k1l_6gLuvPDQ.woff2',
    'Tajawal-Light.woff2' => 'https://fonts.gstatic.com/s/tajawal/v9/Iura6YBj_oCad4k1l8ahLuvPDQ.woff2',
    'Tajawal-Regular.woff2' => 'https://fonts.gstatic.com/s/tajawal/v9/Iurf6YBj_oCad4k1l5XGAA.woff2',
    'Tajawal-Medium.woff2' => 'https://fonts.gstatic.com/s/tajawal/v9/Iura6YBj_oCad4k1l-qjLuvPDQ.woff2',
    'Tajawal-Bold.woff2' => 'https://fonts.gstatic.com/s/tajawal/v9/Iura6YBj_oCad4k1l4qkLuvPDQ.woff2',
    'Tajawal-ExtraBold.woff2' => 'https://fonts.gstatic.com/s/tajawal/v9/Iura6YBj_oCad4k1l5KmLuvPDQ.woff2',
    'Tajawal-Black.woff2' => 'https://fonts.gstatic.com/s/tajawal/v9/Iura6YBj_oCad4k1l56nLuvPDQ.woff2'
];

// قائمة خطوط Font Awesome
$fontawesome_fonts = [
    'fa-solid-900.woff2' => 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/webfonts/fa-solid-900.woff2',
    'fa-regular-400.woff2' => 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/webfonts/fa-regular-400.woff2',
    'fa-brands-400.woff2' => 'https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/webfonts/fa-brands-400.woff2'
];

$total_files = count($tajawal_fonts) + count($fontawesome_fonts);
$downloaded = 0;
$failed = 0;

echo "<div class='info'>سيتم تحميل $total_files ملف خط...</div>";

// تحميل خطوط Tajawal
echo "<h2>تحميل خطوط Tajawal:</h2>";
foreach ($tajawal_fonts as $filename => $url) {
    $destination = $tajawal_dir . '/' . $filename;
    
    if (file_exists($destination)) {
        echo "<div class='info'>✅ الملف موجود بالفعل: $filename</div>";
        $downloaded++;
        continue;
    }
    
    echo "<div class='info'>📥 جاري تحميل: $filename...</div>";
    
    if (downloadFile($url, $destination)) {
        echo "<div class='success'>✅ تم تحميل: $filename (" . formatBytes(filesize($destination)) . ")</div>";
        $downloaded++;
    } else {
        echo "<div class='error'>❌ فشل تحميل: $filename</div>";
        $failed++;
    }
    
    // عرض شريط التقدم
    $progress = (($downloaded + $failed) / $total_files) * 100;
    echo "<div class='progress'><div class='progress-bar' style='width: {$progress}%'></div></div>";
    
    // تأخير قصير لتجنب الحظر
    usleep(500000); // 0.5 ثانية
}

// تحميل خطوط Font Awesome
echo "<h2>تحميل خطوط Font Awesome:</h2>";
foreach ($fontawesome_fonts as $filename => $url) {
    $destination = $fontawesome_dir . '/' . $filename;
    
    if (file_exists($destination)) {
        echo "<div class='info'>✅ الملف موجود بالفعل: $filename</div>";
        $downloaded++;
        continue;
    }
    
    echo "<div class='info'>📥 جاري تحميل: $filename...</div>";
    
    if (downloadFile($url, $destination)) {
        echo "<div class='success'>✅ تم تحميل: $filename (" . formatBytes(filesize($destination)) . ")</div>";
        $downloaded++;
    } else {
        echo "<div class='error'>❌ فشل تحميل: $filename</div>";
        $failed++;
    }
    
    // عرض شريط التقدم
    $progress = (($downloaded + $failed) / $total_files) * 100;
    echo "<div class='progress'><div class='progress-bar' style='width: {$progress}%'></div></div>";
    
    usleep(500000); // 0.5 ثانية
}

// دالة تنسيق حجم الملف
function formatBytes($size, $precision = 2) {
    $units = array('B', 'KB', 'MB', 'GB');
    
    for ($i = 0; $size > 1024 && $i < count($units) - 1; $i++) {
        $size /= 1024;
    }
    
    return round($size, $precision) . ' ' . $units[$i];
}

// إنشاء ملفات TTF و WOFF كنسخ احتياطية
echo "<h2>إنشاء نسخ احتياطية للخطوط:</h2>";

// نسخ ملفات WOFF2 كـ WOFF و TTF للتوافق
foreach ($tajawal_fonts as $filename => $url) {
    $woff2_file = $tajawal_dir . '/' . $filename;
    
    if (file_exists($woff2_file)) {
        // إنشاء نسخة WOFF
        $woff_file = str_replace('.woff2', '.woff', $woff2_file);
        if (!file_exists($woff_file)) {
            copy($woff2_file, $woff_file);
            echo "<div class='info'>📋 تم إنشاء نسخة WOFF: " . basename($woff_file) . "</div>";
        }
        
        // إنشاء نسخة TTF
        $ttf_file = str_replace('.woff2', '.ttf', $woff2_file);
        if (!file_exists($ttf_file)) {
            copy($woff2_file, $ttf_file);
            echo "<div class='info'>📋 تم إنشاء نسخة TTF: " . basename($ttf_file) . "</div>";
        }
    }
}

foreach ($fontawesome_fonts as $filename => $url) {
    $woff2_file = $fontawesome_dir . '/' . $filename;
    
    if (file_exists($woff2_file)) {
        // إنشاء نسخة WOFF
        $woff_file = str_replace('.woff2', '.woff', $woff2_file);
        if (!file_exists($woff_file)) {
            copy($woff2_file, $woff_file);
            echo "<div class='info'>📋 تم إنشاء نسخة WOFF: " . basename($woff_file) . "</div>";
        }
        
        // إنشاء نسخة TTF
        $ttf_file = str_replace('.woff2', '.ttf', $woff2_file);
        if (!file_exists($ttf_file)) {
            copy($woff2_file, $ttf_file);
            echo "<div class='info'>📋 تم إنشاء نسخة TTF: " . basename($ttf_file) . "</div>";
        }
    }
}

// ملخص النتائج
echo "<h2>ملخص التحميل:</h2>";
echo "<div class='info'>";
echo "<p><strong>إجمالي الملفات:</strong> $total_files</p>";
echo "<p><strong>تم تحميلها بنجاح:</strong> $downloaded</p>";
echo "<p><strong>فشل التحميل:</strong> $failed</p>";
echo "<p><strong>معدل النجاح:</strong> " . round(($downloaded / $total_files) * 100, 1) . "%</p>";
echo "</div>";

if ($downloaded > 0) {
    echo "<div class='success'>";
    echo "<h3>✅ تم تحميل الخطوط بنجاح!</h3>";
    echo "<p>يمكنك الآن استخدام النظام بدون إنترنت. الخطوط متوفرة في:</p>";
    echo "<ul>";
    echo "<li><strong>خطوط Tajawal:</strong> $tajawal_dir/</li>";
    echo "<li><strong>خطوط Font Awesome:</strong> $fontawesome_dir/</li>";
    echo "</ul>";
    echo "</div>";
}

if ($failed > 0) {
    echo "<div class='warning'>";
    echo "<h3>⚠️ بعض الملفات لم يتم تحميلها</h3>";
    echo "<p>في حالة فشل تحميل بعض الخطوط، سيتم استخدام الخطوط الخارجية كبديل.</p>";
    echo "<p>يمكنك إعادة تشغيل هذا السكريبت لمحاولة تحميل الملفات المفقودة.</p>";
    echo "</div>";
}

echo "<h2>الخطوات التالية:</h2>";
echo "<div class='info'>";
echo "<ol>";
echo "<li><a href='update_assets_paths.php'>تشغيل سكريبت تحديث مسارات الموارد</a></li>";
echo "<li>اختبار النظام للتأكد من عمل الخطوط</li>";
echo "<li>في حالة وجود مشاكل، تحقق من ملف assets/fonts/fonts.css</li>";
echo "</ol>";
echo "</div>";

echo "<br><a href='admin/dash.php' style='display:inline-block;margin-top:20px;padding:10px;background-color:#4CAF50;color:white;text-decoration:none;border-radius:5px;'>العودة للوحة التحكم</a>";

echo "</body></html>";
?>
