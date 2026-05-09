<?php
/**
 * صفحة التقارير مع إمكانية التصدير إلى PDF
 */

require_once '../../includes/config.php';
require_once '../../includes/db.php';
require_once '../../includes/auth.php';
require_once '../../includes/pdf_generator.php';

// التحقق من الصلاحيات
if (!isset($_SESSION['user_type']) || $_SESSION['user_type'] !== 'admin') {
    header("Location: ../login.php?error=ليس لديك صلاحية للوصول إلى هذه الصفحة");
    exit();
}

$message = '';
$error = '';

// معالجة تصدير التقارير
if (isset($_GET['export']) && isset($_GET['type'])) {
    try {
        $report_generator = new SystemReportGenerator($conn);
        $export_type = $_GET['export'];
        $report_type = $_GET['type'];
        
        $start_date = $_GET['start_date'] ?? null;
        $end_date = $_GET['end_date'] ?? null;
        
        switch ($report_type) {
            case 'bookings':
                $pdf = $report_generator->generateBookingsReport($start_date, $end_date);
                $filename = 'bookings_report_' . date('Y-m-d_H-i-s') . '.pdf';
                break;
                
            case 'rooms':
                $pdf = $report_generator->generateRoomsReport();
                $filename = 'rooms_report_' . date('Y-m-d_H-i-s') . '.pdf';
                break;
                
            case 'financial':
                $pdf = $report_generator->generateFinancialReport($start_date, $end_date);
                $filename = 'financial_report_' . date('Y-m-d_H-i-s') . '.pdf';
                break;
                
            case 'system':
                $pdf = $report_generator->generateSystemHealthReport();
                $filename = 'system_health_report_' . date('Y-m-d_H-i-s') . '.pdf';
                break;
                
            default:
                throw new Exception('نوع التقرير غير صحيح');
        }
        
        if ($export_type === 'download') {
            $report_generator->downloadPDF($filename);
        } elseif ($export_type === 'view') {
            $report_generator->displayPDF($filename);
        }
        
        exit;
        
    } catch (Exception $e) {
        $error = "فشل في إنشاء التقرير: " . $e->getMessage();
    }
}

// جلب إحصائيات سريعة للتقارير
try {
    // إحصائيات الحجوزات
    $bookings_stats = $conn->query("
        SELECT 
            COUNT(*) as total,
            COUNT(CASE WHEN status = 'محجوزة' THEN 1 END) as active,
            COUNT(CASE WHEN DATE(checkin_date) = CURDATE() THEN 1 END) as today
        FROM bookings
    ");
    $bookings_data = $bookings_stats ? $bookings_stats->fetch_assoc() : ['total' => 0, 'active' => 0, 'today' => 0];
    
    // إحصائيات الغرف
    $rooms_stats = $conn->query("
        SELECT 
            COUNT(*) as total,
            COUNT(CASE WHEN status = 'شاغرة' THEN 1 END) as available,
            COUNT(CASE WHEN status = 'محجوزة' THEN 1 END) as occupied
        FROM rooms
    ");
    $rooms_data = $rooms_stats ? $rooms_stats->fetch_assoc() : ['total' => 0, 'available' => 0, 'occupied' => 0];
    
} catch (Exception $e) {
    $bookings_data = ['total' => 0, 'active' => 0, 'today' => 0];
    $rooms_data = ['total' => 0, 'available' => 0, 'occupied' => 0];
}

include_once '../../includes/header.php';
?>

<div class="container-fluid">
    <div class="row">
        <div class="col-12">
            <div class="card">
                <div class="card-header">
                    <h1><i class="fas fa-chart-bar"></i> التقارير والإحصائيات</h1>
                    <p>إنشاء وتصدير التقارير المختلفة للنظام</p>
                </div>
                
                <div class="card-body">
                    <?php if ($message): ?>
                        <div class="alert alert-success">
                            <i class="fas fa-check-circle"></i> <?php echo htmlspecialchars($message); ?>
                        </div>
                    <?php endif; ?>
                    
                    <?php if ($error): ?>
                        <div class="alert alert-danger">
                            <i class="fas fa-exclamation-circle"></i> <?php echo htmlspecialchars($error); ?>
                        </div>
                    <?php endif; ?>
                    
                    <!-- إحصائيات سريعة -->
                    <div class="row mb-4">
                        <div class="col-md-3">
                            <div class="card bg-primary text-white">
                                <div class="card-body">
                                    <div class="d-flex justify-content-between">
                                        <div>
                                            <h4><?php echo $bookings_data['total']; ?></h4>
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
                                            <h4><?php echo $bookings_data['active']; ?></h4>
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
                                            <h4><?php echo $rooms_data['available']; ?></h4>
                                            <p>الغرف المتاحة</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-door-open fa-2x"></i>
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
                                            <h4><?php echo $rooms_data['occupied']; ?></h4>
                                            <p>الغرف المشغولة</p>
                                        </div>
                                        <div>
                                            <i class="fas fa-door-closed fa-2x"></i>
                                        </div>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- تقارير الحجوزات -->
                    <div class="row">
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header">
                                    <h3><i class="fas fa-calendar-alt"></i> تقرير الحجوزات</h3>
                                </div>
                                <div class="card-body">
                                    <p>تقرير شامل عن جميع الحجوزات مع إمكانية التصفية حسب التاريخ</p>
                                    
                                    <form class="mb-3" id="bookingsReportForm">
                                        <div class="row">
                                            <div class="col-md-6">
                                                <label>من تاريخ:</label>
                                                <input type="date" class="form-control" name="start_date" id="bookings_start_date">
                                            </div>
                                            <div class="col-md-6">
                                                <label>إلى تاريخ:</label>
                                                <input type="date" class="form-control" name="end_date" id="bookings_end_date">
                                            </div>
                                        </div>
                                    </form>
                                    
                                    <div class="btn-group" role="group">
                                        <button onclick="exportReport('bookings', 'view')" class="btn btn-primary">
                                            <i class="fas fa-eye"></i> عرض
                                        </button>
                                        <button onclick="exportReport('bookings', 'download')" class="btn btn-success">
                                            <i class="fas fa-download"></i> تحميل PDF
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- تقرير الغرف -->
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header">
                                    <h3><i class="fas fa-bed"></i> تقرير الغرف</h3>
                                </div>
                                <div class="card-body">
                                    <p>تقرير عن حالة جميع الغرف ومعدلات الإشغال</p>
                                    
                                    <div class="btn-group" role="group">
                                        <button onclick="exportReport('rooms', 'view')" class="btn btn-primary">
                                            <i class="fas fa-eye"></i> عرض
                                        </button>
                                        <button onclick="exportReport('rooms', 'download')" class="btn btn-success">
                                            <i class="fas fa-download"></i> تحميل PDF
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="row mt-4">
                        <!-- التقرير المالي -->
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header">
                                    <h3><i class="fas fa-chart-line"></i> التقرير المالي</h3>
                                </div>
                                <div class="card-body">
                                    <p>تقرير عن الإيرادات والمصروفات والأرباح</p>
                                    
                                    <form class="mb-3" id="financialReportForm">
                                        <div class="row">
                                            <div class="col-md-6">
                                                <label>من تاريخ:</label>
                                                <input type="date" class="form-control" name="start_date" id="financial_start_date">
                                            </div>
                                            <div class="col-md-6">
                                                <label>إلى تاريخ:</label>
                                                <input type="date" class="form-control" name="end_date" id="financial_end_date">
                                            </div>
                                        </div>
                                    </form>
                                    
                                    <div class="btn-group" role="group">
                                        <button onclick="exportReport('financial', 'view')" class="btn btn-primary">
                                            <i class="fas fa-eye"></i> عرض
                                        </button>
                                        <button onclick="exportReport('financial', 'download')" class="btn btn-success">
                                            <i class="fas fa-download"></i> تحميل PDF
                                        </button>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <!-- تقرير صحة النظام -->
                        <div class="col-md-6">
                            <div class="card">
                                <div class="card-header">
                                    <h3><i class="fas fa-heartbeat"></i> تقرير صحة النظام</h3>
                                </div>
                                <div class="card-body">
                                    <p>تقرير شامل عن حالة النظام والأداء والأمان</p>
                                    
                                    <div class="btn-group" role="group">
                                        <button onclick="exportReport('system', 'view')" class="btn btn-primary">
                                            <i class="fas fa-eye"></i> عرض
                                        </button>
                                        <button onclick="exportReport('system', 'download')" class="btn btn-success">
                                            <i class="fas fa-download"></i> تحميل PDF
                                        </button>
                                        <a href="../system_health_report.php" class="btn btn-info">
                                            <i class="fas fa-external-link-alt"></i> عرض تفاعلي
                                        </a>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <!-- تقارير مخصصة -->
                    <div class="row mt-4">
                        <div class="col-12">
                            <div class="card">
                                <div class="card-header">
                                    <h3><i class="fas fa-cogs"></i> تقارير مخصصة</h3>
                                </div>
                                <div class="card-body">
                                    <p>إنشاء تقارير مخصصة حسب احتياجاتك</p>
                                    
                                    <div class="alert alert-info">
                                        <i class="fas fa-info-circle"></i>
                                        <strong>قريباً:</strong> ستتمكن من إنشاء تقارير مخصصة باستخدام أدوات التصفية المتقدمة.
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <div class="card-footer">
                    <a href="dash.php" class="btn btn-secondary">
                        <i class="fas fa-arrow-right"></i> العودة للوحة التحكم
                    </a>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
function exportReport(type, action) {
    let url = `?export=${action}&type=${type}`;
    
    // إضافة التواريخ إذا كانت متوفرة
    if (type === 'bookings') {
        const startDate = document.getElementById('bookings_start_date').value;
        const endDate = document.getElementById('bookings_end_date').value;
        
        if (startDate) url += `&start_date=${startDate}`;
        if (endDate) url += `&end_date=${endDate}`;
    } else if (type === 'financial') {
        const startDate = document.getElementById('financial_start_date').value;
        const endDate = document.getElementById('financial_end_date').value;
        
        if (startDate) url += `&start_date=${startDate}`;
        if (endDate) url += `&end_date=${endDate}`;
    }
    
    if (action === 'download') {
        // تحميل مباشر
        window.location.href = url;
    } else {
        // عرض في نافذة جديدة
        window.open(url, '_blank');
    }
}

// تعيين التاريخ الافتراضي (آخر 30 يوم)
document.addEventListener('DOMContentLoaded', function() {
    const today = new Date();
    const thirtyDaysAgo = new Date(today.getTime() - (30 * 24 * 60 * 60 * 1000));
    
    const formatDate = (date) => {
        return date.toISOString().split('T')[0];
    };
    
    // تعيين التواريخ الافتراضية
    document.getElementById('bookings_start_date').value = formatDate(thirtyDaysAgo);
    document.getElementById('bookings_end_date').value = formatDate(today);
    document.getElementById('financial_start_date').value = formatDate(thirtyDaysAgo);
    document.getElementById('financial_end_date').value = formatDate(today);
});
</script>

<?php include_once '../../includes/footer.php'; ?>
