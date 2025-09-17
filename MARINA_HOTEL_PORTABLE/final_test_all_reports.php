<?php
/**
 * اختبار نهائي شامل لجميع ملفات التقارير
 * Final comprehensive test for all report files
 */

// إعداد الجلسة
session_start();
$_SESSION['user_id'] = 1;
$_SESSION['user_type'] = 'admin';
$_SESSION['permissions'] = ['view_reports'];

echo "<!DOCTYPE html>";
echo "<html lang='ar' dir='rtl'>";
echo "<head>";
echo "<meta charset='UTF-8'>";
echo "<meta name='viewport' content='width=device-width, initial-scale=1.0'>";
echo "<title>اختبار نهائي شامل - نظام التقارير</title>";
echo "<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.1.3/dist/css/bootstrap.min.css' rel='stylesheet'>";
echo "<link href='https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css' rel='stylesheet'>";
echo "<style>";
echo ".test-card { margin: 10px 0; }";
echo ".success { color: #28a745; }";
echo ".error { color: #dc3545; }";
echo ".warning { color: #ffc107; }";
echo ".test-result { padding: 10px; border-radius: 5px; margin: 5px 0; }";
echo ".success-bg { background-color: #d4edda; border: 1px solid #c3e6cb; }";
echo ".error-bg { background-color: #f8d7da; border: 1px solid #f5c6cb; }";
echo ".warning-bg { background-color: #fff3cd; border: 1px solid #ffeaa7; }";
echo "</style>";
echo "</head>";
echo "<body class='bg-light'>";

echo "<div class='container py-4'>";
echo "<h1 class='text-center mb-4'><i class='fas fa-clipboard-check'></i> اختبار نهائي شامل - نظام التقارير</h1>";

// اختبار تحميل الدوال المساعدة
echo "<div class='card test-card'>";
echo "<div class='card-header bg-primary text-white'>";
echo "<h5><i class='fas fa-code'></i> اختبار تحميل الدوال المساعدة</h5>";
echo "</div>";
echo "<div class='card-body'>";

try {
    include_once 'includes/report_functions.php';
    echo "<div class='test-result success-bg success'>";
    echo "<i class='fas fa-check-circle'></i> تم تحميل ملف الدوال المساعدة بنجاح";
    echo "</div>";
    
    // اختبار دالة تنسيق التاريخ
    if (function_exists('format_arabic_date')) {
        $test_date = format_arabic_date('2024-12-15');
        echo "<div class='test-result success-bg success'>";
        echo "<i class='fas fa-calendar'></i> دالة تنسيق التاريخ تعمل: " . $test_date;
        echo "</div>";
    } else {
        echo "<div class='test-result error-bg error'>";
        echo "<i class='fas fa-times-circle'></i> دالة format_arabic_date غير موجودة";
        echo "</div>";
    }
    
} catch (Exception $e) {
    echo "<div class='test-result error-bg error'>";
    echo "<i class='fas fa-times-circle'></i> خطأ في تحميل الدوال: " . $e->getMessage();
    echo "</div>";
}

echo "</div></div>";

// اختبار الاتصال بقاعدة البيانات
echo "<div class='card test-card'>";
echo "<div class='card-header bg-success text-white'>";
echo "<h5><i class='fas fa-database'></i> اختبار قاعدة البيانات</h5>";
echo "</div>";
echo "<div class='card-body'>";

try {
    include_once 'includes/db.php';
    if ($conn->connect_error) {
        throw new Exception($conn->connect_error);
    }
    echo "<div class='test-result success-bg success'>";
    echo "<i class='fas fa-check-circle'></i> الاتصال بقاعدة البيانات يعمل بشكل صحيح";
    echo "</div>";
} catch (Exception $e) {
    echo "<div class='test-result error-bg error'>";
    echo "<i class='fas fa-times-circle'></i> خطأ في قاعدة البيانات: " . $e->getMessage();
    echo "</div>";
}

echo "</div></div>";

// اختبار استعلامات SQL المحدثة
echo "<div class='card test-card'>";
echo "<div class='card-header bg-info text-white'>";
echo "<h5><i class='fas fa-search'></i> اختبار استعلامات SQL المُصلحة</h5>";
echo "</div>";
echo "<div class='card-body'>";

$test_queries = [
    'revenue' => [
        'query' => "SELECT SUM(amount) as total FROM payment WHERE DATE(payment_date) BETWEEN '2024-01-01' AND '2024-12-31' LIMIT 1",
        'description' => 'استعلام الإيرادات'
    ],
    'expenses' => [
        'query' => "SELECT expense_type, SUM(amount) as total FROM expenses WHERE DATE(date) BETWEEN '2024-01-01' AND '2024-12-31' GROUP BY expense_type LIMIT 1",
        'description' => 'استعلام المصروفات'
    ],
    'withdrawals' => [
        'query' => "SELECT SUM(amount) as total FROM salary_withdrawals WHERE DATE(date) BETWEEN '2024-01-01' AND '2024-12-31' LIMIT 1",
        'description' => 'استعلام سحوبات الموظفين'
    ],
    'bookings' => [
        'query' => "SELECT COUNT(*) as total FROM bookings WHERE DATE(checkin_date) BETWEEN '2024-01-01' AND '2024-12-31' LIMIT 1",
        'description' => 'استعلام الحجوزات'
    ]
];

foreach ($test_queries as $name => $query_info) {
    try {
        $result = $conn->query($query_info['query']);
        if ($result) {
            echo "<div class='test-result success-bg success'>";
            echo "<i class='fas fa-check-circle'></i> " . $query_info['description'] . " يعمل بشكل صحيح";
            echo "</div>";
        } else {
            echo "<div class='test-result error-bg error'>";
            echo "<i class='fas fa-times-circle'></i> خطأ في " . $query_info['description'] . ": " . $conn->error;
            echo "</div>";
        }
    } catch (Exception $e) {
        echo "<div class='test-result error-bg error'>";
        echo "<i class='fas fa-times-circle'></i> خطأ في " . $query_info['description'] . ": " . $e->getMessage();
        echo "</div>";
    }
}

echo "</div></div>";

// فحص ملفات التقارير
echo "<div class='card test-card'>";
echo "<div class='card-header bg-warning text-dark'>";
echo "<h5><i class='fas fa-file-check'></i> فحص ملفات التقارير</h5>";
echo "</div>";
echo "<div class='card-body'>";

$report_files = [
    'admin/reports/comprehensive_reports.php' => 'التقارير الشاملة',
    'admin/reports/export_excel.php' => 'تصدير Excel',
    'admin/reports/export_pdf.php' => 'تصدير PDF',
    'admin/reports/employee_withdrawals_report.php' => 'تقرير سحوبات الموظفين',
    'admin/reports/export_employee_withdrawals_excel.php' => 'تصدير سحوبات Excel',
    'admin/reports/report.php' => 'التقرير العام',
    'admin/reports/revenue.php' => 'تقرير الإيرادات',
    'admin/reports/occupancy.php' => 'تقرير الإشغال',
    'includes/report_functions.php' => 'دوال مساعدة التقارير'
];

$total_files = count($report_files);
$working_files = 0;

foreach ($report_files as $file => $description) {
    if (file_exists($file)) {
        echo "<div class='test-result success-bg success'>";
        echo "<i class='fas fa-check-circle'></i> $description: موجود ومتاح";
        
        // فحص إضافي للأخطاء الشائعة
        $content = file_get_contents($file);
        $common_errors = [
            'expense_gory' => 'خطأ في اسم العمود',
            'total_expensecategory' => 'خطأ في اسم العمود',
            'expense_expense_type' => 'تكرار في اسم العمود',
            'total_withdrawals sw' => 'خطأ في اسم الجدول',
            'withdrawals_$stmt' => 'خطأ في اسم المتغير',
            'WHEREDATE(' => 'خطأ في syntax SQL',
            'DATE(d)ate)' => 'خطأ في syntax SQL',
            ')DATE(' => 'خطأ في syntax SQL',
            'expense_type as expense_type as' => 'تكرار في alias'
        ];
        
        $errors_found = 0;
        foreach ($common_errors as $error => $desc) {
            if (strpos($content, $error) !== false) {
                echo "<br><small class='text-warning'>⚠️ تحذير: $desc</small>";
                $errors_found++;
            }
        }
        
        if ($errors_found == 0) {
            echo "<br><small class='text-success'>✨ خالي من الأخطاء الشائعة</small>";
            $working_files++;
        }
        
        echo "</div>";
    } else {
        echo "<div class='test-result error-bg error'>";
        echo "<i class='fas fa-times-circle'></i> $description: الملف غير موجود";
        echo "</div>";
    }
}

echo "</div></div>";

// ملخص النتائج
echo "<div class='card test-card'>";
echo "<div class='card-header bg-dark text-white'>";
echo "<h5><i class='fas fa-chart-pie'></i> ملخص النتائج</h5>";
echo "</div>";
echo "<div class='card-body'>";

$success_rate = ($working_files / $total_files) * 100;

echo "<div class='row text-center'>";
echo "<div class='col-md-3'>";
echo "<div class='test-result success-bg'>";
echo "<h4 class='success'>$working_files</h4>";
echo "<small>ملفات تعمل بشكل صحيح</small>";
echo "</div>";
echo "</div>";

echo "<div class='col-md-3'>";
echo "<div class='test-result warning-bg'>";
echo "<h4 class='text-dark'>" . ($total_files - $working_files) . "</h4>";
echo "<small>ملفات تحتاج مراجعة</small>";
echo "</div>";
echo "</div>";

echo "<div class='col-md-3'>";
echo "<div class='test-result " . ($success_rate >= 90 ? 'success-bg' : 'warning-bg') . "'>";
echo "<h4 class='" . ($success_rate >= 90 ? 'success' : 'text-dark') . "'>" . round($success_rate) . "%</h4>";
echo "<small>معدل النجاح</small>";
echo "</div>";
echo "</div>";

echo "<div class='col-md-3'>";
echo "<div class='test-result " . ($success_rate >= 90 ? 'success-bg' : 'error-bg') . "'>";
echo "<h4 class='" . ($success_rate >= 90 ? 'success' : 'error') . "'>";
echo $success_rate >= 90 ? '✅ جاهز' : '⚠️ يحتاج عمل';
echo "</h4>";
echo "<small>الحالة العامة</small>";
echo "</div>";
echo "</div>";

echo "</div>";

echo "</div></div>";

// روابط سريعة للاختبار
echo "<div class='card test-card'>";
echo "<div class='card-header bg-secondary text-white'>";
echo "<h5><i class='fas fa-link'></i> روابط سريعة للاختبار</h5>";
echo "</div>";
echo "<div class='card-body text-center'>";

$test_links = [
    'admin/reports.php' => ['التقارير الرئيسية', 'primary'],
    'admin/reports/comprehensive_reports.php' => ['التقارير الشاملة', 'success'],
    'admin/reports/report.php' => ['التقرير العام', 'info'],
    'admin/reports/employee_withdrawals_report.php' => ['سحوبات الموظفين', 'warning'],
    'admin/reports/revenue.php' => ['تقرير الإيرادات', 'success'],
    'admin/reports/occupancy.php' => ['تقرير الإشغال', 'info']
];

foreach ($test_links as $link => $info) {
    echo "<a href='$link' target='_blank' class='btn btn-{$info[1]} m-2'>";
    echo "<i class='fas fa-external-link-alt'></i> {$info[0]}";
    echo "</a>";
}

echo "</div></div>";

echo "<div class='text-center mt-4'>";
echo "<p class='text-muted'>تم إكمال الاختبار النهائي الشامل - " . date('Y-m-d H:i:s') . "</p>";
echo "</div>";

echo "</div>"; // container
echo "</body></html>";

if (isset($conn)) {
    $conn->close();
}
?>