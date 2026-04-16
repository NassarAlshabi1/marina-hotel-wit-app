<?php
// تضمين ملفات الاتصال بقاعدة البيانات والتوثيق
require_once '../../includes/db.php';

require_once '../../includes/functions.php';

// التحقق من المعلمات المطلوبة
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');
$report_type = isset($_GET['report_type']) ? $_GET['report_type'] : 'all';

// تحديد اسم الملف
$filename = "comprehensive_report_{$start_date}_to_{$end_date}.csv";

// إعداد رأس الملف
header('Content-Type: text/csv; charset=utf-8');
header('Content-Disposition: attachment; filename="' . $filename . '"');

// فتح مخرج PHP كملف CSV
$output = fopen('php://output', 'w');

// إضافة BOM لدعم Unicode (UTF-8)
fprintf($output, chr(0xEF).chr(0xBB).chr(0xBF));

// تحديد أي تقرير سيتم تصديره
switch ($report_type) {
    case 'revenue':
        exportRevenueReport($conn, $output, $start_date, $end_date);
        break;
    case 'expenses':
        exportExpensesReport($conn, $output, $start_date, $end_date);
        break;
    case 'occupancy':
        exportOccupancyReport($conn, $output, $start_date, $end_date);
        break;
    case 'rooms':
        exportRoomsReport($conn, $output, $start_date, $end_date);
        break;
    case 'withdrawals':
        exportWithdrawalsReport($conn, $output, $start_date, $end_date);
        break;
    case 'all':
    default:
        exportComprehensiveReport($conn, $output, $start_date, $end_date);
        break;
}

// إغلاق الملف
fclose($output);
exit;

// دالة لتصدير تقرير الإيرادات
function exportRevenueReport($conn, $output, $start_date, $end_date) {
    // كتابة عنوان التقرير
    fputcsv($output, ['تقرير الإيرادات', "من {$start_date} إلى {$end_date}"]);
    fputcsv($output, []); // سطر فارغ
    
    // كتابة رؤوس الأعمدة
    fputcsv($output, ['التاريخ', 'المبلغ (ريال)']);
    
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
    
    // كتابة بيانات الإيرادات
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [$row['date'], $row['total_revenue']]);
        $total_revenue += $row['total_revenue'];
    }
    
    // كتابة الإجمالي
    fputcsv($output, []); // سطر فارغ
    fputcsv($output, ['الإجمالي', $total_revenue]);
}

// دالة لتصدير تقرير المصروفات
function exportExpensesReport($conn, $output, $start_date, $end_date) {
    // كتابة عنوان التقرير
    fputcsv($output, ['تقرير المصروفات', "من {$start_date} إلى {$end_date}"]);
    fputcsv($output, []); // سطر فارغ
    
    // كتابة رؤوس الأعمدة
    fputcsv($output, ['التاريخ', 'الفئة', 'الوصف', 'المبلغ (ريال)']);
    
    // استعلام المصروفات
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
    
    $total_expenses = 0;
    
    // كتابة بيانات المصروفات
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [$row['date'], $row['expense_category'], $row['description'], $row['amount']]);
        $total_expenses += $row['amount'];
    }
    
    // كتابة الإجمالي
    fputcsv($output, []); // سطر فارغ
    fputcsv($output, ['الإجمالي', '', '', $total_expenses]);
    
    // كتابة ملخص حسب الفئة
    fputcsv($output, []); // سطر فارغ
    fputcsv($output, ['ملخص المصروفات حسب الفئة']);
    fputcsv($output, ['الفئة', 'المبلغ (ريال)']);
    
    // استعلام ملخص المصروفات حسب الفئة
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
    
    // كتابة بيانات ملخص المصروفات
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [$row['expense_category'], $row['total_expense']]);
    }
}

// دالة لتصدير تقرير الإشغال
function exportOccupancyReport($conn, $output, $start_date, $end_date) {
    // كتابة عنوان التقرير
    fputcsv($output, ['تقرير الإشغال', "من {$start_date} إلى {$end_date}"]);
    fputcsv($output, []); // سطر فارغ
    
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
    
    // كتابة إحصائيات الإشغال
    fputcsv($output, ['إجمالي الحجوزات', $occupancy_data['total_bookings']]);
    fputcsv($output, ['الحجوزات النشطة', $occupancy_data['active_bookings']]);
    fputcsv($output, ['الحجوزات المكتملة', $occupancy_data['completed_bookings']]);
    
    // حساب معدل الإشغال
    $occupancy_rate = 0;
    if ($occupancy_data['total_bookings'] > 0) {
        $occupancy_rate = ($occupancy_data['active_bookings'] / $occupancy_data['total_bookings']) * 100;
    }
    fputcsv($output, ['معدل الإشغال', number_format($occupancy_rate, 2) . '%']);
    
    fputcsv($output, []); // سطر فارغ
    
    // كتابة تفاصيل الحجوزات
    fputcsv($output, ['تفاصيل الحجوزات']);
    fputcsv($output, ['رقم الحجز', 'اسم الضيف', 'رقم الغرفة', 'تاريخ الوصول', 'تاريخ المغادرة', 'الحالة', 'المبلغ (ريال)']);
    
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
    
    // كتابة بيانات الحجوزات
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [
            $row['id'],
            $row['guest_name'],
            $row['room_number'],
            $row['check_in'],
            $row['check_out'],
            $row['status'],
            $row['total_paid']
        ]);
    }
}

// دالة لتصدير تقرير الغرف
function exportRoomsReport($conn, $output, $start_date, $end_date) {
    // كتابة عنوان التقرير
    fputcsv($output, ['تقرير أداء الغرف', "من {$start_date} إلى {$end_date}"]);
    fputcsv($output, []); // سطر فارغ
    
    // كتابة رؤوس الأعمدة
    fputcsv($output, ['رقم الغرفة', 'نوع الغرفة', 'عدد الحجوزات', 'الإيرادات (ريال)', 'معدل الإشغال (%)']);
    
    // استعلام أداء الغرف
    $query = "
        SELECT 
            r.room_number,
            r.room_type,
            COUNT(b.id) as booking_count,
            COALESCE(SUM(p.amount), 0) as room_revenue,
            COUNT(DISTINCT DATE(b.check_in)) as days_occupied
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
    
    // حساب عدد الأيام في نطاق التاريخ
    $date_range_days = (strtotime($end_date) - strtotime($start_date)) / (60 * 60 * 24) + 1;
    
    // كتابة بيانات الغرف
    while ($row = $result->fetch_assoc()) {
        // حساب معدل الإشغال
        $occupancy_rate = ($row['days_occupied'] / $date_range_days) * 100;
        
        fputcsv($output, [
            $row['room_number'],
            $row['room_type'],
            $row['booking_count'],
            $row['room_revenue'],
            number_format($occupancy_rate, 2) . '%'
        ]);
    }
}

// دالة لتصدير تقرير سحوبات الموظفين
function exportWithdrawalsReport($conn, $output, $start_date, $end_date) {
    // كتابة عنوان التقرير
    fputcsv($output, ['تقرير سحوبات الموظفين', "من {$start_date} إلى {$end_date}"]);
    fputcsv($output, []); // سطر فارغ
    
    // كتابة رؤوس الأعمدة
    fputcsv($output, ['الموظف', 'تاريخ السحب', 'المبلغ (ريال)', 'الملاحظات']);
    
    // استعلام سحوبات الموظفين
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
    
    $total_withdrawals = 0;
    
    // كتابة بيانات السحوبات
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [
            $row['employee_name'],
            $row['withdrawal_date'],
            $row['amount'],
            $row['notes']
        ]);
        $total_withdrawals += $row['amount'];
    }
    
    // كتابة الإجمالي
    fputcsv($output, []); // سطر فارغ
    fputcsv($output, ['الإجمالي', '', $total_withdrawals, '']);
    
    // كتابة ملخص حسب الموظف
    fputcsv($output, []); // سطر فارغ
    fputcsv($output, ['ملخص السحوبات حسب الموظف']);
    fputcsv($output, ['الموظف', 'إجمالي السحوبات (ريال)']);
    
    // استعلام ملخص السحوبات حسب الموظف
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
    
    // كتابة بيانات ملخص السحوبات
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [$row['employee_name'], $row['total_withdrawals']]);
    }
}

// دالة لتصدير التقرير الشامل
function exportComprehensiveReport($conn, $output, $start_date, $end_date) {
    // كتابة عنوان التقرير
    fputcsv($output, ['التقرير الشامل', "من {$start_date} إلى {$end_date}"]);
    fputcsv($output, []); // سطر فارغ
    
    // استعلام ملخص الإيرادات
    $query = "SELECT SUM(amount) as total_revenue FROM payment WHERE DATE(payment_date) BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_revenue = $result->fetch_assoc()['total_revenue'] ?? 0;
    
    // استعلام ملخص المصروفات
    $query = "SELECT SUM(amount) as total_expenses FROM expenses WHERE DATE(date) BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_expenses = $result->fetch_assoc()['total_expenses'] ?? 0;
    
    // استعلام ملخص سحوبات الموظفين
    $query = "SELECT SUM(amount) as total_withdrawals FROM salary_withdrawals WHERE DATE(date) BETWEEN ? AND ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    $total_withdrawals = $result->fetch_assoc()['total_withdrawals'] ?? 0;
    
    // حساب صافي الربح
    $net_profit = $total_revenue - $total_expenses;
    
    // كتابة ملخص التقرير
    fputcsv($output, ['ملخص التقرير']);
    fputcsv($output, ['إجمالي الإيرادات', $total_revenue . ' ريال']);
    fputcsv($output, ['إجمالي المصروفات', $total_expenses . ' ريال']);
    fputcsv($output, ['صافي الربح', $net_profit . ' ريال']);
    fputcsv($output, ['إجمالي سحوبات الموظفين', $total_withdrawals . ' ريال']);
    fputcsv($output, []); // سطر فارغ
    
    // تصدير تقرير الإيرادات
    fputcsv($output, ['تقرير الإيرادات']);
    fputcsv($output, ['التاريخ', 'المبلغ (ريال)']);
    
    $query = "
        SELECT 
            DATE(payment_date) as date,
            SUM(amount) as total_revenue
        FROM 
            payments
        WHERE 
            payment_date BETWEEN ? AND ?
        GROUP BY 
            DATE(payment_date)
        ORDER BY 
            date ASC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [$row['date'], $row['total_revenue']]);
    }
    
    fputcsv($output, []); // سطر فارغ
    
    // تصدير تقرير المصروفات حسب الفئة
    fputcsv($output, ['تقرير المصروفات حسب الفئة']);
    fputcsv($output, ['الفئة', 'المبلغ (ريال)']);
    
    $query = "
        SELECT 
            expense_category,
            SUM(amount) as total_expense
        FROM 
            expenses
        WHERE 
            expense_date BETWEEN ? AND ?
        GROUP BY 
            expense_category
        ORDER BY 
            total_expense DESC
    ";
    
    $stmt = $conn->prepare($query);
    $stmt->bind_param("ss", $start_date, $end_date);
    $stmt->execute();
    $result = $stmt->get_result();
    
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [$row['expense_category'], $row['total_expense']]);
    }
    
    fputcsv($output, []); // سطر فارغ
    
    // تصدير تقرير أداء الغرف
    fputcsv($output, ['تقرير أداء الغرف']);
    fputcsv($output, ['رقم الغرفة', 'نوع الغرفة', 'عدد الحجوزات', 'الإيرادات (ريال)']);
    
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
    
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [
            $row['room_number'],
            $row['room_type'],
            $row['booking_count'],
            $row['room_revenue']
        ]);
    }
    
    fputcsv($output, []); // سطر فارغ
    
    // تصدير تقرير سحوبات الموظفين
    fputcsv($output, ['تقرير سحوبات الموظفين']);
    fputcsv($output, ['الموظف', 'إجمالي السحوبات (ريال)']);
    
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
    
    while ($row = $result->fetch_assoc()) {
        fputcsv($output, [$row['employee_name'], $row['total_withdrawals']]);
    }
}
