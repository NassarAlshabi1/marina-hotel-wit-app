<?php
require_once __DIR__ . '/../bootstrap.php';

current_user_or_fail(true);
require_permissions(['manage_rooms']);

if ($_SERVER['REQUEST_METHOD'] !== 'POST') {
    send_json(false, ['error' => 'Method not allowed'], null, 405);
}

$maxSize = 2 * 1024 * 1024; // 2MB
$allowed = ['image/jpeg' => 'jpg', 'image/png' => 'png'];

if (!isset($_FILES['image'])) {
    send_json(false, ['error' => 'No file uploaded'], null, 400);
}

$file = $_FILES['image'];
if ($file['error'] !== UPLOAD_ERR_OK) {
    send_json(false, ['error' => 'Upload error'], null, 400);
}
if ($file['size'] > $maxSize) {
    send_json(false, ['error' => 'File too large (max 2MB)'], null, 400);
}
$finfo = finfo_open(FILEINFO_MIME_TYPE);
$mime = finfo_file($finfo, $file['tmp_name']);
finfo_close($finfo);
if (!isset($allowed[$mime])) {
    send_json(false, ['error' => 'Invalid file type'], null, 400);
}

$room_number = $_POST['room_number'] ?? null;
if (!$room_number) {
    send_json(false, ['error' => 'room_number required'], null, 400);
}

$now = new DateTime('now', new DateTimeZone('UTC'));
$y = $now->format('Y');
$m = $now->format('m');
$baseDir = realpath(__DIR__ . '/../..') . '/uploads/rooms/' . $y . '/' . $m;
if (!is_dir($baseDir)) {
    mkdir($baseDir, 0755, true);
}
$ext = $allowed[$mime];
$fname = uniqid('room_', true) . '.' . $ext;
$dest = $baseDir . '/' . $fname;
if (!move_uploaded_file($file['tmp_name'], $dest)) {
    send_json(false, ['error' => 'Failed to save file'], null, 500);
}

// Build public URL based on MARINA_HOTEL_PORTABLE root
$rootBase = rtrim(BASE_URL, '/');
$rootBase = preg_replace('#/api/v1/.*$#', '', $rootBase); // strip /api/v1/... if present
if (!str_ends_with($rootBase, '/MARINA_HOTEL_PORTABLE')) {
    // try to ensure we end at the portable root
    $rootBase = rtrim($rootBase, '/') . '/MARINA_HOTEL_PORTABLE';
}
$baseUrl = $rootBase . '/uploads/rooms/' . $y . '/' . $m . '/' . $fname;

// In new design, client should PUT /v1/rooms/<room_number> with { image_url: <url> } to persist.
send_json(true, ['url' => $baseUrl, 'meta' => ['filename' => $fname, 'mime' => $mime]], ['server_time' => time()]);
