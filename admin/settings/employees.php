<?php
include_once '../../includes/db.php';
include_once '../../includes/functions.php';
include_once '../../includes/security.php';

$message = '';

// معالجة إضافة موظف جديد
if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['add_employee'])) {
    // التحقق من رمز CSRF
    verify_csrf_token();

    $name = trim($_POST['name']);
    $position = trim($_POST['position']);
    $salary = (float)$_POST['salary'];
    $phone = trim($_POST['phone']);
    $hire_date = $_POST['hire_date'];
    $status = $_POST['status'];

    if (!empty($name) && !empty($position) && $salary > 0) {
        $stmt = $conn->prepare("INSERT INTO employees (name, position, salary, phone, hire_date, status) VALUES (?, ?, ?, ?, ?, ?)");
        $stmt->bind_param("ssdsss", $name, $position, $salary, $phone, $hire_date, $status);
        
        if ($stmt->execute()) {
            $message = "<div class='alert alert-success'><i class='fas fa-check-circle me-2'></i>تم إضافة الموظف بنجاح</div>";
        } else {
            $message = "<div class='alert alert-danger'><i class='fas fa-exclamation-circle me-2'></i>حدث خطأ: " . htmlspecialchars($conn->error) . "</div>";
        }
    } else {
        $message = "<div class='alert alert-danger'><i class='fas fa-exclamation-circle me-2'></i>يرجى تعبئة جميع الحقول المطلوبة والتأكد من أن الراتب أكبر من صفر</div>";
    }
}

// معالجة تحديث حالة الموظف
if ($_SERVER["REQUEST_METHOD"] == "POST" && isset($_POST['update_status'])) {
    // التحقق من رمز CSRF
    verify_csrf_token();

    $employee_id = (int)$_POST['employee_id'];
    $new_status = $_POST['new_status'];
    
    if (!empty($new_status)) {
        $stmt = $conn->prepare("UPDATE employees SET status = ? WHERE id = ?");
        $stmt->bind_param("si", $new_status, $employee_id);
        
        if ($stmt->execute()) {
            $message = "<div class='alert alert-success'><i class='fas fa-check-circle me-2'></i>تم تحديث حالة الموظف بنجاح</div>";
        } else {
            $message = "<div class='alert alert-danger'><i class='fas fa-exclamation-circle me-2'></i>حدث خطأ في التحديث</div>";
        }
    }
}

// جلب قائمة الموظفين
$employees_query = "SELECT * FROM employees ORDER BY name";
$employees_result = $conn->query($employees_query);

// تضمين الهيدر
include_once '../../includes/header.php';
?>

<style>
    .status-active {
        color: #28a745;
        font-weight: bold;
    }
    .status-inactive {
        color: #ffc107;
        font-weight: bold;
    }
    .status-terminated {
        color: #dc3545;
        font-weight: bold;
    }
</style>

<div class="container py-4">
    <div class="d-flex justify-content-between align-items-center mb-4">
        <h2><i class="fas fa-user-tie me-2"></i>إدارة الموظفين</h2>
        <a href="../dash.php" class="btn btn-outline-primary">
            <i class="fas fa-arrow-right me-1"></i> العودة للوحة التحكم
        </a>
    </div>

    <?= $message ?>

    <!-- نموذج إضافة موظف جديد -->
    <div class="card mb-4">
        <div class="card-header bg-primary text-white">
            <h5 class="mb-0"><i class="fas fa-user-plus me-2"></i>إضافة موظف جديد</h5>
        </div>
        <div class="card-body">
            <form method="post">
                <?= csrf_field(); ?>
                <div class="row">
                    <div class="col-md-4">
                        <label class="form-label fw-bold">اسم الموظف *</label>
                        <input type="text" name="name" class="form-control" required placeholder="أدخل اسم الموظف">
                    </div>
                    <div class="col-md-4">
                        <label class="form-label fw-bold">المنصب *</label>
                        <input type="text" name="position" class="form-control" required placeholder="أدخل المنصب">
                    </div>
                    <div class="col-md-4">
                        <label class="form-label fw-bold">الراتب *</label>
                        <input type="number" name="salary" class="form-control" required placeholder="0.00" step="0.01" min="0.01">
                    </div>
                </div>
                <div class="row mt-3">
                    <div class="col-md-4">
                        <label class="form-label fw-bold">رقم الهاتف</label>
                        <input type="text" name="phone" class="form-control" placeholder="رقم الهاتف">
                    </div>
                    <div class="col-md-4">
                        <label class="form-label fw-bold">تاريخ التوظيف</label>
                        <input type="date" name="hire_date" class="form-control" value="<?= date('Y-m-d') ?>">
                    </div>
                    <div class="col-md-4">
                        <label class="form-label fw-bold">الحالة</label>
                        <select name="status" class="form-select">
                            <option value="active">نشط</option>
                            <option value="inactive">غير نشط</option>
                            <option value="terminated">منتهي الخدمة</option>
                        </select>
                    </div>
                </div>
                <div class="text-center mt-4">
                    <button type="submit" name="add_employee" class="btn btn-success">
                        <i class="fas fa-save me-1"></i> حفظ الموظف
                    </button>
                </div>
            </form>
        </div>
    </div>

    <!-- قائمة الموظفين -->
    <div class="card">
        <div class="card-header bg-info text-white">
            <h5 class="mb-0"><i class="fas fa-users me-2"></i>قائمة الموظفين</h5>
        </div>
        <div class="card-body">
            <?php if ($employees_result && $employees_result->num_rows > 0): ?>
                <div class="table-responsive">
                    <table class="table table-hover">
                        <thead>
                            <tr>
                                <th>#</th>
                                <th>الاسم</th>
                                <th>المنصب</th>
                                <th>الراتب</th>
                                <th>الهاتف</th>
                                <th>تاريخ التوظيف</th>
                                <th>الحالة</th>
                                <th>الإجراءات</th>
                            </tr>
                        </thead>
                        <tbody>
                            <?php 
                            $counter = 1;
                            while ($employee = $employees_result->fetch_assoc()): 
                            ?>
                                <tr>
                                    <td><?= $counter++ ?></td>
                                    <td><?= htmlspecialchars($employee['name']) ?></td>
                                    <td><?= htmlspecialchars($employee['position']) ?></td>
                                    <td><?= formatCurrency($employee['salary']) ?></td>
                                    <td><?= htmlspecialchars($employee['phone']) ?></td>
                                    <td><?= $employee['hire_date'] ? date('Y-m-d', strtotime($employee['hire_date'])) : '-' ?></td>
                                    <td>
                                        <span class="status-<?= $employee['status'] ?>">
                                            <?php
                                            switch($employee['status']) {
                                                case 'active': echo '<i class="fas fa-check-circle me-1"></i>نشط'; break;
                                                case 'inactive': echo '<i class="fas fa-pause-circle me-1"></i>غير نشط'; break;
                                                case 'terminated': echo '<i class="fas fa-times-circle me-1"></i>منتهي الخدمة'; break;
                                                default: echo htmlspecialchars($employee['status']);
                                            }
                                            ?>
                                        </span>
                                    </td>
                                    <td>
                                        <form method="post" style="display: inline;">
                                            <?= csrf_field(); ?>
                                            <input type="hidden" name="employee_id" value="<?= $employee['id'] ?>">
                                            <select name="new_status" onchange="this.form.submit()" class="form-select form-select-sm" style="width: auto; display: inline-block;">
                                                <option value="">تغيير الحالة</option>
                                                <option value="active" <?= $employee['status'] == 'active' ? 'selected' : '' ?>>نشط</option>
                                                <option value="inactive" <?= $employee['status'] == 'inactive' ? 'selected' : '' ?>>غير نشط</option>
                                                <option value="terminated" <?= $employee['status'] == 'terminated' ? 'selected' : '' ?>>منتهي الخدمة</option>
                                            </select>
                                            <input type="hidden" name="update_status" value="1">
                                        </form>
                                    </td>
                                </tr>
                            <?php endwhile; ?>
                        </tbody>
                    </table>
                </div>
            <?php else: ?>
                <div class="alert alert-info text-center">
                    <i class="fas fa-info-circle me-2"></i> لا يوجد موظفين مسجلين في النظام
                </div>
            <?php endif; ?>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
