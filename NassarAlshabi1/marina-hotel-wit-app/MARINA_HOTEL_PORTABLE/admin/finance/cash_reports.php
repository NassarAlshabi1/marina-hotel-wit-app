<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// تحديد نوع التقرير والفترة الزمنية
$report_type = isset($_GET['report_type']) ? $_GET['report_type'] : 'daily';
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-d');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-d');

// تعديل الفترة الزمنية حسب نوع التقرير
if ($report_type === 'monthly') {
    $start_date = date('Y-m-01', strtotime($start_date)); // أول يوم في الشهر
    $end_date = date('Y-m-t', strtotime($start_date)); // آخر يوم في الشهر
} elseif ($report_type === 'yearly') {
    $year = date('Y', strtotime($start_date));
    $start_date = "$year-01-01"; // أول يوم في السنة
    $end_date = "$year-12-31"; // آخر يوم في السنة
}

// استعلام لجلب بيانات الصندوق خلال الفترة المحددة
$register_query = "
    SELECT 
        cr.id,
        cr.date,
        cr.opening_balance,
        cr.closing_balance,
        cr.total_income,
        cr.total_expense,
        cr.status,
        cr.notes
    FROM cash_register cr
    WHERE cr.date BETWEEN ? AND ?
    ORDER BY cr.date ASC
";

$register_stmt = $conn->prepare($register_query);
$register_stmt->bind_param("ss", $start_date, $end_date);
$register_stmt->execute();
$register_result = $register_stmt->get_result();

// استعلام لجلب تفاصيل الحركات النقدية خلال الفترة المحددة
$transactions_query = "
    SELECT 
        ct.id,
        ct.register_id,
        ct.transaction_type,
        ct.amount,
        ct.reference_type,
        ct.reference_id,
        ct.description,
        ct.transaction_time,
        cr.date
    FROM cash_transactions ct
    JOIN cash_register cr ON ct.register_id = cr.id
    WHERE cr.date BETWEEN ? AND ?
    ORDER BY ct.transaction_time ASC
";

$transactions_stmt = $conn->prepare($transactions_query);
$transactions_stmt->bind_param("ss", $start_date, $end_date);
$transactions_stmt->execute();
$transactions_result = $transactions_stmt->get_result();

// تجميع البيانات للتحليل
$registers = [];
$transactions = [];
$total_opening_balance = 0;
$total_closing_balance = 0;
$total_income = 0;
$total_expense = 0;
$income_by_type = [];
$expense_by_type = [];
$daily_totals = [];

while ($row = $register_result->fetch_assoc()) {
    $registers[] = $row;
    
    if ($row === $register_result->fetch_assoc(0)) {
        $total_opening_balance = $row['opening_balance'];
    }
    
    if ($row['status'] === 'closed') {
        $total_closing_balance = $row['closing_balance'];
    } else {
        $total_closing_balance = $row['opening_balance'] + $row['total_income'] - $row['total_expense'];
    }
    
    $total_income += $row['total_income'];
    $total_expense += $row['total_expense'];
    
    $date = $row['date'];
    $daily_totals[$date] = [
        'date' => $date,
        'income' => $row['total_income'],
        'expense' => $row['total_expense'],
        'net' => $row['total_income'] - $row['total_expense']
    ];
}

while ($row = $transactions_result->fetch_assoc()) {
    $transactions[] = $row;
    
    $type = $row['reference_type'];
    
    if ($row['transaction_type'] === 'income') {
        if (!isset($income_by_type[$type])) {
            $income_by_type[$type] = 0;
        }
        $income_by_type[$type] += $row['amount'];
    } else {
        if (!isset($expense_by_type[$type])) {
            $expense_by_type[$type] = 0;
        }
        $expense_by_type[$type] += $row['amount'];
    }
}

// تحديد عنوان التقرير
$report_titles = [
    'daily' => 'التقرير اليومي',
    'monthly' => 'التقرير الشهري',
    'yearly' => 'التقرير السنوي'
];

$report_title = $report_titles[$report_type] ?? 'تقرير الصندوق';

// تنسيق التواريخ للعرض
$display_start_date = date('Y-m-d', strtotime($start_date));
$display_end_date = date('Y-m-d', strtotime($end_date));

if ($report_type === 'daily') {
    $period_text = "ليوم " . $display_start_date;
} elseif ($report_type === 'monthly') {
    $period_text = "لشهر " . date('F Y', strtotime($start_date));
} elseif ($report_type === 'yearly') {
    $period_text = "لسنة " . date('Y', strtotime($start_date));
} else {
    $period_text = "للفترة من " . $display_start_date . " إلى " . $display_end_date;
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title><?= $report_title ?> - فندق مارينا بلازا</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
        }
        .card {
            border-radius: 15px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
        }
        .card-header {
            border-radius: 15px 15px 0 0 !important;
            font-weight: bold;
        }
        .summary-card {
            text-align: center;
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 15px;
        }
        .summary-title {
            font-size: 1rem;
            font-weight: bold;
            margin-bottom: 5px;
        }
        .summary-amount {
            font-size: 1.5rem;
            font-weight: bold;
        }
        .income-card {
            background-color: #d1e7dd;
            color: #0f5132;
        }
        .expense-card {
            background-color: #f8d7da;
            color: #842029;
        }
        .balance-card {
            background-color: #cfe2ff;
            color: #084298;
        }
        .chart-container {
            position: relative;
            height: 300px;
            margin-bottom: 20px;
        }
        .transaction-table th {
            background-color: #f1f1f1;
            font-weight: bold;
        }
        .income-row {
            background-color: rgba(209, 231, 221, 0.3);
        }
        .expense-row {
            background-color: rgba(248, 215, 218, 0.3);
        }
        .type-badge {
            display: inline-block;
            padding: 5px 10px;
            border-radius: 20px;
            font-size: 0.8rem;
            font-weight: bold;
        }
        .income-badge {
            background-color: #d1e7dd;
            color: #0f5132;
        }
        .expense-badge {
            background-color: #f8d7da;
            color: #842029;
        }
        
        /* تحسينات للطباعة */
        @media print {
            body {
                background-color: white;
                font-size: 12pt;
            }
            .container {
                width: 100%;
                max-width: 100%;
            }
            .card {
                border: 1px solid #ddd;
                box-shadow: none;
                break-inside: avoid;
            }
            .no-print {
                display: none !important;
            }
            .chart-container {
                height: 200px;
                page-break-inside: avoid;
            }
            .page-break {
                page-break-before: always;
            }
            .summary-card {
                border: 1px solid #ddd;
            }
            .income-card {
                background-color: rgba(209, 231, 221, 0.3) !important;
                color: #0f5132 !important;
            }
            .expense-card {
                background-color: rgba(248, 215, 218, 0.3) !important;
                color: #842029 !important;
            }
            .balance-card {
                background-color: rgba(207, 226, 255, 0.3) !important;
                color: #084298 !important;
            }
            .transaction-table th {
                background-color: #f1f1f1 !important;
                color: black !important;
            }
            .income-row {
                background-color: rgba(209, 231, 221, 0.2) !important;
            }
            .expense-row {
                background-color: rgba(248, 215, 218, 0.2) !important;
            }
            .type-badge {
                border: 1px solid #ddd;
            }
            .income-badge {
                background-color: rgba(209, 231, 221, 0.3) !important;
                color: #0f5132 !important;
            }
            .expense-badge {
                background-color: rgba(248, 215, 218, 0.3) !important;
                color: #842029 !important;
            }
            
            /* ترقيم الصفحات */
            @page {
                margin: 1cm;
            }
            
            /* إضافة رأس وتذييل للطباعة */
            .print-header {
                display: block !important;
                text-align: center;
                margin-bottom: 20px;
                border-bottom: 1px solid #ddd;
                padding-bottom: 10px;
            }
            .print-footer {
                display: block !important;
                text-align: center;
                margin-top: 20px;
                border-top: 1px solid #ddd;
                padding-top: 10px;
                font-size: 10pt;
            }
        }
        
        /* إخفاء رأس وتذييل الطباعة في العرض العادي */
        .print-header, .print-footer {
            display: none;
        }
    </style>
</head>
<body>
    <!-- رأس الطباعة -->
    <div class="print-header">
        <h2>فندق مارينا بلازا</h2>
        <p><?= $report_title ?> <?= $period_text ?></p>
        <p>تاريخ الطباعة: <?= date('Y-m-d H:i') ?></p>
    </div>

    <div class="container py-4">
        <div class="d-flex justify-content-between mb-3 no-print">
            <a href="cash_register.php" class="btn btn-outline-primary fw-bold">
                ← العودة إلى سجل الصندوق
            </a>
            <button onclick="window.print()" class="btn btn-success fw-bold">
                <i class="fas fa-print me-1"></i> طباعة التقرير
            </button>
        </div>

        <h2 class="text-center mb-4 text-primary fw-bold">
            <?= $report_title ?> للصندوق - فندق مارينا بلازا
        </h2>
        <h4 class="text-center mb-4"><?= $period_text ?></h4>

        <!-- نموذج التصفية -->
        <div class="card mb-4 no-print">
            <div class="card-header bg-info text-white">
                <h5 class="mb-0">تصفية التقرير</h5>
            </div>
            <div class="card-body">
                <form method="GET" class="row g-3">
                    <div class="col-md-4">
                        <label for="report_type" class="form-label">نوع التقرير</label>
                        <select class="form-select" id="report_type" name="report_type">
                            <option value="daily" <?= $report_type === 'daily' ? 'selected' : '' ?>>يومي</option>
                            <option value="monthly" <?= $report_type === 'monthly' ? 'selected' : '' ?>>شهري</option>
                            <option value="yearly" <?= $report_type === 'yearly' ? 'selected' : '' ?>>سنوي</option>
                        </select>
                    </div>
                    <div class="col-md-4">
                        <label for="start_date" class="form-label">التاريخ</label>
                        <input type="date" class="form-control" id="start_date" name="start_date" value="<?= $start_date ?>">
                    </div>
                    <div class="col-md-4 d-flex align-items-end">
                        <button type="submit" class="btn btn-primary w-100">تطبيق</button>
                    </div>
                </form>
            </div>
        </div>

        <!-- ملخص التقرير -->
        <div class="card">
            <div class="card-header bg-primary text-white">
                <h5 class="mb-0">ملخص التقرير</h5>
            </div>
            <div class="card-body">
                <div class="row">
                    <div class="col-md-4">
                        <div class="summary-card income-card">
                            <div class="summary-title">إجمالي الإيرادات</div>
                            <div class="summary-amount"><?= number_format($total_income, 2) ?> </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="summary-card expense-card">
                            <div class="summary-title">إجمالي المصروفات</div>
                            <div class="summary-amount"><?= number_format($total_expense, 2) ?> </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="summary-card balance-card">
                            <div class="summary-title">صافي الحركة</div>
                            <div class="summary-amount"><?= number_format($total_income - $total_expense, 2) ?> </div>
                        </div>
                    </div>
                </div>
                
                <div class="row mt-4">
                    <div class="col-md-6">
                        <div class="card">
                            <div class="card-header bg-success text-white">
                                <h5 class="mb-0">الإيرادات حسب النوع</h5>
                            </div>
                            <div class="card-body">
                                <div class="chart-container">
                                    <canvas id="incomeChart"></canvas>
                                </div>
                                <div class="table-responsive">
                                    <table class="table table-bordered table-striped">
                                        <thead>
                                            <tr>
                                                <th>النوع</th>
                                                <th>المبلغ</th>
                                                <th>النسبة</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            <?php foreach ($income_by_type as $type => $amount): ?>
                                                <tr>
                                                    <td>
                                                        <?php
                                                        $reference_types = [
                                                            'booking' => 'حجز',
                                                            'restaurant' => 'مطعم',
                                                            'service' => 'خدمة إضافية',
                                                            'other' => 'أخرى'
                                                        ];
                                                        echo $reference_types[$type] ?? $type;
                                                        ?>
                                                    </td>
                                                    <td><?= number_format($amount, 2) ?> </td>
                                                    <td><?= number_format(($amount / $total_income) * 100, 1) ?>%</td>
                                                </tr>
                                            <?php endforeach; ?>
                                        </tbody>
                                    </table>
                                </div>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-6">
                        <div class="card">
                            <div class="card-header bg-danger text-white">
                                <h5 class="mb-0">المصروفات حسب النوع</h5>
                            </div>
                            <div class="card-body">
                                <div class="chart-container">
                                    <canvas id="expenseChart"></canvas>
                                </div>
                                <div class="table-responsive">
                                    <table class="table table-bordered table-striped">
                                        <thead>
                                            <tr>
                                                <th>النوع</th>
                                                <th>المبلغ</th>
                                                <th>النسبة</th>
                                            </tr>
                                        </thead>
                                        <tbody>
                                            <?php foreach ($expense_by_type as $type => $amount): ?>
                                                <tr>
                                                    <td>
                                                        <?php
                                                        $reference_types = [
                                                            'salary' => 'رواتب',
                                                            'utility' => 'فواتير',
                                                            'purchase' => 'مشتريات',
                                                            'other' => 'أخرى'
                                                        ];
                                                        echo $reference_types[$type] ?? $type;
                                                        ?>
                                                    </td>
                                                    <td><?= number_format($amount, 2) ?> </td>
                                                    <td><?= number_format(($amount / $total_expense) * 100, 1) ?>%</td>
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

        <!-- الرسم البياني للإيرادات والمصروفات -->
        <?php if (count($daily_totals) > 1): ?>
            <div class="card mt-4">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0">تحليل الإيرادات والمصروفات</h5>
                </div>
                <div class="card-body">
                    <div class="chart-container">
                        <canvas id="dailyChart"></canvas>
                    </div>
                </div>
            </div>
        <?php endif; ?>

        <!-- تفاصيل الحركات النقدية -->
        <div class="card mt-4 page-break">
            <div class="card-header bg-secondary text-white">
                <h5 class="mb-0">تفاصيل الحركات النقدية</h5>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-bordered transaction-table">
                        <thead>
                            <tr>
                                <th>#</th>
                                <th>التاريخ</th>
                                <th>الوقت</th>
                                <th>النوع</th>
                                <th>المرجع</th>
                                <th>الوصف</th>
                                <th>المبلغ</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (count($transactions) > 0): ?>
                                <?php $counter = 1; ?>
                                <?php foreach ($transactions as $transaction): ?>
                                    <tr class="<?= $transaction['transaction_type'] === 'income' ? 'income-row' : 'expense-row' ?>">
                                        <td><?= $counter++ ?></td>
                                        <td><?= date('Y-m-d', strtotime($transaction['date'])) ?></td>
                                        <td><?= date('H:i:s', strtotime($transaction['transaction_time'])) ?></td>
                                        <td>
                                            <span class="type-badge <?= $transaction['transaction_type'] === 'income' ? 'income-badge' : 'expense-badge' ?>">
                                                <?= $transaction['transaction_type'] === 'income' ? 'إيراد' : 'مصروف' ?>
                                            </span>
                                        </td>
                                        <td>
                                            <?php
                                            $reference_types = [
                                                'booking' => 'حجز',
                                                'restaurant' => 'مطعم',
                                                'service' => 'خدمة إضافية',
                                                'salary' => 'راتب',
                                                'utility' => 'فاتورة',
                                                'purchase' => 'مشتريات',
                                                'other' => 'أخرى'
                                            ];
                                            echo $reference_types[$transaction['reference_type']] ?? $transaction['reference_type'];
                                            if ($transaction['reference_id']) {
                                                echo ' #' . $transaction['reference_id'];
                                            }
                                            ?>
                                        </td>
                                        <td><?= htmlspecialchars($transaction['description']) ?></td>
                                        <td class="text-<?= $transaction['transaction_type'] === 'income' ? 'success' : 'danger' ?> fw-bold">
                                            <?= $transaction['transaction_type'] === 'income' ? '+' : '-' ?> <?= number_format($transaction['amount'], 2) ?> 
                                        </td>
                                    </tr>
                                <?php endforeach; ?>
                            <?php else: ?>
                                <tr>
                                    <td colspan="7" class="text-center">لا توجد حركات نقدية خلال هذه الفترة</td>
                                </tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <!-- تذييل الطباعة -->
    <div class="print-footer">
        <p>فندق مارينا بلازا - نظام إدارة الفندق</p>
        <p>صفحة <span class="page-number"></span></p>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // بيانات الرسوم البيانية
        const incomeData = <?= json_encode(array_values($income_by_type)) ?>;
        const incomeLabels = <?= json_encode(array_map(function($type) {
            $reference_types = [
                'booking' => 'حجز',
                'restaurant' => 'مطعم',
                'service' => 'خدمة إضافية',
                'other' => 'أخرى'
            ];
            return $reference_types[$type] ?? $type;
        }, array_keys($income_by_type))) ?>;
        
        const expenseData = <?= json_encode(array_values($expense_by_type)) ?>;
        const expenseLabels = <?= json_encode(array_map(function($type) {
            $reference_types = [
                'salary' => 'رواتب',
                'utility' => 'فواتير',
                'purchase' => 'مشتريات',
                'other' => 'أخرى'
            ];
            return $reference_types[$type] ?? $type;
        }, array_keys($expense_by_type))) ?>;
        
        <?php if (count($daily_totals) > 1): ?>
        const dailyDates = <?= json_encode(array_map(function($item) {
            return $item['date'];
        }, $daily_totals)) ?>;
        
        const dailyIncome = <?= json_encode(array_map(function($item) {
            return $item['income'];
        }, $daily_totals)) ?>;
        
        const dailyExpense = <?= json_encode(array_map(function($item) {
            return $item['expense'];
        }, $daily_totals)) ?>;
        
        const dailyNet = <?= json_encode(array_map(function($item) {
            return $item['net'];
        }, $daily_totals)) ?>;
        <?php endif; ?>
        
        // إنشاء الرسوم البيانية
        document.addEventListener('DOMContentLoaded', function() {
            // رسم بياني للإيرادات
            const incomeCtx = document.getElementById('incomeChart').getContext('2d');
            new Chart(incomeCtx, {
                type: 'pie',
                data: {
                    labels: incomeLabels,
                    datasets: [{
                        data: incomeData,
                        backgroundColor: [
                            'rgba(40, 167, 69, 0.7)',
                            'rgba(0, 123, 255, 0.7)',
                            'rgba(255, 193, 7, 0.7)',
                            'rgba(23, 162, 184, 0.7)',
                            'rgba(111, 66, 193, 0.7)'
                        ],
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom'
                        }
                    }
                }
            });
            
            // رسم بياني للمصروفات
            const expenseCtx = document.getElementById('expenseChart').getContext('2d');
            new Chart(expenseCtx, {
                type: 'pie',
                data: {
                    labels: expenseLabels,
                    datasets: [{
                        data: expenseData,
                        backgroundColor: [
                            'rgba(220, 53, 69, 0.7)',
                            'rgba(255, 193, 7, 0.7)',
                            'rgba(108, 117, 125, 0.7)',
                            'rgba(23, 162, 184, 0.7)',
                            'rgba(111, 66, 193, 0.7)'
                        ],
                        borderWidth: 1
                    }]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    plugins: {
                        legend: {
                            position: 'bottom'
                        }
                    }
                }
            });
            
            <?php if (count($daily_totals) > 1): ?>
            // رسم بياني للإيرادات والمصروفات اليومية
            const dailyCtx = document.getElementById('dailyChart').getContext('2d');
            new Chart(dailyCtx, {
                type: 'bar',
                data: {
                    labels: dailyDates,
                    datasets: [
                        {
                            label: 'الإيرادات',
                            data: dailyIncome,
                            backgroundColor: 'rgba(40, 167, 69, 0.5)',
                            borderColor: 'rgba(40, 167, 69, 1)',
                            borderWidth: 1
                        },
                        {
                            label: 'المصروفات',
                            data: dailyExpense,
                            backgroundColor: 'rgba(220, 53, 69, 0.5)',
                            borderColor: 'rgba(220, 53, 69, 1)',
                            borderWidth: 1
                        },
                        {
                            label: 'صافي',
                            data: dailyNet,
                            type: 'line',
                            fill: false,
                            backgroundColor: 'rgba(0, 123, 255, 0.5)',
                            borderColor: 'rgba(0, 123, 255, 1)',
                            borderWidth: 2,
                            pointRadius: 4
                        }
                    ]
                },
                options: {
                    responsive: true,
                    maintainAspectRatio: false,
                    scales: {
                        y: {
                            beginAtZero: true
                        }
                    },
                    plugins: {
                        legend: {
                            position: 'bottom'
                        }
                    }
                }
            });
            <?php endif; ?>
        });
        
        // تغيير نوع التقرير بناءً على الاختيار
        document.getElementById('report_type').addEventListener('change', function() {
            const reportType = this.value;
            const startDateInput = document.getElementById('start_date');
            
            if (reportType === 'monthly') {
                // تغيير التاريخ إلى أول يوم في الشهر الحالي
                const currentDate = new Date(startDateInput.value);
                currentDate.setDate(1);
                startDateInput.value = currentDate.toISOString().split('T')[0];
            } else if (reportType === 'yearly') {
                // تغيير التاريخ إلى أول يوم في السنة الحالية
                const currentDate = new Date(startDateInput.value);
                currentDate.setMonth(0);
                currentDate.setDate(1);
                startDateInput.value = currentDate.toISOString().split('T')[0];
            }
        });
        
        // ترقيم صفحات الطباعة
        window.onbeforeprint = function() {
            const pageNumbers = document.querySelectorAll('.page-number');
            for (let i = 0; i < pageNumbers.length; i++) {
                pageNumbers[i].textContent = (i + 1);
            }
        };
    </script>
</body>
</html>

<?php
$register_stmt->close();
$transactions_stmt->close();
$conn->close();
?>
