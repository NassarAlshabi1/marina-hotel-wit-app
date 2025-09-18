<?php
require_once __DIR__ . '/../includes/init.php';
$method = $_SERVER['REQUEST_METHOD'];
$booking_id = isset($_GET['booking_id']) ? intval($_GET['booking_id']) : (isset($_POST['booking_id']) ? intval($_POST['booking_id']) : 0);
if ($booking_id <= 0) { json_err('رقم الحجز غير صالح', 400); }
$booking_sql = "
    SELECT b.booking_id, b.guest_name, b.guest_phone, b.room_number, b.checkin_date, b.checkout_date,
           r.price AS room_price,
           b.status,
           IFNULL((SELECT SUM(p.amount) FROM payment p WHERE p.booking_id = b.booking_id), 0) AS paid_amount
    FROM bookings b
    LEFT JOIN rooms r ON b.room_number = r.room_number
    WHERE b.booking_id = ? LIMIT 1
";
$stmt = $conn->prepare($booking_sql);
if (!$stmt) { json_err('خطأ في الاستعلام', 500, ['details' => $conn->error]); }
$stmt->bind_param('i', $booking_id);
$stmt->execute();
$res = $stmt->get_result();
if ($res->num_rows === 0) { json_err('الحجز غير موجود', 404); }
$booking = $res->fetch_assoc();
$checkin = new DateTime($booking['checkin_date']);
$checkout = !empty($booking['checkout_date']) ? new DateTime($booking['checkout_date']) : new DateTime($booking['checkin_date']);
$nights = $checkout->diff($checkin)->days; if ($nights < 1) { $nights = 1; }
$total_price = floatval($booking['room_price']) * $nights;
$paid_amount = floatval($booking['paid_amount']);
$remaining = max(0, $total_price - $paid_amount);
if ($method === 'GET') {
    $payments_q = $conn->prepare('SELECT payment_id, amount, payment_date, payment_method, notes FROM payment WHERE booking_id = ? ORDER BY payment_date DESC');
    $payments_q->bind_param('i', $booking_id);
    $payments_q->execute();
    $payments = $payments_q->get_result()->fetch_all(MYSQLI_ASSOC);
    json_ok([
        'booking' => [
            'booking_id' => (int)$booking['booking_id'],
            'guest_name' => $booking['guest_name'],
            'guest_phone' => $booking['guest_phone'],
            'room_number' => $booking['room_number'],
            'checkin_date' => $booking['checkin_date'],
            'checkout_date' => $booking['checkout_date'],
            'status' => $booking['status'],
            'room_price' => floatval($booking['room_price'])
        ],
        'nights' => $nights,
        'total' => $total_price,
        'paid' => $paid_amount,
        'remaining' => $remaining,
        'payments' => $payments
    ]);
}
$action = $_POST['action'] ?? '';
if ($action === 'add_payment') {
    require_permission_any(['manage_payments','finance_manage']);
    $amount = isset($_POST['amount']) ? floatval($_POST['amount']) : 0;
    $payment_date = $_POST['payment_date'] ?? date('Y-m-d H:i:s');
    $payment_method = $conn->real_escape_string($_POST['payment_method'] ?? 'نقدي');
    $notes = $conn->real_escape_string($_POST['notes'] ?? '');
    if ($amount <= 0 || $amount > $remaining) {
        json_err('المبلغ يجب أن يكون بين 1 و ' . number_format($remaining, 0), 400);
    }
    $ins = $conn->prepare('INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes, revenue_type) VALUES (?, ?, ?, ?, ?, \'room\')');
    if (!$ins) { json_err('خطأ في إضافة الدفعة', 500, ['details' => $conn->error]); }
    $ins->bind_param('idsss', $booking_id, $amount, $payment_date, $payment_method, $notes);
    if ($ins->execute()) {
        $remaining_after = $remaining - $amount;
        $phone = $booking['guest_phone'];
        $message = "عزيزي {$booking['guest_name']}، تم استلام دفعة بقيمة: {$amount} ريال\nرقم الحجز: {$booking_id}\nالمبلغ المتبقي: {$remaining_after} ريال\nشكراً لاختيارك فندقنا\nللاستفسار: 9677734587456";
        $wa = send_yemeni_whatsapp($phone, $message);
        $wa_status = '';
        if (is_array($wa) && isset($wa['status'])) {
            $wa_status = ($wa['status'] === 'sent') ? 'وتم إرسال الإشعار للعميل عبر واتساب.' : 'ولكن لم يتم إرسال الإشعار للعميل.';
        } else { $wa_status = 'ولكن لم يتم إرسال الإشعار للعميل.'; }
        json_ok([
            'message' => 'تم تسجيل الدفعة بنجاح ' . $wa_status,
            'remaining' => $remaining_after
        ]);
    } else {
        json_err('خطأ في إضافة الدفعة: ' . $conn->error, 500);
    }
} elseif ($action === 'checkout') {
    require_permission_any(['manage_bookings','bookings_edit','rooms_manage']);
    if ($remaining != 0) { json_err('لا يمكن تسجيل المغادرة قبل تسديد كافة المستحقات.', 400); }
    $conn->begin_transaction();
    try {
        $u1 = $conn->prepare("UPDATE bookings SET status = 'شاغرة', actual_checkout = NOW() WHERE booking_id = ?");
        $u1->bind_param('i', $booking_id);
        if (!$u1->execute()) { throw new Exception($u1->error); }
        $u2 = $conn->prepare("UPDATE rooms SET status = 'شاغرة' WHERE room_number = ?");
        $u2->bind_param('s', $booking['room_number']);
        if (!$u2->execute()) { throw new Exception($u2->error); }
        $conn->commit();
        json_ok(['message' => 'تم تسجيل خروج النزيل بنجاح وتم تحرير الغرفة.']);
    } catch (Exception $e) {
        $conn->rollback();
        json_err('حدث خطأ أثناء عملية تسجيل المغادرة', 500, ['details' => $e->getMessage()]);
    }
} else {
    json_err('طلب غير مدعوم', 405);
}
