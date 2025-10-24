<?php
require_once __DIR__ . '/../bootstrap.php';
require_once __DIR__ . '/../utils_jwt.php';

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    send_json(false, ['error' => 'Method not allowed'], null, 405);
}

$input = json_input();
$id_token = $input['id_token'] ?? '';
$username = trim($input['username'] ?? '');
$password = (string)($input['password'] ?? '');

if ($id_token !== '') {
    // Google Sign-In
    $ch = curl_init();
    curl_setopt($ch, CURLOPT_URL, 'https://www.googleapis.com/oauth2/v3/tokeninfo?id_token=' . urlencode($id_token));
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, 1);
    curl_setopt($ch, CURLOPT_SSL_VERIFYPEER, true);
    $response = curl_exec($ch);
    $httpCode = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    
    if ($httpCode !== 200) {
        send_json(false, ['error' => 'Invalid Google token'], null, 401);
    }
    
    $token_info = json_decode($response, true);
    if (json_last_error() !== JSON_ERROR_NONE || !isset($token_info['email'])) {
        send_json(false, ['error' => 'Invalid token format'], null, 401);
    }
    
    $email = $token_info['email'];
    $name = $token_info['name'] ?? $token_info['email'];
    
    // Find or create user by email
    $stmt = $conn->prepare("SELECT user_id, username, full_name, email, phone, user_type, is_active FROM users WHERE email = ?");
    $stmt->bind_param('s', $email);
    $stmt->execute();
    $user = $stmt->get_result()->fetch_assoc();
    $stmt->close();
    
    if (!$user) {
        // Create new user
        $username = explode('@', $email)[0];
        $user_type = 'guest';
        $is_active = 1;
        
        $stmt = $conn->prepare("INSERT INTO users (username, full_name, email, user_type, is_active) VALUES (?, ?, ?, ?, ?)");
        $stmt->bind_param('ssssi', $username, $name, $email, $user_type, $is_active);
        $stmt->execute();
        $user_id = $conn->insert_id;
        $stmt->close();
        
        $user = [
            'user_id' => $user_id,
            'username' => $username,
            'full_name' => $name,
            'email' => $email,
            'user_type' => $user_type,
            'is_active' => $is_active
        ];
    } else if ((int)$user['is_active'] !== 1) {
        send_json(false, ['error' => 'Account inactive'], null, 401);
    }
} else if ($username === '' || $password === '') {
    send_json(false, ['error' => 'Username and password are required'], null, 400);
} else {
    // Traditional login
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

// Fetch permissions
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
