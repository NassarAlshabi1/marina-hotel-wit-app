<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';

$message = '';

// معالجة إضافة سحب راتب جديد
if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['add_withdrawal'])) {
    $employee_id = (int)$_POST['employee_id'];
    $amount = (float)$_POST['amount'];
    $date = $_POST['date'];
    $notes = $_POST['notes'] ?? '';

    if ($employee_id > 0 && $amount > 0 && !empty($date)) {
        $stmt = $conn->prepare("INSERT INTO salary_withdrawals (employee_id, amount, date, notes) VALUES (?, ?, ?, ?)");
        $stmt->bind_param("idss", $employee_id, $amount, $date, $notes);
        
        if ($stmt->execute()) {
            $message = "<div class='alert alert-success'>تم تسجيل سحب الراتب بنجاح</div>";
        } else {
            $message = "<div class='alert alert-danger'>حدث خطأ: " . $conn->error . "</div>";
        }
    } else {
        $message = "<div class='alert alert-danger'>يرجى تعبئة جميع الحقول المطلوبة</div>";
    }
}

// جلب قائمة الموظفين
$employees_query = "SELECT id, name FROM employees WHERE status = 'active' ORDER BY name";
$employees_result = $conn->query($employees_query);

// جلب سحوبات الرواتب
$withdrawals_query = "SELECT sw.*, e.name as employee_name 
                     FROM salary_withdrawals sw 
                     JOIN employees e ON sw.employee_id = e.id 
                     ORDER BY sw.date DESC, sw.created_at DESC";
$withdrawals_result = $conn->query($withdrawals_query);
?>

<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title> تقرير سحوبات الراتب</title>
    <link href="<?= BASE_URL ?>assets/css/bootstrap.rtl.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <style>
        body {
            background-color: #f8f9fa;
            font-family: 'Tajawal', sans-serif;
        }
        .card {
            border-radius: 15px;
            box-shadow: 0 4px 6px rgba(0, 0, 0, 0.1);
            margin-bottom: 20px;
        }
        .card-header {
            border-radius: 15px 15px 0 0 !important;
            font-weight: bold;
        }
        .table th {
            background-color: #f8f9fa;
            font-weight: bold;
        }
        .btn-primary {
            background-color: #0d6efd;
            border-color: #0d6efd;
        }
        .form-label {
            font-weight: bold;
        }
    </style>
</head>
<body>
    <div class="container py-4">
        <div class="d-flex justify-content-between mb-3">
            <h2 class="text-primary fw-bold">إدارة سحوبات الرواتب</h2>
            <a href="../dashboard.php" class="btn btn-outline-primary">
                <i class="fas fa-arrow-left me-2"></i>العودة إلى لوحة التحكم
            </a>
        </div>

        <?php echo $message; ?>

        <!-- نموذج إضافة سحب راتب جديد -->
        <div class="card">
            <div class="card-header bg-primary text-white">
                <h5 class="mb-0"><i class="fas fa-plus me-2"></i>إضافة سحب راتب جديد</h5>
            </div>
            <div class="card-body">
                <form method="post">
                    <div class="row g-3">
                        <div class="col-md-3">
                            <label class="form-label">الموظف *</label>
                            <select name="employee_id" class="form-select" required>
                                <option value="">اختر الموظف</option>
                                <?php while ($employee = $employees_result->fetch_assoc()): ?>
                                    <option value="<?= $employee['id'] ?>"><?= htmlspecialchars($employee['name']) ?></option>
                                <?php endwhile; ?>
                            </select>
                        </div>
                        
                        <div class="col-md-3">
                            <label class="form-label">المبلغ *</label>
                            <input type="number" step="0.01" name="amount" class="form-control" required>
                        </div>
                        
                        <div class="col-md-3">
                            <label class="form-label">التاريخ *</label>
                            <input type="date" name="date" class="form-control" value="<?= date('Y-m-d') ?>" required>
                        </div>
                        
                        <div class="col-md-3">
                            <label class="form-label">ملاحظات</label>
                            <input type="text" name="notes" class="form-control" placeholder="ملاحظات اختيارية">
                        </div>
                    </div>
                    
                    <div class="text-center mt-3">
                        <button type="submit" name="add_withdrawal" class="btn btn-primary px-4">
                            <i class="fas fa-save me-2"></i>حفظ
                        </button>
                    </div>
                </form>
            </div>
        </div>

        <!-- جدول سحوبات الرواتب -->
        <div class="card">
            <div class="card-header bg-info text-white">
                <h5 class="mb-0"><i class="fas fa-list me-2"></i>سحوبات الرواتب</h5>
            </div>
            <div class="card-body">
                <?php if ($withdrawals_result && $withdrawals_result->num_rows > 0): ?>
                    <div class="table-responsive">
                        <table class="table table-striped table-hover">
                            <thead>
                                <tr>
                                    <th>#</th>
                                    <th>اسم الموظف</th>
                                    <th>المبلغ</th>
                                    <th>التاريخ</th>
                                    <th>الملاحظات</th>
                                    <th>تاريخ التسجيل</th>
                                </tr>
                            </thead>
                            <tbody>
                                <?php 
                                $counter = 1;
                                $total_withdrawals = 0;
                                while ($withdrawal = $withdrawals_result->fetch_assoc()): 
                                    $total_withdrawals += $withdrawal['amount'];
                                ?>
                                    <tr>
                                        <td><?= $counter++ ?></td>
                                        <td><?= htmlspecialchars($withdrawal['employee_name']) ?></td>
                                        <td class="text-success fw-bold"><?= number_format($withdrawal['amount'], 2) ?> ر.ي</td>
                                        <td><?= date('Y-m-d', strtotime($withdrawal['date'])) ?></td>
                                        <td><?= htmlspecialchars($withdrawal['notes']) ?></td>
                                        <td><?= date('Y-m-d H:i', strtotime($withdrawal['created_at'])) ?></td>
                                    </tr>
                                <?php endwhile; ?>
                            </tbody>
                            <tfoot>
                                <tr class="table-warning">
                                    <th colspan="2">إجمالي السحوبات</th>
                                    <th class="text-danger"><?= number_format($total_withdrawals, 2) ?> ر.ي</th>
                                    <th colspan="3"></th>
                                </tr>
                            </tfoot>
                        </table>
                    </div>
                <?php else: ?>
                    <div class="alert alert-info text-center">
                        <i class="fas fa-info-circle me-2"></i>لا توجد سحوبات رواتب مسجلة
                    </div>
                <?php endif; ?>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
</body>
</html>

<?php $conn->close(); ?>
