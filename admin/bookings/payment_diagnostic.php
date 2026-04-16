<?php
session_start();
require '../../includes/db.php';
require_once '../../includes/functions.php';

// فحص حالة النظام
$diagnostics = [];
$errors = [];

// 1. فحص قاعدة البيانات
try {
    $conn->query("SELECT 1");
    $diagnostics['database'] = "✅ قاعدة البيانات متصلة بنجاح";
} catch (Exception $e) {
    $errors[] = "❌ خطأ في قاعدة البيانات: " . $e->getMessage();
    $diagnostics['database'] = "❌ قاعدة البيانات غير متصلة";
}

// 2. فحص جدول payment
try {
    $payment_check = $conn->query("SHOW TABLES LIKE 'payment'");
    if ($payment_check->num_rows > 0) {
        $diagnostics['payment_table'] = "✅ جدول payment موجود";
        
        // فحص البنية
        $structure = $conn->query("DESCRIBE payment");
        $fields = [];
        while ($row = $structure->fetch_assoc()) {
            $fields[] = $row['Field'];
        }
        $diagnostics['payment_structure'] = "✅ أعمدة الجدول: " . implode(', ', $fields);
        
        // فحص البيانات
        $count = $conn->query("SELECT COUNT(*) as count FROM payment")->fetch_assoc()['count'];
        $diagnostics['payment_data'] = "✅ عدد الدفعات المسجلة: " . $count;
        
    } else {
        $errors[] = "❌ جدول payment غير موجود";
        $diagnostics['payment_table'] = "❌ جدول payment غير موجود";
    }
} catch (Exception $e) {
    $errors[] = "❌ خطأ في فحص جدول payment: " . $e->getMessage();
    $diagnostics['payment_table'] = "❌ خطأ في فحص جدول payment";
}

// 3. فحص جدول bookings
try {
    $bookings_check = $conn->query("SHOW TABLES LIKE 'bookings'");
    if ($bookings_check->num_rows > 0) {
        $diagnostics['bookings_table'] = "✅ جدول bookings موجود";
        
        $count = $conn->query("SELECT COUNT(*) as count FROM bookings")->fetch_assoc()['count'];
        $diagnostics['bookings_data'] = "✅ عدد الحجوزات المسجلة: " . $count;
    } else {
        $errors[] = "❌ جدول bookings غير موجود";
        $diagnostics['bookings_table'] = "❌ جدول bookings غير موجود";
    }
} catch (Exception $e) {
    $errors[] = "❌ خطأ في فحص جدول bookings: " . $e->getMessage();
    $diagnostics['bookings_table'] = "❌ خطأ في فحص جدول bookings";
}

// 4. فحص ملف functions.php
if (file_exists('../../includes/functions.php')) {
    $diagnostics['functions_file'] = "✅ ملف functions.php موجود";
    
    if (function_exists('send_yemeni_whatsapp')) {
        $diagnostics['whatsapp_function'] = "✅ دالة الواتساب متوفرة";
    } else {
        $errors[] = "❌ دالة الواتساب غير متوفرة";
        $diagnostics['whatsapp_function'] = "❌ دالة الواتساب غير متوفرة";
    }
} else {
    $errors[] = "❌ ملف functions.php غير موجود";
    $diagnostics['functions_file'] = "❌ ملف functions.php غير موجود";
}

// 5. فحص الأذونات
$diagnostics['session_status'] = session_status() === PHP_SESSION_ACTIVE ? "✅ الجلسة نشطة" : "❌ الجلسة غير نشطة";
$diagnostics['php_version'] = "✅ إصدار PHP: " . phpversion();
$diagnostics['output_buffering'] = ob_get_level() > 0 ? "✅ Output buffering نشط" : "❌ Output buffering غير نشط";

// 6. فحص اتصال آخر حجز
try {
    $last_booking = $conn->query("SELECT booking_id, guest_name, created_at FROM bookings ORDER BY booking_id DESC LIMIT 1");
    if ($last_booking && $last_booking->num_rows > 0) {
        $booking = $last_booking->fetch_assoc();
        $diagnostics['last_booking'] = "✅ آخر حجز: #" . $booking['booking_id'] . " - " . $booking['guest_name'];
    } else {
        $diagnostics['last_booking'] = "⚠️ لا توجد حجوزات";
    }
} catch (Exception $e) {
    $errors[] = "❌ خطأ في فحص الحجوزات: " . $e->getMessage();
    $diagnostics['last_booking'] = "❌ خطأ في فحص الحجوزات";
}

// 7. فحص آخر دفعة
try {
    $last_payment = $conn->query("SELECT payment_id, booking_id, amount, payment_date FROM payment ORDER BY payment_id DESC LIMIT 1");
    if ($last_payment && $last_payment->num_rows > 0) {
        $payment = $last_payment->fetch_assoc();
        $diagnostics['last_payment'] = "✅ آخر دفعة: #" . $payment['payment_id'] . " - " . $payment['amount'] . " ريال";
    } else {
        $diagnostics['last_payment'] = "⚠️ لا توجد دفعات مسجلة";
    }
} catch (Exception $e) {
    $errors[] = "❌ خطأ في فحص الدفعات: " . $e->getMessage();
    $diagnostics['last_payment'] = "❌ خطأ في فحص الدفعات";
}

// 8. فحص مسار الملفات
$diagnostics['current_file'] = "✅ المسار الحالي: " . __FILE__;
$diagnostics['includes_path'] = file_exists('../../includes/') ? "✅ مجلد includes موجود" : "❌ مجلد includes غير موجود";

?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تشخيص نظام الدفعات</title>
    <link href="../../include../../includes/css/bootstrap.min.css" rel="stylesheet">
    <link href="../../includes/css/fontawesome.min.css" rel="stylesheet">
    <link href="../../includes/css/cairo-font.css" rel="stylesheet">
    <link href="../../includes/css/custom.css" rel="stylesheet">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Cairo', sans-serif;
        }
        .diagnostic-item {
            padding: 10px;
            margin: 5px 0;
            border-radius: 5px;
            border-left: 4px solid #007bff;
        }
        .diagnostic-success {
            background-color: #d4edda;
            border-left-color: #28a745;
        }
        .diagnostic-error {
            background-color: #f8d7da;
            border-left-color: #dc3545;
        }
        .diagnostic-warning {
            background-color: #fff3cd;
            border-left-color: #ffc107;
        }
        .emoji {
            font-size: 1.2em;
            margin-left: 10px;
        }
    </style>
</head>
<body>

<div class="container py-4">
    <div class="row justify-content-center">
        <div class="col-lg-10">
            
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h3 class="card-title mb-0">
                        <i class="fas fa-stethoscope me-2"></i>
                        تشخيص نظام الدفعات
                    </h3>
                </div>
                <div class="card-body">
                    
                    <?php if (empty($errors)): ?>
                        <div class="alert alert-success">
                            <i class="fas fa-check-circle me-2"></i>
                            <strong>ممتاز!</strong> جميع الفحوصات تمت بنجاح. النظام يعمل بشكل صحيح.
                        </div>
                    <?php else: ?>
                        <div class="alert alert-danger">
                            <i class="fas fa-exclamation-triangle me-2"></i>
                            <strong>تحذير!</strong> تم اكتشاف <?= count($errors) ?> خطأ في النظام:
                            <ul class="mt-2 mb-0">
                                <?php foreach ($errors as $error): ?>
                                    <li><?= htmlspecialchars($error) ?></li>
                                <?php endforeach; ?>
                            </ul>
                        </div>
                    <?php endif; ?>
                    
                    <h5 class="mt-4 mb-3">
                        <i class="fas fa-list-check me-2"></i>
                        نتائج التشخيص التفصيلية
                    </h5>
                    
                    <?php foreach ($diagnostics as $key => $result): ?>
                        <div class="diagnostic-item <?= 
                            strpos($result, '✅') !== false ? 'diagnostic-success' : 
                            (strpos($result, '❌') !== false ? 'diagnostic-error' : 'diagnostic-warning') 
                        ?>">
                            <strong><?= ucfirst(str_replace('_', ' ', $key)) ?>:</strong>
                            <?= htmlspecialchars($result) ?>
                        </div>
                    <?php endforeach; ?>
                    
                    <div class="mt-4 pt-3 border-top">
                        <h5>
                            <i class="fas fa-tools me-2"></i>
                            أدوات التشخيص
                        </h5>
                        <div class="row">
                            <div class="col-md-4">
                                <a href="payment.php?id=1" class="btn btn-outline-primary w-100 mb-2">
                                    <i class="fas fa-money-check-alt me-2"></i>
                                    اختبار صفحة الدفعات
                                </a>
                            </div>
                            <div class="col-md-4">
                                <a href="list.php" class="btn btn-outline-secondary w-100 mb-2">
                                    <i class="fas fa-list me-2"></i>
                                    قائمة الحجوزات
                                </a>
                            </div>
                            <div class="col-md-4">
                                <a href="../../admin/dash.php" class="btn btn-outline-success w-100 mb-2">
                                    <i class="fas fa-tachometer-alt me-2"></i>
                                    لوحة التحكم
                                </a>
                            </div>
                        </div>
                    </div>
                    
                    <div class="mt-3">
                        <small class="text-muted">
                            <i class="fas fa-clock me-1"></i>
                            تم التشخيص في: <?= date('Y-m-d H:i:s') ?>
                        </small>
                    </div>
                    
                </div>
            </div>
            
        </div>
    </div>
</div>

<script src="../../includes/js/bootstrap.bundle.min.js"></script>
<script src="../../includes/js/custom../../includes/js/bootstrap.bundle.min.js"></script>
<script src="../../includes/js/custom.js"></script>
</body>
</html>