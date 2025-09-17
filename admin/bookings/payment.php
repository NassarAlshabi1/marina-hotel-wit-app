<?php
ob_start();
session_start();
require '../../includes/db.php';
require_once '../../includes/functions.php';

// ❗ تحقق من صلاحية المستخدم حسب الحاجة
// if (!isset($_SESSION['user_id'])) {
//     header('Location: ../../login.php');
//     exit();
// }

//========================================================
// جلب بيانات الحجز
//========================================================
$booking_id = intval($_GET['id'] ?? 0);
if ($booking_id <= 0) die('رقم الحجز غير صالح');

$booking_query = "
    SELECT b.booking_id, b.guest_name, b.guest_phone, b.room_number,
           b.checkin_date, b.checkout_date, r.price AS room_price,
           b.status,
           IFNULL((SELECT SUM(p.amount) FROM payment p WHERE p.booking_id = b.booking_id), 0) AS paid_amount
    FROM bookings b
    LEFT JOIN rooms r ON b.room_number = r.room_number
    WHERE b.booking_id = ? LIMIT 1
";
$stmt = $conn->prepare($booking_query);
$stmt->bind_param('i', $booking_id);
$stmt->execute();
$booking_res = $stmt->get_result();
if ($booking_res->num_rows === 0) die('الحجز غير موجود');
$booking = $booking_res->fetch_assoc();

$checkin  = new DateTime($booking['checkin_date']);
$checkout = new DateTime($booking['checkout_date']);
$nights   = $checkout->diff($checkin)->days ?: 1;

$total_price = $booking['room_price'] * $nights;
$paid_amount  = $booking['paid_amount'];
$remaining    = max(0, $total_price - $paid_amount);

//========================================================
// معالجة تسجيل المغادرة
//========================================================
if (isset($_POST['checkout'])) {
    if ($remaining == 0) {
        $conn->begin_transaction();
        try {
            $s1 = $conn->prepare("UPDATE bookings SET status='شاغرة', actual_checkout=NOW() WHERE booking_id=?");
            $s1->bind_param('i', $booking_id); $s1->execute();

            $s2 = $conn->prepare("UPDATE rooms SET status='شاغرة' WHERE room_number=?");
            $s2->bind_param('s', $booking['room_number']); $s2->execute();

            $conn->commit();

            $_SESSION['flash'] = [
                'type'    => 'success',
                'message' => 'تم تسجيل مغادرة النزيل بنجاح وتم تحرير الغرفة.'
            ];
            header("Location: payment.php?id=$booking_id");
            exit();
        } catch (Exception $e) {
            $conn->rollback();
            $_SESSION['flash'] = [
                'type'    => 'danger',
                'message' => 'خطأ أثناء تسجيل المغادرة: ' . $e->getMessage()
            ];
            header("Location: payment.php?id=$booking_id");
            exit();
        }
    } else {
        $_SESSION['flash'] = [
            'type'    => 'danger',
            'message' => 'لا يمكن تسجيل المغادرة قبل تسديد كافة المستحقات.'
        ];
        header("Location: payment.php?id=$booking_id");
        exit();
    }
}

//========================================================
// سجل الدفعات
//========================================================
$payments_query = "SELECT * FROM payment WHERE booking_id=? ORDER BY payment_date DESC";
$stmt_pay = $conn->prepare($payments_query);
$stmt_pay->bind_param('i', $booking_id);
$stmt_pay->execute();
$payments_res = $stmt_pay->get_result();

//========================================================
// إضافة دفعة جديدة
//========================================================
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['submit_payment'])) {
    $amount = floatval($_POST['amount']);
    $payment_date = $_POST['payment_date'] ?: date('Y-m-d H:i:s');
    $payment_method = $conn->real_escape_string($_POST['payment_method'] ?: 'نقدي');
    $notes = $conn->real_escape_string($_POST['notes'] ?: '');

    if ($amount <= 0 || $amount > $remaining) {
        $_SESSION['flash'] = [
            'type'    => 'danger',
            'message' => 'المبلغ يجب أن يكون بين 1 و ' . number_format($remaining, 0) . ' ريال'
        ];
        header("Location: payment.php?id=$booking_id");
        exit();
    }

    $st = $conn->prepare("INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes) VALUES (?, ?, ?, ?, ?)");
    $st->bind_param('idsss', $booking_id, $amount, $payment_date, $payment_method, $notes);

    if ($st->execute()) {
        $remaining_after = max(0, $remaining - $amount);
        $msg = sprintf(
            "عزيزي %s، تم استلام دفعة بقيمة %.2f ريال.\nرقم الحجز: %d\nالمتبقي: %.2f ريال",
            $booking['guest_name'], $amount, $booking_id, $remaining_after
        );
        $wa = send_yemeni_whatsapp($booking['guest_phone'], $msg);
        $wa_status = (is_array($wa) && $wa['status'] === 'sent')
            ? 'وتم إرسال إشعار للعميل عبر الواتساب.'
            : 'ولكن لم يتم إرسال إشعار للعميل.';

        $_SESSION['flash'] = [
            'type'    => 'success',
            'message' => "تم تسجيل الدفعة بنجاح، $wa_status"
        ];
        header("Location: payment.php?id=$booking_id");
        exit();
    } else {
        $_SESSION['flash'] = [
            'type'    => 'danger',
            'message' => 'خطأ في إضافة الدفعة: ' . $conn->error
        ];
        header("Location: payment.php?id=$booking_id");
        exit();
    }
}

include '../../includes/header.php';
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>إدارة الدفعات - حجز #<?= $booking_id ?></title>
  <link href="../../includes/css/bootstrap.min.css" rel="stylesheet">
  <link href="../../includes/css/all.min.css" rel="stylesheet">
  <link href="../../includes/css/tajawal-font.css" rel="stylesheet">
  <style>
    /* ضمان عمل الخطوط بدون انترنت */
    body {
        background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
        font-family: 'Tajawal', 'Cairo', 'Arial', sans-serif !important;
        direction: rtl;
        text-align: right;
        min-height: 100vh;
    }
    
    /* تحسين Font Awesome للعمل محلياً */
    .fas, .far, .fab, .fa {
        font-family: "Font Awesome 6 Free", "Font Awesome 6 Brands" !important;
        font-weight: 900;
    }
    
    .main-container {
        padding: 15px 0;
    }
    .logo-header {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        padding: 15px;
        border-radius: 15px;
        margin-bottom: 20px;
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        backdrop-filter: blur(10px);
        border: 1px solid rgba(255, 255, 255, 0.18);
    }
    .hotel-logo {
        width: 60px;
        height: 60px;
        background: rgba(255, 255, 255, 0.2);
        border-radius: 50%;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 24px;
        margin-left: 15px;
        border: 2px solid rgba(255, 255, 255, 0.3);
        animation: pulse 2s infinite;
        transition: all 0.3s ease;
    }
    .hotel-logo:hover {
        transform: scale(1.1);
        box-shadow: 0 0 20px rgba(255, 255, 255, 0.4);
    }
    @keyframes pulse {
        0% { box-shadow: 0 0 0 0 rgba(255, 255, 255, 0.4); }
        70% { box-shadow: 0 0 0 10px rgba(255, 255, 255, 0); }
        100% { box-shadow: 0 0 0 0 rgba(255, 255, 255, 0); }
    }
    .card {
        box-shadow: 0 8px 32px rgba(0, 0, 0, 0.1);
        border: none;
        border-radius: 15px;
        backdrop-filter: blur(10px);
        background: rgba(255, 255, 255, 0.95);
        margin-bottom: 15px;
    }
    .card-header {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border-radius: 15px 15px 0 0 !important;
        padding: 12px 20px;
        border: none;
    }
    .card-body {
        padding: 15px 20px;
    }
    .summary-card {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        color: white;
        border-radius: 15px;
        padding: 20px;
        margin-bottom: 20px;
        box-shadow: 0 8px 32px rgba(102, 126, 234, 0.3);
    }
    .summary-item {
        background: rgba(255, 255, 255, 0.15);
        padding: 15px;
        border-radius: 12px;
        text-align: center;
        backdrop-filter: blur(10px);
        border: 1px solid rgba(255, 255, 255, 0.2);
        margin-bottom: 10px;
    }
    .summary-item h6 {
        margin-bottom: 8px;
        font-size: 0.9em;
        opacity: 0.9;
    }
    .summary-item h4 {
        margin-bottom: 0;
        font-weight: bold;
        text-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
    }
    .badge {
        font-size: 0.85em;
        padding: 6px 12px;
        border-radius: 20px;
    }
    .table th {
        background-color: #f8f9fa;
        border-top: none;
        padding: 10px;
        font-size: 0.9em;
    }
    .table td {
        padding: 10px;
        font-size: 0.9em;
    }
    .btn-primary {
        background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        border: none;
        border-radius: 25px;
        padding: 10px 20px;
        font-weight: 600;
        box-shadow: 0 4px 15px rgba(102, 126, 234, 0.4);
    }
    .btn-success {
        background: linear-gradient(135deg, #56ab2f 0%, #a8e6cf 100%);
        border: none;
        border-radius: 25px;
        padding: 10px 20px;
        font-weight: 600;
        box-shadow: 0 4px 15px rgba(86, 171, 47, 0.4);
    }
    .btn-danger {
        background: linear-gradient(135deg, #ff6b6b 0%, #ee5a6f 100%);
        border: none;
        border-radius: 25px;
        padding: 10px 20px;
        font-weight: 600;
        box-shadow: 0 4px 15px rgba(255, 107, 107, 0.4);
    }
    .btn-outline-secondary {
        border-radius: 25px;
        padding: 8px 20px;
        border: 2px solid #6c757d;
        color: #6c757d;
        font-weight: 600;
    }
    .alert {
        border-radius: 12px;
        border: none;
        padding: 15px;
        margin-bottom: 15px;
    }
    .form-control, .form-select {
        border-radius: 10px;
        padding: 10px 15px;
        border: 2px solid #e3e6f0;
    }
    .form-control:focus, .form-select:focus {
        border-color: #667eea;
        box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
    }
    .toast-container {
        z-index: 9999;
    }
    .compact-info {
        background: rgba(255, 255, 255, 0.1);
        padding: 12px;
        border-radius: 10px;
        margin-bottom: 10px;
    }
    .compact-info p {
        margin-bottom: 5px;
        font-size: 0.9em;
    }
    .page-title {
        font-size: 1.5em;
        font-weight: bold;
        text-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
        animation: fadeInDown 1s ease-out;
    }
    @keyframes fadeInDown {
        from {
            opacity: 0;
            transform: translateY(-20px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
    .card {
        animation: fadeInUp 0.6s ease-out;
    }
    @keyframes fadeInUp {
        from {
            opacity: 0;
            transform: translateY(20px);
        }
        to {
            opacity: 1;
            transform: translateY(0);
        }
    }
    .btn {
        transition: all 0.3s ease;
    }
    .btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
    }
    .summary-item {
        transition: all 0.3s ease;
    }
    .summary-item:hover {
        transform: translateY(-5px);
        box-shadow: 0 10px 25px rgba(0, 0, 0, 0.1);
    }
  </style>
</head>
<body>

<!-- Toast Notification -->
<?php if (isset($_SESSION['flash'])): ?>
<div class="toast-container position-fixed top-0 end-0 p-3">
  <div id="flashToast" class="toast align-items-center text-bg-<?= $_SESSION['flash']['type'] ?> border-0" role="alert" aria-live="assertive" aria-atomic="true">
    <div class="d-flex">
      <div class="toast-body"><?= htmlspecialchars($_SESSION['flash']['message']) ?></div>
      <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
    </div>
  </div>
</div>
<?php unset($_SESSION['flash']); endif; ?>

<div class="container-fluid main-container">
    <div class="row justify-content-center">
        <div class="col-lg-10">
            
            <!-- Logo and Header -->
            <div class="logo-header">
                <div class="d-flex align-items-center justify-content-between">
                    <div class="d-flex align-items-center">
                        <div class="hotel-logo">
                            <i class="fas fa-hotel"></i>
                        </div>
                        <div>
                            <h1 class="page-title mb-1">مارينا هوتل</h1>
                            <p class="mb-0 opacity-75">
                                <i class="fas fa-money-check-alt me-2"></i>
                                إدارة الدفعات - حجز #<?= $booking_id ?>
                            </p>
                        </div>
                    </div>
                    <a href="list.php" class="btn btn-outline-light">
                        <i class="fas fa-arrow-right me-2"></i>العودة
                    </a>
                </div>
            </div>

            <!-- Payment Summary Card - في الأعلى -->
            <div class="summary-card">
                <div class="d-flex align-items-center justify-content-between mb-3">
                    <h5 class="mb-0">
                        <i class="fas fa-calculator me-2"></i>ملخص الدفعات
                    </h5>
                    <div class="d-flex align-items-center">
                        <span class="badge <?= $booking['status'] === 'شاغرة' ? 'bg-success' : 'bg-warning' ?> me-2">
                            <?= htmlspecialchars($booking['status']) ?>
                        </span>
                        <span class="opacity-75">الغرفة <?= htmlspecialchars($booking['room_number']) ?></span>
                    </div>
                </div>
                <div class="row">
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>إجمالي المبلغ</h6>
                            <h4><?= number_format($total_price, 0) ?> ريال</h4>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>المبلغ المدفوع</h6>
                            <h4 class="text-success"><?= number_format($paid_amount, 0) ?> ريال</h4>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>المبلغ المتبقي</h6>
                            <h4 class="text-warning"><?= number_format($remaining, 0) ?> ريال</h4>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>نسبة الدفع</h6>
                            <h4 class="text-info"><?= $total_price > 0 ? round(($paid_amount / $total_price) * 100, 1) : 0 ?>%</h4>
                        </div>
                    </div>
                </div>
                <!-- معلومات الحجز المختصرة -->
                <div class="row mt-3">
                    <div class="col-md-6">
                        <div class="compact-info">
                            <p><strong>النزيل:</strong> <?= htmlspecialchars($booking['guest_name']) ?></p>
                            <p><strong>الهاتف:</strong> <?= htmlspecialchars($booking['guest_phone']) ?></p>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="compact-info">
                            <p><strong>تاريخ الدخول:</strong> <?= date('Y-m-d', strtotime($booking['checkin_date'])) ?></p>
                            <p><strong>عدد الليالي:</strong> <?= $nights ?> ليلة</p>
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
                                <div class="row">
                                    <div class="col-md-6">
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
                                    </div>
                                    <div class="col-md-6">
                                        <div class="mb-3">
                                            <label for="payment_method" class="form-label">طريقة الدفع</label>
                                            <select class="form-select" id="payment_method" name="payment_method" required>
                                                <option value="نقدي">💵 نقدي</option>
                                                <option value="بطاقة ائتمان">💳 بطاقة ائتمان</option>
                                                <option value="تحويل بنكي">🏦 تحويل بنكي</option>
                                                <option value="شيك">📝 شيك</option>
                                            </select>
                                        </div>
                                    </div>
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
                                    <label for="notes" class="form-label">ملاحظات</label>
                                    <textarea class="form-control" 
                                              id="notes" 
                                              name="notes" 
                                              rows="2" 
                                              placeholder="أي ملاحظات إضافية..."></textarea>
                                </div>
                                
                                <button type="submit" name="submit_payment" class="btn btn-primary w-100">
                                    <i class="fas fa-save me-2"></i>تسجيل الدفعة
                                </button>
                            </form>
                            <?php else: ?>
                            <div class="alert alert-success text-center">
                                <i class="fas fa-check-circle fa-2x mb-2"></i>
                                <h6>تم تسديد كامل المبلغ</h6>
                                <p class="mb-0">تم استلام جميع الدفعات المطلوبة لهذا الحجز.</p>
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
                            <?php if ($payments_res->num_rows > 0): ?>
                            <div class="table-responsive">
                                <table class="table table-striped table-sm">
                                    <thead>
                                        <tr>
                                            <th>التاريخ</th>
                                            <th>المبلغ</th>
                                            <th>الطريقة</th>
                                            <th>الملاحظات</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php 
                                        $payments_res->data_seek(0); // إعادة تعيين مؤشر النتيجة
                                        while ($payment = $payments_res->fetch_assoc()): 
                                        ?>
                                        <tr>
                                            <td><?= date('m/d H:i', strtotime($payment['payment_date'])) ?></td>
                                            <td class="text-success fw-bold"><?= number_format($payment['amount'], 0) ?></td>
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
                                <i class="fas fa-info-circle fa-2x mb-2"></i>
                                <h6>لا توجد دفعات مسجلة</h6>
                                <p class="mb-0">لم يتم تسجيل أي دفعات لهذا الحجز بعد.</p>
                            </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>

            <!-- Checkout Section -->
            <?php if ($booking['status'] !== 'شاغرة'): ?>
            <div class="card mt-3">
                <div class="card-header" style="background: linear-gradient(135deg, #ff6b6b 0%, #ee5a6f 100%);">
                    <h5 class="card-title mb-0">
                        <i class="fas fa-sign-out-alt me-2"></i>تسجيل المغادرة
                    </h5>
                </div>
                <div class="card-body">
                    <div class="row align-items-center">
                        <div class="col-md-8">
                            <?php if ($remaining > 0): ?>
                            <div class="alert alert-warning mb-0">
                                <i class="fas fa-exclamation-triangle me-2"></i>
                                <strong>تنبيه:</strong> لا يمكن تسجيل المغادرة قبل تسديد كامل المبلغ. 
                                المبلغ المتبقي: <strong><?= number_format($remaining, 0) ?> ريال</strong>
                            </div>
                            <?php else: ?>
                            <div class="alert alert-success mb-0">
                                <i class="fas fa-check-circle me-2"></i>
                                <strong>جاهز للمغادرة:</strong> تم تسديد كامل المبلغ المطلوب.
                            </div>
                            <?php endif; ?>
                        </div>
                        <div class="col-md-4 text-center">
                            <?php if ($remaining == 0): ?>
                            <form method="POST" action="" onsubmit="return confirm('هل أنت متأكد من تسجيل مغادرة النزيل؟')">
                                <button type="submit" name="checkout" class="btn btn-success btn-lg">
                                    <i class="fas fa-sign-out-alt me-2"></i>تسجيل المغادرة
                                </button>
                            </form>
                            <?php else: ?>
                            <button type="button" class="btn btn-secondary btn-lg" disabled>
                                <i class="fas fa-lock me-2"></i>غير متاح
                            </button>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>
            <?php else: ?>
            <div class="card mt-3">
                <div class="card-body text-center">
                    <div class="alert alert-info mb-0">
                        <i class="fas fa-info-circle fa-2x mb-2"></i>
                        <h6>تم تسجيل المغادرة</h6>
                        <p class="mb-0">تم تسجيل مغادرة النزيل وتحرير الغرفة.</p>
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
    
    // تحسين تجربة المستخدم في النماذج
    const amountInput = document.getElementById('amount');
    if (amountInput) {
        // إضافة تأثير بصري للحقل
        amountInput.addEventListener('focus', function() {
            this.parentElement.style.transform = 'scale(1.02)';
        });
        
        amountInput.addEventListener('blur', function() {
            this.parentElement.style.transform = 'scale(1)';
        });
        
        amountInput.addEventListener('input', function() {
            const value = parseFloat(this.value);
            const max = parseFloat(this.getAttribute('max'));
            
            if (value > max) {
                this.setCustomValidity('المبلغ لا يمكن أن يتجاوز ' + max.toLocaleString() + ' ريال');
                this.classList.add('is-invalid');
            } else if (value <= 0) {
                this.setCustomValidity('المبلغ يجب أن يكون أكبر من صفر');
                this.classList.add('is-invalid');
            } else {
                this.setCustomValidity('');
                this.classList.remove('is-invalid');
                this.classList.add('is-valid');
            }
        });
    }
    
    // تحديد التاريخ الافتراضي
    const dateInput = document.getElementById('payment_date');
    if (dateInput && !dateInput.value) {
        const now = new Date();
        const localDateTime = now.toISOString().slice(0, 16);
        dateInput.value = localDateTime;
    }
    
    // تأكيد قبل تسجيل المغادرة
    const checkoutForms = document.querySelectorAll('form[onsubmit*="checkout"]');
    checkoutForms.forEach(form => {
        form.addEventListener('submit', function(e) {
            if (!confirm('هل أنت متأكد من تسجيل مغادرة النزيل؟ هذا الإجراء لا يمكن التراجع عنه.')) {
                e.preventDefault();
            }
        });
    });
    
    // تأثير الحركة للأزرار
    const buttons = document.querySelectorAll('.btn');
    buttons.forEach(button => {
        button.addEventListener('mouseenter', function() {
            this.style.transform = 'translateY(-2px)';
        });
        
        button.addEventListener('mouseleave', function() {
            this.style.transform = 'translateY(0)';
        });
    });
    
    // تأثير النقر على العناصر التفاعلية
    const summaryItems = document.querySelectorAll('.summary-item');
    summaryItems.forEach(item => {
        item.addEventListener('click', function() {
            this.style.transform = 'scale(0.95)';
            setTimeout(() => {
                this.style.transform = 'scale(1)';
            }, 150);
        });
    });
    
    // تحديث الوقت كل ثانية في حقل التاريخ
    setInterval(function() {
        const dateInput = document.getElementById('payment_date');
        if (dateInput && dateInput === document.activeElement) {
            // عدم تحديث الوقت إذا كان المستخدم يحرر الحقل
            return;
        }
        if (dateInput) {
            const now = new Date();
            const localDateTime = now.toISOString().slice(0, 16);
            if (!dateInput.value || Math.abs(new Date(dateInput.value) - now) > 300000) { // 5 دقائق
                dateInput.value = localDateTime;
            }
        }
    }, 1000);
});
</script>
</body>
</html>
<?php ob_end_flush(); ?>
