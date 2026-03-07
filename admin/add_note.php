<?php
// إنشاء ملف لإضافة ملاحظات وتنبيهات للموظفين
include_once '../../includes/db.php';
include_once '../../includes/header.php';

// التحقق من وجود معرف الحجز
if (!isset($_GET['id']) || empty($_GET['id'])) {
    header("Location: list.php?error=يجب تحديد الحجز");
    exit;
}

$booking_id = $_GET['id'];

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// التحقق من وجود جدول booking_notes
$check_table = $conn->query("SHOW TABLES LIKE 'booking_notes'");
if ($check_table->num_rows == 0) {
    $error_message = "جدول ملاحظات الحجوزات (booking_notes) غير موجود. يرجى تنفيذ ملف SQL لإنشاء الجدول أولاً.";
} else {
    // جلب بيانات الحجز مباشرة من جدول bookings
    $booking_query = "SELECT * FROM bookings WHERE booking_id = ?";
    $stmt = $conn->prepare($booking_query);
    
    // التحقق من نجاح عملية prepare
    if ($stmt === false) {
        $error_message = "خطأ في استعلام SQL: " . $conn->error;
    } else {
        $stmt->bind_param("i", $booking_id);
        $stmt->execute();
        $booking_result = $stmt->get_result();
        
        if ($booking_result->num_rows === 0) {
            header("Location: list.php?error=الحجز غير موجود");
            exit;
        }
        
        $booking = $booking_result->fetch_assoc();
        
        // معالجة إضافة ملاحظة جديدة
        if ($_SERVER['REQUEST_METHOD'] === 'POST') {
            $note_text = $_POST['note_text'];
            $alert_type = $_POST['alert_type'];
            $alert_until = !empty($_POST['alert_until']) ? $_POST['alert_until'] : null;
            
            // إضافة الملاحظة إلى قاعدة البيانات
            $insert_query = "INSERT INTO booking_notes (booking_id, note_text, alert_type, alert_until, created_at) 
                            VALUES (?, ?, ?, ?, NOW())";
            $insert_stmt = $conn->prepare($insert_query);
            
            // التحقق من نجاح عملية prepare
            if ($insert_stmt === false) {
                $error_message = "خطأ في استعلام SQL لإضافة الملاحظة: " . $conn->error;
            } else {
                $insert_stmt->bind_param("isss", $booking_id, $note_text, $alert_type, $alert_until);
                
                if ($insert_stmt->execute()) {
                    header("Location: list.php?success=تمت إضافة الملاحظة بنجاح");
                    exit;
                } else {
                    $error_message = "حدث خطأ أثناء إضافة الملاحظة: " . $insert_stmt->error;
                }
                
                $insert_stmt->close();
            }
        }
    }
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إضافة ملاحظة للنزيل</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
        }
        .card {
            border-radius: 15px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
        }
        .card-header {
            border-radius: 15px 15px 0 0 !important;
            font-weight: bold;
        }
        .form-label {
            font-weight: bold;
        }
        .alert-type-high {
            background-color: #f8d7da;
            border-color: #f5c2c7;
            color: #842029;
        }
        .alert-type-medium {
            background-color: #fff3cd;
            border-color: #ffecb5;
            color: #664d03;
        }
        .alert-type-low {
            background-color: #d1e7dd;
            border-color: #badbcc;
            color: #0f5132;
        }
    </style>
</head>
<body>
    <div class="container py-4">
        <div class="row justify-content-center">
            <div class="col-md-8">
                <div class="d-flex justify-content-between mb-3">
                    <a href="list.php" class="btn btn-outline-primary fw-bold">
                        ← العودة إلى قائمة الحجوزات
                    </a>
                </div>

                <?php if (isset($error_message)): ?>
                    <div class="alert alert-danger text-center" role="alert">
                        <?= htmlspecialchars($error_message); ?>
                    </div>
                <?php endif; ?>

                <?php if (!isset($error_message) || strpos($error_message, "جدول ملاحظات الحجوزات") === false): ?>
                <div class="card">
                    <div class="card-header bg-primary text-white">
                        <h4 class="mb-0">إضافة ملاحظة وتنبيه للنزيل</h4>
                    </div>
                    <div class="card-body">
                        <div class="mb-4">
                            <h5>معلومات الحجز:</h5>
                            <?php if (isset($booking)): ?>
                            <p><strong>اسم النزيل:</strong> <?= htmlspecialchars($booking['guest_name'] ?? 'غير محدد'); ?></p>
                            <p><strong>رقم الغرفة:</strong> <?= htmlspecialchars($booking['room_number'] ?? 'غير محدد'); ?></p>
                            <p><strong>تاريخ الوصول:</strong> <?= htmlspecialchars($booking['checkin_date'] ?? 'غير محدد'); ?></p>
                            <?php else: ?>
                            <p>لا يمكن عرض معلومات الحجز.</p>
                            <?php endif; ?>
                        </div>

                        <form method="POST" action="">
                            <div class="mb-3">
                                <label for="note_text" class="form-label">نص الملاحظة / التنبيه:</label>
                                <textarea class="form-control" id="note_text" name="note_text" rows="4" required
                                    placeholder="مثال: النزيل أخذ بطاقة الغرفة الساعة 2 مساءً، يرجى استعادتها عند عودته"></textarea>
                            </div>

                            <div class="mb-3">
                                <label for="alert_type" class="form-label">مستوى أهمية التنبيه:</label>
                                <select class="form-select" id="alert_type" name="alert_type" required>
                                    <option value="high">عالي (أحمر)</option>
                                    <option value="medium">متوسط (برتقالي)</option>
                                    <option value="low">منخفض (أخضر)</option>
                                </select>
                            </div>

                            <div class="mb-3">
                                <label for="alert_until" class="form-label">عرض التنبيه حتى تاريخ:</label>
                                <input type="datetime-local" class="form-control" id="alert_until" name="alert_until">
                                <small class="text-muted">اترك هذا الحقل فارغاً إذا كنت تريد عرض التنبيه حتى يتم إلغاؤه يدوياً</small>
                            </div>

                            <div class="d-grid gap-2">
                                <button type="submit" class="btn btn-primary fw-bold">
                                    <i class="fas fa-save me-1"></i> حفظ الملاحظة والتنبيه
                                </button>
                            </div>
                        </form>
                    </div>
                </div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>

<?php
if (isset($stmt) && $stmt !== false) {
    $stmt->close();
}
$conn->close();
?>
