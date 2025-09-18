<?php
require_once __DIR__ . '/../includes/init.php';
if ($_SERVER['REQUEST_METHOD'] !== 'GET') { json_err('طريقة غير مدعومة', 405); }
$guest_name = isset($_GET['name']) ? trim($_GET['name']) : '';
if ($guest_name === '') { json_err('اسم النزيل مطلوب', 400); }
$bookings_sql = "
    SELECT 
        b.*, r.type as room_type, r.price as room_price,
        COALESCE(SUM(p.amount), 0) as total_paid
    FROM bookings b
    LEFT JOIN rooms r ON b.room_number = r.room_number
    LEFT JOIN payment p ON b.booking_id = p.booking_id
    WHERE b.guest_name = ?
    GROUP BY b.booking_id
    ORDER BY b.checkin_date DESC
";
$stmt = $conn->prepare($bookings_sql);
$stmt->bind_param('s', $guest_name);
$stmt->execute();
$bookings = $stmt->get_result()->fetch_all(MYSQLI_ASSOC);
$stats_sql = "
    SELECT 
        COUNT(*) as total_bookings,
        SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings,
        SUM(CASE WHEN status = 'مكتملة' THEN 1 ELSE 0 END) as completed_bookings,
        SUM(CASE WHEN status = 'ملغية' THEN 1 ELSE 0 END) as cancelled_bookings,
        MIN(checkin_date) as first_visit,
        MAX(checkin_date) as last_visit
    FROM bookings WHERE guest_name = ?
";
$stmt2 = $conn->prepare($stats_sql);
$stmt2->bind_param('s', $guest_name);
$stmt2->execute();
$stats = $stmt2->get_result()->fetch_assoc();
$pay_sql = "SELECT COALESCE(SUM(p.amount), 0) as total_payments FROM bookings b LEFT JOIN payment p ON b.booking_id = p.booking_id WHERE b.guest_name = ?";
$stmt3 = $conn->prepare($pay_sql);
$stmt3->bind_param('s', $guest_name);
$stmt3->execute();
$total_payments = $stmt3->get_result()->fetch_assoc()['total_payments'] ?? 0;
json_ok(['bookings' => $bookings, 'stats' => $stats, 'total_payments' => floatval($total_payments)]);
