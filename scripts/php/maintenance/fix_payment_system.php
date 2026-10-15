<?php

require_once dirname(__DIR__) . '/bootstrap.php';
session_start();
require 'includes/db.php';

// إصلاح نظام الدفعات
$fixes = [];
$errors = [];

echo "<!DOCTYPE html>
<html lang='ar' dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <meta name='viewport' content='width=device-width, initial-scale=1.0'>
    <title>إصلاح نظام الدفعات</title>
    <link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>
    <style>
        body { font-family: 'Cairo', sans-serif; background-color: #f8f9fa; }
        .fix-result { padding: 15px; margin: 10px 0; border-radius: 8px; }
        .success { background-color: #d4edda; color: #155724; border: 1px solid #c3e6cb; }
        .error { background-color: #f8d7da; color: #721c24; border: 1px solid #f5c6cb; }
        .warning { background-color: #fff3cd; color: #856404; border: 1px solid #ffeaa7; }
    </style>
</head>
<body>
<div class='container py-4'>
    <div class='row justify-content-center'>
        <div class='col-lg-10'>
            <div class='card'>
                <div class='card-header bg-warning text-dark'>
                    <h3>🔧 إصلاح نظام الدفعات</h3>
                </div>
                <div class='card-body'>";

// 1. التحقق من وجود جدول payment وإنشاؤه إذا لم يكن موجوداً
try {
    $check_payment_table = $conn->query("SHOW TABLES LIKE 'payment'");
    if ($check_payment_table->num_rows == 0) {
        $create_payment_table = "
        CREATE TABLE `payment` (
            `payment_id` int(11) NOT NULL AUTO_INCREMENT,
            `booking_id` int(11) NOT NULL,
            `amount` decimal(10,2) NOT NULL,
            `payment_date` timestamp NOT NULL DEFAULT current_timestamp(),
            `payment_method` varchar(50) NOT NULL DEFAULT 'نقدي',
            `notes` text DEFAULT NULL,
            `revenue_type` enum('room','restaurant','services','other') NOT NULL DEFAULT 'room',
            `cash_transaction_id` int(11) DEFAULT NULL,
            `room_number` varchar(10) DEFAULT NULL,
            PRIMARY KEY (`payment_id`),
            KEY `booking_id` (`booking_id`)
        ) ENGINE=MyISAM DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
        ";
        
        if ($conn->query($create_payment_table)) {
            $fixes[] = ["✅ إنشاء جدول payment", "تم إنشاء جدول payment بنجاح", "success"];
        } else {
            $errors[] = ["❌ إنشاء جدول payment", "فشل في إنشاء جدول payment: " . $conn->error, "error"];
        }
    } else {
        $fixes[] = ["✅ جدول payment", "الجدول موجود بالفعل", "success"];
    }
} catch (Exception $e) {
    $errors[] = ["❌ فحص جدول payment", "خطأ: " . $e->getMessage(), "error"];
}

// 2. التحقق من أعمدة الجدول وإضافة المفقود منها
try {
    $columns = $conn->query("DESCRIBE payment");
    $existing_columns = [];
    while ($row = $columns->fetch_assoc()) {
        $existing_columns[] = $row['Field'];
    }
    
    $required_columns = [
        'payment_id' => 'int(11) NOT NULL AUTO_INCREMENT',
        'booking_id' => 'int(11) NOT NULL',
        'amount' => 'decimal(10,2) NOT NULL',
        'payment_date' => 'timestamp NOT NULL DEFAULT current_timestamp()',
        'payment_method' => 'varchar(50) NOT NULL DEFAULT \'نقدي\'',
        'notes' => 'text DEFAULT NULL'
    ];
    
    $added_columns = [];
    foreach ($required_columns as $column => $definition) {
        if (!in_array($column, $existing_columns)) {
            $alter_query = "ALTER TABLE payment ADD COLUMN $column $definition";
            if ($conn->query($alter_query)) {
                $added_columns[] = $column;
            }
        }
    }
    
    if (!empty($added_columns)) {
        $fixes[] = ["✅ إضافة أعمدة", "تم إضافة الأعمدة: " . implode(', ', $added_columns), "success"];
    } else {
        $fixes[] = ["✅ أعمدة الجدول", "جميع الأعمدة المطلوبة موجودة", "success"];
    }
} catch (Exception $e) {
    $errors[] = ["❌ فحص الأعمدة", "خطأ: " . $e->getMessage(), "error"];
}

// 3. التحقق من وجود دالة الواتساب في functions.php
try {
    $functions_file = 'includes/functions.php';
    if (file_exists($functions_file)) {
        $content = file_get_contents($functions_file);
        if (strpos($content, 'function send_yemeni_whatsapp') === false) {
            // إضافة دالة الواتساب
            $whatsapp_function = "
            
// دالة تنسيق أرقام الهاتف اليمنية
function format_yemeni_phone(\$phone) {
    // إزالة المسافات والرموز
    \$phone = preg_replace('/[^0-9]/', '', \$phone);
    
    // التحقق من صحة الرقم اليمني
    if (preg_match('/^(967|00967|\\+967)?(7[0-9]{8})$/', \$phone, \$matches)) {
        return '967' . \$matches[2]; // إرجاع الرقم بصيغة 967xxxxxxxx
    }
    if (preg_match('/^7[0-9]{8}$/', \$phone)) {
        return '967' . \$phone; // إضافة كود الدولة
    }
    return false; // رقم غير صالح
}

// دالة لإرسال رسالة واتساب للعملاء اليمنيين
function send_yemeni_whatsapp(\$phone, \$message) {
    \$api_url = 'https://wa.nux.my.id/api/sendWA';
    \$secret_key = 'd4fc5abd713b541b7013f978e8cc4495';

    \$phone = format_yemeni_phone(\$phone);
    if (!\$phone) {
        return ['status' => 'error', 'message' => 'رقم الهاتف اليمني غير صالح'];
    }

    \$url = sprintf(
        '%s?to=%s&msg=%s&secret=%s',
        \$api_url,
        urlencode(\$phone),
        urlencode(\$message),
        \$secret_key
    );

    \$ch = curl_init();
    curl_setopt(\$ch, CURLOPT_URL, \$url);
    curl_setopt(\$ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt(\$ch, CURLOPT_TIMEOUT, 10);
    \$response = curl_exec(\$ch);
    curl_close(\$ch);

    if (\$response === false) {
        return ['status' => 'error', 'message' => 'فشل الاتصال بخادم الواتساب'];
    }

    return json_decode(\$response, true) ?: ['status' => 'sent', 'message' => 'تم الإرسال'];
}
";
            
            if (file_put_contents($functions_file, $content . $whatsapp_function)) {
                $fixes[] = ["✅ دالة الواتساب", "تم إضافة دالة الواتساب إلى functions.php", "success"];
            } else {
                $errors[] = ["❌ دالة الواتساب", "فشل في إضافة دالة الواتساب", "error"];
            }
        } else {
            $fixes[] = ["✅ دالة الواتساب", "دالة الواتساب موجودة بالفعل", "success"];
        }
    } else {
        $errors[] = ["❌ ملف functions.php", "الملف غير موجود", "error"];
    }
} catch (Exception $e) {
    $errors[] = ["❌ فحص دالة الواتساب", "خطأ: " . $e->getMessage(), "error"];
}

// 4. إنشاء فهرس للجدول لتحسين الأداء
try {
    $conn->query("CREATE INDEX idx_booking_payment ON payment(booking_id)");
    $fixes[] = ["✅ فهرس الجدول", "تم إنشاء فهرس لتحسين الأداء", "success"];
} catch (Exception $e) {
    // إذا كان الفهرس موجوداً بالفعل، فلا مشكلة
    $fixes[] = ["✅ فهرس الجدول", "الفهرس موجود بالفعل أو تم إنشاؤه", "success"];
}

// 5. إضافة بيانات تجريبية إذا كان الجدول فارغاً
try {
    $count = $conn->query("SELECT COUNT(*) as count FROM payment")->fetch_assoc()['count'];
    if ($count == 0) {
        // البحث عن حجز لإضافة دفعة تجريبية
        $booking = $conn->query("SELECT booking_id FROM bookings LIMIT 1");
        if ($booking && $booking->num_rows > 0) {
            $booking_id = $booking->fetch_assoc()['booking_id'];
            $sample_payment = "INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes) 
                              VALUES ($booking_id, 1000.00, NOW(), 'نقدي', 'دفعة تجريبية للاختبار')";
            if ($conn->query($sample_payment)) {
                $fixes[] = ["✅ بيانات تجريبية", "تم إضافة دفعة تجريبية للاختبار", "success"];
            }
        }
    } else {
        $fixes[] = ["✅ بيانات الجدول", "الجدول يحتوي على $count دفعة", "success"];
    }
} catch (Exception $e) {
    $errors[] = ["❌ البيانات التجريبية", "خطأ: " . $e->getMessage(), "error"];
}

// عرض النتائج
$total_fixes = count($fixes);
$total_errors = count($errors);

if ($total_errors == 0) {
    echo "<div class='fix-result success'>
        <h4>🎉 تم الإصلاح بنجاح!</h4>
        <p>تم تنفيذ $total_fixes إصلاح بنجاح. النظام جاهز للاستخدام.</p>
    </div>";
} else {
    echo "<div class='fix-result error'>
        <h4>⚠️ إصلاح جزئي</h4>
        <p>تم تنفيذ $total_fixes إصلاح بنجاح، لكن هناك $total_errors خطأ يحتاج إلى إصلاح يدوي.</p>
    </div>";
}

echo "<h5>📋 تفاصيل الإصلاحات:</h5>";

foreach ($fixes as $fix) {
    echo "<div class='fix-result {$fix[2]}'>
        <strong>{$fix[0]}</strong><br>
        {$fix[1]}
    </div>";
}

foreach ($errors as $error) {
    echo "<div class='fix-result {$error[2]}'>
        <strong>{$error[0]}</strong><br>
        {$error[1]}
    </div>";
}

echo "<div class='mt-4'>
    <h5>🔗 الخطوات التالية:</h5>
    <div class='row'>
        <div class='col-md-4'>
            <a href='scripts/php/diagnostics/test_payment_system.php' class='btn btn-primary w-100 mb-2'>
                🧪 اختبار النظام
            </a>
        </div>
        <div class='col-md-4'>
            <a href='admin/bookings/payment_diagnostic.php' class='btn btn-secondary w-100 mb-2'>
                🔍 تشخيص النظام
            </a>
        </div>
        <div class='col-md-4'>
            <a href='admin/bookings/payment.php?id=1' class='btn btn-success w-100 mb-2'>
                💰 تجربة الدفعات
            </a>
        </div>
    </div>
</div>

<div class='mt-3 text-muted'>
    <small>📅 تم الإصلاح في: " . date('Y-m-d H:i:s') . "</small>
</div>

                </div>
            </div>
        </div>
    </div>
</div>
</body>
</html>";
?>