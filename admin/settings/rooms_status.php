<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// جلب حالة الغرف مع تفاصيل الحجوزات
$rooms_query = "
    SELECT 
        r.*,
        b.booking_id,
        b.guest_name,
        b.guest_phone,
        b.checkin_date,
        b.checkout_date,
        b.status as booking_status,
        DATEDIFF(COALESCE(b.checkout_date, CURDATE()), b.checkin_date) as stay_duration,
        CASE 
            WHEN b.booking_id IS NOT NULL AND b.status = 'محجوزة' THEN 'محجوزة'
            WHEN r.status = 'خارج الخدمة' THEN 'خارج الخدمة'
            WHEN r.status = 'تحت الصيانة' THEN 'تحت الصيانة'
            ELSE 'شاغرة'
        END as current_status
    FROM rooms r
    LEFT JOIN bookings b ON r.room_number = b.room_number AND b.status = 'محجوزة'
    ORDER BY r.floor, r.room_number
";

$rooms_result = $conn->query($rooms_query);

// إحصائيات الغرف
$stats_query = "
    SELECT 
        COUNT(*) as total_rooms,
        SUM(CASE WHEN r.status = 'شاغرة' AND b.booking_id IS NULL THEN 1 ELSE 0 END) as available_rooms,
        SUM(CASE WHEN b.booking_id IS NOT NULL AND b.status = 'محجوزة' THEN 1 ELSE 0 END) as occupied_rooms,
        SUM(CASE WHEN r.status = 'خارج الخدمة' THEN 1 ELSE 0 END) as out_of_service,
        SUM(CASE WHEN r.status = 'تحت الصيانة' THEN 1 ELSE 0 END) as maintenance_rooms
    FROM rooms r
    LEFT JOIN bookings b ON r.room_number = b.room_number AND b.status = 'محجوزة'
";

$stats = $conn->query($stats_query)->fetch_assoc();

// معالجة تغيير حالة الغرفة
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['change_status'])) {
    $room_number = $_POST['room_number'];
    $new_status = $_POST['new_status'];
    
    $stmt = $conn->prepare("UPDATE rooms SET status = ? WHERE room_number = ?");
    $stmt->bind_param("ss", $new_status, $room_number);
    
    if ($stmt->execute()) {
        $success_message = "تم تغيير حالة الغرفة $room_number إلى $new_status";
        // إعادة تحميل البيانات
        header("Location: rooms_status.php?success=" . urlencode($success_message));
        exit();
    } else {
        $error_message = "حدث خطأ أثناء تغيير حالة الغرفة";
    }
}

// رسالة النجاح من الـ URL
if (isset($_GET['success'])) {
    $success_message = $_GET['success'];
}

// تجميع الغرف حسب الطوابق
$floors = [];
if ($rooms_result->num_rows > 0) {
    while ($room = $rooms_result->fetch_assoc()) {
        $floors[$room['floor']][] = $room;
    }
}

// تضمين الهيدر بعد انتهاء معالجة البيانات
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-chart-bar me-2"></i>حالة الغرف</h2>
                <div>
                    <a href="index.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>العودة للإعدادات
                    </a>
                    <a href="../rooms/list.php" class="btn btn-outline-primary">
                        <i class="fas fa-bed me-1"></i>إدارة الغرف
                    </a>
                </div>
            </div>
        </div>
    </div>

    <?php if (isset($success_message)): ?>
        <div class="alert alert-success alert-dismissible fade show" role="alert">
            <i class="fas fa-check-circle me-2"></i><?= htmlspecialchars($success_message) ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <?php if (isset($error_message)): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="fas fa-exclamation-circle me-2"></i><?= htmlspecialchars($error_message) ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <!-- إحصائيات الغرف -->
    <div class="row mb-4">
        <div class="col-md-2-4">
            <div class="card bg-primary text-white">
                <div class="card-body text-center">
                    <h3><?= $stats['total_rooms'] ?></h3>
                    <p class="mb-0">إجمالي الغرف</p>
                </div>
            </div>
        </div>
        <div class="col-md-2-4">
            <div class="card bg-success text-white">
                <div class="card-body text-center">
                    <h3><?= $stats['available_rooms'] ?></h3>
                    <p class="mb-0">غرف شاغرة</p>
                </div>
            </div>
        </div>
        <div class="col-md-2-4">
            <div class="card bg-warning text-white">
                <div class="card-body text-center">
                    <h3><?= $stats['occupied_rooms'] ?></h3>
                    <p class="mb-0">غرف محجوزة</p>
                </div>
            </div>
        </div>
        <div class="col-md-2-4">
            <div class="card bg-danger text-white">
                <div class="card-body text-center">
                    <h3><?= $stats['out_of_service'] ?></h3>
                    <p class="mb-0">خارج الخدمة</p>
                </div>
            </div>
        </div>
        <div class="col-md-2-4">
            <div class="card bg-secondary text-white">
                <div class="card-body text-center">
                    <h3><?= $stats['maintenance_rooms'] ?></h3>
                    <p class="mb-0">تحت الصيانة</p>
                </div>
            </div>
        </div>
    </div>

    <!-- مفتاح الألوان -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header">
                    <h5 class="mb-0"><i class="fas fa-key me-2"></i>مفتاح الألوان</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-3">
                            <span class="badge bg-success me-2">شاغرة</span> غرف متاحة للحجز
                        </div>
                        <div class="col-md-3">
                            <span class="badge bg-warning me-2">محجوزة</span> غرف مشغولة حالياً
                        </div>
                        <div class="col-md-3">
                            <span class="badge bg-danger me-2">خارج الخدمة</span> غرف غير متاحة
                        </div>
                        <div class="col-md-3">
                            <span class="badge bg-secondary me-2">تحت الصيانة</span> غرف قيد الصيانة
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- عرض الغرف حسب الطوابق -->
    <?php if (!empty($floors)): ?>
        <?php foreach ($floors as $floor => $floor_rooms): ?>
            <div class="row mb-4">
                <div class="col-12">
                    <div class="card">
                        <div class="card-header bg-info text-white">
                            <h5 class="mb-0">
                                <i class="fas fa-building me-2"></i>الطابق <?= $floor ?>
                                <span class="badge bg-light text-dark ms-2"><?= count($floor_rooms) ?> غرفة</span>
                            </h5>
                        </div>
                        <div class="card-body">
                            <div class="row">
                                <?php foreach ($floor_rooms as $room): ?>
                                    <?php
                                    $status_class = '';
                                    $status_icon = '';
                                    switch($room['current_status']) {
                                        case 'شاغرة':
                                            $status_class = 'success';
                                            $status_icon = 'fa-bed';
                                            break;
                                        case 'محجوزة':
                                            $status_class = 'warning';
                                            $status_icon = 'fa-user';
                                            break;
                                        case 'خارج الخدمة':
                                            $status_class = 'danger';
                                            $status_icon = 'fa-times-circle';
                                            break;
                                        case 'تحت الصيانة':
                                            $status_class = 'secondary';
                                            $status_icon = 'fa-tools';
                                            break;
                                    }
                                    ?>
                                    <div class="col-md-4 col-lg-3 mb-3">
                                        <div class="card border-<?= $status_class ?>">
                                            <div class="card-header bg-<?= $status_class ?> text-white">
                                                <div class="d-flex justify-content-between align-items-center">
                                                    <h6 class="mb-0">
                                                        <i class="fas <?= $status_icon ?> me-1"></i>
                                                        غرفة <?= $room['room_number'] ?>
                                                    </h6>
                                                    <span class="badge bg-light text-dark"><?= $room['type'] ?></span>
                                                </div>
                                            </div>
                                            <div class="card-body">
                                                <p class="card-text">
                                                    <strong>الحالة:</strong> <?= $room['current_status'] ?><br>
                                                    <strong>السعر:</strong> <?= number_format($room['price'], 0) ?> ريال
                                                </p>
                                                
                                                <?php if ($room['current_status'] == 'محجوزة' && $room['guest_name']): ?>
                                                    <div class="border-top pt-2">
                                                        <small>
                                                            <strong>النزيل:</strong> <?= htmlspecialchars($room['guest_name']) ?><br>
                                                            <strong>الهاتف:</strong> <?= htmlspecialchars($room['guest_phone']) ?><br>
                                                            <strong>تاريخ الوصول:</strong> <?= $room['checkin_date'] ?><br>
                                                            <?php if ($room['checkout_date']): ?>
                                                                <strong>تاريخ المغادرة:</strong> <?= $room['checkout_date'] ?><br>
                                                            <?php endif; ?>
                                                            <strong>مدة الإقامة:</strong> <?= $room['stay_duration'] ?> يوم
                                                        </small>
                                                    </div>
                                                <?php endif; ?>
                                                
                                                <div class="mt-2">
                                                    <?php if ($room['current_status'] == 'محجوزة'): ?>
                                                        <a href="../bookings/view.php?id=<?= $room['booking_id'] ?>" 
                                                           class="btn btn-sm btn-outline-info">
                                                            <i class="fas fa-eye"></i> عرض الحجز
                                                        </a>
                                                    <?php else: ?>
                                                        <button type="button" class="btn btn-sm btn-outline-primary" 
                                                                data-bs-toggle="modal" 
                                                                data-bs-target="#changeStatusModal"
                                                                data-room="<?= $room['room_number'] ?>"
                                                                data-current="<?= $room['current_status'] ?>">
                                                            <i class="fas fa-edit"></i> تغيير الحالة
                                                        </button>
                                                    <?php endif; ?>
                                                </div>
                                            </div>
                                        </div>
                                    </div>
                                <?php endforeach; ?>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        <?php endforeach; ?>
    <?php else: ?>
        <div class="row">
            <div class="col-12">
                <div class="alert alert-info text-center">
                    <i class="fas fa-info-circle fa-3x mb-3"></i>
                    <h4>لا توجد غرف مسجلة</h4>
                    <p>قم بإضافة غرف جديدة من صفحة إدارة الغرف</p>
                    <a href="../rooms/add.php" class="btn btn-primary">
                        <i class="fas fa-plus me-1"></i>إضافة غرفة جديدة
                    </a>
                </div>
            </div>
        </div>
    <?php endif; ?>
</div>

<!-- Modal تغيير حالة الغرفة -->
<div class="modal fade" id="changeStatusModal" tabindex="-1">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title">تغيير حالة الغرفة</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
            </div>
            <form method="POST">
                <div class="modal-body">
                    <input type="hidden" id="modal_room_number" name="room_number">
                    <div class="mb-3">
                        <label class="form-label">رقم الغرفة:</label>
                        <span id="modal_room_display" class="fw-bold"></span>
                    </div>
                    <div class="mb-3">
                        <label class="form-label">الحالة الحالية:</label>
                        <span id="modal_current_status" class="fw-bold"></span>
                    </div>
                    <div class="mb-3">
                        <label for="new_status" class="form-label">الحالة الجديدة:</label>
                        <select class="form-select" id="new_status" name="new_status" required>
                            <option value="شاغرة">شاغرة</option>
                            <option value="خارج الخدمة">خارج الخدمة</option>
                            <option value="تحت الصيانة">تحت الصيانة</option>
                        </select>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إلغاء</button>
                    <button type="submit" name="change_status" class="btn btn-primary">حفظ التغيير</button>
                </div>
            </form>
        </div>
    </div>
</div>

<style>
.col-md-2-4 {
    flex: 0 0 auto;
    width: 20%;
}
@media (max-width: 768px) {
    .col-md-2-4 {
        width: 100%;
        margin-bottom: 10px;
    }
}
</style>

<script>
// تحديث Modal عند فتحه
document.getElementById('changeStatusModal').addEventListener('show.bs.modal', function (event) {
    const button = event.relatedTarget;
    const roomNumber = button.getAttribute('data-room');
    const currentStatus = button.getAttribute('data-current');
    
    document.getElementById('modal_room_number').value = roomNumber;
    document.getElementById('modal_room_display').textContent = roomNumber;
    document.getElementById('modal_current_status').textContent = currentStatus;
});
</script>

<?php include_once '../../includes/footer.php'; ?>
