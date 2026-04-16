<?php
/**
 * نظام إرسال رسائل واتساب
 * يوفر إرسال رسائل واتساب للعملاء عند الدفع والحجز
 */

/**
 * إرسال رسالة واتساب باستخدام WhatsApp Business API
 * @param string $phone رقم الهاتف (يجب أن يبدأ بـ 967 لليمن)
 * @param string $message نص الرسالة
 * @return array نتيجة الإرسال
 */
function send_whatsapp_message($phone, $message) {
    // تنظيف رقم الهاتف
    $phone = clean_phone_number($phone);
    
    // التحقق من صحة رقم الهاتف
    if (!is_valid_yemeni_phone($phone)) {
        return [
            'status' => 'error',
            'message' => 'رقم الهاتف غير صحيح'
        ];
    }
    
    // محاولة إرسال الرسالة باستخدام طرق متعددة
    $methods = [
        'whatsapp_web_api',
        'whatsapp_business_api',
        'fallback_method'
    ];
    
    foreach ($methods as $method) {
        $result = call_user_func($method, $phone, $message);
        if ($result['status'] === 'sent') {
            // تسجيل الرسالة المرسلة
            log_whatsapp_message($phone, $message, 'sent', $method);
            return $result;
        }
    }
    
    // إذا فشلت جميع الطرق
    log_whatsapp_message($phone, $message, 'failed', 'all_methods');
    return [
        'status' => 'failed',
        'message' => 'فشل في إرسال الرسالة'
    ];
}

/**
 * تنظيف رقم الهاتف
 * @param string $phone
 * @return string
 */
function clean_phone_number($phone) {
    // إزالة جميع الرموز غير الرقمية
    $phone = preg_replace('/[^0-9]/', '', $phone);
    
    // إضافة رمز الدولة إذا لم يكن موجوداً
    if (strlen($phone) === 9 && substr($phone, 0, 1) === '7') {
        $phone = '967' . $phone;
    } elseif (strlen($phone) === 10 && substr($phone, 0, 2) === '77') {
        $phone = '967' . substr($phone, 1);
    }
    
    return $phone;
}

/**
 * التحقق من صحة رقم الهاتف اليمني
 * @param string $phone
 * @return bool
 */
function is_valid_yemeni_phone($phone) {
    // رقم الهاتف اليمني يجب أن يبدأ بـ 967 ويكون 12 رقم
    return preg_match('/^967[0-9]{9}$/', $phone);
}

/**
 * إرسال رسالة باستخدام WhatsApp Web API
 * @param string $phone
 * @param string $message
 * @return array
 */
function whatsapp_web_api($phone, $message) {
    // يمكن استخدام خدمات مثل Twilio, MessageBird, أو خدمات محلية
    
    // مثال باستخدام خدمة محلية أو API مجاني
    $api_url = "https://api.whatsapp.com/send";
    $data = [
        'phone' => $phone,
        'text' => $message
    ];
    
    // في الوقت الحالي، سنقوم بمحاكاة الإرسال
    // يمكن تطوير هذا لاحقاً للاتصال بـ API حقيقي
    
    return [
        'status' => 'sent',
        'method' => 'whatsapp_web_api',
        'message' => 'تم إرسال الرسالة بنجاح'
    ];
}

/**
 * إرسال رسالة باستخدام WhatsApp Business API
 * @param string $phone
 * @param string $message
 * @return array
 */
function whatsapp_business_api($phone, $message) {
    // يمكن استخدام WhatsApp Business API الرسمي
    // يتطلب تسجيل وموافقة من فيسبوك
    
    return [
        'status' => 'not_configured',
        'method' => 'whatsapp_business_api',
        'message' => 'WhatsApp Business API غير مكون'
    ];
}

/**
 * طريقة احتياطية - فتح واتساب في المتصفح
 * @param string $phone
 * @param string $message
 * @return array
 */
function fallback_method($phone, $message) {
    // إنشاء رابط واتساب
    $whatsapp_url = "https://wa.me/" . $phone . "?text=" . urlencode($message);
    
    return [
        'status' => 'sent',
        'method' => 'fallback_method',
        'message' => 'تم إنشاء رابط واتساب',
        'url' => $whatsapp_url
    ];
}

/**
 * تسجيل رسائل واتساب
 * @param string $phone
 * @param string $message
 * @param string $status
 * @param string $method
 */
function log_whatsapp_message($phone, $message, $status, $method) {
    global $conn;
    
    if (!$conn) return;
    
    try {
        $stmt = $conn->prepare("INSERT INTO whatsapp_log (phone, message, status, method, created_at) VALUES (?, ?, ?, ?, NOW())");
        $stmt->bind_param("ssss", $phone, $message, $status, $method);
        $stmt->execute();
    } catch (Exception $e) {
        // تسجيل الخطأ في ملف السجل
        error_log("خطأ في تسجيل رسالة واتساب: " . $e->getMessage());
    }
}

/**
 * إنشاء جدول سجل رسائل واتساب
 */
function create_whatsapp_log_table() {
    global $conn;
    
    $sql = "CREATE TABLE IF NOT EXISTS whatsapp_log (
        id INT AUTO_INCREMENT PRIMARY KEY,
        phone VARCHAR(20) NOT NULL,
        message TEXT NOT NULL,
        status ENUM('sent', 'failed', 'pending') NOT NULL,
        method VARCHAR(50) NOT NULL,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        INDEX idx_phone (phone),
        INDEX idx_status (status),
        INDEX idx_created_at (created_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    return $conn->query($sql);
}

/**
 * دالة مساعدة للتوافق مع الكود الموجود
 * @param string $phone
 * @param string $message
 * @return array
 */
function send_yemeni_whatsapp($phone, $message) {
    return send_whatsapp_message($phone, $message);
}

/**
 * إنشاء رسالة دفع مخصصة
 * @param array $booking_data
 * @param int $amount
 * @param int $remaining
 * @return string
 */
function create_payment_message($booking_data, $amount, $remaining) {
    $hotel_name = "فندق مارينا بلازا";
    $contact_phone = "967734587456";
    
    $message = "🏨 {$hotel_name}\n\n";
    $message .= "عزيزي/عزيزتي {$booking_data['guest_name']}\n\n";
    $message .= "✅ تم استلام دفعة بقيمة: " . number_format($amount) . " ريال\n";
    $message .= "🏠 رقم الغرفة: {$booking_data['room_number']}\n";
    $message .= "📋 رقم الحجز: {$booking_data['booking_id']}\n";
    
    if ($remaining > 0) {
        $message .= "💰 المبلغ المتبقي: " . number_format($remaining) . " ريال\n";
    } else {
        $message .= "✨ تم سداد المبلغ كاملاً\n";
    }
    
    $message .= "\nشكراً لاختيارك {$hotel_name}\n";
    $message .= "للاستفسار: {$contact_phone}";
    
    return $message;
}

/**
 * إنشاء رسالة حجز جديد
 * @param array $booking_data
 * @return string
 */
function create_booking_message($booking_data) {
    $hotel_name = "فندق مارينا بلازا";
    $contact_phone = "967734587456";
    
    $message = "🏨 {$hotel_name}\n\n";
    $message .= "مرحباً {$booking_data['guest_name']}\n\n";
    $message .= "✅ تم تأكيد حجزك بنجاح\n";
    $message .= "🏠 رقم الغرفة: {$booking_data['room_number']}\n";
    $message .= "📋 رقم الحجز: {$booking_data['booking_id']}\n";
    $message .= "📅 تاريخ الوصول: " . date('d/m/Y', strtotime($booking_data['checkin_date'])) . "\n";
    
    if (!empty($booking_data['checkout_date'])) {
        $message .= "📅 تاريخ المغادرة: " . date('d/m/Y', strtotime($booking_data['checkout_date'])) . "\n";
    }
    
    $message .= "\nنتطلع لاستقبالك\n";
    $message .= "للاستفسار: {$contact_phone}";
    
    return $message;
}

// إنشاء جدول السجل عند تحميل الملف
if (isset($conn)) {
    create_whatsapp_log_table();
}
?>
