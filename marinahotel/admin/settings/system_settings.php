<?php
session_start();
require_once __DIR__ . '/../../includes/auth.php';
require_once __DIR__ . '/../../includes/config.php';
require_once __DIR__ . '/../../includes/db.php';

// التحقق من تسجيل الدخول والصلاحيات
redirect_if_not_logged_in();
if (!isset($_SESSION['user_type']) || $_SESSION['user_type'] !== 'admin') {
    show_user_error(" ليس لديك صلاحية الوصول إلى هذه الصفحة.");
}

$message = '';
$messageType = '';

// معالجة الطلبات
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    
    switch ($action) {
        case 'update_general':
            $settings = [
                'hotel_name' => $_POST['hotel_name'] ?? '',
                'hotel_address' => $_POST['hotel_address'] ?? '',
                'hotel_phone' => $_POST['hotel_phone'] ?? '',
                'hotel_email' => $_POST['hotel_email'] ?? '',
                'currency' => $_POST['currency'] ?? 'ريال يمني',
                'timezone' => $_POST['timezone'] ?? 'Asia/Aden',
                'language' => $_POST['language'] ?? 'ar',
                'date_format' => $_POST['date_format'] ?? 'Y-m-d',
                'time_format' => $_POST['time_format'] ?? 'H:i'
            ];
            
            // تحديث الإعدادات في قاعدة البيانات
            foreach ($settings as $key => $value) {
                $stmt = $conn->prepare("INSERT INTO system_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = ?");
                $stmt->bind_param("sss", $key, $value, $value);
                $stmt->execute();
            }
            
            $message = 'تم تحديث الإعدادات العامة بنجاح';
            $messageType = 'success';
            break;
            
        case 'update_api':
            $settings = [
                'enable_api' => isset($_POST['enable_api']) ? '1' : '0',
                'api_rate_limit' => $_POST['api_rate_limit'] ?? '100'
            ];
            
            // توليد مفتاح API جديد إذا لم يكن موجوداً
            $stmt = $conn->prepare("SELECT setting_value FROM system_settings WHERE setting_key = 'api_key'");
            $stmt->execute();
            $result = $stmt->get_result();
            
            if ($result->num_rows === 0) {
                $settings['api_key'] = bin2hex(random_bytes(32));
                $stmt = $conn->prepare("INSERT INTO system_settings (setting_key, setting_value) VALUES ('api_key', ?)");
                $stmt->bind_param("s", $settings['api_key']);
                $stmt->execute();
            }
            
            // تحديث الإعدادات
            foreach ($settings as $key => $value) {
                $stmt = $conn->prepare("INSERT INTO system_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = ?");
                $stmt->bind_param("sss", $key, $value, $value);
                $stmt->execute();
            }
            
            $message = 'تم تحديث إعدادات API بنجاح';
            $messageType = 'success';
            break;
            
        case 'regenerate_api_key':
            $newApiKey = bin2hex(random_bytes(32));
            $stmt = $conn->prepare("UPDATE system_settings SET setting_value = ? WHERE setting_key = 'api_key'");
            $stmt->bind_param("s", $newApiKey);
            if ($stmt->execute()) {
                $message = 'تم توليد مفتاح API جديد بنجاح';
                $messageType = 'success';
            } else {
                $message = 'حدث خطأ في توليد مفتاح API';
                $messageType = 'error';
            }
            break;
            
        case 'update_mobile':
            $settings = [
                'android_app_ip' => $_POST['android_app_ip'] ?? '',
                'android_app_port' => $_POST['android_app_port'] ?? '8082'
            ];
            
            foreach ($settings as $key => $value) {
                $stmt = $conn->prepare("INSERT INTO system_settings (setting_key, setting_value) VALUES (?, ?) ON DUPLICATE KEY UPDATE setting_value = ?");
                $stmt->bind_param("sss", $key, $value, $value);
                $stmt->execute();
            }
            
            $message = 'تم تحديث إعدادات تطبيق الأندرويد بنجاح';
            $messageType = 'success';
            break;
            
        case 'test_android_connection':
            $ip = $_POST['android_app_ip'] ?? '';
            $port = $_POST['android_app_port'] ?? '8082';
            
            if ($ip && $port) {
                $connection = @fsockopen($ip, $port, $errno, $errstr, 5);
                if ($connection) {
                    fclose($connection);
                    $message = 'تم الاتصال بتطبيق الأندرويد بنجاح';
                    $messageType = 'success';
                } else {
                    $message = "فشل الاتصال بتطبيق الأندرويد: $errstr ($errno)";
                    $messageType = 'error';
                }
            } else {
                $message = 'يرجى إدخال عنوان IP ورقم المنفذ';
                $messageType = 'error';
            }
            break;
    }
}

// الحصول على الإعدادات الحالية
function get_setting($key, $default = '') {
    global $conn;
    $stmt = $conn->prepare("SELECT setting_value FROM system_settings WHERE setting_key = ?");
    $stmt->bind_param("s", $key);
    $stmt->execute();
    $result = $stmt->get_result();
    if ($row = $result->fetch_assoc()) {
        return $row['setting_value'];
    }
    return $default;
}

// تضمين الهيدر
include_once __DIR__ . '/../../includes/header.php';
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إعدادات النظام - نظام إدارة فندق مارينا بلازا</title>
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background-color: #f5f5f5;
            color: #333;
            line-height: 1.6;
        }
        
        .container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }
        
        .header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 10px;
            margin-bottom: 30px;
            text-align: center;
        }
        
        .header h1 {
            font-size: 2.5em;
            margin-bottom: 10px;
        }
        
        .nav-tabs {
            display: flex;
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 30px;
            flex-wrap: wrap;
        }
        
        .nav-tab {
            flex: 1;
            padding: 15px 10px;
            background: white;
            border: none;
            cursor: pointer;
            font-size: 14px;
            transition: all 0.3s ease;
            min-width: 120px;
        }
        
        .nav-tab.active {
            background: #667eea;
            color: white;
        }
        
        .nav-tab:hover {
            background: #f0f0f0;
        }
        
        .nav-tab.active:hover {
            background: #5a67d8;
        }
        
        .tab-content {
            display: none;
        }
        
        .tab-content.active {
            display: block;
        }
        
        .card {
            background: white;
            border-radius: 10px;
            padding: 30px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
            margin-bottom: 30px;
        }
        
        .form-group {
            margin-bottom: 20px;
        }
        
        .form-group label {
            display: block;
            margin-bottom: 8px;
            font-weight: bold;
            color: #555;
        }
        
        .form-group input,
        .form-group select,
        .form-group textarea {
            width: 100%;
            padding: 12px;
            border: 2px solid #e1e1e1;
            border-radius: 8px;
            font-size: 16px;
            transition: border-color 0.3s ease;
        }
        
        .form-group input:focus,
        .form-group select:focus,
        .form-group textarea:focus {
            outline: none;
            border-color: #667eea;
        }
        
        .form-group textarea {
            min-height: 100px;
            resize: vertical;
        }
        
        .checkbox-group {
            display: flex;
            align-items: center;
            gap: 10px;
        }
        
        .checkbox-group input[type="checkbox"] {
            width: auto;
            margin: 0;
        }
        
        .btn {
            padding: 12px 24px;
            border: none;
            border-radius: 8px;
            cursor: pointer;
            font-size: 16px;
            transition: all 0.3s ease;
            text-decoration: none;
            display: inline-block;
            text-align: center;
        }
        
        .btn-primary {
            background: #667eea;
            color: white;
        }
        
        .btn-primary:hover {
            background: #5a67d8;
        }
        
        .btn-success {
            background: #48bb78;
            color: white;
        }
        
        .btn-success:hover {
            background: #38a169;
        }
        
        .btn-warning {
            background: #ed8936;
            color: white;
        }
        
        .btn-warning:hover {
            background: #dd6b20;
        }
        
        .btn-secondary {
            background: #718096;
            color: white;
        }
        
        .btn-secondary:hover {
            background: #4a5568;
        }
        
        .message {
            padding: 15px;
            border-radius: 8px;
            margin-bottom: 20px;
            font-weight: bold;
        }
        
        .message.success {
            background: #c6f6d5;
            color: #22543d;
            border: 1px solid #9ae6b4;
        }
        
        .message.error {
            background: #fed7d7;
            color: #742a2a;
            border: 1px solid #fc8181;
        }
        
        .back-link {
            display: inline-block;
            margin-bottom: 20px;
            color: #667eea;
            text-decoration: none;
            font-weight: bold;
        }
        
        .back-link:hover {
            text-decoration: underline;
        }
        
        .form-row {
            display: flex;
            gap: 20px;
        }
        
        .form-row .form-group {
            flex: 1;
        }
        
        .info-box {
            background: #e6fffa;
            border: 1px solid #81e6d9;
            border-radius: 8px;
            padding: 15px;
            margin-bottom: 20px;
        }
        
        .info-box h4 {
            color: #234e52;
            margin-bottom: 10px;
        }
        
        .info-box p {
            color: #285e61;
            margin: 0;
        }
        
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-left: 8px;
        }
        
        .status-active {
            background: #48bb78;
        }
        
        .status-inactive {
            background: #f56565;
        }
        
        .api-key-display {
            background: #f7fafc;
            border: 1px solid #e2e8f0;
            border-radius: 8px;
            padding: 12px;
            font-family: monospace;
            font-size: 14px;
            word-break: break-all;
            margin-bottom: 10px;
        }
        
        .actions {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        
        @media (max-width: 768px) {
            .form-row {
                flex-direction: column;
                gap: 10px;
            }
            
            .nav-tabs {
                flex-direction: column;
            }
            
            .nav-tab {
                width: 100%;
                text-align: center;
            }
        }
    </style>
</head>
<body>
    <div class="container">
        <a href="index.php" class="back-link">← العودة للوحة التحكم</a>
        
        <div class="header">
            <h1>إعدادات النظام</h1>
            <p>إدارة وتكوين جميع جوانب النظام</p>
        </div>
        
        <?php if ($message): ?>
            <div class="message <?php echo $messageType; ?>">
                <?php echo htmlspecialchars($message); ?>
            </div>
        <?php endif; ?>
        
        <div class="nav-tabs">
            <button class="nav-tab active" onclick="showTab('general')">الإعدادات العامة</button>
            <button class="nav-tab" onclick="showTab('api')">API</button>
            <button class="nav-tab" onclick="showTab('mobile')">تطبيق الأندرويد</button>
        </div>
        
        <!-- الإعدادات العامة -->
        <div id="general" class="tab-content active">
            <div class="card">
                <h2>الإعدادات العامة</h2>
                <form method="post">
                    <input type="hidden" name="action" value="update_general">
                    
                    <div class="form-group">
                        <label for="hotel_name">اسم الفندق</label>
                        <input type="text" id="hotel_name" name="hotel_name" value="<?php echo htmlspecialchars(get_setting('hotel_name', 'فندق مارينا بلازا')); ?>">
                    </div>
                    
                    <div class="form-group">
                        <label for="hotel_address">عنوان الفندق</label>
                        <textarea id="hotel_address" name="hotel_address"><?php echo htmlspecialchars(get_setting('hotel_address', '')); ?></textarea>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="hotel_phone">رقم الهاتف</label>
                            <input type="text" id="hotel_phone" name="hotel_phone" value="<?php echo htmlspecialchars(get_setting('hotel_phone', '')); ?>">
                        </div>
                        
                        <div class="form-group">
                            <label for="hotel_email">البريد الإلكتروني</label>
                            <input type="email" id="hotel_email" name="hotel_email" value="<?php echo htmlspecialchars(get_setting('hotel_email', '')); ?>">
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="currency">العملة</label>
                            <select id="currency" name="currency">
                                <option value="ريال يمني" <?php echo get_setting('currency') === 'ريال يمني' ? 'selected' : ''; ?>>ريال يمني</option>
                                <option value="ريال سعودي" <?php echo get_setting('currency') === 'ريال سعودي' ? 'selected' : ''; ?>>ريال سعودي</option>
                                <option value="دولار أمريكي" <?php echo get_setting('currency') === 'دولار أمريكي' ? 'selected' : ''; ?>>دولار أمريكي</option>
                                <option value="يورو" <?php echo get_setting('currency') === 'يورو' ? 'selected' : ''; ?>>يورو</option>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label for="timezone">المنطقة الزمنية</label>
                            <select id="timezone" name="timezone">
                                <option value="Asia/Aden" <?php echo get_setting('timezone') === 'Asia/Aden' ? 'selected' : ''; ?>>عدن</option>
                                <option value="Asia/Riyadh" <?php echo get_setting('timezone') === 'Asia/Riyadh' ? 'selected' : ''; ?>>الرياض</option>
                                <option value="Asia/Dubai" <?php echo get_setting('timezone') === 'Asia/Dubai' ? 'selected' : ''; ?>>دبي</option>
                                <option value="Asia/Kuwait" <?php echo get_setting('timezone') === 'Asia/Kuwait' ? 'selected' : ''; ?>>الكويت</option>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label for="language">اللغة</label>
                            <select id="language" name="language">
                                <option value="ar" <?php echo get_setting('language') === 'ar' ? 'selected' : ''; ?>>العربية</option>
                                <option value="en" <?php echo get_setting('language') === 'en' ? 'selected' : ''; ?>>English</option>
                            </select>
                        </div>
                    </div>
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="date_format">تنسيق التاريخ</label>
                            <select id="date_format" name="date_format">
                                <option value="Y-m-d" <?php echo get_setting('date_format') === 'Y-m-d' ? 'selected' : ''; ?>>YYYY-MM-DD</option>
                                <option value="d/m/Y" <?php echo get_setting('date_format') === 'd/m/Y' ? 'selected' : ''; ?>>DD/MM/YYYY</option>
                                <option value="m/d/Y" <?php echo get_setting('date_format') === 'm/d/Y' ? 'selected' : ''; ?>>MM/DD/YYYY</option>
                            </select>
                        </div>
                        
                        <div class="form-group">
                            <label for="time_format">تنسيق الوقت</label>
                            <select id="time_format" name="time_format">
                                <option value="H:i" <?php echo get_setting('time_format') === 'H:i' ? 'selected' : ''; ?>>24 ساعة</option>
                                <option value="h:i A" <?php echo get_setting('time_format') === 'h:i A' ? 'selected' : ''; ?>>12 ساعة</option>
                            </select>
                        </div>
                    </div>
                    
                    <button type="submit" class="btn btn-primary">حفظ الإعدادات العامة</button>
                </form>
            </div>
        </div>
        
        <!-- إعدادات API -->
        <div id="api" class="tab-content">
            <div class="card">
                <h2>إعدادات API</h2>
                
                <div class="info-box">
                    <h4>حالة API</h4>
                    <p>
                        API حالياً: 
                        <?php if (get_setting('enable_api') === '1'): ?>
                            <span class="status-indicator status-active"></span> مفعل
                        <?php else: ?>
                            <span class="status-indicator status-inactive"></span> غير مفعل
                        <?php endif; ?>
                    </p>
                </div>
                
                <form method="post">
                    <input type="hidden" name="action" value="update_api">
                    
                    <div class="form-group">
                        <div class="checkbox-group">
                            <input type="checkbox" id="enable_api" name="enable_api" <?php echo get_setting('enable_api') === '1' ? 'checked' : ''; ?>>
                            <label for="enable_api">تفعيل API</label>
                        </div>
                    </div>
                    
                    <div class="form-group">
                        <label for="api_rate_limit">حد معدل الطلبات (في الساعة)</label>
                        <input type="number" id="api_rate_limit" name="api_rate_limit" value="<?php echo htmlspecialchars(get_setting('api_rate_limit', '100')); ?>" min="1" max="10000">
                    </div>
                    
                    <div class="form-group">
                        <label>مفتاح API الحالي</label>
                        <div class="api-key-display">
                            <?php echo htmlspecialchars(get_setting('api_key', 'غير متوفر')); ?>
                        </div>
                    </div>
                    
                    <div class="actions">
                        <button type="submit" class="btn btn-primary">حفظ إعدادات API</button>
                        <button type="submit" name="action" value="regenerate_api_key" class="btn btn-warning" onclick="return confirm('هل أنت متأكد من توليد مفتاح API جديد؟ سيتوجب تحديث جميع التطبيقات التي تستخدم المفت钥 الحالي.')">توليد مفتاح جديد</button>
                    </div>
                </form>
            </div>
        </div>
        
        <!-- إعدادات تطبيق الأندرويد -->
        <div id="mobile" class="tab-content">
            <div class="card">
                <h2>إعدادات تطبيق الأندرويد</h2>
                
                <div class="info-box">
                    <h4>ربط تطبيق الأندرويد</h4>
                    <p>قم بإدخال عنوان IP للجهاز الذي يعمل عليه تطبيق الأندرويد لربطه بالنظام عبر الشبكة المحلية.</p>
                </div>
                
                <form method="post">
                    <input type="hidden" name="action" value="update_mobile">
                    
                    <div class="form-row">
                        <div class="form-group">
                            <label for="android_app_ip">عنوان IP لتطبيق الأندرويد</label>
                            <input type="text" id="android_app_ip" name="android_app_ip" value="<?php echo htmlspecialchars(get_setting('android_app_ip', '')); ?>" placeholder="192.168.1.100">
                        </div>
                        
                        <div class="form-group">
                            <label for="android_app_port">منفذ تطبيق الأندرويد</label>
                            <input type="number" id="android_app_port" name="android_app_port" value="<?php echo htmlspecialchars(get_setting('android_app_port', '8082')); ?>" min="1024" max="65535">
                        </div>
                    </div>
                    
                    <div class="actions">
                        <button type="submit" class="btn btn-primary">حفظ إعدادات الأندرويد</button>
                        <button type="submit" name="action" value="test_android_connection" class="btn btn-secondary">اختبار الاتصال</button>
                    </div>
                </form>
            </div>
        </div>
    </div>
    
    <script>
        function showTab(tabName) {
            // إخفاء جميع التبويبات
            const tabs = document.querySelectorAll('.tab-content');
            tabs.forEach(tab => tab.classList.remove('active'));
            
            // إزالة الفئة النشطة من جميع أزرار التبويب
            const navTabs = document.querySelectorAll('.nav-tab');
            navTabs.forEach(tab => tab.classList.remove('active'));
            
            // إظهار التبويب المحدد
            document.getElementById(tabName).classList.add('active');
            
            // إضافة الفئة النشطة لزر التبويب المحدد
            event.target.classList.add('active');
        }
    </script>
</body>
</html>