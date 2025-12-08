<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// التحقق من وجود رقم الغرفة
if (!isset($_GET['room_number']) || empty($_GET['room_number'])) {
    $_SESSION['error'] = "لم يتم تحديد غرفة";
    header("Location: list.php");
    exit();
}

$room_number = urldecode($_GET['room_number']);

// جلب بيانات الغرفة
$stmt = $conn->prepare("SELECT * FROM rooms WHERE room_number = ?");
$stmt->bind_param("s", $room_number);
$stmt->execute();
$result = $stmt->get_result();
$room = $result->fetch_assoc();

if (!$room) {
    $_SESSION['error'] = "الغرفة غير موجودة";
    header("Location: list.php");
    exit();
}

// تضمين الهيدر بعد انتهاء معالجة POST
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <h2 class="mb-4">تفاصيل الغرفة</h2>
    
    <div class="card">
        <div class="card-body">
            <div class="row">
                <div class="col-md-6">
                    <p><strong>رقم الغرفة:</strong> <?= htmlspecialchars($room['room_number']) ?></p>
                    <p><strong>النوع:</strong> <?= htmlspecialchars($room['type']) ?></p>
                </div>
                <div class="col-md-6">
                    <p><strong>السعر:</strong> <?= number_format($room['price'], 2) ?> </p>
                    <p><strong>الحالة:</strong> 
                        <span class="badge <?= [
                            'شاغرة' => 'bg-success',
                            'محجوزة' => 'bg-danger',
                            'صيانة' => 'bg-warning text-dark'
                        ][$room['status']] ?? 'bg-secondary' ?>">
                            <?= htmlspecialchars($room['status']) ?>
                        </span>
                    </p>
                </div>
            </div>
        </div>
    </div>
    
    <div class="mt-3">
        <a href="edit.php?room_number=<?= urlencode($room['room_number']) ?>" class="btn btn-primary">
            <i class="fas fa-edit"></i> تعديل
        </a>
        <a href="list.php" class="btn btn-secondary">
            <i class="fas fa-list"></i> العودة للقائمة
        </a>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
