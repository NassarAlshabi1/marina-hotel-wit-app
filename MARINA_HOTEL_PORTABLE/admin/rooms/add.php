<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

$message = '';
$room_types = ['سرير عائلي', 'سرير فردي'];
$statuses = ['شاغرة', 'محجوزة', 'صيانة']; // الحالات المحددة فقط

if ($_SERVER["REQUEST_METHOD"] == "POST") {
    $room_number = trim($_POST['room_number']);
    $type = $_POST['type'];
    $price = floatval($_POST['price']);
    $status = $_POST['status'];

    // التحقق من صحة البيانات
    if (!in_array($type, $room_types)) {
        $message = "<div class='alert alert-danger'>نوع الغرفة غير صالح</div>";
    } elseif (!in_array($status, $statuses)) {
        $message = "<div class='alert alert-danger'>حالة الغرفة غير صالحة</div>";
    } else {
        // التحقق من عدم تكرار رقم الغرفة
        $check = $conn->prepare("SELECT id FROM rooms WHERE room_number = ?");
        $check->bind_param("s", $room_number);
        $check->execute();
        
        if ($check->get_result()->num_rows > 0) {
            $message = "<div class='alert alert-danger'>رقم الغرفة موجود مسبقاً!</div>";
        } else {
            $stmt = $conn->prepare("INSERT INTO rooms (room_number, type, price, status) 
                                   VALUES (?, ?, ?, ?)");
            $stmt->bind_param("ssds", $room_number, $type, $price, $status);

            if ($stmt->execute()) {
                $message = "<div class='alert alert-success'>تمت إضافة الغرفة رقم $room_number بنجاح</div>";
                $_POST = array(); // إعادة تعيين النموذج
            } else {
                $message = "<div class='alert alert-danger'>حدث خطأ: " . $conn->error . "</div>";
            }
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
                <h2><i class="fas fa-plus-circle me-2"></i>إضافة غرفة جديدة</h2>
                <div>
                    <a href="list.php" class="btn btn-outline-secondary">
                        <i class="fas fa-arrow-left me-1"></i>العودة للقائمة
                    </a>
                </div>
            </div>
        </div>
    </div>

    <?php echo $message; ?>

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
                   value="<?= htmlspecialchars($_POST['room_number'] ?? '') ?>" required>
        </div>
        
        <div class="mb-3">
            <label class="form-label">نوع الغرفة *</label>
            <select name="type" class="form-select" required>
                <?php foreach ($room_types as $room_type): ?>
                <option value="<?= $room_type ?>" 
                    <?= ($_POST['type'] ?? '') == $room_type ? 'selected' : '' ?>>
                    <?= $room_type ?>
                </option>
                <?php endforeach; ?>
            </select>
        </div>
        
        <div class="mb-3">
            <label class="form-label">السعر *</label>
            <input type="number" step="0.01" name="price" class="form-control"
                   value="<?= htmlspecialchars($_POST['price'] ?? '') ?>" required>
        </div>
        
        <div class="mb-3">
            <label class="form-label">الحالة *</label>
            <select name="status" class="form-select" required>
                <?php foreach ($statuses as $status_option): ?>
                <option value="<?= $status_option ?>" 
                    <?= ($_POST['status'] ?? '') == $status_option ? 'selected' : '' ?>>
                    <?= $status_option ?>
                </option>
                <?php endforeach; ?>
            </select>
        </div>
        
        <div class="text-center">
            <button type="submit" class="btn btn-primary px-4">حفظ</button>
            <a href="list.php" class="btn btn-secondary px-4">إلغاء</a>
        </div>
    </form>
</div>

<?php include_once '../../includes/footer.php'; ?>
