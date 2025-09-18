<?php
header('Content-Type: application/json; charset=utf-8');
if (session_status() === PHP_SESSION_NONE) { session_start(); }
require_once __DIR__ . '/../../includes/db.php';
require_once __DIR__ . '/../../includes/auth_check.php';
require_once __DIR__ . '/../../includes/functions.php';
function require_permission_any($codes) {
    if (!isset($_SESSION['user_id'])) {
        http_response_code(401);
        echo json_encode(['success' => false, 'error' => 'Unauthorized']);
        exit;
    }
    if ($_SESSION['user_type'] === 'admin') { return; }
    $has = false;
    foreach ($codes as $code) {
        if (check_permission($code)) { $has = true; break; }
    }
    if (!$has) {
        http_response_code(403);
        echo json_encode(['success' => false, 'error' => 'Forbidden']);
        exit;
    }
}
function json_ok($data = []) { echo json_encode(['success' => true] + $data, JSON_UNESCAPED_UNICODE); exit; }
function json_err($msg, $code = 400, $extra = []) { http_response_code($code); echo json_encode(['success' => false, 'error' => $msg] + $extra, JSON_UNESCAPED_UNICODE); exit; }
?>