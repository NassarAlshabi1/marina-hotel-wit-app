<?php
include_once '../../includes/db.php';
include_once '../../includes/header2.php';
include_once '../../includes/functions.php';
include_once '../../includes/report_functions.php';
//include_once '../../includes/header.php';
// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// التحقق من وجود الجداول المطلوبة
$required_tables = ['payment', 'bookings', 'expenses', 'employees', 'salary_withdrawals'];
foreach ($required_tables as $table) {
    $check_query = "SHOW TABLES LIKE '$table'";
    $result = $conn->query($check_query);
    if ($result->num_rows == 0) {
        die("الجدول المطلوب '$table' غير موجود في قاعدة البيانات");
    }
}

// تحديد التواريخ الافتراضية (الشهر الحالي)
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');
$report_type = isset($_GET['report_type']) ? $_GET['report_type'] : 'all';

// متغيرات لحفظ البيانات
$revenues = [];
$expenses = [];
$salary_withdrawals = [];
$total_revenue = 0;
$total_expenses = 0;
$total_withdrawals = 0;

// جلب الإيرادات (مع معالجة أعمدة مختلفة محتملة)
if ($report_type == 'all' || $report_type == 'revenues') {
    // أولاً نتحقق من الأعمدة الموجودة في جدول bookings
    $columns_query = "SHOW COLUMNS FROM bookings";
    $columns_result = $conn->query($columns_query);
    $available_columns = [];
    
    while ($col = $columns_result->fetch_assoc()) {
        $available_columns[] = $col['Field'];
    }
    
    // تحديد أعمدة الاسم والهاتف المتاحة
    $guest_name_column = 'booking_id'; // افتراضي
    $guest_phone_column = 'NULL';
    
    if (in_array('guest_name', $available_columns)) {
        $guest_name_column = 'b.guest_name';
    } elseif (in_array('name', $available_columns)) {
        $guest_name_column = 'b.name';
    } elseif (in_array('customer_name', $available_columns)) {
        $guest_name_column = 'b.customer_name';
    } elseif (in_array('client_name', $available_columns)) {
        $guest_name_column = 'b.client_name';
    } else {
        $guest_name_column = "'غير محدد'";
    }
    
    if (in_array('guest_phone', $available_columns)) {
        $guest_phone_column = 'b.guest_phone';
    } elseif (in_array('phone', $available_columns)) {
        $guest_phone_column = 'b.phone';
    } elseif (in_array('mobile', $available_columns)) {
        $guest_phone_column = 'b.mobile';
    } elseif (in_array('contact_phone', $available_columns)) {
        $guest_phone_column = 'b.contact_phone';
    } else {
        $guest_phone_column = "''";
    }
    
    $revenue_query = "
        SELECT 
            p.payment_id,
            p.booking_id,
            b.room_number,
            p.amount,
            p.payment_date,
            p.payment_method,
            p.notes,
            COALESCE($guest_name_column, 'غير محدد') as guest_name,
            COALESCE($guest_phone_column, '') as guest_phone
        FROM payment p
        JOIN bookings b ON p.booking_id = b.booking_id
        WHERE DATE(p.payment_date) BETWEEN ? AND ?
        ORDER BY p.payment_date DESC
    ";
    
    $stmt = $conn->prepare($revenue_query);
    if ($stmt === false) {
        die("خطأ في إعداد استعلام الإيرادات: " . $conn->error);
    }
    
    $stmt->bind_param("ss", $start_date, $end_date);
    if (!$stmt->execute()) {
        die("خطأ في تنفيذ استعلام الإيرادات: " . $stmt->error);
    }
    
    $result = $stmt->get_result();
    
    while ($row = $result->fetch_assoc()) {
        $total_revenue += $row['amount'];
        $revenues[] = $row;
    }
    $stmt->close();
}

// جلب المصروفات
if ($report_type == 'all' || $report_type == 'expenses') {
    $expenses_query = "
        SELECT 
            e.*,
            CASE 
                WHEN e.expense_type = 'salaries' THEN CONCAT('راتب الموظف: ', COALESCE(emp.name, 'غير محدد'))
                WHEN e.expense_type = 'utilities' THEN CONCAT('فاتورة: ', e.description)
                WHEN e.expense_type = 'purchases' THEN CONCAT('شراء: ', e.description)
                ELSE e.description
            END AS display_text
        FROM expenses e
        LEFT JOIN employees emp ON e.expense_type = 'salaries' AND e.related_id = emp.id
        WHERE DATE(e.date) BETWEEN ? AND ?
        ORDER BY e.date DESC
    ";
    
    $stmt = $conn->prepare($expenses_query);
    if ($stmt === false) {
        die("خطأ في إعداد استعلام المصروفات: " . $conn->error);
    }
    
    $stmt->bind_param("ss", $start_date, $end_date);
    if (!$stmt->execute()) {
        die("خطأ في تنفيذ استعلام المصروفات: " . $stmt->error);
    }
    
    $result = $stmt->get_result();
    
    while ($row = $result->fetch_assoc()) {
        $total_expenses += $row['amount'];
        $expenses[] = $row;
    }
    $stmt->close();
}

// جلب سحوبات الموظفين
if ($report_type == 'all' || $report_type == 'withdrawals') {
    $withdrawals_query = "
        SELECT 
            sw.*,
            e.name as employee_name
        FROM salary_withdrawals sw
        JOIN employees e ON sw.employee_id = e.id
        WHERE DATE(sw.date) BETWEEN ? AND ?
        ORDER BY sw.date DESC
    ";
    
    $stmt = $conn->prepare($withdrawals_query);
    if ($stmt === false) {
        die("خطأ في إعداد استعلام سحوبات الموظفين: " . $conn->error);
    }
    
    $stmt->bind_param("ss", $start_date, $end_date);
    if (!$stmt->execute()) {
        die("خطأ في تنفيذ استعلام سحوبات الموظفين: " . $stmt->error);
    }
    
    $result = $stmt->get_result();
    
    while ($row = $result->fetch_assoc()) {
        $total_withdrawals += $row['amount'];
        $salary_withdrawals[] = $row;
    }
    $stmt->close();
}

// حساب الصافي
$net_amount = $total_revenue - ($total_expenses + $total_withdrawals);
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>التقارير المالية الشاملة</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/arabic-support.css" rel="stylesheet">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
        }
        
        .report-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 25px;
            text-align: center;
        }
        
        .summary-card {
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
            transition: transform 0.3s ease;
        }
        
        .summary-card:hover {
            transform: translateY(-5px);
        }
        
        .revenue-card { border-left: 5px solid #28a745; }
        .expense-card { border-left: 5px solid #dc3545; }
        .withdrawal-card { border-left: 5px solid #ffc107; }
        .net-card { border-left: 5px solid #17a2b8; }
        
        .filter-card {
            background: white;
            border-radius: 15px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
            margin-bottom: 25px;
        }
        
        .table-container {
            background: white;
            border-radius: 15px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
            margin-bottom: 25px;
            overflow: hidden;
        }
        
        .table th {
            background-color: #f8f9fa;
            font-weight: bold;
            border: none;
            padding: 15px;
        }
        
        .table td {
            padding: 12px 15px;
            border: none;
            border-bottom: 1px solid #eee;
        }
        
        .amount-positive { color: #28a745; font-weight: bold; }
        .amount-negative { color: #dc3545; font-weight: bold; }
        .amount-warning { color: #ffc107; font-weight: bold; }
        .amount-info { color: #17a2b8; font-weight: bold; }
        
        .section-title {
            background: linear-gradient(90deg, #667eea, #764ba2);
            color: white;
            padding: 15px 20px;
            margin: 0;
            font-weight: bold;
        }
        
        .export-buttons {
            background: white;
            border-radius: 15px;
            box-shadow: 0 2px 10px rgba(0, 0, 0, 0.1);
            padding: 20px;
            margin-bottom: 25px;
        }
        
        .btn-export {
            margin: 5px;
            padding: 12px 25px;
            border-radius: 10px;
            transition: all 0.3s ease;
            font-weight: bold;
            position: relative;
            overflow: hidden;
        }
        
        .btn-export:hover {
            transform: translateY(-3px);
            box-shadow: 0 6px 20px rgba(0, 0, 0, 0.15);
        }
        
        .guest-info {
            font-size: 0.9em;
            color: #6c757d;
        }
        
        @media print {
            .no-print { display: none !important; }
            body { font-size: 12px; }
            .summary-card { break-inside: avoid; }
        }
    </style>
    <?php add_date_styles(); ?>
</head>
<body>
    <div class="container py-4">
        <!-- رأس التقرير -->
        <div class="report-header">
            <h1 class="mb-2"><i class="fas fa-chart-line me-3"></i>التقارير المالية الشاملة</h1>
            <p class="mb-0">تاريخ التقرير: <?php echo format_arabic_date(date('Y-m-d'), 'title'); ?></p>
        </div>



        <!-- بطاقة التصفية -->
        <div class="filter-card no-print">
            <div class="card-header bg-primary text-white">
                <h5 class="mb-0"><i class="fas fa-filter me-2"></i>تصفية التقارير</h5>
            </div>
            <div class="card-body">
                <form method="GET" class="row g-3">
                    <div class="col-md-3">
                        <label for="report_type" class="form-label">نوع التقرير</label>
                        <select id="report_type" name="report_type" class="form-select">
                            <option value="all" <?= $report_type == 'all' ? 'selected' : '' ?>>جميع التقارير</option>
                            <option value="revenues" <?= $report_type == 'revenues' ? 'selected' : '' ?>>الإيرادات فقط</option>
                            <option value="expenses" <?= $report_type == 'expenses' ? 'selected' : '' ?>>المصروفات فقط</option>
                            <option value="withdrawals" <?= $report_type == 'withdrawals' ? 'selected' : '' ?>>سحوبات الموظفين فقط</option>
                        </select>
                    </div>
                    <div class="col-md-3">
                        <label for="start_date" class="form-label">من تاريخ</label>
                        <input type="date" id="start_date" name="start_date" 
                               class="form-control" value="<?php echo $start_date; ?>">
                    </div>
                    <div class="col-md-3">
                        <label for="end_date" class="form-label">إلى تاريخ</label>
                        <input type="date" id="end_date" name="end_date" 
                               class="form-control" value="<?php echo $end_date; ?>">
                    </div>
                    <div class="col-md-3 d-flex align-items-end">
                        <button type="submit" class="btn btn-primary w-100">
                            <i class="fas fa-search me-2"></i>تطبيق الفلتر
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- أزرار التصدير -->
        <div class="export-buttons no-print">
            <div class="text-center">
                <h5 class="mb-4"><i class="fas fa-download me-2"></i>تصدير التقرير بصيغ مختلفة</h5>
                <div class="row justify-content-center">
                    <div class="col-md-2 col-6 mb-3">
                        <button onclick="window.print()" class="btn btn-success btn-export w-100">
                            <i class="fas fa-print fa-lg mb-2 d-block"></i>
                            <span>طباعة</span>
                        </button>
                    </div>
                    <div class="col-md-2 col-6 mb-3">
                        <a href="debug_bookings.php" class="btn btn-info btn-export w-100" target="_blank">
                            <i class="fas fa-bug fa-lg mb-2 d-block"></i>
                            <span>فحص الجدول</span>
                        </a>
                    </div>
                    <div class="col-md-2 col-6 mb-3">
                        <button onclick="exportToExcel()" class="btn btn-success btn-export w-100" id="excelBtn">
                            <i class="fas fa-file-excel fa-lg mb-2 d-block"></i>
                            <span>Excel</span>
                        </button>
                    </div>
                </div>
            </div>
        </div>

        <!-- ملخص المبالغ -->
        <div class="row mb-4">
            <?php if ($report_type == 'all' || $report_type == 'revenues'): ?>
            <div class="col-md-3">
                <div class="card summary-card revenue-card">
                    <div class="card-body text-center">
                        <i class="fas fa-arrow-up fa-2x text-success mb-2"></i>
                        <h5>إجمالي الإيرادات</h5>
                        <h3 class="amount-positive"><?= format_currency($total_revenue) ?></h3>
                        <small class="text-muted"><?= count($revenues) ?> معاملة</small>
                    </div>
                </div>
            </div>
            <?php endif; ?>

            <?php if ($report_type == 'all' || $report_type == 'expenses'): ?>
            <div class="col-md-3">
                <div class="card summary-card expense-card">
                    <div class="card-body text-center">
                        <i class="fas fa-arrow-down fa-2x text-danger mb-2"></i>
                        <h5>إجمالي المصروفات</h5>
                        <h3 class="amount-negative"><?= format_currency($total_expenses) ?></h3>
                        <small class="text-muted"><?= count($expenses) ?> معاملة</small>
                    </div>
                </div>
            </div>
            <?php endif; ?>

            <?php if ($report_type == 'all' || $report_type == 'withdrawals'): ?>
            <div class="col-md-3">
                <div class="card summary-card withdrawal-card">
                    <div class="card-body text-center">
                        <i class="fas fa-hand-holding-usd fa-2x text-warning mb-2"></i>
                        <h5>سحوبات الموظفين</h5>
                        <h3 class="amount-warning"><?= format_currency($total_withdrawals) ?></h3>
                        <small class="text-muted"><?= count($salary_withdrawals) ?> معاملة</small>
                    </div>
                </div>
            </div>
            <?php endif; ?>

            <?php if ($report_type == 'all'): ?>
            <div class="col-md-3">
                <div class="card summary-card net-card">
                    <div class="card-body text-center">
                        <i class="fas fa-calculator fa-2x text-info mb-2"></i>
                        <h5>الصافي</h5>
                        <h3 class="<?= $net_amount >= 0 ? 'amount-positive' : 'amount-negative' ?>">
                            <?= format_currency($net_amount) ?>
                        </h3>
                        <small class="text-muted">
                            <?php 
                            if ($total_revenue > 0) {
                                echo number_format(($net_amount / $total_revenue) * 100, 1) . '% ربحية';
                            }
                            ?>
                        </small>
                    </div>
                </div>
            </div>
            <?php endif; ?>
        </div>

        <!-- جدول الإيرادات -->
        <?php if (($report_type == 'all' || $report_type == 'revenues') && !empty($revenues)): ?>
        <div class="table-container">
            <h4 class="section-title">
                <i class="fas fa-money-bill-wave me-2"></i>تفاصيل الإيرادات (<?= count($revenues) ?> معاملة)
            </h4>
            <div class="table-responsive">
                <table class="table table-hover mb-0">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>رقم الدفعة</th>
                            <th>رقم الحجز</th>
                            <th>اسم النزيل</th>
                            <th>رقم الغرفة</th>
                            <th>المبلغ</th>
                            <th>طريقة الدفع</th>
                            <th>التاريخ</th>
                            <th>ملاحظات</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php $counter = 1; ?>
                        <?php foreach ($revenues as $revenue): ?>
                            <tr>
                                <td><?= $counter++ ?></td>
                                <td><?= htmlspecialchars($revenue['payment_id']) ?></td>
                                <td><?= htmlspecialchars($revenue['booking_id']) ?></td>
                                <td>
                                    <?= htmlspecialchars($revenue['guest_name']) ?>
                                    <?php if (!empty($revenue['guest_phone'])): ?>
                                        <div class="guest-info">
                                            <i class="fas fa-phone fa-sm"></i> <?= htmlspecialchars($revenue['guest_phone']) ?>
                                        </div>
                                    <?php endif; ?>
                                </td>
                                <td><?= htmlspecialchars($revenue['room_number']) ?></td>
                                <td class="amount-positive"><?= format_currency($revenue['amount']) ?></td>
                                <td><?= htmlspecialchars($revenue['payment_method']) ?></td>
                                <td><?= format_arabic_date($revenue['payment_date']) ?></td>
                                <td><?= htmlspecialchars($revenue['notes'] ?? '-') ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- جدول المصروفات -->
        <?php if (($report_type == 'all' || $report_type == 'expenses') && !empty($expenses)): ?>
        <div class="table-container">
            <h4 class="section-title">
                <i class="fas fa-receipt me-2"></i>تفاصيل المصروفات (<?= count($expenses) ?> معاملة)
            </h4>
            <div class="table-responsive">
                <table class="table table-hover mb-0">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>النوع</th>
                            <th>الوصف</th>
                            <th>المبلغ</th>
                            <th>التاريخ</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php $counter = 1; ?>
                        <?php foreach ($expenses as $expense): ?>
                            <tr>
                                <td><?= $counter++ ?></td>
                                <td>
                                    <?php 
                                    $types = [
                                        'salaries' => 'رواتب',
                                        'utilities' => 'فواتير',
                                        'purchases' => 'مشتريات',
                                        'other' => 'أخرى'
                                    ];
                                    echo $types[$expense['expense_type']] ?? $expense['expense_type'];
                                    ?>
                                </td>
                                <td><?= htmlspecialchars($expense['display_text']) ?></td>
                                <td class="amount-negative"><?= format_currency($expense['amount']) ?></td>
                                <td><?= format_arabic_date($expense['date']) ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- جدول سحوبات الموظفين -->
        <?php if (($report_type == 'all' || $report_type == 'withdrawals') && !empty($salary_withdrawals)): ?>
        <div class="table-container">
            <h4 class="section-title">
                <i class="fas fa-users me-2"></i>تفاصيل سحوبات الموظفين (<?= count($salary_withdrawals) ?> معاملة)
            </h4>
            <div class="table-responsive">
                <table class="table table-hover mb-0">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>اسم الموظف</th>
                            <th>المبلغ</th>
                            <th>التاريخ</th>
                            <th>ملاحظات</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php $counter = 1; ?>
                        <?php foreach ($salary_withdrawals as $withdrawal): ?>
                            <tr>
                                <td><?= $counter++ ?></td>
                                <td><?= htmlspecialchars($withdrawal['employee_name']) ?></td>
                                <td class="amount-warning"><?= format_currency($withdrawal['amount']) ?></td>
                                <td><?= format_arabic_date($withdrawal['date']) ?></td>
                                <td><?= htmlspecialchars($withdrawal['notes'] ?? '-') ?></td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- رسالة عدم وجود بيانات -->
        <?php if (empty($revenues) && empty($expenses) && empty($salary_withdrawals)): ?>
        <div class="alert alert-info text-center">
            <i class="fas fa-info-circle fa-2x mb-3"></i>
            <h5>لا توجد بيانات للعرض</h5>
            <p>لا توجد بيانات مطابقة للفترة المحددة ونوع التقرير المختار</p>
        </div>
        <?php endif; ?>

        <!-- العودة للوحة التحكم -->
        <div class="text-center mt-4 no-print">
            <a href="../dashboard.php" class="btn btn-secondary btn-lg">
                <i class="fas fa-arrow-left me-2"></i>العودة للوحة التحكم
            </a>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        function exportToExcel() {
            const params = new URLSearchParams(window.location.search);
            const exportUrl = 'export_excel.php?' + params.toString();
            window.location.href = exportUrl;
        }
    </script>
</body>
</html>

<?php $conn->close(); ?>
