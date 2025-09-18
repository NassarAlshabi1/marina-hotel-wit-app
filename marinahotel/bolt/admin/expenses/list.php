<?php
session_start();
require_once '../../includes/config.php';
require_once '../../includes/db.php';
//require_once '../../includes/auth_check.php';

// التحقق من صلاحيات المستخدم
if (!isset($_SESSION['user_id'])) {
    header('Location: ../../login.php');
    exit();
}

// المستخدمون المسجلون فقط يمكنهم الوصول

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

// معالجة معايير الفلترة
$where_conditions = [];
$params = [];
$param_types = '';

// فلترة بالتواريخ
if (isset($_GET['start_date']) && !empty($_GET['start_date'])) {
    $start_date = filter_var($_GET['start_date'], FILTER_SANITIZE_STRING);
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $start_date)) {
        $where_conditions[] = "DATE(date) >= ?";
        $params[] = $start_date;
        $param_types .= 's';
    }
}

if (isset($_GET['end_date']) && !empty($_GET['end_date'])) {
    $end_date = filter_var($_GET['end_date'], FILTER_SANITIZE_STRING);
    if (preg_match('/^\d{4}-\d{2}-\d{2}$/', $end_date)) {
        $where_conditions[] = "DATE(date) <= ?";
        $params[] = $end_date;
        $param_types .= 's';
    }
}

// فلترة بنوع المصروف
if (isset($_GET['type']) && !empty($_GET['type'])) {
    $type_filter = filter_var($_GET['type'], FILTER_SANITIZE_STRING);
    if (in_array($type_filter, ['expense', 'withdrawal'])) {
        // سيتم تطبيقها في الاستعلام
    }
}

// بناء استعلام المصروفات
$where_clause = '';
if (!empty($where_conditions)) {
    $where_clause = 'WHERE ' . implode(' AND ', $where_conditions);
}

// استعلام للحصول على جميع المصروفات
$expenses_query = "
    SELECT 'expense' AS type, e.id, e.expense_type, e.related_id, e.description, e.amount, e.date, e.created_at
    FROM expenses e
    $where_clause
";

$withdrawals_query = "
    SELECT 'withdrawal' AS type, sw.id, 'salary' AS expense_type, sw.employee_id AS related_id, sw.notes AS description, sw.amount, sw.date, sw.created_at
    FROM salary_withdrawals sw
    $where_clause
";

// دمج النتائج
$union_query = "$expenses_query UNION ALL $withdrawals_query ORDER BY date DESC, created_at DESC";

$stmt = $conn->prepare($union_query);
if (!$stmt) {
    die("خطأ في تحضير الاستعلام: " . $conn->error);
}

if (!empty($params)) {
    // دمج المعاملات لكلا الاستعلامين
    $all_params = array_merge($params, $params);
    $all_param_types = $param_types . $param_types;
    $stmt->bind_param($all_param_types, ...$all_params);
}

if (!$stmt->execute()) {
    die("خطأ في تنفيذ الاستعلام: " . $stmt->error);
}

$result = $stmt->get_result();
$expenses_data = [];
$total_amount = 0;

while ($row = $result->fetch_assoc()) {
    $expenses_data[] = $row;
    $total_amount += floatval($row['amount']);
}

$stmt->close();

// إحصائيات سريعة
$total_expenses = 0;
$total_withdrawals = 0;
$expenses_count = 0;
$withdrawals_count = 0;

foreach ($expenses_data as $expense) {
    if ($expense['type'] === 'expense') {
        $total_expenses += $expense['amount'];
        $expenses_count++;
    } else {
        $total_withdrawals += $expense['amount'];
        $withdrawals_count++;
    }
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>قائمة المصروفات</title>
    <link href="<?= defined('BASE_URL') ? BASE_URL : '../../' ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= defined('BASE_URL') ? BASE_URL : '../../' ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        :root {
            --primary-color: #4e73df;
            --secondary-color: #1cc88a;
            --danger-color: #e74a3b;
            --warning-color: #f6c23e;
            --info-color: #36b9cc;
            --dark-color: #5a5c69;
        }
        
        body {
            background-color: #f8f9fc;
            font-family: 'Tajawal', sans-serif;
        }
        
        .main-container {
            background-color: white;
            border-radius: 15px;
            box-shadow: 0 0.15rem 1.75rem 0 rgba(58, 59, 69, 0.15);
            padding: 30px;
            margin: 30px auto;
        }
        
        .page-header {
            border-bottom: 1px solid #e3e6f0;
            padding-bottom: 20px;
            margin-bottom: 30px;
            text-align: center;
        }
        
        .page-title {
            color: var(--dark-color);
            font-weight: 700;
            font-size: 1.8rem;
            margin: 0;
        }
        
        .stats-cards {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 20px;
            margin-bottom: 30px;
        }
        
        .stat-card {
            background: linear-gradient(135deg, var(--primary-color) 0%, #224abe 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            text-align: center;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
        }
        
        .stat-card.expenses {
            background: linear-gradient(135deg, var(--warning-color) 0%, #dda20a 100%);
        }
        
        .stat-card.withdrawals {
            background: linear-gradient(135deg, var(--info-color) 0%, #2c9faf 100%);
        }
        
        .stat-card.total {
            background: linear-gradient(135deg, var(--danger-color) 0%, #c0392b 100%);
        }
        
        .stat-value {
            font-size: 1.8rem;
            font-weight: bold;
            margin-bottom: 5px;
        }
        
        .stat-label {
            font-size: 0.9rem;
            opacity: 0.9;
        }
        
        .filters-section {
            background-color: #f8f9fc;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 25px;
        }
        
        .filter-row {
            display: flex;
            gap: 15px;
            align-items: center;
            flex-wrap: wrap;
            justify-content: center;
        }
        
        .filter-group {
            display: flex;
            flex-direction: column;
            gap: 5px;
        }
        
        .filter-group label {
            font-weight: 600;
            color: var(--dark-color);
            font-size: 0.9rem;
        }
        
        .filter-input {
            border: 1px solid #d1d3e2;
            border-radius: 6px;
            padding: 8px 12px;
            min-width: 150px;
        }
        
        .btn-filter {
            background-color: var(--primary-color);
            color: white;
            border: none;
            padding: 10px 20px;
            border-radius: 6px;
            font-weight: 600;
            cursor: pointer;
            transition: all 0.3s;
        }
        
        .btn-filter:hover {
            background-color: #2653d4;
            transform: translateY(-1px);
        }
        
        .expenses-table {
            border-collapse: separate;
            border-spacing: 0;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            width: 100%;
        }
        
        .expenses-table thead th {
            background-color: var(--primary-color);
            color: white;
            font-weight: 700;
            padding: 15px 10px;
            text-align: center;
            border: none;
        }
        
        .expenses-table tbody tr {
            background-color: white;
            transition: all 0.2s;
        }
        
        .expenses-table tbody tr:hover {
            background-color: rgba(78, 115, 223, 0.05);
            transform: translateY(-1px);
        }
        
        .expenses-table tbody tr:nth-child(even) {
            background-color: #f8f9fc;
        }
        
        .expenses-table td {
            padding: 12px 10px;
            text-align: center;
            border-top: 1px solid #e3e6f0;
            vertical-align: middle;
        }
        
        .badge-type {
            padding: 6px 12px;
            border-radius: 20px;
            font-weight: 600;
            font-size: 0.8rem;
        }
        
        .badge-expense {
            background-color: var(--warning-color);
            color: #000;
        }
        
        .badge-withdrawal {
            background-color: var(--info-color);
            color: white;
        }
        
        .amount-cell {
            font-weight: 700;
            color: var(--danger-color);
            font-size: 1.1rem;
        }
        
        .description-cell {
            text-align: right;
            max-width: 200px;
            word-wrap: break-word;
        }
        
        .total-row {
            background-color: #e9ecef !important;
            font-weight: bold;
            border-top: 3px solid var(--primary-color) !important;
        }
        
        .action-buttons {
            display: flex;
            justify-content: center;
            gap: 10px;
            margin-bottom: 20px;
            flex-wrap: wrap;
        }
        
        .btn-action {
            padding: 10px 20px;
            border-radius: 8px;
            font-weight: 600;
            text-decoration: none;
            color: white;
            transition: all 0.3s;
            border: none;
            cursor: pointer;
        }
        
        .btn-add {
            background-color: var(--secondary-color);
        }
        
        .btn-add:hover {
            background-color: #17a673;
            color: white;
        }
        
        .btn-print {
            background-color: var(--info-color);
        }
        
        .btn-print:hover {
            background-color: #2c9faf;
        }
        
        .btn-back {
            background-color: var(--dark-color);
        }
        
        .btn-back:hover {
            background-color: #484856;
            color: white;
        }
        
        .empty-state {
            text-align: center;
            padding: 60px 20px;
            color: var(--dark-color);
        }
        
        .empty-icon {
            font-size: 4rem;
            margin-bottom: 20px;
            opacity: 0.3;
        }
        
        @media (max-width: 768px) {
            .main-container {
                margin: 15px;
                padding: 20px;
            }
            
            .stats-cards {
                grid-template-columns: repeat(2, 1fr);
                gap: 15px;
            }
            
            .filter-row {
                flex-direction: column;
                align-items: stretch;
            }
            
            .filter-input {
                min-width: auto;
                width: 100%;
            }
            
            .action-buttons {
                flex-direction: column;
            }
            
            .expenses-table {
                font-size: 0.8rem;
            }
            
            .expenses-table td {
                padding: 8px 5px;
            }
        }
        
        @media print {
            .filters-section,
            .action-buttons {
                display: none !important;
            }
            
            body {
                background-color: white !important;
            }
            
            .main-container {
                box-shadow: none !important;
                margin: 0 !important;
                padding: 0 !important;
            }
        }
    </style>
</head>
<body>
    <div class="main-container">
        <div class="page-header">
            <h1 class="page-title">
                <i class="fas fa-list-alt me-2"></i>
                قائمة المصروفات والسحوبات
            </h1>
        </div>
        
        <!-- الإحصائيات -->
        <div class="stats-cards">
            <div class="stat-card expenses">
                <div class="stat-value"><?= number_format($total_expenses, 0, '', ',') ?></div>
                <div class="stat-label">إجمالي المصروفات (<?= $expenses_count ?>)</div>
            </div>
            <div class="stat-card withdrawals">
                <div class="stat-value"><?= number_format($total_withdrawals, 0, '', ',') ?></div>
                <div class="stat-label">إجمالي السحوبات (<?= $withdrawals_count ?>)</div>
            </div>
            <div class="stat-card total">
                <div class="stat-value"><?= number_format($total_amount, 0, '', ',') ?></div>
                <div class="stat-label">المجموع الكلي</div>
            </div>
        </div>
        
        <!-- الرسائل -->
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
        
        <!-- أزرار الإجراءات -->
        <div class="action-buttons">
            <a href="add_expense.php" class="btn-action btn-add">
                <i class="fas fa-plus me-2"></i>إضافة مصروف جديد
            </a>
            <button onclick="window.print()" class="btn-action btn-print">
                <i class="fas fa-print me-2"></i>طباعة
            </button>
            <a href="../dashboard.php" class="btn-action btn-back">
                <i class="fas fa-arrow-right me-2"></i>العودة للوحة التحكم
            </a>
        </div>
        
        <!-- فلاتر البحث -->
        <div class="filters-section">
            <form method="GET" action="">
                <div class="filter-row">
                    <div class="filter-group">
                        <label for="start_date">من تاريخ:</label>
                        <input type="date" id="start_date" name="start_date" class="filter-input" 
                               value="<?= $_GET['start_date'] ?? '' ?>">
                    </div>
                    
                    <div class="filter-group">
                        <label for="end_date">إلى تاريخ:</label>
                        <input type="date" id="end_date" name="end_date" class="filter-input" 
                               value="<?= $_GET['end_date'] ?? '' ?>">
                    </div>
                    
                    <div class="filter-group">
                        <label for="type">نوع المصروف:</label>
                        <select id="type" name="type" class="filter-input">
                            <option value="">الكل</option>
                            <option value="expense" <?= ($_GET['type'] ?? '') == 'expense' ? 'selected' : '' ?>>مصروفات</option>
                            <option value="withdrawal" <?= ($_GET['type'] ?? '') == 'withdrawal' ? 'selected' : '' ?>>سحوبات</option>
                        </select>
                    </div>
                    
                    <div class="filter-group">
                        <label>&nbsp;</label>
                        <button type="submit" class="btn-filter">
                            <i class="fas fa-search me-2"></i>تصفية
                        </button>
                    </div>
                </div>
            </form>
        </div>
        
        <!-- جدول المصروفات -->
        <?php if (empty($expenses_data)): ?>
            <div class="empty-state">
                <div class="empty-icon">
                    <i class="fas fa-inbox"></i>
                </div>
                <h3>لا توجد مصروفات</h3>
                <p>لم يتم العثور على أي مصروفات أو سحوبات في الفترة المحددة</p>
            </div>
        <?php else: ?>
            <div class="table-responsive">
                <table class="expenses-table">
                    <thead>
                        <tr>
                            <th width="15%">النوع</th>
                            <th width="20%">الموظف/المورد</th>
                            <th width="25%">الوصف</th>
                            <th width="15%">المبلغ</th>
                            <th width="15%">التاريخ</th>
                            <th width="10%">الوقت</th>
                        </tr>
                    </thead>
                    <tbody>
                        <?php foreach ($expenses_data as $expense): ?>
                            <tr>
                                <td>
                                    <span class="badge-type <?= $expense['type'] == 'expense' ? 'badge-expense' : 'badge-withdrawal' ?>">
                                        <?= $expense['type'] == 'expense' ? $expense['expense_type'] : 'سحب راتب' ?>
                                    </span>
                                </td>
                                <td>
                                    <?php
                                        if ($expense['type'] == 'expense') {
                                            $related_name = '';
                                            if ($expense['related_id'] && isset($suppliers[$expense['related_id']])) {
                                                $related_name = $suppliers[$expense['related_id']];
                                            }
                                            echo htmlspecialchars($related_name ?: '-');
                                        } else {
                                            $employee_name = '-';
                                            if ($expense['related_id'] && isset($employees[$expense['related_id']])) {
                                                $employee_name = $employees[$expense['related_id']];
                                            }
                                            echo htmlspecialchars($employee_name);
                                        }
                                    ?>
                                </td>
                                <td class="description-cell">
                                    <?= nl2br(htmlspecialchars($expense['description'])) ?>
                                </td>
                                <td class="amount-cell">
                                    <?= number_format($expense['amount'], 0, '', ',') ?>
                                </td>
                                <td>
                                    <?= date('Y-m-d', strtotime($expense['date'])) ?>
                                </td>
                                <td>
                                    <?= date('H:i', strtotime($expense['created_at'] ?? $expense['date'])) ?>
                                </td>
                            </tr>
                        <?php endforeach; ?>
                        
                        <!-- صف المجموع -->
                        <tr class="total-row">
                            <td colspan="3"><strong>المجموع الكلي:</strong></td>
                            <td class="amount-cell"><?= number_format($total_amount, 0, '', ',') ?></td>
                            <td colspan="2"></td>
                        </tr>
                    </tbody>
                </table>
            </div>
        <?php endif; ?>
    </div>
    
    <script src="<?= defined('BASE_URL') ? BASE_URL : '../../' ?>assets/js/jquery.min.js"></script>
    <script>
        document.addEventListener('DOMContentLoaded', function() {
            // إضافة وظيفة البحث في الجدول
            function addQuickSearch() {
                if (document.querySelectorAll('tbody tr:not(.total-row)').length === 0) return;
                
                const searchInput = document.createElement('input');
                searchInput.type = 'text';
                searchInput.placeholder = 'البحث السريع في الجدول...';
                searchInput.className = 'filter-input';
                searchInput.style.width = '100%';
                searchInput.style.marginBottom = '20px';
                
                const tableContainer = document.querySelector('.table-responsive');
                tableContainer.parentNode.insertBefore(searchInput, tableContainer);
                
                searchInput.addEventListener('input', function() {
                    const searchTerm = this.value.toLowerCase();
                    const rows = document.querySelectorAll('tbody tr:not(.total-row)');
                    
                    rows.forEach(row => {
                        const text = row.textContent.toLowerCase();
                        row.style.display = text.includes(searchTerm) ? '' : 'none';
                    });
                });
            }
            
            addQuickSearch();
            
            // تحسين تجربة المستخدم في الفلاتر
            const filterInputs = document.querySelectorAll('.filter-input');
            filterInputs.forEach(input => {
                if (input.type === 'date') {
                    input.addEventListener('change', function() {
                        // يمكن إضافة validation هنا
                    });
                }
            });
            
            // إضافة اختصارات لوحة المفاتيح
            document.addEventListener('keydown', function(e) {
                // Ctrl+P للطباعة
                if (e.ctrlKey && e.key === 'p') {
                    e.preventDefault();
                    window.print();
                }
                
                // Ctrl+F للبحث
                if (e.ctrlKey && e.key === 'f') {
                    e.preventDefault();
                    const searchInput = document.querySelector('input[placeholder*="البحث السريع"]');
                    if (searchInput) {
                        searchInput.focus();
                    }
                }
            });
        });
    </script>
</body>
</html>