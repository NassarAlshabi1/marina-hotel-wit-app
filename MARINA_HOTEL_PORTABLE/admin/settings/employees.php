<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// إنشاء جدول الموظفين إذا لم يكن موجوداً
$create_table_sql = "
CREATE TABLE IF NOT EXISTS employees (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    position VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    email VARCHAR(255),
    salary DECIMAL(10,2) DEFAULT 0,
    hire_date DATE,
    status ENUM('نشط', 'غير نشط') DEFAULT 'نشط',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)";
$conn->query($create_table_sql);

// معالجة إضافة موظف جديد
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['add_employee'])) {
    $name = trim($_POST['name']);
    $position = trim($_POST['position']);
    $phone = trim($_POST['phone']);
    $email = trim($_POST['email']);
    $salary = floatval($_POST['salary']);
    $hire_date = $_POST['hire_date'];
    $status = $_POST['status'];
    
    if (!empty($name) && !empty($position)) {
        $stmt = $conn->prepare("INSERT INTO employees (name, position, phone, email, salary, hire_date, status) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->bind_param("ssssdss", $name, $position, $phone, $email, $salary, $hire_date, $status);
        
        if ($stmt->execute()) {
            $success_message = "تم إضافة الموظف بنجاح";
        } else {
            $error_message = "حدث خطأ أثناء إضافة الموظف";
        }
    } else {
        $error_message = "الاسم والمنصب مطلوبان";
    }
}

// معالجة حذف موظف
if (isset($_GET['delete']) && is_numeric($_GET['delete'])) {
    $id = intval($_GET['delete']);
    $stmt = $conn->prepare("DELETE FROM employees WHERE id = ?");
    $stmt->bind_param("i", $id);
    
    if ($stmt->execute()) {
        $success_message = "تم حذف الموظف بنجاح";
    } else {
        $error_message = "حدث خطأ أثناء حذف الموظف";
    }
}

// جلب قائمة الموظفين
$employees = $conn->query("SELECT * FROM employees ORDER BY name");

// تضمين الهيدر بعد انتهاء معالجة POST
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-user-tie me-2"></i>إدارة الموظفين</h2>
                <div>
                    <a href="index.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>العودة للإعدادات
                    </a>
                    <a href="../dash.php" class="btn btn-outline-primary">
                        <i class="fas fa-home me-1"></i>لوحة التحكم
                    </a>
                </div>
            </div>
        </div>
    </div>

    <?php if (isset($success_message)): ?>
        <div class="alert alert-success alert-dismissible fade show" role="alert">
            <i class="fas fa-check-circle me-2"></i><?= $success_message ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <?php if (isset($error_message)): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="fas fa-exclamation-circle me-2"></i><?= $error_message ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <!-- نموذج إضافة موظف جديد -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0"><i class="fas fa-user-plus me-2"></i>إضافة موظف جديد</h5>
                </div>
                <div class="card-body">
                    <form method="POST">
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label for="name" class="form-label">اسم الموظف *</label>
                                <input type="text" class="form-control" id="name" name="name" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="position" class="form-label">المنصب *</label>
                                <input type="text" class="form-control" id="position" name="position" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="phone" class="form-label">رقم الهاتف</label>
                                <input type="tel" class="form-control" id="phone" name="phone">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="email" class="form-label">البريد الإلكتروني</label>
                                <input type="email" class="form-control" id="email" name="email">
                            </div>
                            <div class="col-md-4 mb-3">
                                <label for="salary" class="form-label">الراتب</label>
                                <input type="number" step="0.01" class="form-control" id="salary" name="salary" value="0">
                            </div>
                            <div class="col-md-4 mb-3">
                                <label for="hire_date" class="form-label">تاريخ التوظيف</label>
                                <input type="date" class="form-control" id="hire_date" name="hire_date" value="<?= date('Y-m-d') ?>">
                            </div>
                            <div class="col-md-4 mb-3">
                                <label for="status" class="form-label">الحالة</label>
                                <select class="form-select" id="status" name="status">
                                    <option value="نشط">نشط</option>
                                    <option value="غير نشط">غير نشط</option>
                                </select>
                            </div>
                        </div>
                        <div class="text-end">
                            <button type="submit" name="add_employee" class="btn btn-primary">
                                <i class="fas fa-save me-1"></i>حفظ الموظف
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- قائمة الموظفين -->
    <div class="row">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0"><i class="fas fa-list me-2"></i>قائمة الموظفين</h5>
                </div>
                <div class="card-body">
                    <?php if ($employees->num_rows > 0): ?>
                        <div class="table-responsive">
                            <table class="table table-striped table-hover">
                                <thead class="table-dark">
                                    <tr>
                                        <th>#</th>
                                        <th>الاسم</th>
                                        <th>المنصب</th>
                                        <th>الهاتف</th>
                                        <th>البريد الإلكتروني</th>
                                        <th>الراتب</th>
                                        <th>تاريخ التوظيف</th>
                                        <th>الحالة</th>
                                        <th>الإجراءات</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php 
                                    $counter = 1;
                                    while ($employee = $employees->fetch_assoc()): 
                                    ?>
                                    <tr>
                                        <td><?= $counter++ ?></td>
                                        <td><?= htmlspecialchars($employee['name']) ?></td>
                                        <td><?= htmlspecialchars($employee['position']) ?></td>
                                        <td><?= htmlspecialchars($employee['phone']) ?></td>
                                        <td><?= htmlspecialchars($employee['email']) ?></td>
                                        <td><?= number_format($employee['salary'], 2) ?> ريال</td>
                                        <td><?= $employee['hire_date'] ?></td>
                                        <td>
                                            <span class="badge <?= $employee['status'] == 'نشط' ? 'bg-success' : 'bg-secondary' ?>">
                                                <?= $employee['status'] ?>
                                            </span>
                                        </td>
                                        <td>
                                            <div class="btn-group" role="group">
                                                <a href="edit_employee.php?id=<?= $employee['id'] ?>" 
                                                   class="btn btn-sm btn-outline-primary" title="تعديل">
                                                    <i class="fas fa-edit"></i>
                                                </a>
                                                <a href="?delete=<?= $employee['id'] ?>" 
                                                   class="btn btn-sm btn-outline-danger" 
                                                   title="حذف"
                                                   onclick="return confirm('هل أنت متأكد من حذف هذا الموظف؟')">
                                                    <i class="fas fa-trash"></i>
                                                </a>
                                            </div>
                                        </td>
                                    </tr>
                                    <?php endwhile; ?>
                                </tbody>
                            </table>
                        </div>
                    <?php else: ?>
                        <div class="text-center py-4">
                            <i class="fas fa-users fa-3x text-muted mb-3"></i>
                            <h5 class="text-muted">لا يوجد موظفين مسجلين</h5>
                            <p class="text-muted">قم بإضافة موظف جديد باستخدام النموذج أعلاه</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>

<?php include_once '../../includes/footer.php'; ?>
