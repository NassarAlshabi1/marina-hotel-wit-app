<?php
require_once __DIR__ . '/utils_jwt.php';

function require_auth($CONFIG) {
    $headers = getallheaders();
    $auth = $headers['Authorization'] ?? $headers['authorization'] ?? '';
    if (stripos($auth, 'Bearer ') !== 0) {
        http_response_code(401);
        echo json_encode(['success' => false, 'data' => ['error' => 'unauthorized']]);
        exit;
    }
    $token = substr($auth, 7);
    $payload = jwt_decode_verify($token, $CONFIG['jwt_secret']);
    if (!$payload) {
        http_response_code(401);
        echo json_encode(['success' => false, 'data' => ['error' => 'unauthorized']]);
        exit;
    }
    return $payload;
}
