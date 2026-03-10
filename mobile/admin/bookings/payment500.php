<?php
ob_start();
session_start();
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
            $update_booking = $conn->prepare("UPDATE bookings SET status='شاغرة', actual_checkout=NOW() WHERE booking_id=?");
            $update_booking->bind_param('i', $booking_id);
            $update_booking->execute();

            $update_room = $conn->prepare("UPDATE rooms SET status='شاغرة' WHERE room_number=?");
            $update_room->bind_param('s', $booking['room_number']);
            $update_room->execute();

            $conn->commit();

            $_SESSION['flash'] = [
                'type' => 'success',
                'message' => 'تم تسجيل مغادرة النزيل بنجاح وتم تحرير الغرفة.'
            ];
            
            header("Location: payment_premium.php?id=$booking_id");
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
        $insert_payment = $conn->prepare("INSERT INTO payment (booking_id, amount, payment_date, payment_method, notes) VALUES (?, ?, ?, ?, ?)");
        $insert_payment->bind_param('idsss', $booking_id, $amount, $payment_date, $payment_method, $notes);

        if ($insert_payment->execute()) {
            $remaining_after = max(0, $remaining - $amount);
            
            $whatsapp_message = sprintf(
                "🏨 مارينا هوتل\n\nعزيزي %s،\n\n✅ تم استلام دفعة بقيمة %.2f ريال\n📝 رقم الحجز: %d\n💰 المبلغ المتبقي: %.2f ريال\n\nشكراً لك 🙏",
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
            
            header("Location: payment_premium.php?id=$booking_id");
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
    <title>💰 إدارة الدفعات - مارينا هوتل</title>
    <link href="../../includes/css/bootstrap.min.css" rel="stylesheet">
    <link href="../../includes/css/fontawesome.min.css" rel="stylesheet">
    <link href="../../includes/css/cairo-font.css" rel="stylesheet">
    <link href="../../includes/css/custom.css" rel="stylesheet">
    <style>
        * {
            font-family: 'Cairo', sans-serif;
        }
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 10px 0;
        }
        .main-logo {
            background: linear-gradient(135deg, #ff6b6b 0%, #ee5a6f 100%);
            color: white;
            padding: 20px;
            border-radius: 20px;
            margin-bottom: 20px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.1);
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.18);
        }
        .hotel-logo {
            width: 80px;
            height: 80px;
            background: linear-gradient(135deg, #ffd700 0%, #ffed4e 100%);
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 32px;
            margin-left: 20px;
            border: 3px solid rgba(255, 255, 255, 0.3);
            color: #333;
            animation: logoFloat 3s ease-in-out infinite;
            box-shadow: 0 10px 30px rgba(255, 215, 0, 0.4);
        }
        @keyframes logoFloat {
            0%, 100% { transform: translateY(0px); }
            50% { transform: translateY(-10px); }
        }
        .hotel-name {
            font-size: 2.2em;
            font-weight: 700;
            text-shadow: 0 4px 8px rgba(0, 0, 0, 0.3);
            margin-bottom: 5px;
        }
        .hotel-subtitle {
            font-size: 1.1em;
            opacity: 0.9;
            font-weight: 400;
        }
        .summary-card {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 20px;
            padding: 25px;
            margin-bottom: 20px;
            box-shadow: 0 15px 35px rgba(102, 126, 234, 0.3);
            border: 1px solid rgba(255, 255, 255, 0.1);
        }
        .summary-item {
            background: rgba(255, 255, 255, 0.15);
            padding: 20px;
            border-radius: 15px;
            text-align: center;
            backdrop-filter: blur(10px);
            border: 1px solid rgba(255, 255, 255, 0.2);
            margin-bottom: 15px;
            transition: all 0.3s ease;
            cursor: pointer;
        }
        .summary-item:hover {
            transform: translateY(-5px);
            box-shadow: 0 15px 30px rgba(0, 0, 0, 0.2);
        }
        .summary-item h6 {
            font-size: 0.9em;
            opacity: 0.9;
            margin-bottom: 10px;
        }
        .summary-item h3 {
            font-weight: 700;
            margin-bottom: 0;
            text-shadow: 0 2px 4px rgba(0, 0, 0, 0.2);
        }
        .card {
            border: none;
            border-radius: 20px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.1);
            backdrop-filter: blur(10px);
            background: rgba(255, 255, 255, 0.95);
            margin-bottom: 20px;
            overflow: hidden;
        }
        .card-header {
            background: linear-gradient(135deg, #36d1dc 0%, #5b86e5 100%);
            color: white;
            padding: 15px 25px;
            border: none;
            font-weight: 600;
        }
        .card-body {
            padding: 25px;
        }
        .form-control, .form-select {
            border-radius: 12px;
            padding: 12px 16px;
            border: 2px solid #e3e6f0;
            font-size: 0.95em;
            transition: all 0.3s ease;
        }
        .form-control:focus, .form-select:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
            transform: scale(1.02);
        }
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            border: none;
            border-radius: 25px;
            padding: 12px 30px;
            font-weight: 600;
            font-size: 1.1em;
            box-shadow: 0 8px 25px rgba(102, 126, 234, 0.4);
            transition: all 0.3s ease;
        }
        .btn-primary:hover {
            transform: translateY(-3px);
            box-shadow: 0 12px 35px rgba(102, 126, 234, 0.6);
        }
        .btn-success {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            border: none;
            border-radius: 25px;
            padding: 12px 30px;
            font-weight: 600;
            box-shadow: 0 8px 25px rgba(40, 167, 69, 0.4);
        }
        .btn-outline-light {
            border: 2px solid rgba(255, 255, 255, 0.5);
            color: white;
            border-radius: 25px;
            padding: 8px 20px;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        .btn-outline-light:hover {
            background: rgba(255, 255, 255, 0.2);
            border-color: white;
            color: white;
        }
        .table {
            border-radius: 15px;
            overflow: hidden;
        }
        .table th {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            border: none;
            padding: 15px;
            font-weight: 600;
            color: #495057;
        }
        .table td {
            padding: 12px 15px;
            border: none;
            border-bottom: 1px solid #dee2e6;
        }
        .badge {
            font-size: 0.85em;
            padding: 8px 15px;
            border-radius: 20px;
            font-weight: 600;
        }
        .alert {
            border: none;
            border-radius: 15px;
            padding: 20px;
            font-weight: 500;
        }
        .compact-info {
            background: rgba(255, 255, 255, 0.1);
            padding: 15px;
            border-radius: 12px;
            margin-bottom: 10px;
        }
        .compact-info p {
            margin-bottom: 5px;
            font-size: 0.95em;
        }
        .payment-emoji {
            font-size: 1.2em;
            margin-left: 8px;
        }
        .toast-container {
            z-index: 9999;
        }
        .progress-ring {
            display: inline-block;
            width: 60px;
            height: 60px;
            margin-left: 10px;
        }
        .progress-ring circle {
            fill: none;
            stroke: rgba(255, 255, 255, 0.3);
            stroke-width: 6;
            stroke-linecap: round;
            transform: rotate(-90deg);
            transform-origin: 50% 50%;
        }
        .progress-ring .progress {
            stroke: #ffd700;
            stroke-dasharray: 157;
            stroke-dashoffset: 157;
            animation: progress 2s ease-in-out forwards;
        }
        @keyframes progress {
            to {
                stroke-dashoffset: calc(157 - (157 * var(--progress)) / 100);
            }
        }
        .floating-elements {
            position: fixed;
            width: 100%;
            height: 100%;
            pointer-events: none;
            z-index: -1;
        }
        .floating-element {
            position: absolute;
            opacity: 0.1;
            animation: float 6s ease-in-out infinite;
        }
        @keyframes float {
            0%, 100% { transform: translateY(0px) rotate(0deg); }
            50% { transform: translateY(-20px) rotate(180deg); }
        }
    </style>
</head>
<body>

<!-- عناصر مُعلقة للتأثير البصري -->
<div class="floating-elements">
    <i class="fas fa-coins floating-element" style="top: 10%; left: 10%; font-size: 2em; animation-delay: 0s;"></i>
    <i class="fas fa-hotel floating-element" style="top: 20%; right: 15%; font-size: 1.5em; animation-delay: 1s;"></i>
    <i class="fas fa-money-bill-wave floating-element" style="bottom: 30%; left: 20%; font-size: 1.8em; animation-delay: 2s;"></i>
    <i class="fas fa-credit-card floating-element" style="bottom: 20%; right: 10%; font-size: 1.3em; animation-delay: 3s;"></i>
</div>

<!-- Toast Notifications -->
<?php if (isset($_SESSION['flash'])): ?>
<div class="toast-container position-fixed top-0 end-0 p-3" style="z-index: 9999;">
    <div id="flashToast" class="toast align-items-center text-bg-<?= $_SESSION['flash']['type'] ?> border-0" role="alert">
        <div class="d-flex">
            <div class="toast-body">
                <i class="fas fa-<?= $_SESSION['flash']['type'] === 'success' ? 'check-circle' : 'exclamation-triangle' ?> me-2"></i>
                <?= htmlspecialchars($_SESSION['flash']['message']) ?>
            </div>
            <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
        </div>
    </div>
</div>
<?php unset($_SESSION['flash']); endif; ?>

<div class="container-fluid">
    <div class="row justify-content-center">
        <div class="col-lg-10">
            
            <!-- الشعار والعنوان الرئيسي -->
            <div class="main-logo">
                <div class="d-flex align-items-center justify-content-between">
                    <div class="d-flex align-items-center">
                        <div class="hotel-logo">
                            <i class="fas fa-hotel"></i>
                        </div>
                        <div>
                            <h1 class="hotel-name mb-0">مارينا هوتل</h1>
                            <p class="hotel-subtitle mb-0">
                                <i class="fas fa-money-check-alt me-2"></i>
                                إدارة الدفعات - حجز #<?= $booking_id ?>
                            </p>
                        </div>
                    </div>
                    <div class="d-flex align-items-center">
                        <svg class="progress-ring" style="--progress: <?= $total_price > 0 ? round(($paid_amount / $total_price) * 100) : 0 ?>">
                            <circle cx="30" cy="30" r="25" class="progress"></circle>
                        </svg>
                        <a href="list.php" class="btn btn-outline-light ms-3">
                            <i class="fas fa-arrow-right me-2"></i>العودة
                        </a>
                    </div>
                </div>
            </div>

            <!-- ملخص الدفعات المحسن -->
            <div class="summary-card">
                <div class="d-flex align-items-center justify-content-between mb-4">
                    <h4 class="mb-0">
                        <i class="fas fa-chart-pie me-2"></i>الملخص المالي
                    </h4>
                    <div class="d-flex align-items-center">
                        <span class="badge <?= $booking['status'] === 'شاغرة' ? 'bg-success' : 'bg-warning' ?> me-3">
                            <?= htmlspecialchars($booking['status']) ?>
                        </span>
                        <span class="opacity-75">🏨 الغرفة <?= htmlspecialchars($booking['room_number']) ?></span>
                    </div>
                </div>
                
                <div class="row">
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>💰 إجمالي المبلغ</h6>
                            <h3><?= number_format($total_price, 0) ?> ريال</h3>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>✅ المبلغ المدفوع</h6>
                            <h3 class="text-success"><?= number_format($paid_amount, 0) ?> ريال</h3>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>⏳ المبلغ المتبقي</h6>
                            <h3 class="text-warning"><?= number_format($remaining, 0) ?> ريال</h3>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="summary-item">
                            <h6>📊 نسبة الدفع</h6>
                            <h3 class="text-info"><?= $total_price > 0 ? round(($paid_amount / $total_price) * 100, 1) : 0 ?>%</h3>
                        </div>
                    </div>
                </div>
                
                <div class="row mt-3">
                    <div class="col-md-6">
                        <div class="compact-info">
                            <p><strong>👤 النزيل:</strong> <?= htmlspecialchars($booking['guest_name']) ?></p>
                            <p><strong>📱 الهاتف:</strong> <?= htmlspecialchars($booking['guest_phone']) ?></p>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="compact-info">
                            <p><strong>📅 تاريخ الدخول:</strong> <?= date('Y-m-d', strtotime($booking['checkin_date'])) ?></p>
                            <p><strong>🌙 عدد الليالي:</strong> <?= $nights ?> ليلة</p>
                        </div>
                    </div>
                </div>
            </div>

            <div class="row">
                <!-- إضافة دفعة جديدة -->
                <div class="col-lg-6">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">
                                <i class="fas fa-plus-circle me-2"></i>إضافة دفعة جديدة
                            </h5>
                        </div>
                        <div class="card-body">
                            <?php if ($remaining > 0): ?>
                            <form method="POST" action="">
                                <div class="row">
                                    <div class="col-md-6">
                                        <div class="mb-3">
                                            <label for="amount" class="form-label">💰 المبلغ (ريال)</label>
                                            <input type="number" 
                                                   class="form-control" 
                                                   id="amount" 
                                                   name="amount" 
                                                   min="1" 
                                                   max="<?= $remaining ?>" 
                                                   step="0.01" 
                                                   required
                                                   placeholder="أدخل المبلغ">
                                            <div class="form-text">الحد الأقصى: <?= number_format($remaining, 0) ?> ريال</div>
                                        </div>
                                    </div>
                                    <div class="col-md-6">
                                        <div class="mb-3">
                                            <label for="payment_method" class="form-label">💳 طريقة الدفع</label>
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
                                    <label for="payment_date" class="form-label">📅 تاريخ الدفع</label>
                                    <input type="datetime-local" 
                                           class="form-control" 
                                           id="payment_date" 
                                           name="payment_date" 
                                           value="<?= date('Y-m-d\TH:i') ?>" 
                                           required>
                                </div>
                                
                                <div class="mb-3">
                                    <label for="notes" class="form-label">📝 ملاحظات</label>
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
                                <i class="fas fa-trophy fa-3x mb-3 text-warning"></i>
                                <h5>🎉 تم تسديد كامل المبلغ</h5>
                                <p class="mb-0">تم استلام جميع الدفعات المطلوبة لهذا الحجز بنجاح!</p>
                            </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>

                <!-- سجل الدفعات -->
                <div class="col-lg-6">
                    <div class="card">
                        <div class="card-header">
                            <h5 class="mb-0">
                                <i class="fas fa-history me-2"></i>سجل الدفعات
                            </h5>
                        </div>
                        <div class="card-body">
                            <?php if ($payments_result->num_rows > 0): ?>
                            <div class="table-responsive">
                                <table class="table table-hover">
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
                                            <td>
                                                <small class="text-muted"><?= date('m/d', strtotime($payment['payment_date'])) ?></small><br>
                                                <small><?= date('H:i', strtotime($payment['payment_date'])) ?></small>
                                            </td>
                                            <td>
                                                <strong class="text-success"><?= number_format($payment['amount'], 0) ?></strong>
                                                <small class="text-muted d-block">ريال</small>
                                            </td>
                                            <td>
                                                <span class="badge bg-secondary">
                                                    <?= htmlspecialchars($payment['payment_method']) ?>
                                                </span>
                                            </td>
                                            <td>
                                                <small><?= htmlspecialchars($payment['notes']) ?: '-' ?></small>
                                            </td>
                                        </tr>
                                        <?php endwhile; ?>
                                    </tbody>
                                </table>
                            </div>
                            <?php else: ?>
                            <div class="alert alert-info text-center">
                                <i class="fas fa-info-circle fa-3x mb-3 text-primary"></i>
                                <h6>لا توجد دفعات مسجلة</h6>
                                <p class="mb-0">لم يتم تسجيل أي دفعات لهذا الحجز بعد.</p>
                            </div>
                            <?php endif; ?>
                        </div>
                    </div>
                </div>
            </div>

            <!-- قسم المغادرة -->
            <?php if ($booking['status'] !== 'شاغرة'): ?>
            <div class="card">
                <div class="card-header" style="background: linear-gradient(135deg, #ff6b6b 0%, #ee5a6f 100%);">
                    <h5 class="mb-0">
                        <i class="fas fa-sign-out-alt me-2"></i>تسجيل المغادرة
                    </h5>
                </div>
                <div class="card-body">
                    <div class="row align-items-center">
                        <div class="col-lg-8">
                            <?php if ($remaining > 0): ?>
                            <div class="alert alert-warning">
                                <i class="fas fa-exclamation-triangle me-2"></i>
                                <strong>تنبيه:</strong> لا يمكن تسجيل المغادرة قبل تسديد كامل المبلغ. 
                                المبلغ المتبقي: <strong><?= number_format($remaining, 0) ?> ريال</strong>
                            </div>
                            <?php else: ?>
                            <div class="alert alert-success">
                                <i class="fas fa-check-circle me-2"></i>
                                <strong>🎉 جاهز للمغادرة!</strong> تم تسديد كامل المبلغ المطلوب.
                            </div>
                            <?php endif; ?>
                        </div>
                        <div class="col-lg-4 text-center">
                            <?php if ($remaining == 0): ?>
                            <form method="POST" action="">
                                <button type="submit" name="checkout" class="btn btn-success btn-lg" onclick="return confirm('🤔 هل أنت متأكد من تسجيل مغادرة النزيل؟')">
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
            <div class="card">
                <div class="card-body text-center">
                    <div class="alert alert-info">
                        <i class="fas fa-check-circle fa-3x mb-3 text-success"></i>
                        <h5>✅ تم تسجيل المغادرة</h5>
                        <p class="mb-0">تم تسجيل مغادرة النزيل وتحرير الغرفة بنجاح.</p>
                    </div>
                </div>
            </div>
            <?php endif; ?>

        </div>
    </div>
</div>

<script src="../../includes/js/bootstrap.bundle.min.js"></script>
<script src="../../includes/js/custom.js"></script>
<script>
document.addEventListener('DOMContentLoaded', function() {
    // إظهار التنبيهات
    const toastElement = document.getElementById('flashToast');
    if (toastElement) {
        const toast = new bootstrap.Toast(toastElement, { delay: 5000 });
        toast.show();
    }
    
    // تحسين تجربة المستخدم
    const amountInput = document.getElementById('amount');
    if (amountInput) {
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
    
    // تحديث التاريخ
    const dateInput = document.getElementById('payment_date');
    if (dateInput) {
        const now = new Date();
        dateInput.value = now.toISOString().slice(0, 16);
    }
    
    // تأثيرات تفاعلية
    const summaryItems = document.querySelectorAll('.summary-item');
    summaryItems.forEach(item => {
        item.addEventListener('click', function() {
            this.style.transform = 'scale(0.95)';
            setTimeout(() => {
                this.style.transform = 'scale(1)';
            }, 150);
        });
    });
});
</script>

</body>
</html>
<?php ob_end_flush(); ?>