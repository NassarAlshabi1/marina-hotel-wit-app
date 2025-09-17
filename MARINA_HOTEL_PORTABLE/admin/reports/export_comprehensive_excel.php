<?php
// تضمين ملفات التهيئة والتحقق من تسجيل الدخول
require_once '../../includes/db.php';
require_once '../../includes/auth_check.php';
require_once '../../includes/functions.php';

// التحقق من وجود المعاملات المطلوبة
if (!isset($_GET['start_date']) || !isset($_GET['end_date']) || !isset($_GET['report_type'])) {
    die('معاملات غير كافية');
}

$start_date = $_GET['start_date'];
$end_date = $_GET['end_date'];
$report_type = $_GET['report_type'];

// تعيين رأس التنسيق لملف Excel
header('Content-Type: application/vnd.ms-excel');
header('Content-Disposition: attachment; filename="comprehensive_report_' . date('Y-m-d') . '.xls"');

// الحصول على بيانات الإيرادات
function get_revenue_data($conn, $start_date, $end_date) {
    $sql = "SELECT 
                DATE(payment_date) as payment_day,
                SUM(amount) as daily_revenue
            FROM payments
            WHERE payment_date BETWEEN ? AND ?
            GROUP BY payment_day
            ORDER BY payment_day";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $revenue_data = [];
    $total_revenue = 0;
    
    while ($row = $result->fetch_assoc()) {
        $revenue_data[$row['payment_day']] = $row['daily_revenue'];
        $total_revenue += $row['daily_revenue'];
    }
    
    return [
        'daily_data' => $revenue_data,
        'total' => $total_revenue
    ];
}

// الحصول على بيانات المصروفات
function get_expense_data($conn, $start_date, $end_date) {
    $sql = "SELECT 
                DATE(expense_date) as expense_day,
                SUM(amount) as daily_expense,
                category
            FROM expenses
            WHERE expense_date BETWEEN ? AND ?
            GROUP BY expense_day, category
            ORDER BY expense_day";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $expense_data = [];
    $expense_by_category = [];
    $total_expense = 0;
    
    while ($row = $result->fetch_assoc()) {
        $day = $row['expense_day'];
        $category = $row['category'];
        $amount = $row['daily_expense'];
        
        if (!isset($expense_data[$day])) {
            $expense_data[$day] = 0;
        }
        
        $expense_data[$day] += $amount;
        
        if (!isset($expense_by_category[$category])) {
            $expense_by_category[$category] = 0;
        }
        
        $expense_by_category[$category] += $amount;
        $total_expense += $amount;
    }
    
    return [
        'daily_data' => $expense_data,
        'by_category' => $expense_by_category,
        'total' => $total_expense
    ];
}

// الحصول على بيانات الإشغال
function get_occupancy_data($conn, $start_date, $end_date) {
    // الحصول على إجمالي عدد الغرف
    $total_rooms_sql = "SELECT COUNT(*) as total FROM rooms WHERE status = 'active'";
    $total_rooms_result = $conn->query($total_rooms_sql);
    $total_rooms = $total_rooms_result->fetch_assoc()['total'];
    
    // الحصول على بيانات الإشغال اليومية
    $sql = "SELECT 
                DATE(check_in) as day,
                COUNT(*) as booked_rooms
            FROM bookings
            WHERE 
                (check_in BETWEEN ? AND ?) OR
                (check_out BETWEEN ? AND ?) OR
                (check_in <= ? AND check_out >= ?)
            GROUP BY day
            ORDER BY day";
    
    $stmt = $conn->prepare($sql);
    $stmt->bind_param("ssssss", $start_date, $end_date, $start_date, $end_date, $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $occupancy_data = [];
    $total_booked_days = 0;
    $possible_days = (strtotime($end_date) - strtotime($start_date)) / (60 * 60 * 24) + 1;
    
    while ($row = $result->fetch_assoc()) {
        $day = $row['day'];
        $booked = $row['booked_rooms'];
        $occupancy_rate = ($total_rooms > 0) ? ($booked / $total_rooms) * 100 : 0;
        
        $occupancy_data[$day] = [
            'booked' => $booked,
            'total' => $total_rooms,
            'rate' => $occupancy_rate
        ];
        
        $total_booked_days += $booked;
    }
    
    $average_occupancy = ($total_rooms > 0 && $possible_days > 0) ? 
        ($total_booked_days / ($total_rooms * $possible_days)) * 100 : 0;
    
    return [
        'daily_data' => $occupancy_data,
        'average_rate' => $average_occupancy,
        'total_rooms' => $total_rooms
    ];
}

// الحصول على البيانات حسب نوع التقرير
$revenue_data = ($report_type == 'all' || $report_type == 'revenue') ? 
    get_revenue_data($conn, $start_date, $end_date) : null;
    
$expense_data = ($report_type == 'all' || $report_type == 'expenses') ? 
    get_expense_data($conn, $start_date, $end_date) : null;
    
$occupancy_data = ($report_type == 'all' || $report_type == 'occupancy') ? 
    get_occupancy_data($conn, $start_date, $end_date) : null;

// حساب صافي الربح إذا كانت البيانات متاحة
$net_profit = 0;
if ($revenue_data && $expense_data) {
    $net_profit = $revenue_data['total'] - $expense_data['total'];
}

// بناء ملف Excel
echo '<html xmlns:o="urn:schemas-microsoft-com:office:office" xmlns:x="urn:schemas-microsoft-com:office:excel" xmlns="http://www.w3.org/TR/REC-html40">
<head>
<meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
<!--[if gte mso 9]>
<xml>
 <x:ExcelWorkbook>
  <x:ExcelWorksheets>
   <x:ExcelWorksheet>
    <x:Name>Comprehensive Report</x:Name>
    <x:WorksheetOptions>
     <x:Panes></x:Panes>
    </x:WorksheetOptions>
   </x:ExcelWorksheet>
  </x:ExcelWorksheets>
 </x:ExcelWorkbook>
</xml>
<![endif]-->
<style>
td {
    mso-number-format: "\@";
    text-align: right;
    direction: rtl;
}
.number {
    mso-number-format: "#,##0.00";
}
.header {
    background-color: #f0f0f0;
    font-weight: bold;
}
</style>
</head>
<body>
<table border="1">
    <tr>
        <td colspan="4" style="text-align: center; font-size: 18pt; font-weight: bold;">التقرير الشامل</td>
    </tr>
    <tr>
        <td colspan="4" style="text-align: center;">من ' . date('Y/m/d', strtotime($start_date)) . ' إلى ' . date('Y/m/d', strtotime($end_date)) . '</td>
    </tr>
    <tr><td colspan="4"></td></tr>';

// ملخص التقرير
echo '<tr><td colspan="4" style="font-weight: bold; background-color: #cccccc;">ملخص التقرير</td></tr>';

if ($revenue_data) {
    echo '<tr><td>إجمالي الإيرادات:</td><td class="number">' . $revenue_data['total'] . '</td><td colspan="2"></td></tr>';
}

if ($expense_data) {
    echo '<tr><td>إجمالي المصروفات:</td><td class="number">' . $expense_data['total'] . '</td><td colspan="2"></td></tr>';
}

if ($revenue_data && $expense_data) {
    echo '<tr><td>صافي الربح:</td><td class="number">' . $net_profit . '</td><td colspan="2"></td></tr>';
}

if ($occupancy_data) {
    echo '<tr><td>متوسط نسبة الإشغال:</td><td>' . number_format($occupancy_data['average_rate'], 1) . '%</td><td colspan="2"></td></tr>';
}

echo '<tr><td colspan="4"></td></tr>';

// تفاصيل الإيرادات
if ($revenue_data) {
    echo '<tr><td colspan="4" style="font-weight: bold; background-color: #cccccc;">تفاصيل الإيرادات</td></tr>';
    echo '<tr class="header"><td>التاريخ</td><td>الإيراد اليومي</td><td>النسبة من الإجمالي</td><td></td></tr>';
    
    foreach ($revenue_data['daily_data'] as $date => $amount) {
        $percentage = ($revenue_data['total'] > 0) ? ($amount / $revenue_data['total']) * 100 : 0;
        echo '<tr>';
        echo '<td>' . date('Y/m/d', strtotime($date)) . '</td>';
        echo '<td class="number">' . $amount . '</td>';
        echo '<td>' . number_format($percentage, 1) . '%</td>';
        echo '<td></td>';
        echo '</tr>';
    }
    
    echo '<tr class="header">';
    echo '<td>الإجمالي</td>';
    echo '<td class="number">' . $revenue_data['total'] . '</td>';
    echo '<td>100%</td>';
    echo '<td></td>';
    echo '</tr>';
    
    echo '<tr><td colspan="4"></td></tr>';
}

// تفاصيل المصروفات
if ($expense_data) {
    echo '<tr><td colspan="4" style="font-weight: bold; background-color: #cccccc;">تفاصيل المصروفات</td></tr>';
    echo '<tr class="header"><td>التاريخ</td><td>المصروف اليومي</td><td>النسبة من الإجمالي</td><td></td></tr>';
    
    foreach ($expense_data['daily_data'] as $date => $amount) {
        $percentage = ($expense_data['total'] > 0) ? ($amount / $expense_data['total']) * 100 : 0;
        echo '<tr>';
        echo '<td>' . date('Y/m/d', strtotime($date)) . '</td>';
        echo '<td class="number">' . $amount . '</td>';
        echo '<td>' . number_format($percentage, 1) . '%</td>';
        echo '<td></td>';
        echo '</tr>';
    }
    
    echo '<tr class="header">';
    echo '<td>الإجمالي</td>';
    echo '<td class="number">' . $expense_data['total'] . '</td>';
    echo '<td>100%</td>';
    echo '<td></td>';
    echo '</tr>';
    
    echo '<tr><td colspan="4"></td></tr>';
    
    // المصروفات حسب الفئة
    echo '<tr><td colspan="4" style="font-weight: bold; background-color: #cccccc;">المصروفات حسب الفئة</td></tr>';
    echo '<tr class="header"><td>الفئة</td><td>المبلغ</td><td>النسبة من الإجمالي</td><td></td></tr>';
    
    foreach ($expense_data['by_category'] as $category => $amount) {
        $percentage = ($expense_data['total'] > 0) ? ($amount / $expense_data['total']) * 100 : 0;
        echo '<tr>';
        echo '<td>' . $category . '</td>';
        echo '<td class="number">' . $amount . '</td>';
        echo '<td>' . number_format($percentage, 1) . '%</td>';
        echo '<td></td>';
        echo '</tr>';
    }
    
    echo '<tr class="header">';
    echo '<td>الإجمالي</td>';
    echo '<td class="number">' . $expense_data['total'] . '</td>';
    echo '<td>100%</td>';
    echo '<td></td>';
    echo '</tr>';
    
    echo '<tr><td colspan="4"></td></tr>';
}

// تفاصيل الإشغال
if ($occupancy_data) {
    echo '<tr><td colspan="4" style="font-weight: bold; background-color: #cccccc;">تفاصيل الإشغال</td></tr>';
    echo '<tr class="header"><td>التاريخ</td><td>الغرف المشغولة</td><td>إجمالي الغرف</td><td>نسبة الإشغال</td></tr>';
    
    $current = strtotime($start_date);
    $end = strtotime($end_date);
    
    while ($current <= $end) {
        $date = date('Y-m-d', $current);
        $booked = isset($occupancy_data['daily_data'][$date]) ? $occupancy_data['daily_data'][$date]['booked'] : 0;
        $total = $occupancy_data['total_rooms'];
        $rate = ($total > 0) ? ($booked / $total) * 100 : 0;
        
        echo '<tr>';
        echo '<td>' . date('Y/m/d', $current) . '</td>';
        echo '<td>' . $booked . '</td>';
        echo '<td>' . $total . '</td>';
        echo '<td>' . number_format($rate, 1) . '%</td>';
        echo '</tr>';
        
        $current = strtotime('+1 day', $current);
    }
    
    echo '<tr class="header">';
    echo '<td>المتوسط الإجمالي</td>';
    echo '<td></td>';
    echo '<td></td>';
    echo '<td>' . number_format($occupancy_data['average_rate'], 1) . '%</td>';
    echo '</tr>';
    
    echo '<tr><td colspan="4"></td></tr>';
}

echo '<tr><td colspan="4">تم إنشاء هذا التقرير في ' . date('Y/m/d H:i:s') . ' بواسطة ' . $_SESSION['username'] . '</td></tr>';
echo '</table></body></html>';
?>
