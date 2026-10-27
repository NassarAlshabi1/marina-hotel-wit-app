<?php
/**
 * ملف الدوال المساعدة المحسن
 * يحتوي على دوال مساعدة محسنة مع دعم كامل للغة العربية
 */

/**
 * دالة لتنظيف وتنسيق رقم الهاتف اليمني
 * @param string $phone رقم الهاتف المدخل
 * @return string|false رقم الهاتف المنسق أو false في حالة الخطأ
 */
function format_yemeni_phone($phone) {
    if (empty($phone)) {
        return false;
    }

    // إزالة جميع الأحرف غير الرقمية والمسافات
    $phone = preg_replace('/[^0-9]/', '', trim($phone));

    // التحقق من طول الرقم
    if (strlen($phone) < 8 || strlen($phone) > 15) {
        return false;
    }

    // تحويل إلى الصيغة الدولية (967)
    if (strlen($phone) >= 12 && strpos($phone, '00967') === 0) {
        return '967' . substr($phone, 5);
    } elseif (strlen($phone) >= 10 && strpos($phone, '967') === 0) {
        return $phone; // الرقم بالفعل بالصيغة الصحيحة
    } elseif (strlen($phone) >= 9 && strpos($phone, '07') === 0) {
        return '967' . substr($phone, 1);
    } elseif (strlen($phone) >= 8 && strpos($phone, '7') === 0) {
        return '967' . $phone;
    }

    return false; // رقم غير صالح
}

/**
 * دالة للتحقق من صحة رقم الهاتف اليمني
 * @param string $phone رقم الهاتف
 * @return bool
 */
function is_valid_yemeni_phone($phone) {
    $formatted = format_yemeni_phone($phone);
    if (!$formatted) {
        return false;
    }

    // التحقق من أن الرقم يبدأ بأحد أكواد الشبكات اليمنية
    $valid_prefixes = ['96770', '96771', '96773', '96777', '96778'];

    foreach ($valid_prefixes as $prefix) {
        if (strpos($formatted, $prefix) === 0) {
            return true;
        }
    }

    return false;
}

/**
 * دالة لإرسال رسالة واتساب للعملاء اليمنيين عبر API خارجي
 * @param string $phone رقم الهاتف
 * @param string $message الرسالة
 * @return array نتيجة الإرسال
 */
function send_yemeni_whatsapp($phone, $message) {
    try {
        $api_url = "https://wa.nux.my.id/api/sendWA";
        $secret_key = "d4fc5abd713b541b7013f978e8cc4495";

        $phone = format_yemeni_phone($phone);
        if (!$phone) {
            return ['status' => 'error', 'message' => 'رقم الهاتف اليمني غير صالح'];
        }

        // تنظيف الرسالة وضمان الترميز الصحيح
        $message = clean_arabic_text($message);

        $url = sprintf(
            "%s?to=%s&msg=%s&secret=%s",
            $api_url,
            urlencode($phone),
            urlencode($message),
            $secret_key
        );

        $ch = curl_init();
        curl_setopt($ch, CURLOPT_URL, $url);
        curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
        curl_setopt($ch, CURLOPT_TIMEOUT, 10);
        curl_setopt($ch, CURLOPT_CONNECTTIMEOUT, 5);
        curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, false);
        curl_setopt($ch, CURLOPT_USERAGENT, 'Hotel Management System');

        $response = curl_exec($ch);
        $http_code = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $curl_error = curl_error($ch);
        curl_close($ch);

        if ($response === false || !empty($curl_error)) {
            log_custom_error("فشل إرسال واتساب", [
                'phone' => $phone,
                'curl_error' => $curl_error,
                'http_code' => $http_code
            ]);
            return ['status' => 'error', 'message' => 'فشل الاتصال بخادم الواتساب'];
        }

        $result = json_decode($response, true);
        if (json_last_error() !== JSON_ERROR_NONE) {
            return ['status' => 'error', 'message' => 'استجابة غير صحيحة من الخادم'];
        }

        return $result;

    } catch (Exception $e) {
        log_custom_error("خطأ في إرسال واتساب", [
            'phone' => $phone,
            'error' => $e->getMessage()
        ]);
        return ['status' => 'error', 'message' => 'حدث خطأ في إرسال الرسالة'];
    }
}

/**
 * دالة لتنظيف النص العربي وضمان الترميز الصحيح
 * @param string $text النص المراد تنظيفه
 * @return string النص المنظف
 */
function clean_arabic_text($text) {
    if (empty($text)) {
        return '';
    }

    // تحويل الترميز إلى UTF-8 إذا لم يكن كذلك
    if (!mb_check_encoding($text, 'UTF-8')) {
        $text = mb_convert_encoding($text, 'UTF-8', 'auto');
    }

    // إزالة المسافات الزائدة
    $text = preg_replace('/\s+/', ' ', trim($text));

    // تنظيف الأحرف الخاصة
    $text = str_replace(["\r\n", "\r", "\n"], ' ', $text);

    return $text;
}

/**
 * دالة لتنسيق التاريخ بالعربية
 * @param string $date التاريخ
 * @param string $format تنسيق التاريخ
 * @return string التاريخ المنسق
 */
function format_arabic_date($date, $format = 'Y-m-d H:i:s') {
    if (empty($date)) {
        return '';
    }

    $timestamp = is_numeric($date) ? $date : strtotime($date);
    if (!$timestamp) {
        return $date;
    }

    $formatted = date($format, $timestamp);

    // تحويل الأرقام إلى العربية إذا لزم الأمر
    $arabic_numbers = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];
    $english_numbers = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];

    // يمكن تفعيل هذا إذا كنت تريد الأرقام العربية
    // $formatted = str_replace($english_numbers, $arabic_numbers, $formatted);

    return $formatted;
}

/**
 * دالة لتنسيق المبالغ المالية
 * @param float $amount المبلغ
 * @param string $currency العملة
 * @return string المبلغ المنسق
 */
function format_currency($amount, $currency = 'ريال') {
    if (!is_numeric($amount)) {
        return '0 ' . $currency;
    }

    return number_format($amount, 2, '.', ',') . ' ' . $currency;
}

/**
 * دالة للتحقق من صحة البريد الإلكتروني
 * @param string $email البريد الإلكتروني
 * @return bool
 */
function is_valid_email($email) {
    return !empty($email) && filter_var($email, FILTER_VALIDATE_EMAIL);
}

/**
 * دالة لتوليد كلمة مرور عشوائية
 * @param int $length طول كلمة المرور
 * @return string كلمة المرور
 */
function generate_password($length = 8) {
    $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*';
    return substr(str_shuffle($chars), 0, $length);
}

/**
 * دالة لتشفير البيانات الحساسة
 * @param string $data البيانات
 * @param string $key المفتاح
 * @return string البيانات المشفرة
 */
function encrypt_data($data, $key = null) {
    if (empty($data)) {
        return '';
    }

    $key = $key ?: hash('sha256', 'hotel_system_key_2024');
    $iv = openssl_random_pseudo_bytes(16);
    $encrypted = openssl_encrypt($data, 'AES-256-CBC', $key, 0, $iv);

    return base64_encode($iv . $encrypted);
}

/**
 * دالة لفك تشفير البيانات
 * @param string $encrypted_data البيانات المشفرة
 * @param string $key المفتاح
 * @return string البيانات المفكوكة
 */
function decrypt_data($encrypted_data, $key = null) {
    if (empty($encrypted_data)) {
        return '';
    }

    $key = $key ?: hash('sha256', 'hotel_system_key_2024');
    $data = base64_decode($encrypted_data);
    $iv = substr($data, 0, 16);
    $encrypted = substr($data, 16);

    return openssl_decrypt($encrypted, 'AES-256-CBC', $key, 0, $iv);
}
?>
