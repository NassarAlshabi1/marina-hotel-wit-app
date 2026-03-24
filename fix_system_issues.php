<?php
/**
 * ملف إصلاح مشاكل النظام المحسن
 * يقوم بإصلاح تناقضات البيانات وتحسين بنية قاعدة البيانات
 */

require_once 'includes/db.php';
require_once 'includes/auth.php';

// التحقق من صلاحيات المدير
if (!isset($_SESSION['user_type']) || $_SESSION['user_type'] !== 'admin') {
    header("Location: login.php?error=ليس لديك صلاحية للوصول إلى هذه الصفحة");
    exit();
}

echo "<!DOCTYPE html>
<html dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>إصلاح مشاكل النظام</title>
    <style>
        body { font-family: 'Tajawal', sans-serif; padding: 20px; }
        h1, h2 { color: #333; }
        .success { color: green; }
        .error { color: red; }
        .warning { color: orange; }
    </style>
</head>
<body>";

echo "<h1>إصلاح مشاكل النظام</h1>";

// تسجيل الإجراء في سجل النظام
function log_action($conn, $action, $details) {
    // إنشاء جدول السجلات إذا لم يكن موجوداً
    $create_logs_table = "
    CREATE TABLE IF NOT EXISTS system_logs (
        log_id INT AUTO_INCREMENT PRIMARY KEY,
        action VARCHAR(100) NOT NULL,
        details TEXT,
        user_id INT,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_action (action),
        INDEX idx_created_at (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

    $conn->query($create_logs_table);

    $query = "INSERT INTO system_logs (action, details, user_id, created_at)
              VALUES (?, ?, ?, NOW())";
    $stmt = $conn->prepare($query);
    $user_id = $_SESSION['user_id'] ?? 0;
    $stmt->bind_param("ssi", $action, $details, $user_id);
    $stmt->execute();
}

// دالة لإضافة الفهارس المفقودة
function add_missing_indexes($conn) {
    $indexes_to_add = [
        // فهارس جدول الحجوزات
        "ALTER TABLE bookings ADD INDEX IF NOT EXISTS idx_room_number (room_number)",
        "ALTER TABLE bookings ADD INDEX IF NOT EXISTS idx_checkin_date (checkin_date)",
        "ALTER TABLE bookings ADD INDEX IF NOT EXISTS idx_status (status)",
        "ALTER TABLE bookings ADD INDEX IF NOT EXISTS idx_guest_phone (guest_phone)",
        "ALTER TABLE bookings ADD INDEX IF NOT EXISTS idx_created_at (created_at)",

        // فهارس جدول الغرف
        "ALTER TABLE rooms ADD INDEX IF NOT EXISTS idx_status (status)",
        "ALTER TABLE rooms ADD INDEX IF NOT EXISTS idx_room_type (room_type)",

        // فهارس جدول المدفوعات (إذا كان موجوداً)
        "ALTER TABLE payment ADD INDEX IF NOT EXISTS idx_booking_id (booking_id)",
        "ALTER TABLE payment ADD INDEX IF NOT EXISTS idx_payment_date (payment_date)",

        // فهارس جدول المعاملات النقدية (إذا كان موجوداً)
        "ALTER TABLE cash_transactions ADD INDEX IF NOT EXISTS idx_transaction_type (transaction_type)",
        "ALTER TABLE cash_transactions ADD INDEX IF NOT EXISTS idx_transaction_time (transaction_time)"
    ];

    $added_count = 0;
    $errors = [];

    foreach ($indexes_to_add as $index_query) {
        if ($conn->query($index_query)) {
            $added_count++;
        } else {
            // تجاهل الأخطاء المتعلقة بالجداول غير الموجودة
            if (strpos($conn->error, "doesn't exist") === false) {
                $errors[] = $conn->error;
            }
        }
    }

    return ['added' => $added_count, 'errors' => $errors];
}

// إصلاح تناقضات حالات الغرف
if (isset($_POST['fix_room_status']) || isset($_POST['fix_all'])) {
    echo "<h2>إصلاح تناقضات حالات الغرف:</h2>";
    
    // بدء المعاملة
    $conn->begin_transaction();
    
    try {
        // 1. تحديث حالات الغرف بناءً على الحجوزات النشطة
        $update_rooms = "UPDATE rooms r
                        LEFT JOIN (
                            SELECT room_number, COUNT(*) as active_bookings
                            FROM bookings
                            WHERE status = 'محجوزة'
                            GROUP BY room_number
                        ) b ON r.room_number = b.room_number
                        SET r.status = CASE 
                                         WHEN b.active_bookings > 0 THEN 'محجوزة'
                                         ELSE 'شاغرة'
                                       END";
        
        $conn->query($update_rooms);
        $rooms_updated = $conn->affected_rows;
        
        // 2. تحديث حالات الحجوزات المتناقضة
        $update_bookings = "UPDATE bookings b
                           LEFT JOIN rooms r ON b.room_number = r.room_number
                           SET b.status = r.status
                           WHERE b.status != r.status AND b.status IN ('محجوزة', 'شاغرة')";
        
        $conn->query($update_bookings);
        $bookings_updated = $conn->affected_rows;
        
        // تنفيذ المعاملة
        $conn->commit();
        
        echo "<p class='success'>✅ تم إصلاح تناقضات حالات الغرف بنجاح.</p>";
        echo "<p>- تم تحديث $rooms_updated غرفة.</p>";
        echo "<p>- تم تحديث $bookings_updated حجز.</p>";
        
        // تسجيل الإجراء
        log_action($conn, "fix_room_status", "تم إصلاح $rooms_updated غرفة و $bookings_updated حجز");
        
    } catch (Exception $e) {
        // التراجع عن المعاملة في حالة حدوث خطأ
        $conn->rollback();
        echo "<p class='error'>❌ حدث خطأ أثناء إصلاح تناقضات حالات الغرف: " . $e->getMessage() . "</p>";
    }
}

// إصلاح المدفوعات اليتيمة
if (isset($_POST['fix_orphaned_payments']) || isset($_POST['fix_all'])) {
    echo "<h2>إصلاح المدفوعات اليتيمة:</h2>";
    
    // الحصول على المدفوعات اليتيمة
    $orphaned_payments = $conn->query("
        SELECT p.payment_id, p.booking_id, p.amount, p.payment_date
        FROM payment p
        LEFT JOIN bookings b ON p.booking_id = b.booking_id
        WHERE b.booking_id IS NULL
    ");
    
    if ($orphaned_payments->num_rows > 0) {
        echo "<p class='warning'>⚠️ تم العثور على " . $orphaned_payments->num_rows . " مدفوعات يتيمة.</p>";
        
        // بدء المعاملة
        $conn->begin_transaction();
        
        try {
            // إنشاء جدول للمدفوعات المحذوفة إذا لم يكن موجودًا
            $conn->query("
                CREATE TABLE IF NOT EXISTS deleted_payments (
                    payment_id INT,
                    booking_id INT,
                    amount DECIMAL(10,2),
                    payment_date DATETIME,
                    deleted_at DATETIME,
                    deleted_by INT,
                    reason VARCHAR(255)
                )
            ");
            
            // نقل المدفوعات اليتيمة إلى جدول المدفوعات المحذوفة
            $moved_count = 0;
            while ($payment = $orphaned_payments->fetch_assoc()) {
                $insert = "INSERT INTO deleted_payments 
                          (payment_id, booking_id, amount, payment_date, deleted_at, deleted_by, reason) 
                          VALUES (?, ?, ?, ?, NOW(), ?, 'مدفوعات يتيمة تم إصلاحها تلقائيًا')";
                
                $stmt = $conn->prepare($insert);
                $user_id = $_SESSION['user_id'] ?? 0;
                $stmt->bind_param("iidsi", 
                    $payment['payment_id'], 
                    $payment['booking_id'], 
                    $payment['amount'], 
                    $payment['payment_date'],
                    $user_id
                );
                
                if ($stmt->execute()) {
                    // حذف المدفوعة من جدول المدفوعات الأصلي
                    $delete = "DELETE FROM payment WHERE payment_id = ?";
                    $stmt_delete = $conn->prepare($delete);
                    $stmt_delete->bind_param("i", $payment['payment_id']);
                    $stmt_delete->execute();
                    $moved_count++;
                }
            }
            
            // تنفيذ المعاملة
            $conn->commit();
            
            echo "<p class='success'>✅ تم نقل $moved_count مدفوعات يتيمة إلى جدول المدفوعات المحذوفة.</p>";
            
            // تسجيل الإجراء
            log_action($conn, "fix_orphaned_payments", "تم نقل $moved_count مدفوعات يتيمة إلى جدول المدفوعات المحذوفة");
            
        } catch (Exception $e) {
            // التراجع عن المعاملة في حالة حدوث خطأ
            $conn->rollback();
            echo "<p class='error'>❌ حدث خطأ أثناء إصلاح المدفوعات اليتيمة: " . $e->getMessage() . "</p>";
        }
    } else {
        echo "<p class='success'>✅ لا توجد مدفوعات يتيمة للإصلاح.</p>";
    }
}

// إضافة الفهارس المفقودة
if (isset($_POST['add_indexes']) || isset($_POST['fix_all'])) {
    echo "<h2>إضافة الفهارس المفقودة:</h2>";

    $result = add_missing_indexes($conn);

    if ($result['added'] > 0) {
        echo "<p class='success'>✅ تم إضافة {$result['added']} فهرس بنجاح.</p>";
        log_action($conn, "add_indexes", "تم إضافة {$result['added']} فهرس");
    }

    if (!empty($result['errors'])) {
        echo "<p class='warning'>⚠️ حدثت بعض الأخطاء:</p>";
        echo "<ul>";
        foreach ($result['errors'] as $error) {
            echo "<li class='error'>" . htmlspecialchars($error) . "</li>";
        }
        echo "</ul>";
    }

    if ($result['added'] == 0 && empty($result['errors'])) {
        echo "<p class='success'>✅ جميع الفهارس موجودة بالفعل.</p>";
    }
}

// إضافة أزرار الإصلاح إذا لم يتم تنفيذ أي إجراء
if (!isset($_POST['fix_room_status']) && !isset($_POST['fix_orphaned_payments']) &&
    !isset($_POST['add_indexes']) && !isset($_POST['fix_all'])) {

    echo "<h2>خيارات الإصلاح المتاحة:</h2>";
    echo "<form method='post'>";
    echo "<button type='submit' name='fix_room_status' style='margin:5px;padding:10px;background-color:#007bff;color:white;border:none;border-radius:5px;'>إصلاح تناقضات حالات الغرف</button><br>";
    echo "<button type='submit' name='fix_orphaned_payments' style='margin:5px;padding:10px;background-color:#ffc107;color:black;border:none;border-radius:5px;'>إصلاح المدفوعات اليتيمة</button><br>";
    echo "<button type='submit' name='add_indexes' style='margin:5px;padding:10px;background-color:#28a745;color:white;border:none;border-radius:5px;'>إضافة الفهارس المفقودة</button><br>";
    echo "<button type='submit' name='fix_all' style='margin:5px;padding:15px;background-color:#dc3545;color:white;border:none;border-radius:5px;font-weight:bold;'>إصلاح جميع المشاكل</button>";
    echo "</form>";
}

// زر العودة إلى تقرير النظام
echo "<p><a href='system_report.php' style='display:inline-block;margin-top:20px;padding:10px;background-color:#4CAF50;color:white;text-decoration:none;border-radius:5px;'>العودة إلى تقرير النظام</a></p>";

echo "</body></html>";
?>
