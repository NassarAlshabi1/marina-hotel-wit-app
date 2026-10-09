<?php
require_once 'auth.php';
// تحديد المنطقة الزمنية لعدن (اليمن)
date_default_timezone_set('Asia/Aden');

// تحديد المسار النسبي للأصول حسب موقع الملف
$current_dir = dirname($_SERVER['SCRIPT_NAME']);
$depth = substr_count($current_dir, '/') - 1; // عدد المستويات من الجذر
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>نظام إدارة الفندق</title>

    <!-- Bootstrap CSS -->
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
    <!-- Font Awesome -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet">
    <!-- Google Fonts -->
    <link href="https://fonts.googleapis.com/css2?family=Tajawal:wght@200;300;400;500;700;800;900&display=swap" rel="stylesheet">

    <style>
        body {
            font-family: 'Tajawal', sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            margin: 0;
            padding: 20px 0;
            direction: rtl;
            text-align: right;
            min-height: 100vh;
        }

        /* تنسيق عام للعناصر */
        * {
            font-family: 'Tajawal', sans-serif;
        }

        /* تنسيق الحاوي الرئيسي */
        .main-container {
            max-width: 1200px;
            margin: 0 auto;
            padding: 0 15px;
        }

        /* تنسيق رأس الصفحة */
        .page-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 20px;
            border-radius: 15px;
            margin-bottom: 25px;
            text-align: center;
            box-shadow: 0 8px 25px rgba(0,0,0,0.1);
        }

        .page-header h1 {
            margin-bottom: 10px;
            font-weight: 700;
            text-shadow: 0 2px 4px rgba(0,0,0,0.3);
        }

        /* تنسيق الجداول */
        .table {
            direction: rtl;
            text-align: right;
            background: white;
            border-radius: 10px;
            overflow: hidden;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }

        .table th {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            font-weight: 600;
            border: none;
            padding: 15px;
        }

        .table td {
            padding: 12px 15px;
            border-bottom: 1px solid #eee;
            vertical-align: middle;
        }

        .table-responsive {
            overflow-x: auto;
            border-radius: 10px;
        }

        /* تنسيق النماذج */
        .form-control, .form-select {
            direction: rtl;
            text-align: right;
            border-radius: 8px;
            border: 1px solid #ced4da;
            transition: all 0.3s ease;
        }

        .form-control:focus, .form-select:focus {
            border-color: #667eea;
            box-shadow: 0 0 0 0.25rem rgba(102, 126, 234, 0.25);
        }

        input[type="number"], input[type="tel"], .number-input {
            direction: ltr;
            text-align: left;
        }

        /* تنسيق الأزرار */
        .btn {
            border-radius: 8px;
            font-weight: 500;
            transition: all 0.3s ease;
            border: none;
        }

        .btn:hover {
            transform: translateY(-2px);
            box-shadow: 0 4px 12px rgba(0,0,0,0.15);
        }

        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
        }

        .btn-success {
            background: linear-gradient(135deg, #56ab2f 0%, #a8e6cf 100%);
        }

        .btn-danger {
            background: linear-gradient(135deg, #ff416c 0%, #ff4b2b 100%);
        }

        .btn-warning {
            background: linear-gradient(135deg, #f093fb 0%, #f5576c 100%);
        }

        .btn-secondary {
            background: linear-gradient(135deg, #6c757d 0%, #5a6268 100%);
        }

        .btn-info {
            background: linear-gradient(135deg, #17a2b8 0%, #138496 100%);
        }

        /* ألوان النصوص */
        .text-success { color: #28a745 !important; }
        .text-danger { color: #dc3545 !important; }
        .text-warning { color: #ffc107 !important; }
        .text-info { color: #17a2b8 !important; }

        /* تنسيق التنبيهات */
        .alert {
            font-size: 1rem;
            font-weight: 500;
            border-radius: 10px;
            border: none;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }

        /* تنسيق البطاقات */
        .card {
            border: none;
            border-radius: 15px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
            transition: all 0.3s ease;
        }

        .card:hover {
            transform: translateY(-5px);
            box-shadow: 0 8px 25px rgba(0,0,0,0.15);
        }

        .card-header {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border-radius: 15px 15px 0 0 !important;
            border: none;
            font-weight: 600;
        }

        /* أزرار العودة */
        .back-button {
            position: fixed;
            top: 20px;
            right: 20px;
            z-index: 1000;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
            border-radius: 50px;
            padding: 12px 20px;
            font-weight: 500;
            text-decoration: none;
            transition: all 0.3s ease;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
        }

        .back-button:hover {
            color: white;
            transform: translateY(-3px);
            box-shadow: 0 6px 20px rgba(0,0,0,0.3);
        }

        /* تنسيق متجاوب */
        @media (max-width: 768px) {
            .main-container {
                padding: 0 10px;
            }

            .page-header {
                padding: 15px;
                margin-bottom: 20px;
            }

            .page-header h1 {
                font-size: 1.5rem;
            }

            .table {
                font-size: 0.9rem;
            }

            .btn {
                font-size: 0.9rem;
                padding: 0.5rem 1rem;
            }

            .back-button {
                top: 10px;
                right: 10px;
                padding: 10px 15px;
                font-size: 0.9rem;
            }
        }

        @media (max-width: 576px) {
            .table th, .table td {
                padding: 8px 10px;
                font-size: 0.8rem;
            }

            .page-header h1 {
                font-size: 1.3rem;
            }
        }
    </style>
</head>
<body>
    <!-- زر العودة -->
    <a href="<?php echo str_repeat('../', max(0, $depth)); ?>admin/dash.php" class="back-button">
        <i class="fas fa-arrow-right me-2"></i>العودة للوحة التحكم
    </a>

    <div class="main-container">

        <?php if (isset($_SESSION['success'])): ?>
            <div class="alert alert-success alert-dismissible fade show" role="alert">
                <i class="fas fa-check-circle me-2"></i><?= htmlspecialchars($_SESSION['success']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['success']); ?>
        <?php endif; ?>

        <?php if (isset($_SESSION['error'])): ?>
            <div class="alert alert-danger alert-dismissible fade show" role="alert">
                <i class="fas fa-exclamation-triangle me-2"></i><?= htmlspecialchars($_SESSION['error']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['error']); ?>
        <?php endif; ?>

        <?php if (isset($_SESSION['warning'])): ?>
            <div class="alert alert-warning alert-dismissible fade show" role="alert">
                <i class="fas fa-exclamation-circle me-2"></i><?= htmlspecialchars($_SESSION['warning']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['warning']); ?>
        <?php endif; ?>

        <?php if (isset($_SESSION['info'])): ?>
            <div class="alert alert-info alert-dismissible fade show" role="alert">
                <i class="fas fa-info-circle me-2"></i><?= htmlspecialchars($_SESSION['info']) ?>
                <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
            </div>
            <?php unset($_SESSION['info']); ?>
        <?php endif; ?>

        <!-- باقي محتوى الصفحة -->
    </div>

    <!-- Bootstrap JS Bundle -->
    <script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js"></script>

    <script>
        // تحسين تجربة المستخدم
        document.addEventListener('DOMContentLoaded', function() {
            // إضافة تأثيرات للأزرار
            const buttons = document.querySelectorAll('.btn');
            buttons.forEach(button => {
                button.addEventListener('mouseenter', function() {
                    this.style.transform = 'translateY(-2px)';
                });
                button.addEventListener('mouseleave', function() {
                    this.style.transform = 'translateY(0)';
                });
            });

            // تحسين عرض التنبيهات
            const alerts = document.querySelectorAll('.alert');
            alerts.forEach(alert => {
                setTimeout(() => {
                    if (alert.classList.contains('alert-dismissible')) {
                        const closeBtn = alert.querySelector('.btn-close');
                        if (closeBtn) {
                            closeBtn.click();
                        }
                    }
                }, 5000); // إخفاء التنبيه بعد 5 ثوان
            });

            // تحسين الجداول
            const tables = document.querySelectorAll('.table');
            tables.forEach(table => {
                // إضافة تأثير hover للصفوف
                const rows = table.querySelectorAll('tbody tr');
                rows.forEach(row => {
                    row.addEventListener('mouseenter', function() {
                        this.style.backgroundColor = '#f8f9fa';
                    });
                    row.addEventListener('mouseleave', function() {
                        this.style.backgroundColor = '';
                    });
                });
            });
        });

        // دالة لتأكيد الحذف
        function confirmDelete(message = 'هل أنت متأكد من الحذف؟') {
            return confirm(message);
        }

        // دالة لعرض رسائل النجاح
        function showSuccess(message) {
            const alertDiv = document.createElement('div');
            alertDiv.className = 'alert alert-success alert-dismissible fade show';
            alertDiv.innerHTML = `
                <i class="fas fa-check-circle me-2"></i>${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            `;

            const container = document.querySelector('.main-container');
            if (container) {
                container.insertBefore(alertDiv, container.firstChild);
            }
        }

        // دالة لعرض رسائل الخطأ
        function showError(message) {
            const alertDiv = document.createElement('div');
            alertDiv.className = 'alert alert-danger alert-dismissible fade show';
            alertDiv.innerHTML = `
                <i class="fas fa-exclamation-triangle me-2"></i>${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            `;

            const container = document.querySelector('.main-container');
            if (container) {
                container.insertBefore(alertDiv, container.firstChild);
            }
        }

        // دالة لتنسيق الأرقام
        function formatNumber(num) {
            return new Intl.NumberFormat('ar-SA').format(num);
        }

        // دالة لتنسيق العملة
        function formatCurrency(amount, currency = 'ريال') {
            return formatNumber(amount) + ' ' + currency;
        }
    </script>
</body>
</html>
