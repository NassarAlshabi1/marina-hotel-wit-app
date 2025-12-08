<?php
// تأكد من وجود معرف الحجز
if(!isset($_GET['id']) || empty($_GET['id']) || !is_numeric($_GET['id'])) {
    header("Location: ../dashboard.php?error=معرف الحجز غير صالح");
    exit();
}

include_once '../../includes/db.php';
include_once '../../includes/header.php';

// استعداد بيانات الحجز
$booking_id = intval($_GET['id']);

// استعلام محسّن لجلب بيانات الحجز مع التحقق من الصحة
$booking_query = "SELECT 
    b.booking_id,
    b.guest_name,
    b.room_number,
    r.price AS room_price,
    DATE(b.checkin_date) AS checkin_date,
    b.actual_checkout,
    DATEDIFF(IFNULL(b.actual_checkout, CURRENT_DATE), b.checkin_date) + 
    CASE WHEN TIME(IFNULL(b.actual_checkout, CURRENT_TIME)) > '13:00:00' THEN 1 ELSE 0 END AS nights,
    b.status,
    IFNULL((SELECT SUM(p.amount) FROM payment p WHERE p.booking_id = b.booking_id), 0) AS paid_amount
FROM bookings b
LEFT JOIN rooms r ON b.room_number = r.room_number
WHERE b.booking_id = ?
LIMIT 1";

$stmt = $conn->prepare($booking_query);
$stmt->bind_param("i", $booking_id);
$stmt->execute();
$booking_result = $stmt->get_result();

if($booking_result->num_rows === 0) {
    header("Location: ../dashboard.php?error=الحجز غير موجود");
    exit();
}

$booking = $booking_result->fetch_assoc();

// حماية ضد القيم غير الصالحة
$nights = max(1, intval($booking['nights']));
$total_price = intval($booking['room_price']) * $nights;
$remaining = max(0, $total_price - intval($booking['paid_amount']));

// معالجة إضافة دفعة
if($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['submit_payment'])) {
    $amount = intval($_POST['amount'] ?? 0);
    $payment_date = date('Y-m-d H:i:s', strtotime($_POST['payment_date'] ?? 'now'));
    $payment_method = $conn->real_escape_string($_POST['payment_method'] ?? 'نقدي');
    $notes = $conn->real_escape_string($_POST['notes'] ?? '');

    if($amount <= 0 || $amount > $remaining) {
        $payment_error = "المبلغ يجب أن يكون بين 1 و {$remaining}";
    } else {
        $insert_payment = "INSERT INTO payment 
                          (booking_id, amount, payment_date, payment_method, notes) 
                          VALUES (?, ?, ?, ?, ?)";
        
        $stmt = $conn->prepare($insert_payment);
        $stmt->bind_param("iisss", $booking_id, $amount, $payment_date, $payment_method, $notes);
        
        if($stmt->execute()) {
            header("Location: payment.php?id={$booking_id}&success=تم تسجيل الدفعة بنجاح");
            exit();
        } else {
            $payment_error = "خطأ في تسجيل الدفعة: " . $conn->error;
        }
    }
}

// معالجة تسجيل المغادرة
if($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['checkout'])) {
    if($remaining > 0) {
        $checkout_error = "لا يمكن تسجيل المغادرة، المبلغ المتبقي: {$remaining}";
    } else {
        // بدء معاملة
        $conn->begin_transaction();
        try {
            // تسجيل الفاتورة
            $invoice_query = "INSERT INTO invoices 
                            (booking_id, No_room, amount, created_at) 
                            VALUES (?, ?, ?, NOW())";
            $stmt = $conn->prepare($invoice_query);
            $no_room = intval($booking['room_number']);
            $stmt->bind_param("iii", $booking_id, $no_room, $total_price);
            $stmt->execute();
            $invoice_id = $conn->insert_id;

            // تحديث حالة الحجز
            $update_booking = "UPDATE bookings 
                             SET status = 'شاغرة', 
                                 actual_checkout = NOW(),
                                 calculated_nights = ?
                             WHERE booking_id = ?";
            $stmt = $conn->prepare($update_booking);
            $stmt->bind_param("ii", $nights, $booking_id);
            $stmt->execute();

            // تحديث حالة الغرفة
            $update_room = "UPDATE rooms 
                          SET status = 'شاغرة' 
                          WHERE room_number = ?";
            $stmt = $conn->prepare($update_room);
            $stmt->bind_param("i", $no_room);
            $stmt->execute();

            $conn->commit();
            header("Location: payment.php?id={$booking_id}&success=تم تسجيل المغادرة بنجاح");
            exit();
        } catch (Exception $e) {
            $conn->rollback();
            $checkout_error = "خطأ في تسجيل المغادرة: " . $e->getMessage();
        }
    }
}

// جلب سجل الدفعات
$payments_query = "SELECT 
                  payment_id, 
                  amount, 
                  payment_date, 
                  payment_method, 
                  notes 
                  FROM payment 
                  WHERE booking_id = ? 
                  ORDER BY payment_date DESC";

$stmt = $conn->prepare($payments_query);
$stmt->bind_param("i", $booking_id);
$stmt->execute();
$payments_result = $stmt->get_result();
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إدارة الدفعات - حجز #<?= $booking_id ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        :root {
            --main-color: #2c3e50;
            --secondary-color: #7f8c8d;
            --success-color: #28a745;
            --danger-color: #dc3545;
            --warning-color: #ffc107;
        }
        body {
            background-color: #f8f9fa;
        }
        .summary-card {
            border-radius: 10px;
            box-shadow: 0 4px 10px rgba(0,0,0,0.1);
            border: none;
            transition: all 0.3s;
        }
        .summary-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 20px rgba(0,0,0,0.15);
        }
        .payment-method {
            padding: 15px;
            border: 2px solid #ddd;
            border-radius: 8px;
            cursor: pointer;
            transition: all 0.3s;
        }
        .payment-method:hover {
            border-color: var(--main-color);
        }
        .payment-method.active {
            background-color: rgba(44, 62, 80, 0.1);
            border-color: var(--main-color);
        }
        .action-btn {
            position: fixed;
            bottom: 20px;
            z-index: 1000;
            box-shadow: 0 4px 10px rgba(0,0,0,0.2);
        }
        .back-btn {
            right: 20px;
        }
        .checkout-btn {
            left: 20px;
        }
        @media (max-width: 768px) {
            .action-btn {
                position: static;
                margin-top: 20px;
                width: 100%;
            }
        }
    </style>
</head>
<body>
    <div class="container py-4">
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h2 class="mb-0">
                <i class="fas fa-file-invoice-dollar text-primary me-2"></i>
                إدارة الدفعات - حجز #<?= $booking_id ?>
            </h2>
            <div>
                <a href="../bookings/list.php" class="btn btn-outline-secondary">
                    <i class="fas fa-arrow-left me-2"></i>العودة
                </a>
            </div>
        </div>

        <!-- عرض رسائل التبليغ -->
        <?php if(isset($_GET['success'])): ?>
        <div class="alert alert-success alert-dismissible fade show">
            <?= htmlspecialchars($_GET['success']) ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
        <?php endif; ?>

        <?php if(isset($payment_error)): ?>
        <div class="alert alert-danger alert-dismissible fade show">
            <?= htmlspecialchars($payment_error) ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
        <?php endif; ?>

        <?php if(isset($checkout_error)): ?>
        <div class="alert alert-warning alert-dismissible fade show">
            <?= htmlspecialchars($checkout_error) ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
        <?php endif; ?>

        <div class="row">
            <!-- معلومات الحجز -->
            <div class="col-md-6">
                <div class="card summary-card mb-4">
                    <div class="card-header bg-primary text-white">
                        <i class="fas fa-info-circle me-2"></i>
                        تفاصيل الحجز
                    </div>
                    <div class="card-body">
                        <table class="table table-borderless">
                            <tbody>
                                <tr>
                                    <td class="fw-bold text-end" width="40%">اسم النزيل:</td>
                                    <td><?= htmlspecialchars($booking['guest_name']) ?></td>
                                </tr>
                                <tr>
                                    <td class="fw-bold text-end">رقم الغرفة:</td>
                                    <td><?= htmlspecialchars($booking['room_number']) ?></td>
                                </tr>
                                <tr>
                                    <td class="fw-bold text-end">تاريخ الوصول:</td>
                                    <td><?= htmlspecialchars($booking['checkin_date']) ?></td>
                                </tr>
                                <tr>
                                    <td class="fw-bold text-end">عدد الليالي:</td>
                                    <td><?= $nights ?></td>
                                </tr>
                                <tr>
                                    <td class="fw-bold text-end">سعر الليلة:</td>
                                    <td><?= $booking['room_price'] ?></td>
                                </tr>
                                <tr class="border-top">
                                    <td class="fw-bold text-end">المبلغ الإجمالي:</td>
                                    <td class="fw-bold"><?= $total_price ?></td>
                                </tr>
                                <tr>
                                    <td class="fw-bold text-end">المبلغ المدفوع:</td>
                                    <td><?= $booking['paid_amount'] ?></td>
                                </tr>
                                <tr class="border-top">
                                    <td class="fw-bold text-end">المبلغ المتبقي:</td>
                                    <td class="fw-bold <?= $remaining > 0 ? 'text-danger' : 'text-success' ?>">
                                        <?= $remaining ?>
                                    </td>
                                </tr>
                            </tbody>
                        </table>
                    </div>
                </div>
            </div>

            <!-- إضافة دفعة جديدة -->
            <div class="col-md-6">
                <div class="card summary-card">
                    <div class="card-header bg-success text-white">
                        <i class="fas fa-money-bill-wave me-2"></i>
                        إضافة دفعة
                    </div>
                    <div class="card-body">
                        <form method="post" novalidate>
                            <div class="mb-3">
                                <label class="form-label">المبلغ:</label>
                                <input type="number" name="amount" 
                                       class="form-control form-control-lg" 
                                       min="1" 
                                       max="<?= $remaining ?>"
                                       required>
                            </div>
                            
                            <div class="mb-3">
                                <label class="form-label">تاريخ الدفع:</label>
                                <input type="datetime-local" name="payment_date"
                                       class="form-control" 
                                       value="<?= date('Y-m-d\TH:i') ?>"
                                       required>
                            </div>
                            
                            <div class="mb-3">
                                <label class="form-label mb-2">طريقة الدفع:</label>
                                <select name="payment_method" class="form-select" required>
                                    <option value="نقدي">نقدي</option>
                                    <
                                    <option value="تحويل بنكي">تحويل بنكي</option>
                                </select>
                            </div>
                            
                            <div class="mb-4">
                                <label class="form-label">ملاحظات:</label>
                                <textarea name="notes" class="form-control" rows="2"></textarea>
                            </div>
                            
                            <button type="submit" name="submit_payment" 
                                    class="btn btn-success w-100 py-2">
                                <i class="fas fa-check-circle me-2"></i>
                                تسجيل الدفعة
                            </button>
                        </form>
                    </div>
                </div>
            </div>
        </div>

        <!-- سجل الدفعات -->
        <div class="card summary-card mt-4">
            <div class="card-header bg-info text-white">
                <i class="fas fa-history me-2"></i>
                سجل الدفعات
            </div>
            <div class="card-body">
                <?php if($payments_result->num_rows > 0): ?>
                    <div class="table-responsive">
                        <table class="table table-hover">
                            <thead class="table-light">
                                <tr>
                                    <th>#</th>
                                    <th>المبلغ</th>
                                    <th>التاريخ</th>
                                    <th>الطريقة</th>
                                    <th>ملاحظات</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php while($payment = $payments_result->fetch_assoc()): ?>
                                <tr>
                                    <td><?= $payment['payment_id'] ?></td>
                                    <td><?= $payment['amount'] ?></td>
                                    <td><?= date('Y-m-d H:i', strtotime($payment['payment_date'])) ?></td>
                                    <td><?= htmlspecialchars($payment['payment_method']) ?></td>
                                    <td class="text-truncate" style="max-width: 200px;" title="<?= htmlspecialchars($payment['notes'] ?? '') ?>">
                                        <?= htmlspecialchars($payment['notes'] ?? '-') ?>
                                    </td>
                                </tr>
                                <?php endwhile; ?>
                            </tbody>
                        </table>
                    </div>
                <?php else: ?>
                    <div class="text-center py-4 text-muted">
                        <i class="fas fa-info-circle fa-2x mb-3"></i>
                        <p class="mb-0">لا توجد دفعات مسجلة لهذا الحجز</p>
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <!-- زر تسجيل المغادرة -->
    <?php if($booking['status'] != 'شاغرة'): ?>
    <form method="post" 
          class="checkout-btn action-btn"
          onsubmit="return confirm('هل أنت متأكد من تسجيل مغادرة النزيل؟');">
        <button type="submit" name="checkout" 
                class="btn btn-<?= $remaining > 0 ? 'secondary' : 'danger' ?> btn-lg px-4"
                <?= $remaining > 0 ? 'disabled' : '' ?>>
            <i class="fas fa-sign-out-alt me-2"></i>
            <?= $remaining > 0 ? 'المبلغ غير مسدد بالكامل' : 'تسجيل المغادرة' ?>
        </button>
    </form>
    <?php endif; ?>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // إدارة التمركز الأوتوماتيكي لمربع الدفع
        document.querySelector('[name="amount"]').focus();
        
        // التحقق من المبلغ قبل الإرسال
        document.querySelector('form[name="submit_payment"]').addEventListener('submit', function(e) {
            const amountInput = this.querySelector('[name="amount"]');
            const remaining = <?= $remaining ?>;
            
            if(parseInt(amountInput.value) > remaining) {
                alert('المبلغ المدخل أكبر من المبلغ المتبقي!');
                e.preventDefault();
                amountInput.focus();
            }
        });
    </script>
</body>
</html>

<?php include_once '../../includes/footer.php'; ?>
