<?php
require_once __DIR__ . '/../includes/init.php';
require_permission_any(['manage_bookings','bookings_add']);
if ($_SERVER['REQUEST_METHOD'] !== 'POST') { json_err('طريقة غير مدعومة', 405); }
$input = $_POST;
$prefill = [
    'guest_name' => trim($input['guest_name'] ?? ''),
    'guest_phone' => trim($input['guest_phone'] ?? ''),
    'guest_email' => trim($input['guest_email'] ?? ''),
    'guest_nationality' => trim($input['guest_nationality'] ?? ''),
    'guest_id_type' => trim($input['guest_id_type'] ?? ''),
    'guest_id_number' => trim($input['guest_id_number'] ?? ''),
    'room_number' => $input['room_number'] ?? null,
    'checkin_date' => $input['checkin_date'] ?? date('Y-m-d H:i:s'),
    'checkout_date' => $input['checkout_date'] ?? null
];
json_ok(['prefill' => $prefill]);
