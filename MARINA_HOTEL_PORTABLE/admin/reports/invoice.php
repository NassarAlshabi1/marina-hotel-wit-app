
<?php
include_once '../../includes/db.php';

$date_today = date('Y-m-d');
$month_start = date('Y-m-01');
$month_end = date('Y-m-t');

// استعلام لجلب التقارير اليومية
$daily_report_query = "
    SELECT 
        b.booking_id,
        g.name AS guest_name,
        g.phone,
        r.room_number,
        b.checkin_date,
        b.checkout_date,
        r.price AS room_price,
        DATEDIFF(b.checkout_date, b.checkin_date) AS days,
        (DATEDIFF(b.checkout_date, b.checkin_date) * r.price) AS total
    FROM bookings b 
    JOIN guests g ON b.guest_id = g.guest_id 
    JOIN rooms r ON b.room_number = r.room_number 
    WHERE b.status = 'محجوز' AND DATE(b.checkout_date) = ?
";

$daily_stmt = $conn->prepare($daily_report_query);
$daily_stmt->bind_param("s", $date_today);
$daily_stmt->execute();
$daily_result = $daily_stmt->get_result();

// استعلام لجلب التقارير الشهرية
$monthly_report_query = "
    SELECT 
        b.booking_id,
        g.name AS guest_name,
        g.phone,
        r.room_number,
        b.checkin_date,
        b.checkout_date,
        r.price AS room_price,
        DATEDIFF(b.checkout_date, b.checkin_date) AS days,
        (DATEDIFF(b.checkout_date, b.checkin_date) * r.price) AS total
    FROM bookings b 
    JOIN guests g ON b.guest_id = g.guest_id 
    JOIN rooms r ON b.room_number = r.room_number 
    WHERE b.status = 'محجوز' AND b.checkout_date BETWEEN ? AND ?
";

$monthly_stmt = $conn->prepare($monthly_report_query);
$monthly_stmt->bind_param("ss", $month_start, $month_end);
$monthly_stmt->execute();
$monthly_result = $monthly_stmt->get_result();
?>

<div class="container py-4">
    <h2 class="text-center mb-4">تقارير النزلاء</h2>

    <h3>التقرير اليومي (<?= $date_today; ?>)</h3>
    <table class="table table-bordered">
        <thead>
            <tr>
                <th>رقم الحجز</th>
                <th>اسم النزيل</th>
                <th>رقم الهاتف</th>
                <th>رقم الغرفة</th>
                <th>تاريخ الوصول</th>
                <th>تاريخ المغادرة</th>
                <th>عدد الليالي</th>
                <th>الإجمالي</th>
            </tr>
        </thead>
        <tbody>
            <?php while ($row = $daily_result->fetch_assoc()): ?>
                <tr>
                    <td><?= $row['booking_id']; ?></td>
                    <td><?= htmlspecialchars($row['guest_name']); ?></td>
                    <td><?= htmlspecialchars($row['phone']); ?></td>
                    <td><?= htmlspecialchars($row['room_number']); ?></td>
                    <td><?= htmlspecialchars($row['checkin_date']); ?></td>
                    <td><?= htmlspecialchars($row['checkout_date']); ?></td>
                    <td><?= $row['days']; ?> ليالي</td>
                    <td><?= number_format($row['total']); ?> </td>
                </tr>
            <?php endwhile; ?>
        </tbody>
    </table>

    <h3>التقرير الشهري (<?= date('F Y'); ?>)</h3>
    <table class="table table-bordered">
        <thead>
            <tr>
                <th>رقم الحجز</th>
                <th>اسم النزيل</th>
                <th>رقم الهاتف</th>
                <th>رقم الغرفة</th>
                <th>تاريخ الوصول</th>
                <th>تاريخ المغادرة</th>
                <th>عدد الليالي</th>
                <th>الإجمالي</th>
            </tr>
        </thead>
        <tbody>
            <?php while ($row = $monthly_result->fetch_assoc()): ?>
                <tr>
                    <td><?= $row['booking_id']; ?></td>
                    <td><?= htmlspecialchars($row['guest_name']); ?></td>
                    <td><?= htmlspecialchars($row['phone']); ?></td>
                    <td><?= htmlspecialchars($row['room_number']); ?></td>
                    <td><?= htmlspecialchars($row['checkin_date']); ?></td>
                    <td><?= htmlspecialchars($row['checkout_date']); ?></td>
                    <td><?= $row['days']; ?> ليالي</td>
                    <td><?= number_format($row['total']); ?> درهم</td>
                </tr>
            <?php endwhile; ?>
        </tbody>
    </table>
</div>

<?php
$daily_stmt->close();
$monthly_stmt->close();
$conn->close();
?>

