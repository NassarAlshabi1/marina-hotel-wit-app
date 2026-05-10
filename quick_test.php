<?php
session_start();
?>
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <title>اختبار سريع</title>
</head>
<body>
    <h2>اختبار سريع للنظام</h2>
    
    <?php if (isset($_SESSION['user_id'])): ?>
        <p>✅ مسجل دخول: <?= $_SESSION['username'] ?></p>
        <p>نوع المستخدم: <?= $_SESSION['user_type'] ?? 'غير محدد' ?></p>
        <p>الدور: <?= $_SESSION['role'] ?? 'غير محدد' ?></p>
        
        <h3>اختبار الوصول:</h3>
        <a href="admin/expenses/list.php" target="_blank">صفحة المصروفات</a>
        
    <?php else: ?>
        <p>❌ غير مسجل دخول</p>
        <a href="login.php">تسجيل الدخول</a>
    <?php endif; ?>
    
    <h3>تفاصيل الجلسة:</h3>
    <pre><?= print_r($_SESSION, true) ?></pre>
</body>
</html>