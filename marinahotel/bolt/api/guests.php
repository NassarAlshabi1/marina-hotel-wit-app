<?php
require_once __DIR__ . '/../includes/init.php';
if ($_SERVER['REQUEST_METHOD'] !== 'GET') { json_err('طريقة غير مدعومة', 405); }
$search = isset($_GET['search']) ? trim($_GET['search']) : '';
$query = '';
$params = [];
$types = '';
if ($search !== '') {
    $query = "
        SELECT DISTINCT 
            guest_name,
            guest_phone,
            guest_email,
            guest_nationality,
            guest_id_number,
            guest_id_type,
            COUNT(*) as total_bookings,
            MAX(checkin_date) as last_visit,
            SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings
        FROM bookings
        WHERE guest_name LIKE ? OR guest_phone LIKE ? OR guest_email LIKE ?
        GROUP BY guest_name, guest_phone, guest_email
        ORDER BY last_visit DESC
    ";
    $sp = "%$search%";
    $params = [$sp,$sp,$sp];
    $types = 'sss';
    $stmt = $conn->prepare($query);
    $stmt->bind_param($types, ...$params);
    $stmt->execute();
    $rows = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
} else {
    $query = "
        SELECT DISTINCT 
            guest_name,
            guest_phone,
            guest_email,
            guest_nationality,
            guest_id_number,
            guest_id_type,
            COUNT(*) as total_bookings,
            MAX(checkin_date) as last_visit,
            SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings
        FROM bookings
        GROUP BY guest_name, guest_phone, guest_email
        ORDER BY last_visit DESC
        LIMIT 50
    ";
    $rows = $conn->query($query)->fetch_all(MYSQLI_ASSOC);
}
$stats = [];
$stats['total_guests'] = intval($conn->query("SELECT COUNT(DISTINCT guest_name) as count FROM bookings")->fetch_assoc()['count']);
$stats['active_guests'] = intval($conn->query("SELECT COUNT(DISTINCT guest_name) as count FROM bookings WHERE status = 'محجوزة'")->fetch_assoc()['count']);
$stats['repeat_guests'] = intval($conn->query("SELECT COUNT(*) as count FROM (SELECT guest_name FROM bookings GROUP BY guest_name HAVING COUNT(*) > 1) as t")->fetch_assoc()['count']);
json_ok(['records' => $rows, 'stats' => $stats]);
