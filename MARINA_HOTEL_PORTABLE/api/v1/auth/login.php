<?php
require_once __DIR__ . '/../bootstrap.php';
require_once __DIR__ . '/../utils_jwt.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    send_json(false, ['error' => 'Method not allowed'], null, 405);
}

$input = json_input();
$username = trim($input['username'] ?? '');
$password = (string)($input['password'] ?? '');

if ($username === '' || $password === '') {
    send_json(false, ['error' => 'Username and password are required'], null, 400);
}

$stmt = $conn->prepare("SELECT user_id, username, full_name, email, phone, user_type, is_active, password, password_hash FROM users WHERE username = ? LIMIT 1");
$stmt->bind_param('s', $username);
$stmt->execute();
$user = $stmt->get_result()->fetch_assoc();
$stmt->close();

if (!$user || (int)$user['is_active'] !== 1) {
    send_json(false, ['error' => 'Invalid credentials'], null, 401);
}

$verified = false;
if (!empty($user['password_hash'])) {
    $verified = password_verify($password, $user['password_hash']);
} else if (!empty($user['password'])) {
    $verified = hash_equals($user['password'], $password);
}

if (!$verified) {
    send_json(false, ['error' => 'Invalid credentials'], null, 401);
}

$perms = [];
$ps = $conn->prepare("SELECT p.permission_code FROM user_permissions up JOIN permissions p ON p.permission_id = up.permission_id WHERE up.user_id = ?");
$ps->bind_param('i', $user['user_id']);
$ps->execute();
$res = $ps->get_result();
while ($row = $res->fetch_assoc()) { $perms[] = $row['permission_code']; }
$ps->close();

$payload = [
    'user_id' => (int)$user['user_id'],
    'username' => $user['username'],
    'perms' => $perms,
];
$token = jwt_encode($payload, $CONFIG['jwt_secret'], (int)$CONFIG['jwt_ttl_hours']);

$data_user = [
    'id' => (int)$user['user_id'],
    'username' => $user['username'],
    'full_name' => $user['full_name'],
    'user_type' => $user['user_type'],
    'permissions' => $perms,
];

send_json(true, [
    'token' => $token,
    'user' => $data_user
], ['server_time' => time()]);
