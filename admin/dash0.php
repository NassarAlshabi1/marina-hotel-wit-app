<?php
// First, let's fix the error handling at the beginning
include_once '../includes/db.php';
include_once '../includes/header.php';
ini_set('display_errors', 1);
ini_set('display_startup_errors', 1);
error_reporting(E_ALL);

// Check database connection
if (!$conn) {
    die("<div class='alert alert-danger text-center'>فشل الاتصال بقاعدة البيانات: " . mysqli_connect_error() . "</div>");
}

// Get room data from the 'rooms' table
$sql = "SELECT room_number, status FROM rooms";
$result = mysqli_query($conn, $sql);

// Check for query errors
if (!$result) {
    die("<div class='alert alert-danger text-center'>خطأ في الاستعلام: " . mysqli_error($conn) . "</div>");
}

$rooms = [];
if (mysqli_num_rows($result) > 0) {
    while ($row = mysqli_fetch_assoc($result)) {
        $rooms[] = $row;
    }
}

// جلب بيانات الصندوق
$cash_data = [
    'today_income' => 0,
    'today_expense' => 0,
    'pending_notes' => 0
];

// محاولة جلب بيانات الصندوق إذا كانت الجداول موجودة
$check_cash_table = mysqli_query($conn, "SHOW TABLES LIKE 'cash_transactions'");
if (mysqli_num_rows($check_cash_table) > 0) {
    $income_query = "SELECT COALESCE(SUM(amount), 0) as total FROM cash_transactions WHERE transaction_type='income' AND DATE(transaction_time) = CURDATE()";
    $income_result = mysqli_query($conn, $income_query);
    if ($income_result && mysqli_num_rows($income_result) > 0) {
        $cash_data['today_income'] = mysqli_fetch_assoc($income_result)['total'];
    }
    
    $expense_query = "SELECT COALESCE(SUM(amount), 0) as total FROM cash_transactions WHERE transaction_type='expense' AND DATE(transaction_time) = CURDATE()";
    $expense_result = mysqli_query($conn, $expense_query);
    if ($expense_result && mysqli_num_rows($expense_result) > 0) {
        $cash_data['today_expense'] = mysqli_fetch_assoc($expense_result)['total'];
    }
}

// جلب التنبيهات النشطة إذا كان الجدول موجوداً
$active_alerts = [];
$check_notes_table = mysqli_query($conn, "SHOW TABLES LIKE 'booking_notes'");
if (mysqli_num_rows($check_notes_table) > 0) {
    $alerts_query = "
        SELECT
            bn.note_id,
            bn.booking_id,
            bn.note_text,
            bn.alert_type,
            bn.created_at,
            b.guest_name,
            b.room_number
        FROM booking_notes bn
        JOIN bookings b ON bn.booking_id = b.booking_id
        WHERE bn.is_active = 1
        AND (bn.alert_until IS NULL OR bn.alert_until > NOW())
        AND b.status != 'غادر' AND b.actual_checkout IS NULL
        ORDER BY bn.alert_type = 'high' DESC, bn.alert_type = 'medium' DESC, bn.created_at DESC
        LIMIT 10
    ";
    $alerts_result = mysqli_query($conn, $alerts_query);
    if ($alerts_result && mysqli_num_rows($alerts_result) > 0) {
        while ($alert = mysqli_fetch_assoc($alerts_result)) {
            $active_alerts[] = $alert;
        }
    }
}

mysqli_close($conn);
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
   
    <!-- Bootstrap RTL محلي للعمل بدون انترنت -->
    <link href="<?= BASE_URL ?>assets/css/bootstrap-complete.css" rel="stylesheet">
    <!-- Font Awesome محلي بدون انترنت -->
    <link href="<?= BASE_URL ?>assets/css/fontawesome-offline.css" rel="stylesheet">
    <!-- خط تجوال محلي بدون انترنت -->
    <link href="<?= BASE_URL ?>assets/fonts/tajawal-offline.css" rel="stylesheet">
    <!-- أنماط الصفحة -->
    <link href="<?= BASE_URL ?>assets/css/dash.css" rel="stylesheet">
    <style>
        /* إعدادات الخط للعمل بدون انترنت */
        body, * {
            font-family: 'Tajawal', 'Cairo', 'Segoe UI', 'Roboto', 'Arial', sans-serif !important;
        }
        
        /* تأكيد دعم RTL ورفع المحتوى */
        html {
            direction: rtl;
            text-align: right;
            margin: 0 !important;
            padding: 0 !important;
        }
        
        body {
            margin: 0 !important;
            padding: 0 !important;
        }
        
        .dashboard-container {
            margin: 0 !important;
            padding: 0 !important;
        }
        
        .container.mt-0 {
            margin-top: 0 !important;
            padding-top: 0 !important;
        }
        
        /* إزالة جميع الهوامش العلوية */
        * {
            margin-top: 0 !important;
        }
        
        /* استثناء للعناصر الداخلية فقط */
        .alert-card, .stat-card, .room-btn, .section-title {
            margin-top: auto !important;
        }
        
        /* تحسين جميع جميع جميع المسافات- الحفاظ على - نسخة محسنة */
        .container {
            padding-left: 8px !important;
            padding: 10px !important;
            padding: 8px !important;
            padding-right: 5px !important;
        }
        
        .container { 
            padding-left: 8px !important; 
            padding-right: 2px !important;
            padding: 8px !important; 
            padding: 2px !important;
            padding: 3px !important;
        }
        
        /* تقليل مسافات الطوابق بشكل كبير */
        .container { padding: 5px 10px !important; }
        .alerts-section { margin-bottom: 8px !important;
            padding: 8px !important;
        }
        
        /* تقليل مسافات الصفوف والأعمدة */
        .row {
            margin-left: -5px !important;
            margin-right: -5px !important;
            margin-bottom: 5px !important;
        }
        
        .col, .col-auto, .col-12, .col-md-6, .col-lg-4, .col-xl-3 {
            padding-left: 5px !important;
            padding-right: 5px !important;
            margin-bottom: 5px !important;
        }
        
        /* تقليل مسافات البطاقات والتنبيهات */
        .alert-card, .card {
            margin-bottom: 8px !important;
            padding: 10px !important;
        }
        
        .alert-card .card-body {
            padding: 8px !important;
        }
        
        /* تقليل مسافات العناوين */
        .section-title {
            margin-bottom: 8px !important;
            padding-bottom: 5px !important;
        }
        
        h3.section-title {
            margin-top: 5px !important;
            margin-bottom: 8px !important;
        }
        
        /* تقليل مسافات أزرار الغرف */
        .room-btn {
            width: 100px !important;
            height: 60px !important;
            margin: 4px !important;
            padding: 4px !important;
            font-size: 0.7em !important;
            border-radius: 4px !important;
            border: none;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.2s ease;
        }
        
        .available-btn {
            background: #28a745 !important;
            color: white !important;
        }
        
        .occupied-btn {
            background: #dc3545 !important;
            color: white !important;
        }
        
        .room-btn:hover {
            transform: scale(1.05);
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        
        /* تقليل مسافات الطوابق */
        .floor-container {
            margin-bottom: 6px !important;
            padding: 5px !important;
        }
        
        .floor-title {
            font-size: 0.9em !important;
            margin-bottom: 5px !important;
            padding: 3px 8px !important;
        }
        
        .floor-rooms {
            padding: 2px !important;
            padding: 4px !important;
            border: 1px solid #e9ecef;
            border-radius: 6px;
            background: #f8f9fa;
        }
        
        .floor-title {
            font-size: 0.85em !important;
            margin-bottom: 3px !important;
            padding: 2px 6px !important;
            background: #007bff;
            color: white;
            border-radius: 4px;
            display: inline-block;
            font-weight: bold;
        }
        
        .floor-rooms {
            padding: 2px !important;
            margin-top: 3px !important;
        }
        
        /* تقليل مسافات أزرار الغرف */
        .room-btn {
            width: 50px !important;
            height: 35px !important;
            margin: 1px !important;
            padding: 1px !important;
            font-size: 0.65em !important;
            border-radius: 3px !important;
            border: none;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.2s ease;
        }
        
        .available-btn {
            background: #28a745 !important;
            color: white !important;
        }
        
        .occupied-btn {
            background: #dc3545 !important;
            color: white !important;
        }
        
        .room-btn:hover {
            transform: scale(1.05);
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        
        /* تقليل مسافات الصفوف والأعمدة */
        .row {
            margin-left: -3px !important;
            margin-right: -3px !important;
            margin-bottom: 3px !important;
        }
        
        .col, .col-auto, .col-12, .col-md-6, .col-lg-4, .col-xl-3 {
            padding-left: 3px !important;
            padding-right: 3px !important;
            margin-bottom: 3px !important;
        }
        
        /* تقليل مسافات البطاقات والتنبيهات */
        .alert-card, .card {
            margin-bottom: 6px !important;
            padding: 8px !important;
        }
        
        .alert-card .card-body {
            padding: 6px !important;
        }
        
        /* تقليل مسافات العناوين */
        .section-title {
            margin-bottom: 6px !important;
            padding-bottom: 3px !important;
            font-size: 1.1rem !important;
        }
        
        h3.section-title {
            margin-top: 3px !important;
            margin-bottom: 6px !important;
            padding: 8px !important; padding: 8px !important; }
        #rooms-container { margin-top: 20px !important;
            padding: 2px !important;
        }
        
        /* تصميم مضغوط للطوابق */
        .floor-container {
            margin-bottom: 2px !important;
            padding: 3px 5px !important;
            border: 1px solid #dee2e6;
            border-radius: 4px;
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
        }
        
        .floor-title {
            font-size: 0.75em !important;
            margin-bottom: 2px !important;
            padding: 1px 4px !important;
            background: #007bff;
            color: white;
            border-radius: 3px;
            display: inline-block;
            font-weight: bold;
            text-align: center;
            min-width: 60px;
        }
        
        .floor-rooms {
            padding: 1px !important;
            margin-top: 2px !important;
            line-height: 1;
        }
        
        /* أزرار الغرف مضغوطة جداً */
        .room-btn {
            width: 45px !important;
            height: 30px !important;
            margin: 1px !important;
            padding: 0px !important;
            font-size: 0.6em !important;
            border-radius: 2px !important;
            border: none;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.15s ease;
            display: inline-flex;
            align-items: center;
            justify-content: center;
        }
        
        .available-btn {
            background: #28a745 !important;
            color: white !important;
        }
        
        .occupied-btn {
            background: #dc3545 !important;
            color: white !important;
        }
        
        .room-btn:hover {
            transform: scale(1.1);
            box-shadow: 0 1px 3px rgba(0,0,0,0.3);
            z-index: 1;
            position: relative;
        }
        
        /* مسافات مضغوطة للصفوف */
        .row {
            margin-left: -2px !important;
            margin-right: -2px !important;
            margin-bottom: 2px !important;
        }
        
        .col, .col-auto, .col-12, .col-md-6, .col-lg-4, .col-xl-3 {
            padding-left: 2px !important;
            padding-right: 2px !important;
            margin-bottom: 2px !important;
        }
        
        /* تقليل مسافات التنبيهات */
        .alert-card, .card {
            margin-bottom: 3px !important;
            padding: 6px !important;
        }
        
        .alert-card .card-body {
            padding: 4px !important;
        }
        
        /* عناوين مضغوطة */
        .section-title {
            margin-bottom: 3px !important;
            padding-bottom: 2px !important;
            font-size: 1rem !important;
        }
        
        h3.section-title {
            margin-top: 2px !important;
            margin-bottom: 3px !important;
            padding: 3px !important; padding: 5px !important; }
        
        .floor-container {
            margin-bottom: px !important;
            padding: 6px !important;
            border: 1px solid #dee2e6;
            border-radius: 6px;
            background: #f8f9fa;
        }
        
        .floor-title {
            font-size: 0.9em !important;
            margin-bottom: 5px !important;
            padding: 3px 8px !important;
            background: #007bff;
            color: white;
            border-radius: 4px;
            display: inline-block;
            font-weight: bold;
        }
        
        .floor-rooms {
            padding: 3px !important;
            margin-top: 5px !important;
        }
        
        /* الحفاظ على حجم أزرار الغرف الطبيعي */
        .room-btn {
            margin: 3px !important;
            border: none;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.2s ease;
        }
        
        .available-btn {
            background: #28a745 !important;
            color: white !important;
        }
        
        .occupied-btn {
            background: #dc3545 !important;
            color: white !important;
        }
        
        .room-btn:hover {
            transform: scale(1.05);
            box-shadow: 0 2px 4px rgba(0,0,0,0.2);
        }
        
        /* تقليل مسافات عامة */
        .row {
            margin-left: -5px !important;
            margin-right: -5px !important;
            margin-bottom: 5px !important;
        }
        
        .col, .col-auto, .col-12 {
            padding-left: 5px !important;
            padding-right: 5px !important;
            margin-bottom: 5px !important;
        }
        
        .alert-card, .card {
            margin-bottom: 8px !important;
            padding: 10px !important;
        }
        
        .section-title {
            margin-bottom: 8px !important;
            padding-bottom: 5px !important;
        }
        
        h3.section-title {
            margin-top: 5px !important;
            margin-bottom: 86px !important;
            padding: 6px 10px !important;
            border: 1px solid #ddd;
            border-radius: 6px;
            background: #f8f9fa;
        }
        
        /* تقليل مسافات الطوابق فقط */
        .floor-title {
            font-size: 0.9em !important;
            margin-bottom: 4px !important;
            padding: 3px 8px !important;
            background: #007bff;
            color: white;
            border-radius: 4px;
            display: inline-block;
            font-weight: bold;
        }
        
        .floor-rooms { padding: 3px !important; margin-top: 4px !important; }
        .room-btn { margin: 3px !important; }
        .row { margin: 0 -5px 5px !important; }
        .col, .col-auto, .col-12 { padding: 0 5px !important; margin-bottom: 5px !important; }
        .alert-card, .card { margin-bottom: 8px !important; padding: 10px !important; }
        .section-title { margin: 5px 0 8px !important; }
        
        /* ضمان عمل Font Awesome بدون انترنت */
        .fas, .far, .fab, .fa {
            font-family: "Font Awesome 6 Free", "Font Awesome 6 Brands" !important;
            font-weight: 900;
            display: inline-block;
            font-style: normal;
            font-variant: normal;
            text-rendering: auto;
            line-height: 1;
        }
        
        /* إضافة أنماط للأقسام الجديدة */
        .stats-container {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
            gap: 10px;
            margin-bottom: 15px;
        }
        
        .stat-card {
            background-color: #fff;
            border-radius: 8px;
            padding: 10px;
            box-shadow: 0 3px 5px rgba(0, 0, 0, 0.1);
            text-align: center;
            transition: all 0.3s ease;
        }
        
        .stat-card:hover {
            transform: translateY(-3px);
            box-shadow: 0 5px 10px rgba(0, 0, 0, 0.1);
        }
        
        .stat-card.finance {
            border-top: 3px solid #f39c12;
        }
        
        .stat-card.notes {
            border-top: 3px solid #9b59b6;
        }
        
        .stat-card .value {
            font-size: 18px;
            font-weight: bold;
            margin: 5px 0;
        }
        
        .stat-card .icon {
            font-size: 22px;
            margin-bottom: 5px;
            color: #3498db;
        }
        
        .stat-card h3 {
            font-size: 14px;
            margin-bottom: 5px;
        }
        
        .stat-card.finance .icon {
            color: #f39c12;
        }
        
        .stat-card.notes .icon {
            color: #9b59b6;
        }
        
        .stat-card small {
            font-size: 11px;
        }
        
        .section-title {
            margin: 25px 0 15px;
            padding-bottom: 8px;
            border-bottom: 1px solid #eee;
            color: #2c3e50;
            font-size: 1.3rem;
        }

        /* أنماط التنبيهات */
        .alerts-container {
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
            gap: 10px;
            margin-bottom: 20px;
        }

        .alert-card {
            background: #fff;
            border-radius: 6px;
            padding: 10px;
            box-shadow: 0 2px 6px rgba(0,0,0,0.08);
            border-left: 3px solid;
            transition: all 0.3s ease;
            font-size: 0.85em;
        }

        .alert-card:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }

        .alert-card.alert-high {
            border-left-color: #dc3545;
            background: linear-gradient(135deg, #fff 0%, #fff5f5 100%);
        }

        .alert-card.alert-medium {
            border-left-color: #fd7e14;
            background: linear-gradient(135deg, #fff 0%, #fff8f0 100%);
        }

        .alert-card.alert-low {
            border-left-color: #198754;
            background: linear-gradient(135deg, #fff 0%, #f0fff4 100%);
        }

        .alert-header {
            display: flex;
            justify-content: space-between;
            align-items: flex-start;
            margin-bottom: 8px;
        }

        .alert-info strong {
            color: #2c3e50;
            font-size: 0.95em;
            display: block;
        }

        .guest-name {
            color: #6c757d;
            font-size: 0.8em;
            display: block;
            margin-top: 2px;
        }

        .alert-priority {
            display: flex;
            align-items: center;
            gap: 3px;
            font-size: 0.75em;
            font-weight: bold;
        }

        .alert-priority.alert-high i,
        .alert-card.alert-high .alert-priority {
            color: #dc3545;
        }

        .alert-priority.alert-medium i,
        .alert-card.alert-medium .alert-priority {
            color: #fd7e14;
        }

        .alert-priority.alert-low i,
        .alert-card.alert-low .alert-priority {
            color: #198754;
        }

        .alert-content {
            color: #495057;
            line-height: 1.4;
            margin-bottom: 8px;
            padding: 4px 0;
            font-size: 0.9em;
            max-height: 60px;
            overflow: hidden;
            text-overflow: ellipsis;
        }

        .alert-footer {
            display: flex;
            justify-content: space-between;
            align-items: center;
            border-top: 1px solid #eee;
            padding-top: 6px;
            font-size: 0.75em;
        }

        .alert-footer .btn {
            font-size: 0.7em;
            padding: 2px 6px;
        }

        /* تنسيق العنوان الرئيسي */
        .dashboard-title {
            color: #2c3e50;
            font-size: 2.5rem;
            font-weight: 700;
            margin-bottom: 0.5rem;
            text-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }

        .dashboard-subtitle {
            color: #6c757d;
            font-size: 1.1rem;
            font-weight: 400;
            margin-bottom: 1.5rem;
        }



        /* تنسيق زر الإعدادات في أعلى الصفحة */
        .container-fluid {
            background: linear-gradient(135deg, #f8f9fa 0%, #e9ecef 100%);
            border-bottom: 1px solid #dee2e6;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            margin: 0 !important;
            padding-top: 8px !important;
            padding-bottom: 8px !important;
        }

        .container-fluid .btn {
            background: linear-gradient(135deg, #007bff 0%, #0056b3 100%);
            border: none;
            border-radius: 25px;
            padding: 10px 20px;
            font-weight: 600;
            box-shadow: 0 4px 15px rgba(0, 123, 255, 0.3);
            transition: all 0.3s ease;
            font-size: 0.95rem;
        }

        .container-fluid .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 6px 20px rgba(0, 123, 255, 0.4);
            background: linear-gradient(135deg, #0056b3 0%, #004494 100%);
        }

        /* أنماط أزرار التنقل */
        .nav-btn {
            background: linear-gradient(135deg, #4CAF50 0%, #45a049 100%);
            color: white;
            padding: 12px 20px;
            margin: 6px;
            border-radius: 25px;
            text-decoration: none;
            font-size: 0.9em;
            font-weight: 600;
            transition: all 0.3s ease;
            display: inline-flex;
            align-items: center;
            box-shadow: 0 3px 10px rgba(76, 175, 80, 0.3);
            border: 2px solid transparent;
        }

        .nav-btn:hover {
            transform: translateY(-3px);
            box-shadow: 0 6px 20px rgba(76, 175, 80, 0.4);
            color: white;
            text-decoration: none;
            border-color: rgba(255,255,255,0.3);
            background: linear-gradient(135deg, #45a049 0%, #4CAF50 100%);
        }

        .nav-btn i {
            margin-left: 8px;
            font-size: 1.1em;
        }


    </style>
</head>
<body>
    <!-- زر الإعدادات في أعلى الصفحة -->
    <div class="container-fluid px-3 py-1 m-0">
        <div class="d-flex justify-content-end">
            <a href="settings/index.php" class="btn btn-primary btn-lg">
                <i class="fas fa-cogs me-2"></i>الإعدادات الرئيسية
            </a>
        </div>
    </div>

    <main class="dashboard-container">
        <div class="container mt-0 pt-0 px-1">

            <!-- قسم التنبيهات النشطة -->
            <?php if (!empty($active_alerts)): ?>
            <div class="alerts-section mb-0">
                <h3 class="section-title">
                    <i class="fas fa-bell text-warning"></i> التنبيهات النشطة
                    <span class="badge bg-danger ms-2"><?= count($active_alerts) ?></span>
                </h3>
                <div class="alerts-container">
                    <?php foreach ($active_alerts as $alert): ?>
                    <div class="alert-card alert-<?= $alert['alert_type'] ?>">
                        <div class="alert-header">
                            <div class="alert-info">
                                <strong>غرفة <?= htmlspecialchars($alert['room_number']) ?></strong>
                                <span class="guest-name"><?= htmlspecialchars($alert['guest_name']) ?></span>
                            </div>
                            <div class="alert-priority">
                                <?php
                                $priority_text = '';
                                $priority_icon = '';
                                switch($alert['alert_type']) {
                                    case 'high':
                                        $priority_text = 'عالي';
                                        $priority_icon = 'fas fa-exclamation-triangle';
                                        break;
                                    case 'medium':
                                        $priority_text = 'متوسط';
                                        $priority_icon = 'fas fa-exclamation-circle';
                                        break;
                                    case 'low':
                                        $priority_text = 'منخفض';
                                        $priority_icon = 'fas fa-info-circle';
                                        break;
                                }
                                ?>
                                <i class="<?= $priority_icon ?>"></i>
                                <span><?= $priority_text ?></span>
                            </div>
                        </div>
                        <div class="alert-content">
                            <?= htmlspecialchars($alert['note_text']) ?>
                        </div>
                        <div class="alert-footer">
                            <small class="text-muted">
                                <i class="fas fa-clock"></i>
                                <?= date('Y-m-d H:i', strtotime($alert['created_at'])) ?>
                            </small>
                            <a href="bookings/add_note.php?booking_id=<?= $alert['booking_id'] ?>"
                               class="btn btn-sm btn-outline-primary">
                                <i class="fas fa-edit"></i> إدارة
                            </a>
                        </div>
                    </div>
                    <?php endforeach; ?>
                </div>
            </div>
            <?php endif; ?>

            <!-- عرض الغرف حسب الطوابق -->
            <div id="rooms-container" class="mt-0">
                <!-- سيتم إنشاء هذا القسم ديناميكياً بواسطة JavaScript -->
            </div>
        </div>
    </main>

    <!-- Bootstrap JavaScript محلي للعمل بدون انترنت -->
    <script src="<?= BASE_URL ?>assets/js/bootstrap-local.js"></script>
    <script>
        // تحويل بيانات الغرف من PHP إلى JavaScript
        const roomsData = <?php echo json_encode($rooms); ?>;
        
        // تنظيم الغرف حسب الطوابق
        function organizeRoomsByFloor(rooms) {
            const floors = {};
            
            rooms.forEach(room => {
                // استخراج رقم الطابق من رقم الغرفة (الرقم الأول)
                const floorNumber = room.room_number.charAt(0);
                
                if (!floors[floorNumber]) {
                    floors[floorNumber] = [];
                }
                
                floors[floorNumber].push(room);
            });
            
            // ترتيب الغرف في كل طابق
            for (const floor in floors) {
                floors[floor].sort((a, b) => {
                    return parseInt(a.room_number) - parseInt(b.room_number);
                });
            }
            
            return floors;
        }
        
        // عرض الغرف حسب الطوابق
        function displayRoomsByFloor() {
            const roomsContainer = document.getElementById('rooms-container');
            roomsContainer.innerHTML = '';
            
            const floors = organizeRoomsByFloor(roomsData);
            
            // ترتيب الطوابق تصاعدياً
            const sortedFloors = Object.keys(floors).sort();
            
            sortedFloors.forEach(floor => {
                const floorContainer = document.createElement('div');
                floorContainer.className = 'floor-container';
                
                const floorTitle = document.createElement('div');
                floorTitle.className = 'floor-title';
                floorTitle.innerHTML = `<i class="fas fa-building me-2"></i> الطابق ${floor}`;
                
                const floorRooms = document.createElement('div');
                floorRooms.className = 'floor-rooms';
                
                floors[floor].forEach(room => {
                    const roomButton = document.createElement('button');
                    roomButton.className = `room-btn ${room.status === 'شاغرة' ? 'available-btn' : 'occupied-btn'}`;
                    roomButton.setAttribute('data-status', room.status);
                    roomButton.setAttribute('data-room-number', room.room_number);
                    roomButton.onclick = function() {
                        handleRoomClick(room.room_number, room.status);
                    };
                    roomButton.textContent = room.room_number;
                    
                    floorRooms.appendChild(roomButton);
                });
                
                floorContainer.appendChild(floorTitle);
                floorContainer.appendChild(floorRooms);
                roomsContainer.appendChild(floorContainer);
            });
        }

        // معالجة النقر على الغرفة
        function handleRoomClick(roomNumber, status) {
            if (status === 'شاغرة') {
                // توجيه المستخدم إلى صفحة تسجيل الحجز
                window.location.href = `bookings/add.php?room_number=${roomNumber}`;
            } else {
                alert("هذه الغرفة محجوزة ولا يمكن حجزها.");
            }
        }
        
        // تهيئة العرض الأولي
        document.addEventListener('DOMContentLoaded', () => {
            displayRoomsByFloor();
        });
        

    </script>
</body>
</html>
