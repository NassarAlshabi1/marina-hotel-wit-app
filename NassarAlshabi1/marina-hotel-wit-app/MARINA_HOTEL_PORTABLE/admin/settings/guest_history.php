<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// التحقق من وجود اسم النزيل
$guest_name = '';
if (isset($_GET['name']) && !empty($_GET['name'])) {
    $guest_name = trim($_GET['name']);
} else {
    header("Location: guests.php");
    exit();
}

// جلب تاريخ حجوزات النزيل
$bookings_query = "
    SELECT 
        b.*,
        r.type as room_type,
        r.price as room_price,
        COALESCE(SUM(p.amount), 0) as total_paid
    FROM bookings b
    LEFT JOIN rooms r ON b.room_number = r.room_number
    LEFT JOIN payment p ON b.booking_id = p.booking_id
    WHERE b.guest_name = ?
    GROUP BY b.booking_id
    ORDER BY b.checkin_date DESC
";
$stmt = $conn->prepare($bookings_query);
$stmt->bind_param("s", $guest_name);
$stmt->execute();
$bookings = $stmt->get_result();

// إحصائيات النزيل
$stats_query = "
    SELECT 
        COUNT(*) as total_bookings,
        SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings,
        SUM(CASE WHEN status = 'مكتملة' THEN 1 ELSE 0 END) as completed_bookings,
        SUM(CASE WHEN status = 'ملغية' THEN 1 ELSE 0 END) as cancelled_bookings,
        MIN(checkin_date) as first_visit,
        MAX(checkin_date) as last_visit
    FROM bookings 
    WHERE guest_name = ?
";
$stmt = $conn->prepare($stats_query);
$stmt->bind_param("s", $guest_name);
$stmt->execute();
$stats = $stmt->get_result()->fetch_assoc();

// جلب إجمالي المدفوعات
$payments_query = "
    SELECT COALESCE(SUM(p.amount), 0) as total_payments
    FROM bookings b
    LEFT JOIN payment p ON b.booking_id = p.booking_id
    WHERE b.guest_name = ?
";
$stmt = $conn->prepare($payments_query);
$stmt->bind_param("s", $guest_name);
$stmt->execute();
$total_payments = $stmt->get_result()->fetch_assoc()['total_payments'];

// تضمين الهيدر بعد انتهاء معالجة البيانات
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-history me-2"></i>تاريخ النزيل: <?= htmlspecialchars($guest_name) ?></h2>
                <div>
                    <a href="guests.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>العودة للنزلاء
                    </a>
                    <a href="../bookings/add2.php?guest_name=<?= urlencode($guest_name) ?>" class="btn btn-success">
                        <i class="fas fa-plus me-1"></i>حجز جديد
                    </a>
                </div>
            </div>
        </div>
    </div>

    <!-- إحصائيات النزيل -->
    <div class="row mb-4">
        <div class="col-md-3">
            <div class="card bg-primary text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['total_bookings'] ?></h4>
                            <p class="mb-0">إجمالي الحجوزات</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-calendar fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-success text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['completed_bookings'] ?></h4>
                            <p class="mb-0">الحجوزات المكتملة</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-check-circle fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-warning text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= $stats['active_bookings'] ?></h4>
                            <p class="mb-0">الحجوزات النشطة</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-clock fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        <div class="col-md-3">
            <div class="card bg-info text-white">
                <div class="card-body">
                    <div class="d-flex justify-content-between">
                        <div>
                            <h4><?= number_format($total_payments, 0) ?></h4>
                            <p class="mb-0">إجمالي المدفوعات</p>
                        </div>
                        <div class="align-self-center">
                            <i class="fas fa-money-bill-wave fa-2x"></i>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- معلومات إضافية -->
    <div class="row mb-4">
        <div class="col-md-6">
            <div class="card">
                <div class="card-body">
                    <h6 class="card-title"><i class="fas fa-calendar-plus me-2"></i>أول زيارة</h6>
                    <p class="card-text h5 text-primary"><?= $stats['first_visit'] ?></p>
                </div>
            </div>
        </div>
        <div class="col-md-6">
            <div class="card">
                <div class="card-body">
                    <h6 class="card-title"><i class="fas fa-calendar-check me-2"></i>آخر زيارة</h6>
                    <p class="card-text h5 text-success"><?= $stats['last_visit'] ?></p>
                </div>
            </div>
        </div>
    </div>

    <!-- تاريخ الحجوزات -->
    <div class="row">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0"><i class="fas fa-list me-2"></i>تاريخ الحجوزات</h5>
                </div>
                <div class="card-body">
                    <?php if ($bookings->num_rows > 0): ?>
                        <div class="table-responsive">
                            <table class="table table-striped table-hover">
                                <thead class="table-dark">
                                    <tr>
                                        <th>رقم الحجز</th>
                                        <th>رقم الغرفة</th>
                                        <th>نوع الغرفة</th>
                                        <th>تاريخ الوصول</th>
                                        <th>تاريخ المغادرة</th>
                                        <th>الحالة</th>
                                        <th>المبلغ المدفوع</th>
                                        <th>الإجراءات</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php while ($booking = $bookings->fetch_assoc()): ?>
                                    <tr>
                                        <td><strong><?= $booking['booking_id'] ?></strong></td>
                                        <td><?= htmlspecialchars($booking['room_number']) ?></td>
                                        <td><?= htmlspecialchars($booking['room_type']) ?></td>
                                        <td><?= $booking['checkin_date'] ?></td>
                                        <td><?= $booking['checkout_date'] ?: 'غير محدد' ?></td>
                                        <td>
                                            <?php
                                            $status_class = '';
                                            switch($booking['status']) {
                                                case 'محجوزة':
                                                    $status_class = 'bg-warning';
                                                    break;
                                                case 'مكتملة':
                                                    $status_class = 'bg-success';
                                                    break;
                                                case 'ملغية':
                                                    $status_class = 'bg-danger';
                                                    break;
                                                default:
                                                    $status_class = 'bg-secondary';
                                            }
                                            ?>
                                            <span class="badge <?= $status_class ?>"><?= $booking['status'] ?></span>
                                        </td>
                                        <td><?= number_format($booking['total_paid'], 2) ?> ريال</td>
                                        <td>
                                            <div class="btn-group" role="group">
                                                <a href="../bookings/view.php?id=<?= $booking['booking_id'] ?>" 
                                                   class="btn btn-sm btn-outline-info" title="عرض التفاصيل">
                                                    <i class="fas fa-eye"></i>
                                                </a>
                                                <?php if ($booking['status'] == 'محجوزة'): ?>
                                                <a href="../bookings/payment.php?id=<?= $booking['booking_id'] ?>" 
                                                   class="btn btn-sm btn-outline-success" title="الدفع">
                                                    <i class="fas fa-money-bill-wave"></i>
                                                </a>
                                                <?php endif; ?>
                                            </div>
                                        </td>
                                    </tr>
                                    <?php endwhile; ?>
                                </tbody>
                            </table>
                        </div>
                    <?php else: ?>
                        <div class="text-center py-4">
                            <i class="fas fa-calendar-times fa-3x text-muted mb-3"></i>
                            <h5 class="text-muted">لا توجد حجوزات لهذا النزيل</h5>
                            <p class="text-muted">لم يتم العثور على أي حجوزات سابقة</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
