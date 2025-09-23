<?php
require_once __DIR__ . '/../bootstrap.php';

$current = current_user_or_fail(true);

// Refresh token: extend exp and re-attach current permissions from DB
$user_id = (int)$current['sub'];
$perms = [];
$ps = $conn->prepare("SELECT p.permission_code FROM user_permissions up JOIN permissions p ON p.permission_id = up.permission_id WHERE up.user_id = ?");
$ps->bind_param('i', $user_id);
$ps->execute();
$res = $ps->get_result();
while ($row = $res->fetch_assoc()) { $perms[] = $row['permission_code']; }
$ps->close();

$exp = time() + 60 * 60 * 12;
$new_payload = [
    'sub' => $user_id,
    'username' => $current['username'] ?? '',
    'permissions' => $perms,
    'exp' => $exp
];
$token = jwt_encode($new_payload, jwt_secret());

send_json(true, ['token' => $token, 'permissions' => $perms], ['server_time' => time()]);
