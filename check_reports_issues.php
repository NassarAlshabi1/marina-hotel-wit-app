<?php
/**
 * فحص مشاكل التقارير وإصلاحها
 */

error_reporting(E_ALL);
ini_set('display_errors', 1);

require_once 'includes/config.php';
require_once 'includes/db.php';

echo "<h1>فحص وإصلاح مشاكل التقارير</h1>";

// 1. فحص الملفات المطلوبة
echo "<h2>1. فحص الملفات المطلوبة</h2>";

$required_files = [
    'includes/pdf_generator.php',
    'admin/reports.php',
    'admin/reports/comprehensive_reports.php',
    'admin/reports/report.php',
    'admin/reports/revenue.php',
    'admin/reports/occupancy.php',
    'admin/reports/export_excel.php',
    'admin/reports/export_pdf.php'
];

foreach ($required_files as $file) {
    if (file_exists($file)) {
        echo "✅ $file - موجود<br>";
    } else {
        echo "❌ $file - غير موجود<br>";
    }
}

// 2. فحص الجداول المطلوبة
echo "<h2>2. فحص الجداول المطلوبة</h2>";

$required_tables = [
    'bookings',
    'rooms', 
    'payment',
    'expenses',
    'employees',
    'salary_withdrawals',
    'users'
];

foreach ($required_tables as $table) {
    $result = $conn->query("SHOW TABLES LIKE '$table'");
    if ($result && $result->num_rows > 0) {
        echo "✅ جدول $table - موجود<br>";
        
        // فحص عدد السجلات
        $count_result = $conn->query("SELECT COUNT(*) as count FROM $table");
        if ($count_result) {
            $count = $count_result->fetch_assoc()['count'];
            echo "&nbsp;&nbsp;&nbsp;📊 عدد السجلات: $count<br>";
        }
    } else {
        echo "❌ جدول $table - غير موجود<br>";
    }
}

// 3. فحص أعمدة الجداول المهمة
echo "<h2>3. فحص أعمدة الجداول المهمة</h2>";

// فحص جدول bookings
echo "<h3>جدول bookings:</h3>";
$bookings_columns = $conn->query("SHOW COLUMNS FROM bookings");
if ($bookings_columns) {
    while ($col = $bookings_columns->fetch_assoc()) {
        echo "- " . $col['Field'] . " (" . $col['Type'] . ")<br>";
    }
}

// فحص جدول payment
echo "<h3>جدول payment:</h3>";
$payment_check = $conn->query("SHOW TABLES LIKE 'payment'");
if ($payment_check && $payment_check->num_rows > 0) {
    $payment_columns = $conn->query("SHOW COLUMNS FROM payment");
    while ($col = $payment_columns->fetch_assoc()) {
        echo "- " . $col['Field'] . " (" . $col['Type'] . ")<br>";
    }
} else {
    echo "❌ جدول payment غير موجود<br>";
}

// 4. فحص مجلدات التحميل والتقارير
echo "<h2>4. فحص المجلدات المطلوبة</h2>";

$required_dirs = [
    'uploads',
    'uploads/reports',
    'cache',
    'admin/reports'
];

foreach ($required_dirs as $dir) {
    if (!is_dir($dir)) {
        mkdir($dir, 0755, true);
        echo "✅ تم إنشاء المجلد: $dir<br>";
    } else {
        echo "✅ المجلد موجود: $dir<br>";
    }
    
    if (is_writable($dir)) {
        echo "&nbsp;&nbsp;&nbsp;✅ قابل للكتابة<br>";
    } else {
        echo "&nbsp;&nbsp;&nbsp;❌ غير قابل للكتابة<br>";
    }
}

// 5. فحص إعدادات PHP
echo "<h2>5. فحص إعدادات PHP</h2>";

$php_settings = [
    'max_execution_time' => ini_get('max_execution_time'),
    'memory_limit' => ini_get('memory_limit'),
    'upload_max_filesize' => ini_get('upload_max_filesize'),
    'post_max_size' => ini_get('post_max_size')
];

foreach ($php_settings as $setting => $value) {
    echo "- $setting: $value<br>";
}

// 6. اختبار إنشاء PDF
echo "<h2>6. اختبار إنشاء PDF</h2>";

try {
    if (file_exists('includes/pdf_generator.php')) {
        require_once 'includes/pdf_generator.php';
        
        $report_generator = new SystemReportGenerator($conn);
        echo "✅ تم تحميل مولد التقارير بنجاح<br>";
        
        // اختبار إنشاء تقرير بسيط
        $pdf = $report_generator->generateSystemHealthReport();
        echo "✅ تم إنشاء تقرير صحة النظام بنجاح<br>";
        
    } else {
        echo "❌ ملف pdf_generator.php غير موجود<br>";
    }
} catch (Exception $e) {
    echo "❌ خطأ في إنشاء PDF: " . $e->getMessage() . "<br>";
}

// 7. فحص الخطوط العربية
echo "<h2>7. فحص الخطوط العربية</h2>";

$font_dir = 'includes/fpdf/font/';
if (is_dir($font_dir)) {
    echo "✅ مجلد الخطوط موجود<br>";
    
    $fonts = ['DejaVuSansCondensed.php', 'DejaVuSansCondensed-Bold.php'];
    foreach ($fonts as $font) {
        if (file_exists($font_dir . $font)) {
            echo "✅ خط $font موجود<br>";
        } else {
            echo "❌ خط $font غير موجود<br>";
        }
    }
} else {
    echo "❌ مجلد الخطوط غير موجود<br>";
}

// 8. اختبار الاتصال بقاعدة البيانات
echo "<h2>8. اختبار الاتصال بقاعدة البيانات</h2>";

if ($conn && !$conn->connect_error) {
    echo "✅ الاتصال بقاعدة البيانات يعمل بنجاح<br>";
    echo "- الخادم: " . $conn->server_info . "<br>";
    echo "- قاعدة البيانات: " . (defined('DB_NAME') ? DB_NAME : 'غير محددة') . "<br>";
} else {
    echo "❌ فشل الاتصال بقاعدة البيانات: " . ($conn ? $conn->connect_error : 'لم يتم إنشاء الاتصال') . "<br>";
}

// 9. فحص البيانات التجريبية
echo "<h2>9. فحص البيانات التجريبية</h2>";

$sample_queries = [
    'الحجوزات' => "SELECT COUNT(*) as count FROM bookings",
    'المدفوعات' => "SELECT COUNT(*) as count FROM payment",
    'المصروفات' => "SELECT COUNT(*) as count FROM expenses",
    'الموظفين' => "SELECT COUNT(*) as count FROM employees"
];

foreach ($sample_queries as $name => $query) {
    try {
        $result = $conn->query($query);
        if ($result) {
            $count = $result->fetch_assoc()['count'];
            echo "✅ $name: $count سجل<br>";
        } else {
            echo "❌ خطأ في استعلام $name<br>";
        }
    } catch (Exception $e) {
        echo "❌ خطأ في $name: " . $e->getMessage() . "<br>";
    }
}

echo "<h2>انتهى الفحص</h2>";
echo "<p>تم فحص جميع مكونات نظام التقارير. يرجى مراجعة النتائج أعلاه لتحديد أي مشاكل تحتاج إلى إصلاح.</p>";
?>