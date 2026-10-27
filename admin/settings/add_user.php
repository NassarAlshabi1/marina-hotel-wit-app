<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

// إنشاء جدول المستخدمين إذا لم يكن موجوداً
$create_table_sql = "
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    email VARCHAR(255),
    phone VARCHAR(20),
    role ENUM('admin', 'manager', 'employee') DEFAULT 'employee',
    status ENUM('active', 'inactive') DEFAULT 'active',
    last_login TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
)";
$conn->query($create_table_sql);

// معالجة إضافة مستخدم جديد
if ($_SERVER['REQUEST_METHOD'] == 'POST' && isset($_POST['add_user'])) {
    $username = trim($_POST['username']);
    $password = $_POST['password'];
    $confirm_password = $_POST['confirm_password'];
    $full_name = trim($_POST['full_name']);
    $email = trim($_POST['email']);
    $phone = trim($_POST['phone']);
    $role = $_POST['role'];
    $status = $_POST['status'];
    
    $errors = [];
    
    // التحقق من صحة البيانات
    if (empty($username)) {
        $errors[] = "اسم المستخدم مطلوب";
    } elseif (strlen($username) < 3) {
        $errors[] = "اسم المستخدم يجب أن يكون 3 أحرف على الأقل";
    }
    
    if (empty($password)) {
        $errors[] = "كلمة المرور مطلوبة";
    } elseif (strlen($password) < 6) {
        $errors[] = "كلمة المرور يجب أن تكون 6 أحرف على الأقل";
    }
    
    if ($password !== $confirm_password) {
        $errors[] = "كلمة المرور وتأكيد كلمة المرور غير متطابقتان";
    }
    
    if (empty($full_name)) {
        $errors[] = "الاسم الكامل مطلوب";
    }
    
    // التحقق من عدم وجود اسم المستخدم مسبقاً
    if (empty($errors)) {
        $check_stmt = $conn->prepare("SELECT id FROM users WHERE username = ?");
        $check_stmt->bind_param("s", $username);
        $check_stmt->execute();
        if ($check_stmt->get_result()->num_rows > 0) {
            $errors[] = "اسم المستخدم موجود مسبقاً";
        }
    }
    
    // إضافة المستخدم إذا لم توجد أخطاء
    if (empty($errors)) {
        $hashed_password = password_hash($password, PASSWORD_DEFAULT);
        $stmt = $conn->prepare("INSERT INTO users (username, password, full_name, email, phone, role, status) VALUES (?, ?, ?, ?, ?, ?, ?)");
        $stmt->bind_param("sssssss", $username, $hashed_password, $full_name, $email, $phone, $role, $status);
        
        if ($stmt->execute()) {
            $success_message = "تم إضافة المستخدم بنجاح";
            // مسح النموذج
            $_POST = [];
        } else {
            $errors[] = "حدث خطأ أثناء إضافة المستخدم";
        }
    }
}

// تضمين الهيدر بعد انتهاء معالجة POST
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-user-plus me-2"></i>إضافة مستخدم جديد</h2>
                <div>
                    <a href="users.php" class="btn btn-outline-secondary me-2">
                        <i class="fas fa-arrow-left me-1"></i>العودة للمستخدمين
                    </a>
                    <a href="index.php" class="btn btn-outline-primary">
                        <i class="fas fa-cogs me-1"></i>الإعدادات
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

    <?php if (!empty($errors)): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="fas fa-exclamation-circle me-2"></i>
            <ul class="mb-0">
                <?php foreach ($errors as $error): ?>
                    <li><?= $error ?></li>
                <?php endforeach; ?>
            </ul>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <div class="row justify-content-center">
        <div class="col-md-8">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0"><i class="fas fa-user-plus me-2"></i>بيانات المستخدم الجديد</h5>
                </div>
                <div class="card-body">
                    <form method="POST">
                        <div class="row">
                            <div class="col-md-6 mb-3">
                                <label for="username" class="form-label">اسم المستخدم *</label>
                                <input type="text" class="form-control" id="username" name="username" 
                                       value="<?= htmlspecialchars($_POST['username'] ?? '') ?>" required>
                                <div class="form-text">يجب أن يكون 3 أحرف على الأقل</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="full_name" class="form-label">الاسم الكامل *</label>
                                <input type="text" class="form-control" id="full_name" name="full_name" 
                                       value="<?= htmlspecialchars($_POST['full_name'] ?? '') ?>" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="email" class="form-label">البريد الإلكتروني</label>
                                <input type="email" class="form-control" id="email" name="email" 
                                       value="<?= htmlspecialchars($_POST['email'] ?? '') ?>">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="phone" class="form-label">رقم الهاتف</label>
                                <input type="tel" class="form-control" id="phone" name="phone" 
                                       value="<?= htmlspecialchars($_POST['phone'] ?? '') ?>">
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="password" class="form-label">كلمة المرور *</label>
                                <input type="password" class="form-control" id="password" name="password" required>
                                <div class="form-text">يجب أن تكون 6 أحرف على الأقل</div>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="confirm_password" class="form-label">تأكيد كلمة المرور *</label>
                                <input type="password" class="form-control" id="confirm_password" name="confirm_password" required>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="role" class="form-label">الدور *</label>
                                <select class="form-select" id="role" name="role" required>
                                    <option value="employee" <?= ($_POST['role'] ?? '') == 'employee' ? 'selected' : '' ?>>موظف</option>
                                    <option value="manager" <?= ($_POST['role'] ?? '') == 'manager' ? 'selected' : '' ?>>مدير</option>
                                    <option value="admin" <?= ($_POST['role'] ?? '') == 'admin' ? 'selected' : '' ?>>مدير عام</option>
                                </select>
                            </div>
                            <div class="col-md-6 mb-3">
                                <label for="status" class="form-label">الحالة *</label>
                                <select class="form-select" id="status" name="status" required>
                                    <option value="active" <?= ($_POST['status'] ?? 'active') == 'active' ? 'selected' : '' ?>>نشط</option>
                                    <option value="inactive" <?= ($_POST['status'] ?? '') == 'inactive' ? 'selected' : '' ?>>غير نشط</option>
                                </select>
                            </div>
                        </div>
                        
                        <div class="row">
                            <div class="col-12">
                                <div class="card bg-light">
                                    <div class="card-body">
                                        <h6 class="card-title"><i class="fas fa-info-circle me-2"></i>معلومات الأدوار</h6>
                                        <ul class="mb-0">
                                            <li><strong>موظف:</strong> يمكنه إدارة الحجوزات والمدفوعات</li>
                                            <li><strong>مدير:</strong> يمكنه إدارة الحجوزات والتقارير والموظفين</li>
                                            <li><strong>مدير عام:</strong> يمكنه الوصول لجميع وظائف النظام</li>
                                        </ul>
                                    </div>
                                </div>
                            </div>
                        </div>
                        
                        <div class="text-end mt-3">
                            <button type="reset" class="btn btn-outline-secondary me-2">
                                <i class="fas fa-undo me-1"></i>مسح
                            </button>
                            <button type="submit" name="add_user" class="btn btn-primary">
                                <i class="fas fa-save me-1"></i>حفظ المستخدم
                            </button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
// التحقق من تطابق كلمة المرور
document.getElementById('confirm_password').addEventListener('input', function() {
    const password = document.getElementById('password').value;
    const confirmPassword = this.value;
    
    if (password !== confirmPassword) {
        this.setCustomValidity('كلمة المرور غير متطابقة');
    } else {
        this.setCustomValidity('');
    }
});
</script>

<?php include_once '../../includes/footer.php'; ?>
