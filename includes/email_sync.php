<?php
/**
 * نظام المزامنة التلقائية عبر البريد الإلكتروني
 * Auto Sync System via Email - كل دقيقتين
 */

// إعدادات البريد الإلكتروني
define('SYNC_EMAIL', 'adenmarina2@gmail.com');
define('SYNC_INTERVAL', 120); // كل دقيقتين (120 ثانية)
define('SYNC_ENABLED', true);

/**
 * إرسال تحديثات المزامنة عبر البريد الإلكتروني
 */
function sendSyncUpdate($subject, $data) {
    if (!SYNC_ENABLED) {
        return false;
    }

    $headers = [
        'From: نظام إدارة الفندق <' . SYNC_EMAIL . '>',
        'Content-Type: text/html; charset=UTF-8',
        'X-Mailer: Hotel Management System'
    ];

    $body = generateSyncEmailBody($data);
    
    return mail(SYNC_EMAIL, $subject, $body, implode("\r\n", $headers));
}

/**
 * إنشاء محتوى البريد الإلكتروني
 */
function generateSyncEmailBody($data) {
    $timestamp = date('Y-m-d H:i:s');
    
    $html = "
    <!DOCTYPE html>
    <html dir='rtl' lang='ar'>
    <head>
        <meta charset='UTF-8'>
        <style>
            body { font-family: Arial, sans-serif; direction: rtl; }
            .header { background: #2c3e50; color: white; padding: 20px; text-align: center; }
            .content { padding: 20px; }
            .data-table { width: 100%; border-collapse: collapse; margin: 10px 0; }
            .data-table th, .data-table td { border: 1px solid #ddd; padding: 8px; text-align: right; }
            .data-table th { background: #f2f2f2; }
            .timestamp { color: #666; font-size: 12px; }
        </style>
    </head>
    <body>
        <div class='header'>
            <h2>🏨 تحديث نظام إدارة الفندق</h2>
            <p class='timestamp'>وقت التحديث: {$timestamp}</p>
        </div>
        <div class='content'>
            {$data}
        </div>
    </body>
    </html>";
    
    return $html;
}

/**
 * جمع بيانات المزامنة
 */
function collectSyncData() {
    global $conn;
    
    if (!$conn) {
        require_once 'db.php';
    }

    $data = [];
    
    // الحجوزات الجديدة في آخر دقيقتين
    $recent_bookings = getRecentBookings();
    if (!empty($recent_bookings)) {
        $data['bookings'] = $recent_bookings;
    }
    
    // المدفوعات الجديدة
    $recent_payments = getRecentPayments();
    if (!empty($recent_payments)) {
        $data['payments'] = $recent_payments;
    }
    
    // المصروفات الجديدة
    $recent_expenses = getRecentExpenses();
    if (!empty($recent_expenses)) {
        $data['expenses'] = $recent_expenses;
    }
    
    // تغييرات حالة الغرف
    $room_changes = getRecentRoomChanges();
    if (!empty($room_changes)) {
        $data['room_changes'] = $room_changes;
    }
    
    return $data;
}

/**
 * الحصول على الحجوزات الجديدة
 */
function getRecentBookings() {
    global $conn;
    
    $sql = "SELECT booking_id, guest_name, room_number, checkin_date, checkout_date, total_amount, created_at 
            FROM bookings 
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL 2 MINUTE)
            ORDER BY created_at DESC";
    
    $result = $conn->query($sql);
    $bookings = [];
    
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $bookings[] = $row;
        }
    }
    
    return $bookings;
}

/**
 * الحصول على المدفوعات الجديدة
 */
function getRecentPayments() {
    global $conn;
    
    $sql = "SELECT p.payment_id, p.amount, p.payment_method, p.payment_date, b.guest_name, b.room_number
            FROM payment p
            JOIN bookings b ON p.booking_id = b.booking_id
            WHERE p.payment_date >= DATE_SUB(NOW(), INTERVAL 2 MINUTE)
            ORDER BY p.payment_date DESC";
    
    $result = $conn->query($sql);
    $payments = [];
    
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $payments[] = $row;
        }
    }
    
    return $payments;
}

/**
 * الحصول على المصروفات الجديدة
 */
function getRecentExpenses() {
    global $conn;
    
    $sql = "SELECT id, description, amount, expense_type, date, created_at
            FROM expenses 
            WHERE created_at >= DATE_SUB(NOW(), INTERVAL 2 MINUTE)
            ORDER BY created_at DESC";
    
    $result = $conn->query($sql);
    $expenses = [];
    
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $expenses[] = $row;
        }
    }
    
    return $expenses;
}

/**
 * الحصول على تغييرات حالة الغرف
 */
function getRecentRoomChanges() {
    global $conn;
    
    // إنشاء جدول سجل تغييرات الغرف إذا لم يكن موجوداً
    $create_table = "CREATE TABLE IF NOT EXISTS room_status_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        room_number VARCHAR(10) NOT NULL,
        old_status VARCHAR(20),
        new_status VARCHAR(20) NOT NULL,
        changed_by VARCHAR(100),
        change_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_room_number (room_number),
        INDEX idx_change_time (change_time)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4";
    
    $conn->query($create_table);
    
    $sql = "SELECT room_number, old_status, new_status, changed_by, change_time
            FROM room_status_log 
            WHERE change_time >= DATE_SUB(NOW(), INTERVAL 2 MINUTE)
            ORDER BY change_time DESC";
    
    $result = $conn->query($sql);
    $changes = [];
    
    if ($result && $result->num_rows > 0) {
        while ($row = $result->fetch_assoc()) {
            $changes[] = $row;
        }
    }
    
    return $changes;
}

/**
 * تنسيق البيانات للعرض في البريد الإلكتروني
 */
function formatSyncDataForEmail($data) {
    $content = '';
    
    if (isset($data['bookings']) && !empty($data['bookings'])) {
        $content .= "<h3>🆕 حجوزات جديدة</h3>";
        $content .= "<table class='data-table'>";
        $content .= "<tr><th>اسم النزيل</th><th>رقم الغرفة</th><th>تاريخ الوصول</th><th>تاريخ المغادرة</th><th>المبلغ</th></tr>";
        
        foreach ($data['bookings'] as $booking) {
            $content .= "<tr>";
            $content .= "<td>" . htmlspecialchars($booking['guest_name']) . "</td>";
            $content .= "<td>" . htmlspecialchars($booking['room_number']) . "</td>";
            $content .= "<td>" . $booking['checkin_date'] . "</td>";
            $content .= "<td>" . $booking['checkout_date'] . "</td>";
            $content .= "<td>" . number_format($booking['total_amount']) . " ريال</td>";
            $content .= "</tr>";
        }
        $content .= "</table>";
    }
    
    if (isset($data['payments']) && !empty($data['payments'])) {
        $content .= "<h3>💰 مدفوعات جديدة</h3>";
        $content .= "<table class='data-table'>";
        $content .= "<tr><th>اسم النزيل</th><th>رقم الغرفة</th><th>المبلغ</th><th>طريقة الدفع</th></tr>";
        
        foreach ($data['payments'] as $payment) {
            $content .= "<tr>";
            $content .= "<td>" . htmlspecialchars($payment['guest_name']) . "</td>";
            $content .= "<td>" . htmlspecialchars($payment['room_number']) . "</td>";
            $content .= "<td>" . number_format($payment['amount']) . " ريال</td>";
            $content .= "<td>" . htmlspecialchars($payment['payment_method']) . "</td>";
            $content .= "</tr>";
        }
        $content .= "</table>";
    }
    
    if (isset($data['expenses']) && !empty($data['expenses'])) {
        $content .= "<h3>💸 مصروفات جديدة</h3>";
        $content .= "<table class='data-table'>";
        $content .= "<tr><th>الوصف</th><th>النوع</th><th>المبلغ</th><th>التاريخ</th></tr>";
        
        foreach ($data['expenses'] as $expense) {
            $content .= "<tr>";
            $content .= "<td>" . htmlspecialchars($expense['description']) . "</td>";
            $content .= "<td>" . htmlspecialchars($expense['expense_type']) . "</td>";
            $content .= "<td>" . number_format($expense['amount']) . " ريال</td>";
            $content .= "<td>" . $expense['date'] . "</td>";
            $content .= "</tr>";
        }
        $content .= "</table>";
    }
    
    if (isset($data['room_changes']) && !empty($data['room_changes'])) {
        $content .= "<h3>🏠 تغييرات حالة الغرف</h3>";
        $content .= "<table class='data-table'>";
        $content .= "<tr><th>رقم الغرفة</th><th>الحالة السابقة</th><th>الحالة الجديدة</th><th>وقت التغيير</th></tr>";
        
        foreach ($data['room_changes'] as $change) {
            $content .= "<tr>";
            $content .= "<td>" . htmlspecialchars($change['room_number']) . "</td>";
            $content .= "<td>" . htmlspecialchars($change['old_status']) . "</td>";
            $content .= "<td>" . htmlspecialchars($change['new_status']) . "</td>";
            $content .= "<td>" . $change['change_time'] . "</td>";
            $content .= "</tr>";
        }
        $content .= "</table>";
    }
    
    if (empty($content)) {
        $content = "<p>✅ لا توجد تحديثات جديدة في آخر دقيقتين</p>";
    }
    
    return $content;
}

/**
 * تشغيل المزامنة
 */
function runSync() {
    if (!SYNC_ENABLED) {
        return false;
    }
    
    $data = collectSyncData();
    
    if (!empty($data)) {
        $formatted_data = formatSyncDataForEmail($data);
        $subject = "🔄 تحديث نظام الفندق - " . date('H:i:s');
        
        return sendSyncUpdate($subject, $formatted_data);
    }
    
    return true; // لا توجد بيانات للمزامنة
}
?>
