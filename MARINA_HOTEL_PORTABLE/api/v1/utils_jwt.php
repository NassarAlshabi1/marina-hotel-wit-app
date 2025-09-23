<?php
function base64url_encode($data) {
    return rtrim(strtr(base64_encode($data), '+/', '-_'), '=');
}
function base64url_decode($data) {
    return base64_decode(strtr($data, '-_', '+/'));
}

function jwt_encode(array $payload, string $secret, int $ttl_hours = 24) {
    $header = ['typ' => 'JWT', 'alg' => 'HS256'];
    $now = time();
    if (!isset($payload['iat'])) $payload['iat'] = $now;
    if (!isset($payload['exp'])) $payload['exp'] = $now + ($ttl_hours * 3600);
    $segments = [base64url_encode(json_encode($header)), base64url_encode(json_encode($payload))];
    $signing_input = implode('.', $segments);
    $signature = hash_hmac('sha256', $signing_input, $secret, true);
    $segments[] = base64url_encode($signature);
    return implode('.', $segments);
}

function jwt_decode_verify(string $jwt, string $secret) {
    $parts = explode('.', $jwt);
    if (count($parts) !== 3) return null;
    list($h64, $p64, $s64) = $parts;
    $payload = json_decode(base64url_decode($p64), true);
    $sig = base64url_decode($s64);
    $expected = hash_hmac('sha256', $h64 . '.' . $p64, $secret, true);
    if (!hash_equals($expected, $sig)) return null;
    if (isset($payload['exp']) && time() >= (int)$payload['exp']) return null;
    return $payload;
}
