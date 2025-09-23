<?php
require_once __DIR__ . '/../bootstrap.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    send_json(false, ['error' => 'Method not allowed'], null, 405);
}

$input = json_input();
$username = trim($input['username'] ?? '');
$password = (string)($input['password'] ?? '');

if ($username === '' || $password === '') {
    send_json(false, ['error' => 'Username and password are required'], null, 400);
}

// fetch user
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

// permissions
$perms = [];
$ps = $conn->prepare("SELECT p.permission_code FROM user_permissions up JOIN permissions p ON p.permission_id = up.permission_id WHERE up.user_id = ?");
$ps->bind_param('i', $user['user_id']);
$ps->execute();
$res = $ps->get_result();
while ($row = $res->fetch_assoc()) { $perms[] = $row['permission_code']; }
$ps->close();

$exp = time() + 60 * 60 * 12; // 12 hours
$payload = [
    'sub' => (int)$user['user_id'],
    'username' => $user['username'],
    'permissions' => $perms,
    'exp' => $exp
];
$token = jwt_encode($payload, jwt_secret());

unset($user['password']);
unset($user['password_hash']);

send_json(true, [
    'token' => $token,
    'user' => $user,
    'permissions' => $perms
], ['server_time' => time()]);
