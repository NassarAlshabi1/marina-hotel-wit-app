<?php
include_once '../../includes/db.php';
require_once('../../includes/fpdf/fpdf.php'); // مكتبة طباعة PDF

if (!isset($_GET['id']) || !is_numeric($_GET['id'])) {
    die("معرف الدفعة غير صالح");
}

$payment_id = intval($_GET['id']);

// استعلام لبيانات الدفعة
$query = "
    SELECT 
        p.*,
        b.guest_name,
        b.room_number,
        b.guest_id_number,
        r.price
    FROM 
        payment p
    JOIN 
        bookings b ON p.booking_id = b.booking_id
    JOIN 
        rooms r ON b.room_number = r.room_number
    WHERE 
        p.payment_id = $payment_id
";

$result = $conn->query($query);

if (!$result || $result->num_rows == 0) {
    die("الدفعة غير موجودة");
}

$payment = $result->fetch_assoc();

// إنشاء ملف PDF
$pdf = new FPDF('P', 'mm', 'A5');
$pdf->AddPage();
$pdf->SetRightMargin(10);

// تنسيق الخط العربي (يجب تثبيت الخط مسبقاً)
$pdf->AddFont('aealarabiya','','aealarabiya.php');
$pdf->SetFont('aealarabiya','',14);

// رأس الإيصال
$pdf->SetFillColor(0, 102, 204);
$pdf->SetTextColor(255);
$pdf->Cell(0, 10, iconv('UTF-8', 'ISO-8859-6', 'فندق مارينا بلازا'), 0, 1, 'C', true);
$pdf->SetFont('aealarabiya','',10);
$pdf->Cell(0, 6, iconv('UTF-8', 'ISO-8859-6', 'العنوان: عدن - القاهرة، شارع أحمد قاسم'), 0, 1, 'C', true);
$pdf->Cell(0, 6, iconv('UTF-8', 'ISO-8859-6', 'هاتف: 02324457'), 0, 1, 'C', true);

// تفاصيل الحجز
$pdf->SetFillColor(255);
$pdf->SetTextColor(0);
$pdf->SetFont('aealarabiya','',12);
$pdf->Ln(5);
$pdf->Cell(0, 8, iconv('UTF-8', 'ISO-8859-6', '============== إيصال دفع =============='), 0, 1, 'C');

// تاريخ الطباعة
$pdf->SetFont('aealarabiya','',10);
$pdf->Cell(0, 6, iconv('UTF-8', 'ISO-8859-6', 'تاريخ الطباعة: ' . date('d/m/Y H:i')), 0, 1, 'L');

// جدول البيانات
$pdf->SetFont('aealarabiya','',12);
$pdf->Cell(40, 8, iconv('UTF-8', 'ISO-8859-6', 'رقم الإيصال:'), 0, 0, 'R');
$pdf->Cell(0, 8, $payment['payment_id'], 0, 1);

$pdf->Cell(40, 8, iconv('UTF-8', 'ISO-8859-6', 'اسم النزيل:'), 0, 0, 'R');
$pdf->Cell(0, 8, iconv('UTF-8', 'ISO-8859-6', $payment['guest_name']), 0, 1);

$pdf->Cell(40, 8, iconv('UTF-8', 'ISO-8859-6', 'رقم الغرفة:'), 0, 0, 'R');
$pdf->Cell(0, 8, $payment['room_number'], 0, 1);

$pdf->Cell(40, 8, iconv('UTF-8', 'ISO-8859-6', 'تاريخ الدفع:'), 0, 0, 'R');
$pdf->Cell(0, 8, date('d/m/Y H:i', strtotime($payment['payment_date'])), 0, 1);

$pdf->Cell(40, 8, iconv('UTF-8', 'ISO-8859-6', 'المبلغ:'), 0, 0, 'R');
$pdf->SetFont('aealarabiya','B',12);
$pdf->Cell(0, 8, number_format($payment['amount']) . ' ر.س', 0, 1);

// الملاحظات
$pdf->SetFont('aealarabiya','',10);
$pdf->Ln(3);
$pdf->MultiCell(0, 6, iconv('UTF-8', 'ISO-8859-6', 'ملاحظات: ' . ($payment['notes'] ?? 'لا يوجد')), 0, 'R');

// تذييل الإيصال
$pdf->SetY(-30);
$pdf->SetFont('aealarabiya','',10);
$pdf->Cell(0, 6, iconv('UTF-8', 'ISO-8859-6', '=========================================='), 0, 1, 'C');
$pdf->Cell(0, 6, iconv('UTF-8', 'ISO-8859-6', 'شكراً لاختياركم فندق مارينا بلازا'), 0, 1, 'C');
$pdf->Cell(0, 6, iconv('UTF-8', 'ISO-8859-6', 'نتمنى لكم إقامة ممتعة'), 0, 1, 'C');

// إخراج الملف
$pdf->Output('I', 'receipt_' . $payment['payment_id'] . '.pdf');
?>

<!-- يمكنك استبدال هذا الكود بملف receipt.php الموجود لديك -->
