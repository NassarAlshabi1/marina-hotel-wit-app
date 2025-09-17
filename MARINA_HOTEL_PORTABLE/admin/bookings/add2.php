<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';
$conn->set_charset("utf8mb4");

// قائمة الجنسيات المحددة
$nationalities = ['يمني', 'صومالي', 'إثيوبي', 'جبوتي', 'سوداني', 'سوري', 'مصري'];

// جلب الغرف المتاحة
$rooms = [];
$rooms_query = $conn->query("SELECT room_number FROM rooms WHERE status = 'شاغرة'");
if ($rooms_query && $rooms_query->num_rows > 0) {
    while ($row = $rooms_query->fetch_assoc()) {
        $rooms[] = $row['room_number'];
    }
}

// معالجة نموذج الحجز
if ($_SERVER["REQUEST_METHOD"] === "POST") {
    $required_fields = [
        'guest_name' => 'اسم النزيل',
        'guest_id_type' => 'نوع الهوية',
        'guest_id_number' => 'رقم الهوية',
        'guest_id_issue_date' => 'تاريخ إصدار الهوية',
        'guest_id_issue_place' => 'مكان إصدار الهوية',
        'guest_phone' => 'رقم الهاتف',
        'guest_nationality' => 'الجنسية',
        'checkin_date' => 'تاريخ الوصول',
        'room_number' => 'رقم الغرفة'
    ];

    foreach ($required_fields as $field => $name) {
        if (empty($_POST[$field])) {
            $errors[] = "حقل {$name} مطلوب";
        }
    }

    if (empty($errors)) {
        $conn->begin_transaction();

        try {
            // جمع وتعقيم البيانات
            $guest_name = sanitize_input($_POST['guest_name']);
            $guest_id_type = sanitize_input($_POST['guest_id_type']);
            $guest_id_number = sanitize_input($_POST['guest_id_number']);
            $guest_id_issue_date = sanitize_input($_POST['guest_id_issue_date']);
            $guest_id_issue_place = sanitize_input($_POST['guest_id_issue_place']);
            $guest_phone = sanitize_input($_POST['guest_phone']);
            $guest_nationality = sanitize_input($_POST['guest_nationality']);
            $guest_email = !empty($_POST['guest_email']) ? sanitize_input($_POST['guest_email']) : null;
            $guest_address = !empty($_POST['guest_address']) ? sanitize_input($_POST['guest_address']) : null;
            $checkin_date = sanitize_input($_POST['checkin_date']);
            $checkout_date = !empty($_POST['checkout_date']) ? sanitize_input($_POST['checkout_date']) : null;
            $notes = !empty($_POST['notes']) ? sanitize_input($_POST['notes']) : null;
            $room_number = sanitize_input($_POST['room_number']);
            $status = 'محجوزة';

            // حساب عدد الليالي
            $calculated_nights = 1;
            if (!empty($checkout_date)) {
                $stmt = $conn->prepare("SELECT 
                    CASE 
                        WHEN TIME(?) >= '13:00:00' THEN DATEDIFF(DATE(?), ?) + 1
                        ELSE DATEDIFF(DATE(?), ?)
                    END AS nights");
                $stmt->bind_param('sssss', $checkout_date, $checkout_date, $checkin_date, $checkout_date, $checkin_date);
                $stmt->execute();
                $nights_result = $stmt->get_result();
                $calculated_nights = ($nights_result->num_rows > 0) ? intval($nights_result->fetch_assoc()['nights']) : 1;
                $stmt->close();
            }

            // إدراج الحجز
            $stmt_booking = $conn->prepare("INSERT INTO bookings 
                (guest_name, guest_id_type, guest_id_number, guest_id_issue_date, guest_id_issue_place,
                 guest_phone, guest_nationality, guest_email, guest_address, room_number, 
                 checkin_date, checkout_date, status, notes, calculated_nights) 
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)");

            if (!$stmt_booking) {
                throw new Exception("خطأ في تحضير استعلام الحجز: " . $conn->error);
            }

            $stmt_booking->bind_param(
                "ssssssssssssssi", 
                $guest_name,
                $guest_id_type,
                $guest_id_number,
                $guest_id_issue_date,
                $guest_id_issue_place,
                $guest_phone,
                $guest_nationality,
                $guest_email,
                $guest_address,
                $room_number,
                $checkin_date,
                $checkout_date,
                $status,
                $notes,
                $calculated_nights
            );

            if (!$stmt_booking->execute()) {
                throw new Exception("خطأ أثناء إنشاء الحجز: " . $stmt_booking->error);
            }

            $booking_id = $conn->insert_id;

            // تحديث guest_id
            $conn->query("UPDATE bookings SET guest_id = $booking_id WHERE booking_id = $booking_id");

            // تحديث حالة الغرفة
            $conn->query("UPDATE rooms SET status = 'محجوزة' WHERE room_number = '$room_number'");

            $conn->commit();

            $_SESSION['success'] = "تم حفظ الحجز بنجاح. رقم الحجز: " . $booking_id;
            header("Location: list.php");
            exit();

        } catch (Exception $e) {
            $conn->rollback();
            $errors[] = "خطأ أثناء إنشاء الحجز: " . $e->getMessage();
        }
    }
}
?>

<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title> اضافة حجز جديد</title>
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
            font-weight: 600; /* زيادة سماكة الخط العام */
        }
        .card {
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .form-label {
            font-weight: 600; /* زيادة سماكة تسميات الحقول */
        }
        .form-label.required:after {
            content: " *";
            color: red;
        }
        .btn-submit {
            background-color: #28a745;
            border-color: #28a745;
            font-weight: 600; /* زيادة سماكة نص الأزرار */
        }
        .page-title {
            font-size: 1.5rem;
            font-weight: 700; /* زيادة سماكة العنوان الرئيسي */
        }
        .card-header h4 {
            font-weight: 700; /* زيادة سماكة عنوان البطاقة */
        }
        .form-control, .form-select {
            font-weight: 500; /* سماكة متوسطة لنص الحقول */
        }
        .alert {
            font-weight: 600; /* زيادة سماكة نص التنبيهات */
        }
        @media (max-width: 768px) {
            .container {
                padding: 15px;
            }
        }
    </style>
    <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700&display=swap" rel="stylesheet">
</head>
<body>
    <div class="container py-4">
        <!-- باقي الكود يبقى كما هو -->
    </div>
</body>
</html>

    <div class="container py-4">
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h2 class="mb-0 text-primary small-title">
                <i class="fas fa-plus-circle me-2"></i>إضافة حجز جديد
            </h2>
            <a href="../dashboard.php" class="btn btn-outline-primary">
                <i class="fas fa-arrow-left me-2"></i>العودة
            </a>
        </div>

        <?php if (!empty($errors)): ?>
        <div class="alert alert-danger">
            <h5 class="alert-heading">حدثت الأخطاء التالية:</h5>
            <ul>
                <?php foreach ($errors as $error): ?>
                <li><?php echo $error; ?></li>
                <?php endforeach; ?>
            </ul>
        </div>
        <?php endif; ?>

        <div class="card">
            <div class="card-header bg-primary text-white">
                <h4 class="mb-0 small-title">
                    <i class="fas fa-door-open me-2"></i>
                    بيانات الحجز
                </h4>
            </div>
            <div class="card-body">
                <form method="post">
                    <div class="row g-3 mb-4">
                        <div class="col-md-6">
                            <label for="guest_name" class="form-label required">اسم الضيف</label>
                            <input type="text" class="form-control" id="guest_name" name="guest_name" required
                                   value="<?php echo htmlspecialchars($_POST['guest_name'] ?? ''); ?>">
                        </div>

                        <div class="col-md-6">
                            <label for="guest_nationality" class="form-label required">الجنسية</label>
                            <select class="form-select" id="guest_nationality" name="guest_nationality" required>
                                <option value="">اختر الجنسية</option>
                                <?php foreach ($nationalities as $nationality): ?>
                                <option value="<?php echo $nationality; ?>"
                                    <?php if (($_POST['guest_nationality'] ?? '') === $nationality) echo 'selected'; ?>>
                                    <?php echo $nationality; ?>
                                </option>
                                <?php endforeach; ?>
                            </select>
                        </div>

                        <div class="col-md-6">
                            <label for="guest_phone" class="form-label required">رقم الهاتف</label>
                            <input type="tel" class="form-control" id="guest_phone" name="guest_phone" required
                                   value="<?php echo htmlspecialchars($_POST['guest_phone'] ?? ''); ?>">
                        </div>

                        <div class="col-md-6">
                            <label for="guest_email" class="form-label">البريد الإلكتروني</label>
                            <input type="email" class="form-control" id="guest_email" name="guest_email"
                                   value="<?php echo htmlspecialchars($_POST['guest_email'] ?? ''); ?>">
                        </div>

                        <div class="col-md-4">
                            <label for="guest_id_type" class="form-label required">نوع الهوية</label>
                            <select class="form-select" id="guest_id_type" name="guest_id_type" required>
                                <option value="">اختر نوع الهوية</option>
                                <option value="بطاقة شخصية" <?php if (($_POST['guest_id_type'] ?? '') === 'بطاقة شخصية') echo 'selected'; ?>>بطاقة شخصية</option>
                                <option value="جواز سفر" <?php if (($_POST['guest_id_type'] ?? '') === 'جواز سفر') echo 'selected'; ?>>جواز سفر</option>
                                <option value="رخصة قيادة" <?php if (($_POST['guest_id_type'] ?? '') === 'رخصة قيادة') echo 'selected'; ?>>رخصة قيادة</option>
                            </select>
                        </div>

                        <div class="col-md-4">
                            <label for="guest_id_number" class="form-label required">رقم الهوية</label>
                            <input type="text" class="form-control" id="guest_id_number" name="guest_id_number" required
                                   value="<?php echo htmlspecialchars($_POST['guest_id_number'] ?? ''); ?>">
                        </div>

                        <div class="col-md-4">
                            <label for="guest_id_issue_date" class="form-label required">تاريخ الإصدار</label>
                            <input type="date" class="form-control" id="guest_id_issue_date" name="guest_id_issue_date" required
                                   value="<?php echo htmlspecialchars($_POST['guest_id_issue_date'] ?? ''); ?>">
                        </div>

                        <div class="col-md-6">
                            <label for="guest_id_issue_place" class="form-label required">مكان الإصدار</label>
                            <input type="text" class="form-control" id="guest_id_issue_place" name="guest_id_issue_place" required
                                   value="<?php echo htmlspecialchars($_POST['guest_id_issue_place'] ?? ''); ?>">
                        </div>

                        <div class="col-md-6">
                            <label for="guest_address" class="form-label">العنوان</label>
                            <textarea class="form-control" id="guest_address" name="guest_address" rows="2"><?php echo htmlspecialchars($_POST['guest_address'] ?? ''); ?></textarea>
                        </div>

                        <div class="col-md-6">
                            <label for="checkin_date" class="form-label required">تاريخ الوصول</label>
                            <input type="date" class="form-control" id="checkin_date" name="checkin_date" required
                                   value="<?php echo htmlspecialchars($_POST['checkin_date'] ?? date('Y-m-d')); ?>">
                        </div>

                        <div class="col-md-6">
                            <label for="checkout_date" class="form-label">تاريخ المغادرة</label>
                            <input type="date" class="form-control" id="checkout_date" name="checkout_date"
                                   value="<?php echo htmlspecialchars($_POST['checkout_date'] ?? ''); ?>">
                        </div>

                        <div class="col-md-8">
                            <label for="notes" class="form-label">ملاحظات</label>
                            <textarea class="form-control" id="notes" name="notes" rows="3"><?php echo htmlspecialchars($_POST['notes'] ?? ''); ?></textarea>
                        </div>

                        <div class="col-md-4">
                            <label for="room_number" class="form-label required">رقم الغرفة</label>
                            <select class="form-select" id="room_number" name="room_number" required>
                                <option value="">اختر غرفة</option>
                                <?php foreach ($rooms as $room): ?>
                                    <option value="<?php echo $room; ?>"
                                        <?php if (($_POST['room_number'] ?? '') === $room) echo 'selected'; ?>>
                                        <?php echo $room; ?>
                                    </option>
                                <?php endforeach; ?>
                            </select>
                        </div>
                    </div>

                    <div class="text-center">
                        <button type="submit" class="btn btn-primary px-5">
                            <i class="fas fa-save me-2"></i>حفظ الحجز
                        </button>
                        <a href="list.php" class="btn btn-secondary px-4">
                            <i class="fas fa-times me-2"></i>إلغاء
                        </a>
                    </div>
                </form>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // التحقق من صحة التواريخ
        document.addEventListener('DOMContentLoaded', function() {
            const checkinDate = document.getElementById('checkin_date');
            const checkoutDate = document.getElementById('checkout_date');

            checkinDate.addEventListener('change', function() {
                if (checkoutDate.value && new Date(checkoutDate.value) < new Date(this.value)) {
                    alert('تاريخ المغادرة لا يمكن أن يكون قبل تاريخ الوصول');
                    checkoutDate.value = '';
                }
            });

            checkoutDate.addEventListener('change', function() {
                if (checkinDate.value && new Date(this.value) < new Date(checkinDate.value)) {
                    alert('تاريخ المغادرة لا يمكن أن يكون
