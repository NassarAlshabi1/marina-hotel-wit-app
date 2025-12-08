<?php
/**
 * اختبار صفحة لوحة التحكم للعمل بدون انترنت
 * يحاكي بيانات الغرف والتنبيهات لاختبار التصميم
 */

// محاكاة بيانات الغرف
$rooms = [
    ['room_number' => '101', 'status' => 'شاغرة'],
    ['room_number' => '102', 'status' => 'محجوزة'],
    ['room_number' => '103', 'status' => 'شاغرة'],
    ['room_number' => '201', 'status' => 'محجوزة'],
    ['room_number' => '202', 'status' => 'شاغرة'],
    ['room_number' => '203', 'status' => 'محجوزة'],
];

// محاكاة بيانات الصندوق
$cash_data = [
    'today_income' => 1500,
    'today_expense' => 300,
    'pending_notes' => 2
];

// محاكاة التنبيهات النشطة
$active_alerts = [
    [
        'note_id' => 1,
        'booking_id' => 123,
        'note_text' => 'النزيل يطلب تنظيف إضافي للغرفة',
        'alert_type' => 'medium',
        'created_at' => '2024-01-15 10:30:00',
        'guest_name' => 'أحمد محمد',
        'room_number' => '101'
    ],
    [
        'note_id' => 2,
        'booking_id' => 124,
        'note_text' => 'مشكلة في التكييف - يحتاج صيانة عاجلة',
        'alert_type' => 'high',
        'created_at' => '2024-01-15 11:15:00',
        'guest_name' => 'فاطمة أحمد',
        'room_number' => '201'
    ]
];

// تعريف BASE_URL للاختبار
define('BASE_URL', 'http://localhost/marina%20hotel/');
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>اختبار لوحة التحكم - بدون انترنت</title>
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
        
        /* تأكيد دعم RTL */
        html {
            direction: rtl;
            text-align: right;
        }
        
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
        
        /* أنماط اختبار الاتصال */
        .offline-indicator {
            position: fixed;
            top: 10px;
            left: 10px;
            background: #dc3545;
            color: white;
            padding: 8px 12px;
            border-radius: 4px;
            font-size: 12px;
            z-index: 9999;
            display: none;
        }
        
        .offline-indicator.show {
            display: block;
        }
        
        .online-indicator {
            position: fixed;
            top: 10px;
            left: 10px;
            background: #198754;
            color: white;
            padding: 8px 12px;
            border-radius: 4px;
            font-size: 12px;
            z-index: 9999;
        }
        
        /* باقي الأنماط من الملف الأصلي */
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

        /* أنماط الغرف */
        .floor-container {
            margin-bottom: 20px;
            border: 1px solid #ddd;
            border-radius: 8px;
            overflow: hidden;
        }

        .floor-title {
            background: linear-gradient(135deg, #3498db 0%, #2980b9 100%);
            color: white;
            padding: 10px 15px;
            font-weight: bold;
            font-size: 1.1em;
        }

        .floor-rooms {
            padding: 15px;
            display: grid;
            grid-template-columns: repeat(auto-fill, minmax(60px, 1fr));
            gap: 8px;
        }

        .room-btn {
            padding: 8px;
            border: none;
            border-radius: 4px;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.3s ease;
            min-height: 40px;
        }

        .room-btn.available-btn {
            background: linear-gradient(135deg, #27ae60 0%, #2ecc71 100%);
            color: white;
        }

        .room-btn.occupied-btn {
            background: linear-gradient(135deg, #e74c3c 0%, #c0392b 100%);
            color: white;
        }

        .room-btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 8px rgba(0,0,0,0.2);
        }
    </style>
</head>
<body>
    <!-- مؤشر حالة الاتصال -->
    <div id="connectionStatus" class="online-indicator">
        <i class="fas fa-wifi"></i> متصل محلياً
    </div>

    <div class="container mt-4">
        <!-- العنوان الرئيسي -->
        <div class="row mb-4">
            <div class="col-12">
                <div class="d-flex justify-content-between align-items-center">
                    <h2 class="mb-0">
                        <i class="fas fa-tachometer-alt me-2"></i>لوحة التحكم الرئيسية (اختبار بدون انترنت)
                    </h2>
                    <button class="btn btn-primary btn-lg">
                        <i class="fas fa-cogs me-2"></i>الإعدادات الرئيسية
                    </button>
                </div>
            </div>
        </div>

        <!-- إحصائيات الصندوق -->
        <div class="stats-container mb-4">
            <div class="stat-card finance">
                <div class="icon">
                    <i class="fas fa-money-bill"></i>
                </div>
                <h3>إيرادات اليوم</h3>
                <div class="value"><?= number_format($cash_data['today_income']) ?> ريال</div>
                <small>المبلغ المحصل اليوم</small>
            </div>
            
            <div class="stat-card finance">
                <div class="icon">
                    <i class="fas fa-credit-card"></i>
                </div>
                <h3>مصروفات اليوم</h3>
                <div class="value"><?= number_format($cash_data['today_expense']) ?> ريال</div>
                <small>إجمالي المصروفات</small>
            </div>
            
            <div class="stat-card notes">
                <div class="icon">
                    <i class="fas fa-bell"></i>
                </div>
                <h3>التنبيهات</h3>
                <div class="value"><?= $cash_data['pending_notes'] ?></div>
                <small>تنبيهات نشطة</small>
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
                        <button class="btn btn-sm btn-outline-primary">
                            <i class="fas fa-edit"></i> إدارة
                        </button>
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

    <!-- Bootstrap JavaScript محلي للعمل بدون انترنت -->
    <script src="<?= BASE_URL ?>assets/js/bootstrap-local.js"></script>
    <script>
        // تحويل بيانات الغرف من PHP إلى JavaScript
        const roomsData = <?php echo json_encode($rooms); ?>;
        
        // اختبار حالة الاتصال
        function checkConnectionStatus() {
            const indicator = document.getElementById('connectionStatus');
            
            if (!navigator.onLine) {
                indicator.className = 'offline-indicator show';
                indicator.innerHTML = '<i class="fas fa-wifi-slash"></i> غير متصل - وضع بدون انترنت';
            } else {
                // محاولة تحميل مورد خارجي للتأكد من الاتصال
                fetch('https://www.google.com/favicon.ico', { 
                    mode: 'no-cors',
                    cache: 'no-cache'
                }).then(() => {
                    indicator.className = 'online-indicator';
                    indicator.innerHTML = '<i class="fas fa-wifi"></i> متصل بالانترنت';
                }).catch(() => {
                    indicator.className = 'offline-indicator show';
                    indicator.innerHTML = '<i class="fas fa-wifi-slash"></i> غير متصل - وضع بدون انترنت';
                });
            }
        }
        
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
                alert(`غرفة ${roomNumber} شاغرة - يمكن حجزها`);
            } else {
                alert(`غرفة ${roomNumber} محجوزة`);
            }
        }
        
        // تهيئة العرض الأولي
        document.addEventListener('DOMContentLoaded', () => {
            displayRoomsByFloor();
            checkConnectionStatus();
            
            // فحص حالة الاتصال كل 30 ثانية
            setInterval(checkConnectionStatus, 30000);
        });
        
        // مراقبة تغيير حالة الاتصال
        window.addEventListener('online', checkConnectionStatus);
        window.addEventListener('offline', checkConnectionStatus);
    </script>
</body>
</html>