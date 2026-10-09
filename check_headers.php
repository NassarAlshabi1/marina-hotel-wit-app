<?php
/**
 * سكريبت فحص ملفات الهيدر للتأكد من عدم وجود مشاكل
 */

echo "<h1>فحص ملفات النظام للتأكد من عدم وجود مشاكل في الهيدر</h1>";

// قائمة الملفات المراد فحصها
$files_to_check = [
    'admin/bookings/add_note.php',
    'admin/bookings/payment.php',
    'admin/bookings/edit.php',
    'admin/bookings/list.php',
    'admin/bookings/add.php',
    'admin/bookings/add2.php',
    'admin/expenses/expenses.php',
    'admin/reports/revenue.php',
    'admin/reports/report.php',
    'includes/header.php',
    'includes/header2.php',
    'includes/simple-header.php',
    'includes/auth.php'
];

echo "<h2>نتائج الفحص:</h2>";

foreach ($files_to_check as $file) {
    echo "<h3>فحص ملف: $file</h3>";
    
    if (!file_exists($file)) {
        echo "<div style='color: red;'>❌ الملف غير موجود</div>";
        continue;
    }
    
    $content = file_get_contents($file);
    $lines = explode("\n", $content);
    
    // فحص السطر الأول
    $first_line = trim($lines[0]);
    if ($first_line !== '<?php') {
        echo "<div style='color: red;'>❌ السطر الأول لا يبدأ بـ <?php</div>";
        echo "<div>السطر الأول: " . htmlspecialchars($first_line) . "</div>";
    } else {
        echo "<div style='color: green;'>✅ السطر الأول صحيح</div>";
    }
    
    // فحص وجود رموز غريبة قبل <?php
    if (strpos($content, '<?php') !== 0) {
        $before_php = substr($content, 0, strpos($content, '<?php'));
        if (!empty(trim($before_php))) {
            echo "<div style='color: red;'>❌ يوجد محتوى قبل <?php: " . htmlspecialchars($before_php) . "</div>";
        }
    }
    
    // فحص استخدام header() بعد include header.php
    $has_header_include = strpos($content, "include '../../includes/header.php'") !== false ||
                         strpos($content, 'include "../../includes/header.php"') !== false ||
                         strpos($content, "require_once '../../includes/header.php'") !== false ||
                         strpos($content, 'require_once "../../includes/header.php"') !== false;
    
    $has_header_function = strpos($content, 'header(') !== false;
    
    if ($has_header_include && $has_header_function) {
        // التحقق من ترتيب الاستدعاءات
        $header_include_pos = max(
            strpos($content, "include '../../includes/header.php'") ?: 0,
            strpos($content, 'include "../../includes/header.php"') ?: 0,
            strpos($content, "require_once '../../includes/header.php'") ?: 0,
            strpos($content, 'require_once "../../includes/header.php"') ?: 0
        );
        
        $header_function_pos = strpos($content, 'header(');
        
        if ($header_include_pos < $header_function_pos) {
            echo "<div style='color: red;'>❌ يتم استدعاء header() بعد تضمين header.php</div>";
        } else {
            echo "<div style='color: green;'>✅ ترتيب الاستدعاءات صحيح</div>";
        }
    } else if ($has_header_function) {
        echo "<div style='color: blue;'>ℹ️ يستخدم header() بدون تضمين header.php</div>";
    } else {
        echo "<div style='color: green;'>✅ لا يوجد استخدام لـ header()</div>";
    }
    
    echo "<hr>";
}

echo "<h2>التوصيات:</h2>";
echo "<ul>";
echo "<li>تأكد من أن جميع الملفات تبدأ بـ <?php بدون أي رموز قبلها</li>";
echo "<li>استخدم header() قبل تضمين أي ملفات هيدر</li>";
echo "<li>تأكد من عدم وجود مسافات أو أسطر فارغة قبل <?php</li>";
echo "</ul>";
?>
