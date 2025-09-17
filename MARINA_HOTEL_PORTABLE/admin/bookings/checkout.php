Alright, I need to help the user modify their PHP page for checking out guests. They provided a detailed PHP script and asked to remove the currency symbol and decimal places. 

First, I'll look at the current code. It includes displaying amounts with Saudi Riyal symbols and decimal points. My task is to strip those out.

I'll start by locating where the amounts are displayed. The code shows several places where `number_format()` is used with `room_price`, `total_price`, `paid_amount`, and `remaining`. Each of these should be adjusted to remove the currency symbol and decimals.

Since the user doesn't want any currency symbols, I'll remove the "ر.س" that was added after each amount. Also, to eliminate decimal places, I'll change `number_format()` to use zero decimal places. For example, `number_format($booking['room_price'])` becomes `number_format($booking['room_price'], 0)`.

I'll go through each occurrence:
- `room_price`
- `total_price`
- `paid_amount`
- `remaining`

For each, I'll replace `number_format()` with a version that doesn't include decimals or currency symbols.

I should also ensure that the rest of the code remains unchanged to avoid introducing errors. After making these changes, I'll review the code to confirm that all specified modifications are correctly applied.

Finally, I'll present the updated code to the user, explaining the changes made to ensure clarity and correctness.



لديك هنا التعديلات التي طلبتها:

\`\`\`php
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
        <a href="../dashboard.php" class="btn btn-outline-primary fw-bold">
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
