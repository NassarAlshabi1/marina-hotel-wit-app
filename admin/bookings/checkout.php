<?php
require_once '../../includes/security.php';
include_once '../../includes/db.php';

if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

$conn->set_charset("utf8mb4");

if (!isset($_GET['id']) || !is_numeric($_GET['id'])) {
    die("معرف الحجز غير صالح.");
}

$booking_id = intval($_GET['id']);

// استعلام لجلب بيانات الحجز مع حالة الغرفة
$query = "
    SELECT 
        b.booking_id,
        b.guest_name,
        b.status,
        b.room_number,
        r.price AS room_price,
        b.checkin_date,
        CASE 
            WHEN b.actual_checkout IS NULL 
            THEN DATEDIFF(CURRENT_DATE(), b.checkin_date) + 
                 (CASE WHEN TIME(CURRENT_TIME()) > '13:00:00' THEN 1 ELSE 0 END)
            ELSE DATEDIFF(b.actual_checkout, b.checkin_date)
        END AS nights,
        IFNULL((SELECT SUM(amount) FROM payment WHERE booking_id = b.booking_id), 0) AS paid_amount
    FROM bookings b
    JOIN rooms r ON b.room_number = r.room_number
    WHERE b.booking_id = ?
";

$stmt = $conn->prepare($query);
$stmt->bind_param("i", $booking_id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    die("الحجز غير موجود.");
}

$booking = $result->fetch_assoc();
$total_price = $booking['nights'] * $booking['room_price'];
$remaining = $total_price - $booking['paid_amount'];

$error = '';
$success = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    verify_csrf_token();

    if ($remaining > 0) {
        $error = "لا يمكن تسجيل المغادرة. يوجد مبلغ متبقي قدره: " . number_format($remaining, 0);
    } else {
        $conn->begin_transaction();
        
        try {
            $checkout_date = date('Y-m-d H:i:s');
            
            // تحديث حالة الحجز: استخدام 'شاغرة' (قيمة صالحة في ENUM) بدلاً من 'غادر'
            $update_booking = "UPDATE bookings SET actual_checkout = ?, checkout_date = ?, status = 'شاغرة', last_calculation = CURRENT_TIMESTAMP WHERE booking_id = ?";
            $stmt_booking = $conn->prepare($update_booking);
            $stmt_booking->bind_param("ssi", $checkout_date, $checkout_date, $booking_id);
            $stmt_booking->execute();

            $update_room = "UPDATE rooms SET status = 'شاغرة' WHERE room_number = ?";
            $stmt_room = $conn->prepare($update_room);
            $stmt_room->bind_param("s", $booking['room_number']);
            $stmt_room->execute();

            $conn->commit();
            
            // إعادة حساب حالات الغرف بعد التسجيل الخروج لضمان المزامنة الصحيحة
            require_once '../../api/v1/config.php';
            recalculateAllRoomStatuses($conn);
            
            $success = "تم تسجيل مغادرة النزيل وتحديث حالة الغرفة إلى شاغرة.";
        } catch (Exception $e) {
            $conn->rollback();
            $error = "حدث خطأ أثناء تسجيل المغادرة: " . $e->getMessage();
        }
    }
}

include_once '../../includes/header.php';
?>

<div class="container py-4" style="max-width:700px;">
    <div class="mb-3">
        <a href="../dash.php" class="btn btn-outline-primary fw-bold">
            <i class="fas fa-arrow-right me-2"></i>العودة إلى لوحة التحكم
        </a>
    </div>

    <h2 class="text-center mb-4 text-primary fw-bold">
        <i class="fas fa-sign-out-alt me-2"></i>تسجيل مغادرة النزيل
    </h2>

    <?php if ($error): ?>
        <div class="alert alert-danger text-center"><?= htmlspecialchars($error); ?></div>
    <?php elseif ($success): ?>
        <div class="alert alert-success text-center"><?= htmlspecialchars($success); ?></div>
        <div class="text-center mb-3">
            <a href="list.php" class="btn btn-primary">العودة لقائمة الحجوزات</a>
        </div>
    <?php endif; ?>

    <?php if (!$success): ?>
        <div class="card mx-auto">
            <div class="card-header bg-primary text-white">
                <h5 class="mb-0"><i class="fas fa-info-circle me-2"></i>بيانات الحجز</h5>
            </div>
            <div class="card-body">
                <div class="row g-3">
                    <div class="col-md-6">
                        <strong>اسم النزيل:</strong> <?= htmlspecialchars($booking['guest_name']); ?>
                    </div>
                    <div class="col-md-6">
                        <strong>رقم الغرفة:</strong> <?= htmlspecialchars($booking['room_number']); ?>
                    </div>
                    <div class="col-md-6">
                        <strong>تاريخ الوصول:</strong> <?= date('d/m/Y', strtotime($booking['checkin_date'])); ?>
                    </div>
                    <div class="col-md-6">
                        <strong>عدد الليالي:</strong> <?= $booking['nights']; ?>
                    </div>
                    <div class="col-md-6">
                        <strong>سعر الغرفة / ليلة:</strong> <?= number_format($booking['room_price'], 0); ?>
                    </div>
                    <div class="col-md-6">
                        <strong>المبلغ الإجمالي:</strong> <?= number_format($total_price, 0); ?>
                    </div>
                    <div class="col-md-6">
                        <strong>المبلغ المدفوع:</strong> <?= number_format($booking['paid_amount'], 0); ?>
                    </div>
                    <div class="col-md-6">
                        <strong>المبلغ المتبقي:</strong> 
                        <span class="<?= $remaining > 0 ? 'text-danger' : 'text-success'; ?>">
                            <?= number_format($remaining, 0); ?>
                        </span>
                    </div>
                </div>

                <hr>

                <form method="post" onsubmit="return confirm('هل أنت متأكد من تسجيل مغادرة النزيل؟');">
                    <?= csrf_field(); ?>
                    <?php if ($remaining > 0): ?>
                        <div class="alert alert-warning">
                            <i class="fas fa-exclamation-triangle me-2"></i>
                            لا يمكن تسجيل المغادرة. يجب سداد المبلغ المتبقي أولاً.
                        </div>
                        <a href="payment.php?id=<?= $booking_id ?>" class="btn btn-warning w-100 mb-2">
                            <i class="fas fa-money-bill me-2"></i>إضافة دفعة
                        </a>
                    <?php endif; ?>
                    
                    <button type="submit" class="btn btn-danger w-100" <?= ($remaining > 0) ? 'disabled' : ''; ?>>
                        <i class="fas fa-sign-out-alt me-2"></i>تسجيل مغادرة النزيل
                    </button>
                </form>

                <div class="mt-3 text-center">
                    <a href="list.php" class="btn btn-outline-secondary">
                        <i class="fas fa-list me-2"></i>العودة لقائمة الحجوزات
                    </a>
                </div>
            </div>
        </div>
    <?php endif; ?>
</div>

<?php include_once '../../includes/footer.php'; ?>
