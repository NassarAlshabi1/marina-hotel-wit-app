<?php

require_once dirname(__DIR__) . '/bootstrap.php';
session_start();
require 'includes/db.php';
require_once 'includes/functions.php';

// فحص شامل لنظام الدفعات
echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>اختبار نظام الدفعات</title>
    <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
    <style>
        body { font-family: 'Cairo', sans-serif; background-color: #f8f9fa; }
        .test-result { padding: 15px; margin: 10px 0; border-radius: 8px; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .warning { background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
        .info { background-color: #d1ecf1; color: #0c5460; border: 1px solid #b8daff; }
    </style>
</head>
<body>
<div class='container py-4'>
    <div class='row justify-content-center'>
        <div class='col-lg-10'>
            <div class='card'>
                <div class='card-header bg-primary text-white'>
                    <h3>🔍 اختبار نظام الدفعات</h3>
                </div>
                <div class='card-body'>";

$tests = [];
$passed = 0;
$total = 0;

// 1. اختبار الاتصال بقاعدة البيانات
$total++;
try {
    $conn->query("SELECT 1");
    $tests[] = ["✅ اتصال قاعدة البيانات", "تم الاتصال بقاعدة البيانات بنجاح", "success"];
    $passed++;
} catch (Exception $e) {
    $tests[] = ["❌ اتصال قاعدة البيانات", "فشل الاتصال: " . $e->getMessage(), "error"];
}

// 2. اختبار جدول payment
$total++;
try {
    $result = $conn->query("SHOW TABLES LIKE 'payment'");
    if ($result->num_rows > 0) {
        // فحص البنية
        $structure = $conn->query("DESCRIBE payment");
        $fields = [];
        while ($row = $structure->fetch_assoc()) {
            $fields[] = $row['Field'];
        }
        $required_fields = ['payment_id', 'booking_id', 'amount', 'payment_date', 'payment_method'];
        $missing_fields = array_diff($required_fields, $fields);
        
        if (empty($missing_fields)) {
            $tests[] = ["✅ جدول payment", "الجدول موجود وبنيته صحيحة. الأعمدة: " . implode(', ', $fields), "success"];
            $passed++;
        } else {
            $tests[] = ["⚠️ جدول payment", "الجدول موجود لكن ينقصه أعمدة: " . implode(', ', $missing_fields), "warning"];
        }
    } else {
        $tests[] = ["❌ جدول payment", "الجدول غير موجود", "error"];
    }
} catch (Exception $e) {
    $tests[] = ["❌ جدول payment", "خطأ في فحص الجدول: " . $e->getMessage(), "error"];
}

// 3. اختبار جدول bookings
$total++;
try {
    $result = $conn->query("SHOW TABLES LIKE 'bookings'");
    if ($result->num_rows > 0) {
        $count = $conn->query("SELECT COUNT(*) as count FROM bookings")->fetch_assoc()['count'];
        $tests[] = ["✅ جدول bookings", "الجدول موجود ويحتوي على {$count} حجز", "success"];
        $passed++;
    } else {
        $tests[] = ["❌ جدول bookings", "الجدول غير موجود", "error"];
    }
} catch (Exception $e) {
    $tests[] = ["❌ جدول bookings", "خطأ في فحص الجدول: " . $e->getMessage(), "error"];
}

// 4. اختبار دالة الواتساب
$total++;
if (function_exists('send_yemeni_whatsapp')) {
    $tests[] = ["✅ دالة الواتساب", "دالة send_yemeni_whatsapp متوفرة", "success"];
    $passed++;
} else {
    $tests[] = ["❌ دالة الواتساب", "دالة send_yemeni_whatsapp غير متوفرة", "error"];
}

// 5. اختبار صفحة الدفعات
$total++;
if (file_exists('admin/bookings/payment.php')) {
    $content = file_get_contents('admin/bookings/payment.php');
    if (strpos($content, 'submit_payment') !== false && strpos($content, 'INSERT INTO payment') !== false) {
        $tests[] = ["✅ صفحة الدفعات", "الصفحة موجودة وتحتوي على الكود المطلوب", "success"];
        $passed++;
    } else {
        $tests[] = ["⚠️ صفحة الدفعات", "الصفحة موجودة لكن قد تحتاج إلى تحديث", "warning"];
    }
} else {
    $tests[] = ["❌ صفحة الدفعات", "الصفحة غير موجودة", "error"];
}

// 6. اختبار عملية إدراج دفعة تجريبية
$total++;
try {
    // البحث عن حجز موجود
    $booking = $conn->query("SELECT booking_id FROM bookings LIMIT 1");
    if ($booking && $booking->num_rows > 0) {
        $booking_id = $booking->fetch_assoc()['booking_id'];
        
        // محاولة إدراج دفعة تجريبية
        $stmt = $conn->prepare("INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes) VALUES (?, ?, ?, ?, ?)");
        $test_amount = 100.00;
        $test_date = date('Y-m-d H:i:s');
        $test_method = 'اختبار';
        $test_notes = 'دفعة تجريبية - يمكن حذفها';
        
        $stmt->bind_param('idsss', $booking_id, $test_amount, $test_date, $test_method, $test_notes);
        
        if ($stmt->execute()) {
            $payment_id = $conn->insert_id;
            // حذف الدفعة التجريبية
            $conn->query("DELETE FROM payment WHERE payment_id = $payment_id");
            $tests[] = ["✅ إدراج الدفعات", "تم اختبار عملية الإدراج بنجاح", "success"];
            $passed++;
        } else {
            $tests[] = ["❌ إدراج الدفعات", "فشل في إدراج الدفعة التجريبية: " . $stmt->error, "error"];
        }
    } else {
        $tests[] = ["⚠️ إدراج الدفعات", "لا توجد حجوزات لاختبار الدفعات عليها", "warning"];
    }
} catch (Exception $e) {
    $tests[] = ["❌ إدراج الدفعات", "خطأ في اختبار الإدراج: " . $e->getMessage(), "error"];
}

// 7. اختبار متغيرات الجلسة
$total++;
if (session_status() === PHP_SESSION_ACTIVE) {
    $tests[] = ["✅ نظام الجلسات", "الجلسات تعمل بشكل صحيح", "success"];
    $passed++;
} else {
    $tests[] = ["❌ نظام الجلسات", "الجلسات لا تعمل بشكل صحيح", "error"];
}

// 8. اختبار الملفات المطلوبة
$total++;
$required_files = [
    'includes/db.php',
    'includes/functions.php',
    'admin/bookings/payment.php'
];

$missing_files = [];
foreach ($required_files as $file) {
    if (!file_exists($file)) {
        $missing_files[] = $file;
    }
}

if (empty($missing_files)) {
    $tests[] = ["✅ الملفات المطلوبة", "جميع الملفات المطلوبة موجودة", "success"];
    $passed++;
} else {
    $tests[] = ["❌ الملفات المطلوبة", "الملفات المفقودة: " . implode(', ', $missing_files), "error"];
}

// عرض النتائج
$percentage = round(($passed / $total) * 100);
$status_class = $percentage >= 80 ? 'success' : ($percentage >= 60 ? 'warning' : 'error');

echo "<div class='test-result $status_class'>
    <h4>📊 النتيجة الإجمالية: $passed/$total ($percentage%)</h4>
    <p>" . ($percentage >= 80 ? 
        "🎉 ممتاز! النظام يعمل بشكل صحيح" : 
        ($percentage >= 60 ? 
            "⚠️ النظام يعمل لكن يحتاج إلى بعض التحسينات" : 
            "❌ النظام يحتاج إلى إصلاحات مهمة"
        )
    ) . "</p>
</div>";

echo "<h5>📋 تفاصيل الاختبارات:</h5>";

foreach ($tests as $test) {
    echo "<div class='test-result {$test[2]}'>
        <strong>{$test[0]}</strong><br>
        {$test[1]}
    </div>";
}

echo "<div class='mt-4'>
    <h5>🔧 الإجراءات المقترحة:</h5>
    <ul>";

if ($percentage < 100) {
    echo "<li>تشغيل ملف التشخيص: <a href='admin/bookings/payment_diagnostic.php' class='btn btn-sm btn-outline-primary'>تشخيص النظام</a></li>";
    echo "<li>فحص إعدادات قاعدة البيانات في ملف includes/db.php</li>";
    echo "<li>التأكد من صحة أذونات الملفات</li>";
}

echo "<li>اختبار صفحة الدفعات: <a href='admin/bookings/payment.php?id=1' class='btn btn-sm btn-outline-success'>اختبار الدفعات</a></li>";
echo "<li>العودة للوحة التحكم: <a href='admin/dashboard.php' class='btn btn-sm btn-outline-secondary'>لوحة التحكم</a></li>";

echo "</ul>
</div>

<div class='mt-3 text-muted'>
    <small>📅 تم الاختبار في: " . date('Y-m-d H:i:s') . "</small>
</div>

                </div>
            </div>
        </div>
    </div>
</div>
</body>
</html>";
?>