<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';

// الجلسة تبدأ تلقائياً عبر header.php -> auth.php


if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

$conn->set_charset("utf8mb4");

// استعلام لجلب الحجوزات النشطة مع الملاحظات والتنبيهات
$query = "
    SELECT 
        b.booking_id,
        b.guest_name,
        b.room_number,
        r.price AS room_price,
        DATE_FORMAT(b.checkin_date, '%d/%m/%Y') AS checkin_date,
        CASE 
            WHEN b.actual_checkout IS NULL 
            THEN DATEDIFF(CURRENT_DATE(), b.checkin_date) + 
                 (CASE WHEN TIME(CURRENT_TIME()) > '13:00:00' THEN 1 ELSE 0 END)
            ELSE DATEDIFF(b.actual_checkout, b.checkin_date)
        END AS nights,
        IFNULL((SELECT SUM(amount) FROM payment WHERE booking_id = b.booking_id), 0) AS paid_amount,
        (r.price * (
            CASE 
                WHEN b.actual_checkout IS NULL 
                THEN DATEDIFF(CURRENT_DATE(), b.checkin_date) + 
                     (CASE WHEN TIME(CURRENT_TIME()) > '13:00:00' THEN 1 ELSE 0 END)
                ELSE DATEDIFF(b.actual_checkout, b.checkin_date)
            END
        )) - IFNULL((SELECT SUM(amount) FROM payment WHERE booking_id = b.booking_id), 0) AS remaining_amount,
        b.status,
        b.notes,
        (SELECT COUNT(*) FROM booking_notes WHERE booking_id = b.booking_id AND is_active = 1 AND (alert_until IS NULL OR alert_until > NOW())) AS has_alerts
    FROM bookings b
    JOIN rooms r ON b.room_number = r.room_number
    WHERE b.status != 'غادر' AND b.actual_checkout IS NULL
    ORDER BY b.checkin_date DESC
";

$result = $conn->query($query);

// استعلام لجلب التنبيهات النشطة
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
    ORDER BY bn.created_at DESC
";

$alerts_result = $conn->query($alerts_query);
$active_alerts = [];
if ($alerts_result && $alerts_result->num_rows > 0) {
    while ($alert = $alerts_result->fetch_assoc()) {
        $active_alerts[$alert['booking_id']][] = $alert;
    }
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>قائمة الحجوزات - فندق مارينا بلازا</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
    <style>
        .container {
            max-width: 1200px;
        }

        .table {
            font-size: 14px;
            width: 100% !important;
            border-collapse: separate;
            border-spacing: 0;
        }

        .table thead th {
            text-align: center;
            vertical-align: middle;
            padding: 15px 10px;
            font-weight: bold;
        }

        .small-col {
            width: 5% !important;
            padding-left: 5px !important;
            padding-right: 5px !important;
        }

        .table td, .table th {
            padding: 15px 10px;
            vertical-align: middle !important;
            font-weight: 700;
        }

        .small-text {
            font-size: 11px !important;
            font-weight: normal !important;
        }

        td.text-start {
            white-space: nowrap !important;
            overflow: hidden;
            text-overflow: ellipsis;
            text-align: right !important;
        }

        td.text-center {
            text-align: center !important;
        }

        .badge {
            font-size: 0.75rem;
            padding: 0.35em 0.65em;
            font-weight: 700;
        }

        .btn-sm {
            padding: 5px 9px;
            min-width: 50px;
            font-weight: 700;
            font-size: 12px;
        }

        .d-flex.gap-2 {
            gap: 10px !important;
        }

        .bg-success {
            background-color: #198754 !important;
        }

        .bg-warning {
            background-color: #ffc107 !important;
            color: #212529 !important;
        }

        .bg-danger {
            background-color: #dc3545 !important;
        }

        .table-primary {
            background-color: #0d6efd !important;
            color: #fff;
        }

        /* تصميم التنبيهات */
        .alert-badge {
            position: relative;
            display: inline-block;
            cursor: pointer;
        }

        .alert-badge .badge {
            position: absolute;
            top: -8px;
            right: -8px;
            border-radius: 50%;
            width: 20px;
            height: 20px;
            font-size: 12px;
            display: flex;
            align-items: center;
            justify-content: center;
        }

        .alert-icon {
            font-size: 1.2rem;
        }

        .alert-high {
            color: #dc3545;
        }

        .alert-medium {
            color: #fd7e14;
        }

        .alert-low {
            color: #198754;
        }

        .alert-tooltip {
            position: absolute;
            z-index: 1000;
            background-color: white;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 10px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.2);
            min-width: 250px;
            max-width: 350px;
            display: none;
        }

        .alert-tooltip-item {
            padding: 8px;
            margin-bottom: 5px;
            border-radius: 5px;
        }

        .alert-tooltip-item.high {
            background-color: #f8d7da;
            border: 1px solid #f5c2c7;
        }

        .alert-tooltip-item.medium {
            background-color: #fff3cd;
            border: 1px solid #ffecb5;
        }

        .alert-tooltip-item.low {
            background-color: #d1e7dd;
            border: 1px solid #badbcc;
        }

        .alert-tooltip-item .time {
            font-size: 0.8rem;
            color: #6c757d;
            display: block;
            margin-top: 5px;
        }

        .alert-tooltip-item .text {
            font-weight: normal;
        }

        .alert-tooltip-title {
            font-weight: bold;
            margin-bottom: 10px;
            border-bottom: 1px solid #ddd;
            padding-bottom: 5px;
        }

        /* قسم التنبيهات النشطة */
        .active-alerts-section {
            margin-bottom: 20px;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 15px;
            background-color: #f8f9fa;
        }

        .active-alerts-title {
            font-weight: bold;
            margin-bottom: 15px;
            color: #0d6efd;
            border-bottom: 1px solid #ddd;
            padding-bottom: 10px;
        }

        .active-alerts-container {
            display: flex;
            flex-wrap: wrap;
            gap: 10px;
        }

        .active-alert-item {
            padding: 10px;
            border-radius: 5px;
            width: 100%;
            margin-bottom: 10px;
        }

        .active-alert-item.high {
            background-color: #f8d7da;
            border: 1px solid #f5c2c7;
        }

        .active-alert-item.medium {
            background-color: #fff3cd;
            border: 1px solid #ffecb5;
        }

        .active-alert-item.low {
            background-color: #d1e7dd;
            border: 1px solid #badbcc;
        }

        .active-alert-header {
            display: flex;
            justify-content: space-between;
            margin-bottom: 5px;
        }

        .active-alert-guest {
            font-weight: bold;
        }

        .active-alert-room {
            font-weight: bold;
            background-color: #e9ecef;
            padding: 2px 8px;
            border-radius: 15px;
        }

        .active-alert-text {
            margin-bottom: 5px;
        }

        .active-alert-time {
            font-size: 0.8rem;
            color: #6c757d;
            text-align: left;
        }

        @media (min-width: 992px) {
            .table-responsive {
                padding: 15px;
            }
            
            .active-alert-item {
                width: calc(50% - 5px);
            }
        }
    </style>
</head>
<body>
    <div class="container py-4">
        <!-- أزرار العودة والحجز الجديد -->
        <div class="d-flex justify-content-between mb-3">
            <a href="../dash.php" class="btn btn-outline-primary fw-bold">
                ← العودة إلى لوحة التحكم
            </a>
            <a href="../bookings/add2.php" class="btn btn-success fw-bold">
                + حجز جديد
            </a>
        </div>

        <h2 class="text-center mb-4 text-primary fw-bold">قائمة الحجوزات الحالية - فندق مارينا بلازا</h2>

        <?php if (isset($_GET['success'])): ?>
            <div class="alert alert-success text-center" role="alert">
                <?= htmlspecialchars($_GET['success']); ?>
            </div>
        <?php endif; ?>

        <?php if (isset($_GET['error'])): ?>
            <div class="alert alert-danger text-center" role="alert">
                <?= htmlspecialchars($_GET['error']); ?>
            </div>
        <?php endif; ?>

        <!-- قسم التنبيهات النشطة -->
        <?php 
        $total_alerts = 0;
        foreach ($active_alerts as $booking_alerts) {
            $total_alerts += count($booking_alerts);
        }
        
        if ($total_alerts > 0): 
        ?>
        <div class="active-alerts-section">
            <div class="active-alerts-title">
                <i class="fas fa-bell me-2"></i> التنبيهات النشطة (<?= $total_alerts ?>)
            </div>
            <div class="active-alerts-container">
                <?php foreach ($active_alerts as $booking_id => $booking_alerts): ?>
                    <?php foreach ($booking_alerts as $alert): ?>
                        <div class="active-alert-item <?= $alert['alert_type'] ?>">
                            <div class="active-alert-header">
                                <span class="active-alert-guest">
                                    <i class="fas fa-user me-1"></i> <?= htmlspecialchars($alert['guest_name']) ?>
                                </span>
                                <span class="active-alert-room">
                                    <i class="fas fa-door-open me-1"></i> غرفة <?= htmlspecialchars($alert['room_number']) ?>
                                </span>
                            </div>
                            <div class="active-alert-text">
                                <?= htmlspecialchars($alert['note_text']) ?>
                            </div>
                            <div class="active-alert-time">
                                <i class="fas fa-clock me-1"></i> <?= date('d/m/Y H:i', strtotime($alert['created_at'])) ?>
                            </div>
                        </div>
                    <?php endforeach; ?>
                <?php endforeach; ?>
            </div>
        </div>
        <?php endif; ?>

        <div class="table-responsive rounded shadow-sm border">
            <table class="table table-bordered table-hover align-middle mb-0">
                <thead class="table-primary text-center">
                    <tr>
                        <th>#</th>
                        <th style="text-align: right;">اسم النزيل</th>
                        <th>رقم الغرفة</th>
                        <th>السعر/ليلة</th>
                        <th>تاريخ الوصول</th>
                        <th style="width: 5%;">عدد الليالي</th>
                        <th>المدفوع</th>
                        <th>المتبقي</th>
                        <th>حالة الفاتورة</th>
                        <th>حالة الحجز</th>
                        <th>تنبيهات</th>
                        <th>الإجراءات</th>
                    </tr>
                </thead>
                <tbody>
                    <?php if ($result && $result->num_rows > 0): ?>
                        <?php $counter = 1; ?>
                        <?php while ($row = $result->fetch_assoc()): ?>
                            <?php
                                $nights = max(1, $row['nights']);
                                $total_price = $row['room_price'] * $nights;
                                $remaining = max(0, $row['remaining_amount']);
                                $paid = $row['paid_amount'];

                                if ($paid >= $total_price) {
                                    $payment_status = 'مسددة';
                                    $payment_class = 'bg-success text-white';
                                } elseif ($paid > 0) {
                                    $payment_status = 'مدفوعة جزئياً';
                                    $payment_class = 'bg-warning';
                                } else {
                                    $payment_status = 'غير مسددة';
                                    $payment_class = 'bg-danger text-white';
                                }

                                $booking_status_labels = [
                                    'confirmed' => 'مؤكدة',
                                    'checked_in' => 'مقيمة حالياً',
                                    'checked_out' => 'مغادرة',
                                    'cancelled' => 'ملغية',
                                ];
                                $booking_status = $booking_status_labels[$row['status']] ?? htmlspecialchars($row['status']);
                                
                                // تحديد نوع التنبيه الأعلى أهمية
                                $alert_type = '';
                                if (isset($active_alerts[$row['booking_id']])) {
                                    foreach ($active_alerts[$row['booking_id']] as $alert) {
                                        if ($alert['alert_type'] == 'high') {
                                            $alert_type = 'high';
                                            break;
                                        } elseif ($alert['alert_type'] == 'medium' && $alert_type != 'high') {
                                            $alert_type = 'medium';
                                        } elseif ($alert['alert_type'] == 'low' && $alert_type == '') {
                                            $alert_type = 'low';
                                        }
                                    }
                                }
                            ?>
                            <tr>
                                <td class="text-center fw-bold"><?= $counter++; ?></td>
                                <td class="text-start fw-bold"><?= htmlspecialchars($row['guest_name']); ?></td>
                                <td class="text-center fw-bold"><?= htmlspecialchars($row['room_number']); ?></td>
                                <td class="text-center fw-bold"><?= number_format($row['room_price'], 0); ?></td>
                                <td class="text-center small-text"><?= htmlspecialchars($row['checkin_date']); ?></td>
                                <td class="text-center fw-bold small-col"><?= $nights; ?></td>
                                <td class="text-center fw-bold"><?= number_format($paid, 0); ?></td>
                                <td class="text-center fw-bold"><?= number_format($remaining, 0); ?></td>
                                <td class="text-center"><span class="badge <?= $payment_class; ?> fw-bold"><?= $payment_status; ?></span></td>
                                <td class="text-center fw-bold"><?= $booking_status; ?></td>
                                <td class="text-center">
                                    <?php if (isset($active_alerts[$row['booking_id']])): ?>
                                        <div class="alert-badge" data-booking-id="<?= $row['booking_id']; ?>">
                                            <i class="fas fa-bell alert-icon alert-<?= $alert_type ?>"></i>
                                            <span class="badge bg-danger"><?= count($active_alerts[$row['booking_id']]); ?></span>
                                            <div class="alert-tooltip" id="tooltip-<?= $row['booking_id']; ?>">
                                                <div class="alert-tooltip-title">تنبيهات النزيل <?= htmlspecialchars($row['guest_name']); ?></div>
                                                <?php foreach ($active_alerts[$row['booking_id']] as $alert): ?>
                                                    <div class="alert-tooltip-item <?= $alert['alert_type']; ?>">
                                                        <div class="text"><?= htmlspecialchars($alert['note_text']); ?></div>
                                                        <div class="time"><?= date('d/m/Y H:i', strtotime($alert['created_at'])); ?></div>
                                                    </div>
                                                <?php endforeach; ?>
                                            </div>
                                        </div>
                                    <?php else: ?>
                                        <a href="add_note.php?id=<?= $row['booking_id']; ?>" class="btn btn-sm btn-outline-secondary">
                                            <i class="fas fa-plus"></i> إضافة
                                        </a>
                                    <?php endif; ?>
                                </td>
                                <td class="text-center">
                                    <div class="d-flex justify-content-center gap-2 flex-wrap">
                                        <?php if ($row['status'] === 'confirmed'): ?>
                                            <a href="checkin.php?id=<?= $row['booking_id']; ?>" class="btn btn-sm btn-primary fw-bold">تسجيل الدخول</a>
                                        <?php elseif ($row['status'] === 'checked_in'): ?>
                                            <a href="payment.php?id=<?= $row['booking_id']; ?>" class="btn btn-sm btn-success fw-bold">تسديد</a>
                                            <a href="checkout.php?id=<?= $row['booking_id']; ?>" class="btn btn-sm btn-danger fw-bold">تسجيل المغادرة</a>
                                        <?php endif; ?>
                                        
                                        <a href="payment.php?id=<?= $row['booking_id']; ?>" class="btn btn-sm btn-success fw-bold">دفع</a>
                                        
                                        <?php if (isset($active_alerts[$row['booking_id']])): ?>
                                            <a href="add_note.php?id=<?= $row['booking_id']; ?>" class="btn btn-sm btn-warning fw-bold">
                                                <i class="fas fa-edit"></i> تعديل التنبيه
                                            </a>
                                        <?php else: ?>
                                            <a href="add_note.php?id=<?= $row['booking_id']; ?>" class="btn btn-sm btn-info fw-bold">
                                                <i class="fas fa-bell"></i> إضافة تنبيه
                                            </a>
                                        <?php endif; ?>
                                    </div>
                                </td>
                            </tr>
                        <?php endwhile; ?>
                    <?php else: ?>
                        <tr>
                            <td colspan="12" class="text-center py-3 text-muted fw-bold">لا توجد حجوزات حالية في الفندق</td>
                        </tr>
                    <?php endif; ?>
                </tbody>
            </table>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // عرض وإخفاء التنبيهات عند النقر
        document.addEventListener('DOMContentLoaded', function() {
            const alertBadges = document.querySelectorAll('.alert-badge');
            
            alertBadges.forEach(badge => {
                badge.addEventListener('click', function(e) {
                    e.stopPropagation();
                    const bookingId = this.getAttribute('data-booking-id');
                    const tooltip = document.getElementById('tooltip-' + bookingId);
                    
                    // إغلاق جميع التنبيهات المفتوحة
                    document.querySelectorAll('.alert-tooltip').forEach(tip => {
                        if (tip.id !== 'tooltip-' + bookingId) {
                            tip.style.display = 'none';
                        }
                    });
                    
                    // عرض أو إخفاء التنبيه الحالي
                    if (tooltip.style.display === 'block') {
                        tooltip.style.display = 'none';
                    } else {
                        tooltip.style.display = 'block';
                        
                        // تحديد موقع التنبيه
                        const badgeRect = this.getBoundingClientRect();
                        tooltip.style.top = (badgeRect.bottom + window.scrollY + 10) + 'px';
                        tooltip.style.left = (badgeRect.left + window.scrollX - 150) + 'px';
                    }
                });
            });
            
            // إغلاق التنبيهات عند النقر في أي مكان آخر
            document.addEventListener('click', function() {
                document.querySelectorAll('.alert-tooltip').forEach(tooltip => {
                    tooltip.style.display = 'none';
                });
            });
        });
    </script>
</body>
</html>

<?php $conn->close(); ?>
