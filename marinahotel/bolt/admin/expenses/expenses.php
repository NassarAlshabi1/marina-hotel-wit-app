<?php
session_start();
require_once '../../includes/config.php';
require_once '../../includes/db.php';
require_once '../../includes/auth_check.php';

// التحقق من صلاحيات المستخدم
if (!isset($_SESSION['user_id'])) {
    header('Location: ../../login.php');
    exit();
}

// التحقق من صلاحيات الوصول للمصروفات
$user_role = $_SESSION['role'] ?? '';
if (!in_array($user_role, ['admin', 'finance', 'manager'])) {
    die('ليس لديك صلاحية للوصول لهذه الصفحة');
}

// جلب البيانات اللازمة للقوائم المنسدلة
$employees = [];
$suppliers = [];

// جلب الموظفين النشطين
try {
    $emp_query = "SELECT id, name FROM employees WHERE status = 'active'";
    $emp_result = $conn->query($emp_query);
    if ($emp_result) {
        while ($row = $emp_result->fetch_assoc()) {
            $employees[$row['id']] = $row['name'];
        }
    }
} catch (Exception $e) {
    error_log("خطأ في جلب بيانات الموظفين: " . $e->getMessage());
}

// جلب الموردين
try {
    $sup_query = "SELECT id, name FROM suppliers";
    $sup_result = $conn->query($sup_query);
    if ($sup_result) {
        while ($row = $sup_result->fetch_assoc()) {
            $suppliers[$row['id']] = $row['name'];
        }
    }
} catch (Exception $e) {
    error_log("خطأ في جلب بيانات الموردين: " . $e->getMessage());
}

// الحصول على تواريخ الفلترة من الرابط (إذا وجدت) مع التحقق من صحتها
$start_date = isset($_GET['start_date']) && !empty($_GET['start_date']) ? 
    filter_var($_GET['start_date'], FILTER_SANITIZE_STRING) : date('Y-m-01');
$end_date = isset($_GET['end_date']) && !empty($_GET['end_date']) ? 
    filter_var($_GET['end_date'], FILTER_SANITIZE_STRING) : date('Y-m-d');

// التحقق من صحة التواريخ
if (!preg_match('/^\d{4}-\d{2}-\d{2}$/', $start_date) || !preg_match('/^\d{4}-\d{2}-\d{2}$/', $end_date)) {
    $start_date = date('Y-m-01');
    $end_date = date('Y-m-d');
}

// عرض المصروفات من كلا الجدولين حسب نطاق التاريخ - استخدام Prepared Statements
$all_expenses_query = "
    SELECT 'expense' AS type, e.expense_type, e.related_id, e.description, e.amount, e.date, NULL as id
    FROM expenses e
    WHERE e.date BETWEEN ? AND ?
    UNION ALL
    SELECT 'withdrawal' AS type, 'salary' AS expense_type, sw.employee_id AS related_id, sw.notes AS description, sw.amount, sw.date, sw.id
    FROM salary_withdrawals sw
    WHERE sw.date BETWEEN ? AND ?
    ORDER BY date DESC
";

$stmt = $conn->prepare($all_expenses_query);
if (!$stmt) {
    die("خطأ في تحضير الاستعلام: " . $conn->error);
}

$stmt->bind_param('ssss', $start_date, $end_date, $start_date, $end_date);

if (!$stmt->execute()) {
    die("خطأ في تنفيذ الاستعلام: " . $stmt->error);
}

$all_expenses_result = $stmt->get_result();
if ($all_expenses_result === false) {
    die("خطأ في جلب بيانات المصروفات: " . $stmt->error);
}

// تخزين النتائج في مصفوفة لاستخدامها مرتين
$expenses_data = [];
$total_amount = 0;

while ($row = $all_expenses_result->fetch_assoc()) {
    $expenses_data[] = $row;
    $total_amount += floatval($row['amount']);
}

// إغلاق البيان المحضر
$stmt->close();
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>نظام المصروفات - عرض المصروفات</title>
    <link href="<?= defined('BASE_URL') ? BASE_URL : '../../' ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= defined('BASE_URL') ? BASE_URL : '../../' ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        :root {
            --primary-color: #4e73df;
            --secondary-color: #1cc88a;
            --danger-color: #e74a3b;
            --dark-color: #5a5c69;
        }
        
        body {
            background-color: #f8f9fc;
            font-family: 'Tajawal', sans-serif;
        }
        
        .container {
            background-color: white;
            border-radius: 15px;
            box-shadow: 0 0.15rem 1.75rem 0 rgba(58, 59, 69, 0.15);
            padding: 30px;
            margin-top: 30px;
            margin-bottom: 30px;
        }
        
        .page-header {
            border-bottom: 1px solid #e3e6f0;
            padding-bottom: 15px;
            margin-bottom: 25px;
        }
        
        .page-title {
            color: var(--dark-color);
            font-weight: 700;
            font-size: 1.75rem;
            text-align: center;
        }
        
        .btn-custom {
            border-radius: 8px;
            font-weight: 600;
            padding: 10px 20px;
            transition: all 0.3s;
            text-align: center;
        }
        
        .btn-add {
            background-color: var(--secondary-color);
            border-color: var(--secondary-color);
            color: white;
        }
        
        .btn-add:hover {
            background-color: #17a673;
            border-color: #17a673;
            color: white;
        }
        
        .table-custom {
            border-collapse: separate;
            border-spacing: 0;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 0.15rem 1.75rem 0 rgba(58, 59, 69, 0.1);
        }
        
        .table-custom thead th {
            background-color: var(--primary-color);
            color: white;
            font-weight: 700;
            border: none;
            padding: 15px 10px;
            text-align: center;
        }
        
        .table-custom tbody tr {
            transition: all 0.2s;
            text-align: center;
        }
        
        .table-custom tbody tr:hover {
            background-color: rgba(78, 115, 223, 0.05);
            transform: translateY(-1px);
        }
        
        .table-custom td {
            padding: 12px 10px;
            vertical-align: middle;
            border-top: 1px solid #e3e6f0;
            text-align: center;
        }
        
        .amount-cell {
            font-weight: 700;
            color: var(--danger-color);
            text-align: center;
        }
        
        .total-row {
            background-color: #f8f9fc;
            font-weight: 700;
        }
        
        .total-row td {
            border-top: 2px solid #e3e6f0;
            text-align: center;
        }
        
        .badge-custom {
            padding: 6px 10px;
            border-radius: 8px;
            font-weight: 600;
        }
        
        .badge-expense {
            background-color: #f6c23e;
            color: #000;
        }
        
        .badge-salary {
            background-color: #36b9cc;
            color: #fff;
        }
        
        .btn-group {
            display: flex;
            justify-content: center;
            gap: 10px;
            margin-bottom: 20px;
        }
        
        .filter-container {
            display: flex;
            justify-content: center;
            gap: 10px;
            margin-bottom: 20px;
            align-items: center;
            flex-wrap: wrap;
        }
        
        .filter-container label {
            margin-bottom: 0;
            font-weight: 600;
        }
        
        .date-input {
            border: 1px solid #ced4da;
            border-radius: 4px;
            padding: 6px 12px;
            min-width: 150px;
        }
        
        .description-cell {
            white-space: pre-line;
            text-align: right;
            padding-right: 15px;
        }
        
        @media (max-width: 768px) {
            .container {
                padding: 15px;
            }
            
            .btn-group {
                flex-direction: column;
                align-items: center;
            }
            
            .btn-group .btn {
                margin-bottom: 10px;
                width: 100%;
            }
            
            .filter-container {
                flex-direction: column;
                align-items: stretch;
            }
            
            .date-input {
                width: 100%;
            }
        }
        
        @media print {
            .btn-group,
            .filter-container {
                display: none !important;
            }
            
            body {
                background-color: white !important;
            }
            
            .container {
                box-shadow: none !important;
                margin: 0 !important;
                padding: 0 !important;
            }
            
            .table-custom {
                box-shadow: none !important;
            }
            
            .page-title {
                font-size: 1.5rem;
                text-align: center;
                margin-bottom: 20px;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-money-bill-wave me-2"></i>عرض المصروفات
            </h1>
        </div>
        
        <?php if (isset($_SESSION['error'])): ?>
            <div class="alert alert-danger">
                <?= $_SESSION['error']; unset($_SESSION['error']); ?>
            </div>
        <?php endif; ?>
        
        <?php if (isset($_SESSION['success'])): ?>
            <div class="alert alert-success">
                <?= $_SESSION['success']; unset($_SESSION['success']); ?>
            </div>
        <?php endif; ?>
        
        <div class="btn-group">
            <a href="add_expense.php" class="btn btn-add btn-custom">
                <i class="fas fa-plus me-2"></i>إضافة مصروف جديد
            </a>
            <button onclick="window.print()" class="btn btn-info btn-custom">
                <i class="fas fa-print me-2"></i>طباعة
            </button>
            <a href="../reports/report.php" class="btn btn-primary btn-custom">
                <i class="fas fa-chart-bar me-2"></i>التقارير
            </a>
            <a href="../dashboard.php" class="btn btn-secondary btn-custom">
                <i class="fas fa-home me-2"></i>الرئيسية
            </a>
        </div>
        
        <div class="filter-container">
            <label for="start-date">من تاريخ:</label>
            <input type="date" id="start-date" class="date-input" value="<?php echo $start_date; ?>">
            
            <label for="end-date">إلى تاريخ:</label>
            <input type="date" id="end-date" class="date-input" value="<?php echo $end_date; ?>">
            
            <button id="filter-button" class="btn btn-primary">تصفية</button>
        </div>
        
        <div class="table-responsive">
            <table class="table table-custom">
                <thead>
                    <tr>
                        <th width="15%">نوع المصروف</th>
                        <th width="20%">الموظف / المورد</th>
                        <th width="30%">الوصف</th>
                        <th width="15%">المبلغ</th>
                        <th width="20%">التاريخ</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if (empty($expenses_data)): ?>
                        <tr>
                            <td colspan="5" class="text-center text-muted">
                                <i class="fas fa-info-circle me-2"></i>لا توجد مصروفات في هذا النطاق الزمني
                            </td>
                        </tr>
                    <?php else: ?>
                        <?php foreach ($expenses_data as $row): ?>
                            <tr>
                                <td>
                                    <span class="badge badge-custom <?= $row['type'] == 'expense' ? 'badge-expense' : 'badge-salary' ?>">
                                        <?= htmlspecialchars($row['expense_type']) ?>
                                    </span>
                                </td>
                                <td>
                                    <?php
                                        if ($row['type'] == 'expense') {
                                            $related_name = '';
                                            if ($row['related_id'] && isset($suppliers[$row['related_id']])) {
                                                $related_name = $suppliers[$row['related_id']];
                                            }
                                            echo htmlspecialchars($related_name);
                                        } else {
                                            $employee_name = 'غير معروف';
                                            if ($row['related_id'] && isset($employees[$row['related_id']])) {
                                                $employee_name = $employees[$row['related_id']];
                                            }
                                            echo htmlspecialchars($employee_name);
                                        }
                                    ?>
                                </td>
                                <td class="description-cell">
                                    <?= nl2br(htmlspecialchars($row['description'])) ?>
                                </td>
                                <td class="amount-cell"><?= number_format($row['amount'], 0, '', ',') ?></td>
                                <td>
                                    <?= htmlspecialchars($row['date']) ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                    <?php endif; ?>
                    <tr class="total-row">
                        <td colspan="3">
                            <strong>المجموع الكلي:</strong>
                        </td>
                        <td class="amount-cell"><?= number_format($total_amount, 0, '', ',') ?></td>
                        <td></td>
                    </tr>
                </tbody>
            </table>
        </div>
    </div>
    
    <script src="<?= defined('BASE_URL') ? BASE_URL : '../../' ?>assets/js/jquery.min.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            const filterButton = document.getElementById('filter-button');
            const startDateInput = document.getElementById('start-date');
            const endDateInput = document.getElementById('end-date');
            
            // تفعيل التصفية عند الضغط على Enter
            [startDateInput, endDateInput].forEach(input => {
                input.addEventListener('keypress', function(e) {
                    if (e.key === 'Enter') {
                        filterButton.click();
                    }
                });
            });
            
            // عند النقر على زر التصفية
            filterButton.addEventListener('click', function() {
                const startDate = startDateInput.value;
                const endDate = endDateInput.value;
                
                if (!startDate || !endDate) {
                    alert('الرجاء اختيار تاريخ البداية والنهاية');
                    return;
                }
                
                if (startDate > endDate) {
                    alert('تاريخ البداية يجب أن يكون قبل تاريخ النهاية');
                    startDateInput.focus();
                    return;
                }
                
                // إضافة مؤشر التحميل
                filterButton.innerHTML = '<i class="fas fa-spinner fa-spin me-2"></i>جاري التصفية...';
                filterButton.disabled = true;
                
                // إعادة تحميل الصفحة مع معلمات الفلترة
                window.location.href = window.location.pathname + 
                    '?start_date=' + encodeURIComponent(startDate) + 
                    '&end_date=' + encodeURIComponent(endDate);
            });
            
            // إضافة وظيفة البحث السريع في الجدول
            function addTableSearch() {
                const searchInput = document.createElement('input');
                searchInput.type = 'text';
                searchInput.placeholder = 'البحث في المصروفات...';
                searchInput.className = 'form-control mb-3';
                searchInput.style.maxWidth = '300px';
                searchInput.style.margin = '0 auto';
                
                const table = document.querySelector('.table-responsive');
                table.parentNode.insertBefore(searchInput, table);
                
                searchInput.addEventListener('input', function() {
                    const searchTerm = this.value.toLowerCase();
                    const rows = document.querySelectorAll('tbody tr:not(.total-row)');
                    
                    rows.forEach(row => {
                        const text = row.textContent.toLowerCase();
                        row.style.display = text.includes(searchTerm) ? '' : 'none';
                    });
                });
            }
            
            // إضافة البحث إذا كان هناك بيانات
            if (document.querySelectorAll('tbody tr:not(.total-row)').length > 0) {
                addTableSearch();
            }
        });
    </script>
</body>
</html>
