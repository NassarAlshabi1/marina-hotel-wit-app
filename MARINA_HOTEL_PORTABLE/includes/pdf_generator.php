<?php
/**
 * مولد PDF محسن للتقارير العربية
 * يستخدم FPDF مع دعم كامل للغة العربية
 */

require_once 'fpdf/fpdf.php';

class ArabicPDF extends FPDF {
    private $arabic_font_loaded = false;
    
    function __construct($orientation = 'P', $unit = 'mm', $size = 'A4') {
        parent::__construct($orientation, $unit, $size);
        $this->loadArabicFont();
    }
    
    /**
     * تحميل الخط العربي
     */
    private function loadArabicFont() {
        if (!$this->arabic_font_loaded) {
            // إضافة خط عربي (يجب وضع ملف الخط في مجلد fpdf/font)
            $this->AddFont('DejaVu', '', 'DejaVuSansCondensed.php');
            $this->AddFont('DejaVu', 'B', 'DejaVuSansCondensed-Bold.php');
            $this->arabic_font_loaded = true;
        }
    }
    
    /**
     * رأس الصفحة
     */
    function Header() {
        // شعار النظام
        $this->SetFont('DejaVu', 'B', 16);
        $this->SetTextColor(26, 75, 136);
        $this->Cell(0, 10, 'نظام إدارة فندق مارينا بلازا', 0, 1, 'C');
        $this->Ln(5);
        
        // خط فاصل
        $this->SetDrawColor(200, 200, 200);
        $this->Line(10, 25, 200, 25);
        $this->Ln(10);
    }
    
    /**
     * تذييل الصفحة
     */
    function Footer() {
        $this->SetY(-15);
        $this->SetFont('DejaVu', '', 8);
        $this->SetTextColor(128, 128, 128);
        
        // تاريخ الطباعة
        $this->Cell(0, 10, 'تاريخ الطباعة: ' . date('Y-m-d H:i:s'), 0, 0, 'L');
        
        // رقم الصفحة
        $this->Cell(0, 10, 'صفحة ' . $this->PageNo() . ' من {nb}', 0, 0, 'R');
    }
    
    /**
     * إضافة عنوان التقرير
     */
    function addReportTitle($title, $subtitle = '') {
        $this->SetFont('DejaVu', 'B', 14);
        $this->SetTextColor(26, 75, 136);
        $this->Cell(0, 10, $title, 0, 1, 'C');
        
        if ($subtitle) {
            $this->SetFont('DejaVu', '', 10);
            $this->SetTextColor(100, 100, 100);
            $this->Cell(0, 8, $subtitle, 0, 1, 'C');
        }
        
        $this->Ln(5);
    }
    
    /**
     * إضافة جدول
     */
    function addTable($headers, $data, $widths = null) {
        if (!$widths) {
            $widths = array_fill(0, count($headers), 190 / count($headers));
        }
        
        // رأس الجدول
        $this->SetFont('DejaVu', 'B', 10);
        $this->SetFillColor(26, 75, 136);
        $this->SetTextColor(255, 255, 255);
        $this->SetDrawColor(128, 128, 128);
        
        for ($i = 0; $i < count($headers); $i++) {
            $this->Cell($widths[$i], 8, $headers[$i], 1, 0, 'C', true);
        }
        $this->Ln();
        
        // بيانات الجدول
        $this->SetFont('DejaVu', '', 9);
        $this->SetTextColor(0, 0, 0);
        $fill = false;
        
        foreach ($data as $row) {
            $this->SetFillColor(245, 245, 245);
            for ($i = 0; $i < count($row); $i++) {
                $this->Cell($widths[$i], 7, $row[$i], 1, 0, 'C', $fill);
            }
            $this->Ln();
            $fill = !$fill;
        }
        
        $this->Ln(5);
    }
    
    /**
     * إضافة معلومات إحصائية
     */
    function addStatistics($stats) {
        $this->SetFont('DejaVu', 'B', 12);
        $this->SetTextColor(26, 75, 136);
        $this->Cell(0, 10, 'الإحصائيات', 0, 1, 'R');
        
        $this->SetFont('DejaVu', '', 10);
        $this->SetTextColor(0, 0, 0);
        
        foreach ($stats as $label => $value) {
            $this->Cell(95, 8, $label . ':', 0, 0, 'R');
            $this->Cell(95, 8, $value, 0, 1, 'L');
        }
        
        $this->Ln(5);
    }
    
    /**
     * إضافة ملاحظة
     */
    function addNote($note) {
        $this->SetFont('DejaVu', 'B', 10);
        $this->SetTextColor(220, 53, 69);
        $this->Cell(0, 8, 'ملاحظة:', 0, 1, 'R');
        
        $this->SetFont('DejaVu', '', 9);
        $this->SetTextColor(100, 100, 100);
        $this->MultiCell(0, 6, $note, 0, 'R');
        
        $this->Ln(5);
    }
    
    /**
     * إضافة قسم
     */
    function addSection($title, $content) {
        // عنوان القسم
        $this->SetFont('DejaVu', 'B', 12);
        $this->SetTextColor(26, 75, 136);
        $this->Cell(0, 10, $title, 0, 1, 'R');
        
        // خط تحت العنوان
        $this->SetDrawColor(26, 75, 136);
        $this->Line(10, $this->GetY(), 200, $this->GetY());
        $this->Ln(5);
        
        // محتوى القسم
        $this->SetFont('DejaVu', '', 10);
        $this->SetTextColor(0, 0, 0);
        $this->MultiCell(0, 6, $content, 0, 'R');
        
        $this->Ln(5);
    }
    
    /**
     * إضافة رسم بياني بسيط (نص)
     */
    function addSimpleChart($title, $data) {
        $this->SetFont('DejaVu', 'B', 11);
        $this->SetTextColor(26, 75, 136);
        $this->Cell(0, 10, $title, 0, 1, 'R');
        
        $this->SetFont('DejaVu', '', 9);
        $this->SetTextColor(0, 0, 0);
        
        $max_value = max(array_values($data));
        
        foreach ($data as $label => $value) {
            $percentage = $max_value > 0 ? ($value / $max_value) * 100 : 0;
            $bar_width = ($percentage / 100) * 150;
            
            // التسمية
            $this->Cell(40, 6, $label, 0, 0, 'R');
            
            // الشريط
            $this->SetFillColor(26, 75, 136);
            $this->Cell($bar_width, 6, '', 0, 0, 'L', true);
            
            // القيمة
            $this->Cell(0, 6, ' ' . $value, 0, 1, 'L');
        }
        
        $this->Ln(5);
    }
}

/**
 * فئة مولد تقارير النظام
 */
class SystemReportGenerator {
    private $conn;
    private $pdf;
    
    public function __construct($connection) {
        $this->conn = $connection;
    }
    
    /**
     * إنشاء تقرير الحجوزات
     */
    public function generateBookingsReport($start_date = null, $end_date = null) {
        $this->pdf = new ArabicPDF();
        $this->pdf->AliasNbPages();
        $this->pdf->AddPage();
        
        // عنوان التقرير
        $date_range = '';
        if ($start_date && $end_date) {
            $date_range = "من $start_date إلى $end_date";
        }
        
        $this->pdf->addReportTitle('تقرير الحجوزات', $date_range);
        
        // جلب بيانات الحجوزات
        $sql = "SELECT booking_id, guest_name, room_number, checkin_date, status 
                FROM bookings";
        
        if ($start_date && $end_date) {
            $sql .= " WHERE DATE(checkin_date) BETWEEN '$start_date' AND '$end_date'";
        }
        
        $sql .= " ORDER BY checkin_date DESC LIMIT 50";
        
        $result = $this->conn->query($sql);
        $bookings = [];
        
        while ($row = $result->fetch_assoc()) {
            $bookings[] = [
                $row['booking_id'],
                $row['guest_name'],
                $row['room_number'],
                date('Y-m-d', strtotime($row['checkin_date'])),
                $row['status']
            ];
        }
        
        // إضافة الجدول
        $headers = ['رقم الحجز', 'اسم النزيل', 'رقم الغرفة', 'تاريخ الوصول', 'الحالة'];
        $widths = [25, 50, 25, 35, 25];
        
        $this->pdf->addTable($headers, $bookings, $widths);
        
        // إحصائيات
        $stats_sql = "SELECT 
                        COUNT(*) as total_bookings,
                        COUNT(CASE WHEN status = 'محجوزة' THEN 1 END) as active_bookings,
                        COUNT(CASE WHEN status = 'شاغرة' THEN 1 END) as completed_bookings
                      FROM bookings";
        
        if ($start_date && $end_date) {
            $stats_sql .= " WHERE DATE(checkin_date) BETWEEN '$start_date' AND '$end_date'";
        }
        
        $stats_result = $this->conn->query($stats_sql);
        $stats = $stats_result->fetch_assoc();
        
        $this->pdf->addStatistics([
            'إجمالي الحجوزات' => $stats['total_bookings'],
            'الحجوزات النشطة' => $stats['active_bookings'],
            'الحجوزات المكتملة' => $stats['completed_bookings']
        ]);
        
        return $this->pdf;
    }
    
    /**
     * إنشاء تقرير الغرف
     */
    public function generateRoomsReport() {
        $this->pdf = new ArabicPDF();
        $this->pdf->AliasNbPages();
        $this->pdf->AddPage();
        
        $this->pdf->addReportTitle('تقرير حالة الغرف');
        
        // جلب بيانات الغرف
        $sql = "SELECT room_number, room_type, status, floor FROM rooms ORDER BY room_number";
        $result = $this->conn->query($sql);
        $rooms = [];
        
        while ($row = $result->fetch_assoc()) {
            $rooms[] = [
                $row['room_number'],
                $row['room_type'] ?? 'عادية',
                $row['status'],
                $row['floor'] ?? '1'
            ];
        }
        
        // إضافة الجدول
        $headers = ['رقم الغرفة', 'نوع الغرفة', 'الحالة', 'الطابق'];
        $widths = [30, 50, 30, 30];
        
        $this->pdf->addTable($headers, $rooms, $widths);
        
        // إحصائيات الغرف
        $stats_sql = "SELECT 
                        COUNT(*) as total_rooms,
                        COUNT(CASE WHEN status = 'شاغرة' THEN 1 END) as available_rooms,
                        COUNT(CASE WHEN status = 'محجوزة' THEN 1 END) as occupied_rooms
                      FROM rooms";
        
        $stats_result = $this->conn->query($stats_sql);
        $stats = $stats_result->fetch_assoc();
        
        $occupancy_rate = $stats['total_rooms'] > 0 ? 
            round(($stats['occupied_rooms'] / $stats['total_rooms']) * 100, 2) : 0;
        
        $this->pdf->addStatistics([
            'إجمالي الغرف' => $stats['total_rooms'],
            'الغرف المتاحة' => $stats['available_rooms'],
            'الغرف المشغولة' => $stats['occupied_rooms'],
            'معدل الإشغال' => $occupancy_rate . '%'
        ]);
        
        return $this->pdf;
    }
    
    /**
     * إنشاء تقرير مالي
     */
    public function generateFinancialReport($start_date = null, $end_date = null) {
        $this->pdf = new ArabicPDF();
        $this->pdf->AliasNbPages();
        $this->pdf->AddPage();
        
        $date_range = '';
        if ($start_date && $end_date) {
            $date_range = "من $start_date إلى $end_date";
        }
        
        $this->pdf->addReportTitle('التقرير المالي', $date_range);
        
        // محاولة جلب البيانات المالية
        $financial_data = [];
        
        // فحص وجود جدول المعاملات المالية
        $check_table = $this->conn->query("SHOW TABLES LIKE 'cash_transactions'");
        
        if ($check_table && $check_table->num_rows > 0) {
            $sql = "SELECT transaction_type, SUM(amount) as total 
                    FROM cash_transactions";
            
            if ($start_date && $end_date) {
                $sql .= " WHERE DATE(transaction_time) BETWEEN '$start_date' AND '$end_date'";
            }
            
            $sql .= " GROUP BY transaction_type";
            
            $result = $this->conn->query($sql);
            
            while ($row = $result->fetch_assoc()) {
                $financial_data[] = [
                    $row['transaction_type'] == 'income' ? 'الإيرادات' : 'المصروفات',
                    number_format($row['total'], 2) . ' ريال'
                ];
            }
        } else {
            $financial_data[] = ['لا توجد بيانات مالية', 'غير متوفر'];
        }
        
        if (!empty($financial_data)) {
            $headers = ['نوع المعاملة', 'المبلغ'];
            $widths = [95, 95];
            
            $this->pdf->addTable($headers, $financial_data, $widths);
        }
        
        $this->pdf->addNote('هذا التقرير يعتمد على البيانات المتوفرة في النظام. للحصول على تقرير مالي مفصل، يرجى التأكد من إدخال جميع المعاملات المالية.');
        
        return $this->pdf;
    }
    
    /**
     * إنشاء تقرير صحة النظام
     */
    public function generateSystemHealthReport() {
        $this->pdf = new ArabicPDF();
        $this->pdf->AliasNbPages();
        $this->pdf->AddPage();
        
        $this->pdf->addReportTitle('تقرير صحة النظام');
        
        // معلومات النظام
        $this->pdf->addSection('معلومات النظام', 
            "إصدار النظام: " . (defined('SYSTEM_VERSION') ? SYSTEM_VERSION : '2.0.0') . "\n" .
            "إصدار PHP: " . phpversion() . "\n" .
            "إصدار MySQL: " . $this->conn->server_info . "\n" .
            "تاريخ التقرير: " . date('Y-m-d H:i:s')
        );
        
        // فحص الجداول
        $tables_check = [];
        $required_tables = ['rooms', 'bookings', 'users'];
        
        foreach ($required_tables as $table) {
            $result = $this->conn->query("SHOW TABLES LIKE '$table'");
            $status = $result && $result->num_rows > 0 ? 'موجود' : 'غير موجود';
            $tables_check[] = [$table, $status];
        }
        
        $this->pdf->addTable(['الجدول', 'الحالة'], $tables_check, [95, 95]);
        
        // إحصائيات عامة
        $general_stats = [];
        
        // عدد الغرف
        $rooms_result = $this->conn->query("SELECT COUNT(*) as count FROM rooms");
        if ($rooms_result) {
            $rooms_count = $rooms_result->fetch_assoc()['count'];
            $general_stats['عدد الغرف'] = $rooms_count;
        }
        
        // عدد الحجوزات
        $bookings_result = $this->conn->query("SELECT COUNT(*) as count FROM bookings");
        if ($bookings_result) {
            $bookings_count = $bookings_result->fetch_assoc()['count'];
            $general_stats['عدد الحجوزات'] = $bookings_count;
        }
        
        if (!empty($general_stats)) {
            $this->pdf->addStatistics($general_stats);
        }
        
        return $this->pdf;
    }
    
    /**
     * حفظ PDF وإرجاع المسار
     */
    public function savePDF($filename) {
        $upload_dir = ROOT_PATH . '/uploads/reports/';
        
        if (!is_dir($upload_dir)) {
            mkdir($upload_dir, 0755, true);
        }
        
        $filepath = $upload_dir . $filename;
        $this->pdf->Output('F', $filepath);
        
        return $filepath;
    }
    
    /**
     * تحميل PDF مباشرة
     */
    public function downloadPDF($filename) {
        $this->pdf->Output('D', $filename);
    }
    
    /**
     * عرض PDF في المتصفح
     */
    public function displayPDF($filename) {
        $this->pdf->Output('I', $filename);
    }
}
?>
