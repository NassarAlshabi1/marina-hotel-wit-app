<?php
include_once '../../includes/db.php';
include_once '../../includes/auth.php';

$message = '';
$error = '';

// معالجة العمليات
if ($_SERVER['REQUEST_METHOD'] == 'POST') {
    
    // تنظيف الجلسات المنتهية الصلاحية
    if (isset($_POST['clean_sessions'])) {
        try {
            // حذف الجلسات القديمة (أكثر من 24 ساعة)
            $result = $conn->query("DELETE FROM user_sessions WHERE last_activity < DATE_SUB(NOW(), INTERVAL 24 HOUR)");
            $message = "تم تنظيف الجلسات المنتهية الصلاحية بنجاح";
        } catch (Exception $e) {
            $error = "خطأ في تنظيف الجلسات: " . $e->getMessage();
        }
    }
    
    // تنظيف السجلات القديمة
    if (isset($_POST['clean_logs'])) {
        try {
            // حذف السجلات الأقدم من 30 يوم
            $result = $conn->query("DELETE FROM system_logs WHERE created_at < DATE_SUB(NOW(), INTERVAL 30 DAY)");
            $message = "تم تنظيف السجلات القديمة بنجاح";
        } catch (Exception $e) {
            $error = "خطأ في تنظيف السجلات: " . $e->getMessage();
        }
    }
    
    // إعادة تعيين كلمة مرور المدير
    if (isset($_POST['reset_admin_password'])) {
        $new_password = $_POST['new_password'];
        $confirm_password = $_POST['confirm_password'];
        
        if (empty($new_password) || strlen($new_password) < 6) {
            $error = "كلمة المرور يجب أن تكون 6 أحرف على الأقل";
        } elseif ($new_password !== $confirm_password) {
            $error = "كلمة المرور وتأكيد كلمة المرور غير متطابقتان";
        } else {
            try {
                $hashed_password = password_hash($new_password, PASSWORD_DEFAULT);
                $stmt = $conn->prepare("UPDATE users SET password = ? WHERE role = 'admin' LIMIT 1");
                $stmt->bind_param("s", $hashed_password);
                $stmt->execute();
                $message = "تم تغيير كلمة مرور المدير بنجاح";
            } catch (Exception $e) {
                $error = "خطأ في تغيير كلمة المرور: " . $e->getMessage();
            }
        }
    }
    
    // إصلاح حالات الغرف
    if (isset($_POST['fix_room_status'])) {
        try {
            // تحديث حالة الغرف بناءً على الحجوزات النشطة
            $conn->query("
                UPDATE rooms r 
                LEFT JOIN bookings b ON r.room_number = b.room_number AND b.status = 'محجوزة'
                SET r.status = CASE 
                    WHEN b.room_number IS NOT NULL THEN 'محجوزة'
                    ELSE 'شاغرة'
                END
            ");
            $message = "تم إصلاح حالات الغرف بنجاح";
        } catch (Exception $e) {
            $error = "خطأ في إصلاح حالات الغرف: " . $e->getMessage();
        }
    }
    
    // تحسين قاعدة البيانات
    if (isset($_POST['optimize_database'])) {
        try {
            $tables = ['bookings', 'rooms', 'payment', 'expenses', 'users'];
            foreach ($tables as $table) {
                $conn->query("OPTIMIZE TABLE $table");
            }
            $message = "تم تحسين قاعدة البيانات بنجاح";
        } catch (Exception $e) {
            $error = "خطأ في تحسين قاعدة البيانات: " . $e->getMessage();
        }
    }
    
    // إعادة بناء الفهارس
    if (isset($_POST['rebuild_indexes'])) {
        try {
            $indexes = [
                "ALTER TABLE bookings ADD INDEX idx_guest_name (guest_name)",
                "ALTER TABLE bookings ADD INDEX idx_room_number (room_number)",
                "ALTER TABLE bookings ADD INDEX idx_checkin_date (checkin_date)",
                "ALTER TABLE payment ADD INDEX idx_booking_id (booking_id)",
                "ALTER TABLE expenses ADD INDEX idx_date (date)"
            ];

            foreach ($indexes as $index) {
                try {
                    $conn->query($index);
                } catch (Exception $e) {
                    // تجاهل الأخطاء إذا كان الفهرس موجود مسبقاً
                }
            }
            $message = "تم إعادة بناء الفهارس بنجاح";
        } catch (Exception $e) {
            $error = "خطأ في إعادة بناء الفهارس: " . $e->getMessage();
        }
    }

    // فحص سلامة البيانات
    if (isset($_POST['check_data_integrity'])) {
        try {
            $issues = [];

            // فحص الحجوزات بدون غرف
            $result = $conn->query("
                SELECT COUNT(*) as count
                FROM bookings b
                LEFT JOIN rooms r ON b.room_number = r.room_number
                WHERE r.room_number IS NULL
            ");
            $orphaned_bookings = $result->fetch_assoc()['count'];
            if ($orphaned_bookings > 0) {
                $issues[] = "يوجد $orphaned_bookings حجز مرتبط بغرف غير موجودة";
            }

            // فحص المدفوعات بدون حجوزات
            $result = $conn->query("
                SELECT COUNT(*) as count
                FROM payment p
                LEFT JOIN bookings b ON p.booking_id = b.booking_id
                WHERE b.booking_id IS NULL
            ");
            $orphaned_payments = $result->fetch_assoc()['count'];
            if ($orphaned_payments > 0) {
                $issues[] = "يوجد $orphaned_payments دفعة مرتبطة بحجوزات غير موجودة";
            }

            if (empty($issues)) {
                $message = "فحص سلامة البيانات: لا توجد مشاكل";
            } else {
                $error = "مشاكل في سلامة البيانات:<br>" . implode("<br>", $issues);
            }
        } catch (Exception $e) {
            $error = "خطأ في فحص سلامة البيانات: " . $e->getMessage();
        }
    }

    // إنشاء نسخة احتياطية سريعة
    if (isset($_POST['quick_backup'])) {
        try {
            $backup_dir = '../../backups/';
            if (!is_dir($backup_dir)) {
                mkdir($backup_dir, 0755, true);
            }

            $filename = 'quick_backup_' . date('Y-m-d_H-i-s') . '.sql';
            $filepath = $backup_dir . $filename;

            // تصدير البيانات الأساسية
            $tables = ['rooms', 'bookings', 'payment', 'expenses'];
            $backup_content = "-- نسخة احتياطية سريعة - " . date('Y-m-d H:i:s') . "\n\n";

            foreach ($tables as $table) {
                $result = $conn->query("SELECT * FROM $table");
                if ($result && $result->num_rows > 0) {
                    $backup_content .= "-- جدول $table\n";
                    $backup_content .= "TRUNCATE TABLE $table;\n";

                    while ($row = $result->fetch_assoc()) {
                        $values = array_map(function($value) use ($conn) {
                            return $value === null ? 'NULL' : "'" . $conn->real_escape_string($value) . "'";
                        }, $row);

                        $backup_content .= "INSERT INTO $table VALUES (" . implode(', ', $values) . ");\n";
                    }
                    $backup_content .= "\n";
                }
            }

            file_put_contents($filepath, $backup_content);
            $message = "تم إنشاء نسخة احتياطية سريعة: $filename";
        } catch (Exception $e) {
            $error = "خطأ في إنشاء النسخة الاحتياطية: " . $e->getMessage();
        }
    }
}

// جلب إحصائيات النظام
$system_stats = [];

// حجم قاعدة البيانات
try {
    $db_size_query = "
        SELECT 
            ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) AS db_size_mb
        FROM information_schema.tables 
        WHERE table_schema = DATABASE()
    ";
    $result = $conn->query($db_size_query);
    $system_stats['db_size'] = $result->fetch_assoc()['db_size_mb'] ?? 0;
} catch (Exception $e) {
    $system_stats['db_size'] = 'غير متاح';
}

// عدد السجلات في الجداول الرئيسية
$tables = ['bookings', 'rooms', 'payment', 'expenses'];
foreach ($tables as $table) {
    try {
        $result = $conn->query("SELECT COUNT(*) as count FROM $table");
        $system_stats[$table . '_count'] = $result->fetch_assoc()['count'];
    } catch (Exception $e) {
        $system_stats[$table . '_count'] = 0;
    }
}

// تضمين الهيدر بعد انتهاء معالجة POST
include_once '../../includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="d-flex justify-content-between align-items-center mb-4">
                <h2><i class="fas fa-tools me-2"></i>صيانة النظام</h2>
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

    <?php if (!empty($message)): ?>
        <div class="alert alert-success alert-dismissible fade show" role="alert">
            <i class="fas fa-check-circle me-2"></i><?= $message ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <?php if (!empty($error)): ?>
        <div class="alert alert-danger alert-dismissible fade show" role="alert">
            <i class="fas fa-exclamation-circle me-2"></i><?= $error ?>
            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
        </div>
    <?php endif; ?>

    <!-- إحصائيات النظام -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0"><i class="fas fa-chart-bar me-2"></i>إحصائيات النظام</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-3">
                            <div class="text-center">
                                <h4 class="text-primary"><?= $system_stats['db_size'] ?> MB</h4>
                                <p class="mb-0">حجم قاعدة البيانات</p>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="text-center">
                                <h4 class="text-success"><?= $system_stats['bookings_count'] ?></h4>
                                <p class="mb-0">إجمالي الحجوزات</p>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="text-center">
                                <h4 class="text-warning"><?= $system_stats['payment_count'] ?></h4>
                                <p class="mb-0">إجمالي المدفوعات</p>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="text-center">
                                <h4 class="text-danger"><?= $system_stats['expenses_count'] ?></h4>
                                <p class="mb-0">إجمالي المصروفات</p>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- أدوات التنظيف -->
    <div class="row mb-4">
        <div class="col-md-6">
            <div class="card">
                <div class="card-header bg-warning text-dark">
                    <h5 class="mb-0"><i class="fas fa-broom me-2"></i>أدوات التنظيف</h5>
                </div>
                <div class="card-body">
                    <form method="POST" class="mb-3">
                        <p class="card-text">تنظيف الجلسات المنتهية الصلاحية (أكثر من 24 ساعة)</p>
                        <button type="submit" name="clean_sessions" class="btn btn-warning" 
                                onclick="return confirm('هل أنت متأكد من تنظيف الجلسات؟')">
                            <i class="fas fa-trash me-1"></i>تنظيف الجلسات
                        </button>
                    </form>
                    
                    <form method="POST">
                        <p class="card-text">تنظيف السجلات القديمة (أكثر من 30 يوم)</p>
                        <button type="submit" name="clean_logs" class="btn btn-warning"
                                onclick="return confirm('هل أنت متأكد من حذف السجلات القديمة؟')">
                            <i class="fas fa-file-alt me-1"></i>تنظيف السجلات
                        </button>
                    </form>
                </div>
            </div>
        </div>

        <div class="col-md-6">
            <div class="card">
                <div class="card-header bg-success text-white">
                    <h5 class="mb-0"><i class="fas fa-wrench me-2"></i>أدوات الإصلاح</h5>
                </div>
                <div class="card-body">
                    <form method="POST" class="mb-3">
                        <p class="card-text">إصلاح حالات الغرف بناءً على الحجوزات النشطة</p>
                        <button type="submit" name="fix_room_status" class="btn btn-success">
                            <i class="fas fa-bed me-1"></i>إصلاح حالات الغرف
                        </button>
                    </form>
                    
                    <form method="POST">
                        <p class="card-text">تحسين أداء قاعدة البيانات</p>
                        <button type="submit" name="optimize_database" class="btn btn-success"
                                onclick="return confirm('هل أنت متأكد من تحسين قاعدة البيانات؟')">
                            <i class="fas fa-database me-1"></i>تحسين قاعدة البيانات
                        </button>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- أدوات متقدمة -->
    <div class="row mb-4">
        <div class="col-md-6">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0"><i class="fas fa-cogs me-2"></i>أدوات متقدمة</h5>
                </div>
                <div class="card-body">
                    <form method="POST" class="mb-3">
                        <p class="card-text">إعادة بناء فهارس قاعدة البيانات لتحسين الأداء</p>
                        <button type="submit" name="rebuild_indexes" class="btn btn-primary"
                                onclick="return confirm('هل أنت متأكد من إعادة بناء الفهارس؟')">
                            <i class="fas fa-list me-1"></i>إعادة بناء الفهارس
                        </button>
                    </form>

                    <form method="POST" class="mb-3">
                        <p class="card-text">فحص سلامة البيانات والبحث عن المشاكل</p>
                        <button type="submit" name="check_data_integrity" class="btn btn-info">
                            <i class="fas fa-search me-1"></i>فحص سلامة البيانات
                        </button>
                    </form>

                    <form method="POST">
                        <p class="card-text">إنشاء نسخة احتياطية سريعة للبيانات الأساسية</p>
                        <button type="submit" name="quick_backup" class="btn btn-secondary">
                            <i class="fas fa-download me-1"></i>نسخة احتياطية سريعة
                        </button>
                    </form>
                </div>
            </div>
        </div>

        <div class="col-md-6">
            <div class="card">
                <div class="card-header bg-danger text-white">
                    <h5 class="mb-0"><i class="fas fa-key me-2"></i>إعادة تعيين كلمة مرور المدير</h5>
                </div>
                <div class="card-body">
                    <form method="POST">
                        <div class="mb-3">
                            <label for="new_password" class="form-label">كلمة المرور الجديدة</label>
                            <input type="password" class="form-control" id="new_password" name="new_password" required>
                        </div>
                        <div class="mb-3">
                            <label for="confirm_password" class="form-label">تأكيد كلمة المرور</label>
                            <input type="password" class="form-control" id="confirm_password" name="confirm_password" required>
                        </div>
                        <button type="submit" name="reset_admin_password" class="btn btn-danger"
                                onclick="return confirm('هل أنت متأكد من تغيير كلمة مرور المدير؟')">
                            <i class="fas fa-key me-1"></i>تغيير كلمة المرور
                        </button>
                    </form>
                </div>
            </div>
        </div>
    </div>

    <!-- معلومات النظام -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-dark text-white">
                    <h5 class="mb-0"><i class="fas fa-info-circle me-2"></i>معلومات النظام</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-4">
                            <h6>معلومات الخادم</h6>
                            <ul class="list-unstyled">
                                <li><strong>إصدار PHP:</strong> <?= phpversion() ?></li>
                                <li><strong>إصدار MySQL:</strong> <?= $conn->server_info ?></li>
                                <li><strong>نظام التشغيل:</strong> <?= PHP_OS ?></li>
                                <li><strong>الذاكرة المتاحة:</strong> <?= ini_get('memory_limit') ?></li>
                            </ul>
                        </div>
                        <div class="col-md-4">
                            <h6>إعدادات PHP</h6>
                            <ul class="list-unstyled">
                                <li><strong>حد رفع الملفات:</strong> <?= ini_get('upload_max_filesize') ?></li>
                                <li><strong>حد تنفيذ السكريبت:</strong> <?= ini_get('max_execution_time') ?>s</li>
                                <li><strong>المنطقة الزمنية:</strong> <?= date_default_timezone_get() ?></li>
                                <li><strong>الترميز:</strong> <?= ini_get('default_charset') ?></li>
                            </ul>
                        </div>
                        <div class="col-md-4">
                            <h6>حالة النظام</h6>
                            <ul class="list-unstyled">
                                <li><strong>وقت التشغيل:</strong> <?= date('Y-m-d H:i:s') ?></li>
                                <li><strong>المستخدم الحالي:</strong> <?= $_SESSION['username'] ?? 'غير معروف' ?></li>
                                <li><strong>آخر نسخة احتياطية:</strong>
                                    <?php
                                    $backup_dir = '../../backups/';
                                    if (is_dir($backup_dir)) {
                                        $files = glob($backup_dir . '*.sql');
                                        if (!empty($files)) {
                                            $latest = max(array_map('filemtime', $files));
                                            echo date('Y-m-d H:i:s', $latest);
                                        } else {
                                            echo 'لا توجد نسخ احتياطية';
                                        }
                                    } else {
                                        echo 'مجلد النسخ غير موجود';
                                    }
                                    ?>
                                </li>
                            </ul>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- تحذيرات مهمة -->
    <div class="row">
        <div class="col-12">
            <div class="alert alert-warning">
                <h5><i class="fas fa-exclamation-triangle me-2"></i>تحذيرات مهمة</h5>
                <ul class="mb-0">
                    <li>قم بعمل نسخة احتياطية قبل تشغيل أي من أدوات الصيانة</li>
                    <li>تأكد من عدم وجود مستخدمين نشطين قبل تحسين قاعدة البيانات</li>
                    <li>عملية إعادة بناء الفهارس قد تستغرق وقتاً طويلاً</li>
                    <li>تغيير كلمة مرور المدير سيؤثر على جميع المدراء في النظام</li>
                    <li>فحص سلامة البيانات قد يكشف عن مشاكل تحتاج إصلاح يدوي</li>
                </ul>
            </div>
        </div>
    </div>
</div>

<script>
// التحقق من تطابق كلمة المرور
document.getElementById('confirm_password').addEventListener('input', function() {
    const password = document.getElementById('new_password').value;
    const confirmPassword = this.value;
    
    if (password !== confirmPassword) {
        this.setCustomValidity('كلمة المرور غير متطابقة');
    } else {
        this.setCustomValidity('');
    }
});
</script>

<?php include_once '../../includes/footer.php'; ?>
