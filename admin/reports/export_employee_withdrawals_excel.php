<?php
require_once '../../includes/db.php';
require_once '../../includes/functions.php';
require_once '../../includes/report_functions.php';

// التحقق من المعاملات
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');
$employee_id = isset($_GET['employee_id']) ? (int)$_GET['employee_id'] : 0;

// تحديد اسم الملف
$filename = 'تقرير_سحوبات_الموظفين_' . $start_date . '_إلى_' . $end_date . '.xls';

// إعداد headers للتحميل
header('Content-Type: application/vnd.ms-excel; charset=UTF-8');
header('Content-Disposition: attachment; filename="' . $filename . '"');
header('Cache-Control: max-age=0');

// بدء محتوى Excel مع دعم UTF-8
echo "\xEF\xBB\xBF"; // UTF-8 BOM

// إعداد الاستعلام
$where_conditions = ["DATE(sw.date) BETWEEN ? AND ?"];
$params = [$start_date, $end_date];
$param_types = "ss";

if ($employee_id > 0) {
    $where_conditions[] = "sw.employee_id = ?";
    $params[] = $employee_id;
    $param_types .= "i";
}

// جلب البيانات
$withdrawals_query = "
    SELECT 
        e.id as employee_id,
        e.name as employee_name,
        e.salary as monthly_salary,
        sw.amount as withdrawal_amount,
        sw.date as withdrawal_date,
        sw.notes,
        (SELECT COALESCE(SUM(amount), 0) 
         FROM salary_withdrawals 
         WHERE employee_id = e.id 
         AND YEAR(date) = YEAR(sw.date) 
         AND MONTH(date) = MONTH(sw.date)
         AND date <= sw.date) as total_withdrawn_month
    FROM salary_withdrawals sw
    JOIN employees e ON sw.employee_id = e.id
    WHERE " . implode(" AND ", $where_conditions) . "
    ORDER BY sw.date DESC, e.name ASC
";

$all_params = array_merge([$start_date, $end_date], $params);
$all_param_types = "ss" . $param_types;

$stmt = $conn->prepare($withdrawals_query);
$stmt->bind_param($all_param_types, ...$all_params);
$stmt->execute();
$result = $stmt->get_result();

$withdrawals_data = [];
$employee_summaries = [];
$total_withdrawals = 0;

while ($row = $result->fetch_assoc()) {
    $withdrawals_data[] = $row;
    $total_withdrawals += $row['withdrawal_amount'];
    
    $emp_id = $row['employee_id'];
    if (!isset($employee_summaries[$emp_id])) {
        $employee_summaries[$emp_id] = [
            'name' => $row['employee_name'],
            'monthly_salary' => $row['monthly_salary'],
            'total_withdrawn' => 0,
            'withdrawal_count' => 0
        ];
    }
    
    $employee_summaries[$emp_id]['total_withdrawn'] += $row['withdrawal_amount'];
    $employee_summaries[$emp_id]['withdrawal_count']++;
}

$stmt->close();
?>
<!DOCTYPE html>
<html dir="rtl">
<head>
    <meta charset="UTF-8">
    <style>
        body { 
            font-family: Arial, sans-serif; 
            direction: rtl; 
            text-align: right;
        }
        .header { 
            background-color: #4472C4; 
            color: white; 
            font-weight: bold; 
            text-align: center;
            font-size: 16px;
            padding: 10px;
        }
        .summary-table { 
            border-collapse: collapse; 
            width: 100%; 
            margin-bottom: 20px;
        }
        .summary-table th, .summary-table td { 
            border: 1px solid #000; 
            padding: 8px; 
            text-align: center;
        }
        .summary-table th { 
            background-color: #D9E2F3; 
            font-weight: bold;
        }
        .data-table { 
            border-collapse: collapse; 
            width: 100%; 
            margin-bottom: 30px;
        }
        .data-table th, .data-table td { 
            border: 1px solid #000; 
            padding: 6px; 
            text-align: center;
        }
        .data-table th { 
            background-color: #E2EFDA; 
            font-weight: bold;
        }
        .section-title { 
            background-color: #70AD47; 
            color: white; 
            font-weight: bold; 
            padding: 10px; 
            text-align: center;
            font-size: 14px;
        }
        .amount-positive { color: #008000; font-weight: bold; }
        .amount-negative { color: #FF0000; font-weight: bold; }
        .amount-warning { color: #FF8C00; font-weight: bold; }
        .total-row { background-color: #F2F2F2; font-weight: bold; }
    </style>
</head>
<body>

<!-- رأس التقرير -->
<div class="header">
    <h1>تقرير سحوبات الموظفين المفصل</h1>
    <p>من <?php echo format_arabic_date($start_date); ?> إلى <?php echo format_arabic_date($end_date); ?></p>
    <p>تاريخ الطباعة: <?php echo format_arabic_date(date('Y-m-d')); ?> - <?php echo date('H:i:s'); ?></p>
</div>

<br>

<!-- ملخص عام -->
<table class="summary-table">
    <tr>
        <th colspan="2">الملخص العام</th>
    </tr>
    <tr>
        <td>عدد الموظفين</td>
        <td><?php echo count($employee_summaries); ?> موظف</td>
    </tr>
    <tr>
        <td>إجمالي السحوبات</td>
        <td class="amount-warning"><?php echo format_currency($total_withdrawals); ?></td>
    </tr>
    <tr>
        <td>عدد عمليات السحب</td>
        <td><?php echo count($withdrawals_data); ?> عملية</td>
    </tr>
    <tr>
        <td>متوسط السحب</td>
        <td class="amount-warning">
            <?php echo count($withdrawals_data) > 0 ? format_currency($total_withdrawals / count($withdrawals_data)) : format_currency(0); ?>
        </td>
    </tr>
</table>

<!-- ملخص الموظفين -->
<?php if (!empty($employee_summaries)): ?>
<div class="section-title">ملخص الموظفين والرواتب المتبقية</div>
<table class="data-table">
    <thead>
        <tr>
            <th>م</th>
            <th>اسم الموظف</th>
            <th>الراتب الشهري</th>
            <th>إجمالي المسحوب</th>
            <th>الراتب المتبقي</th>
            <th>نسبة السحب</th>
            <th>عدد السحوبات</th>
        </tr>
    </thead>
    <tbody>
        <?php $counter = 1; ?>
        <?php foreach ($employee_summaries as $emp_id => $summary): ?>
            <?php 
            $remaining_salary = $summary['monthly_salary'] - $summary['total_withdrawn'];
            $withdrawal_percentage = $summary['monthly_salary'] > 0 ? 
                ($summary['total_withdrawn'] / $summary['monthly_salary']) * 100 : 0;
            ?>
            <tr>
                <td><?php echo $counter++; ?></td>
                <td><?php echo htmlspecialchars($summary['name']); ?></td>
                <td class="amount-positive"><?php echo format_currency($summary['monthly_salary']); ?></td>
                <td class="amount-warning"><?php echo format_currency($summary['total_withdrawn']); ?></td>
                <td class="amount-positive"><?php echo format_currency($remaining_salary); ?></td>
                <td><?php echo number_format($withdrawal_percentage, 1); ?>%</td>
                <td><?php echo $summary['withdrawal_count']; ?> مرة</td>
            </tr>
        <?php endforeach; ?>
    </tbody>
</table>
<br>
<?php endif; ?>

<!-- تفاصيل السحوبات -->
<?php if (!empty($withdrawals_data)): ?>
<div class="section-title">تفاصيل عمليات السحب</div>
<table class="data-table">
    <thead>
        <tr>
            <th>م</th>
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
            ?>
            <tr>
                <td><?php echo $counter++; ?></td>
                <td><?php echo htmlspecialchars($withdrawal['employee_name']); ?></td>
                <td class="amount-positive"><?php echo format_currency($withdrawal['monthly_salary']); ?></td>
                <td class="amount-warning"><?php echo format_currency($withdrawal['withdrawal_amount']); ?></td>
                <td class="amount-negative"><?php echo format_currency($withdrawal['total_withdrawn_month']); ?></td>
                <td class="amount-positive"><?php echo format_currency($remaining_salary); ?></td>
                <td><?php echo format_arabic_date($withdrawal['withdrawal_date']); ?></td>
                <td><?php echo htmlspecialchars($withdrawal['notes'] ?? '-'); ?></td>
            </tr>
        <?php endforeach; ?>
    </tbody>
</table>
<?php endif; ?>

<!-- تذييل التقرير -->
<br><br>
<table class="summary-table">
    <tr>
        <td colspan="2" style="text-align: center; background-color: #F8F9FA; font-style: italic;">
            تم إنشاء هذا التقرير تلقائياً بواسطة نظام إدارة الفندق<br>
            تاريخ الإنشاء: <?php echo date('Y-m-d H:i:s'); ?>
        </td>
    </tr>
</table>

</body>
</html>

<?php $conn->close(); ?>
