<?php
require_once 'includes/config.php';
require_once 'includes/db.php';
require_once 'includes/security.php';

// بدء الجلسة مع إعدادات الأمان
ini_set('session.cookie_httponly', 1);
ini_set('session.cookie_secure', 1);
ini_set('session.use_strict_mode', 1);
session_start();

// إعادة توجيه المستخدم إذا كان مسجل دخول بالفعل
if (isset($_SESSION['user_id']) && !empty($_SESSION['user_id'])) {
    header('Location: admin/dash.php');
    exit;
}

$error = '';
$success = '';

// عرض رسائل من URL parameters
if (isset($_GET['error'])) {
    $error = htmlspecialchars($_GET['error'], ENT_QUOTES, 'UTF-8');
}
if (isset($_GET['message'])) {
    $success = htmlspecialchars($_GET['message'], ENT_QUOTES, 'UTF-8');
}

// إنشاء مدير الأمان
$security_setup_needed = false;
$security_error = '';

try {
    $security = new SecurityManager($conn);
    // التحقق من وجود الجداول الأمنية
    $security->createSecurityTables();
} catch (Exception $e) {
    $security_setup_needed = true;
    $security_error = $e->getMessage();
    error_log("خطأ في إعداد الأمان: " . $e->getMessage());

    // إنشاء كائن أمان مبسط للاستمرار
    $security = null;
}

// دوال مساعدة للأمان
function safe_sanitize_input($input) {
    return htmlspecialchars(trim($input), ENT_QUOTES, 'UTF-8');
}

function safe_csrf_token() {
    if (!isset($_SESSION['csrf_token'])) {
        $_SESSION['csrf_token'] = bin2hex(random_bytes(32));
    }
    return $_SESSION['csrf_token'];
}

function safe_validate_csrf($token) {
    return isset($_SESSION['csrf_token']) && hash_equals($_SESSION['csrf_token'], $token);
}

if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    // التحقق من رمز CSRF
    if (!safe_validate_csrf($_POST['csrf_token'] ?? '')) {
        $error = "رمز الأمان غير صحيح. يرجى إعادة تحميل الصفحة.";
    } else {
        $username = safe_sanitize_input($_POST['username'] ?? '');
        $password = $_POST['password'] ?? '';
        $ip_address = get_real_ip();

        // التحقق من صحة البيانات
        if (empty($username) || empty($password)) {
            $error = "يرجى إدخال اسم المستخدم وكلمة المرور.";
        } elseif ($security && method_exists($security, 'checkSuspiciousIP') && $security->checkSuspiciousIP($ip_address)) {
            $error = "تم حظر عنوان IP هذا مؤقتاً بسبب المحاولات المشبوهة.";
        } elseif ($security && method_exists($security, 'isUserLocked') && $security->isUserLocked($username)) {
            $error = "تم قفل هذا الحساب مؤقتاً بسبب المحاولات الفاشلة المتكررة.";
        } else {
            // محاولة تسجيل الدخول
            try {
            // التحقق من قاعدة البيانات أولاً - استخدام الأعمدة الموجودة فعلياً
            $stmt = $conn->prepare("SELECT user_id, username, password, password_hash, user_type, is_active FROM users WHERE username = ? AND is_active = 1");

            if ($stmt) {
                $stmt->bind_param("s", $username);
                $stmt->execute();
                $result = $stmt->get_result();

                if ($result->num_rows === 1) {
                    $user = $result->fetch_assoc();

                    // التحقق من كلمة المرور (دعم النظام القديم والجديد)
                    $password_valid = false;

                    // أولاً: التحقق من كلمة المرور المشفرة (النظام الجديد)
                    if (!empty($user['password_hash'])) {
                        $password_valid = password_verify($password, $user['password_hash']);
                    }
                    // ثانياً: التحقق من كلمة المرور غير المشفرة (النظام القديم)
                    elseif (!empty($user['password'])) {
                        $password_valid = ($password === $user['password']);

                        // إذا كانت كلمة المرور صحيحة، قم بتشفيرها وحفظها
                        if ($password_valid) {
                            $new_hash = password_hash($password, PASSWORD_DEFAULT);
                            $update_stmt = $conn->prepare("UPDATE users SET password_hash = ? WHERE user_id = ?");
                            if ($update_stmt) {
                                $update_stmt->bind_param("si", $new_hash, $user['user_id']);
                                $update_stmt->execute();
                                $update_stmt->close();
                            }
                        }
                    }

                    if ($password_valid) {
                        // تسجيل دخول ناجح
                        session_regenerate_id(true);
                        $_SESSION['user_id'] = $user['user_id'];
                        $_SESSION['username'] = $user['username'];
                        $_SESSION['user_type'] = $user['user_type'];
                        $_SESSION['last_activity'] = time();
                        $_SESSION['initiated'] = true;

                        // تحديث آخر دخول
                        $update_login_stmt = $conn->prepare("UPDATE users SET last_login = NOW() WHERE user_id = ?");
                        if ($update_login_stmt) {
                            $update_login_stmt->bind_param("i", $user['user_id']);
                            $update_login_stmt->execute();
                            $update_login_stmt->close();
                        }

                        // تسجيل تسجيل الدخول الناجح
                        if ($security && method_exists($security, 'logUserActivity')) {
                            $security->logUserActivity($user['user_id'], 'login', 'Successful login');
                        }
                        if ($security && method_exists($security, 'resetFailedAttempts')) {
                            $security->resetFailedAttempts($username);
                        }

                        header('Location: admin/dash.php');
                        exit;
                    } else {
                        $error = "اسم المستخدم أو كلمة المرور غير صحيحة.";
                        if ($security && method_exists($security, 'logFailedLogin')) {
                            $security->logFailedLogin($username, $ip_address);
                        }
                    }
                } else {
                    $error = "اسم المستخدم أو كلمة المرور غير صحيحة.";
                    if ($security && method_exists($security, 'logFailedLogin')) {
                        $security->logFailedLogin($username, $ip_address);
                    }
                }
                $stmt->close();
            } else {
                // إذا لم يكن جدول المستخدمين موجود، استخدم النظام القديم
                if ($username === 'admin' && $password === '1234') {
                    session_regenerate_id(true);
                    $_SESSION['user_id'] = 1;
                    $_SESSION['username'] = 'admin';
                    $_SESSION['user_type'] = 'admin';
                    $_SESSION['last_activity'] = time();
                    $_SESSION['initiated'] = true;
                    $_SESSION['ip_address'] = $ip_address;

                    header('Location: admin/dash.php');
                    exit;
                } else {
                    $error = "اسم المستخدم أو كلمة المرور غير صحيحة.";
                    if (method_exists($security, 'logFailedLogin')) {
                        $security->logFailedLogin($username, $ip_address);
                    }
                }
            }
        } catch (Exception $e) {
            error_log("خطأ في تسجيل الدخول: " . $e->getMessage());
            $error = "حدث خطأ في النظام. يرجى المحاولة مرة أخرى.";
        }
        }
    }
}
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
    <meta name="language" content="ar">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>نظام إدارة الفندق - تسجيل الدخول</title>
    <!-- الخطوط والأيقونات المحلية -->
    <link rel="stylesheet" href="assets/fonts/fonts.css">
    <link rel="stylesheet" href="assets/css/bootstrap-local.css">
    <link rel="stylesheet" href="assets/css/arabic-enhanced.css">

    <!-- Fallback للخطوط الخارجية -->
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" media="print" onload="this.media='all'">


    <style>
        :root {
            --primary-color: #1a4b88;
            --secondary-color: #f8b400;
            --accent-color: #28a745;
            --error-color: #dc3545;
            --text-color: #333;
            --light-bg: #f8f9fa;
        }

        * {
            box-sizing: border-box;
            margin: 0;
            padding: 0;
            font-family: 'Tajawal', 'Arial', sans-serif;
        }

        body {
            background-color: #f5f5f5;
            background-image: linear-gradient(rgba(0,0,0,0.5), rgba(0,0,0,0.5)), url('hotel-bg.jpg');
            background-size: cover;
            background-position: center;
            background-repeat: no-repeat;
            height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
            color: #fff;
            font-family: 'Tajawal', 'Arial', sans-serif;
            direction: rtl;
        }

        .login-container {
            width: 90%;
            max-width: 450px;
            background-color: rgba(255, 255, 255, 0.95);
            padding: 2rem;
            border-radius: 10px;
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
            text-align: center;
            animation: fadeIn 0.5s ease;
        }

        @keyframes fadeIn {
            from { opacity: 0; transform: translateY(-20px); }
            to { opacity: 1; transform: translateY(0); }
        }

        .logo {
            margin-bottom: 1.5rem;
            color: var(--primary-color);
        }

        .logo i {
            font-size: 3.5rem;
            margin-bottom: 0.5rem;
        }

        .logo h1 {
            font-size: 1.8rem;
            margin-bottom: 0.5rem;
            color: var(--primary-color);
        }

        .logo p {
            color: var(--text-color);
            font-size: 0.9rem;
        }

        h2 {
            color: var(--primary-color);
            margin-bottom: 1.5rem;
            font-size: 1.5rem;
        }

        .error-message {
            color: var(--error-color);
            margin-bottom: 1rem;
            font-weight: bold;
            padding: 10px;
            background-color: #f8d7da;
            border: 1px solid #f5c6cb;
            border-radius: 5px;
        }

        .success-message {
            color: var(--accent-color);
            margin-bottom: 1rem;
            font-weight: bold;
            padding: 10px;
            background-color: #d4edda;
            border: 1px solid #c3e6cb;
            border-radius: 5px;
        }

        .form-group {
            margin-bottom: 1.5rem;
            text-align: right;
        }

        label {
            display: block;
            margin-bottom: 0.5rem;
            color: var(--text-color);
            font-weight: 500;
        }

        input {
            width: 100%;
            padding: 12px 15px;
            border: 1px solid #ddd;
            border-radius: 5px;
            font-size: 1rem;
            transition: border 0.3s;
        }

        input:focus {
            outline: none;
            border-color: var(--primary-color);
            box-shadow: 0 0 0 3px rgba(26, 75, 136, 0.2);
        }

        .btn {
            width: 100%;
            padding: 12px;
            background-color: var(--primary-color);
            color: white;
            border: none;
            border-radius: 5px;
            font-size: 1rem;
            cursor: pointer;
            transition: background-color 0.3s;
        }

        .btn:hover {
            background-color: #0d3a6e;
        }

        .btn i {
            margin-left: 8px;
        }

        @media (max-width: 768px) {
            .login-container {
                padding: 1.5rem;
                width: 95%;
            }

            .logo h1 {
                font-size: 1.5rem;
            }
        }
    </style>
    <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@400;500;700&display=swap" rel="stylesheet">
</head>
<body>
    <div class="login-container">
        <div class="logo">
            <i class="fas fa-hotel"></i>
            <h1>نظام إدارة فندق مارينا بلازا</h1>
            <p>منصة الإدارة المتكاملة لخدمات الفندق</p>
        </div>

        <h2>تسجيل الدخول للنظام</h2>

        <?php if (!empty($error)): ?>
            <div class='error-message'><i class='fas fa-exclamation-circle'></i> <?php echo htmlspecialchars($error, ENT_QUOTES, 'UTF-8'); ?></div>
        <?php endif; ?>

        <?php if (!empty($success)): ?>
            <div class='success-message'><i class='fas fa-check-circle'></i> <?php echo htmlspecialchars($success, ENT_QUOTES, 'UTF-8'); ?></div>
        <?php endif; ?>

        <?php if ($security_setup_needed): ?>
            <div style="background: #fff3cd; color: #856404; border: 1px solid #ffeaa7; padding: 15px; border-radius: 5px; margin-bottom: 20px; text-align: center;">
                <i class="fas fa-exclamation-triangle"></i>
                <strong>تنبيه:</strong> يحتاج النظام إلى إعداد جداول الأمان.
                <br><br>
                <a href="setup_security_tables.php" style="color: #856404; text-decoration: underline; font-weight: bold;">انقر هنا لإعداد جداول الأمان</a>
            </div>
        <?php endif; ?>

        <form method="POST">
            <input type="hidden" name="csrf_token" value="<?php echo safe_csrf_token(); ?>">

            <div class="form-group">
                <label for="username"><i class="fas fa-user"></i> اسم المستخدم</label>
                <input type="text" id="username" name="username" required placeholder="أدخل اسم المستخدم" autocomplete="username">
            </div>

            <div class="form-group">
                <label for="password"><i class="fas fa-lock"></i> كلمة المرور</label>
                <input type="password" id="password" name="password" required placeholder="أدخل كلمة المرور" autocomplete="current-password">
            </div>

            <button type="submit" class="btn"><i class="fas fa-sign-in-alt"></i> تسجيل الدخول</button>
        </form>
    </div>
</body>
</html>
