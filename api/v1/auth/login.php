<?php
/**
 * نقطة نهاية تسجيل الدخول
 * POST /api/v1/auth/login.php
 */

require_once __DIR__ . '/../config.php';

// التحقق من طريقة الطلب
if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    jsonResponse(false, null, 'طريقة الطلب غير مدعومة', 405);
}

// الحصول على بيانات الإدخال
$input = getInput();

// التحقق من الحقول المطلوبة
validateRequired($input, ['username', 'password']);

$username = sanitizeInput($input['username']);
$password = $input['password']; // لا نقوم بتنظيف كلمة المرور حتى لا نؤثر على التحقق

// البحث عن المستخدم
$stmt = $conn->prepare("
    SELECT id, username, password, full_name, role, status, token
    FROM users 
    WHERE username = ? AND status = 'active'
    LIMIT 1
");

$stmt->bind_param('s', $username);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    // تسجيل محاولة فاشلة
    $stmt = $conn->prepare("
        INSERT INTO failed_logins (username, ip_address, attempt_time)
        VALUES (?, ?, NOW())
    ");
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $stmt->bind_param('ss', $username, $ip);
    $stmt->execute();
    
    jsonResponse(false, null, 'اسم المستخدم أو كلمة المرور غير صحيحة', 401);
}

$user = $result->fetch_assoc();

// التحقق من كلمة المرور
if (!password_verify($password, $user['password'])) {
    // تسجيل محاولة فاشلة
    $stmt = $conn->prepare("
        INSERT INTO failed_logins (username, ip_address, attempt_time)
        VALUES (?, ?, NOW())
    ");
    $ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
    $stmt->bind_param('ss', $username, $ip);
    $stmt->execute();
    
    jsonResponse(false, null, 'اسم المستخدم أو كلمة المرور غير صحيحة', 401);
}

// توليد توكن جديد إذا لم يكن موجودًا
if (empty($user['token'])) {
    $token = bin2hex(random_bytes(32));
    $stmt = $conn->prepare("UPDATE users SET token = ? WHERE id = ?");
    $stmt->bind_param('si', $token, $user['id']);
    $stmt->execute();
    $user['token'] = $token;
}

// تسجيل نشاط المستخدم
$stmt = $conn->prepare("
    INSERT INTO user_activity_log (user_id, action, details, ip_address)
    VALUES (?, 'login', 'تسجيل دخول ناجح عبر API', ?)
");
$ip = $_SERVER['REMOTE_ADDR'] ?? 'unknown';
$stmt->bind_param('is', $user['id'], $ip);
$stmt->execute();

// إرجاع البيانات
unset($user['password']); // إزالة كلمة المرور من الاستجابة

jsonResponse(true, [
    'token' => $user['token'],
    'user' => [
        'id' => (int)$user['id'],
        'username' => $user['username'],
        'full_name' => $user['full_name'],
        'role' => $user['role']
    ]
], null, 200);
