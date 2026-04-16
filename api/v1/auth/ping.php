<?php
/**
 * نقطة نهاية اختبار الاتصال والمصادقة
 * GET /api/v1/auth/ping.php
 */

require_once __DIR__ . '/../config.php';

// التحقق من طريقة الطلب
if ($_SERVER['REQUEST_METHOD'] !== 'GET') {
    jsonResponse(false, null, 'طريقة الطلب غير مدعومة', 405);
}

// التحقق من المصادقة
$user = authenticateRequest();

// إرجاع البيانات
jsonResponse(true, [
    'authenticated' => true,
    'user' => [
        'id' => (int)$user['id'],
        'username' => $user['username'],
        'full_name' => $user['full_name'],
        'role' => $user['role']
    ]
], null, 200);
