<?php
// دالة لتنظيف وتنسيق رقم الهاتف اليمني
function format_yemeni_phone($phone) {
    // إزالة جميع الأحرف غير الرقمية
    $phone = preg_replace('/[^0-9]/', '', $phone);
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

// دالة لإرسال رسالة واتساب للعملاء اليمنيين عبر API خارجي
function send_yemeni_whatsapp($phone, $message) {
    $api_url = "https://wa.nux.my.id/api/sendWA";
    $secret_key = "d4fc5abd713b541b7013f978e8cc4495";

    $phone = format_yemeni_phone($phone);
    if (!$phone) {
        return ['status' => 'error', 'message' => 'رقم الهاتف اليمني غير صالح'];
    }

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
    $response = curl_exec($ch);
    curl_close($ch);

    if ($response === false) {
        return ['status' => 'error', 'message' => 'فشل الاتصال بخادم الواتساب'];
    }

    return json_decode($response, true);
}
?>
