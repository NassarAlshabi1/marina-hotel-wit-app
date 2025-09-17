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
    <link href="../../css/bootstrap.min.css" rel="stylesheet">
    <link href="../../includes/css/fontawesome.min.css" rel="stylesheet">
    <link href="../../includes/css/cairo-font.css" rel="stylesheet">
    <link href="../../includes/css/custom.css" rel="stylesheet">
    <!-- تم نقل جميع الأنماط إلى ملفات CSS منفصلة لتعمل بدون إنترنت -->
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
// Marina Hotel Payment System - Premium Features
document.addEventListener('DOMContentLoaded', function() {
    console.log('🏨 Marina Hotel Payment System Premium - Starting...');
    
    // Initialize payment system specific features
    PaymentSystem.init();
    
    console.log('✅ Marina Hotel Payment System Premium - Ready!');
});

// Payment System Module
const PaymentSystem = {
    init: function() {
        this.initializeToasts();
        this.setupPaymentValidation();
        this.setupProgressRing();
        this.initializeCounters();
        this.setupFormEnhancements();
    },

    initializeToasts: function() {
        const toastElement = document.getElementById('flashToast');
        if (toastElement && window.bootstrap) {
            const toast = new bootstrap.Toast(toastElement, { 
                delay: 5000,
                autohide: true 
            });
            toast.show();
            
            // Add custom animation
            toastElement.style.animation = 'slideInRight 0.5s ease-out';
        }
    },

    setupPaymentValidation: function() {
        const amountInput = document.getElementById('amount');
        if (amountInput) {
            amountInput.addEventListener('input', this.validateAmount);
            amountInput.addEventListener('focus', function() {
                this.parentElement.style.transform = 'scale(1.02)';
                this.parentElement.style.transition = 'transform 0.3s ease';
            });
            amountInput.addEventListener('blur', function() {
                this.parentElement.style.transform = 'scale(1)';
            });
        }

        // Phone validation
        const phoneInputs = document.querySelectorAll('input[type="tel"]');
        phoneInputs.forEach(input => {
            input.addEventListener('input', this.formatYemeniPhone);
        });
    },

    validateAmount: function() {
        const value = parseFloat(this.value);
        const max = parseFloat(this.getAttribute('max'));
        const min = parseFloat(this.getAttribute('min')) || 0;

        this.classList.remove('is-valid', 'is-invalid');

        if (isNaN(value) || value <= min) {
            this.classList.add('is-invalid');
            this.setCustomValidity('المبلغ يجب أن يكون أكبر من ' + min);
            PaymentSystem.showValidationFeedback(this, 'error', 'المبلغ يجب أن يكون أكبر من صفر');
        } else if (value > max) {
            this.classList.add('is-invalid');
            this.setCustomValidity('المبلغ لا يمكن أن يتجاوز ' + max.toLocaleString() + ' ريال');
            PaymentSystem.showValidationFeedback(this, 'error', 'المبلغ يتجاوز الحد المسموح');
        } else {
            this.classList.add('is-valid');
            this.setCustomValidity('');
            PaymentSystem.showValidationFeedback(this, 'success', 'المبلغ صحيح ✓');
        }
    },

    formatYemeniPhone: function() {
        let value = this.value.replace(/[^0-9+]/g, '');
        
        // Format Yemeni numbers
        if (value.startsWith('7') && value.length <= 9) {
            value = value.replace(/(\d{3})(\d{3})(\d{3})/, '$1 $2 $3');
        } else if (value.startsWith('967')) {
            value = value.replace(/(\d{3})(\d{1})(\d{3})(\d{3})(\d{3})/, '$1 $2 $3 $4 $5');
        }
        
        this.value = value;

        // Validate
        if (window.MarinaHotel && window.MarinaHotel.Utils.validateYemeniPhone(value)) {
            this.classList.add('is-valid');
            this.classList.remove('is-invalid');
        } else if (value.length > 3) {
            this.classList.add('is-invalid');
            this.classList.remove('is-valid');
        }
    },

    showValidationFeedback: function(input, type, message) {
        let feedback = input.parentElement.querySelector('.validation-feedback');
        
        if (!feedback) {
            feedback = document.createElement('div');
            feedback.className = 'validation-feedback small mt-1';
            input.parentElement.appendChild(feedback);
        }

        feedback.className = `validation-feedback small mt-1 text-${type === 'error' ? 'danger' : 'success'}`;
        feedback.innerHTML = `<i class="fas fa-${type === 'error' ? 'exclamation-circle' : 'check-circle'} me-1"></i>${message}`;
        
        // Animate
        feedback.style.opacity = '0';
        feedback.style.transform = 'translateY(-10px)';
        
        requestAnimationFrame(() => {
            feedback.style.transition = 'all 0.3s ease';
            feedback.style.opacity = '1';
            feedback.style.transform = 'translateY(0)';
        });
    },

    setupProgressRing: function() {
        const progressRing = document.querySelector('.progress-ring .progress');
        if (progressRing) {
            const progressValue = progressRing.closest('svg').style.getPropertyValue('--progress') || '0';
            
            // Animate progress ring
            setTimeout(() => {
                progressRing.style.transition = 'stroke-dashoffset 2s ease-in-out';
                progressRing.style.strokeDashoffset = `calc(157 - (157 * ${progressValue}) / 100)`;
            }, 500);
        }
    },

    initializeCounters: function() {
        const counters = document.querySelectorAll('.summary-item h3');
        
        counters.forEach((counter, index) => {
            const text = counter.textContent;
            const numbers = text.match(/[\d,]+/);
            
            if (numbers) {
                const targetValue = parseInt(numbers[0].replace(/,/g, ''));
                const suffix = text.replace(/[\d,\s]+/, '');
                
                if (targetValue > 0) {
                    this.animateCounter(counter, 0, targetValue, suffix, 2000 + (index * 200));
                }
            }
        });
    },

    animateCounter: function(element, start, end, suffix, duration) {
        const startTime = performance.now();
        
        const animate = (currentTime) => {
            const elapsed = currentTime - startTime;
            const progress = Math.min(elapsed / duration, 1);
            
            // Easing function
            const easeOutQuart = 1 - Math.pow(1 - progress, 4);
            const current = Math.floor(start + (end - start) * easeOutQuart);
            
            element.textContent = current.toLocaleString('ar-SA') + ' ' + suffix;
            
            if (progress < 1) {
                requestAnimationFrame(animate);
            }
        };
        
        requestAnimationFrame(animate);
    },

    setupFormEnhancements: function() {
        // Auto-update payment date
        const dateInput = document.getElementById('payment_date');
        if (dateInput) {
            // Set current datetime if empty
            if (!dateInput.value) {
                const now = new Date();
                dateInput.value = now.toISOString().slice(0, 16);
            }

            // Update every minute if not focused
            setInterval(() => {
                if (document.activeElement !== dateInput && !dateInput.value) {
                    const now = new Date();
                    dateInput.value = now.toISOString().slice(0, 16);
                }
            }, 60000);
        }

        // Enhanced form submission
        const paymentForm = document.querySelector('form[method="POST"]');
        if (paymentForm) {
            paymentForm.addEventListener('submit', function(e) {
                const submitBtn = this.querySelector('button[type="submit"]');
                if (submitBtn) {
                    submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>جارٍ التسجيل...';
                    submitBtn.disabled = true;
                    
                    // Re-enable after 5 seconds as fallback
                    setTimeout(() => {
                        submitBtn.innerHTML = '<i class="fas fa-save me-2"></i>تسجيل الدفعة';
                        submitBtn.disabled = false;
                    }, 5000);
                }
            });
        }

        // Enhanced checkout confirmation
        const checkoutForm = document.querySelector('form[name="checkout"], button[name="checkout"]');
        if (checkoutForm) {
            checkoutForm.addEventListener('click', function(e) {
                e.preventDefault();
                
                // Create custom confirmation dialog
                PaymentSystem.showCheckoutConfirmation(() => {
                    // Submit the form
                    if (this.closest('form')) {
                        this.closest('form').submit();
                    } else {
                        // Create and submit form
                        const form = document.createElement('form');
                        form.method = 'POST';
                        form.action = '';
                        
                        const input = document.createElement('input');
                        input.type = 'hidden';
                        input.name = 'checkout';
                        input.value = '1';
                        
                        form.appendChild(input);
                        document.body.appendChild(form);
                        form.submit();
                    }
                });
            });
        }
    },

    showCheckoutConfirmation: function(callback) {
        // Create custom modal for checkout confirmation
        const modalHTML = `
            <div class="modal fade" id="checkoutModal" tabindex="-1">
                <div class="modal-dialog modal-dialog-centered">
                    <div class="modal-content" style="border-radius: 20px; border: none;">
                        <div class="modal-header" style="background: linear-gradient(135deg, #ff6b6b 0%, #ee5a6f 100%); color: white; border-radius: 20px 20px 0 0;">
                            <h5 class="modal-title">
                                <i class="fas fa-sign-out-alt me-2"></i>
                                تأكيد تسجيل المغادرة
                            </h5>
                        </div>
                        <div class="modal-body text-center" style="padding: 30px;">
                            <div class="mb-4">
                                <i class="fas fa-question-circle fa-4x text-warning mb-3"></i>
                                <h4>هل أنت متأكد من تسجيل مغادرة النزيل؟</h4>
                                <p class="text-muted">هذا الإجراء لا يمكن التراجع عنه وسيتم تحرير الغرفة نهائياً.</p>
                            </div>
                        </div>
                        <div class="modal-footer justify-content-center" style="border: none; padding: 20px 30px 30px;">
                            <button type="button" class="btn btn-secondary me-2" data-bs-dismiss="modal">
                                <i class="fas fa-times me-2"></i>إلغاء
                            </button>
                            <button type="button" class="btn btn-danger" id="confirmCheckout">
                                <i class="fas fa-check me-2"></i>تأكيد المغادرة
                            </button>
                        </div>
                    </div>
                </div>
            </div>
        `;

        // Remove existing modal
        const existingModal = document.getElementById('checkoutModal');
        if (existingModal) {
            existingModal.remove();
        }

        // Add new modal
        document.body.insertAdjacentHTML('beforeend', modalHTML);
        const modal = document.getElementById('checkoutModal');
        
        // Setup event listeners
        document.getElementById('confirmCheckout').addEventListener('click', function() {
            if (window.bootstrap) {
                bootstrap.Modal.getInstance(modal).hide();
            }
            callback();
        });

        // Show modal
        if (window.bootstrap) {
            const bsModal = new bootstrap.Modal(modal);
            bsModal.show();
            
            // Remove modal after hide
            modal.addEventListener('hidden.bs.modal', function() {
                this.remove();
            });
        }
    }
};

// Add custom CSS animations
const customStyle = document.createElement('style');
customStyle.textContent = `
    @keyframes slideInRight {
        from { transform: translateX(100%); opacity: 0; }
        to { transform: translateX(0); opacity: 1; }
    }
    
    .validation-feedback {
        font-size: 0.875em;
        margin-top: 0.25rem;
    }
    
    .modal-content {
        animation: fadeInUp 0.3s ease-out;
    }
    
    @keyframes fadeInUp {
        from { transform: translateY(50px); opacity: 0; }
        to { transform: translateY(0); opacity: 1; }
    }
`;
document.head.appendChild(customStyle);
</script>

</body>
</html>
<?php ob_end_flush(); ?>