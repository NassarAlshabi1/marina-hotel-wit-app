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
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>لوحة التحكم الرئيسية</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/dash.css" rel="stylesheet">
    <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700&display=swap" rel="stylesheet">
    <style>
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


    <main class="dashboard-container">
        <div class="container">
            <!-- زر الإعدادات الرئيسي -->
            <div class="row mb-4">
                <div class="col-12">
                    <div class="d-flex justify-content-between align-items-center">
                        <h2 class="mb-0">
                            <i class="fas fa-tachometer-alt me-2"></i>لوحة التحكم الرئيسية
                        </h2>
                        <a href="settings/index.php" class="btn btn-primary btn-lg">
                            <i class="fas fa-cogs me-2"></i>الإعدادات الرئيسية
                        </a>
                    </div>
                </div>
            </div>

            <!-- قسم التنبيهات النشطة -->
            <?php if (!empty($active_alerts)): ?>
            <div class="alerts-section mb-4">
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
            <h3 class="section-title"><i class="fas fa-door-open"></i> حالة الغرف</h3>
            <div id="rooms-container">
                <!-- سيتم إنشاء هذا القسم ديناميكياً بواسطة JavaScript -->
            </div>
        </div>
    </main>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
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
