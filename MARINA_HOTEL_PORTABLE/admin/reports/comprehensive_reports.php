<?php
// تضمين ملفات الاتصال بقاعدة البيانات والتوثيق
require_once '../../includes/db.php';
require_once '../../includes/auth_check.php';
require_once '../../includes/functions.php';

// تحديد نطاق التاريخ الافتراضي (الشهر الحالي)
$today = date('Y-m-d');
$first_day_of_month = date('Y-m-01');
$last_day_of_month = date('Y-m-t');

// الحصول على نطاق التاريخ من الطلب إذا تم تحديده
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : $first_day_of_month;
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : $last_day_of_month;
$report_type = isset($_GET['report_type']) ? $_GET['report_type'] : 'all';

// تحسين الأداء: استخدام التخزين المؤقت للتقارير
$cache_file = "../../cache/report_{$report_type}_{$start_date}_{$end_date}_" . $_SESSION['user_id'] . ".json";
$cache_time = 3600; // ساعة واحدة

// التحقق من وجود ملف التخزين المؤقت وصلاحيته
$use_cache = false;
if (file_exists($cache_file) && (time() - filemtime($cache_file) < $cache_time)) {
    $report_data = json_decode(file_get_contents($cache_file), true);
    $use_cache = true;
}

// إذا لم يكن هناك بيانات مخزنة مؤقتًا، قم بجلب البيانات من قاعدة البيانات
if (!$use_cache) {
    // تحسين الأداء: استخدام استعلامات مجمعة بدلاً من استعلامات متعددة
    
    // 1. بيانات الإيرادات
    $revenue_query = "
        SELECT 
            DATE(payment_date) as date,
            SUM(amount) as total_revenue
        FROM 
            payment
        WHERE 
            DATE(payment_date) BETWEEN ? AND ?
        GROUP BY 
            DATE(payment_date)
        ORDER BY 
            date ASC
    ";
    
    $stmt = $conn->prepare($revenue_query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $revenue_result = $stmt->get_result();
    
    $revenue_data = [];
    $total_revenue = 0;
    
    while ($row = $revenue_result->fetch_assoc()) {
        $revenue_data[] = $row;
        $total_revenue += $row['total_revenue'];
    }
    
    // 2. بيانات المصروفات
    $expenses_query = "
        SELECT 
            DATE(date) as date,
            expense_type as expense_category,
            SUM(amount) as total_expense
        FROM 
            expenses
        WHERE 
            DATE(date) BETWEEN ? AND ?
        GROUP BY 
            DATE(date), expense_type
        ORDER BY 
            date ASC
    ";
    
    $stmt = $conn->prepare($expenses_query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $expenses_result = $stmt->get_result();
    
    $expenses_data = [];
    $expenses_by_category = [];
    $total_expenses = 0;
    
    while ($row = $expenses_result->fetch_assoc()) {
        $expenses_data[] = $row;
        $total_expenses += $row['total_expense'];
        
        // تجميع المصروفات حسب الفئة
        if (!isset($expenses_by_category[$row['expense_category']])) {
            $expenses_by_category[$row['expense_category']] = 0;
        }
        $expenses_by_category[$row['expense_category']] += $row['total_expense'];
    }
    
    // 3. بيانات الإشغال
    $occupancy_query = "
        SELECT 
            COUNT(*) as total_bookings,
            SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings,
            SUM(CASE WHEN status = 'مكتملة' THEN 1 ELSE 0 END) as completed_bookings
        FROM 
            bookings
        WHERE 
            checkin_date BETWEEN ? AND ? OR checkout_date BETWEEN ? AND ?
    ";
    
    $stmt = $conn->prepare($occupancy_query);
    $stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
    $stmt->execute();
    $occupancy_result = $stmt->get_result();
    $occupancy_data = $occupancy_result->fetch_assoc();
    
    // 4. بيانات الغرف
    $rooms_query = "
        SELECT 
            r.room_number,
            r.type as room_type,
            COUNT(b.booking_id) as booking_count,
            SUM(p.amount) as room_revenue
        FROM 
            rooms r
        LEFT JOIN 
            bookings b ON r.room_number = b.room_number AND (b.checkin_date BETWEEN ? AND ? OR b.checkout_date BETWEEN ? AND ?)
        LEFT JOIN 
            payment p ON b.booking_id = p.booking_id
        GROUP BY 
            r.room_number
        ORDER BY 
            room_revenue DESC
    ";
    
    $stmt = $conn->prepare($rooms_query);
    $stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
    $stmt->execute();
    $rooms_result = $stmt->get_result();
    
    $rooms_data = [];
    while ($row = $rooms_result->fetch_assoc()) {
        $rooms_data[] = $row;
    }
    
    // 5. بيانات سحوبات الموظفين
    $withdrawals_query = "
        SELECT 
            e.name as employee_name,
            SUM(sw.amount) as total_withdrawals
        FROM 
            salary_withdrawals sw
        JOIN 
            employees e ON sw.employee_id = e.id
        WHERE 
            sw.date BETWEEN ? AND ?
        GROUP BY 
            sw.employee_id
        ORDER BY 
            total_withdrawals DESC
    ";
    
    $stmt = $conn->prepare($withdrawals_query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $withdrawals_result = $stmt->get_result();
    
    $withdrawals_data = [];
    $total_withdrawals = 0;
    
    while ($row = $withdrawals_result->fetch_assoc()) {
        $withdrawals_data[] = $row;
        $total_withdrawals += $row['total_withdrawals'];
    }
    
    // تجميع كل البيانات
    $report_data = [
        'revenue_data' => $revenue_data,
        'total_revenue' => $total_revenue,
        'expenses_data' => $expenses_data,
        'expenses_by_category' => $expenses_by_category,
        'total_expenses' => $total_expenses,
        'net_profit' => $total_revenue - $total_expenses,
        'occupancy_data' => $occupancy_data,
        'rooms_data' => $rooms_data,
        'withdrawals_data' => $withdrawals_data,
        'total_withdrawals' => $total_withdrawals,
        'generated_at' => date('Y-m-d H:i:s')
    ];
    
    // تخزين البيانات مؤقتًا لتحسين الأداء
    if (!is_dir("../../cache")) {
        mkdir("../../cache", 0755, true);
    }
    file_put_contents($cache_file, json_encode($report_data));
}

// تعيين عنوان الصفحة
$page_title = "التقارير الشاملة";
?>

<?php include_once '../../includes/header.php'; ?>
<?php add_date_styles(); ?>

<div class="container-fluid mt-4 rtl">
    <div class="row">
        <div class="col-12">
            <div class="card shadow-sm">
                <div class="card-header bg-primary text-white d-flex justify-content-between align-items-center">
                    <h5 class="mb-0">التقارير الشاملة</h5>
                    <div>
                        <button type="button" class="btn btn-sm btn-light" id="print-report">
                            <i class="fas fa-print"></i> طباعة
                        </button>
                        <button type="button" class="btn btn-sm btn-light" id="export-excel">
                            <i class="fas fa-file-excel"></i> تصدير Excel
                        </button>
                        <button type="button" class="btn btn-sm btn-light" id="export-pdf">
                            <i class="fas fa-file-pdf"></i> تصدير PDF
                        </button>
                    </div>
                </div>
                <div class="card-body">
                    <!-- فلاتر التقرير -->
                    <form id="report-filters" class="mb-4">
                        <div class="row">
                            <div class="col-md-3">
                                <div class="form-group">
                                    <label for="start_date">من تاريخ</label>
                                    <input type="date" class="form-control" id="start_date" name="start_date" value="<?php echo $start_date; ?>">
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="form-group">
                                    <label for="end_date">إلى تاريخ</label>
                                    <input type="date" class="form-control" id="end_date" name="end_date" value="<?php echo $end_date; ?>">
                                </div>
                            </div>
                            <div class="col-md-3">
                                <div class="form-group">
                                    <label for="report_type">نوع التقرير</label>
                                    <select class="form-control" id="report_type" name="report_type">
                                        <option value="all" <?php echo $report_type == 'all' ? 'selected' : ''; ?>>جميع التقارير</option>
                                        <option value="revenue" <?php echo $report_type == 'revenue' ? 'selected' : ''; ?>>الإيرادات</option>
                                        <option value="expenses" <?php echo $report_type == 'expenses' ? 'selected' : ''; ?>>المصروفات</option>
                                        <option value="occupancy" <?php echo $report_type == 'occupancy' ? 'selected' : ''; ?>>الإشغال</option>
                                        <option value="rooms" <?php echo $report_type == 'rooms' ? 'selected' : ''; ?>>الغرف</option>
                                        <option value="withdrawals" <?php echo $report_type == 'withdrawals' ? 'selected' : ''; ?>>سحوبات الموظفين</option>
                                    </select>
                                </div>
                            </div>
                            <div class="col-md-3 d-flex align-items-end">
                                <button type="submit" class="btn btn-primary">
                                    <i class="fas fa-filter"></i> تصفية
                                </button>
                                <button type="button" class="btn btn-secondary mr-2" id="reset-filters">
                                    <i class="fas fa-sync"></i> إعادة تعيين
                                </button>
                            </div>
                        </div>
                    </form>
                    
                    <!-- اختصارات التاريخ -->
                    <div class="date-shortcuts mb-4">
                        <button type="button" class="btn btn-outline-secondary btn-sm date-shortcut" data-range="today">اليوم</button>
                        <button type="button" class="btn btn-outline-secondary btn-sm date-shortcut" data-range="yesterday">الأمس</button>
                        <button type="button" class="btn btn-outline-secondary btn-sm date-shortcut" data-range="this_week">هذا الأسبوع</button>
                        <button type="button" class="btn btn-outline-secondary btn-sm date-shortcut" data-range="last_week">الأسبوع الماضي</button>
                        <button type="button" class="btn btn-outline-secondary btn-sm date-shortcut" data-range="this_month">هذا الشهر</button>
                        <button type="button" class="btn btn-outline-secondary btn-sm date-shortcut" data-range="last_month">الشهر الماضي</button>
                        <button type="button" class="btn btn-outline-secondary btn-sm date-shortcut" data-range="this_year">هذه السنة</button>
                    </div>
                    
                    <!-- بطاقات الملخص -->
                    <div class="row mb-4">
                        <div class="col-md-3">
                            <div class="card bg-success text-white">
                                <div class="card-body">
                                    <h6 class="card-title">إجمالي الإيرادات</h6>
                                    <h3 class="card-text"><?php echo number_format($report_data['total_revenue'], 2); ?> ريال</h3>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card bg-danger text-white">
                                <div class="card-body">
                                    <h6 class="card-title">إجمالي المصروفات</h6>
                                    <h3 class="card-text"><?php echo number_format($report_data['total_expenses'], 2); ?> ريال</h3>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card bg-info text-white">
                                <div class="card-body">
                                    <h6 class="card-title">صافي الربح</h6>
                                    <h3 class="card-text"><?php echo number_format($report_data['net_profit'], 2); ?> ريال</h3>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card bg-warning text-dark">
                                <div class="card-body">
                                    <h6 class="card-title">إجمالي سحوبات الموظفين</h6>
                                    <h3 class="card-text"><?php echo number_format($report_data['total_withdrawals'], 2); ?> ريال</h3>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- تبويبات التقارير -->
                    <ul class="nav nav-tabs" id="reportTabs" role="tablist">
                        <li class="nav-item">
                            <a class="nav-link active" id="revenue-tab" data-toggle="tab" href="#revenue" role="tab">الإيرادات</a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" id="expenses-tab" data-toggle="tab" href="#expenses" role="tab">المصروفات</a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" id="occupancy-tab" data-toggle="tab" href="#occupancy" role="tab">الإشغال</a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" id="rooms-tab" data-toggle="tab" href="#rooms" role="tab">الغرف</a>
                        </li>
                        <li class="nav-item">
                            <a class="nav-link" id="withdrawals-tab" data-toggle="tab" href="#withdrawals" role="tab">سحوبات الموظفين</a>
                        </li>
                    </ul>
                    
                    <!-- محتوى التبويبات -->
                    <div class="tab-content mt-3" id="reportTabsContent">
                        <!-- تبويب الإيرادات -->
                        <div class="tab-pane fade show active" id="revenue" role="tabpanel">
                            <div class="row">
                                <div class="col-md-8">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">الإيرادات اليومية</h6>
                                        </div>
                                        <div class="card-body">
                                            <canvas id="revenueChart" height="300"></canvas>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-4">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">تفاصيل الإيرادات</h6>
                                        </div>
                                        <div class="card-body">
                                            <div class="table-responsive" style="max-height: 300px; overflow-y: auto;">
                                                <table class="table table-sm table-hover">
                                                    <thead>
                                                        <tr>
                                                            <th>التاريخ</th>
                                                            <th>المبلغ</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        <?php foreach ($report_data['revenue_data'] as $revenue): ?>
                                                        <tr>
                                                            <td><?php echo date('Y-m-d', strtotime($revenue['date'])); ?></td>
                                                            <td><?php echo number_format($revenue['total_revenue'], 2); ?> ريال</td>
                                                        </tr>
                                                        <?php endforeach; ?>
                                                    </tbody>
                                                </table>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- تبويب المصروفات -->
                        <div class="tab-pane fade" id="expenses" role="tabpanel">
                            <div class="row">
                                <div class="col-md-8">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">المصروفات حسب الفئة</h6>
                                        </div>
                                        <div class="card-body">
                                            <canvas id="expensesChart" height="300"></canvas>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-4">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">تفاصيل المصروفات</h6>
                                        </div>
                                        <div class="card-body">
                                            <div class="table-responsive" style="max-height: 300px; overflow-y: auto;">
                                                <table class="table table-sm table-hover">
                                                    <thead>
                                                        <tr>
                                                            <th>الفئة</th>
                                                            <th>المبلغ</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        <?php foreach ($report_data['expenses_by_category'] as $category => $amount): ?>
                                                        <tr>
                                                            <td><?php echo $category; ?></td>
                                                            <td><?php echo number_format($amount, 2); ?> ريال</td>
                                                        </tr>
                                                        <?php endforeach; ?>
                                                    </tbody>
                                                </table>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- تبويب الإشغال -->
                        <div class="tab-pane fade" id="occupancy" role="tabpanel">
                            <div class="row">
                                <div class="col-md-6">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">معدل الإشغال</h6>
                                        </div>
                                        <div class="card-body">
                                            <canvas id="occupancyChart" height="300"></canvas>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-6">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">إحصائيات الإشغال</h6>
                                        </div>
                                        <div class="card-body">
                                            <div class="table-responsive">
                                                <table class="table table-bordered">
                                                    <tbody>
                                                        <tr>
                                                            <th>إجمالي الحجوزات</th>
                                                            <td><?php echo $report_data['occupancy_data']['total_bookings']; ?></td>
                                                        </tr>
                                                        <tr>
                                                            <th>الحجوزات النشطة</th>
                                                            <td><?php echo $report_data['occupancy_data']['active_bookings']; ?></td>
                                                        </tr>
                                                        <tr>
                                                            <th>الحجوزات المكتملة</th>
                                                            <td><?php echo $report_data['occupancy_data']['completed_bookings']; ?></td>
                                                        </tr>
                                                        <tr>
                                                            <th>معدل الإشغال</th>
                                                            <td>
                                                                <?php 
                                                                // حساب معدل الإشغال
                                                                $occupancy_rate = 0;
                                                                if ($report_data['occupancy_data']['total_bookings'] > 0) {
                                                                    $occupancy_rate = ($report_data['occupancy_data']['active_bookings'] / $report_data['occupancy_data']['total_bookings']) * 100;
                                                                }
                                                                echo number_format($occupancy_rate, 2) . '%';
                                                                ?>
                                                            </td>
                                                        </tr>
                                                    </tbody>
                                                </table>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- تبويب الغرف -->
                        <div class="tab-pane fade" id="rooms" role="tabpanel">
                            <div class="card shadow-sm mb-4">
                                <div class="card-header">
                                    <h6 class="mb-0">أداء الغرف</h6>
                                </div>
                                <div class="card-body">
                                    <div class="table-responsive">
                                        <table class="table table-striped table-hover" id="roomsTable">
                                            <thead>
                                                <tr>
                                                    <th>رقم الغرفة</th>
                                                    <th>نوع الغرفة</th>
                                                    <th>عدد الحجوزات</th>
                                                    <th>الإيرادات</th>
                                                </tr>
                                            </thead>
                                            <tbody>
                                                <?php foreach ($report_data['rooms_data'] as $room): ?>
                                                <tr>
                                                    <td><?php echo $room['room_number']; ?></td>
                                                    <td><?php echo $room['room_type']; ?></td>
                                                    <td><?php echo $room['booking_count']; ?></td>
                                                    <td><?php echo number_format($room['room_revenue'], 2); ?> ريال</td>
                                                </tr>
                                                <?php endforeach; ?>
                                            </tbody>
                                        </table>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- تبويب سحوبات الموظفين -->
                        <div class="tab-pane fade" id="withdrawals" role="tabpanel">
                            <div class="row">
                                <div class="col-md-8">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">سحوبات الموظفين</h6>
                                        </div>
                                        <div class="card-body">
                                            <canvas id="withdrawalsChart" height="300"></canvas>
                                        </div>
                                    </div>
                                </div>
                                <div class="col-md-4">
                                    <div class="card shadow-sm mb-4">
                                        <div class="card-header">
                                            <h6 class="mb-0">تفاصيل السحوبات</h6>
                                        </div>
                                        <div class="card-body">
                                            <div class="table-responsive" style="max-height: 300px; overflow-y: auto;">
                                                <table class="table table-sm table-hover">
                                                    <thead>
                                                        <tr>
                                                            <th>الموظف</th>
                                                            <th>المبلغ</th>
                                                        </tr>
                                                    </thead>
                                                    <tbody>
                                                        <?php foreach ($report_data['withdrawals_data'] as $withdrawal): ?>
                                                        <tr>
                                                            <td><?php echo $withdrawal['employee_name']; ?></td>
                                                            <td><?php echo number_format($withdrawal['total_withdrawals'], 2); ?> ريال</td>
                                                        </tr>
                                                        <?php endforeach; ?>
                                                    </tbody>
                                                </table>
                                            </div>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                <div class="card-footer text-muted">
                    <small>تم إنشاء التقرير في: <?php echo $report_data['generated_at']; ?></small>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- تضمين Chart.js -->
<script src="https://cdn.jsdelivr.net/npm/chart.js@3.7.0/dist/chart.min.js"></script>
<!-- تضمين DataTables -->
<script src="https://cdn.datatables.net/1.11.5/js/jquery.dataTables.min.js"></script>
<script src="https://cdn.datatables.net/1.11.5/js/dataTables.bootstrap4.min.js"></script>
<link rel="stylesheet" href="https://cdn.datatables.net/1.11.5/css/dataTables.bootstrap4.min.css">

<script>
// تحسين الأداء: تحميل الرسوم البيانية بشكل متأخر
document.addEventListener('DOMContentLoaded', function() {
    // تهيئة DataTables
    $('#roomsTable').DataTable({
        "language": {
            "url": "//cdn.datatables.net/plug-ins/1.11.5/i18n/ar.json"
        },
        "pageLength": 10,
        "responsive": true
    });
    
    // تهيئة الرسوم البيانية
    initCharts();
    
    // معالجة النقر على اختصارات التاريخ
    document.querySelectorAll('.date-shortcut').forEach(button => {
        button.addEventListener('click', function() {
            const range = this.dataset.range;
            const today = new Date();
            let startDate, endDate;
            
            switch(range) {
                case 'today':
                    startDate = formatDate(today);
                    endDate = formatDate(today);
                    break;
                case 'yesterday':
                    const yesterday = new Date(today);
                    yesterday.setDate(yesterday.getDate() - 1);
                    startDate = formatDate(yesterday);
                    endDate = formatDate(yesterday);
                    break;
                case 'this_week':
                    const firstDayOfWeek = new Date(today);
                    firstDayOfWeek.setDate(today.getDate() - today.getDay());
                    startDate = formatDate(firstDayOfWeek);
                    endDate = formatDate(today);
                    break;
                case 'last_week':
                    const lastWeekStart = new Date(today);
                    lastWeekStart.setDate(today.getDate() - today.getDay() - 7);
                    const lastWeekEnd = new Date(today);
                    lastWeekEnd.setDate(today.getDate() - today.getDay() - 1);
                    startDate = formatDate(lastWeekStart);
                    endDate = formatDate(lastWeekEnd);
                    break;
                case 'this_month':
                    startDate = today.getFullYear() + '-' + (today.getMonth() + 1).toString().padStart(2, '0') + '-01';
                    endDate = formatDate(today);
                    break;
                case 'last_month':
                    const lastMonth = new Date(today);
                    lastMonth.setMonth(today.getMonth() - 1);
                    startDate = lastMonth.getFullYear() + '-' + (lastMonth.getMonth() + 1).toString().padStart(2, '0') + '-01';
                    endDate = lastMonth.getFullYear() + '-' + (lastMonth.getMonth() + 1).toString().padStart(2, '0') + '-' + new Date(lastMonth.getFullYear(), lastMonth.getMonth() + 1, 0).getDate();
                    break;
                case 'this_year':
                    startDate = today.getFullYear() + '-01-01';
                    endDate = formatDate(today);
                    break;
            }
            
            document.getElementById('start_date').value = startDate;
            document.getElementById('end_date').value = endDate;
            document.getElementById('report-filters').submit();
        });
    });
    
    // معالجة إعادة تعيين الفلاتر
    document.getElementById('reset-filters').addEventListener('click', function() {
        document.getElementById('start_date').value = '<?php echo $first_day_of_month; ?>';
        document.getElementById('end_date').value = '<?php echo $last_day_of_month; ?>';
        document.getElementById('report_type').value = 'all';
        document.getElementById('report-filters').submit();
    });
    
    // معالجة طباعة التقرير
    document.getElementById('print-report').addEventListener('click', function() {
        window.print();
    });
    
    // معالجة تصدير Excel
    document.getElementById('export-excel').addEventListener('click', function() {
        window.location.href = 'export_excel.php?start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?>&report_type=<?php echo $report_type; ?>';
    });
    
    // معالجة تصدير PDF
    document.getElementById('export-pdf').addEventListener('click', function() {
        window.location.href = 'export_pdf.php?start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?>&report_type=<?php echo $report_type; ?>';
    });
});

// تنسيق التاريخ
function formatDate(date) {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
}

// تهيئة الرسوم البيانية
function initCharts() {
    // بيانات الرسوم البيانية
    const revenueData = <?php echo json_encode(array_map(function($item) { return ['date' => $item['date'], 'amount' => $item['total_revenue']]; }, $report_data['revenue_data'])); ?>;
    const expenseCategories = <?php echo json_encode(array_keys($report_data['expenses_by_category'])); ?>;
    const expenseAmounts = <?php echo json_encode(array_values($report_data['expenses_by_category'])); ?>;
    const withdrawalsData = <?php echo json_encode(array_map(function($item) { return ['name' => $item['employee_name'], 'amount' => $item['total_withdrawals']]; }, $report_data['withdrawals_data'])); ?>;
    const occupancyData = <?php echo json_encode([
        $report_data['occupancy_data']['active_bookings'],
        $report_data['occupancy_data']['completed_bookings'],
        $report_data['occupancy_data']['total_bookings'] - $report_data['occupancy_data']['active_bookings'] - $report_data['occupancy_data']['completed_bookings']
    ]); ?>;
    
    // تحسين الأداء: استخدام Intersection Observer لتحميل الرسوم البيانية عند الحاجة
    const chartObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const chartId = entry.target.id;
                
                switch(chartId) {
                    case 'revenueChart':
                        createRevenueChart(revenueData);
                        break;
                    case 'expensesChart':
                        createExpensesChart(expenseCategories, expenseAmounts);
                        break;
                    case 'occupancyChart':
                        createOccupancyChart(occupancyData);
                        break;
                    case 'withdrawalsChart':
                        createWithdrawalsChart(withdrawalsData);
                        break;
                }
                
                // إلغاء مراقبة العنصر بعد تحميله
                observer.unobserve(entry.target);
            }
        });
    }, { threshold: 0.1 });
    
    // مراقبة عناصر الرسوم البيانية
    document.querySelectorAll('canvas').forEach(canvas => {
        chartObserver.observe(canvas);
    });
    
    // تحميل الرسم البياني الأول مباشرة (الإيرادات)
    createRevenueChart(revenueData);
}

// إنشاء رسم بياني للإيرادات
function createRevenueChart(data) {
    const ctx = document.getElementById('revenueChart').getContext('2d');
    
    new Chart(ctx, {
        type: 'line',
        data: {
            labels: data.map(item => item.date),
            datasets: [{
                label: 'الإيرادات اليومية',
                data: data.map(item => item.amount),
                backgroundColor: 'rgba(75, 192, 192, 0.2)',
                borderColor: 'rgba(75, 192, 192, 1)',
                borderWidth: 2,
                tension: 0.3,
                pointBackgroundColor: 'rgba(75, 192, 192, 1)'
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'top',
                    labels: {
                        font: {
                            family: 'Tajawal'
                        }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            return context.parsed.y.toLocaleString() + ' ريال';
                        }
                    }
                }
            },
            scales: {
                y: {
                    beginAtZero: true,
                    ticks: {
                        callback: function(value) {
                            return value.toLocaleString() + ' ريال';
                        }
                    }
                }
            }
        }
    });
}

// إنشاء رسم بياني للمصروفات
function createExpensesChart(categories, amounts) {
    const ctx = document.getElementById('expensesChart').getContext('2d');
    
    // توليد ألوان عشوائية
    const backgroundColors = categories.map(() => {
        const r = Math.floor(Math.random() * 255);
        const g = Math.floor(Math.random() * 255);
        const b = Math.floor(Math.random() * 255);
        return `rgba(${r}, ${g}, ${b}, 0.7)`;
    });
    
    new Chart(ctx, {
        type: 'pie',
        data: {
            labels: categories,
            datasets: [{
                data: amounts,
                backgroundColor: backgroundColors,
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'right',
                    labels: {
                        font: {
                            family: 'Tajawal'
                        }
                    }
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            const value = context.parsed.toLocaleString() + ' ريال';
                            const percentage = ((context.parsed / context.dataset.data.reduce((a, b) => a + b, 0)) * 100).toFixed(1) + '%';
                            return `${context.label}: ${value} (${percentage})`;
                        }
                    }
                }
            }
        }
    });
}

// إنشاء رسم بياني للإشغال
function createOccupancyChart(data) {
    const ctx = document.getElementById('occupancyChart').getContext('2d');
    
    new Chart(ctx, {
        type: 'doughnut',
        data: {
            labels: ['الحجوزات النشطة', 'الحجوزات المكتملة', 'حجوزات أخرى'],
            datasets: [{
                data: data,
                backgroundColor: [
                    'rgba(54, 162, 235, 0.7)',
                    'rgba(75, 192, 192, 0.7)',
                    'rgba(255, 206, 86, 0.7)'
                ],
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            plugins: {
                legend: {
                    position: 'bottom',
                    labels: {
                        font: {
                            family: 'Tajawal'
                        }
                    }
                }
            }
        }
    });
}

// إنشاء رسم بياني لسحوبات الموظفين
function createWithdrawalsChart(data) {
    const ctx = document.getElementById('withdrawalsChart').getContext('2d');
    
    new Chart(ctx, {
        type: 'bar',
        data: {
            labels: data.map(item => item.name),
            datasets: [{
                label: 'سحوبات الموظفين',
                data: data.map(item => item.amount),
                backgroundColor: 'rgba(153, 102, 255, 0.7)',
                borderColor: 'rgba(153, 102, 255, 1)',
                borderWidth: 1
            }]
        },
        options: {
            responsive: true,
            maintainAspectRatio: false,
            indexAxis: 'y',
            plugins: {
                legend: {
                    display: false
                },
                tooltip: {
                    callbacks: {
                        label: function(context) {
                            return context.parsed.x.toLocaleString() + ' ريال';
                        }
                    }
                }
            },
            scales: {
                x: {
                    beginAtZero: true,
                    ticks: {
                        callback: function(value) {
                            return value.toLocaleString() + ' ريال';
                        }
                    }
                }
            }
        }
    });
}
</script>

<style>
/* تحسينات CSS للأداء والمظهر */
.rtl {
    direction: rtl;
    text-align: right;
}

.date-shortcuts {
    display: flex;
    flex-wrap: wrap;
    gap: 5px;
}

/* تحسين أداء التمرير */
.table-responsive {
    will-change: transform;
    transform: translateZ(0);
}

/* تحسين أداء الرسوم البيانية */
canvas {
    will-change: transform;
    transform: translateZ(0);
}

/* تحسينات للطباعة */
@media print {
    .btn, .nav-tabs, #report-filters, .date-shortcuts {
        display: none !important;
    }
    
    .tab-pane {
        display: block !important;
        opacity: 1 !important;
        visibility: visible !important;
    }
    
    .card {
        border: 1px solid #ddd !important;
        break-inside: avoid;
    }
    
    .container-fluid {
        width: 100% !important;
        padding: 0 !important;
    }
}

/* تحسين سرعة التحميل للصور */
img {
    content-visibility: auto;
}

/* تحسين أداء التحولات */
.card, .btn {
    transition: all 0.2s ease-out;
}

/* تحسين قراءة الجداول */
.table-striped tbody tr:nth-of-type(odd) {
    background-color: rgba(0, 0, 0, 0.03);
}

.table-hover tbody tr:hover {
    background-color: rgba(0, 0, 0, 0.075);
}
</style>

<?php include_once '../../includes/footer.php'; ?>
