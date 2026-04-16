<?php
include_once '../../includes/db.php';
//include_once '../../includes/header.php';

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// تحديد التواريخ الافتراضية (الشهر الحالي)
$start_date = isset($_GET['start_date']) ? $_GET['start_date'] : date('Y-m-01');
$end_date = isset($_GET['end_date']) ? $_GET['end_date'] : date('Y-m-t');
$room_number = isset($_GET['room_number']) ? $_GET['room_number'] : null;

// استعلام الإيرادات المعدل
$revenue_query = "
    SELECT 
        p.payment_id,
        p.booking_id,
        b.room_number,  -- الحصول على رقم الغرفة من جدول الحجوزات
        p.amount,
        p.payment_date,
        p.payment_method,
        p.notes
    FROM payment p
    JOIN bookings b ON p.booking_id = b.booking_id  -- الربط مع جدول الحجوزات
    WHERE DATE(p.payment_date) BETWEEN ? AND ?
    " . ($room_number ? " AND b.room_number = ?" : "") . "  -- التصفية حسب رقم الغرفة
    ORDER BY p.payment_date DESC
";

$stmt = $conn->prepare($revenue_query);
if (!$stmt) {
    die("خطأ في تحضير استعلام الإيرادات: " . $conn->error);
}

if ($room_number) {
    $stmt->bind_param("ssi", $start_date, $end_date, $room_number);
} else {
    $stmt->bind_param("ss", $start_date, $end_date);
}

$stmt->execute();
$result = $stmt->get_result();

// حساب الإجمالي
$total_revenue = 0;
$payments = [];
while ($row = $result->fetch_assoc()) {
    $total_revenue += $row['amount'];
    $payments[] = $row;
}
?>

<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title> تقرير الايرادت</title>
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        /* تصميم عام للصفحة */
body {
    background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
    font-family: 'Segoe UI', Tahoma, Arial, sans-serif;
    direction: rtl;
    min-height: 100vh;
}

/* تصميم رأس التقرير */
.report-header {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    padding: 20px;
    border-radius: 15px;
    margin-bottom: 25px;
    text-align: center;
    box-shadow: 0 8px 25px rgba(0,0,0,0.1);
}

.report-header h2 {
    margin-bottom: 10px;
    font-weight: 700;
    text-shadow: 0 2px 4px rgba(0,0,0,0.3);
}

.report-header p {
    margin-bottom: 0;
    opacity: 0.9;
    font-size: 1.1rem;
}

/* تصميم بطاقة التصفية */
.filter-card {
    margin-bottom: 20px;
}

.filter-card .form-label {
    font-weight: bold;
    margin-bottom: 5px;
    color: #495057;
}

.filter-card .form-control {
    border-radius: 6px;
    border: 1px solid #ced4da;
    transition: border-color 0.15s ease-in-out, box-shadow 0.15s ease-in-out;
}

.filter-card .form-control:focus {
    border-color: #86b7fe;
    box-shadow: 0 0 0 0.25rem rgba(13, 110, 253, 0.25);
}

.filter-card .btn {
    border-radius: 6px;
    font-weight: 500;
    transition: all 0.15s ease-in-out;
}

.filter-card .btn:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 8px rgba(0,0,0,0.1);
}

/* تصميم الجدول */
.table-responsive {
    overflow-x: auto;
    -webkit-overflow-scrolling: touch;
}

.table {
    margin-bottom: 0;
    min-width: 600px; /* الحد الأدنى لعرض الجدول */
}

.table th,
.table td {
    padding: 8px 12px;
    font-size: 14px;
    text-align: center;
    vertical-align: middle;
    white-space: nowrap;
}

.table th {
    background-color: #f8f9fa;
    font-weight: bold;
    border-bottom: 2px solid #dee2e6;
    position: sticky;
    top: 0;
    z-index: 10;
}

.table tbody tr:hover {
    background-color: #f5f5f5;
}

/* تصميم صف الإجمالي */
.total-row {
    font-weight: bold;
    background-color: #e9ecef;
}

/* تصميم الأزرار */
.btn {
    margin: 5px;
    font-size: 14px;
    border-radius: 6px;
    font-weight: 500;
    transition: all 0.15s ease-in-out;
    border: none;
}

.btn:hover {
    transform: translateY(-1px);
    box-shadow: 0 4px 8px rgba(0,0,0,0.1);
}

.btn-primary {
    background: linear-gradient(135deg, #0d6efd 0%, #0b5ed7 100%);
}

.btn-secondary {
    background: linear-gradient(135deg, #6c757d 0%, #5a6268 100%);
}

/* تصميم رسالة عدم وجود بيانات */
.no-data {
    text-align: center;
    color: #6c757d;
    font-style: italic;
    padding: 40px 20px;
}

/* تحسين تصميم البطاقات */
.card {
    border: none;
    border-radius: 10px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    transition: box-shadow 0.15s ease-in-out;
}

.card:hover {
    box-shadow: 0 4px 20px rgba(0,0,0,0.15);
}

.card-header {
    border-radius: 10px 10px 0 0 !important;
    border-bottom: none;
    font-weight: 600;
}

/* تصميم متجاوب للشاشات الصغيرة */
@media (max-width: 768px) {
    .container {
        padding: 10px;
    }

    .report-header {
        padding: 10px;
        margin-bottom: 15px;
    }

    .report-header h2 {
        font-size: 1.5rem;
    }

    .card-header h4 {
        font-size: 1.2rem;
    }

    .table th,
    .table td {
        padding: 6px 8px;
        font-size: 12px;
    }

    .btn {
        font-size: 12px;
        padding: 8px 12px;
    }

    /* إخفاء بعض الأعمدة في الشاشات الصغيرة */
    .table th:nth-child(2),
    .table td:nth-child(2),
    .table th:nth-child(8),
    .table td:nth-child(8) {
        display: none;
    }
}

@media (max-width: 576px) {
    .table {
        min-width: 400px;
    }

    .table th,
    .table td {
        padding: 4px 6px;
        font-size: 11px;
    }

    /* إخفاء المزيد من الأعمدة في الشاشات الأصغر */
    .table th:nth-child(7),
    .table td:nth-child(7) {
        display: none;
    }

    .report-header h2 {
        font-size: 1.3rem;
    }

    .card-header h4 {
        font-size: 1rem;
    }
}

/* تصميم خاص للطباعة */
@media print {
    body {
        font-size: 12px;
        direction: rtl;
    }

    .report-header {
        background-color: #0d6efd !important;
        color: white !important;
        padding: 10px;
        border-radius: 5px;
        margin-bottom: 15px;
        text-align: center;
    }

    .table {
        width: 100%;
        border-collapse: collapse;
        min-width: auto;
    }

    .table th,
    .table td {
        padding: 6px;
        font-size: 10px;
        text-align: center;
        border: 1px solid #ddd !important;
        white-space: normal;
    }

    .table th {
        background-color: #f1f1f1 !important;
        font-weight: bold;
    }

    .total-row {
        font-weight: bold;
        background-color: #e9ecef !important;
    }

    .no-print {
        display: none !important;
    }

    /* إظهار جميع الأعمدة في الطباعة */
    .table th,
    .table td {
        display: table-cell !important;
    }
}

/* تصميم صفحة التصدير */
.export-container {
    max-width: 800px;
    margin: 0 auto;
    padding: 20px;
    background-color: #ffffff;
    border: 1px solid #ddd;
    border-radius: 5px;
}

.export-container h2 {
    text-align: center;
    color: #0d6efd;
    margin-bottom: 20px;
}

.export-container .btn {
    width: 100%;
    padding: 10px;
    margin: 10px 0;
    background-color: #0d6efd;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
}

.export-container .btn:hover {
    background-color: #0b5ed7;
}


    </style>
</head>
<body>
    <div class="container py-4">
        <div class="report-header text-center">
            <h2>تقرير الإيرادات الشامل</h2>
            <p>تاريخ التقرير: <?php echo date('Y-m-d'); ?></p>
        </div>

        <!-- بطاقة تصفية التواريخ ورقم الغرفة -->
        <div class="card filter-card no-print">
            <div class="card-header bg-info text-white">
                <h4>تصفية حسب التاريخ ورقم الغرفة</h4>
            </div>
            <div class="card-body">
                <form method="GET" class="row g-3">
                    <div class="col-lg-3 col-md-6 col-sm-6">
                        <label for="start_date" class="form-label">
                            <i class="fas fa-calendar-alt me-1"></i>من تاريخ
                        </label>
                        <input type="date" id="start_date" name="start_date"
                               class="form-control" value="<?php echo $start_date; ?>">
                    </div>
                    <div class="col-lg-3 col-md-6 col-sm-6">
                        <label for="end_date" class="form-label">
                            <i class="fas fa-calendar-alt me-1"></i>إلى تاريخ
                        </label>
                        <input type="date" id="end_date" name="end_date"
                               class="form-control" value="<?php echo $end_date; ?>">
                    </div>
                    <div class="col-lg-3 col-md-6 col-sm-6">
                        <label for="room_number" class="form-label">
                            <i class="fas fa-door-open me-1"></i>رقم الغرفة
                        </label>
                        <input type="number" id="room_number" name="room_number"
                               class="form-control" value="<?php echo $room_number; ?>"
                               placeholder="اختياري">
                    </div>
                    <div class="col-lg-3 col-md-6 col-sm-6 d-flex align-items-end">
                        <button type="submit" class="btn btn-primary w-100">
                            <i class="fas fa-search me-1"></i>تطبيق التصفية
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <div class="card">
            <div class="card-header bg-success text-white">
                <h4>تفاصيل الإيرادات</h4>
                <p>
                    <?php if ($room_number): ?>
                        للغرفة رقم: <?php echo $room_number; ?> 
                    <?php endif; ?>
                    من <?php echo $start_date; ?> إلى <?php echo $end_date; ?>
                </p>
            </div>
            <div class="card-body">
                <div class="table-responsive">
                    <table class="table table-hover table-striped">
                        <thead class="table-dark">
                            <tr>
                                <th scope="col">
                                    <i class="fas fa-hashtag me-1"></i>#
                                </th>
                                <th scope="col">
                                    <i class="fas fa-receipt me-1"></i>رقم الدفعة
                                </th>
                                <th scope="col">
                                    <i class="fas fa-bookmark me-1"></i>رقم الحجز
                                </th>
                                <th scope="col">
                                    <i class="fas fa-door-open me-1"></i>رقم الغرفة
                                </th>
                                <th scope="col">
                                    <i class="fas fa-money-bill-wave me-1"></i>المبلغ
                                </th>
                                <th scope="col">
                                    <i class="fas fa-calendar me-1"></i>تاريخ الدفعة
                                </th>
                                <th scope="col">
                                    <i class="fas fa-credit-card me-1"></i>طريقة الدفع
                                </th>
                                <th scope="col">
                                    <i class="fas fa-sticky-note me-1"></i>ملاحظات
                                </th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php if (count($payments) > 0): ?>
                                <?php $counter = 1; ?>
                                <?php foreach ($payments as $payment): ?>
                                    <tr>
                                        <td><?php echo $counter++; ?></td>
                                        <td><?php echo htmlspecialchars($payment['payment_id']); ?></td>
                                        <td><?php echo htmlspecialchars($payment['booking_id']); ?></td>
                                        <td><?php echo htmlspecialchars($payment['room_number']); ?></td>
                                        <td><?php echo number_format($payment['amount'], 0); ?></td>
                                        <td><?php echo htmlspecialchars($payment['payment_date']); ?></td>
                                        <td><?php echo htmlspecialchars($payment['payment_method']); ?></td>
                                        <td><?php echo htmlspecialchars($payment['notes'] ?? '-'); ?></td>
                                    </tr>
                                <?php endforeach; ?>
                                <tr class="table-success fw-bold">
                                    <td colspan="4" class="text-end fs-5">
                                        <i class="fas fa-calculator me-2"></i>إجمالي الإيرادات:
                                    </td>
                                    <td class="fs-5 text-success">
                                        <i class="fas fa-coins me-1"></i><?php echo number_format($total_revenue, 0); ?> ريال
                                    </td>
                                    <td colspan="3"></td>
                                </tr>
                            <?php else: ?>
                                <tr>
                                    <td colspan="8" class="text-center text-muted">لا توجد دفعات مسجلة في هذه الفترة</td>
                                </tr>
                            <?php endif; ?>
                        </tbody>
                    </table>
                </div>
            </div>
        </div>

        <div class="mt-4 text-center no-print">
            <div class="d-flex flex-wrap justify-content-center gap-2">
                <button onclick="window.print()" class="btn btn-primary btn-lg">
                    <i class="fas fa-print me-2"></i>طباعة التقرير
                </button>
                <a href="export_excel.php?start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?><?php echo $room_number ? '&room_number='.$room_number : ''; ?>"
                   class="btn btn-success btn-lg">
                    <i class="fas fa-file-excel me-2"></i>تصدير Excel
                </a>
                <a href="export_pdf.php?start_date=<?php echo $start_date; ?>&end_date=<?php echo $end_date; ?><?php echo $room_number ? '&room_number='.$room_number : ''; ?>"
                   class="btn btn-danger btn-lg">
                    <i class="fas fa-file-pdf me-2"></i>تصدير PDF
                </a>
                <a href="../dash.php" class="btn btn-secondary btn-lg">
                    <i class="fas fa-arrow-right me-2"></i>العودة للوحة التحكم
                </a>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script src="https://kit.fontawesome.com/a076d05399.js" crossorigin="anonymous"></script>
    <script>
        // التأكد من أن تاريخ البداية لا يتجاوز تاريخ النهاية
        document.getElementById('start_date').addEventListener('change', function() {
            const startDate = new Date(this.value);
            const endDateInput = document.getElementById('end_date');
            
            if (endDateInput.value) {
                const endDate = new Date(endDateInput.value);
                if (startDate > endDate) {
                    alert('تاريخ البداية لا يمكن أن يكون بعد تاريخ النهاية');
                    this.value = '<?php echo $start_date; ?>';
                }
            }
        });

        document.getElementById('end_date').addEventListener('change', function() {
            const startDateInput = document.getElementById('start_date');
            if (!startDateInput.value) {
                alert('الرجاء تحديد تاريخ البداية أولاً');
                this.value = '<?php echo $end_date; ?>';
                return;
            }

            const startDate = new Date(startDateInput.value);
            const endDate = new Date(this.value);
            
            if (endDate < startDate) {
                alert('تاريخ النهاية لا يمكن أن يكون قبل تاريخ البداية');
                this.value = '<?php echo $end_date; ?>';
            }
        });
    </script>
</body>
</html>

<?php
// إغلاق الاتصال
$stmt->close();
$conn->close();
?>
