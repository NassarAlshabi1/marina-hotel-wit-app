<?php
session_start();
require_once '../../includes/db.php';

// التحقق من صلاحيات المستخدم
require_once '../../includes/auth_check_finance.php';

// التحقق من وجود دالة للتحقق من صلاحيات المسؤول
if (!function_exists('check_admin_permission')) {
    function check_admin_permission() {
        // إذا كان المستخدم مدير النظام، فلديه جميع الصلاحيات
        if (isset($_SESSION['user_type']) && $_SESSION['user_type'] === 'admin') {
            return true;
        }
        
        // التحقق من وجود الصلاحية في مصفوفة صلاحيات المستخدم
        return isset($_SESSION['permissions']) && in_array('manage_users', $_SESSION['permissions']);
    }
}

if (!check_admin_permission()) {
    header("Location: ../../index.php?error=ليس لديك صلاحية للوصول إلى هذه الصفحة");
    exit();
}

// إعداد الصفحة
echo "<!DOCTYPE html>
<html dir='rtl'>
<head>
    <meta charset='UTF-8'>
    <title>إدارة المستخدمين</title>
    <style>
        body { font-family: 'Tajawal', sans-serif; padding: 20px; }
        h1, h2 { color: #333; }
        .success { color: green; }
        .error { color: red; }
        .warning { color: orange; }
        table { width: 100%; border-collapse: collapse; margin-bottom: 20px; }
        table, th, td { border: 1px solid #ddd; }
        th, td { padding: 8px; text-align: right; }
        th { background-color: #f2f2f2; }
        .btn { display: inline-block; padding: 8px 12px; background-color: #4CAF50; color: white; 
               text-decoration: none; border-radius: 4px; margin: 2px; border: none; cursor: pointer; }
        .btn-edit { background-color: #2196F3; }
        .btn-delete { background-color: #f44336; }
        .form-group { margin-bottom: 15px; }
        .form-group label { display: block; margin-bottom: 5px; }
        .form-group input, .form-group select { width: 100%; padding: 8px; box-sizing: border-box; }
    </style>
    <script>
        function showEditForm(userId, username, fullName, email, userType, status) {
            document.getElementById('edit_user_id').value = userId;
            document.getElementById('edit_username').value = username;
            document.getElementById('edit_full_name').value = fullName;
            document.getElementById('edit_email').value = email;
            document.getElementById('edit_user_type').value = userType;
            document.getElementById('edit_status').value = status;
            document.getElementById('editUserForm').style.display = 'block';
        }
        
        function hideEditForm() {
            document.getElementById('editUserForm').style.display = 'none';
        }
    </script>
</head>
<body>
    <h1>إدارة المستخدمين</h1>";

// تسجيل الإجراء في سجل النظام
function log_action($conn, $action, $details) {
    // التحقق من وجود جدول السجلات
    $check_logs_table = $conn->query("SHOW TABLES LIKE 'system_logs'");
    if ($check_logs_table->num_rows == 0) {
        // إنشاء جدول السجلات إذا لم يكن موجودًا
        $conn->query("
            CREATE TABLE system_logs (
                log_id INT AUTO_INCREMENT PRIMARY KEY,
                action VARCHAR(100) NOT NULL,
                details TEXT,
                user_id INT,
                created_at DATETIME NOT NULL
            )
        ");
    }

    $query = "INSERT INTO system_logs (action, details, user_id, created_at) 
              VALUES (?, ?, ?, NOW())";
    $stmt = $conn->prepare($query);
    $user_id = $_SESSION['user_id'] ?? 0;
    $stmt->bind_param("ssi", $action, $details, $user_id);
    $stmt->execute();
}

// التحقق من وجود جدول المستخدمين وإنشائه إذا لم يكن موجودًا
$check_users_table = $conn->query("SHOW TABLES LIKE 'users'");
if ($check_users_table->num_rows == 0) {
    $create_users_table = "
    CREATE TABLE users (
        user_id INT AUTO_INCREMENT PRIMARY KEY,
        username VARCHAR(50) NOT NULL UNIQUE,
        password VARCHAR(255) NOT NULL,
        full_name VARCHAR(100) NOT NULL,
        email VARCHAR(100),
        user_type ENUM('admin', 'manager', 'receptionist', 'accountant') NOT NULL,
        status ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
        last_login DATETIME,
        created_at DATETIME NOT NULL,
        updated_at DATETIME NOT NULL
    )";
    
    if ($conn->query($create_users_table)) {
        echo "<p class='success'>✅ تم إنشاء جدول المستخدمين بنجاح.</p>";
        
        // إنشاء مستخدم افتراضي للمسؤول
        $admin_password = password_hash('admin123', PASSWORD_DEFAULT);
        $create_admin = "
        INSERT INTO users (username, password, full_name, email, user_type, status, created_at, updated_at)
        VALUES ('admin', '$admin_password', 'مدير النظام', 'admin@example.com', 'admin', 'active', NOW(), NOW())
        ";
        
        if ($conn->query($create_admin)) {
            echo "<p class='success'>✅ تم إنشاء حساب المسؤول الافتراضي.</p>";
            echo "<p>اسم المستخدم: admin</p>";
            echo "<p>كلمة المرور: admin123</p>";
            echo "<p class='warning'>⚠️ يرجى تغيير كلمة المرور الافتراضية فورًا!</p>";
        }
    } else {
        echo "<p class='error'>❌ فشل في إنشاء جدول المستخدمين: " . $conn->error . "</p>";
    }
}

// إضافة مستخدم جديد
if (isset($_POST['add_user'])) {
    $username = trim($_POST['username']);
    $password = $_POST['password'];
    $full_name = trim($_POST['full_name']);
    $email = trim($_POST['email']);
    $user_type = $_POST['user_type'];
    
    // التحقق من البيانات
    $errors = [];
    
    if (empty($username)) {
        $errors[] = "اسم المستخدم مطلوب";
    } else {
        // التحقق من عدم وجود اسم المستخدم مسبقًا
        $check_username = $conn->prepare("SELECT user_id FROM users WHERE username = ?");
        $check_username->bind_param("s", $username);
        $check_username->execute();
        if ($check_username->get_result()->num_rows > 0) {
            $errors[] = "اسم المستخدم موجود بالفعل";
        }
    }
    
    if (empty($password)) {
        $errors[] = "كلمة المرور مطلوبة";
    } elseif (strlen($password) < 6) {
        $errors[] = "كلمة المرور يجب أن تكون 6 أحرف على الأقل";
    }
    
    if (empty($full_name)) {
        $errors[] = "الاسم الكامل مطلوب";
    }
    
    if (!empty($email) && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $errors[] = "البريد الإلكتروني غير صالح";
    }
    
    // إذا لم تكن هناك أخطاء، أضف المستخدم
    if (empty($errors)) {
        $hashed_password = password_hash($password, PASSWORD_DEFAULT);
        
        $insert_user = $conn->prepare("
            INSERT INTO users (username, password, full_name, email, user_type, status, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, 'active', NOW(), NOW())
        ");
        
        $insert_user->bind_param("sssss", $username, $hashed_password, $full_name, $email, $user_type);
        
        if ($insert_user->execute()) {
            $user_id = $conn->insert_id;
            echo "<p class='success'>✅ تم إضافة المستخدم بنجاح.</p>";
            
            // تسجيل الإجراء
            log_action($conn, "add_user", "تم إضافة مستخدم جديد: $username (ID: $user_id)");
        } else {
            echo "<p class='error'>❌ فشل في إضافة المستخدم: " . $conn->error . "</p>";
        }
    } else {
        echo "<p class='error'>❌ يرجى تصحيح الأخطاء التالية:</p>";
        echo "<ul>";
        foreach ($errors as $error) {
            echo "<li>$error</li>";
        }
        echo "</ul>";
    }
}

// تعديل مستخدم
if (isset($_POST['edit_user'])) {
    $user_id = $_POST['user_id'];
    $full_name = trim($_POST['full_name']);
    $email = trim($_POST['email']);
    $user_type = $_POST['user_type'];
    $status = $_POST['status'];
    $new_password = $_POST['new_password'];
    
    // التحقق من البيانات
    $errors = [];
    
    if (empty($full_name)) {
        $errors[] = "الاسم الكامل مطلوب";
    }
    
    if (!empty($email) && !filter_var($email, FILTER_VALIDATE_EMAIL)) {
        $errors[] = "البريد الإلكتروني غير صالح";
    }
    
    // إذا لم تكن هناك أخطاء، قم بتحديث المستخدم
    if (empty($errors)) {
        if (!empty($new_password)) {
            // تحديث مع كلمة مرور جديدة
            $hashed_password = password_hash($new_password, PASSWORD_DEFAULT);
            $update_user = $conn->prepare("
                UPDATE users 
                SET full_name = ?, email = ?, user_type = ?, status = ?, password = ?, updated_at = NOW()
                WHERE user_id = ?
            ");
            $update_user->bind_param("sssssi", $full_name, $email, $user_type, $status, $hashed_password, $user_id);
        } else {
            // تحديث بدون تغيير كلمة المرور
            $update_user = $conn->prepare("
                UPDATE users 
                SET full_name = ?, email = ?, user_type = ?, status = ?, updated_at = NOW()
                WHERE user_id = ?
            ");
            $update_user->bind_param("ssssi", $full_name, $email, $user_type, $status, $user_id);
        }
        
        if ($update_user->execute()) {
            echo "<p class='success'>✅ تم تحديث المستخدم بنجاح.</p>";
            
            // تسجيل الإجراء
            log_action($conn, "edit_user", "تم تعديل المستخدم: ID $user_id");
        } else {
            echo "<p class='error'>❌ فشل في تحديث المستخدم: " . $conn->error . "</p>";
        }
    } else {
        echo "<p class='error'>❌ يرجى تصحيح الأخطاء التالية:</p>";
        echo "<ul>";
        foreach ($errors as $error) {
            echo "<li>$error</li>";
        }
        echo "</ul>";
    }
}

// حذف مستخدم
if (isset($_POST['delete_user'])) {
    $user_id = $_POST['user_id'];
    
    // التحقق من عدم حذف المستخدم الحالي
    if ($user_id == ($_SESSION['user_id'] ?? 0)) {
        echo "<p class='error'>❌ لا يمكنك حذف حسابك الحالي.</p>";
    } else {
        $delete_user = $conn->prepare("DELETE FROM users WHERE user_id = ?");
        $delete_user->bind_param("i", $user_id);
        
        if ($delete_user->execute()) {
            echo "<p class='success'>✅ تم حذف المستخدم بنجاح.</p>";
            
            // تسجيل الإجراء
            log_action($conn, "delete_user", "تم حذف المستخدم: ID $user_id");
        } else {
            echo "<p class='error'>❌ فشل في حذف المستخدم: " . $conn->error . "</p>";
        }
    }
}

// عرض نموذج إضافة مستخدم جديد
echo "<h2>إضافة مستخدم جديد</h2>";
echo "<form method='post'>";
echo "<div class='form-group'>";
echo "<label for='username'>اسم المستخدم:</label>";
echo "<input type='text' id='username' name='username' required>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='password'>كلمة المرور:</label>";
echo "<input type='password' id='password' name='password' required>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='full_name'>الاسم الكامل:</label>";
echo "<input type='text' id='full_name' name='full_name' required>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='email'>البريد الإلكتروني:</label>";
echo "<input type='email' id='email' name='email'>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='user_type'>نوع المستخدم:</label>";
echo "<select id='user_type' name='user_type' required>";
echo "<option value='admin'>مدير النظام</option>";
echo "<option value='manager'>مدير</option>";
echo "<option value='receptionist'>موظف استقبال</option>";
echo "<option value='accountant'>محاسب</option>";
echo "</select>";
echo "</div>";

echo "<button type='submit' name='add_user' class='btn'>إضافة مستخدم</button>";
echo "</form>";

// عرض قائمة المستخدمين
echo "<h2>قائمة المستخدمين</h2>";
$users = $conn->query("SELECT * FROM users ORDER BY user_id");

if ($users && $users->num_rows > 0) {
    echo "<table>";
    echo "<tr>";
    echo "<th>الرقم</th>";
    echo "<th>اسم المستخدم</th>";
    echo "<th>الاسم الكامل</th>";
    echo "<th>البريد الإلكتروني</th>";
    echo "<th>نوع المستخدم</th>";
    echo "<th>الحالة</th>";
    echo "<th>آخر تسجيل دخول</th>";
    echo "<th>الإجراءات</th>";
    echo "</tr>";
    
    while ($user = $users->fetch_assoc()) {
        echo "<tr>";
        echo "<td>{$user['user_id']}</td>";
        echo "<td>{$user['username']}</td>";
        echo "<td>{$user['full_name']}</td>";
        echo "<td>{$user['email']}</td>";
        
        // ترجمة نوع المستخدم
        $user_type_ar = [
            'admin' => 'مدير النظام',
            'manager' => 'مدير',
            'receptionist' => 'موظف استقبال',
            'accountant' => 'محاسب'
        ];
        echo "<td>{$user_type_ar[$user['user_type']]}</td>";
        
        // ترجمة الحالة
        $status_ar = [
            'active' => 'نشط',
            'inactive' => 'غير نشط'
        ];
        echo "<td>{$status_ar[$user['status']]}</td>";
        
        echo "<td>{$user['last_login']}</td>";
        echo "<td>";
        echo "<button class='btn btn-edit' onclick='showEditForm({$user['user_id']}, \"{$user['username']}\", \"{$user['full_name']}\", \"{$user['email']}\", \"{$user['user_type']}\", \"{$user['status']}\")'>تعديل</button>";
        
        // لا تعرض زر الحذف للمستخدم الحالي
        if ($user['user_id'] != ($_SESSION['user_id'] ?? 0)) {
            echo "<form method='post' style='display:inline;' onsubmit='return confirm(\"هل أنت متأكد من حذف هذا المستخدم؟\")'>";
            echo "<input type='hidden' name='user_id' value='{$user['user_id']}'>";
            echo "<button type='submit' name='delete_user' class='btn btn-delete'>حذف</button>";
            echo "</form>";
        }
        
        echo "</td>";
        echo "</tr>";
    }
    
    echo "</table>";
} else {
    echo "<p>لا يوجد مستخدمين.</p>";
}

// نموذج تعديل المستخدم (مخفي بشكل افتراضي)
echo "<div id='editUserForm' style='display:none;'>";
echo "<h2>تعديل المستخدم</h2>";
echo "<form method='post'>";
echo "<input type='hidden' id='edit_user_id' name='user_id'>";

echo "<div class='form-group'>";
echo "<label for='edit_username'>اسم المستخدم:</label>";
echo "<input type='text' id='edit_username' disabled>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='edit_full_name'>الاسم الكامل:</label>";
echo "<input type='text' id='edit_full_name' name='full_name' required>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='edit_email'>البريد الإلكتروني:</label>";
echo "<input type='email' id='edit_email' name='email'>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='edit_user_type'>نوع المستخدم:</label>";
echo "<select id='edit_user_type' name='user_type' required>";
echo "<option value='admin'>مدير النظام</option>";
echo "<option value='manager'>مدير</option>";
echo "<option value='receptionist'>موظف استقبال</option>";
echo "<option value='accountant'>محاسب</option>";
echo "</select>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='edit_status'>الحالة:</label>";
echo "<select id='edit_status' name='status' required>";
echo "<option value='active'>نشط</option>";
echo "<option value='inactive'>غير نشط</option>";
echo "</select>";
echo "</div>";

echo "<div class='form-group'>";
echo "<label for='new_password'>كلمة المرور الجديدة (اتركها فارغة للاحتفاظ بكلمة المرور الحالية):</label>";
echo "<input type='password' id='new_password' name='new_password'>";
echo "</div>";

echo "<button type='submit' name='edit_user' class='btn'>حفظ التغييرات</button>";
echo "<button type='button' onclick='hideEditForm()' class='btn' style='background-color:#777;'>إلغاء</button>";
echo "</form>";
echo "</div>";

// زر العودة
echo "
</augment_code_snippet>
