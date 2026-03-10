<?php
/**
 * إعدادات البريد الإلكتروني للمزامنة التلقائية
 * Email Configuration for Auto Sync
 */

// إعدادات البريد الإلكتروني
define('SMTP_HOST', 'smtp.gmail.com');
define('SMTP_PORT', 587);
define('SMTP_USERNAME', 'adenmarina2@gmail.com');
define('SMTP_PASSWORD', ''); // يجب إدخال كلمة مرور التطبيق هنا
define('SMTP_FROM_EMAIL', 'adenmarina2@gmail.com');
define('SMTP_FROM_NAME', 'نظام إدارة الفندق - مارينا');

// إعدادات المزامنة
define('SYNC_ENABLED', true);
define('SYNC_INTERVAL', 300); // كل 5 دقائق (بالثواني)
define('SYNC_EMAIL_TO', 'adenmarina2@gmail.com'); // البريد المستقبل للتحديثات

// أنواع التحديثات المطلوب مزامنتها
$sync_events = [
    'new_booking' => true,      // حجز جديد
    'booking_update' => true,   // تحديث حجز
    'payment' => true,          // دفعة جديدة
    'expense' => true,          // مصروف جديد
    'room_status' => true,      // تغيير حالة غرفة
    'daily_report' => true,     // تقرير يومي
    'system_alert' => true      // تنبيهات النظام
];

/**
 * إرسال بريد إلكتروني
 */
function sendSyncEmail($subject, $body, $isHTML = true) {
    if (!SYNC_ENABLED) {
        return false;
    }

    // استخدام PHPMailer إذا كان متوفراً، وإلا استخدام mail() العادية
    if (class_exists('PHPMailer\PHPMailer\PHPMailer')) {
        return sendEmailWithPHPMailer($subject, $body, $isHTML);
    } else {
        return sendEmailWithMail($subject, $body, $isHTML);
    }
}

/**
 * إرسال بريد إلكتروني باستخدام PHPMailer
 */
function sendEmailWithPHPMailer($subject, $body, $isHTML = true) {
    require_once __DIR__ . '/phpmailer/PHPMailer.php';
    require_once __DIR__ . '/phpmailer/SMTP.php';
    require_once __DIR__ . '/phpmailer/Exception.php';

    use PHPMailer\PHPMailer\PHPMailer;
    use PHPMailer\PHPMailer\SMTP;
    use PHPMailer\PHPMailer\Exception;

    $mail = new PHPMailer(true);

    try {
        // إعدادات الخادم
        $mail->isSMTP();
        $mail->Host       = SMTP_HOST;
        $mail->SMTPAuth   = true;
        $mail->Username   = SMTP_USERNAME;
        $mail->Password   = SMTP_PASSWORD;
        $mail->SMTPSecure = PHPMailer::ENCRYPTION_STARTTLS;
        $mail->Port       = SMTP_PORT;
        $mail->CharSet    = 'UTF-8';

        // المرسل والمستقبل
        $mail->setFrom(SMTP_FROM_EMAIL, SMTP_FROM_NAME);
        $mail->addAddress(SYNC_EMAIL_TO);

        // المحتوى
        $mail->isHTML($isHTML);
        $mail->Subject = $subject;
        $mail->Body    = $body;

        $mail->send();
        return true;
    } catch (Exception $e) {
        error_log("خطأ في إرسال البريد الإلكتروني: {$mail->ErrorInfo}");
        return false;
    }
}

/**
 * إرسال بريد إلكتروني باستخدام mail() العادية
 */
function sendEmailWithMail($subject, $body, $isHTML = true) {
    $headers = [
        'From: ' . SMTP_FROM_NAME . ' <' . SMTP_FROM_EMAIL . '>',
        'Reply-To: ' . SMTP_FROM_EMAIL,
        'X-Mailer: PHP/' . phpversion(),
        'MIME-Version: 1.0'
    ];

    if ($isHTML) {
        $headers[] = 'Content-Type: text/html; charset=UTF-8';
    } else {
        $headers[] = 'Content-Type: text/plain; charset=UTF-8';
    }

    $header_string = implode("\r\n", $headers);
    
    return mail(SYNC_EMAIL_TO, $subject, $body, $header_string);
}

/**
 * تسجيل حدث مزامنة
 */
function logSyncEvent($event_type, $data) {
    global $conn;
    
    if (!isset($conn)) {
        require_once __DIR__ . '/db.php';
    }

    $event_data = json_encode($data, JSON_UNESCAPED_UNICODE);
    $timestamp = date('Y-m-d H:i:s');
    
    $sql = "INSERT INTO sync_log (event_type, event_data, timestamp, synced) VALUES (?, ?, ?, 0)";
    $stmt = $conn->prepare($sql);
    
    if ($stmt) {
        $stmt->bind_param("sss", $event_type, $event_data, $timestamp);
        $result = $stmt->execute();
        $stmt->close();
        return $result;
    }
    
    return false;
}

/**
 * إنشاء جدول سجل المزامنة إذا لم يكن موجوداً
 */
function createSyncLogTable() {
    global $conn;
    
    if (!isset($conn)) {
        require_once __DIR__ . '/db.php';
    }

    $sql = "CREATE TABLE IF NOT EXISTS sync_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        event_type VARCHAR(50) NOT NULL,
        event_data TEXT,
        timestamp DATETIME NOT NULL,
        synced TINYINT(1) DEFAULT 0,
        sync_timestamp DATETIME NULL,
        INDEX idx_event_type (event_type),
        INDEX idx_timestamp (timestamp),
        INDEX idx_synced (synced)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";

    return $conn->query($sql);
}

// إنشاء الجدول عند تحميل الملف
createSyncLogTable();
?>
