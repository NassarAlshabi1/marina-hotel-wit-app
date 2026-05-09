<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// جلب قائمة النزلاء من جدول الحجوزات
$search = '';
if (isset($_GET['search']) && !empty($_GET['search'])) {
    $search = trim($_GET['search']);
    $guests_query = "
        SELECT DISTINCT 
            guest_name, 
            guest_phone, 
            guest_email, 
            guest_nationality,
            guest_id_number,
            guest_id_type,
            COUNT(*) as total_bookings,
            MAX(checkin_date) as last_visit,
            SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings
        FROM bookings 
        WHERE guest_name LIKE ? OR guest_phone LIKE ? OR guest_email LIKE ?
        GROUP BY guest_name, guest_phone, guest_email 
        ORDER BY last_visit DESC
    ";
    $stmt = $conn->prepare($guests_query);
    $search_param = "%$search%";
    $stmt->bind_param("sss", $search_param, $search_param, $search_param);
    $stmt->execute();
    $guests = $stmt->get_result();
} else {
    $guests_query = "
        SELECT DISTINCT 
            guest_name, 
            guest_phone, 
            guest_email, 
            guest_nationality,
            guest_id_number,
            guest_id_type,
            COUNT(*) as total_bookings,
            MAX(checkin_date) as last_visit,
            SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings
        FROM bookings 
        GROUP BY guest_name, guest_phone, guest_email 
        ORDER BY last_visit DESC
        LIMIT 50
    ";
    $guests = $conn->query($guests_query);
}

// إحصائيات النزلاء
$stats = [];
$stats['total_guests'] = $conn->query("SELECT COUNT(DISTINCT guest_name) as count FROM bookings")->fetch_assoc()['count'];
$stats['active_guests'] = $conn->query("SELECT COUNT(DISTINCT guest_name) as count FROM bookings WHERE status = 'محجوزة'")->fetch_assoc()['count'];
$stats['repeat_guests'] = $conn->query("
    SELECT COUNT(*) as count FROM (
        SELECT guest_name FROM bookings 
        GROUP BY guest_name 
        HAVING COUNT(*) > 1
    ) as repeat_customers
")->fetch_assoc()['count'];

// تضمين الهيدر بعد انتهاء معالجة البيانات
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-users me-2"></i>إدارة النزلاء</h2>
                <div>
                    <a href="index.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>العودة للإعدادات
                    </a>
                    <a href="../dash.php" class="btn btn-outline-primary">
                        <i class="fas fa-home me-1"></i>لوحة التحكم
                    </a>
                </div>
            </div>
        </div>
    </div>

    <!-- إحصائيات النزلاء -->
    <div class="row mb-4">
        <div class="col-md-4">
            <div class="card bg-primary text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['total_guests'] ?></h4>
                            <p class="mb-0">إجمالي النزلاء</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-users fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-4">
            <div class="card bg-success text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['active_guests'] ?></h4>
                            <p class="mb-0">النزلاء الحاليين</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-user-check fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-4">
            <div class="card bg-info text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['repeat_guests'] ?></h4>
                            <p class="mb-0">النزلاء المتكررين</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-redo fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- نموذج البحث -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-secondary text-white">
                    <h5 class="mb-0"><i class="fas fa-search me-2"></i>البحث في النزلاء</h5>
                </div>
                <div class="card-body">
                    <form method="GET" class="row g-3">
                        <div class="col-md-8">
                            <input type="text" class="form-control" name="search" 
                                   placeholder="البحث بالاسم أو رقم الهاتف أو البريد الإلكتروني..."
                                   value="<?= htmlspecialchars($search) ?>">
                        </div>
                        <div class="col-md-4">
                            <button type="submit" class="btn btn-primary me-2">
                                <i class="fas fa-search me-1"></i>بحث
                            </button>
                            <a href="guests.php" class="btn btn-outline-secondary">
                                <i class="fas fa-times me-1"></i>مسح
                            </a>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- قائمة النزلاء -->
    <div class="row">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0">
                        <i class="fas fa-list me-2"></i>قائمة النزلاء
                        <?php if (!empty($search)): ?>
                            <small>(نتائج البحث عن: <?= htmlspecialchars($search) ?>)</small>
                        <?php endif; ?>
                    </h5>
                </div>
                <div class="card-body">
                    <?php if ($guests->num_rows > 0): ?>
                        <div class="table-responsive">
                            <table class="table table-striped table-hover">
                                <thead class="table-dark">
                                    <tr>
                                        <th>#</th>
                                        <th>اسم النزيل</th>
                                        <th>رقم الهاتف</th>
                                        <th>البريد الإلكتروني</th>
                                        <th>الجنسية</th>
                                        <th>نوع الهوية</th>
                                        <th>رقم الهوية</th>
                                        <th>عدد الحجوزات</th>
                                        <th>الحجوزات النشطة</th>
                                        <th>آخر زيارة</th>
                                        <th>الإجراءات</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php 
                                    $counter = 1;
                                    while ($guest = $guests->fetch_assoc()): 
                                    ?>
                                    <tr>
                                        <td><?= $counter++ ?></td>
                                        <td>
                                            <strong><?= htmlspecialchars($guest['guest_name']) ?></strong>
                                        </td>
                                        <td><?= htmlspecialchars($guest['guest_phone']) ?></td>
                                        <td><?= htmlspecialchars($guest['guest_email']) ?></td>
                                        <td><?= htmlspecialchars($guest['guest_nationality']) ?></td>
                                        <td><?= htmlspecialchars($guest['guest_id_type']) ?></td>
                                        <td><?= htmlspecialchars($guest['guest_id_number']) ?></td>
                                        <td>
                                            <span class="badge bg-primary"><?= $guest['total_bookings'] ?></span>
                                        </td>
                                        <td>
                                            <?php if ($guest['active_bookings'] > 0): ?>
                                                <span class="badge bg-success"><?= $guest['active_bookings'] ?></span>
                                            <?php else: ?>
                                                <span class="badge bg-secondary">0</span>
                                            <?php endif; ?>
                                        </td>
                                        <td><?= $guest['last_visit'] ?></td>
                                        <td>
                                            <div class="btn-group" role="group">
                                                <a href="edit_guest.php?name=<?= urlencode($guest['guest_name']) ?>&phone=<?= urlencode($guest['guest_phone']) ?>"
                                                   class="btn btn-sm btn-outline-primary" title="تعديل بيانات النزيل">
                                                    <i class="fas fa-edit"></i>
                                                </a>
                                                <a href="guest_history.php?name=<?= urlencode($guest['guest_name']) ?>"
                                                   class="btn btn-sm btn-outline-info" title="تاريخ الحجوزات">
                                                    <i class="fas fa-history"></i>
                                                </a>
                                                <a href="../bookings/add2.php?guest_name=<?= urlencode($guest['guest_name']) ?>&guest_phone=<?= urlencode($guest['guest_phone']) ?>"
                                                   class="btn btn-sm btn-outline-success" title="حجز جديد">
                                                    <i class="fas fa-plus"></i>
                                                </a>
                                            </div>
                                        </td>
                                    </tr>
                                    <?php endwhile; ?>
                                </tbody>
                            </table>
                        </div>
                    <?php else: ?>
                        <div class="text-center py-4">
                            <i class="fas fa-users fa-3x text-muted mb-3"></i>
                            <h5 class="text-muted">
                                <?php if (!empty($search)): ?>
                                    لا توجد نتائج للبحث عن "<?= htmlspecialchars($search) ?>"
                                <?php else: ?>
                                    لا يوجد نزلاء مسجلين
                                <?php endif; ?>
                            </h5>
                            <p class="text-muted">
                                <?php if (!empty($search)): ?>
                                    جرب البحث بكلمات مختلفة
                                <?php else: ?>
                                    سيظهر النزلاء هنا عند إنشاء حجوزات جديدة
                                <?php endif; ?>
                            </p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
