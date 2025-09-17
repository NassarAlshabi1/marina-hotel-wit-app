<?php
include_once '../../includes/db.php';
include_once '../../includes/header.php';
//include_once '../../includes/auth_check.php';
// الجلسة تبدأ تلقائياً عبر header.php -> auth.php
// تم إزالة التحقق من صلاحية المستخدم

// التحقق من الاتصال بقاعدة البيانات
if ($conn->connect_error) {
    die("فشل الاتصال بقاعدة البيانات: " . $conn->connect_error);
}

// جلب قائمة المستخدمين
$users_query = "SELECT * FROM users ORDER BY user_id";
$users_result = $conn->query($users_query);

// جلب قائمة الصلاحيات
$permissions_query = "SELECT * FROM permissions ORDER BY permission_id";
$permissions_result = $conn->query($permissions_query);
$permissions = [];
while ($permission = $permissions_result->fetch_assoc()) {
    $permissions[] = $permission;
}

// معالجة إضافة مستخدم جديد
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['action'])) {
    if ($_POST['action'] === 'add_user') {
        $username = $_POST['username'];
        $password = password_hash($_POST['password'], PASSWORD_DEFAULT);
        $full_name = $_POST['full_name'];
        $email = $_POST['email'] ?? null;
        $phone = $_POST['phone'] ?? null;
        $user_type = $_POST['user_type'];
        $is_active = isset($_POST['is_active']) ? 1 : 0;
        
        // التحقق من عدم وجود اسم مستخدم مكرر
        $check_query = "SELECT * FROM users WHERE username = ?";
        $check_stmt = $conn->prepare($check_query);
        $check_stmt->bind_param("s", $username);
        $check_stmt->execute();
        $check_result = $check_stmt->get_result();
        
        if ($check_result->num_rows > 0) {
            $error_message = "اسم المستخدم موجود بالفعل، يرجى اختيار اسم آخر.";
        } else {
            // إضافة المستخدم الجديد
            $insert_query = "INSERT INTO users (username, password, full_name, email, phone, user_type, is_active) 
                            VALUES (?, ?, ?, ?, ?, ?, ?)";
            $insert_stmt = $conn->prepare($insert_query);
            $insert_stmt->bind_param("ssssssi", $username, $password, $full_name, $email, $phone, $user_type, $is_active);
            
            if ($insert_stmt->execute()) {
                $user_id = $insert_stmt->insert_id;
                
                // إضافة الصلاحيات للمستخدم الجديد
                if (isset($_POST['permissions']) && is_array($_POST['permissions'])) {
                    foreach ($_POST['permissions'] as $permission_id) {
                        $perm_query = "INSERT INTO user_permissions (user_id, permission_id) VALUES (?, ?)";
                        $perm_stmt = $conn->prepare($perm_query);
                        $perm_stmt->bind_param("ii", $user_id, $permission_id);
                        $perm_stmt->execute();
                    }
                }
                
                header("Location: users.php?success=تمت إضافة المستخدم بنجاح");
                exit;
            } else {
                $error_message = "حدث خطأ أثناء إضافة المستخدم: " . $conn->error;
            }
        }
    } elseif ($_POST['action'] === 'update_permissions' && isset($_POST['user_id'])) {
        $user_id = $_POST['user_id'];
        
        // حذف جميع صلاحيات المستخدم الحالية
        $delete_query = "DELETE FROM user_permissions WHERE user_id = ?";
        $delete_stmt = $conn->prepare($delete_query);
        $delete_stmt->bind_param("i", $user_id);
        $delete_stmt->execute();
        
        // إضافة الصلاحيات الجديدة
        if (isset($_POST['permissions']) && is_array($_POST['permissions'])) {
            foreach ($_POST['permissions'] as $permission_id) {
                $perm_query = "INSERT INTO user_permissions (user_id, permission_id) VALUES (?, ?)";
                $perm_stmt = $conn->prepare($perm_query);
                $perm_stmt->bind_param("ii", $user_id, $permission_id);
                $perm_stmt->execute();
            }
        }
        
        header("Location: users.php?success=تم تحديث صلاحيات المستخدم بنجاح");
        exit;
    } elseif ($_POST['action'] === 'update_user' && isset($_POST['user_id'])) {
        $user_id = $_POST['user_id'];
        $full_name = $_POST['full_name'];
        $email = $_POST['email'] ?? null;
        $phone = $_POST['phone'] ?? null;
        $user_type = $_POST['user_type'];
        $is_active = isset($_POST['is_active']) ? 1 : 0;
        
        // تحديث بيانات المستخدم
        $update_query = "UPDATE users SET full_name = ?, email = ?, phone = ?, user_type = ?, is_active = ? WHERE user_id = ?";
        $update_stmt = $conn->prepare($update_query);
        $update_stmt->bind_param("ssssii", $full_name, $email, $phone, $user_type, $is_active, $user_id);
        
        if ($update_stmt->execute()) {
            // تحديث كلمة المرور إذا تم إدخالها
            if (!empty($_POST['password'])) {
                $password = password_hash($_POST['password'], PASSWORD_DEFAULT);
                $pass_query = "UPDATE users SET password = ? WHERE user_id = ?";
                $pass_stmt = $conn->prepare($pass_query);
                $pass_stmt->bind_param("si", $password, $user_id);
                $pass_stmt->execute();
            }
            
            header("Location: users.php?success=تم تحديث بيانات المستخدم بنجاح");
            exit;
        } else {
            $error_message = "حدث خطأ أثناء تحديث بيانات المستخدم: " . $conn->error;
        }
    } elseif ($_POST['action'] === 'delete_user' && isset($_POST['user_id'])) {
        $user_id = $_POST['user_id'];
        
        // التحقق من عدم حذف المستخدم الحالي
        if ($user_id == $_SESSION['user_id']) {
            $error_message = "لا يمكن حذف المستخدم الحالي.";
        } else {
            // حذف المستخدم
            $delete_query = "DELETE FROM users WHERE user_id = ?";
            $delete_stmt = $conn->prepare($delete_query);
            $delete_stmt->bind_param("i", $user_id);
            
            if ($delete_stmt->execute()) {
                header("Location: users.php?success=تم حذف المستخدم بنجاح");
                exit;
            } else {
                $error_message = "حدث خطأ أثناء حذف المستخدم: " . $conn->error;
            }
        }
    }
}

// جلب صلاحيات مستخدم محدد
function get_user_permissions($conn, $user_id) {
    $query = "SELECT permission_id FROM user_permissions WHERE user_id = ?";
    $stmt = $conn->prepare($query);
    $stmt->bind_param("i", $user_id);
    $stmt->execute();
    $result = $stmt->get_result();
    
    $user_permissions = [];
    while ($row = $result->fetch_assoc()) {
        $user_permissions[] = $row['permission_id'];
    }
    
    return $user_permissions;
}
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إدارة المستخدمين والصلاحيات - فندق مارينا بلازا</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.0.0/css/all.min.css" rel="stylesheet">
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
        .form-label {
            font-weight: bold;
        }
        .user-card {
            transition: all 0.3s ease;
        }
        .user-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 15px rgba(0, 0, 0, 0.1);
        }
        .user-avatar {
            width: 60px;
            height: 60px;
            background-color: #e9ecef;
            border-radius: 50%;
            display: flex;
            align-items: center;
            justify-content: center;
            font-size: 1.5rem;
            color: #6c757d;
            margin-right: 15px;
        }
        .user-info {
            flex-grow: 1;
        }
        .user-name {
            font-weight: bold;
            font-size: 1.1rem;
            margin-bottom: 5px;
        }
        .user-username {
            color: #6c757d;
            font-size: 0.9rem;
        }
        .user-type {
            font-size: 0.8rem;
            padding: 3px 8px;
            border-radius: 20px;
            font-weight: bold;
        }
        .user-type.admin {
            background-color: #cfe2ff;
            color: #084298;
        }
        .user-type.employee {
            background-color: #d1e7dd;
            color: #0f5132;
        }
        .user-status {
            font-size: 0.8rem;
            padding: 3px 8px;
            border-radius: 20px;
            font-weight: bold;
        }
        .user-status.active {
            background-color: #d1e7dd;
            color: #0f5132;
        }
        .user-status.inactive {
            background-color: #f8d7da;
            color: #842029;
        }
        .permission-item {
            margin-bottom: 10px;
        }
        .permission-item label {
            font-weight: normal;
            cursor: pointer;
        }
        .permission-group {
            border: 1px solid #dee2e6;
            border-radius: 10px;
            padding: 15px;
            margin-bottom: 15px;
        }
        .permission-group-title {
            font-weight: bold;
            margin-bottom: 10px;
            color: #0d6efd;
        }
        @media (max-width: 768px) {
            .user-avatar {
                width: 40px;
                height: 40px;
                font-size: 1.2rem;
                margin-right: 10px;
            }
            .user-name {
                font-size: 1rem;
            }
        }
    </style>
</head>
<body>
    <div class="container py-4">
        <div class="d-flex justify-content-between mb-3">
            <a href="../dashboard.php" class="btn btn-outline-primary fw-bold">
                ← العودة إلى لوحة التحكم
            </a>
            <button type="button" class="btn btn-success fw-bold" data-bs-toggle="modal" data-bs-target="#addUserModal">
                <i class="fas fa-user-plus me-1"></i> إضافة مستخدم جديد
            </button>
        </div>

        <h2 class="text-center mb-4 text-primary fw-bold">إدارة المستخدمين والصلاحيات - فندق مارينا بلازا</h2>
        
        <?php if (isset($_GET['success'])): ?>
            <div class="alert alert-success text-center" role="alert">
                <?= htmlspecialchars($_GET['success']); ?>
            </div>
        <?php endif; ?>
        
        <?php if (isset($error_message)): ?>
            <div class="alert alert-danger text-center" role="alert">
                <?= htmlspecialchars($error_message); ?>
            </div>
        <?php endif; ?>

        <div class="row">
            <?php if ($users_result && $users_result->num_rows > 0): ?>
                <?php while ($user = $users_result->fetch_assoc()): ?>
                    <div class="col-md-6 col-lg-4 mb-4">
                        <div class="card user-card">
                            <div class="card-body">
                                <div class="d-flex align-items-center mb-3">
                                    <div class="user-avatar">
                                        <i class="fas fa-user"></i>
                                    </div>
                                    <div class="user-info">
                                        <div class="user-name"><?= htmlspecialchars($user['full_name']); ?></div>
                                        <div class="user-username"><?= htmlspecialchars($user['username']); ?></div>
                                    </div>
                                </div>
                                
                                <div class="d-flex justify-content-between mb-3">
                                    <span class="user-type <?= $user['user_type']; ?>">
                                        <?= $user['user_type'] === 'admin' ? 'مدير' : 'موظف'; ?>
                                    </span>
                                    <span class="user-status <?= $user['is_active'] ? 'active' : 'inactive'; ?>">
                                        <?= $user['is_active'] ? 'نشط' : 'غير نشط'; ?>
                                    </span>
                                </div>
                                
                                <?php if ($user['email'] || $user['phone']): ?>
                                    <div class="small text-muted mb-3">
                                        <?php if ($user['email']): ?>
                                            <div><i class="fas fa-envelope me-1"></i> <?= htmlspecialchars($user['email']); ?></div>
                                        <?php endif; ?>
                                        <?php if ($user['phone']): ?>
                                            <div><i class="fas fa-phone me-1"></i> <?= htmlspecialchars($user['phone']); ?></div>
                                        <?php endif; ?>
                                    </div>
                                <?php endif; ?>
                                
                                <div class="d-flex justify-content-between">
                                    <button type="button" class="btn btn-sm btn-primary" 
                                            data-bs-toggle="modal" 
                                            data-bs-target="#permissionsModal" 
                                            data-user-id="<?= $user['user_id']; ?>"
                                            data-user-name="<?= htmlspecialchars($user['full_name']); ?>">
                                        <i class="fas fa-key me-1"></i> الصلاحيات
                                    </button>
                                    <div>
                                        <button type="button" class="btn btn-sm btn-warning" 
                                                data-bs-toggle="modal" 
                                                data-bs-target="#editUserModal"
                                                data-user-id="<?= $user['user_id']; ?>"
                                                data-username="<?= htmlspecialchars($user['username']); ?>"
                                                data-fullname="<?= htmlspecialchars($user['full_name']); ?>"
                                                data-email="<?= htmlspecialchars($user['email'] ?? ''); ?>"
                                                data-phone="<?= htmlspecialchars($user['phone'] ?? ''); ?>"
                                                data-user-type="<?= $user['user_type']; ?>"
                                                data-is-active="<?= $user['is_active']; ?>">
                                            <i class="fas fa-edit me-1"></i> تعديل
                                        </button>
                                        <?php if ($user['user_id'] != $_SESSION['user_id']): ?>
                                            <button type="button" class="btn btn-sm btn-danger" 
                                                    data-bs-toggle="modal" 
                                                    data-bs-target="#deleteUserModal"
                                                    data-user-id="<?= $user['user_id']; ?>"
                                                    data-user-name="<?= htmlspecialchars($user['full_name']); ?>">
                                                <i class="fas fa-trash-alt me-1"></i> حذف
                                            </button>
                                        <?php endif; ?>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>
                <?php endwhile; ?>
            <?php else: ?>
                <div class="col-12">
                    <div class="alert alert-info text-center">
                        لا يوجد مستخدمين مسجلين في النظام.
                    </div>
                </div>
            <?php endif; ?>
        </div>
    </div>

    <!-- Modal إضافة مستخدم جديد -->
    <div class="modal fade" id="addUserModal" tabindex="-1" aria-labelledby="addUserModalLabel" aria-hidden="true">
        <div class="modal-dialog modal-lg">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="addUserModalLabel">إضافة مستخدم جديد</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <form method="POST" action="">
                        <input type="hidden" name="action" value="add_user">
                        
                        <div class="row mb-3">
                            <div class="col-md-6">
                                <label for="username" class="form-label">اسم المستخدم</label>
                                <input type="text" class="form-control" id="username" name="username" required>
                            </div>
                            <div class="col-md-6">
                                <label for="password" class="form-label">كلمة المرور</label>
                                <input type="password" class="form-control" id="password" name="password" required>
                            </div>
                        </div>
                        
                        <div class="mb-3">
                            <label for="full_name" class="form-label">الاسم الكامل</label>
                            <input type="text" class="form-control" id="full_name" name="full_name" required>
                        </div>
                        
                        <div class="row mb-3">
                            <div class="col-md-6">
                                <label for="email" class="form-label">البريد الإلكتروني</label>
                                <input type="email" class="form-control" id="email" name="email">
                            </div>
                            <div class="col-md-6">
                                <label for="phone" class="form-label">رقم الهاتف</label>
                                <input type="text" class="form-control" id="phone" name="phone">
                            </div>
                        </div>
                        
                        <div class="row mb-3">
                            <div class="col-md-6">
                                <label for="user_type" class="form-label">نوع المستخدم</label>
                                <select class="form-select" id="user_type" name="user_type" required>
                                    <option value="admin">مدير</option>
                                    <option value="employee" selected>موظف</option>
                                </select>
                            </div>
                            <div class="col-md-6">
                                <div class="form-check mt-4">
                                    <input class="form-check-input" type="checkbox" id="is_active" name="is_active" checked>
                                    <label class="form-check-label" for="is_active">
                                        حساب نشط
                                    </label>
                                </div>
                            </div>
                        </div>
                        
                        <div class="mb-3">
                            <label class="form-label">الصلاحيات</label>
                            <div class="permission-group">
                                <div class="permission-group-title">صلاحيات النظام</div>
                                <?php foreach ($permissions as $permission): ?>
                                    <div class="permission-item">
                                        <div class="form-check">
                                            <input class="form-check-input" type="checkbox" 
                                                   id="perm_<?= $permission['permission_id']; ?>" 
                                                   name="permissions[]" 
                                                   value="<?= $permission['permission_id']; ?>">
                                            <label class="form-check-label" for="perm_<?= $permission['permission_id']; ?>">
                                                <?= htmlspecialchars($permission['permission_name']); ?>
                                                <small class="text-muted d-block"><?= htmlspecialchars($permission['permission_description']); ?></small>
                                            </label>
                                        </div>
                                    </div>
                                <?php endforeach; ?>
                            </div>
                        </div>
                        
                        <div class="text-center">
                            <button type="submit" class="btn btn-primary">إضافة المستخدم</button>
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إلغاء</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- Modal تعديل المستخدم -->
    <div class="modal fade" id="editUserModal" tabindex="-1" aria-labelledby="editUserModalLabel" aria-hidden="true">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="editUserModalLabel">تعديل بيانات المستخدم</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <form method="POST" action="">
                        <input type="hidden" name="action" value="update_user">
                        <input type="hidden" name="user_id" id="edit_user_id">
                        
                        <div class="mb-3">
                            <label class="form-label">اسم المستخدم</label>
                            <input type="text" class="form-control" id="edit_username" disabled>
                        </div>
                        
                        <div class="mb-3">
                            <label for="edit_password" class="form-label">كلمة المرور الجديدة (اترك فارغاً للإبقاء على كلمة المرور الحالية)</label>
                            <input type="password" class="form-control" id="edit_password" name="password">
                        </div>
                        
                        <div class="mb-3">
                            <label for="edit_full_name" class="form-label">الاسم الكامل</label>
                            <input type="text" class="form-control" id="edit_full_name" name="full_name" required>
                        </div>
                        
                        <div class="mb-3">
                            <label for="edit_email" class="form-label">البريد الإلكتروني</label>
                            <input type="email" class="form-control" id="edit_email" name="email">
                        </div>
                        
                        <div class="mb-3">
                            <label for="edit_phone" class="form-label">رقم الهاتف</label>
                            <input type="text" class="form-control" id="edit_phone" name="phone">
                        </div>
                        
                        <div class="mb-3">
                            <label for="edit_user_type" class="form-label">نوع المستخدم</label>
                            <select class="form-select" id="edit_user_type" name="user_type" required>
                                <option value="admin">مدير</option>
                                <option value="employee">موظف</option>
                            </select>
                        </div>
                        
                        <div class="mb-3">
                            <div class="form-check">
                                <input class="form-check-input" type="checkbox" id="edit_is_active" name="is_active">
                                <label class="form-check-label" for="edit_is_active">
                                    حساب نشط
                                </label>
                            </div>
                        </div>
                        
                        <div class="text-center">
                            <button type="submit" class="btn btn-primary">حفظ التغييرات</button>
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إلغاء</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- Modal الصلاحيات -->
    <div class="modal fade" id="permissionsModal" tabindex="-1" aria-labelledby="permissionsModalLabel" aria-hidden="true">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="permissionsModalLabel">إدارة صلاحيات المستخدم</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <form method="POST" action="">
                        <input type="hidden" name="action" value="update_permissions">
                        <input type="hidden" name="user_id" id="permissions_user_id">
                        
                        <div class="mb-3">
                            <div class="permission-group">
                                <div class="permission-group-title">صلاحيات النظام</div>
                                <?php foreach ($permissions as $permission): ?>
                                    <div class="permission-item">
                                        <div class="form-check">
                                            <input class="form-check-input permission-checkbox" type="checkbox" 
                                                   id="perm_modal_<?= $permission['permission_id']; ?>" 
                                                   name="permissions[]" 
                                                   value="<?= $permission['permission_id']; ?>"
                                                   data-permission-id="<?= $permission['permission_id']; ?>">
                                            <label class="form-check-label" for="perm_modal_<?= $permission['permission_id']; ?>">
                                                <?= htmlspecialchars($permission['permission_name']); ?>
                                                <small class="text-muted d-block"><?= htmlspecialchars($permission['permission_description']); ?></small>
                                            </label>
                                        </div>
                                    </div>
                                <?php endforeach; ?>
                            </div>
                        </div>
                        
                        <div class="text-center">
                            <button type="submit" class="btn btn-primary">حفظ الصلاحيات</button>
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إلغاء</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- Modal حذف المستخدم -->
    <div class="modal fade" id="deleteUserModal" tabindex="-1" aria-labelledby="deleteUserModalLabel" aria-hidden="true">
        <div class="modal-dialog">
            <div class="modal-content">
                <div class="modal-header">
                    <h5 class="modal-title" id="deleteUserModalLabel">تأكيد حذف المستخدم</h5>
                    <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
                </div>
                <div class="modal-body">
                    <p>هل أنت متأكد من حذف المستخدم <span id="delete_user_name" class="fw-bold"></span>؟</p>
                    <p class="text-danger">هذا الإجراء لا يمكن التراجع عنه.</p>
                    
                    <form method="POST" action="">
                        <input type="hidden" name="action" value="delete_user">
                        <input type="hidden" name="user_id" id="delete_user_id">
                        
                        <div class="text-center">
                            <button type="submit" class="btn btn-danger">تأكيد الحذف</button>
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إلغاء</button>
                        </div>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>
    <script>
        // تعبئة بيانات المستخدم في نافذة التعديل
        document.addEventListener('DOMContentLoaded', function() {
            const editUserModal = document.getElementById('editUserModal');
            if (editUserModal) {
                editUserModal.addEventListener('show.bs.modal', function(event) {
                    const button = event.relatedTarget;
                    const userId = button.getAttribute('data-user-id');
                    const username = button.getAttribute('data-username');
                    const fullName = button.getAttribute('data-fullname');
                    const email = button.getAttribute('data-email');
                    const phone = button.getAttribute('data-phone');
                    const userType = button.getAttribute('data-user-type');
                    const isActive = button.getAttribute('data-is-active') === '1';
                    
                    document.getElementById('edit_user_id').value = userId;
                    document.getElementById('edit_username').value = username;
                    document.getElementById('edit_full_name').value = fullName;
                    document.getElementById('edit_email').value = email;
                    document.getElementById('edit_phone').value = phone;
                    document.getElementById('edit_user_type').value = userType;
                    document.getElementById('edit_is_active').checked = isActive;
                });
            }
            
            // تعبئة بيانات المستخدم في نافذة الصلاحيات
            const permissionsModal = document.getElementById('permissionsModal');
            if (permissionsModal) {
                permissionsModal.addEventListener('show.bs.modal', function(event) {
                    const button = event.relatedTarget;
                    const userId = button.getAttribute('data-user-id');
                    const userName = button.getAttribute('data-user-name');
                    
                    document.getElementById('permissions_user_id').value = userId;
                    document.getElementById('permissionsModalLabel').textContent = 'إدارة صلاحيات المستخدم: ' + userName;
                    
                    // إعادة تعيين جميع الصلاحيات
                    document.querySelectorAll('.permission-checkbox').forEach(checkbox => {
                        checkbox.checked = false;
                    });
                    
                    // جلب صلاحيات المستخدم
                    fetch(`get_user_permissions.php?user_id=${userId}`)
                        .then(response => response.json())
                        .then(data => {
                            if (data.success) {
                                data.permissions.forEach(permissionId => {
                                    const checkbox = document.querySelector(`.permission-checkbox[data-permission-id="${permissionId}"]`);
                                    if (checkbox) {
                                        checkbox.checked = true;
                                    }
                                });
                            }
                        })
                        .catch(error => console.error('Error fetching permissions:', error));
                });
            }
            
            // تعبئة بيانات المستخدم في نافذة الحذف
            const deleteUserModal = document.getElementById('deleteUserModal');
            if (deleteUserModal) {
                deleteUserModal.addEventListener('show.bs.modal', function(event) {
                    const button = event.relatedTarget;
                    const userId = button.getAttribute('data-user-id');
                    const userName = button.getAttribute('data-user-name');
                    
                    document.getElementById('delete_user_id').value = userId;
                    document.getElementById('delete_user_name').textContent = userName;
                });
            }
        });
    </script>
</body>
</html>

<?php
if (isset($check_stmt)) $check_stmt->close();
if (isset($insert_stmt)) $insert_stmt->close();
if (isset($perm_stmt)) $perm_stmt->close();
if (isset($delete_stmt)) $delete_stmt->close();
if (isset($update_stmt)) $update_stmt->close();
if (isset($pass_stmt)) $pass_stmt->close();
$conn->close();
?>
