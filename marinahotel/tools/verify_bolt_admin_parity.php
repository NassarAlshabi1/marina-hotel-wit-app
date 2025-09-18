<?php
header('Content-Type: application/json; charset=utf-8');
require_once __DIR__ . '/../includes/db.php';

function fetch_booking_calc($conn, $booking_id) {
    $sql = "
        SELECT b.booking_id, b.guest_name, b.guest_phone, b.room_number, b.checkin_date, b.checkout_date,
               r.price AS room_price,
               b.status,
               IFNULL((SELECT SUM(p.amount) FROM payment p WHERE p.booking_id = b.booking_id), 0) AS paid_amount
        FROM bookings b
        LEFT JOIN rooms r ON b.room_number = r.room_number
        WHERE b.booking_id = ? LIMIT 1
    ";
    $stmt = $conn->prepare($sql);
    $stmt->bind_param('i', $booking_id);
    $stmt->execute();
    $res = $stmt->get_result();
    if ($res->num_rows === 0) { return null; }
    $b = $res->fetch_assoc();
    $checkin = new DateTime($b['checkin_date']);
    $co = !empty($b['checkout_date']) ? new DateTime($b['checkout_date']) : new DateTime($b['checkin_date']);
    $nights = $co->diff($checkin)->days; if ($nights < 1) $nights = 1;
    $total = floatval($b['room_price']) * $nights;
    $paid = floatval($b['paid_amount']);
    $remaining = max(0, $total - $paid);
    return [
        'booking_id' => (int)$b['booking_id'],
        'room_price' => floatval($b['room_price']),
        'nights' => $nights,
        'total' => $total,
        'paid' => $paid,
        'remaining' => $remaining,
        'status' => $b['status'],
        'room_number' => $b['room_number'],
    ];
}

function get_bolt_result_http($base_url, $booking_id, $cookie = null) {
    $url = rtrim($base_url, '/') . '/payments.php?booking_id=' . urlencode($booking_id);
    $ch = curl_init($url);
    curl_setopt($ch, CURLOPT_RETURNTRANSFER, true);
    curl_setopt($ch, CURLOPT_TIMEOUT, 10);
    if ($cookie) {
        curl_setopt($ch, CURLOPT_HTTPHEADER, [ 'Cookie: ' . $cookie ]);
    }
    $resp = curl_exec($ch);
    $err = curl_error($ch);
    $status = curl_getinfo($ch, CURLINFO_HTTP_CODE);
    curl_close($ch);
    if ($resp === false) {
        return ['error' => 'HTTP_ERROR', 'details' => $err, 'status' => $status];
    }
    $json = json_decode($resp, true);
    if (!is_array($json)) {
        return ['error' => 'INVALID_JSON', 'raw' => $resp, 'status' => $status];
    }
    if (isset($json['success']) && $json['success'] === false) {
        return ['error' => $json['error'] ?? 'UNKNOWN', 'status' => $status];
    }
    return $json;
}

function cmp_vals($a, $b) {
    $fa = is_null($a) ? null : floatval($a);
    $fb = is_null($b) ? null : floatval($b);
    if ($fa === null && $fb === null) return true;
    return abs($fa - $fb) < 0.0001;
}

$ids_param = $_GET['ids'] ?? '';
$limit = intval($_GET['limit'] ?? 10);
$bolt_url = $_GET['bolt_url'] ?? '';
$cookie = $_GET['cookie'] ?? '';

$booking_ids = [];
if ($ids_param) {
    foreach (explode(',', $ids_param) as $id) {
        $id = intval(trim($id));
        if ($id > 0) $booking_ids[] = $id;
    }
} else {
    $q = $conn->query("SELECT booking_id FROM bookings ORDER BY booking_id DESC LIMIT " . max(1, $limit));
    while ($row = $q->fetch_assoc()) { $booking_ids[] = intval($row['booking_id']); }
}

$results = [];
$diff_count = 0;
$http_errors = 0;

foreach ($booking_ids as $bid) {
    $admin = fetch_booking_calc($conn, $bid);
    if (!$admin) {
        $results[] = [ 'booking_id' => $bid, 'error' => 'BOOKING_NOT_FOUND' ];
        continue;
    }
    $bolt = null;
    $http_status = null;
    if ($bolt_url) {
        $br = get_bolt_result_http($bolt_url, $bid, $cookie ?: null);
        if (isset($br['error'])) {
            $http_errors++;
            $bolt = [ 'error' => $br['error'], 'http_status' => $br['status'] ?? null ];
            $http_status = $br['status'] ?? null;
        } else {
            $bolt = [
                'nights' => $br['nights'] ?? null,
                'total' => $br['total'] ?? null,
                'paid' => $br['paid'] ?? null,
                'remaining' => $br['remaining'] ?? null,
                'status' => $br['booking']['status'] ?? null,
            ];
        }
    }
    $diffs = [];
    if ($bolt && !isset($bolt['error'])) {
        if (!cmp_vals($admin['nights'], $bolt['nights'])) $diffs['nights'] = [ 'admin' => $admin['nights'], 'bolt' => $bolt['nights'] ];
        if (!cmp_vals($admin['total'], $bolt['total'])) $diffs['total'] = [ 'admin' => $admin['total'], 'bolt' => $bolt['total'] ];
        if (!cmp_vals($admin['paid'], $bolt['paid'])) $diffs['paid'] = [ 'admin' => $admin['paid'], 'bolt' => $bolt['paid'] ];
        if (!cmp_vals($admin['remaining'], $bolt['remaining'])) $diffs['remaining'] = [ 'admin' => $admin['remaining'], 'bolt' => $bolt['remaining'] ];
        $admin_can_checkout = ($admin['remaining'] == 0 && $admin['status'] === 'محجوزة');
        $bolt_can_checkout = ($bolt['remaining'] == 0 && ($bolt['status'] ?? '') === 'محجوزة');
        if ($admin_can_checkout !== $bolt_can_checkout) $diffs['checkout_allowed'] = [ 'admin' => $admin_can_checkout, 'bolt' => $bolt_can_checkout ];
    }
    if (!empty($diffs)) $diff_count++;
    $results[] = [
        'booking_id' => $bid,
        'admin' => [
            'nights' => $admin['nights'],
            'total' => $admin['total'],
            'paid' => $admin['paid'],
            'remaining' => $admin['remaining'],
            'status' => $admin['status']
        ],
        'bolt' => $bolt,
        'diffs' => $diffs,
        'http_status' => $http_status
    ];
}

echo json_encode([
    'success' => true,
    'tested' => count($booking_ids),
    'diff_count' => $diff_count,
    'http_errors' => $http_errors,
    'bolt_url' => $bolt_url ?: null,
    'results' => $results
], JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_PRETTY_PRINT);
