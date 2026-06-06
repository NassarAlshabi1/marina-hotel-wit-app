<?php
/**
 * لوحة التحكم الرئيسية - فندق مارينا
 */

// جلب بيانات الغرف من قاعدة البيانات
include '../includes/db.php';

// التحقق من اتصال قاعدة البيانات
if (!$conn) {
    die("<div class='alert alert-danger text-center'>فشل الاتصال بقاعدة البيانات: " . mysqli_connect_error() . "</div>");
}

// جلب بيانات الغرف
$sql = "SELECT room_number, status FROM rooms";
$result = mysqli_query($conn, $sql);

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

// حساب إحصائيات الغرف
$total_rooms = count($rooms);
$available_rooms = count(array_filter($rooms, fn($r) => $r['status'] === 'شاغرة'));
$occupied_rooms = $total_rooms - $available_rooms;

// لا نغلق الاتصال بقاعدة البيانات هنا - footer.php سيتولى ذلك

// تضمين الرأس (يُخرج DOCTYPE, html, head, body, nav, content-wrapper, main)
include '../includes/header.php';
?>

<!-- أنماط خاصة بلوحة التحكم -->
<link rel="stylesheet" href="<?= $base_path ?>assets/css/dash.css">
<style>
    /* بطاقات الإحصائيات */
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

    .stat-card.rooms-available {
        border-top: 3px solid #28a745;
    }

    .stat-card.rooms-occupied {
        border-top: 3px solid #dc3545;
    }

    .stat-card .value {
        font-size: 18px;
        font-weight: bold;
        margin: 5px 0;
    }

    .stat-card .icon {
        font-size: 22px;
        margin-bottom: 5px;
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

    .stat-card.rooms-available .icon {
        color: #28a745;
    }

    .stat-card.rooms-occupied .icon {
        color: #dc3545;
    }

    .stat-card small {
        font-size: 11px;
    }

    /* عناوين الأقسام */
    .section-title {
        margin: 25px 0 15px;
        padding-bottom: 8px;
        border-bottom: 1px solid #eee;
        color: #2c3e50;
        font-size: 1.3rem;
    }

    /* بطاقات التنبيهات */
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
        border-right: 3px solid;
        transition: all 0.3s ease;
        font-size: 0.85em;
    }

    .alert-card:hover {
        transform: translateY(-2px);
        box-shadow: 0 4px 12px rgba(0,0,0,0.15);
    }

    .alert-card.alert-high {
        border-right-color: #dc3545;
        background: linear-gradient(135deg, #fff 0%, #fff5f5 100%);
    }

    .alert-card.alert-medium {
        border-right-color: #fd7e14;
        background: linear-gradient(135deg, #fff 0%, #fff8f0 100%);
    }

    .alert-card.alert-low {
        border-right-color: #198754;
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

    /* إجراءات سريعة */
    .quick-actions {
        display: flex;
        flex-wrap: wrap;
        gap: 10px;
        margin-bottom: 25px;
    }

    .quick-action-btn {
        background: linear-gradient(135deg, #4CAF50 0%, #45a049 100%);
        color: white;
        padding: 10px 18px;
        border-radius: 25px;
        text-decoration: none;
        font-size: 0.9em;
        font-weight: 600;
        transition: all 0.3s ease;
        display: inline-flex;
        align-items: center;
        gap: 8px;
        box-shadow: 0 3px 10px rgba(76, 175, 80, 0.3);
        border: 2px solid transparent;
    }

    .quick-action-btn:hover {
        transform: translateY(-3px);
        box-shadow: 0 6px 20px rgba(76, 175, 80, 0.4);
        color: white;
        text-decoration: none;
        border-color: rgba(255,255,255,0.3);
        background: linear-gradient(135deg, #45a049 0%, #4CAF50 100%);
    }

    .quick-action-btn.booking {
        background: linear-gradient(135deg, #3498db 0%, #2980b9 100%);
        box-shadow: 0 3px 10px rgba(52, 152, 219, 0.3);
    }

    .quick-action-btn.booking:hover {
        background: linear-gradient(135deg, #2980b9 0%, #3498db 100%);
        box-shadow: 0 6px 20px rgba(52, 152, 219, 0.4);
    }

    .quick-action-btn.finance {
        background: linear-gradient(135deg, #f39c12 0%, #e67e22 100%);
        box-shadow: 0 3px 10px rgba(243, 156, 18, 0.3);
    }

    .quick-action-btn.finance:hover {
        background: linear-gradient(135deg, #e67e22 0%, #f39c12 100%);
        box-shadow: 0 6px 20px rgba(243, 156, 18, 0.4);
    }

    .quick-action-btn.reports {
        background: linear-gradient(135deg, #9b59b6 0%, #8e44ad 100%);
        box-shadow: 0 3px 10px rgba(155, 89, 182, 0.3);
    }

    .quick-action-btn.reports:hover {
        background: linear-gradient(135deg, #8e44ad 0%, #9b59b6 100%);
        box-shadow: 0 6px 20px rgba(155, 89, 182, 0.4);
    }

    /* تجاوز أنماط dash.css للتكامل مع header.php */
    .dashboard-container {
        min-height: auto;
        padding: 0;
        max-width: 100%;
    }
</style>

<!-- عنوان لوحة التحكم -->
<h2 class="mb-4" style="color: #2c3e50; font-weight: 700;">
    <i class="fas fa-tachometer-alt me-2"></i>لوحة التحكم
</h2>

<!-- بطاقات الإحصائيات -->
<div class="stats-container">
    <div class="stat-card rooms-available">
        <div class="icon"><i class="fas fa-door-open"></i></div>
        <h3>غرف شاغرة</h3>
        <div class="value"><?= $available_rooms ?></div>
        <small>من <?= $total_rooms ?> غرفة</small>
    </div>
    <div class="stat-card rooms-occupied">
        <div class="icon"><i class="fas fa-bed"></i></div>
        <h3>غرف محجوزة</h3>
        <div class="value"><?= $occupied_rooms ?></div>
        <small>من <?= $total_rooms ?> غرفة</small>
    </div>
    <div class="stat-card finance">
        <div class="icon"><i class="fas fa-arrow-down"></i></div>
        <h3>إيرادات اليوم</h3>
        <div class="value"><?= number_format($cash_data['today_income']) ?></div>
        <small>ريال يمني</small>
    </div>
    <div class="stat-card finance">
        <div class="icon"><i class="fas fa-arrow-up"></i></div>
        <h3>مصروفات اليوم</h3>
        <div class="value"><?= number_format($cash_data['today_expense']) ?></div>
        <small>ريال يمني</small>
    </div>
    <div class="stat-card notes">
        <div class="icon"><i class="fas fa-bell"></i></div>
        <h3>تنبيهات نشطة</h3>
        <div class="value"><?= count($active_alerts) ?></div>
        <small>تنبيه</small>
    </div>
</div>

<!-- إجراءات سريعة -->
<div class="quick-actions">
    <a href="<?= $base_path ?>bookings/add_booking.php" class="quick-action-btn booking">
        <i class="fas fa-plus"></i> حجز جديد
    </a>
    <a href="<?= $base_path ?>bookings/checkout.php" class="quick-action-btn">
        <i class="fas fa-sign-out-alt"></i> تسجيل خروج
    </a>
    <a href="<?= $base_path ?>finance/cash_register.php" class="quick-action-btn finance">
        <i class="fas fa-wallet"></i> الصندوق
    </a>
    <a href="<?= $base_path ?>reports/revenue.php" class="quick-action-btn reports">
        <i class="fas fa-chart-line"></i> التقارير
    </a>
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
                <a href="<?= $base_path ?>bookings/add_note.php?booking_id=<?= $alert['booking_id'] ?>"
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

<!-- JavaScript الخاص بلوحة التحكم -->
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
            window.location.href = `<?= $base_path ?>bookings/add.php?room_number=${roomNumber}`;
        } else {
            alert("هذه الغرفة محجوزة ولا يمكن حجزها.");
        }
    }

    // تهيئة العرض الأولي
    document.addEventListener('DOMContentLoaded', () => {
        displayRoomsByFloor();
    });
</script>

<?php include '../includes/footer.php'; ?>
