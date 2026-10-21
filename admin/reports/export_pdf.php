<?php
// تضمين ملفات الاتصال بقاعدة البيانات والتوثيق
require_once '../../includes/db.php';

require_once '../../includes/functions.php';
require_once '../../includes/fpdf/fpdf.php';

// التحقق من المعلمات المطلوبة
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');
$report_type = isset($_GET['report_type']) ? $_GET['report_type'] : 'all';

// إنشاء فئة PDF مخصصة مع دعم اللغة العربية
class PDF extends FPDF {
    function Header() {
        // الشعار (إذا كان متوفرًا)
        // $this->Image('logo.png', 10, 10, 30);
        
        // الخط والعنوان
        $this->SetFont('aealarabiya', 'B', 18);
        $this->Cell(0, 10, 'التقرير الشامل', 0, 1, 'C');
        
        // تاريخ التقرير
        $this->SetFont('aealarabiya', '', 12);
        $this->Cell(0, 10, 'من ' . $_GET['start_date'] . ' إلى ' . $_GET['end_date'], 0, 1, 'C');
        
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
    
    function SummaryRow($label, $value) {
        $this->SetFont('aealarabiya', '', 12);
        $this->Cell(100, 10, $label, 0, 0, 'R');
        $this->Cell(80, 10, $value, 0, 1, 'L');
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

// تحديد أي تقرير سيتم إنشاؤه
switch ($report_type) {
    case 'revenue':
        generateRevenueReport($conn, $pdf, $start_date, $end_date);
        break;
    case 'expenses':
        generateExpensesReport($conn, $pdf, $start_date, $end_date);
        break;
    case 'occupancy':
        generateOccupancyReport($conn, $pdf, $start_date, $end_date);
        break;
    case 'rooms':
        generateRoomsReport($conn, $pdf, $start_date, $end_date);
        break;
    case 'withdrawals':
        generateWithdrawalsReport($conn, $pdf, $start_date, $end_date);
        break;
    case 'all':
    default:
        generateComprehensiveReport($conn, $pdf, $start_date, $end_date);
        break;
}

// إخراج الملف
$pdf->Output('comprehensive_report.pdf', 'D');
exit;

// دالة لإنشاء تقرير الإيرادات
function generateRevenueReport($conn, $pdf, $start_date, $end_date) {
    $pdf->ChapterTitle('تقرير الإيرادات');
    
    // استعلام الإيرادات
    $query = "
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
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $total_revenue = 0;
    $revenue_data = [];
    
    while ($row = $result->fetch_assoc()) {
        $revenue_data[] = $row;
        $total_revenue += $row['total_revenue'];
    }
    
    // عرض ملخص الإيرادات
    $pdf->SummaryRow('إجمالي الإيرادات:', number_format($total_revenue, 2) . ' ريال');
    $pdf->Ln(10);
    
    // عرض تفاصيل الإيرادات
    $pdf->TableHeader(['التاريخ', 'المبلغ (ريال)']);
    
    foreach ($revenue_data as $row) {
        $pdf->TableRow([
            $row['date'],
            number_format($row['total_revenue'], 2)
        ]);
    }
}

// دالة لإنشاء تقرير المصروفات
function generateExpensesReport($conn, $pdf, $start_date, $end_date) {
    $pdf->ChapterTitle('تقرير المصروفات');
    
    // استعلام إجمالي المصروفات
    $query = "SELECT SUM(amount) as total_expenses FROM expenses WHERE DATE(date) BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_expenses = $result->fetch_assoc()['total_expenses'] ?? 0;
    
    // عرض ملخص المصروفات
    $pdf->SummaryRow('إجمالي المصروفات:', number_format($total_expenses, 2) . ' ريال');
    $pdf->Ln(10);
    
    // استعلام المصروفات حسب الفئة
    $query = "
        SELECT 
            expense_type as expense_category,
            SUM(amount) as total_expense
        FROM 
            expenses
        WHERE 
            DATE(date) BETWEEN ? AND ?
        GROUP BY 
            expense_type
        ORDER BY 
            total_expense DESC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    // عرض المصروفات حسب الفئة
    $pdf->ChapterTitle('المصروفات حسب الفئة');
    $pdf->TableHeader(['الفئة', 'المبلغ (ريال)']);
    
    while ($row = $result->fetch_assoc()) {
        $pdf->TableRow([
            $row['expense_category'],
            number_format($row['total_expense'], 2)
        ]);
    }
    
    $pdf->Ln(10);
    
    // استعلام تفاصيل المصروفات
    $query = "
        SELECT 
            DATE(date) as date,
            expense_type as expense_category,
            description,
            amount
        FROM 
            expenses
        WHERE 
            DATE(date) BETWEEN ? AND ?
        ORDER BY 
            date ASC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    // عرض تفاصيل المصروفات
    $pdf->ChapterTitle('تفاصيل المصروفات');
    $pdf->TableHeader(['التاريخ', 'الفئة', 'المبلغ (ريال)']);
    
    while ($row = $result->fetch_assoc()) {
        $pdf->TableRow([
            $row['date'],
            $row['expense_category'],
            number_format($row['amount'], 2)
        ]);
    }
}

// دالة لإنشاء تقرير الإشغال
function generateOccupancyReport($conn, $pdf, $start_date, $end_date) {
    $pdf->ChapterTitle('تقرير الإشغال');
    
    // استعلام إحصائيات الإشغال
    $query = "
        SELECT 
            COUNT(*) as total_bookings,
            SUM(CASE WHEN status = 'checked_in' THEN 1 ELSE 0 END) as active_bookings,
            SUM(CASE WHEN status = 'checked_out' THEN 1 ELSE 0 END) as completed_bookings
        FROM 
            bookings
        WHERE 
            check_in BETWEEN ? AND ? OR check_out BETWEEN ? AND ?
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $occupancy_data = $result->fetch_assoc();
    
    // حساب معدل الإشغال
    $occupancy_rate = 0;
    if ($occupancy_data['total_bookings'] > 0) {
        $occupancy_rate = ($occupancy_data['active_bookings'] / $occupancy_data['total_bookings']) * 100;
    }
    
    // عرض ملخص الإشغال
    $pdf->SummaryRow('إجمالي الحجوزات:', $occupancy_data['total_bookings']);
    $pdf->SummaryRow('الحجوزات النشطة:', $occupancy_data['active_bookings']);
    $pdf->SummaryRow('الحجوزات المكتملة:', $occupancy_data['completed_bookings']);
    $pdf->SummaryRow('معدل الإشغال:', number_format($occupancy_rate, 2) . '%');
    $pdf->Ln(10);
    
    // استعلام تفاصيل الحجوزات
    $query = "
        SELECT 
            b.id,
            b.guest_name,
            r.room_number,
            b.check_in,
            b.check_out,
            b.status,
            COALESCE(SUM(p.amount), 0) as total_paid
        FROM 
            bookings b
        JOIN 
            rooms r ON b.room_id = r.id
        LEFT JOIN 
            payments p ON b.id = p.booking_id
        WHERE 
            b.check_in BETWEEN ? AND ? OR b.check_out BETWEEN ? AND ?
        GROUP BY 
            b.id
        ORDER BY 
            b.check_in ASC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    // عرض تفاصيل الحجوزات
    $pdf->ChapterTitle('تفاصيل الحجوزات');
    $pdf->TableHeader(['اسم الضيف', 'رقم الغرفة', 'تاريخ الوصول', 'تاريخ المغادرة', 'المبلغ (ريال)']);
    
    while ($row = $result->fetch_assoc()) {
        $pdf->TableRow([
            $row['guest_name'],
            $row['room_number'],
            $row['check_in'],
            $row['check_out'],
            number_format($row['total_paid'], 2)
        ]);
    }
}

// دالة لإنشاء تقرير الغرف
function generateRoomsReport($conn, $pdf, $start_date, $end_date) {
    $pdf->ChapterTitle('تقرير أداء الغرف');
    
    // استعلام أداء الغرف
    $query = "
        SELECT 
            r.room_number,
            r.room_type,
            COUNT(b.id) as booking_count,
            COALESCE(SUM(p.amount), 0) as room_revenue
        FROM 
            rooms r
        LEFT JOIN 
            bookings b ON r.id = b.room_id AND (b.check_in BETWEEN ? AND ? OR b.check_out BETWEEN ? AND ?)
        LEFT JOIN 
            payments p ON b.id = p.booking_id
        GROUP BY 
            r.id
        ORDER BY 
            room_revenue DESC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    // عرض تفاصيل أداء الغرف
    $pdf->TableHeader(['رقم الغرفة', 'نوع الغرفة', 'عدد الحجوزات', 'الإيرادات (ريال)']);
    
    while ($row = $result->fetch_assoc()) {
        $pdf->TableRow([
            $row['room_number'],
            $row['room_type'],
            $row['booking_count'],
            number_format($row['room_revenue'], 2)
        ]);
    }
}

// دالة لإنشاء تقرير سحوبات الموظفين
function generateWithdrawalsReport($conn, $pdf, $start_date, $end_date) {
    $pdf->ChapterTitle('تقرير سحوبات الموظفين');
    
    // استعلام إجمالي سحوبات الموظفين
    $query = "SELECT SUM(amount) as total_withdrawals FROM employee_withdrawals WHERE withdrawal_date BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_withdrawals = $result->fetch_assoc()['total_withdrawals'] ?? 0;
    
    // عرض ملخص سحوبات الموظفين
    $pdf->SummaryRow('إجمالي سحوبات الموظفين:', number_format($total_withdrawals, 2) . ' ريال');
    $pdf->Ln(10);
    
    // استعلام سحوبات الموظفين حسب الموظف
    $query = "
        SELECT 
            e.name as employee_name,
            SUM(w.amount) as total_withdrawals
        FROM 
            employee_withdrawals w
        JOIN 
            employees e ON w.employee_id = e.id
        WHERE 
            w.withdrawal_date BETWEEN ? AND ?
        GROUP BY 
            w.employee_id
        ORDER BY 
            total_withdrawals DESC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    // عرض سحوبات الموظفين حسب الموظف
    $pdf->ChapterTitle('سحوبات الموظفين حسب الموظف');
    $pdf->TableHeader(['الموظف', 'إجمالي السحوبات (ريال)']);
    
    while ($row = $result->fetch_assoc()) {
        $pdf->TableRow([
            $row['employee_name'],
            number_format($row['total_withdrawals'], 2)
        ]);
    }
    
    $pdf->Ln(10);
    
    // استعلام تفاصيل سحوبات الموظفين
    $query = "
        SELECT 
            e.name as employee_name,
            w.withdrawal_date,
            w.amount,
            w.notes
        FROM 
            employee_withdrawals w
        JOIN 
            employees e ON w.employee_id = e.id
        WHERE 
            w.withdrawal_date BETWEEN ? AND ?
        ORDER BY 
            w.withdrawal_date ASC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    // عرض تفاصيل سحوبات الموظفين
    $pdf->ChapterTitle('تفاصيل سحوبات الموظفين');
    $pdf->TableHeader(['الموظف', 'التاريخ', 'المبلغ (ريال)']);
    
    while ($row = $result->fetch_assoc()) {
        $pdf->TableRow([
            $row['employee_name'],
            $row['withdrawal_date'],
            number_format($row['amount'], 2)
        ]);
    }
}

// دالة لإنشاء التقرير الشامل
function generateComprehensiveReport($conn, $pdf, $start_date, $end_date) {
    // استعلام ملخص الإيرادات
    $query = "SELECT SUM(amount) as total_revenue FROM payments WHERE payment_date BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_revenue = $result->fetch_assoc()['total_revenue'] ?? 0;
    
    // استعلام ملخص المصروفات
    $query = "SELECT SUM(amount) as total_expenses FROM expenses WHERE expense_date BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_expenses = $result->fetch_assoc()['total_expenses'] ?? 0;
    
    // استعلام ملخص سحوبات الموظفين
    $query = "SELECT SUM(amount) as total_withdrawals FROM employee_withdrawals WHERE withdrawal_date BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_withdrawals = $result->fetch_assoc()['total_withdrawals'] ?? 0;
    
    // حساب صافي الربح
    $net_profit = $total_revenue - $total_expenses;
    
    // عرض ملخص التقرير
    $pdf->ChapterTitle('ملخص التقرير');
    $pdf->SummaryRow('إجمالي الإيرادات:', number_format($total_revenue, 2) . ' ريال');
    $pdf->SummaryRow('إجمالي المصروفات:', number_format($total_expenses, 2) . ' ريال');
    $pdf->SummaryRow('صافي الربح:', number_format($net_profit, 2) . ' ريال');
    $pdf->SummaryRow('إجمالي سحوبات الموظفين:', number_format($total_withdrawals, 2) . ' ريال');
    $pdf->Ln(10);
    
    // إنشاء تقرير الإيرادات
    generateRevenueReport($conn, $pdf, $start_date, $end_date);
    
    // إضافة صفحة جديدة
    $pdf->AddPage();
    
    // إنشاء تقرير المصروفات
    generateExpensesReport($conn, $pdf, $start_date, $end_date);
    
    // إضافة صفحة جديدة
    $pdf->AddPage();
    
    // إنشاء تقرير الإشغال
    generateOccupancyReport($conn, $pdf, $start_date, $end_date);
    
    // إضافة صفحة جديدة
    $pdf->AddPage();
    
    // إنشاء تقرير الغرف
    generateRoomsReport($conn, $pdf, $start_date, $end_date);
    
    // إضافة صفحة جديدة
    $pdf->AddPage();
    
    // إنشاء تقرير سحوبات الموظفين
    generateWithdrawalsReport($conn, $pdf, $start_date, $end_date);
}
