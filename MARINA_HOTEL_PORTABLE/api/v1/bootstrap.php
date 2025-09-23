<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/../../includes/config.php';
if (file_exists(__DIR__ . '/../../includes/config_exe.php')) require_once __DIR__ . '/../../includes/config_exe.php';
require_once __DIR__ . '/../../includes/db.php';

$CONFIG = [
    'jwt_secret' => getenv('JWT_SECRET') ?: 'change-me',
    'jwt_ttl_hours' => 24,
    'cors_allowed_origins' => [
        'http://hotelmarina.com:2222',
        'http://hotelmarina.com'
    ],
];

if (defined('TIMEZONE')) date_default_timezone_set(TIMEZONE);
require_once __DIR__ . '/cors.php';
handle_cors($CONFIG);

require_once __DIR__ . '/utils_jwt.php';
require_once __DIR__ . '/middleware.php';

function json_input() {
    $raw = file_get_contents('php://input');
    $data = json_decode($raw, true);
    return is_array($data) ? $data : [];
}

function send_json($success, $data = null, $meta = null, $status = 200) {
    http_response_code($status);
    $out = ['success' => (bool)$success, 'data' => $data];
    if ($meta !== null) $out['meta'] = $meta;
    echo json_encode($out, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function sanitize_filter($conn, $filter) {
    $filter = trim($filter);
    return $conn->real_escape_string($filter);
}
