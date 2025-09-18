<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// التحقق من وجود رقم الغرفة
if (!isset($_GET['room_number']) || empty($_GET['room_number'])) {
    $_SESSION['error'] = "لم يتم تحديد غرفة صالحة للتعديل";
    header("Location: list.php");
    exit();
}
$room_number = urldecode($_GET['room_number']);

// جلب بيانات الغرفة
$stmt = $conn->prepare("SELECT * FROM rooms WHERE room_number = ?");
$stmt->bind_param("s", $room_number);
$stmt->execute();
$result = $stmt->get_result();

if ($result->num_rows === 0) {
    $_SESSION['error'] = "الغرفة غير موجودة";
    header("Location: list.php");
    exit();
}

$room = $result->fetch_assoc();

// معالجة تحديث البيانات
if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $new_room_number = trim($_POST['room_number']);
    $type = $_POST['type'];
    $price = floatval($_POST['price']);
    $status = $_POST['status'];

    // التحقق من عدم تكرار رقم الغرفة (إذا تم تغييره)
    if ($new_room_number !== $room_number) {
        $check = $conn->prepare("SELECT room_number FROM rooms WHERE room_number = ?");
        $check->bind_param("s", $new_room_number);
        $check->execute();
        
        if ($check->get_result()->num_rows > 0) {
            $message = "<div class='alert alert-danger'>رقم الغرفة الجديد موجود مسبقاً!</div>";
        }
    }

    if (!isset($message)) {
        $update = $conn->prepare("UPDATE rooms SET 
                                room_number = ?, 
                                type = ?, 
                                price = ?, 
                                status = ? 
                                WHERE room_number = ?");
        $update->bind_param("ssdss", $new_room_number, $type, $price, $status, $room_number);
        
        if ($update->execute()) {
            $_SESSION['success'] = "تم تحديث بيانات الغرفة بنجاح";
         //   header("Location: list.php");
            exit();
        } else {
            $message = "<div class='alert alert-danger'>حدث خطأ أثناء التحديث: " . $conn->error . "</div>";
        }
    }
}

// تضمين الهيدر بعد انتهاء معالجة POST
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-edit me-2"></i>تعديل بيانات الغرفة</h2>
                <div>
                    <a href="list.php" class="btn btn-outline-secondary">
                        <i class="fas fa-arrow-left me-1"></i>العودة للقائمة
                    </a>
                </div>
            </div>
        </div>
    </div>

    <?php if (isset($message)) echo $message; ?>

    <style>
        .form-control, .form-select {
            font-weight: bold !important;
        }
        .form-label {
            font-weight: bold !important;
        }
    </style>

    <form method="post" class="border p-4 rounded bg-light">
        <div class="mb-3">
            <label class="form-label">رقم الغرفة *</label>
            <input type="text" name="room_number" class="form-control" 
                   value="<?= htmlspecialchars($room['room_number']) ?>" required>
        </div>
        
        <div class="mb-3">
            <label class="form-label">نوع الغرفة *</label>
            <select name="type" class="form-select" required>
                <option value="سرير عائلي" <?= $room['type'] == 'سرير عائلي' ? 'selected' : '' ?>>سرير عائلي</option>
                <option value="سرير فردي" <?= $room['type'] == 'سرير فردي' ? 'selected' : '' ?>>سرير فردي</option>
            </select>
        </div>
        
        <div class="mb-3">
            <label class="form-label">السعر *</label>
            <input type="number" step="0.01" name="price" class="form-control"
                   value="<?= htmlspecialchars($room['price']) ?>" required>
        </div>
        
        <div class="mb-3">
            <label class="form-label">الحالة *</label>
            <select name="status" class="form-select" required>
                <option value="شاغرة" <?= $room['status'] == 'شاغرة' ? 'selected' : '' ?>>شاغرة</option>
                <option value="محجوزة" <?= $room['status'] == 'محجوزة' ? 'selected' : '' ?>>محجوزة</option>
                <option value="صيانة" <?= $room['status'] == 'صيانة' ? 'selected' : '' ?>>صيانة</option>
            </select>
        </div>
        
        <div class="text-center">
            <button type="submit" class="btn btn-primary px-4">
                <i class="fas fa-save"></i> حفظ التغييرات
            </button>
            <a href="list.php" class="btn btn-secondary px-4">
                <i class="fas fa-times"></i> إلغاء
            </a>
        </div>
    </form>
</div>

<?php include_once '../../includes/footer.php'; ?>
