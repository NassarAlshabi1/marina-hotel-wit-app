<?php
ob_start();
session_start();

// التحقق من وجود include files
if (!file_exists('../../includes/db.php')) {
    die('خطأ: ملف قاعدة البيانات غير موجود');
}

require '../../includes/db.php';
require_once '../../includes/functions.php';

// التحقق من صحة معرف الحجز
$booking_id = intval($_GET['id'] ?? 0);
if ($booking_id <= 0) {
    die('خطأ: رقم الحجز غير صالح');
}

// جلب بيانات الحجز مع التحقق من وجوده
$booking_query = "
    SELECT b.booking_id, b.guest_name, b.guest_phone, b.room_number,
           b.checkin_date, b.checkout_date, b.actual_checkout, r.price AS room_price,
           b.status,
           IFNULL((SELECT SUM(p.amount) FROM payment p WHERE p.booking_id = b.booking_id), 0) AS paid_amount
    FROM bookings b
    LEFT JOIN rooms r ON b.room_number = r.room_number
    WHERE b.booking_id = ? LIMIT 1
";

$stmt = $conn->prepare($booking_query);
if (!$stmt) {
    die('خطأ في إعداد الاستعلام: ' . $conn->error);
}

$stmt->bind_param('i', $booking_id);
$stmt->execute();
$booking_res = $stmt->get_result();

if ($booking_res->num_rows === 0) {
    die('خطأ: الحجز غير موجود');
}

$booking = $booking_res->fetch_assoc();

// حساب عدد الليالي والتكلفة الإجمالية
$checkin = new DateTime($booking['checkin_date']);
$checkout = $booking['actual_checkout'] ? new DateTime($booking['actual_checkout']) : new DateTime();
$nights = $checkout->diff($checkin)->days ?: 1;

$total_price = $booking['room_price'] * $nights;
$paid_amount = $booking['paid_amount'];
$remaining = max(0, $total_price - $paid_amount);

// معالجة تسجيل المغادرة
if (isset($_POST['checkout'])) {
    if ($remaining > 0) {
        $_SESSION['flash'] = [
            'type' => 'danger',
            'message' => 'لا يمكن تسجيل المغادرة قبل تسديد كافة المستحقات. المبلغ المتبقي: ' . number_format($remaining, 0) . ' ريال'
        ];
    } else {
        $conn->begin_transaction();
        try {
            // تحديث حالة الحجز
            $update_booking = $conn->prepare("UPDATE bookings SET status='شاغرة', actual_checkout=NOW() WHERE booking_id=?");
            $update_booking->bind_param('i', $booking_id);
            $update_booking->execute();

            // تحديث حالة الغرفة
            $update_room = $conn->prepare("UPDATE rooms SET status='شاغرة' WHERE room_number=?");
            $update_room->bind_param('s', $booking['room_number']);
            $update_room->execute();

            $conn->commit();

            $_SESSION['flash'] = [
                'type' => 'success',
                'message' => 'تم تسجيل مغادرة النزيل بنجاح وتم تحرير الغرفة.'
            ];
            
            header("Location: payment_fixed.php?id=$booking_id");
            exit();
        } catch (Exception $e) {
            $conn->rollback();
            $_SESSION['flash'] = [
                'type' => 'danger',
                'message' => 'خطأ أثناء تسجيل المغادرة: ' . $e->getMessage()
            ];
        }
    }
}

// معالجة إضافة دفعة جديدة
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['submit_payment'])) {
    $amount = floatval($_POST['amount'] ?? 0);
    $payment_date = $_POST['payment_date'] ?? date('Y-m-d H:i:s');
    $payment_method = $conn->real_escape_string($_POST['payment_method'] ?? 'نقدي');
    $notes = $conn->real_escape_string($_POST['notes'] ?? '');

    // التحقق من صحة المبلغ
    if ($amount <= 0) {
        $_SESSION['flash'] = [
            'type' => 'danger',
            'message' => 'المبلغ يجب أن يكون أكبر من صفر'
        ];
    } elseif ($amount > $remaining) {
        $_SESSION['flash'] = [
            'type' => 'danger',
            'message' => 'المبلغ يجب أن لا يتجاوز المتبقي: ' . number_format($remaining, 0) . ' ريال'
        ];
    } else {
        // إدراج الدفعة في قاعدة البيانات
        $insert_payment = $conn->prepare("INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes) VALUES (?, ?, ?, ?, ?)");
        $insert_payment->bind_param('idsss', $booking_id, $amount, $payment_date, $payment_method, $notes);

        if ($insert_payment->execute()) {
            $remaining_after = max(0, $remaining - $amount);
            
            // إرسال إشعار واتساب للعميل
            $whatsapp_message = sprintf(
                "عزيزي %s،\n\nتم استلام دفعة بقيمة %.2f ريال.\nرقم الحجز: %d\nالمبلغ المتبقي: %.2f ريال\n\nشكراً لك",
                $booking['guest_name'], 
                $amount, 
                $booking_id, 
                $remaining_after
            );
            
            $whatsapp_result = send_yemeni_whatsapp($booking['guest_phone'], $whatsapp_message);
            $whatsapp_status = '';
            
            if (is_array($whatsapp_result) && isset($whatsapp_result['status']) && $whatsapp_result['status'] === 'sent') {
                $whatsapp_status = ' وتم إرسال إشعار للعميل عبر الواتساب.';
            } else {
                $whatsapp_status = ' ولكن لم يتم إرسال إشعار للعميل.';
            }

            $_SESSION['flash'] = [
                'type' => 'success',
                'message' => 'تم تسجيل الدفعة بنجاح' . $whatsapp_status
            ];
            
            header("Location: payment_fixed.php?id=$booking_id");
            exit();
        } else {
            $_SESSION['flash'] = [
                'type' => 'danger',
                'message' => 'خطأ في إضافة الدفعة: ' . $conn->error
            ];
        }
    }
}

// جلب سجل الدفعات
$payments_query = "SELECT * FROM payment WHERE booking_id=? ORDER BY payment_date DESC";
$stmt_payments = $conn->prepare($payments_query);
$stmt_payments->bind_param('i', $booking_id);
$stmt_payments->execute();
$payments_result = $stmt_payments->get_result();

// تحديث البيانات بعد المعالجة
$stmt = $conn->prepare($booking_query);
$stmt->bind_param('i', $booking_id);
$stmt->execute();
$booking_res = $stmt->get_result();
$booking = $booking_res->fetch_assoc();

$checkin = new DateTime($booking['checkin_date']);
$checkout = $booking['actual_checkout'] ? new DateTime($booking['actual_checkout']) : new DateTime();
$nights = $checkout->diff($checkin)->days ?: 1;

$total_price = $booking['room_price'] * $nights;
$paid_amount = $booking['paid_amount'];
$remaining = max(0, $total_price - $paid_amount);
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إدارة الدفعات - حجز #<?= $booking_id ?></title>
    <link href="../../includes/css/bootstrap.min.css" rel="stylesheet">
    <link href="../../includes/css/all.min.css" rel="stylesheet">
    <link href="../../includes/css/tajawal-font.css" rel="stylesheet">
    <style>
        /* ضمان عمل الخطوط بدون انترنت */
        body {
            font-family: 'Tajawal', 'Cairo', 'Arial', sans-serif !important;
            direction: rtl;
            text-align: right;
            background-color: #f8f9fa;
            font-family: 'Cairo', sans-serif;
        }
        .card {
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            border: none;
            border-radius: 10px;
        }
        .card-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 10px 10px 0 0 !important;
        }
        .badge {
            font-size: 0.9em;
        }
        .table th {
            background-color: #f8f9fa;
            border-top: none;
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border: none;
        }
        .btn-success {
            background: linear-gradient(135deg, #56ab2f 0%, #a8e6cf 100%);
            border: none;
        }
        .btn-danger {
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a6f 100%);
            border: none;
        }
        .alert {
            border-radius: 10px;
        }
        .form-control, .form-select {
            border-radius: 8px;
        }
        .status-paid {
            background-color: #d4edda;
            color: #155724;
        }
        .status-pending {
            background-color: #fff3cd;
            color: #856404;
        }
        .status-checkout {
            background-color: #f8d7da;
            color: #721c24;
        }
    </style>
</head>
<body>

<!-- Toast Notifications -->
<?php if (isset($_SESSION['flash'])): ?>
<div class="toast-container position-fixed top-0 end-0 p-3" style="z-index: 9999;">
    <div id="flashToast" class="toast align-items-center text-bg-<?= $_SESSION['flash']['type'] ?> border-0" role="alert">
        <div class="d-flex">
            <div class="toast-body">
                <i class="fas fa-<?= $_SESSION['flash']['type'] === 'success' ? 'check-circle' : 'exclamation-triangle' ?>"></i>
                <?= htmlspecialchars($_SESSION['flash']['message']) ?>
            </div>
            <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
    </div>
</div>
<?php unset($_SESSION['flash']); endif; ?>

<div class="container-fluid py-4">
    <div class="row justify-content-center">
        <div class="col-lg-10">
            
            <!-- Page Header -->
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h1 class="h3 mb-0">
                    <i class="fas fa-money-check-alt text-primary me-2"></i>
                    إدارة الدفعات - حجز #<?= $booking_id ?>
                </h1>
                <a href="list.php" class="btn btn-outline-secondary">
                    <i class="fas fa-arrow-right me-2"></i>العودة للحجوزات
                </a>
            </div>

            <!-- Booking Information Card -->
            <div class="card mb-4">
                <div class="card-header">
                    <h5 class="card-title mb-0">
                        <i class="fas fa-info-circle me-2"></i>معلومات الحجز
                    </h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-6">
                            <p><strong>اسم النزيل:</strong> <?= htmlspecialchars($booking['guest_name']) ?></p>
                            <p><strong>رقم الهاتف:</strong> <?= htmlspecialchars($booking['guest_phone']) ?></p>
                            <p><strong>رقم الغرفة:</strong> <?= htmlspecialchars($booking['room_number']) ?></p>
                        </div>
                        <div class="col-md-6">
                            <p><strong>تاريخ الدخول:</strong> <?= date('Y-m-d H:i', strtotime($booking['checkin_date'])) ?></p>
                            <p><strong>عدد الليالي:</strong> <?= $nights ?></p>
                            <p><strong>الحالة:</strong> 
                                <span class="badge <?= $booking['status'] === 'شاغرة' ? 'bg-success' : 'bg-warning' ?>">
                                    <?= htmlspecialchars($booking['status']) ?>
                                </span>
                            </p>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Payment Summary Card -->
            <div class="card mb-4">
                <div class="card-header">
                    <h5 class="card-title mb-0">
                        <i class="fas fa-calculator me-2"></i>ملخص الدفعات
                    </h5>
                </div>
                <div class="card-body">
                    <div class="row text-center">
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <h6>إجمالي المبلغ</h6>
                                <h4 class="text-primary"><?= number_format($total_price, 0) ?> ريال</h4>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <h6>المبلغ المدفوع</h6>
                                <h4 class="text-success"><?= number_format($paid_amount, 0) ?> ريال</h4>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <h6>المبلغ المتبقي</h6>
                                <h4 class="text-danger"><?= number_format($remaining, 0) ?> ريال</h4>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <h6>نسبة الدفع</h6>
                                <h4 class="text-info"><?= $total_price > 0 ? round(($paid_amount / $total_price) * 100, 1) : 0 ?>%</h4>
                            </div>
                        </div>
                    </div>
                </div>
            </div>

            <div class="row">
                <!-- Add New Payment Form -->
                <div class="col-md-6">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="card-title mb-0">
                                <i class="fas fa-plus-circle me-2"></i>إضافة دفعة جديدة
                            </h5>
                        </div>
                        <div class="card-body">
                            <?php if ($remaining > 0): ?>
                            <form method="POST" action="">
                                <div class="mb-3">
                                    <label for="amount" class="form-label">المبلغ (ريال)</label>
                                    <input type="number" 
                                           class="form-control" 
                                           id="amount" 
                                           name="amount" 
                                           min="1" 
                                           max="<?= $remaining ?>" 
                                           step="0.01" 
                                           required>
                                    <div class="form-text">الحد الأقصى: <?= number_format($remaining, 0) ?> ريال</div>
                                </div>
                                
                                <div class="mb-3">
                                    <label for="payment_date" class="form-label">تاريخ الدفع</label>
                                    <input type="datetime-local" 
                                           class="form-control" 
                                           id="payment_date" 
                                           name="payment_date" 
                                           value="<?= date('Y-m-d\TH:i') ?>" 
                                           required>
                                </div>
                                
                                <div class="mb-3">
                                    <label for="payment_method" class="form-label">طريقة الدفع</label>
                                    <select class="form-select" id="payment_method" name="payment_method" required>
                                        <option value="نقدي">نقدي</option>
                                        <option value="بطاقة ائتمان">بطاقة ائتمان</option>
                                        <option value="تحويل بنكي">تحويل بنكي</option>
                                        <option value="شيك">شيك</option>
                                    </select>
                                </div>
                                
                                <div class="mb-3">
                                    <label for="notes" class="form-label">ملاحظات</label>
                                    <textarea class="form-control" 
                                              id="notes" 
                                              name="notes" 
                                              rows="3" 
                                              placeholder="أي ملاحظات إضافية..."></textarea>
                                </div>
                                
                                <button type="submit" name="submit_payment" class="btn btn-primary w-100">
                                    <i class="fas fa-save me-2"></i>تسجيل الدفعة
                                </button>
                            </form>
                            <?php else: ?>
                            <div class="alert alert-success text-center">
                                <i class="fas fa-check-circle fa-3x mb-3"></i>
                                <h5>تم تسديد كامل المبلغ</h5>
                                <p>تم استلام جميع الدفعات المطلوبة لهذا الحجز.</p>
                            </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>

                <!-- Payments History -->
                <div class="col-md-6">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="card-title mb-0">
                                <i class="fas fa-history me-2"></i>سجل الدفعات
                            </h5>
                        </div>
                        <div class="card-body">
                            <?php if ($payments_result->num_rows > 0): ?>
                            <div class="table-responsive">
                                <table class="table table-striped">
                                    <thead>
                                        <tr>
                                            <th>التاريخ</th>
                                            <th>المبلغ</th>
                                            <th>الطريقة</th>
                                            <th>الملاحظات</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php while ($payment = $payments_result->fetch_assoc()): ?>
                                        <tr>
                                            <td><?= date('Y-m-d H:i', strtotime($payment['payment_date'])) ?></td>
                                            <td class="text-success fw-bold"><?= number_format($payment['amount'], 0) ?> ريال</td>
                                            <td>
                                                <span class="badge bg-secondary"><?= htmlspecialchars($payment['payment_method']) ?></span>
                                            </td>
                                            <td><?= htmlspecialchars($payment['notes']) ?: '-' ?></td>
                                        </tr>
                                        <?php endwhile; ?>
                                    </tbody>
                                </table>
                            </div>
                            <?php else: ?>
                            <div class="alert alert-info text-center">
                                <i class="fas fa-info-circle fa-2x mb-3"></i>
                                <h6>لا توجد دفعات مسجلة</h6>
                                <p>لم يتم تسجيل أي دفعات لهذا الحجز بعد.</p>
                            </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Checkout Section -->
            <?php if ($booking['status'] !== 'شاغرة'): ?>
            <div class="card mt-4">
                <div class="card-header bg-danger text-white">
                    <h5 class="card-title mb-0">
                        <i class="fas fa-sign-out-alt me-2"></i>تسجيل المغادرة
                    </h5>
                </div>
                <div class="card-body">
                    <?php if ($remaining > 0): ?>
                    <div class="alert alert-warning">
                        <i class="fas fa-exclamation-triangle me-2"></i>
                        <strong>تنبيه:</strong> لا يمكن تسجيل المغادرة قبل تسديد كامل المبلغ. 
                        المبلغ المتبقي: <strong><?= number_format($remaining, 0) ?> ريال</strong>
                    </div>
                    <?php else: ?>
                    <div class="alert alert-success">
                        <i class="fas fa-check-circle me-2"></i>
                        <strong>جاهز للمغادرة:</strong> تم تسديد كامل المبلغ المطلوب.
                    </div>
                    <form method="POST" action="" onsubmit="return confirm('هل أنت متأكد من تسجيل مغادرة النزيل؟')">
                        <button type="submit" name="checkout" class="btn btn-success btn-lg">
                            <i class="fas fa-sign-out-alt me-2"></i>تسجيل المغادرة
                        </button>
                    </form>
                    <?php endif; ?>
                </div>
            </div>
            <?php else: ?>
            <div class="card mt-4">
                <div class="card-body text-center">
                    <div class="alert alert-info">
                        <i class="fas fa-info-circle fa-3x mb-3"></i>
                        <h5>تم تسجيل المغادرة</h5>
                        <p>تم تسجيل مغادرة النزيل وتحرير الغرفة.</p>
                    </div>
                </div>
            </div>
            <?php endif; ?>

        </div>
    </div>
</div>

<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function() {
    // إظهار التنبيهات
    const toastElement = document.getElementById('flashToast');
    if (toastElement) {
        const toast = new bootstrap.Toast(toastElement, {
            delay: 5000
        });
        toast.show();
    }
    
    // تحديث الصفحة كل 30 ثانية لإظهار التحديثات
    setInterval(function() {
        // يمكن إضافة AJAX هنا لتحديث البيانات دون إعادة تحميل الصفحة
    }, 30000);
});
</script>

</body>
</html>
<?php ob_end_flush(); ?>