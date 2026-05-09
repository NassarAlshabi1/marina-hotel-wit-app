<?php
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $action = $_POST['action'] ?? '';
    
    if ($action === 'use_codepen') {
        // النسخ الاحتياطي للهيدر الحالي
        if (file_exists('includes/header.php')) {
            copy('includes/header.php', 'includes/header-backup.php');
        }
        
        // استخدام هيدر CodePen
        if (file_exists('includes/header-codepen.php')) {
            copy('includes/header-codepen.php', 'includes/header.php');
            $message = 'تم تطبيق هيدر CodePen بنجاح! تم حفظ الهيدر القديم في header-backup.php';
            $type = 'success';
        } else {
            $message = 'لم يتم العثور على ملف header-codepen.php';
            $type = 'error';
        }
    }
    
    elseif ($action === 'restore_original') {
        // استرجاع الهيدر الأصلي
        if (file_exists('includes/header-backup.php')) {
            copy('includes/header-backup.php', 'includes/header.php');
            $message = 'تم استرجاع الهيدر الأصلي بنجاح!';
            $type = 'success';
        } else {
            $message = 'لم يتم العثور على النسخة الاحتياطية للهيدر';
            $type = 'error';
        }
    }
}
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تغيير الهيدر - فندق مارينا</title>
    <link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css">
    <style>
        * {
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }
        
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            align-items: center;
            justify-content: center;
            padding: 20px;
        }
        
        .container {
            background: white;
            border-radius: 15px;
            box-shadow: 0 20px 40px rgba(0,0,0,0.1);
            padding: 40px;
            max-width: 600px;
            width: 100%;
        }
        
        h1 {
            text-align: center;
            color: #2c3e50;
            margin-bottom: 30px;
            font-size: 2rem;
        }
        
        .option-card {
            background: #f8f9fa;
            border-radius: 10px;
            padding: 25px;
            margin-bottom: 20px;
            border: 2px solid transparent;
            transition: all 0.3s ease;
        }
        
        .option-card:hover {
            border-color: #3498db;
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.1);
        }
        
        .option-title {
            font-size: 1.3rem;
            color: #2c3e50;
            margin-bottom: 10px;
            display: flex;
            align-items: center;
        }
        
        .option-title i {
            margin-left: 10px;
            color: #3498db;
        }
        
        .option-description {
            color: #7f8c8d;
            margin-bottom: 15px;
            line-height: 1.6;
        }
        
        .btn {
            background: #3498db;
            color: white;
            border: none;
            padding: 12px 25px;
            border-radius: 25px;
            cursor: pointer;
            font-size: 1rem;
            font-weight: 500;
            transition: all 0.3s ease;
            width: 100%;
        }
        
        .btn:hover {
            background: #2980b9;
            transform: translateY(-2px);
            box-shadow: 0 5px 15px rgba(52, 152, 219, 0.3);
        }
        
        .btn-secondary {
            background: #95a5a6;
        }
        
        .btn-secondary:hover {
            background: #7f8c8d;
        }
        
        .alert {
            padding: 15px;
            border-radius: 10px;
            margin-bottom: 20px;
            text-align: center;
        }
        
        .alert-success {
            background: #d4edda;
            color: #155724;
            border: 1px solid #c3e6cb;
        }
        
        .alert-error {
            background: #f8d7da;
            color: #721c24;
            border: 1px solid #f5c6cb;
        }
        
        .preview-link {
            display: inline-block;
            margin-top: 15px;
            color: #3498db;
            text-decoration: none;
            font-weight: 500;
        }
        
        .preview-link:hover {
            text-decoration: underline;
        }
        
        .status-info {
            background: #e3f2fd;
            border-radius: 10px;
            padding: 20px;
            margin-bottom: 20px;
            border-left: 4px solid #2196f3;
        }
        
        .status-title {
            font-weight: bold;
            color: #1976d2;
            margin-bottom: 10px;
        }
        
        .file-status {
            display: flex;
            align-items: center;
            margin-bottom: 5px;
        }
        
        .file-status i {
            margin-left: 8px;
            width: 16px;
        }
        
        .file-exists {
            color: #4caf50;
        }
        
        .file-missing {
            color: #f44336;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>
            <i class="fas fa-exchange-alt"></i>
            تغيير الهيدر
        </h1>
        
        <?php if (isset($message)): ?>
            <div class="alert alert-<?= $type ?>">
                <i class="fas fa-<?= $type === 'success' ? 'check-circle' : 'exclamation-triangle' ?>"></i>
                <?= $message ?>
            </div>
        <?php endif; ?>
        
        <div class="status-info">
            <div class="status-title">حالة الملفات:</div>
            <div class="file-status">
                <i class="fas fa-file <?= file_exists('includes/header.php') ? 'file-exists' : 'file-missing' ?>"></i>
                Header الحالي: <?= file_exists('includes/header.php') ? 'موجود' : 'غير موجود' ?>
            </div>
            <div class="file-status">
                <i class="fas fa-file <?= file_exists('includes/header-codepen.php') ? 'file-exists' : 'file-missing' ?>"></i>
                Header CodePen: <?= file_exists('includes/header-codepen.php') ? 'موجود' : 'غير موجود' ?>
            </div>
            <div class="file-status">
                <i class="fas fa-file <?= file_exists('includes/header-backup.php') ? 'file-exists' : 'file-missing' ?>"></i>
                النسخة الاحتياطية: <?= file_exists('includes/header-backup.php') ? 'موجود' : 'غير موجود' ?>
            </div>
        </div>
        
        <form method="POST">
            <div class="option-card">
                <div class="option-title">
                    <i class="fas fa-rocket"></i>
                    استخدام هيدر CodePen الجديد
                </div>
                <div class="option-description">
                    سيتم استبدال الهيدر الحالي بالهيدر الجديد بأسلوب CodePen مع القوائم الفرعية التفاعلية.
                    سيتم حفظ نسخة احتياطية من الهيدر الحالي.
                </div>
                <button type="submit" name="action" value="use_codepen" class="btn">
                    <i class="fas fa-download"></i>
                    تطبيق هيدر CodePen
                </button>
                <a href="test_codepen_header.php" class="preview-link" target="_blank">
                    <i class="fas fa-eye"></i>
                    معاينة الهيدر الجديد
                </a>
            </div>
            
            <div class="option-card">
                <div class="option-title">
                    <i class="fas fa-undo"></i>
                    استرجاع الهيدر الأصلي
                </div>
                <div class="option-description">
                    سيتم استرجاع الهيدر الأصلي من النسخة الاحتياطية في حالة وجود مشاكل مع الهيدر الجديد.
                </div>
                <button type="submit" name="action" value="restore_original" class="btn btn-secondary" 
                        <?= !file_exists('includes/header-backup.php') ? 'disabled' : '' ?>>
                    <i class="fas fa-history"></i>
                    استرجاع الهيدر الأصلي
                </button>
            </div>
        </form>
        
        <div style="text-align: center; margin-top: 30px;">
            <a href="admin/dashboard.php" class="preview-link">
                <i class="fas fa-home"></i>
                العودة للرئيسية
            </a>
        </div>
    </div>
</body>
</html>