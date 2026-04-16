<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تسجيل مغادرة النزيل</title>
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
        }
        
        /* تحسين Font Awesome للعمل محلياً */
        .fas, .far, .fab, .fa {
            font-family: "Font Awesome 6 Free", "Font Awesome 6 Brands" !important;
            font-weight: 900;
        }
    </style>
</head>
<body>
<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';

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
    if ($remaining > 0) {
        $error = "لا يمكن تسجيل المغادرة. يوجد مبلغ متبقي قدره: " . number_format($remaining, 0);
    } else {
        $conn->begin_transaction();
        
        try {
            $checkout_date = date('Y-m-d H:i:s');
            
            $update_booking = "UPDATE bookings SET actual_checkout = ?, status = 'غادر' WHERE booking_id = ?";
            $stmt_booking = $conn->prepare($update_booking);
            $stmt_booking->bind_param("si", $checkout_date, $booking_id);
            $stmt_booking->execute();

            $update_room = "UPDATE rooms SET status = 'شاغرة' WHERE room_number = ?";
            $stmt_room = $conn->prepare($update_room);
            $stmt_room->bind_param("s", $booking['room_number']);
            $stmt_room->execute();

            $conn->commit();
            $success = "تم تسجيل مغادرة النزيل وتحديث حالة الغرفة إلى شاغرة.";
        } catch (Exception $e) {
            $conn->rollback();
            $error = "حدث خطأ أثناء تسجيل المغادرة: " . $e->getMessage();
        }
    }
}
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

<script src="../../includes/js/bootstrap.bundle.min.js"></script>

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
        b.checkout_date,
        IFNULL((SELECT SUM(amount) FROM payment WHERE booking_id = b.booking_id), 0) AS paid_amount,
        (
            r.price * 
            CASE
                WHEN b.checkout_date IS NULL THEN DATEDIFF(CURDATE(), b.checkin_date) + 1
                ELSE DATEDIFF(b.checkout_date, b.checkin_date)
            END
        ) AS total_price
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

// نفترض أن عند الخروج الغرفة يجب أن تكون "محجوزة" حتى يسمح بالخروج
if ($booking['status'] !== 'محجوزة') {
    die("لا يمكن تسجيل المغادرة لأن حالة الغرفة ليست 'محجوزة'.");
}

$remaining = $booking['total_price'] - $booking['paid_amount'];
$error = "";
$success = "";

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if ($remaining > 0) {
        $error = "لا يمكن تسجيل المغادرة، يرجى تسديد المبلغ المتبقي أولاً.";
    } else {
        $conn->begin_transaction();
        try {
            $checkout_date = date('Y-m-d H:i:s');

            // تحديث حالة الغرفة في جدول bookings إلى "شاغرة" مع تسجيل تاريخ الخروج
            $update_booking = "UPDATE bookings SET status = 'شاغرة', checkout_date = ? WHERE booking_id = ?";
            $stmt_update = $conn->prepare($update_booking);
            $stmt_update->bind_param("si", $checkout_date, $booking_id);
            $stmt_update->execute();

            // تحديث حالة الغرفة في جدول rooms
            $update_room = "UPDATE rooms SET status = 'شاغرة' WHERE room_number = ?";
            $stmt_room = $conn->prepare($update_room);
            $stmt_room->bind_param("s", $booking['room_number']);
            $stmt_room->execute();

            $conn->commit();
            $success = "تم تسجيل مغادرة النزيل وتحديث حالة الغرفة إلى شاغرة.";
            $booking['status'] = 'شاغرة';
            $booking['checkout_date'] = $checkout_date;
        } catch (Exception $e) {
            $conn->rollback();
            $error = "حدث خطأ أثناء تسجيل المغادرة: " . $e->getMessage();
        }
    }
}
?>

<div class="container py-4" style="max-width:700px;">
    <div class="mb-3">
        <a href="../dash.php" class="btn btn-outline-primary fw-bold">
            ← العودة إلى لوحة التحكم
        </a>
    </div>

    <h2 class="text-center mb-4 text-primary fw-bold">تسجيل مغادرة النزيل</h2>

    <?php if ($error): ?>
        <div class="alert alert-danger text-center"><?= htmlspecialchars($error); ?></div>
    <?php elseif ($success): ?>
        <div class="alert alert-success text-center"><?= htmlspecialchars($success); ?></div>
        <div class="text-center mb-3">
            <a href="index.php" class="btn btn-primary">العودة لقائمة الحجوزات</a>
        </div>
    <?php endif; ?>

    <?php if (!$success): ?>
        <div class="card mx-auto">
            <div class="card-body">
                <h5 class="card-title mb-3">بيانات الحجز</h5>
                <p><strong>اسم النزيل:</strong> <?= htmlspecialchars($booking['guest_name']); ?></p>
                <p><strong>رقم الغرفة:</strong> <?= htmlspecialchars($booking['room_number']); ?></p>
                <p><strong>تاريخ الوصول:</strong> <?= date('d/m/Y', strtotime($booking['checkin_date'])); ?></p>
                <p><strong>سعر الغرفة / ليوم:</strong> <?= number_format($booking['room_price'], 0); ?></p>
                <p><strong>المبلغ الإجمالي المتوقع:</strong> <?= number_format($booking['total_price'], 0); ?></p>
                <p><strong>المبلغ المدفوع:</strong> <?= number_format($booking['paid_amount'], 0); ?></p>
                <p><strong>المبلغ المتبقي:</strong> <?= number_format($remaining, 0); ?></p>
                <p><strong>حالة الغرفة:</strong> <?= htmlspecialchars($booking['status']); ?></p>

                <form method="post" onsubmit="return confirm('هل أنت متأكد من تسجيل مغادرة النزيل؟');">
                    <button type="submit" class="btn btn-danger w-100" <?= ($remaining > 0) ? 'disabled' : ''; ?>>
                        تسجيل مغادرة النزيل
                    </button>
                </form>

                <div class="mt-3 text-center">
                    <a href="index.php" class="btn btn-outline-secondary">العودة لقائمة الحجوزات</a>
                </div>
            </div>
        </div>
    <?php endif; ?>
</div>

<?php include_once '../../includes/footer.php'; ?>
\`\`\`

### التعديلات التي أجريتها:
1. **إزالة علامة العملة**: تم إزالة علامة "ر.س" من عرض المبالغ.
2. **إزالة الكسور العشرية**: تم استخدام `number_format()` مع 参数 `0` لعرض الأرقام بدون أرقام عشرية.

الآن، يتم عرض المبالغ بدون أي رموز للعملة أو أرقام عشرية.
