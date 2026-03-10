<?php
// تضمين ملفات الاتصال بقاعدة البيانات والتوثيق
require_once '../../includes/db.php';
require_once '../../includes/auth_check.php';
require_once '../../includes/functions.php';

// تحديد التواريخ الافتراضية (الشهر الحالي)
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// جلب إحصائيات الإشغال العامة
$occupancy_query = "
    SELECT 
        COUNT(*) as total_bookings,
        SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings,
        SUM(CASE WHEN status = 'مكتملة' THEN 1 ELSE 0 END) as completed_bookings,
        SUM(CASE WHEN status = 'ملغية' THEN 1 ELSE 0 END) as cancelled_bookings
    FROM 
        bookings
    WHERE 
        checkin_date BETWEEN ? AND ? OR checkout_date BETWEEN ? AND ?
";

$stmt = $conn->prepare($occupancy_query);
$stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
$stmt->execute();
$occupancy_result = $stmt->get_result();
$occupancy_data = $occupancy_result->fetch_assoc();

// جلب إحصائيات الغرف
$rooms_query = "
    SELECT 
        COUNT(*) as total_rooms,
        SUM(CASE WHEN status = 'شاغرة' THEN 1 ELSE 0 END) as available_rooms,
        SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as occupied_rooms,
        SUM(CASE WHEN status = 'صيانة' THEN 1 ELSE 0 END) as maintenance_rooms
    FROM 
        rooms
";

$rooms_result = $conn->query($rooms_query);
$rooms_data = $rooms_result ? $rooms_result->fetch_assoc() : ['total_rooms' => 0, 'available_rooms' => 0, 'occupied_rooms' => 0, 'maintenance_rooms' => 0];

// حساب معدل الإشغال
$occupancy_rate = 0;
if ($rooms_data['total_rooms'] > 0) {
    $occupancy_rate = ($rooms_data['occupied_rooms'] / $rooms_data['total_rooms']) * 100;
}

// جلب تفاصيل الحجوزات خلال الفترة المحددة
$bookings_query = "
    SELECT 
        b.booking_id,
        b.room_number,
        b.checkin_date,
        b.checkout_date,
        b.status,
        COALESCE(b.guest_name, 'غير محدد') as guest_name,
        DATEDIFF(b.checkout_date, b.checkin_date) as nights,
        COALESCE(SUM(p.amount), 0) as total_paid
    FROM 
        bookings b
    LEFT JOIN 
        payment p ON b.booking_id = p.booking_id
    WHERE 
        b.checkin_date BETWEEN ? AND ? OR b.checkout_date BETWEEN ? AND ?
    GROUP BY 
        b.booking_id
    ORDER BY 
        b.checkin_date DESC
";

$stmt = $conn->prepare($bookings_query);
$stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
$stmt->execute();
$bookings_result = $stmt->get_result();

$bookings_data = [];
while ($row = $bookings_result->fetch_assoc()) {
    $bookings_data[] = $row;
}

// جلب أداء الغرف
$room_performance_query = "
    SELECT 
        r.room_number,
        r.type,
        COUNT(b.booking_id) as booking_count,
        SUM(DATEDIFF(b.checkout_date, b.checkin_date)) as total_nights,
        COALESCE(SUM(p.amount), 0) as room_revenue
    FROM 
        rooms r
    LEFT JOIN 
        bookings b ON r.room_number = b.room_number 
        AND (b.checkin_date BETWEEN ? AND ? OR b.checkout_date BETWEEN ? AND ?)
    LEFT JOIN 
        payment p ON b.booking_id = p.booking_id
    GROUP BY 
        r.room_number
    ORDER BY 
        room_revenue DESC
";

$stmt = $conn->prepare($room_performance_query);
$stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
$stmt->execute();
$room_performance_result = $stmt->get_result();

$room_performance_data = [];
while ($row = $room_performance_result->fetch_assoc()) {
    $room_performance_data[] = $row;
}

// تعيين عنوان الصفحة
$page_title = "تقرير الإشغال";
?>

<?php include_once '../../includes/header.php'; ?>

<div class="container-fluid mt-4 rtl">
    <div class="row">
        <div class="col-12">
            <div class="card shadow-sm">
                <div class="card-header bg-primary text-white">
                    <h1><i class="fas fa-chart-pie"></i> تقرير الإشغال والحجوزات</h1>
                    <p class="mb-0">إحصائيات شاملة عن الحجوزات ومعدلات الإشغال</p>
                </div>
                
                <div class="card-body">
                    <!-- فلاتر التاريخ -->
                    <div class="row mb-4">
                        <div class="col-12">
                            <div class="card">
                                <div class="card-header bg-info text-white">
                                    <h5><i class="fas fa-filter"></i> تصفية حسب الفترة</h5>
                                </div>
                                <div class="card-body">
                                    <form method="GET" class="row g-3">
                                        <div class="col-md-4">
                                            <label for="start_date" class="form-label">من تاريخ</label>
                                            <input type="date" class="form-control" id="start_date" name="start_date" value="<?php echo $start_date; ?>">
                                        </div>
                                        <div class="col-md-4">
                                            <label for="end_date" class="form-label">إلى تاريخ</label>
                                            <input type="date" class="form-control" id="end_date" name="end_date" value="<?php echo $end_date; ?>">
                                        </div>
                                        <div class="col-md-4 d-flex align-items-end">
                                            <button type="submit" class="btn btn-primary">
                                                <i class="fas fa-search"></i> تطبيق التصفية
                                            </button>
                                        </div>
                                    </form>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- بطاقات الإحصائيات -->
                    <div class="row mb-4">
                        <div class="col-md-3">
                            <div class="card bg-primary text-white">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo $occupancy_data['total_bookings']; ?></h4>
                                            <p>إجمالي الحجوزات</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-calendar-check fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-3">
                            <div class="card bg-success text-white">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo $occupancy_data['active_bookings']; ?></h4>
                                            <p>الحجوزات النشطة</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-bed fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-3">
                            <div class="card bg-info text-white">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo number_format($occupancy_rate, 1); ?>%</h4>
                                            <p>معدل الإشغال</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-chart-pie fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-3">
                            <div class="card bg-warning text-dark">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo $rooms_data['available_rooms']; ?></h4>
                                            <p>الغرف المتاحة</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-door-open fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- جداول التفاصيل -->
                    <div class="row">
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header bg-secondary text-white">
                                    <h5>إحصائيات الحجوزات</h5>
                                </div>
                                <div class="card-body">
                                    <table class="table table-striped">
                                        <tr>
                                            <td>إجمالي الحجوزات</td>
                                            <td><strong><?php echo $occupancy_data['total_bookings']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الحجوزات النشطة</td>
                                            <td><strong class="text-success"><?php echo $occupancy_data['active_bookings']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الحجوزات المكتملة</td>
                                            <td><strong class="text-info"><?php echo $occupancy_data['completed_bookings']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الحجوزات الملغية</td>
                                            <td><strong class="text-danger"><?php echo $occupancy_data['cancelled_bookings']; ?></strong></td>
                                        </tr>
                                    </table>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header bg-secondary text-white">
                                    <h5>إحصائيات الغرف</h5>
                                </div>
                                <div class="card-body">
                                    <table class="table table-striped">
                                        <tr>
                                            <td>إجمالي الغرف</td>
                                            <td><strong><?php echo $rooms_data['total_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الغرف المتاحة</td>
                                            <td><strong class="text-success"><?php echo $rooms_data['available_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الغرف المشغولة</td>
                                            <td><strong class="text-warning"><?php echo $rooms_data['occupied_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الغرف تحت الصيانة</td>
                                            <td><strong class="text-danger"><?php echo $rooms_data['maintenance_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>معدل الإشغال</td>
                                            <td><strong class="text-primary"><?php echo number_format($occupancy_rate, 2); ?>%</strong></td>
                                        </tr>
                                    </table>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- أزرار التصدير -->
                    <div class="row mt-4">
                        <div class="col-12">
                            <div class="card">
                                <div class="card-header bg-dark text-white">
                                    <h5>تصدير التقرير</h5>
                                </div>
                                <div class="card-body text-center">
                                    <a href="export_excel.php?report_type=occupancy&start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?>" 
                                       class="btn btn-success me-2">
                                        <i class="fas fa-file-excel"></i> تصدير Excel
                                    </a>
                                    <a href="export_pdf.php?report_type=occupancy&start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?>" 
                                       class="btn btn-danger me-2">
                                        <i class="fas fa-file-pdf"></i> تصدير PDF
                                    </a>
                                    <button onclick="window.print()" class="btn btn-primary">
                                        <i class="fas fa-print"></i> طباعة
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?
// تضمين ملفات الاتصال بقاعدة البيانات والتوثيق
require_once '../../includes/db.php';
require_once '../../includes/auth_check.php';
require_once '../../includes/functions.php';

// تحديد التواريخ الافتراضية (الشهر الحالي)
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// جلب إحصائيات الإشغال العامة
$occupancy_query = "
    SELECT 
        COUNT(*) as total_bookings,
        SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as active_bookings,
        SUM(CASE WHEN status = 'مكتملة' THEN 1 ELSE 0 END) as completed_bookings,
        SUM(CASE WHEN status = 'ملغية' THEN 1 ELSE 0 END) as cancelled_bookings
    FROM 
        bookings
    WHERE 
        checkin_date BETWEEN ? AND ? OR checkout_date BETWEEN ? AND ?
";

$stmt = $conn->prepare($occupancy_query);
$stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
$stmt->execute();
$occupancy_result = $stmt->get_result();
$occupancy_data = $occupancy_result->fetch_assoc();

// جلب إحصائيات الغرف
$rooms_query = "
    SELECT 
        COUNT(*) as total_rooms,
        SUM(CASE WHEN status = 'شاغرة' THEN 1 ELSE 0 END) as available_rooms,
        SUM(CASE WHEN status = 'محجوزة' THEN 1 ELSE 0 END) as occupied_rooms,
        SUM(CASE WHEN status = 'صيانة' THEN 1 ELSE 0 END) as maintenance_rooms
    FROM 
        rooms
";

$rooms_result = $conn->query($rooms_query);
$rooms_data = $rooms_result ? $rooms_result->fetch_assoc() : ['total_rooms' => 0, 'available_rooms' => 0, 'occupied_rooms' => 0, 'maintenance_rooms' => 0];

// حساب معدل الإشغال
$occupancy_rate = 0;
if ($rooms_data['total_rooms'] > 0) {
    $occupancy_rate = ($rooms_data['occupied_rooms'] / $rooms_data['total_rooms']) * 100;
}

// جلب تفاصيل الحجوزات خلال الفترة المحددة
$bookings_query = "
    SELECT 
        b.booking_id,
        b.room_number,
        b.checkin_date,
        b.checkout_date,
        b.status,
        COALESCE(b.guest_name, 'غير محدد') as guest_name,
        DATEDIFF(b.checkout_date, b.checkin_date) as nights,
        COALESCE(SUM(p.amount), 0) as total_paid
    FROM 
        bookings b
    LEFT JOIN 
        payment p ON b.booking_id = p.booking_id
    WHERE 
        b.checkin_date BETWEEN ? AND ? OR b.checkout_date BETWEEN ? AND ?
    GROUP BY 
        b.booking_id
    ORDER BY 
        b.checkin_date DESC
";

$stmt = $conn->prepare($bookings_query);
$stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
$stmt->execute();
$bookings_result = $stmt->get_result();

$bookings_data = [];
while ($row = $bookings_result->fetch_assoc()) {
    $bookings_data[] = $row;
}

// جلب أداء الغرف
$room_performance_query = "
    SELECT 
        r.room_number,
        r.type,
        COUNT(b.booking_id) as booking_count,
        SUM(DATEDIFF(b.checkout_date, b.checkin_date)) as total_nights,
        COALESCE(SUM(p.amount), 0) as room_revenue
    FROM 
        rooms r
    LEFT JOIN 
        bookings b ON r.room_number = b.room_number 
        AND (b.checkin_date BETWEEN ? AND ? OR b.checkout_date BETWEEN ? AND ?)
    LEFT JOIN 
        payment p ON b.booking_id = p.booking_id
    GROUP BY 
        r.room_number
    ORDER BY 
        room_revenue DESC
";

$stmt = $conn->prepare($room_performance_query);
$stmt->bind_param("ssss", $start_date, $end_date, $start_date, $end_date);
$stmt->execute();
$room_performance_result = $stmt->get_result();

$room_performance_data = [];
while ($row = $room_performance_result->fetch_assoc()) {
    $room_performance_data[] = $row;
}

// تعيين عنوان الصفحة
$page_title = "تقرير الإشغال";
?>

<?php include_once '../../includes/header.php'; ?>

<div class="container-fluid mt-4 rtl">
    <div class="row">
        <div class="col-12">
            <div class="card shadow-sm">
                <div class="card-header bg-primary text-white">
                    <h1><i class="fas fa-chart-pie"></i> تقرير الإشغال والحجوزات</h1>
                    <p class="mb-0">إحصائيات شاملة عن الحجوزات ومعدلات الإشغال</p>
                </div>
                
                <div class="card-body">
                    <!-- فلاتر التاريخ -->
                    <div class="row mb-4">
                        <div class="col-12">
                            <div class="card">
                                <div class="card-header bg-info text-white">
                                    <h5><i class="fas fa-filter"></i> تصفية حسب الفترة</h5>
                                </div>
                                <div class="card-body">
                                    <form method="GET" class="row g-3">
                                        <div class="col-md-4">
                                            <label for="start_date" class="form-label">من تاريخ</label>
                                            <input type="date" class="form-control" id="start_date" name="start_date" value="<?php echo $start_date; ?>">
                                        </div>
                                        <div class="col-md-4">
                                            <label for="end_date" class="form-label">إلى تاريخ</label>
                                            <input type="date" class="form-control" id="end_date" name="end_date" value="<?php echo $end_date; ?>">
                                        </div>
                                        <div class="col-md-4 d-flex align-items-end">
                                            <button type="submit" class="btn btn-primary">
                                                <i class="fas fa-search"></i> تطبيق التصفية
                                            </button>
                                        </div>
                                    </form>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- بطاقات الإحصائيات -->
                    <div class="row mb-4">
                        <div class="col-md-3">
                            <div class="card bg-primary text-white">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo $occupancy_data['total_bookings']; ?></h4>
                                            <p>إجمالي الحجوزات</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-calendar-check fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-3">
                            <div class="card bg-success text-white">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo $occupancy_data['active_bookings']; ?></h4>
                                            <p>الحجوزات النشطة</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-bed fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-3">
                            <div class="card bg-info text-white">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo number_format($occupancy_rate, 1); ?>%</h4>
                                            <p>معدل الإشغال</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-chart-pie fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-3">
                            <div class="card bg-warning text-dark">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo $rooms_data['available_rooms']; ?></h4>
                                            <p>الغرف المتاحة</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-door-open fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- جداول التفاصيل -->
                    <div class="row">
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header bg-secondary text-white">
                                    <h5>إحصائيات الحجوزات</h5>
                                </div>
                                <div class="card-body">
                                    <table class="table table-striped">
                                        <tr>
                                            <td>إجمالي الحجوزات</td>
                                            <td><strong><?php echo $occupancy_data['total_bookings']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الحجوزات النشطة</td>
                                            <td><strong class="text-success"><?php echo $occupancy_data['active_bookings']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الحجوزات المكتملة</td>
                                            <td><strong class="text-info"><?php echo $occupancy_data['completed_bookings']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الحجوزات الملغية</td>
                                            <td><strong class="text-danger"><?php echo $occupancy_data['cancelled_bookings']; ?></strong></td>
                                        </tr>
                                    </table>
                                </div>
                            </div>
                        </div>
                        
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header bg-secondary text-white">
                                    <h5>إحصائيات الغرف</h5>
                                </div>
                                <div class="card-body">
                                    <table class="table table-striped">
                                        <tr>
                                            <td>إجمالي الغرف</td>
                                            <td><strong><?php echo $rooms_data['total_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الغرف المتاحة</td>
                                            <td><strong class="text-success"><?php echo $rooms_data['available_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الغرف المشغولة</td>
                                            <td><strong class="text-warning"><?php echo $rooms_data['occupied_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>الغرف تحت الصيانة</td>
                                            <td><strong class="text-danger"><?php echo $rooms_data['maintenance_rooms']; ?></strong></td>
                                        </tr>
                                        <tr>
                                            <td>معدل الإشغال</td>
                                            <td><strong class="text-primary"><?php echo number_format($occupancy_rate, 2); ?>%</strong></td>
                                        </tr>
                                    </table>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- أزرار التصدير -->
                    <div class="row mt-4">
                        <div class="col-12">
                            <div class="card">
                                <div class="card-header bg-dark text-white">
                                    <h5>تصدير التقرير</h5>
                                </div>
                                <div class="card-body text-center">
                                    <a href="export_excel.php?report_type=occupancy&start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?>" 
                                       class="btn btn-success me-2">
                                        <i class="fas fa-file-excel"></i> تصدير Excel
                                    </a>
                                    <a href="export_pdf.php?report_type=occupancy&start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?>" 
                                       class="btn btn-danger me-2">
                                        <i class="fas fa-file-pdf"></i> تصدير PDF
                                    </a>
                                    <button onclick="window.print()" class="btn btn-primary">
                                        <i class="fas fa-print"></i> طباعة
                                    </button>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
