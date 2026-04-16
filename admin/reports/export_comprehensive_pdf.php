<?php
// تضمين ملفات التهيئة والتحقق من تسجيل الدخول
require_once '../../includes/db.php';

require_once '../../includes/functions.php';
require_once '../../includes/fpdf/fpdf.php';

// التحقق من وجود المعاملات المطلوبة
if (!isset($_GET['start_date']) || !isset($_GET['end_date']) || !isset($_GET['report_type'])) {
    die('معاملات غير كافية');
}

$start_date = $_GET['start_date'];
$end_date = $_GET['end_date'];
$report_type = $_GET['report_type'];

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

// إنشاء ملف PDF
class PDF extends FPDF {
    function Header() {
        // الشعار (إذا كان متوفرًا)
        // $this->Image('logo.png', 10, 10, 30);
        
        // الخط العريض للعنوان
        $this->SetFont('aealarabiya', 'B', 20);
        
        // العنوان
        $this->Cell(0, 10, 'التقرير الشامل', 0, 1, 'C');
        
        // تاريخ التقرير
        $this->SetFont('aealarabiya', '', 12);
        $this->Cell(0, 10, 'من ' . date('Y/m/d', strtotime($_GET['start_date'])) . ' إلى ' . date('Y/m/d', strtotime($_GET['end_date'])), 0, 1, 'C');
        
        // خط تحت العنوان
        $this->Line(10, $this->GetY(), 200, $this->GetY());
        $this->Ln(5);
    }
    
    function Footer() {
        $this->SetY(-15);
        $this->SetFont('aealarabiya', 'I', 8);
        $this->Cell(0, 10, 'الصفحة ' . $this->PageNo() . '/{nb}', 0, 0, 'C');
    }
    
    function ChapterTitle($title) {
        $this->SetFont('aealarabiya', 'B', 14);
        $this->SetFillColor(220, 220, 220);
        $this->Cell(0, 10, $title, 0, 1, 'R', true);
        $this->Ln(5);
    }
    
    function SummaryRow($label, $value, $unit = '') {
        $this->SetFont('aealarabiya', '', 12);
        $this->Cell(100, 10, $label, 0, 0, 'R');
        $this->Cell(80, 10, $value . ' ' . $unit, 0, 1, 'L');
    }
    
    function TableHeader($headers) {
        $this->SetFont('aealarabiya', 'B', 12);
        $this->SetFillColor(220, 220, 220);
        
        $width = 190 / count($headers);
        foreach ($headers as $header) {
            $this->Cell($width, 8, $header, 1, 0, 'C', true);
        }
        $this->Ln();
    }
    
    function TableRow($data) {
        $this->SetFont('aealarabiya', '', 10);
        
        $width = 190 / count($data);
        foreach ($data as $value) {
            $this->Cell($width, 8, $value, 1, 0, 'C');
        }
        $this->Ln();
    }
}

// إنشاء وضبط الملف
$pdf = new PDF();
$pdf->AddFont('aealarabiya', '', 'aealarabiya.php');
$pdf->AddFont('aealarabiya', 'B', 'aealarabiya.php');
$pdf->AddFont('aealarabiya', 'I', 'aealarabiya.php');
$pdf->AliasNbPages();
$pdf->AddPage();
$pdf->SetFont('aealarabiya', '', 12);
$pdf->SetRightMargin(10);
$pdf->SetLeftMargin(10);
$pdf->SetAutoPageBreak(true, 15);

// ملخص التقرير
$pdf->ChapterTitle('ملخص التقرير');

if ($revenue_data) {
    $pdf->SummaryRow('إجمالي الإيرادات:', number_format($revenue_data['total'], 2), 'ريال');
}

if ($expense_data) {
    $pdf->SummaryRow('إجمالي المصروفات:', number_format($expense_data['total'], 2), 'ريال');
}

if ($revenue_data && $expense_data) {
    $pdf->SummaryRow('صافي الربح:', number_format($net_profit, 2), 'ريال');
}

if ($occupancy_data) {
    $pdf->SummaryRow('متوسط نسبة الإشغال:', number_format($occupancy_data['average_rate'], 1), '%');
}

$pdf->Ln(10);

// تفاصيل الإيرادات
if ($revenue_data)  {
    $pdf->ChapterTitle('تفاصيل الإيرادات');
    $pdf->TableHeader(['التاريخ', 'الإيراد اليومي', 'النسبة من الإجمالي']);
    
    foreach ($revenue_data['daily_data'] as $date => $amount) {
        $percentage = ($revenue_data['total'] > 0) ? ($amount / $revenue_data['total']) * 100 : 0;
        $pdf->TableRow([
            date('Y/m/d', strtotime($date)),
            number_format($amount, 2) . ' ريال',
            number_format($percentage, 1) . '%'
        ]);
    }
    
    $pdf->SetFont('aealarabiya', 'B', 12);
    $pdf->TableRow([
        'الإجمالي',
        number_format($revenue_data['total'], 2) . ' ريال',
        '100%'
    ]);
    
    $pdf->Ln(10);
}

// تفاصيل المصروفات
if ($expense_data) {
    $pdf->ChapterTitle('تفاصيل المصروفات');
    $pdf->TableHeader(['التاريخ', 'المصروف اليومي', 'النسبة من الإجمالي']);
    
    foreach ($expense_data['daily_data'] as $date => $amount) {
        $percentage = ($expense_data['total'] > 0) ? ($amount / $expense_data['total']) * 100 : 0;
        $pdf->TableRow([
            date('Y/m/d', strtotime($date)),
            number_format($amount, 2) . ' ريال',
            number_format($percentage, 1) . '%'
        ]);
    }
    
    $pdf->SetFont('aealarabiya', 'B', 12);
    $pdf->TableRow([
        'الإجمالي',
        number_format($expense_data['total'], 2) . ' ريال',
        '100%'
    ]);
    
    $pdf->Ln(10);
    
    // المصروفات حسب الفئة
    $pdf->ChapterTitle('المصروفات حسب الفئة');
    $pdf->TableHeader(['الفئة', 'المبلغ', 'النسبة من الإجمالي']);
    
    foreach ($expense_data['by_category'] as $category => $amount) {
        $percentage = ($expense_data['total'] > 0) ? ($amount / $expense_data['total']) * 100 : 0;
        $pdf->TableRow([
            $category,
            number_format($amount, 2) . ' ريال',
            number_format($percentage, 1) . '%'
        ]);
    }
    
    $pdf->SetFont('aealarabiya', 'B', 12);
    $pdf->TableRow([
        'الإجمالي',
        number_format($expense_data['total'], 2) . ' ريال',
        '100%'
    ]);
    
    $pdf->Ln(10);
}

// تفاصيل الإشغال
if ($occupancy_data) {
    $pdf->ChapterTitle('تفاصيل الإشغال');
    $pdf->TableHeader(['التاريخ', 'الغرف المشغولة', 'إجمالي الغرف', 'نسبة الإشغال']);
    
    $current = strtotime($start_date);
    $end = strtotime($end_date);
    
    while ($current <= $end) {
        $date = date('Y-m-d', $current);
        $booked = isset($occupancy_data['daily_data'][$date]) ? $occupancy_data['daily_data'][$date]['booked'] : 0;
        $total = $occupancy_data['total_rooms'];
        $rate = ($total > 0) ? ($booked / $total) * 100 : 0;
        
        $pdf->TableRow([
            date('Y/m/d', $current),
            $booked,
            $total,
            number_format($rate, 1) . '%'
        ]);
        
        $current = strtotime('+1 day', $current);
    }
    
    $pdf->SetFont('aealarabiya', 'B', 12);
    $pdf->TableRow([
        'المتوسط الإجمالي',
        '',
        '',
        number_format($occupancy_data['average_rate'], 1) . '%'
    ]);
    
    $pdf->Ln(10);
}

// معلومات التقرير
$pdf->SetFont('aealarabiya', 'I', 10);
$pdf->Cell(0, 10, 'تم إنشاء هذا التقرير في ' . date('Y/m/d H:i:s') . ' بواسطة ' . $_SESSION['username'], 0, 1, 'C');

// إخراج الملف
$pdf->Output('comprehensive_report_' . date('Y-m-d') . '.pdf', 'D');
?>
