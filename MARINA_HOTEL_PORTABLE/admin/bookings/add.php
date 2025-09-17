<?php
// تفعيل عرض الأخطاء

// تضمين ملفات النظام
require_once __DIR__ . '/../../includes/db.php';
require_once __DIR__ . '/../../includes/auth.php';

// الجلسة تبدأ تلقائياً عبر auth.php

// إنشاء توكن الحماية
if (empty($_SESSION['csrf_token'])) {
    $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
}

// تأمين معالجة البيانات
function sanitize_input($data) {
    return htmlspecialchars(stripslashes(trim($data)));
}

function validate_date($date) {
    return (DateTime::createFromFormat('Y-m-d', $date) !== false);
}

// تحقق من رقم الغرفة
if (!isset($_GET['room_number']) || !is_numeric($_GET['room_number'])) {
    $_SESSION['error'] = "رقم الغرفة غير صالح";
    header("Location: ../dashboard.php");
    exit();
}

$roomNumber = (int)$_GET['room_number'];
$errors = [];
$nationalities = ['يمني', 'هندي', 'إثيوبي', 'صومالي', 'جبوتي'];

// التحقق من حالة الغرفة باستخدام prepared statement
$stmt = $conn->prepare("SELECT status FROM rooms WHERE room_number = ?");
$stmt->bind_param("i", $roomNumber);
$stmt->execute();
$roomCheck = $stmt->get_result();

if ($roomCheck->num_rows === 0) {
    $_SESSION['error'] = "الغرفة غير موجودة";
    header("Location: ../dashboard.php");
    exit();
}

$roomStatus = $roomCheck->fetch_assoc()['status'];
if ($roomStatus !== 'شاغرة') {
    $_SESSION['error'] = "هذه الغرفة محجوزة ولا يمكن حجزها";
    header("Location: ../dashboard.php");
    exit();
}
$stmt->close();

// معالجة نموذج الحجز
if ($_SERVER["REQUEST_METHOD"] === "POST") {
    // التحقق من CSRF token
    if (!isset($_POST['csrf_token']) || $_POST['csrf_token'] !== $_SESSION['csrf_token']) {
        die("طلب غير صالح");
    }

    $required_fields = [
        'guest_name' => 'اسم النزيل',
        'guest_id_type' => 'نوع الهوية',
        'guest_id_number' => 'رقم الهوية',
        'guest_id_issue_date' => 'تاريخ إصدار الهوية',
        'guest_id_issue_place' => 'مكان إصدار الهوية',
        'guest_phone' => 'رقم الهاتف',
        'guest_nationality' => 'الجنسية',
        'checkin_date' => 'تاريخ الوصول'
    ];

    foreach ($required_fields as $field => $name) {
        if (empty($_POST[$field])) {
            $errors[] = "حقل {$name} مطلوب";
        }
    }

    if (empty($errors)) {
        // جمع وتعقيم البيانات
        $guest_name = sanitize_input($_POST['guest_name']);
        $guest_id_type = sanitize_input($_POST['guest_id_type']);
        $guest_id_number = sanitize_input($_POST['guest_id_number']);
        $guest_id_issue_date = sanitize_input($_POST['guest_id_issue_date']);
        $guest_id_issue_place = sanitize_input($_POST['guest_id_issue_place']);
        $guest_phone = '967' . preg_replace('/[^0-9]/', '', $_POST['guest_phone']);
        $guest_nationality = sanitize_input($_POST['guest_nationality']);
        $guest_email = !empty($_POST['guest_email']) ? sanitize_input($_POST['guest_email']) : null;
        $guest_address = !empty($_POST['guest_address']) ? sanitize_input($_POST['guest_address']) : null;
        $checkin_date = sanitize_input($_POST['checkin_date']);
        $checkout_date = !empty($_POST['checkout_date']) ? sanitize_input($_POST['checkout_date']) : null;
        $notes = !empty($_POST['notes']) ? sanitize_input($_POST['notes']) : null;
        $status = 'محجوزة';

        // التحقق من صحة التواريخ
        if (!validate_date($checkin_date)) {
            $errors[] = "تاريخ الوصول غير صالح";
        }

        if ($checkout_date && !validate_date($checkout_date)) {
            $errors[] = "تاريخ المغادرة غير صالح";
        }

        if ($checkout_date && strtotime($checkout_date) < strtotime($checkin_date)) {
            $errors[] = "تاريخ المغادرة لا يمكن أن يكون قبل تاريخ الوصول";
        }

        if ($guest_email && !filter_var($guest_email, FILTER_VALIDATE_EMAIL)) {
            $errors[] = "صيغة البريد الإلكتروني غير صالحة";
        }

        if (empty($errors)) {
            $conn->begin_transaction();

            try {
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
                    $roomNumber,
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
                $stmt_update = $conn->prepare("UPDATE bookings SET guest_id = ? WHERE booking_id = ?");
                $stmt_update->bind_param("ii", $booking_id, $booking_id);
                if (!$stmt_update->execute()) {
                    throw new Exception("خطأ أثناء تعيين guest_id: " . $stmt_update->error);
                }

                // تحديث حالة الغرفة
                $stmt_room = $conn->prepare("UPDATE rooms SET status = 'محجوزة' WHERE room_number = ?");
                $stmt_room->bind_param("i", $roomNumber);
                if (!$stmt_room->execute()) {
                    throw new Exception("خطأ أثناء تحديث حالة الغرفة: " . $stmt_room->error);
                }

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
}

// جلب قائمة الغرف الشاغرة
$stmt = $conn->prepare("
    SELECT room_number, type, price 
    FROM rooms 
    WHERE status = 'شاغرة' OR room_number = ?
    ORDER BY room_number
");
$stmt->bind_param("i", $roomNumber);
$stmt->execute();
$rooms_result = $stmt->get_result();

?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إضافة حجز جديد - غرفة <?php echo $roomNumber; ?></title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
        }
        .card {
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
        }
        .form-label.required:after {
            content: " *";
            color: red;
        }
        .btn-submit {
            background-color: #28a745;
            border-color: #28a745;
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
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h2 class="mb-0 text-primary">
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
                <h4 class="mb-0">
                    <i class="fas fa-door-open me-2"></i>
                    غرفة <?php echo $roomNumber; ?>
                </h4>
            </div>
            <div class="card-body">
                <form method="post">
                    <input type="hidden" name="csrf_token" value="<?= $_SESSION['csrf_token'] ?>">
                    <input type="hidden" name="room_number" value="<?php echo $roomNumber; ?>">

                    <div class="row g-3 mb-4">
                        <div class="col-md-6">
                            <label for="guest_name" class="form-label required">اسم النزيل</label>
                            <input type="text" class="form-control" id="guest_name" name="guest_name" required
                                   value="<?php echo htmlspecialchars($_POST['guest_name'] ?? ''); ?>">
                        </div>

                        <div class="col-md-6">
                            <label for="guest_nationality" class="form-label required">الجنسية</label>
                            <select class="form-select" id="guest_nationality" name="guest_nationality" required>
                            
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

                        <div class="col-12">
                            <label for="notes" class="form-label">ملاحظات</label>
                            <textarea class="form-control" id="notes" name="notes" rows="3"><?php echo htmlspecialchars($_POST['notes'] ?? ''); ?></textarea>
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
                    alert('تاريخ المغادرة لا يمكن أن يكون قبل تاريخ الوصول');
                    this.value = '';
                }
            });
        });
    </script>
</body>
</html>
<?php
$conn->close();
?>

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
