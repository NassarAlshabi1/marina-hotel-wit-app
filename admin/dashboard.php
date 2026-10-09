<?php
/**
 * لوحة التحكم الرئيسية - فندق مارينا بلازا
 * تعرض إحصائيات شاملة عن حالة الفندق
 */
require_once '../includes/db.php';
require_once '../includes/functions.php';
require_once '../includes/security.php';

// التحقق من تسجيل الدخول
if (!isset($_SESSION['user_id'])) {
    header('Location: ../login.php');
    exit;
}

// الحصول على إحصائيات لوحة التحكم باستخدام prepared statements
try {
    $today = date('Y-m-d');
    $month_start = date('Y-m-01');
    $month_end = date('Y-m-t');

    // إجمالي الغرف
    $stmt = $conn->prepare("SELECT COUNT(*) FROM rooms");
    $stmt->execute();
    $total_rooms = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // الغرف المتاحة
    $stmt = $conn->prepare("SELECT COUNT(*) FROM rooms WHERE status = 'شاغرة'");
    $stmt->execute();
    $available_rooms = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // الغرف المحجوزة
    $stmt = $conn->prepare("SELECT COUNT(*) FROM rooms WHERE status = 'محجوزة'");
    $stmt->execute();
    $occupied_rooms = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // نسبة الإشغال
    $occupancy_rate = ($total_rooms > 0) ? round(($occupied_rooms / $total_rooms) * 100) : 0;

    // إجمالي النزلاء الحاليين
    $stmt = $conn->prepare("SELECT COUNT(*) FROM bookings WHERE status = 'محجوزة'");
    $stmt->execute();
    $current_guests = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // إيرادات اليوم
    $stmt = $conn->prepare("SELECT COALESCE(SUM(amount), 0) FROM payment WHERE DATE(payment_date) = ?");
    $stmt->bind_param("s", $today);
    $stmt->execute();
    $today_revenue = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // إيرادات الشهر
    $stmt = $conn->prepare("SELECT COALESCE(SUM(amount), 0) FROM payment WHERE payment_date BETWEEN ? AND ?");
    $stmt->bind_param("ss", $month_start, $month_end);
    $stmt->execute();
    $month_revenue = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // مصروفات اليوم
    $stmt = $conn->prepare("SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE DATE(date) = ?");
    $stmt->bind_param("s", $today);
    $stmt->execute();
    $today_expenses = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // مصروفات الشهر
    $stmt = $conn->prepare("SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE date BETWEEN ? AND ?");
    $stmt->bind_param("ss", $month_start, $month_end);
    $stmt->execute();
    $month_expenses = $stmt->get_result()->fetch_row()[0] ?? 0;
    $stmt->close();

    // صافي الربح
    $today_profit = $today_revenue - $today_expenses;
    $month_profit = $month_revenue - $month_expenses;

    // الحجوزات القادمة
    $upcoming_bookings_query = "
        SELECT b.booking_id, b.guest_name, b.room_number, b.checkin_date, b.checkout_date, r.price
        FROM bookings b
        JOIN rooms r ON b.room_number = r.room_number
        WHERE b.checkin_date >= CURDATE() AND b.status = 'محجوزة'
        ORDER BY b.checkin_date ASC
        LIMIT 5
    ";
    $upcoming_bookings_result = $conn->query($upcoming_bookings_query);

    // آخر المدفوعات
    $recent_payments_query = "
        SELECT p.payment_id, p.amount, p.payment_date, p.payment_method, b.guest_name, b.room_number
        FROM payment p
        JOIN bookings b ON p.booking_id = b.booking_id
        ORDER BY p.payment_date DESC
        LIMIT 5
    ";
    $recent_payments_result = $conn->query($recent_payments_query);

    // آخر المصروفات
    $recent_expenses_query = "
        SELECT e.id, e.description, e.amount, e.date, e.expense_type
        FROM expenses e
        ORDER BY e.date DESC
        LIMIT 5
    ";
    $recent_expenses_result = $conn->query($recent_expenses_query);

    // الغرف الأكثر حجزاً
    $popular_rooms_query = "
        SELECT b.room_number, COUNT(*) as booking_count, r.price, r.type
        FROM bookings b
        JOIN rooms r ON b.room_number = r.room_number
        GROUP BY b.room_number
        ORDER BY booking_count DESC
        LIMIT 5
    ";
    $popular_rooms_result = $conn->query($popular_rooms_query);

} catch (Exception $e) {
    $error_message = $e->getMessage();
    error_log("خطأ في لوحة التحكم: " . $error_message);
}

// تضمين الهيدر بعد جلب البيانات
require_once '../includes/header.php';
?>

<style>
    .dashboard-stat-card {
        border-radius: 12px;
        transition: transform 0.2s ease, box-shadow 0.2s ease;
        overflow: hidden;
    }
    .dashboard-stat-card:hover {
        transform: translateY(-3px);
        box-shadow: 0 8px 25px rgba(0,0,0,0.15);
    }
    .dashboard-stat-card .stat-icon {
        font-size: 2.5rem;
        opacity: 0.3;
        position: absolute;
        left: 15px;
        top: 15px;
    }
    .dashboard-stat-card .stat-value {
        font-size: 2rem;
        font-weight: 700;
        line-height: 1.2;
    }
    .dashboard-stat-card .stat-label {
        font-size: 0.9rem;
        opacity: 0.85;
    }
    .quick-action-btn {
        border-radius: 10px;
        padding: 12px 20px;
        font-weight: 600;
        transition: all 0.2s ease;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 8px;
    }
    .quick-action-btn:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 15px rgba(0,0,0,0.2);
    }
    .col-md-2-4 {
        flex: 0 0 auto;
        width: 20%;
    }
    @media (max-width: 768px) {
        .col-md-2-4 {
            width: 100%;
            margin-bottom: 10px;
        }
        .dashboard-stat-card .stat-value {
            font-size: 1.5rem;
        }
    }
</style>

<div class="row">
    <div class="col-12">
        <div class="d-flex justify-content-between align-items-center mb-4">
            <h4 class="mb-0"><i class="fas fa-tachometer-alt me-2"></i>لوحة التحكم</h4>
            <a href="settings/index.php" class="btn btn-outline-primary btn-sm">
                <i class="fas fa-cogs me-1"></i> الإعدادات
            </a>
        </div>
    </div>
</div>

<!-- شريط الإحصائيات السريعة -->
<div class="row g-3 mb-4">
    <div class="col-md-3">
        <div class="card dashboard-stat-card bg-primary text-white h-100 position-relative">
            <div class="card-body">
                <i class="fas fa-bed stat-icon"></i>
                <div class="stat-value"><?php echo $available_rooms; ?></div>
                <div class="stat-label">الغرف المتاحة (من <?php echo $total_rooms; ?>)</div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card dashboard-stat-card bg-success text-white h-100 position-relative">
            <div class="card-body">
                <i class="fas fa-money-bill-wave stat-icon"></i>
                <div class="stat-value"><?php echo number_format($today_revenue); ?></div>
                <div class="stat-label">إيرادات اليوم (ريال يمني)</div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card dashboard-stat-card bg-info text-white h-100 position-relative">
            <div class="card-body">
                <i class="fas fa-users stat-icon"></i>
                <div class="stat-value"><?php echo $current_guests; ?></div>
                <div class="stat-label">النزلاء الحاليين</div>
            </div>
        </div>
    </div>
    <div class="col-md-3">
        <div class="card dashboard-stat-card bg-warning text-dark h-100 position-relative">
            <div class="card-body">
                <i class="fas fa-chart-pie stat-icon"></i>
                <div class="stat-value"><?php echo $occupancy_rate; ?>%</div>
                <div class="stat-label">نسبة الإشغال (<?php echo $occupied_rooms; ?> محجوزة)</div>
            </div>
        </div>
    </div>
</div>

<!-- الإحصائيات المالية -->
<div class="row mb-4">
    <div class="col-md-6">
        <div class="card h-100">
            <div class="card-header bg-light">
                <h6 class="mb-0"><i class="fas fa-chart-line me-2"></i>ملخص الإيرادات والمصروفات</h6>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-bordered mb-0">
                        <thead class="table-light">
                            <tr>
                                <th>الفترة</th>
                                <th>الإيرادات</th>
                                <th>المصروفات</th>
                                <th>صافي الربح</th>
                            </tr>
                        </thead>
                        <tbody>
                            <tr>
                                <td>اليوم</td>
                                <td class="text-success fw-bold"><?php echo number_format($today_revenue); ?></td>
                                <td class="text-danger fw-bold"><?php echo number_format($today_expenses); ?></td>
                                <td class="<?php echo ($today_profit >= 0) ? 'text-success' : 'text-danger'; ?> fw-bold">
                                    <?php echo number_format($today_profit); ?>
                                </td>
                            </tr>
                            <tr>
                                <td>الشهر الحالي</td>
                                <td class="text-success fw-bold"><?php echo number_format($month_revenue); ?></td>
                                <td class="text-danger fw-bold"><?php echo number_format($month_expenses); ?></td>
                                <td class="<?php echo ($month_profit >= 0) ? 'text-success' : 'text-danger'; ?> fw-bold">
                                    <?php echo number_format($month_profit); ?>
                                </td>
                            </tr>
                        </tbody>
                    </table>
                </div>
                <div class="text-center mt-3">
                    <a href="reports/comprehensive_reports.php" class="btn btn-outline-primary btn-sm">
                        <i class="fas fa-file-alt me-1"></i> عرض التقارير المفصلة
                    </a>
                </div>
            </div>
        </div>
    </div>

    <!-- الغرف الأكثر حجزاً -->
    <div class="col-md-6">
        <div class="card h-100">
            <div class="card-header bg-light">
                <h6 class="mb-0"><i class="fas fa-star me-2"></i>الغرف الأكثر حجزاً</h6>
            </div>
            <div class="card-body">
                <?php if (isset($popular_rooms_result) && $popular_rooms_result && $popular_rooms_result->num_rows > 0): ?>
                <div class="table-responsive">
                    <table class="table table-sm table-hover mb-0">
                        <thead class="table-light">
                            <tr>
                                <th>رقم الغرفة</th>
                                <th>نوع الغرفة</th>
                                <th>عدد الحجوزات</th>
                                <th>السعر</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php while ($room = $popular_rooms_result->fetch_assoc()): ?>
                            <tr>
                                <td><strong><?php echo htmlspecialchars($room['room_number']); ?></strong></td>
                                <td><?php echo htmlspecialchars($room['type']); ?></td>
                                <td><span class="badge bg-primary"><?php echo $room['booking_count']; ?></span></td>
                                <td><?php echo number_format($room['price']); ?> ر.س</td>
                            </tr>
                            <?php endwhile; ?>
                        </tbody>
                    </table>
                </div>
                <?php else: ?>
                <p class="text-muted text-center mb-0">لا توجد بيانات حجوزات متاحة</p>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- الحجوزات القادمة والمدفوعات الأخيرة -->
<div class="row mb-4">
    <div class="col-md-6">
        <div class="card h-100">
            <div class="card-header bg-light">
                <h6 class="mb-0"><i class="fas fa-calendar-check me-2"></i>الحجوزات القادمة</h6>
            </div>
            <div class="card-body">
                <?php if (isset($upcoming_bookings_result) && $upcoming_bookings_result && $upcoming_bookings_result->num_rows > 0): ?>
                <div class="table-responsive">
                    <table class="table table-sm table-hover mb-0">
                        <thead class="table-light">
                            <tr>
                                <th>اسم النزيل</th>
                                <th>رقم الغرفة</th>
                                <th>تاريخ الوصول</th>
                                <th>تاريخ المغادرة</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php while ($booking = $upcoming_bookings_result->fetch_assoc()): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($booking['guest_name']); ?></td>
                                <td><strong><?php echo htmlspecialchars($booking['room_number']); ?></strong></td>
                                <td><?php echo date('Y-m-d', strtotime($booking['checkin_date'])); ?></td>
                                <td><?php echo date('Y-m-d', strtotime($booking['checkout_date'])); ?></td>
                            </tr>
                            <?php endwhile; ?>
                        </tbody>
                    </table>
                </div>
                <?php else: ?>
                <p class="text-muted text-center mb-0">لا توجد حجوزات قادمة</p>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <div class="col-md-6">
        <div class="card h-100">
            <div class="card-header bg-light">
                <h6 class="mb-0"><i class="fas fa-money-bill-wave me-2"></i>آخر المدفوعات</h6>
            </div>
            <div class="card-body">
                <?php if (isset($recent_payments_result) && $recent_payments_result && $recent_payments_result->num_rows > 0): ?>
                <div class="table-responsive">
                    <table class="table table-sm table-hover mb-0">
                        <thead class="table-light">
                            <tr>
                                <th>اسم النزيل</th>
                                <th>المبلغ</th>
                                <th>طريقة الدفع</th>
                                <th>التاريخ</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php while ($payment = $recent_payments_result->fetch_assoc()): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($payment['guest_name']); ?></td>
                                <td class="text-success"><strong><?php echo number_format($payment['amount']); ?></strong></td>
                                <td><?php echo htmlspecialchars($payment['payment_method']); ?></td>
                                <td><?php echo date('Y-m-d', strtotime($payment['payment_date'])); ?></td>
                            </tr>
                            <?php endwhile; ?>
                        </tbody>
                    </table>
                </div>
                <?php else: ?>
                <p class="text-muted text-center mb-0">لا توجد مدفوعات حديثة</p>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- آخر المصروفات -->
<div class="row mb-4">
    <div class="col-12">
        <div class="card">
            <div class="card-header bg-light">
                <h6 class="mb-0"><i class="fas fa-file-invoice-dollar me-2"></i>آخر المصروفات</h6>
            </div>
            <div class="card-body">
                <?php if (isset($recent_expenses_result) && $recent_expenses_result && $recent_expenses_result->num_rows > 0): ?>
                <div class="table-responsive">
                    <table class="table table-sm table-hover mb-0">
                        <thead class="table-light">
                            <tr>
                                <th>الوصف</th>
                                <th>نوع المصروف</th>
                                <th>المبلغ</th>
                                <th>التاريخ</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php while ($expense = $recent_expenses_result->fetch_assoc()): ?>
                            <tr>
                                <td><?php echo htmlspecialchars($expense['description']); ?></td>
                                <td><?php echo htmlspecialchars($expense['expense_type']); ?></td>
                                <td class="text-danger"><strong><?php echo number_format($expense['amount']); ?></strong></td>
                                <td><?php echo date('Y-m-d', strtotime($expense['date'])); ?></td>
                            </tr>
                            <?php endwhile; ?>
                        </tbody>
                    </table>
                </div>
                <?php else: ?>
                <p class="text-muted text-center mb-0">لا توجد مصروفات حديثة</p>
                <?php endif; ?>
            </div>
        </div>
    </div>
</div>

<!-- أزرار الإجراءات السريعة -->
<div class="row mb-4">
    <div class="col-12">
        <div class="card">
            <div class="card-header bg-light">
                <h6 class="mb-0"><i class="fas fa-bolt me-2"></i>الإجراءات السريعة</h6>
            </div>
            <div class="card-body">
                <div class="row g-3">
                    <div class="col-md-2-4">
                        <a href="bookings/add2.php" class="btn btn-primary quick-action-btn w-100">
                            <i class="fas fa-plus-circle"></i> حجز جديد
                        </a>
                    </div>
                    <div class="col-md-2-4">
                        <a href="bookings/list.php" class="btn btn-info quick-action-btn w-100 text-white">
                            <i class="fas fa-list"></i> عرض الحجوزات
                        </a>
                    </div>
                    <div class="col-md-2-4">
                        <a href="expenses/expenses.php" class="btn btn-warning quick-action-btn w-100">
                            <i class="fas fa-file-invoice-dollar"></i> المصروفات
                        </a>
                    </div>
                    <div class="col-md-2-4">
                        <a href="reports/revenue.php" class="btn btn-success quick-action-btn w-100">
                            <i class="fas fa-chart-bar"></i> التقارير
                        </a>
                    </div>
                    <div class="col-md-2-4">
                        <a href="finance/cash_register.php" class="btn btn-secondary quick-action-btn w-100">
                            <i class="fas fa-cash-register"></i> الصندوق
                        </a>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<?php require_once '../includes/footer.php'; ?>
