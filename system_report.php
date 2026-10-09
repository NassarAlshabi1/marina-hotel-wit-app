<?php
session_start();
require_once '../includes/db.php';

// التحقق من صلاحيات المستخدم
require_once '../includes/auth_check_finance.php';
if (!check_system_tools_permission()) {
    header("Location: ../index.php?error=ليس لديك صلاحية للوصول إلى هذه الصفحة");
    exit();
}

// إضافة رأس HTML للتنسيق
echo "<!DOCTYPE html>
<html dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>تقرير حالة النظام</title>
    <style>
        body { font-family: 'Tajawal', sans-serif; padding: 20px; }
        h1, h2, h3 { color: #333; }
        .success { color: green; }
        .error { color: red; }
        table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
        table, th, td { border: 1px solid #ddd; }
        th, td { padding: 8px; text-align: right; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>";

echo "<h1>تقرير حالة النظام</h1>";

// معلومات النظام
echo "<h2>معلومات النظام</h2>";
echo "<ul>";
echo "<li>إصدار PHP: " . phpversion() . "</li>";
echo "<li>نظام التشغيل: " . php_uname() . "</li>";
echo "<li>الذاكرة المخصصة: " . ini_get('memory_limit') . "</li>";
echo "<li>الوقت الحالي للخادم: " . date('Y-m-d H:i:s') . "</li>";
echo "</ul>";

// إحصائيات النظام
echo "<h2>إحصائيات النظام</h2>";

// عدد الحجوزات
$bookings_count = $conn->query("SELECT COUNT(*) as count FROM bookings")->fetch_assoc()['count'];
echo "<p>عدد الحجوزات الكلي: $bookings_count</p>";

// عدد الغرف
$rooms_count = $conn->query("SELECT COUNT(*) as count FROM rooms")->fetch_assoc()['count'];
echo "<p>عدد الغرف: $rooms_count</p>";

// عدد الغرف المحجوزة حاليا
$occupied_rooms = $conn->query("SELECT COUNT(*) as count FROM rooms WHERE status = 'محجوزة'")->fetch_assoc()['count'];
echo "<p>عدد الغرف المحجوزة حاليا: $occupied_rooms</p>";

// إجمالي المصروفات
$total_expenses = $conn->query("SELECT SUM(amount) as total FROM expenses")->fetch_assoc()['total'];
$total_expenses = $total_expenses ?: 0; // تعيين القيمة إلى 0 إذا كانت NULL
echo "<p>إجمالي المصروفات: " . number_format($total_expenses, 2) . " ريال</p>";

// إجمالي المدفوعات
$total_payments = $conn->query("SELECT SUM(amount) as total FROM payment")->fetch_assoc()['total'];
$total_payments = $total_payments ?: 0; // تعيين القيمة إلى 0 إذا كانت NULL
echo "<p>إجمالي المدفوعات: " . number_format($total_payments, 2) . " ريال</p>";

// نتائج الاختبارات
echo "<h2>نتائج الاختبارات</h2>";

// اختبار الاتصال بقاعدة البيانات
echo "<h3>اختبار الاتصال بقاعدة البيانات:</h3>";
if ($conn->ping()) {
    echo "<p class='success'>✅ الاتصال بقاعدة البيانات يعمل بشكل طبيعي</p>";
} else {
    echo "<p class='error'>❌ مشكلة في الاتصال بقاعدة البيانات: " . $conn->error . "</p>";
}

// اختبار تناسق البيانات
echo "<h3>اختبار تناسق البيانات:</h3>";
$data_integrity_issues = 0;

// فحص تناسق حالات الغرف والحجوزات
$room_status_check = $conn->query("
    SELECT COUNT(*) as count
    FROM rooms r
    LEFT JOIN bookings b ON r.room_number = b.room_number AND b.status = 'محجوزة'
    WHERE (r.status = 'محجوزة' AND (b.status IS NULL OR b.status != 'محجوزة'))
       OR (r.status = 'شاغرة' AND b.status = 'محجوزة')
")->fetch_assoc()['count'];

if ($room_status_check > 0) {
    echo "<p class='error'>❌ وجدنا $room_status_check تناقضات في حالات الغرف والحجوزات</p>";
    
    // عرض تفاصيل التناقضات
    $inconsistent_rooms = $conn->query("
        SELECT r.room_number, r.status AS room_status, b.status AS booking_status, b.booking_id
        FROM rooms r
        LEFT JOIN bookings b ON r.room_number = b.room_number AND b.status = 'محجوزة'
        WHERE (r.status = 'محجوزة' AND (b.status IS NULL OR b.status != 'محجوزة'))
           OR (r.status = 'شاغرة' AND b.status = 'محجوزة')
    ");
    
    echo "<table>";
    echo "<tr><th>رقم الغرفة</th><th>حالة الغرفة</th><th>حالة الحجز</th><th>رقم الحجز</th></tr>";
    while ($row = $inconsistent_rooms->fetch_assoc()) {
        echo "<tr>";
        echo "<td>{$row['room_number']}</td>";
        echo "<td>{$row['room_status']}</td>";
        echo "<td>{$row['booking_status']}</td>";
        echo "<td>{$row['booking_id']}</td>";
        echo "</tr>";
    }
    echo "</table>";
    
    $data_integrity_issues++;
} else {
    echo "<p class='success'>✅ حالات الغرف والحجوزات متناسقة</p>";
}

// فحص تناسق المدفوعات
$orphaned_payments = $conn->query("
    SELECT COUNT(*) as count
    FROM payment p
    LEFT JOIN bookings b ON p.booking_id = b.booking_id
    WHERE b.booking_id IS NULL
")->fetch_assoc()['count'];

if ($orphaned_payments > 0) {
    echo "<p class='error'>❌ وجدنا $orphaned_payments مدفوعات لحجوزات غير موجودة</p>";
    
    // عرض تفاصيل المدفوعات اليتيمة
    $orphaned_payments_details = $conn->query("
        SELECT p.payment_id, p.booking_id, p.amount, p.payment_date
        FROM payment p
        LEFT JOIN bookings b ON p.booking_id = b.booking_id
        WHERE b.booking_id IS NULL
    ");
    
    echo "<table>";
    echo "<tr><th>رقم الدفعة</th><th>رقم الحجز</th><th>المبلغ</th><th>تاريخ الدفع</th></tr>";
    while ($row = $orphaned_payments_details->fetch_assoc()) {
        echo "<tr>";
        echo "<td>{$row['payment_id']}</td>";
        echo "<td>{$row['booking_id']}</td>";
        echo "<td>" . number_format($row['amount'], 2) . " ريال</td>";
        echo "<td>{$row['payment_date']}</td>";
        echo "</tr>";
    }
    echo "</table>";
    
    $data_integrity_issues++;
} else {
    echo "<p class='success'>✅ جميع المدفوعات مرتبطة بحجوزات موجودة</p>";
}

// فحص الحجوزات المتداخلة
$overlapping_bookings = $conn->query("
    SELECT COUNT(*) as count
    FROM bookings b1
    JOIN bookings b2 ON b1.room_number = b2.room_number
                    AND b1.booking_id < b2.booking_id
                    AND b1.status = 'محجوزة' AND b2.status = 'محجوزة'
                    AND (
                        (b1.checkin_date BETWEEN b2.checkin_date AND b2.checkout_date)
                        OR (b1.checkout_date BETWEEN b2.checkin_date AND b2.checkout_date)
                        OR (b2.checkin_date BETWEEN b1.checkin_date AND b1.checkout_date)
                        OR (b2.checkout_date BETWEEN b1.checkin_date AND b1.checkout_date)
                    )
")->fetch_assoc()['count'];

if ($overlapping_bookings > 0) {
    echo "<p class='error'>❌ وجدنا $overlapping_bookings حجوزات متداخلة لنفس الغرفة</p>";
    $data_integrity_issues++;
} else {
    echo "<p class='success'>✅ لا توجد حجوزات متداخلة</p>";
}

// النتيجة النهائية
echo "<h2>النتيجة النهائية</h2>";
if ($data_integrity_issues == 0 && $conn->ping()) {
    echo "<p style='color:green;font-weight:bold;font-size:18px;'>النظام يعمل بشكل طبيعي ✅</p>";
} else {
    echo "<p style='color:red;font-weight:bold;font-size:18px;'>يوجد $data_integrity_issues مشاكل في النظام تحتاج إلى معالجة ❌</p>";
    
    // إضافة أزرار لإصلاح المشاكل
    echo "<h3>إجراءات الإصلاح المقترحة:</h3>";
    echo "<form method='post' action='fix_system_issues.php'>";
    echo "<button type='submit' name='fix_room_status' style='margin:5px;padding:10px;'>إصلاح تناقضات حالات الغرف</button>";
    echo "<button type='submit' name='fix_orphaned_payments' style='margin:5px;padding:10px;'>إصلاح المدفوعات اليتيمة</button>";
    echo "<button type='submit' name='fix_all' style='margin:5px;padding:10px;background-color:#ff6b6b;color:white;'>إصلاح جميع المشاكل</button>";
    echo "</form>";
}

echo "<br><a href='../index.php' style='display:inline-block;margin-top:20px;padding:10px;background-color:#4CAF50;color:white;text-decoration:none;border-radius:5px;'>العودة للصفحة الرئيسية</a>";

echo "</body></html>";
?>

