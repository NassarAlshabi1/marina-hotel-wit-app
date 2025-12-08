<?php
// إنشاء ملف لإضافة ملاحظات وتنبيهات للموظفين
include_once '../../includes/db.php';

// التحقق من وجود معرف الحجز
if (!isset($_GET['id']) || empty($_GET['id'])) {
    header("Location: list.php?error=يجب تحديد الحجز");
    exit;
}

include_once '../../includes/header.php';

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
        
        // معالجة حذف التنبيه
        if (isset($_POST['delete_note']) && isset($_POST['note_id'])) {
            $note_id = $_POST['note_id'];
            
            // حذف التنبيه من قاعدة البيانات
            $delete_query = "DELETE FROM booking_notes WHERE note_id = ? AND booking_id = ?";
            $delete_stmt = $conn->prepare($delete_query);
            
            if ($delete_stmt === false) {
                $error_message = "خطأ في استعلام SQL لحذف التنبيه: " . $conn->error;
            } else {
                $delete_stmt->bind_param("ii", $note_id, $booking_id);
                
                if ($delete_stmt->execute()) {
                    header("Location: list.php?success=تم حذف التنبيه بنجاح");
                    exit;
                } else {
                    $error_message = "حدث خطأ أثناء حذف التنبيه: " . $delete_stmt->error;
                }
                
                $delete_stmt->close();
            }
        }
        
        // معالجة إضافة ملاحظة جديدة
        if ($_SERVER['REQUEST_METHOD'] === 'POST' && !isset($_POST['delete_note'])) {
            $note_text = $_POST['note_text'];
            $alert_type = $_POST['alert_type'];
            
            // إضافة الملاحظة إلى قاعدة البيانات - مدة التنبيه تلقائية بنفس وقت الإنشاء
            $insert_query = "INSERT INTO booking_notes (booking_id, note_text, alert_type, created_at) 
                            VALUES (?, ?, ?, NOW())";
            $insert_stmt = $conn->prepare($insert_query);
            
            // التحقق من نجاح عملية prepare
            if ($insert_stmt === false) {
                $error_message = "خطأ في استعلام SQL لإضافة الملاحظة: " . $conn->error;
            } else {
                $insert_stmt->bind_param("iss", $booking_id, $note_text, $alert_type);
                
                if ($insert_stmt->execute()) {
                    header("Location: list.php?success=تمت إضافة الملاحظة بنجاح");
                    exit;
                } else {
                    $error_message = "حدث خطأ أثناء إضافة الملاحظة: " . $insert_stmt->error;
                }
                
                $insert_stmt->close();
            }
        }
        
        // جلب التنبيهات الحالية للحجز
        $notes_query = "SELECT * FROM booking_notes WHERE booking_id = ? ORDER BY created_at DESC";
        $notes_stmt = $conn->prepare($notes_query);
        $notes = [];
        
        if ($notes_stmt !== false) {
            $notes_stmt->bind_param("i", $booking_id);
            $notes_stmt->execute();
            $notes_result = $notes_stmt->get_result();
            
            while ($note = $notes_result->fetch_assoc()) {
                $notes[] = $note;
            }
            
            $notes_stmt->close();
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
        .note-item {
            border-radius: 10px;
            padding: 15px;
            margin-bottom: 15px;
        }
        .note-actions {
            display: flex;
            justify-content: flex-end;
        }
        .delete-btn {
            color: #dc3545;
            background: none;
            border: none;
            cursor: pointer;
            font-size: 1.1rem;
        }
        .delete-btn:hover {
            color: #bb2d3b;
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
                            <p><strong>تاريخ الوصول:</strong> <?= $booking['checkin_date'] ? date('d/m/Y', strtotime($booking['checkin_date'])) : 'غير محدد'; ?></p>
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

                            <div class="d-grid gap-2">
                                <button type="submit" class="btn btn-primary fw-bold">
                                    <i class="fas fa-save me-1"></i> حفظ الملاحظة والتنبيه
                                </button>
                            </div>
                        </form>
                    </div>
                </div>

                <?php if (!empty($notes)): ?>
                <div class="card mt-4">
                    <div class="card-header bg-info text-white">
                        <h4 class="mb-0">التنبيهات الحالية</h4>
                    </div>
                    <div class="card-body">
                        <?php foreach ($notes as $note): ?>
                            <div class="note-item alert-type-<?= htmlspecialchars($note['alert_type']); ?>">
                                <div class="note-actions">
                                    <form method="POST" action="" onsubmit="return confirm('هل أنت متأكد من حذف هذا التنبيه؟');">
                                        <input type="hidden" name="note_id" value="<?= $note['note_id']; ?>">
                                        <button type="submit" name="delete_note" class="delete-btn" title="حذف التنبيه">
                                            <i class="fas fa-trash-alt"></i>
                                        </button>
                                    </form>
                                </div>
                                <p><strong>التنبيه:</strong> <?= htmlspecialchars($note['note_text']); ?></p>
                                <p><strong>تاريخ الإنشاء:</strong> <?= htmlspecialchars($note['created_at']); ?></p>
                                <p><strong>مستوى الأهمية:</strong> 
                                    <?php 
                                    $alert_types = [
                                        'high' => 'عالي',
                                        'medium' => 'متوسط',
                                        'low' => 'منخفض'
                                    ];
                                    echo $alert_types[$note['alert_type']] ?? $note['alert_type'];
                                    ?>
                                </p>
                            </div>
                        <?php endforeach; ?>
                    </div>
                </div>
                <?php endif; ?>
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
