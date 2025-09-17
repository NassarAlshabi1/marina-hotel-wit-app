<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';
include_once '../../includes/functions.php';
include_once '../../includes/report_functions.php';

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// تحديد التواريخ الافتراضية (الشهر الحالي)
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');
$employee_id = isset($_GET['employee_id']) ? (int)$_GET['employee_id'] : 0;

// جلب قائمة الموظفين
$employees_query = "SELECT id, name, basic_salary FROM employees WHERE status = 'active' ORDER BY name";
$employees_result = $conn->query($employees_query);
$employees = [];
while ($emp = $employees_result->fetch_assoc()) {
    $employees[] = $emp;
}

// إعداد الاستعلام الأساسي
$where_conditions = ["DATE(sw.date) BETWEEN ? AND ?"];
$params = [$start_date, $end_date];
$param_types = "ss";

if ($employee_id > 0) {
    $where_conditions[] = "sw.employee_id = ?";
    $params[] = $employee_id;
    $param_types .= "i";
}

// جلب بيانات سحوبات الموظفين مع تفاصيل الراتب
$withdrawals_query = "
    SELECT
        e.id as employee_id,
        e.name as employee_name,
        e.basic_salary as monthly_salary,
        sw.id as withdrawal_id,
        sw.amount as withdrawal_amount,
        sw.date as withdrawal_date,
        sw.notes,
        sw.created_at,
        (SELECT COALESCE(SUM(amount), 0) 
         FROM salary_withdrawals 
         WHERE employee_id = e.id 
         AND YEAR(date) = YEAR(sw.date) 
         AND MONTH(date) = MONTH(sw.date)
         AND date <= sw.date) as total_withdrawn_month,
        (SELECT COALESCE(SUM(amount), 0) 
         FROM salary_withdrawals 
         WHERE employee_id = e.id 
         AND DATE(date) BETWEEN ? AND ?) as total_withdrawn_period
    FROM salary_withdrawals sw
    JOIN employees e ON sw.employee_id = e.id
    WHERE " . implode(" AND ", $where_conditions) . "
    ORDER BY sw.date DESC, e.name ASC
";

// تحضير المعاملات للاستعلام
$all_params = array_merge([$start_date, $end_date], $params);
$all_param_types = "ss" . $param_types;

$stmt = $conn->prepare($withdrawals_query);
$stmt->bind_param($all_param_types, ...$all_params);
$stmt->execute();
$withdrawals_result = $stmt->get_result();

$withdrawals_data = [];
$employee_summaries = [];
$total_withdrawals = 0;

while ($row = $withdrawals_result->fetch_assoc()) {
    $withdrawals_data[] = $row;
    $total_withdrawals += $row['withdrawal_amount'];
    
    // تجميع البيانات حسب الموظف
    $emp_id = $row['employee_id'];
    if (!isset($employee_summaries[$emp_id])) {
        $employee_summaries[$emp_id] = [
            'name' => $row['employee_name'],
            'monthly_salary' => $row['monthly_salary'],
            'total_withdrawn' => 0,
            'withdrawal_count' => 0,
            'remaining_salary' => $row['monthly_salary']
        ];
    }
    
    $employee_summaries[$emp_id]['total_withdrawn'] += $row['withdrawal_amount'];
    $employee_summaries[$emp_id]['withdrawal_count']++;
    $employee_summaries[$emp_id]['remaining_salary'] = $row['monthly_salary'] - $row['total_withdrawn_period'];
}

$stmt->close();
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تقرير سحوبات الموظفين المفصل</title>
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
            padding: 25px;
            border-radius: 15px;
            margin-bottom: 30px;
            text-align: center;
        }
        
        .summary-card {
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
            margin-bottom: 25px;
            transition: transform 0.3s ease;
            border: none;
        }
        
        .summary-card:hover {
            transform: translateY(-5px);
        }
        
        .employee-card {
            border-left: 5px solid #28a745;
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
        }
        
        .withdrawal-card {
            border-left: 5px solid #ffc107;
            background: linear-gradient(135deg, #fff3cd 0%, #ffeaa7 100%);
        }
        
        .remaining-card {
            border-left: 5px solid #17a2b8;
            background: linear-gradient(135deg, #d1ecf1 0%, #bee5eb 100%);
        }
        
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
            background-color: #495057;
            color: white;
            font-weight: bold;
            border: none;
            padding: 15px;
            text-align: center;
        }
        
        .table td {
            padding: 12px 15px;
            border: none;
            border-bottom: 1px solid #eee;
            text-align: center;
            vertical-align: middle;
        }
        
        .amount-positive { color: #28a745; font-weight: bold; }
        .amount-negative { color: #dc3545; font-weight: bold; }
        .amount-warning { color: #ffc107; font-weight: bold; }
        .amount-info { color: #17a2b8; font-weight: bold; }
        
        .section-title {
            background: linear-gradient(90deg, #495057, #6c757d);
            color: white;
            padding: 15px 20px;
            margin: 0;
            font-weight: bold;
        }
        
        .progress-bar-custom {
            height: 25px;
            border-radius: 12px;
            position: relative;
            overflow: hidden;
        }
        
        .progress-text {
            position: absolute;
            top: 50%;
            left: 50%;
            transform: translate(-50%, -50%);
            color: white;
            font-weight: bold;
            font-size: 12px;
            z-index: 1;
        }
        
        .employee-summary {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            border-radius: 10px;
            padding: 15px;
            margin-bottom: 15px;
            border-left: 4px solid #007bff;
        }
        
        .withdrawal-badge {
            background: linear-gradient(45deg, #ffc107, #ffca2c);
            color: #212529;
            padding: 5px 10px;
            border-radius: 15px;
            font-size: 12px;
            font-weight: bold;
        }
        
        .salary-progress {
            background-color: #e9ecef;
            border-radius: 10px;
            overflow: hidden;
            height: 20px;
            margin-top: 5px;
        }
        
        .salary-progress-bar {
            height: 100%;
            transition: width 0.3s ease;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-size: 11px;
            font-weight: bold;
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
            <h1 class="mb-2"><i class="fas fa-users-cog me-3"></i>تقرير سحوبات الموظفين المفصل</h1>
            <p class="mb-1">المبالغ المسحوبة والرواتب المتبقية</p>
            <p class="mb-0">تاريخ التقرير: <?php echo format_arabic_date(date('Y-m-d'), 'title'); ?></p>
        </div>

        <!-- بطاقة التصفية -->
        <div class="filter-card no-print">
            <div class="card-header bg-primary text-white">
                <h5 class="mb-0"><i class="fas fa-filter me-2"></i>تصفية التقرير</h5>
            </div>
            <div class="card-body">
                <form method="GET" class="row g-3">
                    <div class="col-md-3">
                        <label for="employee_id" class="form-label">الموظف</label>
                        <select id="employee_id" name="employee_id" class="form-select">
                            <option value="0">جميع الموظفين</option>
                            <?php foreach ($employees as $emp): ?>
                                <option value="<?= $emp['id'] ?>" <?= $employee_id == $emp['id'] ? 'selected' : '' ?>>
                                    <?= htmlspecialchars($emp['name']) ?> (راتب: <?= format_currency($emp['basic_salary']) ?>)
                                </option>
                            <?php endforeach; ?>
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

        <!-- ملخص عام -->
        <div class="row mb-4">
            <div class="col-md-4">
                <div class="card summary-card employee-card">
                    <div class="card-body text-center">
                        <i class="fas fa-users fa-2x text-success mb-3"></i>
                        <h5>عدد الموظفين</h5>
                        <h3 class="text-success"><?= count($employee_summaries) ?></h3>
                        <small class="text-muted">موظف نشط</small>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card summary-card withdrawal-card">
                    <div class="card-body text-center">
                        <i class="fas fa-hand-holding-usd fa-2x text-warning mb-3"></i>
                        <h5>إجمالي السحوبات</h5>
                        <h3 class="amount-warning"><?= format_currency($total_withdrawals) ?></h3>
                        <small class="text-muted"><?= count($withdrawals_data) ?> عملية سحب</small>
                    </div>
                </div>
            </div>
            <div class="col-md-4">
                <div class="card summary-card remaining-card">
                    <div class="card-body text-center">
                        <i class="fas fa-calculator fa-2x text-info mb-3"></i>
                        <h5>متوسط السحب</h5>
                        <h3 class="amount-info">
                            <?= count($withdrawals_data) > 0 ? format_currency($total_withdrawals / count($withdrawals_data)) : format_currency(0) ?>
                        </h3>
                        <small class="text-muted">لكل عملية سحب</small>
                    </div>
                </div>
            </div>
        </div>

        <!-- ملخص الموظفين -->
        <?php if (!empty($employee_summaries)): ?>
        <div class="table-container">
            <h4 class="section-title">
                <i class="fas fa-chart-bar me-2"></i>ملخص الموظفين والرواتب المتبقية
            </h4>
            <div class="table-responsive">
                <table class="table table-hover mb-0">
                    <thead>
                        <tr>
                            <th>اسم الموظف</th>
                            <th>الراتب الشهري</th>
                            <th>إجمالي المسحوب</th>
                            <th>الراتب المتبقي</th>
                            <th>نسبة السحب</th>
                            <th>عدد السحوبات</th>
                            <th>حالة الراتب</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($employee_summaries as $emp_id => $summary): ?>
                            <?php 
                            $withdrawal_percentage = $summary['monthly_salary'] > 0 ? 
                                ($summary['total_withdrawn'] / $summary['monthly_salary']) * 100 : 0;
                            $remaining_percentage = 100 - $withdrawal_percentage;
                            
                            // تحديد لون شريط التقدم
                            $progress_color = '';
                            if ($withdrawal_percentage <= 50) {
                                $progress_color = 'bg-success';
                            } elseif ($withdrawal_percentage <= 80) {
                                $progress_color = 'bg-warning';
                            } else {
                                $progress_color = 'bg-danger';
                            }
                            ?>
                            <tr>
                                <td class="text-start">
                                    <strong><?= htmlspecialchars($summary['name']) ?></strong>
                                </td>
                                <td class="amount-info"><?= format_currency($summary['monthly_salary']) ?></td>
                                <td class="amount-warning"><?= format_currency($summary['total_withdrawn']) ?></td>
                                <td class="amount-positive"><?= format_currency($summary['remaining_salary']) ?></td>
                                <td>
                                    <div class="progress-bar-custom">
                                        <div class="progress">
                                            <div class="progress-bar <?= $progress_color ?>" 
                                                 style="width: <?= min($withdrawal_percentage, 100) ?>%">
                                            </div>
                                        </div>
                                        <div class="progress-text">
                                            <?= number_format($withdrawal_percentage, 1) ?>%
                                        </div>
                                    </div>
                                </td>
                                <td>
                                    <span class="withdrawal-badge">
                                        <?= $summary['withdrawal_count'] ?> مرة
                                    </span>
                                </td>
                                <td>
                                    <?php if ($withdrawal_percentage <= 50): ?>
                                        <span class="badge bg-success">ممتاز</span>
                                    <?php elseif ($withdrawal_percentage <= 80): ?>
                                        <span class="badge bg-warning">متوسط</span>
                                    <?php else: ?>
                                        <span class="badge bg-danger">تحذير</span>
                                    <?php endif; ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- تفاصيل السحوبات -->
        <?php if (!empty($withdrawals_data)): ?>
        <div class="table-container">
            <h4 class="section-title">
                <i class="fas fa-list-alt me-2"></i>تفاصيل عمليات السحب (<?= count($withdrawals_data) ?> عملية)
            </h4>
            <div class="table-responsive">
                <table class="table table-hover mb-0">
                    <thead>
                        <tr>
                            <th>#</th>
                            <th>اسم الموظف</th>
                            <th>الراتب الشهري</th>
                            <th>مبلغ السحب</th>
                            <th>إجمالي المسحوب (الشهر)</th>
                            <th>المتبقي من الراتب</th>
                            <th>تاريخ السحب</th>
                            <th>ملاحظات</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php $counter = 1; ?>
                        <?php foreach ($withdrawals_data as $withdrawal): ?>
                            <?php 
                            $remaining_salary = $withdrawal['monthly_salary'] - $withdrawal['total_withdrawn_month'];
                            $withdrawal_percentage = $withdrawal['monthly_salary'] > 0 ? 
                                ($withdrawal['total_withdrawn_month'] / $withdrawal['monthly_salary']) * 100 : 0;
                            ?>
                            <tr>
                                <td><?= $counter++ ?></td>
                                <td class="text-start">
                                    <strong><?= htmlspecialchars($withdrawal['employee_name']) ?></strong>
                                </td>
                                <td class="amount-info"><?= format_currency($withdrawal['monthly_salary']) ?></td>
                                <td class="amount-warning"><?= format_currency($withdrawal['withdrawal_amount']) ?></td>
                                <td class="amount-negative"><?= format_currency($withdrawal['total_withdrawn_month']) ?></td>
                                <td>
                                    <div class="d-flex flex-column">
                                        <span class="amount-positive"><?= format_currency($remaining_salary) ?></span>
                                        <div class="salary-progress">
                                            <div class="salary-progress-bar <?= $withdrawal_percentage > 80 ? 'bg-danger' : ($withdrawal_percentage > 50 ? 'bg-warning' : 'bg-success') ?>" 
                                                 style="width: <?= min($withdrawal_percentage, 100) ?>%">
                                                <?= number_format($withdrawal_percentage, 0) ?>%
                                            </div>
                                        </div>
                                    </div>
                                </td>
                                <td><?= format_arabic_date($withdrawal['withdrawal_date']) ?></td>
                                <td class="text-start">
                                    <?= htmlspecialchars($withdrawal['notes'] ?? '-') ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    </tbody>
                </table>
            </div>
        </div>
        <?php endif; ?>

        <!-- رسالة عدم وجود بيانات -->
        <?php if (empty($withdrawals_data)): ?>
        <div class="alert alert-info text-center">
            <i class="fas fa-info-circle fa-2x mb-3"></i>
            <h5>لا توجد سحوبات للعرض</h5>
            <p>لا توجد عمليات سحب مطابقة للفترة المحددة والموظف المختار</p>
        </div>
        <?php endif; ?>

        <!-- أزرار التحكم -->
        <div class="text-center mt-4 no-print">
            <div class="btn-group" role="group">
                <button onclick="window.print()" class="btn btn-success me-2">
                    <i class="fas fa-print me-2"></i>طباعة التقرير
                </button>
                <button onclick="exportToExcel()" class="btn btn-info me-2">
                    <i class="fas fa-file-excel me-2"></i>تصدير إكسل
                </button>
                <button onclick="exportToPDF()" class="btn btn-danger me-2">
                    <i class="fas fa-file-pdf me-2"></i>تصدير PDF
                </button>
                <a href="../dashboard.php" class="btn btn-secondary">
                    <i class="fas fa-arrow-left me-2"></i>العودة للوحة التحكم
                </a>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // التحقق من صحة التواريخ
        document.getElementById('start_date').addEventListener('change', function() {
            const startDate = new Date(this.value);
            const endDateInput = document.getElementById('end_date');
            
            if (endDateInput.value) {
                const endDate = new Date(endDateInput.value);
                if (startDate > endDate) {
                    alert('تاريخ البداية لا يمكن أن يكون بعد تاريخ النهاية');
                    this.value = '<?php echo $start_date; ?>';
                }
            }
        });

        document.getElementById('end_date').addEventListener('change', function() {
            const startDateInput = document.getElementById('start_date');
            if (!startDateInput.value) {
                alert('الرجاء تحديد تاريخ البداية أولاً');
                this.value = '<?php echo $end_date; ?>';
                return;
            }

            const startDate = new Date(startDateInput.value);
            const endDate = new Date(this.value);
            
            if (endDate < startDate) {
                alert('تاريخ النهاية لا يمكن أن يكون قبل تاريخ البداية');
                this.value = '<?php echo $end_date; ?>';
            }
        });

        // دالة تصدير Excel
        function exportToExcel() {
            const params = new URLSearchParams(window.location.search);
            const exportUrl = 'export_employee_withdrawals_excel.php?' + params.toString();
            window.location.href = exportUrl;
        }

        // دالة تصدير PDF
        function exportToPDF() {
            const params = new URLSearchParams(window.location.search);
            const exportUrl = 'export_employee_withdrawals_pdf.php?' + params.toString();
            window.location.href = exportUrl;
        }

        // تحديث تلقائي للفلتر عند تغيير الموظف
        document.getElementById('employee_id').addEventListener('change', function() {
            // يمكن إضافة تحديث تلقائي هنا إذا رغبت
        });

        // إضافة تأثيرات بصرية
        document.querySelectorAll('.summary-card').forEach(card => {
            card.addEventListener('mouseenter', function() {
                this.style.transform = 'translateY(-5px)';
            });
            
            card.addEventListener('mouseleave', function() {
                this.style.transform = 'translateY(0)';
            });
        });

        // تحديث أشرطة التقدم بتأثير متحرك
        document.addEventListener('DOMContentLoaded', function() {
            const progressBars = document.querySelectorAll('.salary-progress-bar');
            progressBars.forEach(bar => {
                const width = bar.style.width;
                bar.style.width = '0%';
                setTimeout(() => {
                    bar.style.width = width;
                }, 500);
            });
        });
    </script>
</body>
</html>

<?php $conn->close(); ?>
