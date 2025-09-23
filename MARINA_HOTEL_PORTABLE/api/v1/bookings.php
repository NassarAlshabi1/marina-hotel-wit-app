<?php
require_once __DIR__ . '/bootstrap.php';

$method = $_SERVER['REQUEST_METHOD'];
if ($method === 'POST' || $method === 'PUT') {
    current_user_or_fail(true);
    $input = ($method === 'POST') ? (empty($_POST) ? json_input() : $_POST) : json_input();
    $room = $input['room_number'] ?? null;
    $checkin = $input['checkin_date'] ?? null;
    $checkout = $input['checkout_date'] ?? null; // may be null -> open

    // existing booking id if PUT
    $bid = null;
    if ($method === 'PUT') {
        $path = $_SERVER['PATH_INFO'] ?? '';
        if (preg_match('#/(\d+)$#', $path, $m)) $bid = (int)$m[1];
        if (!$bid && isset($_GET['id'])) $bid = (int)$_GET['id'];
    }

    if ($room && $checkin) {
        $sql = "SELECT COUNT(*) AS c FROM bookings 
                WHERE room_number=? AND (deleted_at IS NULL) AND status='محجوزة' " .
               ($bid ? " AND booking_id <> ?" : "") .
               " AND (COALESCE(checkout_date, '9999-12-31') > ?) 
                  AND (COALESCE(?, '9999-12-31') > checkin_date)";
        if ($bid) {
            $stmt = $conn->prepare($sql);
            $stmt->bind_param('isis', $room, $bid, $checkin, $checkout);
        } else {
            $stmt = $conn->prepare($sql);
            $stmt->bind_param('sss', $room, $checkin, $checkout);
        }
        $stmt->execute();
        $row = $stmt->get_result()->fetch_assoc();
        $stmt->close();
        if ((int)($row['c'] ?? 0) > 0) {
            send_json(false, ['error' => 'Double booking conflict for room', 'room_number' => $room], ['server_time' => time()], 409);
        }
    }
}

handle_entity([
    'table' => 'bookings',
    'pk' => 'booking_id',
    'select' => '*',
    'filter_columns' => ['guest_name','guest_phone','room_number','status'],
    'writable' => [
        'guest_id' => 'i',
        'guest_name' => 's',
        'guest_id_type' => 's',
        'guest_id_number' => 's',
        'guest_id_issue_date' => 's',
        'guest_id_issue_place' => 's',
        'guest_phone' => 's',
        'guest_nationality' => 's',
        'guest_email' => 's',
        'guest_address' => 's',
        'room_number' => 's',
        'checkin_date' => 's',
        'checkout_date' => 's',
        'status' => 's',
        'notes' => 's',
        'expected_nights' => 'i',
        'actual_checkout' => 's',
        'calculated_nights' => 'i'
    ],
    'write_perm' => ['manage_bookings']
]);
