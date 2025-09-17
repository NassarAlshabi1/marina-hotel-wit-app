<?php 
include_once '../../includes/db.php'; 
include_once '../../includes/header.php';

// التحقق من وجود معرف الحجز
if (!isset($_GET['id']) || !is_numeric($_GET['id'])) {
    die("<div class='alert alert-danger'>معرف الحجز غير صالح</div>");
}

$booking_id = (int)$_GET['id'];

// جلب بيانات الحجز
$stmt = $conn->prepare("SELECT b.id, b.guest_name, b.identity_number, b.identity_type, 
                        b.phone, b.email, b.address, r.id as room_id, r.room_number, 
                        b.checkin_date, b.checkout_date, b.status, b.amount_paid
                        FROM bookings b
                        JOIN rooms r ON b.room_id = r.id
                        WHERE b.id = ?");
$stmt->bind_param("i", $booking_id);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    die("<div class='alert alert-danger'>الحجز غير موجود</div>");
}

$booking = $result->fetch_assoc();

// معالجة تحديث الحجز
if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['submit'])) {
    // تنظيف البيانات المدخلة
    $guest_name = $conn->real_escape_string(trim($_POST['guest_name'] ?? ''));
    $identity_number = $conn->real_escape_string(trim($_POST['identity_number'] ?? ''));
    $identity_type = $conn->real_escape_string(trim($_POST['identity_type'] ?? ''));
    $phone = $conn->real_escape_string(trim($_POST['phone'] ?? ''));
    $email = $conn->real_escape_string(trim($_POST['email'] ?? ''));
    $address = $conn->real_escape_string(trim($_POST['address'] ?? ''));
    $room_id = (int)($_POST['room_id'] ?? 0);
    $checkin_date = $conn->real_escape_string(trim($_POST['checkin_date'] ?? ''));
    $checkout_date = $conn->real_escape_string(trim($_POST['checkout_date'] ?? ''));
    $status = $conn->real_escape_string(trim($_POST['status'] ?? ''));
    $amount_paid = (float)($_POST['amount_paid'] ?? 0);

    // التحقق من البيانات المطلوبة
    if (empty($guest_name) || empty($identity_number) || empty($identity_type) || empty($phone) || $room_id <= 0) {
        $message = "الرجاء تعبئة جميع الحقول المطلوبة";
    } else {
        // تحديث بيانات الحجز
        $update_stmt = $conn->prepare("UPDATE bookings 
                                    SET guest_name = ?, identity_number = ?, identity_type = ?,
                                        phone = ?, email = ?, address = ?, room_id = ?, 
                                        checkin_date = ?, checkout_date = ?, status = ?, amount_paid = ?
                                    WHERE id = ?");
        $update_stmt->bind_param("ssssssisssdi", 
            $guest_name, $identity_number, $identity_type,
            $phone, $email, $address, $room_id,
            $checkin_date, $checkout_date, $status, $amount_paid,
            $booking_id
        );

        if ($update_stmt->execute()) {
            // إدارة حالة الغرف
            if ($room_id != $booking['room_id']) {
                // تحرير الغرفة القديمة
                $conn->query("UPDATE rooms SET status = 'available' WHERE id = {$booking['room_id']}");
                // حجز الغرفة الجديدة
                $conn->query("UPDATE rooms SET status = 'occupied' WHERE id = $room_id");
            }
            
            // إذا كانت الحالة "تم المغادرة"، تحرير الغرفة
            if ($status == 'تم المغادرة') {
                $conn->query("UPDATE rooms SET status = 'available' WHERE id = $room_id");
            }

            $message = "<div class='alert alert-success'>تم تحديث الحجز بنجاح</div>";
            // تحديث بيانات الحجز بعد التعديل
            $booking = array_merge($booking, [
                'guest_name' => $guest_name,
                'identity_number' => $identity_number,
                'identity_type' => $identity_type,
                'phone' => $phone,
                'email' => $email,
                'address' => $address,
                'room_id' => $room_id,
                'checkin_date' => $checkin_date,
                'checkout_date' => $checkout_date,
                'status' => $status,
                'amount_paid' => $amount_paid
            ]);
        } else {
            $message = "<div class='alert alert-danger'>فشل في تحديث الحجز: " . $conn->error . "</div>";
        }
    }
}

// جلب الغرف المتاحة (بالإضافة للغرفة الحالية)
$rooms = $conn->query("SELECT id, room_number, type FROM rooms 
                       WHERE status = 'available' OR id = {$booking['room_id']}");
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تعديل الحجز</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        .form-section {
            background-color: #f8f9fa;
            border-radius: 5px;
            padding: 20px;
            margin-bottom: 20px;
        }
    </style>
</head>
<body>
    <div class="container py-5">
        <h2 class="text-center mb-4">تعديل الحجز رقم: <?= $booking['id'] ?></h2>
        
        <?= $message ?? '' ?>
        
        <form method="POST" class="border rounded p-4 bg-white">
            <div class="form-section">
                <h4 class="mb-3">بيانات النزيل</h4>
                
                <div class="row g-3">
                    <div class="col-md-6">
                        <label class="form-label">الاسم الكامل</label>
                        <input type="text" name="guest_name" class="form-control" required
                               value="<?= htmlspecialchars($booking['guest_name']) ?>">
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">نوع الهوية</label>
                        <select name="identity_type" class="form-select" required>
                            <option value="بطاقة شخصية" <?= $booking['identity_type'] == 'بطاقة شخصية' ? 'selected' : '' ?>>بطاقة شخصية</option>
                            <option value="رخصة قيادة" <?= $booking['identity_type'] == 'رخصة قيادة' ? 'selected' : '' ?>>رخصة قيادة</option>
                            <option value="جواز سفر" <?= $booking['identity_type'] == 'جواز سفر' ? 'selected' : '' ?>>جواز سفر</option>
                            <option value="أخرى" <?= $booking['identity_type'] == 'أخرى' ? 'selected' : '' ?>>أخرى</option>
                        </select>
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">رقم الهوية</label>
                        <input type="text" name="identity_number" class="form-control" required
                               value="<?= htmlspecialchars($booking['identity_number']) ?>">
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">رقم الهاتف</label>
                        <input type="tel" name="phone" class="form-control" required
                               value="<?= htmlspecialchars($booking['phone']) ?>">
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">البريد الإلكتروني</label>
                        <input type="email" name="email" class="form-control"
                               value="<?= htmlspecialchars($booking['email']) ?>">
                    </div>
                    
                    <div class="col-12">
                        <label class="form-label">العنوان</label>
                        <textarea name="address" class="form-control" rows="2"><?= htmlspecialchars($booking['address']) ?></textarea>
                    </div>
                </div>
            </div>

            <div class="form-section">
                <h4 class="mb-3">بيانات الحجز</h4>
                
                <div class="row g-3">
                    <div class="col-md-6">
                        <label class="form-label">الغرفة</label>
                        <select name="room_id" class="form-select" required>
                            <?php while ($room = $rooms->fetch_assoc()): ?>
                                <option value="<?= $room['id'] ?>"
                                    <?= $room['id'] == $booking['room_id'] ? 'selected' : '' ?>>
                                    <?= $room['room_number'] ?> - <?= $room['type'] ?>
                                </option>
                            <?php endwhile; ?>
                        </select>
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">حالة الحجز</label>
                        <select name="status" class="form-select" required>
                            <option value="محجوز" <?= $booking['status'] == 'محجوز' ? 'selected' : '' ?>>محجوز</option>
                            <option value="تم الوصول" <?= $booking['status'] == 'تم الوصول' ? 'selected' : '' ?>>تم الوصول</option>
                            <option value="تم المغادرة" <?= $booking['status'] == 'تم المغادرة' ? 'selected' : '' ?>>تم المغادرة</option>
                        </select>
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">تاريخ الدخول</label>
                        <input type="date" name="checkin_date" class="form-control" required
                               value="<?= date('Y-m-d', strtotime($booking['checkin_date'])) ?>">
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">تاريخ المغادرة</label>
                        <input type="date" name="checkout_date" class="form-control"
                               value="<?= !empty($booking['checkout_date']) ? date('Y-m-d', strtotime($booking['checkout_date'])) : '' ?>">
                    </div>
                    
                    <div class="col-md-6">
                        <label class="form-label">المبلغ المدفوع</label>
                        <input type="number" step="0" name="amount_paid" class="form-control" required
                               value="<?= $booking['amount_paid'] ?>">
                    </div>
                </div>
            </div>

            <div class="text-center mt-4">
                <button type="submit" name="submit" class="btn btn-primary px-4">حفظ التعديلات</button>
                <a href="list.php" class="btn btn-secondary px-4">العودة للقائمة</a>
            </div>
        </form>
    </div>
</body>
</html>
