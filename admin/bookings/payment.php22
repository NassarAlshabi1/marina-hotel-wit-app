<?php
ob_start();
include '../../includes/db.php';

require_once '../../includes/functions.php';

// التحقق من معرف الحجز
$booking_id = intval($_GET['id'] ?? 0);
if ($booking_id <= 0) {
    die("رقم الحجز غير صالح");
}

$booking_query = "
    SELECT b.booking_id, b.guest_name, b.guest_phone, b.room_number, b.checkin_date, b.checkout_date, 
           r.price AS room_price,
           b.status,
           IFNULL((SELECT SUM(p.amount) FROM payment p WHERE p.booking_id = b.booking_id), 0) AS paid_amount
    FROM bookings b
    LEFT JOIN rooms r ON b.room_number = r.room_number
    WHERE b.booking_id = ? LIMIT 1
";

$stmt = $conn->prepare($booking_query);
if (!$stmt) {
    die("خطأ في الاستعلام: " . $conn->error);
}
$stmt->bind_param("i", $booking_id);
$stmt->execute();
$booking_result = $stmt->get_result();
if ($booking_result->num_rows === 0) {
    die("الحجز غير موجود");
}
$booking = $booking_result->fetch_assoc();

$checkin = new DateTime($booking['checkin_date']);
$checkout = new DateTime($booking['checkout_date']);
$nights = $checkout->diff($checkin)->days;
if ($nights < 1) $nights = 1;

$total_price = $booking['room_price'] * $nights;
$paid_amount = $booking['paid_amount'];
$remaining = max(0, $total_price - $paid_amount);

// تسجيل المغادرة إذا تم الطلب
if (isset($_POST['checkout'])) {
    if ($remaining == 0) {
        $conn->begin_transaction();
        try {
            $update_booking = "UPDATE bookings SET status = 'شاغرة', actual_checkout = NOW() WHERE booking_id = ?";
            $stmt_update_booking = $conn->prepare($update_booking);
            $stmt_update_booking->bind_param("i", $booking_id);
            if (!$stmt_update_booking->execute()) {
                throw new Exception("خطأ في تحديث حالة الحجز: " . $stmt_update_booking->error);
            }

            $update_room = "UPDATE rooms SET status = 'شاغرة' WHERE room_number = ?";
            $stmt_update_room = $conn->prepare($update_room);
            $stmt_update_room->bind_param("s", $booking['room_number']);
            if (!$stmt_update_room->execute()) {
                throw new Exception("خطأ في تحديث حالة الغرفة: " . $stmt_update_room->error);
            }

            $conn->commit();
            echo '<script>
                document.addEventListener("DOMContentLoaded", function() {
                    Swal.fire({
                        icon: "success",
                        title: "نجاح",
                        text: "تم تسجيل خروج النزيل بنجاح وتم تحرير الغرفة.",
                        confirmButtonText: "موافق"
                    }).then((result) => {
                        if (result.isConfirmed) {
                            window.location.href = "payment.php?id=' . $booking_id . '";
                        }
                    });
                });
            </script>';
            exit();
        } catch (Exception $e) {
            $conn->rollback();
            $error = $e->getMessage();
        }
    } else {
        $error = "لا يمكن تسجيل المغادرة قبل تسديد كافة المستحقات.";
    }
}
include '../../includes/header.php';
// جلب الدفعات
$payments_query = "SELECT * FROM payment WHERE booking_id = ? ORDER BY payment_date DESC";
$stmt_payments = $conn->prepare($payments_query);
$stmt_payments->bind_param("i", $booking_id);
$stmt_payments->execute();
$payments_res = $stmt_payments->get_result();

// معالجة إضافة دفعة جديدة
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['submit_payment'])) {
    $amount = floatval($_POST['amount']);
    $payment_date = $_POST['payment_date'] ?? date('Y-m-d H:i:s');
    $payment_method = $conn->real_escape_string($_POST['payment_method'] ?? 'نقدي');
    $notes = $conn->real_escape_string($_POST['notes'] ?? '');

    if ($amount <= 0 || $amount > $remaining) {
        $error = "المبلغ يجب أن يكون بين 1 و " . number_format($remaining, 0) . " ";
    } else {
        $insert_sql = "INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes)
                       VALUES (?, ?, ?, ?, ?)";
        $stmt_insert = $conn->prepare($insert_sql);
        $stmt_insert->bind_param("idsss", $booking_id, $amount, $payment_date, $payment_method, $notes);
        
        if ($stmt_insert->execute()) {
            $remaining_after_payment = $remaining - $amount;
            $phone = $booking['guest_phone'];
            $message = "عزيزي {$booking['guest_name']}، تم استلام دفعة بقيمة: {$amount} ريال\nرقم الحجز: {$booking_id}\nالمبلغ المتبقي: {$remaining_after_payment} ريال\nشكراً لاختيارك فندقنا\nللاستفسار: 9677734587456";

            $wa_result = send_yemeni_whatsapp($phone, $message);
            
            // تحسين معالجة نتيجة إرسال الواتساب
            $wa_status = '';
            if (is_array($wa_result) && isset($wa_result['status'])) {
                $wa_status = $wa_result['status'] === 'sent' ? 
                    "وتم إرسال الإشعار للعميل عبر واتساب." : 
                    "ولكن لم يتم إرسال الإشعار للعميل.";
            } else {
                $wa_status = "ولكن لم يتم إرسال الإشعار للعميل.";
            }

            // استخدام json_encode لتجنب مشاكل الأحرف الخاصة
            $success_msg = json_encode("تم تسجيل الدفعة بنجاح " . $wa_status);
            
            echo '<script>
                document.addEventListener("DOMContentLoaded", function() {
                    Swal.fire({
                        icon: "success",
                        title: "نجاح",
                        text: ' . $success_msg . ',
                        confirmButtonText: "موافق"
                    }).then((result) => {
                        if (result.isConfirmed) {
                            window.location.href = "payment.php?id=' . $booking_id . '";
                        }
                    });
                });
            </script>';
            exit();
        } else {
            $error = "خطأ في إضافة الدفعة: " . $conn->error;
        }
    }
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <title>إدارة الدفعات - حجز #<?= htmlspecialchars($booking_id) ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <script src="https://cdn.jsdelivr.net/npm/sweetalert2@11"></script>
    <style>
        .checkout-btn {position: fixed; bottom: 20px; left: 20px; z-index: 1000;}
        .back-btn {position: fixed; bottom: 20px; right: 20px; z-index: 1000;}
        .highlight-row {background-color: #fff3cd;}
        .total-row {font-weight: bold; background-color: #f8f9fa;}
        .badge {padding: 5px 10px; border-radius: 20px; font-size: 0.8rem; font-weight: 600;}
        
        body {
            font-family: 'Tajawal', sans-serif;
            font-weight: bold;
            direction: rtl;
            text-align: right;
        }
        
        .payment-header {
            background: linear-gradient(135deg, #667eea, #764ba2);
            color: white;
            padding: 25px 15px;
            border-radius: 12px;
            margin-bottom: 20px;
            text-align: center;
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .payment-header h1 {
            margin: 0;
            font-size: 1.8rem;
            font-weight: 700;
        }
        .booking-id {
            font-size: 1.1rem;
            margin-top: 10px;
            opacity: 0.9;
        }
        
        .form-control, .form-select {
            font-weight: bold;
            text-align: right;
        }
        
        input[type="number"] {
            font-family: Arial, sans-serif;
            direction: ltr;
            text-align: left;
        }
    </style>
</head>
<body>
<div class="container py-4">
    <div class="payment-header">
        <h1><i class="fas fa-credit-card"></i> إدارة المدفوعات</h1>
        <div class="booking-id">حجز رقم <?= htmlspecialchars($booking_id) ?> - <?= htmlspecialchars($booking['guest_name']) ?></div>
    </div>

    <?php if (isset($error)): ?>
        <script>
        document.addEventListener("DOMContentLoaded", function() {
            Swal.fire({
                icon: 'error',
                title: 'خطأ',
                text: <?= json_encode($error) ?>,
                confirmButtonText: 'موافق'
            });
        });
        </script>
    <?php endif; ?>

    <div class="row">
        <div class="col-md-6">
            <div class="card shadow-sm mb-4">
                <div class="card-header bg-primary text-white">
                    <i class="fas fa-info-circle"></i> تفاصيل الحجز
                </div>
                <div class="card-body">
                    <table class="table">
                        <tr><th width="40%">اسم النزيل:</th><td><?= htmlspecialchars($booking['guest_name']); ?></td></tr>
                        <tr><th>رقم الهاتف:</th><td><?= htmlspecialchars($booking['guest_phone']); ?></td></tr>
                        <tr><th>رقم الغرفة:</th><td><?= htmlspecialchars($booking['room_number']); ?></td></tr>
                        <tr><th>تاريخ الوصول:</th><td><?= date('d/m/Y', strtotime($booking['checkin_date'])); ?></td></tr>
                        <tr><th>تاريخ المغادرة:</th><td><?= date('d/m/Y', strtotime($booking['checkout_date'])); ?></td></tr>
                        <tr><th>عدد الليالي:</th><td><?= $nights ?> ليلة</td></tr>
                        <tr><th>سعر الليلة:</th><td><?= number_format($booking['room_price'], 0); ?> </td></tr>
                        <tr class="total-row"><th>المبلغ الإجمالي:</th><td><?= number_format($total_price, 0); ?> </td></tr>
                        <tr><th>المدفوع:</th><td><?= number_format($paid_amount, 0); ?> </td></tr>
                        <tr class="total-row"><th>المتبقي:</th><td><?= number_format($remaining, 0); ?> </td></tr>
                        <tr><th>حالة الحجز:</th>
                            <td>
                                <span class="badge" style="background: <?= $booking['status'] == 'محجوزة' ? '#28a745' : '#17a2b8' ?>;">
                                    <?= htmlspecialchars($booking['status']) ?>
                                </span>
                            </td>
                        </tr>
                    </table>
                </div>
            </div>
        </div>

        <div class="col-md-6">
            <div class="card shadow-sm">
                <div class="card-header bg-success text-white"><i class="fas fa-money-bill-wave"></i> إضافة دفعة جديدة</div>
                <div class="card-body">
                    <?php if ($remaining > 0): ?>
                    <form method="post" novalidate>
                        <div class="mb-3">
                            <label for="amount" class="form-label">المبلغ </label>
                            <input type="number" name="amount" id="amount" class="form-control"
                                   step="0.01" min="0.01" max="<?= $remaining ?>" value="<?= min($remaining, 1000) ?>" required>
                        </div>
                        <div class="mb-3">
                            <label for="payment_date" class="form-label">تاريخ ووقت الدفع</label>
                            <input type="datetime-local" name="payment_date" id="payment_date" class="form-control"
                                   value="<?= date('Y-m-d\TH:i') ?>" required>
                        </div>
                        <div class="mb-3">
                            <label for="payment_method" class="form-label">طريقة الدفع</label>
                            <select name="payment_method" id="payment_method" class="form-select" required>
                                <option value="نقدي">💵 نقدي</option>
                                <option value="تحويل بنكي"> تحويل حوالة</option>
                            </select>
                        </div>
                        <div class="mb-3">
                            <label for="notes" class="form-label">ملاحظات</label>
                            <textarea name="notes" id="notes" class="form-control" rows="2"></textarea>
                        </div>
                        <button type="submit" name="submit_payment" class="btn btn-success w-100">
                            <i class="fas fa-check-circle"></i> تسجيل الدفعة وإرسال إشعار للعميل
                        </button>
                    </form>
                    <?php else: ?>
                        <div class="alert alert-info text-center">
                            <i class="fas fa-check-circle"></i> تم تسديد كامل المبلغ المستحق
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>

    <!-- سجل الدفعات -->
    <div class="card shadow-sm mt-4">
        <div class="card-header bg-info text-white"><i class="fas fa-history"></i> سجل الدفعات</div>
        <div class="card-body">
            <?php if ($payments_res && $payments_res->num_rows > 0): ?>
                <div class="table-responsive">
                    <table class="table table-hover">
                        <thead>
                        <tr>
                            <th>#</th>
                            <th>المبلغ</th>
                            <th>التاريخ والوقت</th>
                            <th>طريقة الدفع</th>
                            <th>ملاحظات</th>
                        </tr>
                        </thead>
                        <tbody>
                        <?php while ($payment = $payments_res->fetch_assoc()): ?>
                            <tr>
                                <td>#<?= $payment['payment_id'] ?></td>
                                <td><strong><?= number_format($payment['amount'], 0) ?> </strong></td>
                                <td><?= date('d/m/Y - H:i', strtotime($payment['payment_date'])) ?></td>
                                <td>
                                    <span class="badge"><?= htmlspecialchars($payment['payment_method']) ?></span>
                                </td>
                                <td><?= htmlspecialchars($payment['notes'] ?: 'لا توجد ملاحظات') ?></td>
                            </tr>
                        <?php endwhile; ?>
                        </tbody>
                    </table>
                </div>
            <?php else: ?>
                <p class="text-center">لا توجد دفعات مسجلة.</p>
            <?php endif; ?>
        </div>
    </div>

    <!-- زر العودة -->
    <a href="../dash.php" class="btn btn-primary back-btn">
        <i class="fas fa-arrow-left"></i> العودة لرئيسية النظام
    </a>

    <!-- زر تسجيل المغادرة -->
    <?php if ($remaining == 0 && $booking['status'] == 'محجوزة'): ?>
        <form method="post" class="checkout-btn" onsubmit="return confirm('هل أنت متأكد من تسجيل مغادرة النزيل؟');">
            <button type="submit" name="checkout" class="btn btn-danger btn-lg shadow">
                <i class="fas fa-sign-out-alt"></i> تسجيل مغادرة النزيل وتحرير الغرفة
            </button>
        </form>
    <?php elseif ($booking['status'] == 'شاغرة'): ?>
        <div class="alert alert-info text-center mt-3">
            <i class="fas fa-info-circle"></i> تم تسجيل خروج النزيل بنجاح والغرفة متاحة الآن للحجوزات الجديدة
        </div>
    <?php endif; ?>

    <?php include '../../includes/footer.php'; ?>
</body>
</html>
<?php ob_end_flush(); ?>