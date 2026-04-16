<?php
// تضمين الملفات المطلوبة
require_once '../../includes/db.php';
require_once '../../includes/auth.php';

// التحقق من صلاحية الوصول - تنفيذ مباشر بدلاً من استدعاء الدالة
if (!isset($_SESSION['user_id'])) {
    // إذا لم يكن المستخدم مسجل دخول، إعادة توجيه إلى صفحة تسجيل الدخول
    header('Location: ../../login.php');
    exit;
}

// التحقق من صلاحيات المدير
if (!isset($_SESSION['user_type']) || $_SESSION['user_type'] !== 'admin') {
    // إذا لم يكن المستخدم مديراً، إعادة توجيه مع رسالة خطأ
    header('Location: ../../index.php?error=access_denied');
    exit;
}

require_once '../../includes/header.php';

// التحقق من وجود جدول الموظفين
$table_check = get_single_row($conn, "SHOW TABLES LIKE 'employees'");
if (!$table_check) {
    // إنشاء جدول الموظفين إذا لم يكن موجوداً
    $create_table = "CREATE TABLE employees (
        id INT AUTO_INCREMENT PRIMARY KEY,
        name VARCHAR(255) NOT NULL,
        basic_salary DECIMAL(10,2) DEFAULT 0.00,
        status ENUM('active', 'inactive') DEFAULT 'active',
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci";
    
    execute_query($conn, $create_table);
}

// متغيرات البيانات
$name = '';
$basic_salary = 0;
$status = 'active';

// معالجة إضافة موظف جديد
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['add_employee'])) {
    // التحقق من أن البيانات مرسلة
    $name = trim($_POST['name'] ?? '');
    $basic_salary = floatval($_POST['basic_salary'] ?? 0);
    $status = $_POST['status'] ?? 'active';

    // التحقق من صحة البيانات
    if (empty($name)) {
        $error_message = "يرجى إدخال اسم الموظف";
    } elseif (strlen($name) > 255) {
        $error_message = "اسم الموظف طويل جداً";
    } else {
        try {
            // إضافة الموظف الجديد
            $query = "INSERT INTO employees (name, basic_salary, status) VALUES (?, ?, ?)";
            $params = [$name, $basic_salary, $status];
            $types = "sds";
            
            if (execute_query($conn, $query, $params, $types)) {
                $success_message = "تم إضافة الموظف بنجاح";
                
                // إعادة تعيين القيم بعد الإضافة الناجحة
                $name = '';
                $basic_salary = 0;
                $status = 'active';
            } else {
                $error_message = "خطأ في إضافة الموظف";
            }
        } catch (Exception $e) {
            $error_message = "حدث خطأ أثناء إضافة الموظف: " . $e->getMessage();
        }
    }
}

// معالجة حذف موظف
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['delete_employee'])) {
    $employee_id = intval($_POST['employee_id'] ?? 0);
    
    if ($employee_id > 0) {
        try {
            // التحقق من وجود الموظف
            $employee = get_single_row($conn, "SELECT * FROM employees WHERE id = ?", [$employee_id], "i");
            
            if ($employee) {
                // حذف الموظف
                if (execute_query($conn, "DELETE FROM employees WHERE id = ?", [$employee_id], "i")) {
                    $success_message = "تم حذف الموظف بنجاح";
                } else {
                    $error_message = "خطأ في حذف الموظف";
                }
            } else {
                $error_message = "الموظف غير موجود";
            }
        } catch (Exception $e) {
            $error_message = "حدث خطأ أثناء حذف الموظف: " . $e->getMessage();
        }
    } else {
        $error_message = "معرف الموظف غير صحيح";
    }
}

// معالجة تعديل موظف
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['edit_employee'])) {
    $employee_id = intval($_POST['employee_id'] ?? 0);
    $name = trim($_POST['name'] ?? '');
    $basic_salary = floatval($_POST['basic_salary'] ?? 0);
    $status = $_POST['status'] ?? 'active';

    if ($employee_id > 0) {
        if (empty($name)) {
            $error_message = "يرجى إدخال اسم الموظف";
        } elseif (strlen($name) > 255) {
            $error_message = "اسم الموظف طويل جداً";
        } else {
            try {
                // تعديل الموظف
                $query = "UPDATE employees SET name = ?, basic_salary = ?, status = ? WHERE id = ?";
                $params = [$name, $basic_salary, $status, $employee_id];
                $types = "sdsi";
                
                if (execute_query($conn, $query, $params, $types)) {
                    $success_message = "تم تعديل الموظف بنجاح";
                } else {
                    $error_message = "خطأ في تعديل الموظف";
                }
            } catch (Exception $e) {
                $error_message = "حدث خطأ أثناء تعديل الموظف: " . $e->getMessage();
            }
        }
    } else {
        $error_message = "معرف الموظف غير صحيح";
    }
}

// جلب قائمة الموظفين المحدثة
$employees = get_all_rows($conn, "SELECT * FROM employees ORDER BY id DESC");
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
            <i class="fas fa-check-circle me-2"></i><?= htmlspecialchars($success_message) ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <?php if (isset($error_message)): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="fas fa-exclamation-circle me-2"></i><?= htmlspecialchars($error_message) ?>
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
                    <form method="POST" id="addEmployeeForm" novalidate>
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label for="name" class="form-label">اسم الموظف <span class="text-danger">*</span></label>
                                <input type="text" class="form-control" id="name" name="name" value="<?= htmlspecialchars($name) ?>" required maxlength="255">
                                <div class="invalid-feedback">
                                    يرجى إدخال اسم الموظف
                                </div>
                            </div>
                            <div class="col-md-4 mb-3">
                                <label for="basic_salary" class="form-label">الراتب الأساسي</label>
                                <input type="number" step="0.01" class="form-control" id="basic_salary" name="basic_salary" value="<?= htmlspecialchars($basic_salary) ?>" min="0">
                                <div class="form-text">بالريال اليمني</div>
                            </div>
                            <div class="col-md-2 mb-3">
                                <label for="status" class="form-label">الحالة</label>
                                <select class="form-select" id="status" name="status">
                                    <option value="active" <?= $status === 'active' ? 'selected' : '' ?>>نشط</option>
                                    <option value="inactive" <?= $status === 'inactive' ? 'selected' : '' ?>>غير نشط</option>
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
                    <?php if (!empty($employees)): ?>
                        <div class="table-responsive">
                            <table class="table table-striped table-hover" id="employeesTable">
                                <thead class="table-dark">
                                    <tr>
                                        <th width="10%">#</th>
                                        <th width="30%">الاسم</th>
                                        <th width="20%">الراتب الأساسي</th>
                                        <th width="15%">الحالة</th>
                                        <th width="15%">تاريخ الإضافة</th>
                                        <th width="10%">الإجراءات</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <?php foreach ($employees as $employee): ?>
                                        <tr data-employee-id="<?= $employee['id'] ?>">
                                            <td><?= htmlspecialchars($employee['id']) ?></td>
                                            <td><?= htmlspecialchars($employee['name']) ?></td>
                                            <td><?= number_format($employee['basic_salary'], 2) ?> ريال</td>
                                            <td>
                                                <span class="badge bg-<?= $employee['status'] === 'active' ? 'success' : 'secondary' ?>">
                                                    <?= $employee['status'] === 'active' ? 'نشط' : 'غير نشط' ?>
                                                </span>
                                            </td>
                                            <td><?= date('Y-m-d H:i', strtotime($employee['created_at'])) ?></td>
                                            <td>
                                                <div class="btn-group btn-group-sm" role="group">
                                                    <button type="button" class="btn btn-warning edit-employee" 
                                                            data-id="<?= $employee['id'] ?>" 
                                                            data-name="<?= htmlspecialchars($employee['name']) ?>"
                                                            data-salary="<?= $employee['basic_salary'] ?>"
                                                            data-status="<?= $employee['status'] ?>"
                                                            title="تعديل الموظف">
                                                        <i class="fas fa-edit"></i>
                                                    </button>
                                                    <button type="button" class="btn btn-danger delete-employee" 
                                                            data-id="<?= $employee['id'] ?>" 
                                                            data-name="<?= htmlspecialchars($employee['name']) ?>"
                                                            title="حذف الموظف">
                                                        <i class="fas fa-trash"></i>
                                                    </button>
                                                </div>
                                            </td>
                                        </tr>
                                    <?php endforeach; ?>
                                </tbody>
                            </table>
                        </div>
                    <?php else: ?>
                        <div class="text-center py-5" id="noEmployeesMessage">
                            <i class="fas fa-users fa-3x text-muted mb-3"></i>
                            <h5 class="text-muted">لا توجد موظفين مسجلين</h5>
                            <p class="text-muted">يمكنك إضافة موظف جديد باستخدام النموذج أعلاه</p>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>
</div>

<!-- مودال حذف الموظف -->
<div class="modal fade" id="deleteEmployeeModal" tabindex="-1" aria-labelledby="deleteEmployeeModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="deleteEmployeeModalLabel">تأكيد الحذف</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <div class="modal-body">
                هل أنت متأكد من أنك تريد حذف الموظف <strong id="deleteEmployeeName"></strong>؟
                <br><br>
                <div class="alert alert-warning">
                    <i class="fas fa-exclamation-triangle me-2"></i>
                    تحذير: هذا الإجراء لا يمكن التراجع عنه
                </div>
            </div>
            <div class="modal-footer">
                <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إلغاء</button>
                <form id="deleteEmployeeForm" method="POST" class="d-inline">
                    <input type="hidden" name="employee_id" id="deleteEmployeeId">
                    <button type="submit" name="delete_employee" class="btn btn-danger">
                        <i class="fas fa-trash me-1"></i>حذف
                    </button>
                </form>
            </div>
        </div>
    </div>
</div>

<!-- مودال تعديل الموظف -->
<div class="modal fade" id="editEmployeeModal" tabindex="-1" aria-labelledby="editEmployeeModalLabel" aria-hidden="true">
    <div class="modal-dialog">
        <div class="modal-content">
            <div class="modal-header">
                <h5 class="modal-title" id="editEmployeeModalLabel">تعديل الموظف</h5>
                <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
            </div>
            <form id="editEmployeeForm" method="POST" novalidate>
                <div class="modal-body">
                    <input type="hidden" name="employee_id" id="editEmployeeId">
                    <div class="row">
                        <div class="col-md-12 mb-3">
                            <label for="edit_name" class="form-label">اسم الموظف <span class="text-danger">*</span></label>
                            <input type="text" class="form-control" id="edit_name" name="name" required maxlength="255">
                            <div class="invalid-feedback">
                                يرجى إدخال اسم الموظف
                            </div>
                        </div>
                        <div class="col-md-6 mb-3">
                            <label for="edit_basic_salary" class="form-label">الراتب الأساسي</label>
                            <input type="number" step="0.01" class="form-control" id="edit_basic_salary" name="basic_salary" min="0">
                            <div class="form-text">بالريال اليمني</div>
                        </div>
                        <div class="col-md-6 mb-3">
                            <label for="edit_status" class="form-label">الحالة</label>
                            <select class="form-select" id="edit_status" name="status">
                                <option value="active">نشط</option>
                                <option value="inactive">غير نشط</option>
                            </select>
                        </div>
                    </div>
                </div>
                <div class="modal-footer">
                    <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إلغاء</button>
                    <button type="submit" name="edit_employee" class="btn btn-primary">
                        <i class="fas fa-save me-1"></i>حفظ التعديلات
                    </button>
                </div>
            </form>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // التحقق من صحة النموذج
    const addForm = document.getElementById('addEmployeeForm');
    const editForm = document.getElementById('editEmployeeForm');
    
    // معالجة نموذج الإضافة
    if (addForm) {
        const nameInput = addForm.querySelector('#name');
        const salaryInput = addForm.querySelector('#basic_salary');
        
        addForm.addEventListener('submit', function(e) {
            let isValid = true;
            
            // التحقق من الاسم
            if (nameInput.value.trim() === '') {
                nameInput.classList.add('is-invalid');
                isValid = false;
            } else {
                nameInput.classList.remove('is-invalid');
                nameInput.classList.add('is-valid');
            }
            
            // التحقق من الراتب
            if (salaryInput.value && parseFloat(salaryInput.value) < 0) {
                salaryInput.classList.add('is-invalid');
                isValid = false;
            } else {
                salaryInput.classList.remove('is-invalid');
                if (salaryInput.value) {
                    salaryInput.classList.add('is-valid');
                }
            }
            
            if (!isValid) {
                e.preventDefault();
                e.stopPropagation();
            }
        });
        
        // إزالة رسائل الخطأ عند التعديل
        nameInput.addEventListener('input', function() {
            if (this.value.trim() !== '') {
                this.classList.remove('is-invalid');
                this.classList.add('is-valid');
            }
        });
        
        salaryInput.addEventListener('input', function() {
            if (this.value && parseFloat(this.value) >= 0) {
                this.classList.remove('is-invalid');
                this.classList.add('is-valid');
            }
        });
    }
    
    // معالجة نموذج التعديل
    if (editForm) {
        const editNameInput = editForm.querySelector('#edit_name');
        const editSalaryInput = editForm.querySelector('#edit_basic_salary');
        
        editForm.addEventListener('submit', function(e) {
            let isValid = true;
            
            // التحقق من الاسم
            if (editNameInput.value.trim() === '') {
                editNameInput.classList.add('is-invalid');
                isValid = false;
            } else {
                editNameInput.classList.remove('is-invalid');
                editNameInput.classList.add('is-valid');
            }
            
            // التحقق من الراتب
            if (editSalaryInput.value && parseFloat(editSalaryInput.value) < 0) {
                editSalaryInput.classList.add('is-invalid');
                isValid = false;
            } else {
                editSalaryInput.classList.remove('is-invalid');
                if (editSalaryInput.value) {
                    editSalaryInput.classList.add('is-valid');
                }
            }
            
            if (!isValid) {
                e.preventDefault();
                e.stopPropagation();
            }
        });
        
        // إزالة رسائل الخطأ عند التعديل
        editNameInput.addEventListener('input', function() {
            if (this.value.trim() !== '') {
                this.classList.remove('is-invalid');
                this.classList.add('is-valid');
            }
        });
        
        editSalaryInput.addEventListener('input', function() {
            if (this.value && parseFloat(this.value) >= 0) {
                this.classList.remove('is-invalid');
                this.classList.add('is-valid');
            }
        });
    }
    
    // معالجة حذف الموظف
    const deleteButtons = document.querySelectorAll('.delete-employee');
    const deleteModal = document.getElementById('deleteEmployeeModal');
    const deleteEmployeeName = document.getElementById('deleteEmployeeName');
    const deleteEmployeeId = document.getElementById('deleteEmployeeId');
    
    if (deleteButtons.length > 0 && deleteModal) {
        deleteButtons.forEach(button => {
            button.addEventListener('click', function() {
                const id = this.getAttribute('data-id');
                const name = this.getAttribute('data-name');
                
                if (deleteEmployeeName) deleteEmployeeName.textContent = name;
                if (deleteEmployeeId) deleteEmployeeId.value = id;
                
                const modal = new bootstrap.Modal(deleteModal);
                modal.show();
            });
        });
    }
    
    // معالجة تعديل الموظف
    const editButtons = document.querySelectorAll('.edit-employee');
    const editModal = document.getElementById('editEmployeeModal');
    const editEmployeeId = document.getElementById('editEmployeeId');
    const editName = document.getElementById('edit_name');
    const editSalary = document.getElementById('edit_basic_salary');
    const editStatus = document.getElementById('edit_status');
    
    if (editButtons.length > 0 && editModal) {
        editButtons.forEach(button => {
            button.addEventListener('click', function() {
                const id = this.getAttribute('data-id');
                const name = this.getAttribute('data-name');
                const salary = this.getAttribute('data-salary');
                const status = this.getAttribute('data-status');
                
                if (editEmployeeId) editEmployeeId.value = id;
                if (editName) editName.value = name;
                if (editSalary) editSalary.value = salary;
                if (editStatus) editStatus.value = status;
                
                const modal = new bootstrap.Modal(editModal);
                modal.show();
            });
        });
    }
    
    // إخفاء رسائل التنبيه تلقائياً
    const alerts = document.querySelectorAll('.alert');
    alerts.forEach(alert => {
        setTimeout(() => {
            if (alert.classList.contains('show')) {
                alert.classList.remove('show');
                setTimeout(() => {
                    if (alert.parentNode) {
                        alert.parentNode.removeChild(alert);
                    }
                }, 150);
            }
        }, 5000);
    });
    
    // التمرير إلى الأعلى عند وجود رسائل خطأ
    const errorMessages = document.querySelectorAll('.alert-danger');
    if (errorMessages.length > 0) {
        window.scrollTo({
            top: 0,
            behavior: 'smooth'
        });
    }
});
</script>

<?php include_once '../../includes/footer.php'; ?>

