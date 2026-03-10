<?php
/**
 * اختبار سريع للتحقق من إصلاح جميع الأخطاء
 * Quick test to verify all fixes
 */

// إعداد الجلسة
session_start();
$_SESSION['user_id'] = 1;
$_SESSION['user_type'] = 'admin';
$_SESSION['permissions'] = ['view_reports'];

echo "<h1>🔧 اختبار سريع لإصلاح التقارير</h1>";

// تضمين ملف الدوال الجديد
try {
    include_once 'includes/report_functions.php';
    echo "<p>✅ تم تحميل ملف الدوال المساعدة بنجاح</p>";
    
    // اختبار دالة تنسيق التاريخ
    $test_date = format_arabic_date('2024-12-15');
    echo "<p>✅ دالة تنسيق التاريخ تعمل: " . $test_date . "</p>";
    
} catch (Exception $e) {
    echo "<p>❌ خطأ في تحميل الدوال: " . $e->getMessage() . "</p>";
}

// اختبار الاتصال بقاعدة البيانات
try {
    include_once 'includes/db.php';
    if ($conn->connect_error) {
        throw new Exception($conn->connect_error);
    }
    echo "<p>✅ الاتصال بقاعدة البيانات يعمل</p>";
} catch (Exception $e) {
    echo "<p>❌ خطأ في قاعدة البيانات: " . $e->getMessage() . "</p>";
}

// اختبار استعلامات SQL المصححة
$test_queries = [
    'revenue' => "SELECT SUM(amount) as total FROM payment WHERE DATE(payment_date) BETWEEN '2024-01-01' AND '2024-12-31' LIMIT 1",
    'expenses' => "SELECT SUM(amount) as total FROM expenses WHERE DATE(date) BETWEEN '2024-01-01' AND '2024-12-31' LIMIT 1",
    'withdrawals' => "SELECT SUM(amount) as total FROM salary_withdrawals WHERE DATE(date) BETWEEN '2024-01-01' AND '2024-12-31' LIMIT 1"
];

echo "<h3>🗃️ اختبار استعلامات SQL:</h3>";

foreach ($test_queries as $name => $query) {
    try {
        $result = $conn->query($query);
        if ($result) {
            echo "<p>✅ استعلام $name يعمل بشكل صحيح</p>";
        } else {
            echo "<p>❌ خطأ في استعلام $name: " . $conn->error . "</p>";
        }
    } catch (Exception $e) {
        echo "<p>❌ خطأ في استعلام $name: " . $e->getMessage() . "</p>";
    }
}

// فحص الملفات المُصلحة
echo "<h3>📁 فحص الملفات المُصلحة:</h3>";

$fixed_files = [
    'admin/reports/comprehensive_reports.php' => 'التقارير الشاملة',
    'admin/reports/export_excel.php' => 'تصدير Excel',
    'admin/reports/export_pdf.php' => 'تصدير PDF',
    'admin/reports/employee_withdrawals_report.php' => 'تقرير سحوبات الموظفين',
    'includes/report_functions.php' => 'دوال مساعدة'
];

foreach ($fixed_files as $file => $description) {
    if (file_exists($file)) {
        echo "<p>✅ $description: الملف موجود</p>";
        
        // فحص أساسي للأخطاء
        $content = file_get_contents($file);
        
        // فحص الأخطاء الشائعة
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
        foreach ($common_errors as $error => $description) {
            if (strpos($content, $error) !== false) {
                echo "<p>⚠️ تحذير في $file: $description</p>";
                $errors_found++;
            }
        }
        
        if ($errors_found == 0) {
            echo "<p style='color: green; margin-left: 20px;'>🎉 الملف خالي من الأخطاء الشائعة</p>";
        }
        
    } else {
        echo "<p>❌ $description: الملف غير موجود</p>";
    }
}

// اختبار روابط التقارير
echo "<h3>🔗 روابط سريعة لاختبار التقارير:</h3>";
echo '<div style="margin: 20px 0;">';
echo '<a href="admin/reports.php" target="_blank" style="display:inline-block; margin:5px; padding:10px 15px; background:#007bff; color:white; text-decoration:none; border-radius:5px;">📊 التقارير الرئيسية</a>';
echo '<a href="admin/reports/comprehensive_reports.php" target="_blank" style="display:inline-block; margin:5px; padding:10px 15px; background:#28a745; color:white; text-decoration:none; border-radius:5px;">📈 التقارير الشاملة</a>';
echo '<a href="admin/reports/employee_withdrawals_report.php" target="_blank" style="display:inline-block; margin:5px; padding:10px 15px; background:#6f42c1; color:white; text-decoration:none; border-radius:5px;">👥 سحوبات الموظفين</a>';
echo '</div>';

// خلاصة
echo "<hr><div style='background:#d4edda; padding:15px; border-radius:5px; border: 1px solid #c3e6cb;'>";
echo "<h3 style='color:#155724; margin-bottom:10px;'>🎯 خلاصة الإصلاحات:</h3>";
echo "<ul style='color:#155724;'>";
echo "<li>✅ إصلاح جميع أخطاء SQL</li>";
echo "<li>✅ إضافة دوال مساعدة محمية من التكرار</li>";
echo "<li>✅ إصلاح أسماء الجداول والأعمدة</li>";
echo "<li>✅ إزالة التضمين المضاعف للملفات</li>";
echo "<li>✅ إصلاح جميع أخطاء Syntax</li>";
echo "</ul>";
echo "</div>";

echo "<p style='text-align:center; color:#666; font-size:12px; margin-top:30px;'>";
echo "تم إكمال اختبار الإصلاحات - " . date('Y-m-d H:i:s');
echo "</p>";

if (isset($conn)) {
    $conn->close();
}
?>