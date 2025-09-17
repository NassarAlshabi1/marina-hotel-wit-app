<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';

// استعلام لسحب بيانات الحجوزات
$query = "SELECT 
            b.booking_id,
            b.guest_id,
            b.room_number,
            DATE_FORMAT(b.checkin_date, '%d/%m/%Y') as checkin_date,
            DATE_FORMAT(b.checkout_date, '%d/%m/%Y') as checkout_date,
            b.status,
            b.notes,
            g.guest_name,
            g.phone
          FROM bookings b
          LEFT JOIN guests g ON b.guest_id = g.guest_id
          ORDER BY b.checkin_date DESC";

$result = $conn->query($query);

if (!$result) {
    die("حدث خطأ في جلب البيانات: " . $conn->error);
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>نظام إدارة الحجوزات الفندقية</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <style>
        body {
            font-family: 'Tahoma', Arial, sans-serif;
            background-color: #f8f9fa;
        }
        .header {
            background-color: #2c3e50;
            color: white;
            padding: 15px 0;
            margin-bottom: 30px;
        }
        .card {
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
        }
        .card-header {
            background-color: #3498db;
            color: white;
            border-radius: 10px 10px 0 0 !important;
        }
        .status-reserved {
            background-color: #f39c12;
            color: white;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 14px;
        }
        .status-available {
            background-color: #2ecc71;
            color: white;
            padding: 3px 8px;
            border-radius: 4px;
            font-size: 14px;
        }
        .action-btn {
            margin: 0 3px;
            font-size: 14px;
        }
    </style>
</head>
<body>
    <div class="header">
        <div class="container">
            <h2>نظام إدارة الحجوزات الفندقية</h2>
        </div>
    </div>

    <div class="container">
        <div class="card">
            <div class="card-header d-flex justify-content-between align-items-center">
                <h4 class="mb-0">قائمة الحجوزات الحالية</h4>
                <a href="create.php" class="btn btn-light">
                    <i class="fas fa-plus"></i> إضافة حجز جديد
                </a>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-striped table-hover">
                        <thead class="table-dark">
                            <tr>
                                <th>رقم الحجز</th>
                                <th>اسم النزيل</th>
                                <th>الهاتف</th>
                                <th>رقم الغرفة</th>
                                <th>تاريخ الوصول</th>
                                <th>تاريخ المغادرة</th>
                                <th>الحالة</th>
                                <th>إجراءات</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if ($result->num_rows > 0): ?>
                                <?php while ($row = $result->fetch_assoc()): ?>
                                    <tr>
                                        <td><?= $row['booking_id'] ?></td>
                                        <td><?= htmlspecialchars($row['guest_name'] ?? 'غير معروف') ?></td>
                                        <td><?= htmlspecialchars($row['phone'] ?? '---') ?></td>
                                        <td><?= $row['room_number'] ?></td>
                                        <td><?= $row['checkin_date'] ?></td>
                                        <td><?= $row['checkout_date'] ?? '---' ?></td>
                                        <td>
                                            <?php if ($row['status'] == 'محجوزة'): ?>
                                                <span class="status-reserved">محجوزة</span>
                                            <?php else: ?>
                                                <span class="status-available">شاغرة</span>
                                            <?php endif; ?>
                                        </td>
                                        <td>
                                            <div class="btn-group">
                                                <a href="view.php?id=<?= $row['booking_id'] ?>" 
                                                   class="btn btn-sm btn-info action-btn" title="عرض">
                                                    <i class="fas fa-eye"></i>
                                                </a>
                                                <a href="edit.php?id=<?= $row['booking_id'] ?>" 
                                                   class="btn btn-sm btn-warning action-btn" title="تعديل">
                                                    <i class="fas fa-edit"></i>
                                                </a>
                                                <?php if ($row['status'] == 'محجوزة'): ?>
                                                    <a href="checkout.php?id=<?= $row['booking_id'] ?>" 
                                                       class="btn btn-sm btn-success action-btn" title="تسجيل المغادرة">
                                                        <i class="fas fa-door-open"></i>
                                                    </a>
                                                <?php endif; ?>
                                            </div>
                                        </td>
                                    </tr>
                                <?php endwhile; ?>
                            <?php else: ?>
                                <tr>
                                    <td colspan="8" class="text-center">لا توجد حجوزات مسجلة حالياً</td>
                                </tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/js/all.min.js"></script>
</body>
</html>
