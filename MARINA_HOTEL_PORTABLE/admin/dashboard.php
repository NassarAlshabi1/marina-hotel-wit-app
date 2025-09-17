<?php
require_once '../includes/db.php';
require_once '../includes/functions.php';
require_once '../includes/header.php';

// التحقق من تسجيل الدخول
if (!isset($_SESSION['user_id'])) {
    header('Location: ../login.php');
    exit;
}

// الحصول على إحصائيات لوحة التحكم
try {
    // إجمالي الغرف
    $total_rooms = getDashboardData($conn, "SELECT COUNT(*) FROM rooms");
    
    // الغرف المتاحة
    $available_rooms = getDashboardData($conn, "SELECT COUNT(*) FROM rooms WHERE status = 'شاغرة'");
    
    // الغرف المحجوزة
    $occupied_rooms = getDashboardData($conn, "SELECT COUNT(*) FROM rooms WHERE status = 'محجوزة'");
    
    // نسبة الإشغال
    $occupancy_rate = ($total_rooms > 0) ? round(($occupied_rooms / $total_rooms) * 100) : 0;
    
    // إجمالي النزلاء الحاليين
    $current_guests = getDashboardData($conn, "SELECT COUNT(*) FROM bookings WHERE status = 'نشط'");
    
    // إيرادات اليوم
    $today = date('Y-m-d');
    $today_revenue = getDashboardData($conn, "SELECT COALESCE(SUM(amount), 0) FROM payment WHERE DATE(payment_date) = '$today'");
    
    // إيرادات الشهر
    $month_start = date('Y-m-01');
    $month_end = date('Y-m-t');
    $month_revenue = getDashboardData($conn, "SELECT COALESCE(SUM(amount), 0) FROM payment WHERE payment_date BETWEEN '$month_start' AND '$month_end'");
    
    // مصروفات اليوم
    $today_expenses = getDashboardData($conn, "SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE DATE(date) = '$today'");
    
    // مصروفات الشهر
    $month_expenses = getDashboardData($conn, "SELECT COALESCE(SUM(amount), 0) FROM expenses WHERE date BETWEEN '$month_start' AND '$month_end'");
    
    // صافي الربح اليومي
    $today_profit = $today_revenue - $today_expenses;
    
    // صافي الربح الشهري
    $month_profit = $month_revenue - $month_expenses;
    
    // الحجوزات القادمة
    $upcoming_bookings_query = "
        SELECT b.booking_id, b.guest_name, b.room_number, b.checkin_date, b.checkout_date, r.price
        FROM bookings b
        JOIN rooms r ON b.room_number = r.room_number
        WHERE b.checkin_date >= CURDATE() AND b.status = 'مؤكد'
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
    
    // الغرف الأكثر حجز<|im_start|>
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
}

// دالة للحصول على بيانات لوحة التحكم
function getDashboardData($conn, $sql) {
    $result = $conn->query($sql);
    if (!$result) {
        error_log("خطأ في الاستعلام: " . $conn->error . " SQL: " . $sql);
        return 0;
    }
    $data = $result->fetch_row();
    return $data[0] ?? 0;
}
?>

<div class="row">
    <div class="col-12">
        <div class="card shadow-sm mb-4">
            <div class="card-body">
                <div class="d-flex justify-content-between align-items-center mb-4">
                    <h1 class="card-title mb-0">
                        <i class="fas fa-tachometer-alt me-2"></i> لوحة التحكم
                    </h1>
                    <a href="settings/index.php" class="btn btn-primary btn-lg">
                        <i class="fas fa-cogs me-2"></i> الإعدادات الرئيسية
                    </a>
                </div>
                
                <!-- شريط الإحصائيات السريعة -->
                <div class="row g-4 mb-4">
                    <div class="col-md-3">
                        <div class="card bg-primary text-white h-100">
                            <div class="card-body text-center">
                                <h5 class="card-title">
                                    <i class="fas fa-bed me-2"></i> الغرف المتاحة
                                </h5>
                                <h2 class="display-4"><?php echo $available_rooms; ?></h2>
                                <p class="card-text">من إجمالي <?php echo $total_rooms; ?> غرفة</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-success text-white h-100">
                            <div class="card-body text-center">
                                <h5 class="card-title">
                                    <i class="fas fa-money-bill-wave me-2"></i> إيرادات اليوم
                                </h5>
                                <h2 class="display-4"><?php echo number_format($today_revenue); ?></h2>
                                <p class="card-text">ريال يمني</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-info text-white h-100">
                            <div class="card-body text-center">
                                <h5 class="card-title">
                                    <i class="fas fa-users me-2"></i> النزلاء الحاليين
                                </h5>
                                <h2 class="display-4"><?php echo $current_guests; ?></h2>
                                <p class="card-text">نزيل في الفندق</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-3">
                        <div class="card bg-warning text-dark h-100">
                            <div class="card-body text-center">
                                <h5 class="card-title">
                                    <i class="fas fa-chart-pie me-2"></i> نسبة الإشغال
                                </h5>
                                <h2 class="display-4"><?php echo $occupancy_rate; ?>%</h2>
                                <p class="card-text"><?php echo $occupied_rooms; ?> غرفة محجوزة</p>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- الإحصائيات المالية -->
                <div class="row mb-4">
                    <div class="col-md-6">
                        <div class="card h-100">
                            <div class="card-header bg-light">
                                <h5 class="card-title mb-0">
                                    <i class="fas fa-chart-line me-2"></i> ملخص الإيرادات والمصروفات
                                </h5>
                            </div>
                            <div class="card-body">
                                <div class="table-responsive">
                                    <table class="table table-bordered">
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
                                                <td class="text-success"><?php echo number_format($today_revenue); ?></td>
                                                <td class="text-danger"><?php echo number_format($today_expenses); ?></td>
                                                <td class="<?php echo ($today_profit >= 0) ? 'text-success' : 'text-danger'; ?>">
                                                    <?php echo number_format($today_profit); ?>
                                                </td>
                                            </tr>
                                            <tr>
                                                <td>الشهر الحالي</td>
                                                <td class="text-success"><?php echo number_format($month_revenue); ?></td>
                                                <td class="text-danger"><?php echo number_format($month_expenses); ?></td>
                                                <td class="<?php echo ($month_profit >= 0) ? 'text-success' : 'text-danger'; ?>">
                                                    <?php echo number_format($month_profit); ?>
                                                </td>
                                            </tr>
                                        </tbody>
                                    </table>
                                </div>
                                <div class="text-center mt-3">
                                    <a href="reports/comprehensive_reports.php" class="btn btn-outline-primary">
                                        <i class="fas fa-file-alt me-2"></i> عرض التقارير المفصلة
                                    </a>
                                </div>
                            </div>
                        </div>
                    </div>

                    <!-- الغرف الأكثر حجزاً -->
                    <div class="col-md-6">
                        <div class="card h-100">
                            <div class="card-header bg-light">
                                <h5 class="card-title mb-0">
                                    <i class="fas fa-star me-2"></i> الغرف الأكثر حجزاً
                                </h5>
                            </div>
                            <div class="card-body">
                                <?php if ($popular_rooms_result && $popular_rooms_result->num_rows > 0): ?>
                                <div class="table-responsive">
                                    <table class="table table-sm">
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
                                                <td><?php echo number_format($room['price']); ?> ريال</td>
                                            </tr>
                                            <?php endwhile; ?>
                                        </tbody>
                                    </table>
                                </div>
                                <?php else: ?>
                                <p class="text-muted text-center">لا توجد بيانات حجوزات متاحة</p>
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
                                <h5 class="card-title mb-0">
                                    <i class="fas fa-calendar-check me-2"></i> الحجوزات القادمة
                                </h5>
                            </div>
                            <div class="card-body">
                                <?php if ($upcoming_bookings_result && $upcoming_bookings_result->num_rows > 0): ?>
                                <div class="table-responsive">
                                    <table class="table table-sm">
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
                                <p class="text-muted text-center">لا توجد حجوزات قادمة</p>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>

                    <div class="col-md-6">
                        <div class="card h-100">
                            <div class="card-header bg-light">
                                <h5 class="card-title mb-0">
                                    <i class="fas fa-money-bill-wave me-2"></i> آخر المدفوعات
                                </h5>
                            </div>
                            <div class="card-body">
                                <?php if ($recent_payments_result && $recent_payments_result->num_rows > 0): ?>
                                <div class="table-responsive">
                                    <table class="table table-sm">
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
                                <p class="text-muted text-center">لا توجد مدفوعات حديثة</p>
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
                                <h5 class="card-title mb-0">
                                    <i class="fas fa-file-invoice-dollar me-2"></i> آخر المصروفات
                                </h5>
                            </div>
                            <div class="card-body">
                                <?php if ($recent_expenses_result && $recent_expenses_result->num_rows > 0): ?>
                                <div class="table-responsive">
                                    <table class="table table-striped">
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
                                <p class="text-muted text-center">لا توجد مصروفات حديثة</p>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- أزرار الإجراءات السريعة -->
                <div class="row">
                    <div class="col-12">
                        <div class="card">
                            <div class="card-header bg-light">
                                <h5 class="card-title mb-0">
                                    <i class="fas fa-bolt me-2"></i> الإجراءات السريعة
                                </h5>
                            </div>
                            <div class="card-body">
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
                                <div class="row g-3">
                                    <div class="col-md-2-4">
                                        <a href="bookings/add2.php" class="btn btn-primary w-100">
                                            <i class="fas fa-plus-circle me-2"></i> حجز جديد
                                        </a>
                                    </div>
                                    <div class="col-md-2-4">
                                        <a href="bookings/list.php" class="btn btn-info w-100">
                                            <i class="fas fa-list me-2"></i> عرض الحجوزات
                                        </a>
                                    </div>
                                    <div class="col-md-2-4">
                                        <a href="expenses/expenses.php" class="btn btn-warning w-100">
                                            <i class="fas fa-file-invoice-dollar me-2"></i> إدارة المصروفات
                                        </a>
                                    </div>
                                    <div class="col-md-2-4">
                                        <a href="reports/revenue.php" class="btn btn-success w-100">
                                            <i class="fas fa-chart-bar me-2"></i> التقارير
                                        </a>
                                    </div>
                                    <div class="col-md-2-4">
                                        <a href="settings/index.php" class="btn btn-secondary w-100">
                                            <i class="fas fa-cogs me-2"></i> الإعدادات
                                        </a>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<?php require_once '../includes/footer.php'; ?>
