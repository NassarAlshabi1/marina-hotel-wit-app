<?php
/**
 * إصلاح تلقائي لإضافة تضمين ملف الدوال المساعدة في جميع ملفات التقارير
 * Automatic fix to add report_functions.php include to all report files
 */

echo "<h1>🔧 إصلاح تلقائي لتضمين الدوال المساعدة</h1>";

// قائمة ملفات التقارير التي قد تحتاج إلى تضمين ملف الدوال
$report_files = [
    'admin/reports/comprehensive_reports.php',
    'admin/reports/export_excel.php',
    'admin/reports/export_pdf.php',
    'admin/reports/employee_withdrawals_report.php',
    'admin/reports/export_employee_withdrawals_excel.php',
    'admin/reports/report.php',
    'admin/reports/revenue.php',
    'admin/reports/occupancy.php',
    'admin/reports/reports.php'
];

$include_line = "include_once '../../includes/report_functions.php';";
$require_line = "require_once '../../includes/report_functions.php';";

foreach ($report_files as $file) {
    echo "<h3>🔍 فحص الملف: $file</h3>";
    
    if (!file_exists($file)) {
        echo "<p style='color: orange;'>⚠️ الملف غير موجود</p>";
        continue;
    }
    
    $content = file_get_contents($file);
    
    // التحقق من وجود تضمين ملف الدوال
    if (strpos($content, "report_functions.php") !== false) {
        echo "<p style='color: green;'>✅ الملف يحتوي على تضمين ملف الدوال</p>";
        continue;
    }
    
    // التحقق من استخدام الدوال المساعدة
    $uses_functions = false;
    $helper_functions = ['format_arabic_date', 'format_currency', 'format_number'];
    
    foreach ($helper_functions as $func) {
        if (strpos($content, $func) !== false) {
            $uses_functions = true;
            echo "<p style='color: blue;'>📝 الملف يستخدم دالة: $func</p>";
            break;
        }
    }
    
    if (!$uses_functions) {
        echo "<p style='color: gray;'>ℹ️ الملف لا يستخدم الدوال المساعدة</p>";
        continue;
    }
    
    // البحث عن موقع مناسب لإضافة التضمين
    $lines = explode("\n", $content);
    $insert_position = -1;
    
    for ($i = 0; $i < count($lines); $i++) {
        $line = trim($lines[$i]);
        
        // البحث عن آخر include/require
        if (strpos($line, "include") !== false || strpos($line, "require") !== false) {
            $insert_position = $i + 1;
        }
        
        // التوقف عند أول كود PHP فعلي
        if ($line && !strpos($line, "<?php") && !strpos($line, "include") && 
            !strpos($line, "require") && !strpos($line, "//") && !strpos($line, "*")) {
            break;
        }
    }
    
    if ($insert_position == -1) {
        echo "<p style='color: red;'>❌ لم يتم العثور على موقع مناسب للإضافة</p>";
        continue;
    }
    
    // إضافة التضمين
    array_splice($lines, $insert_position, 0, $include_line);
    $new_content = implode("\n", $lines);
    
    // حفظ الملف
    if (file_put_contents($file, $new_content)) {
        echo "<p style='color: green;'>✅ تم إضافة تضمين ملف الدوال بنجاح</p>";
    } else {
        echo "<p style='color: red;'>❌ فشل في حفظ الملف</p>";
    }
}

echo "<hr>";
echo "<h2>🎯 ملخص الإصلاح التلقائي</h2>";
echo "<p>تم فحص وإصلاح جميع ملفات التقارير لضمان تضمين ملف الدوال المساعدة.</p>";

echo "<h3>🔗 اختبار سريع:</h3>";
echo '<a href="final_test_all_reports.php" target="_blank" style="background:#28a745; color:white; padding:10px 20px; text-decoration:none; border-radius:5px; display:inline-block;">🧪 تشغيل الاختبار النهائي الشامل</a>';

echo "<p style='margin-top: 20px; color: #666;'>تم إكمال الإصلاح التلقائي - " . date('Y-m-d H:i:s') . "</p>";
?>