<?php

require_once dirname(__DIR__) . '/bootstrap.php';
/**
 * اختبار العمل بدون انترنت
 * يتحقق من توفر جميع الموارد المحلية
 */

// تعطيل تحميل الموارد الخارجية لمحاكاة عدم وجود انترنت
$offline_mode = true;

require_once 'includes/config.php';
require_once 'includes/db.php';

$assets_path = rtrim(MARINA_WEB_ROOT, '/') . '/assets/';

// التحقق من الموارد المحلية
$local_resources = [
    'fonts/fonts.css',
    'css/bootstrap-complete.css',
    'css/fontawesome.min.css', 
    'css/arabic-enhanced.css',
    'js/bootstrap-local.js',
    'js/enhanced-ui.js'
];

$missing_resources = [];
$existing_resources = [];

foreach ($local_resources as $resource) {
    $file_path = MARINA_REPO_ROOT . '/assets/' . $resource;
    if (file_exists($file_path)) {
        $existing_resources[] = $resource;
    } else {
        $missing_resources[] = $resource;
    }
}
?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>اختبار العمل بدون انترنت - نظام فندق مارينا</title>
    
    <!-- تحميل الموارد المحلية فقط -->
    <link href="<?= BASE_URL ?>assets/fonts/fonts.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/bootstrap-complete.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/fontawesome.min.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/arabic-enhanced.css" rel="stylesheet">
    
    <style>
        body {
            font-family: 'Tajawal', sans-serif;
            background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
            direction: rtl;
            text-align: right;
            padding: 20px;
        }
        
        .test-container {
            max-width: 1200px;
            margin: 0 auto;
        }
        
        .resource-item {
            margin-bottom: 10px;
            padding: 10px;
            border-radius: 5px;
            display: flex;
            align-items: center;
            justify-content: space-between;
        }
        
        .resource-item.success {
            background-color: #d1edcc;
            border: 1px solid #badbcc;
        }
        
        .resource-item.error {
            background-color: #f8d7da;
            border: 1px solid #f5c2c7;
        }
        
        .status-icon {
            font-size: 1.2em;
            margin-left: 10px;
        }
        
        .demo-section {
            margin-top: 30px;
            padding: 20px;
            background: white;
            border-radius: 10px;
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }
    </style>
</head>
<body>
    <div class="test-container">
        <div class="card">
            <div class="card-header bg-primary text-white">
                <h1 class="card-title mb-0">
                    <i class="fas fa-wifi"></i> اختبار العمل بدون انترنت
                </h1>
            </div>
            <div class="card-body">
                
                <!-- حالة الموارد -->
                <div class="row">
                    <div class="col-md-6">
                        <div class="card">
                            <div class="card-header bg-success text-white">
                                <h5 class="mb-0">
                                    <i class="fas fa-check-circle"></i> الموارد المتوفرة محلياً
                                </h5>
                            </div>
                            <div class="card-body">
                                <?php foreach ($existing_resources as $resource): ?>
                                <div class="resource-item success">
                                    <span><?php echo htmlspecialchars($resource); ?></span>
                                    <span class="status-icon text-success">✓</span>
                                </div>
                                <?php endforeach; ?>
                                
                                <?php if (empty($existing_resources)): ?>
                                <p class="text-muted">لا توجد موارد محلية متوفرة</p>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                    
                    <div class="col-md-6">
                        <div class="card">
                            <div class="card-header bg-danger text-white">
                                <h5 class="mb-0">
                                    <i class="fas fa-times-circle"></i> الموارد المفقودة
                                </h5>
                            </div>
                            <div class="card-body">
                                <?php foreach ($missing_resources as $resource): ?>
                                <div class="resource-item error">
                                    <span><?php echo htmlspecialchars($resource); ?></span>
                                    <span class="status-icon text-danger">✗</span>
                                </div>
                                <?php endforeach; ?>
                                
                                <?php if (empty($missing_resources)): ?>
                                <p class="text-success">جميع الموارد متوفرة محلياً! 🎉</p>
                                <?php endif; ?>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- إحصائيات -->
                <div class="row mt-4">
                    <div class="col-md-4">
                        <div class="card bg-info text-white">
                            <div class="card-body text-center">
                                <h3><?php echo count($existing_resources); ?></h3>
                                <p>موارد متوفرة</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="card bg-warning text-dark">
                            <div class="card-body text-center">
                                <h3><?php echo count($missing_resources); ?></h3>
                                <p>موارد مفقودة</p>
                            </div>
                        </div>
                    </div>
                    <div class="col-md-4">
                        <div class="card bg-primary text-white">
                            <div class="card-body text-center">
                                <h3><?php echo round((count($existing_resources) / count($local_resources)) * 100); ?>%</h3>
                                <p>نسبة الاكتمال</p>
                            </div>
                        </div>
                    </div>
                </div>

                <!-- اختبار المكونات -->
                <div class="demo-section">
                    <h3>اختبار مكونات Bootstrap</h3>
                    
                    <!-- اختبار الأزرار -->
                    <div class="mb-3">
                        <h5>الأزرار</h5>
                        <button type="button" class="btn btn-primary me-2">أساسي</button>
                        <button type="button" class="btn btn-success me-2">نجاح</button>
                        <button type="button" class="btn btn-warning me-2">تحذير</button>
                        <button type="button" class="btn btn-danger me-2">خطر</button>
                    </div>

                    <!-- اختبار التنبيهات -->
                    <div class="mb-3">
                        <h5>التنبيهات</h5>
                        <div class="alert alert-success alert-dismissible fade show">
                            <i class="fas fa-check-circle me-2"></i>
                            هذا تنبيه نجاح يعمل بدون انترنت!
                            <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                        </div>
                    </div>

                    <!-- اختبار النموذج -->
                    <div class="mb-3">
                        <h5>النماذج</h5>
                        <form class="row g-3">
                            <div class="col-md-6">
                                <label class="form-label">اسم المستخدم</label>
                                <input type="text" class="form-control" placeholder="أدخل اسم المستخدم">
                            </div>
                            <div class="col-md-6">
                                <label class="form-label">البريد الإلكتروني</label>
                                <input type="email" class="form-control" placeholder="أدخل البريد الإلكتروني">
                            </div>
                            <div class="col-12">
                                <button type="submit" class="btn btn-primary">إرسال</button>
                            </div>
                        </form>
                    </div>

                    <!-- اختبار القائمة المنسدلة -->
                    <div class="mb-3">
                        <h5>القائمة المنسدلة</h5>
                        <div class="dropdown">
                            <button class="btn btn-secondary dropdown-toggle" type="button" data-bs-toggle="dropdown">
                                <i class="fas fa-cog me-2"></i>الخيارات
                            </button>
                            <ul class="dropdown-menu">
                                <li><a class="dropdown-item" href="#"><i class="fas fa-user me-2"></i>الملف الشخصي</a></li>
                                <li><a class="dropdown-item" href="#"><i class="fas fa-cog me-2"></i>الإعدادات</a></li>
                                <li><hr class="dropdown-divider"></li>
                                <li><a class="dropdown-item" href="#"><i class="fas fa-sign-out-alt me-2"></i>تسجيل الخروج</a></li>
                            </ul>
                        </div>
                    </div>

                    <!-- اختبار البطاقات -->
                    <div class="mb-3">
                        <h5>البطاقات</h5>
                        <div class="row">
                            <div class="col-md-4">
                                <div class="card">
                                    <div class="card-header">
                                        <i class="fas fa-chart-bar me-2"></i>إحصائيات
                                    </div>
                                    <div class="card-body">
                                        <h5 class="card-title">عدد الحجوزات</h5>
                                        <p class="card-text">156 حجز هذا الشهر</p>
                                        <a href="#" class="btn btn-primary">عرض التفاصيل</a>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-4">
                                <div class="card">
                                    <div class="card-header">
                                        <i class="fas fa-money-bill-wave me-2"></i>الإيرادات
                                    </div>
                                    <div class="card-body">
                                        <h5 class="card-title">الإيرادات الشهرية</h5>
                                        <p class="card-text">50,000 ريال يمني</p>
                                        <a href="#" class="btn btn-success">عرض التقرير</a>
                                    </div>
                                </div>
                            </div>
                            <div class="col-md-4">
                                <div class="card">
                                    <div class="card-header">
                                        <i class="fas fa-users me-2"></i>النزلاء
                                    </div>
                                    <div class="card-body">
                                        <h5 class="card-title">النزلاء الحاليين</h5>
                                        <p class="card-text">23 نزيل في الفندق</p>
                                        <a href="#" class="btn btn-info">إدارة النزلاء</a>
                                    </div>
                                </div>
                            </div>
                        </div>
                    </div>

                    <!-- اختبار الجدول -->
                    <div class="mb-3">
                        <h5>الجداول</h5>
                        <div class="table-responsive">
                            <table class="table table-striped">
                                <thead class="table-dark">
                                    <tr>
                                        <th><i class="fas fa-hashtag me-2"></i>الرقم</th>
                                        <th><i class="fas fa-user me-2"></i>الاسم</th>
                                        <th><i class="fas fa-bed me-2"></i>رقم الغرفة</th>
                                        <th><i class="fas fa-calendar me-2"></i>تاريخ الوصول</th>
                                        <th><i class="fas fa-cogs me-2"></i>الإجراءات</th>
                                    </tr>
                                </thead>
                                <tbody>
                                    <tr>
                                        <td>1</td>
                                        <td>أحمد محمد</td>
                                        <td>101</td>
                                        <td>2024-01-15</td>
                                        <td>
                                            <button class="btn btn-sm btn-primary"><i class="fas fa-eye"></i></button>
                                            <button class="btn btn-sm btn-warning"><i class="fas fa-edit"></i></button>
                                            <button class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
                                        </td>
                                    </tr>
                                    <tr>
                                        <td>2</td>
                                        <td>فاطمة عبدالله</td>
                                        <td>102</td>
                                        <td>2024-01-16</td>
                                        <td>
                                            <button class="btn btn-sm btn-primary"><i class="fas fa-eye"></i></button>
                                            <button class="btn btn-sm btn-warning"><i class="fas fa-edit"></i></button>
                                            <button class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button>
                                        </td>
                                    </tr>
                                </tbody>
                            </table>
                        </div>
                    </div>
                </div>

                <!-- أزرار الاختبار -->
                <div class="mt-4">
                    <button type="button" class="btn btn-success" onclick="testFunctionality()">
                        <i class="fas fa-play me-2"></i>اختبار الوظائف
                    </button>
                    <button type="button" class="btn btn-info" onclick="showSystemInfo()">
                        <i class="fas fa-info-circle me-2"></i>معلومات النظام
                    </button>
                    <a href="admin/dashboard.php" class="btn btn-primary">
                        <i class="fas fa-tachometer-alt me-2"></i>العودة للوحة التحكم
                    </a>
                </div>
            </div>
        </div>
    </div>

    <!-- تحميل JavaScript المحلي -->
    <script src="<?= BASE_URL ?>assets/js/bootstrap-local.js"></script>
    <script src="<?= BASE_URL ?>assets/js/enhanced-ui.js"></script>

    <script>
        // اختبار الوظائف
        function testFunctionality() {
            if (typeof window.Bootstrap !== 'undefined') {
                window.HotelSystem.showToast('جميع المكونات تعمل بشكل صحيح!', 'success');
            } else {
                window.HotelSystem.showToast('فشل في تحميل Bootstrap المحلي', 'error');
            }
        }

        // عرض معلومات النظام
        function showSystemInfo() {
            const info = {
                'اسم النظام': '<?php echo SYSTEM_NAME; ?>',
                'إصدار النظام': '<?php echo SYSTEM_VERSION; ?>',
                'وضع التطوير': '<?php echo DEBUG_MODE ? "مفعل" : "معطل"; ?>',
                'الموارد المتوفرة': '<?php echo count($existing_resources); ?>/<?php echo count($local_resources); ?>',
                'نسبة الاكتمال': '<?php echo round((count($existing_resources) / count($local_resources)) * 100); ?>%'
            };

            let message = '<div class="text-start" dir="ltr">';
            for (let key in info) {
                message += `<strong>${key}:</strong> ${info[key]}<br>`;
            }
            message += '</div>';

            // إنشاء مودال مخصص
            const modal = document.createElement('div');
            modal.className = 'modal fade';
            modal.innerHTML = `
                <div class="modal-dialog">
                    <div class="modal-content">
                        <div class="modal-header">
                            <h5 class="modal-title">معلومات النظام</h5>
                            <button type="button" class="btn-close" data-bs-dismiss="modal"></button>
                        </div>
                        <div class="modal-body">
                            ${message}
                        </div>
                        <div class="modal-footer">
                            <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">إغلاق</button>
                        </div>
                    </div>
                </div>
            `;
            document.body.appendChild(modal);
            
            const modalInstance = new window.Bootstrap.Modal(modal);
            modalInstance.show();
            
            // إزالة المودال بعد إغلاقه
            modal.addEventListener('hidden.bs.modal', function () {
                document.body.removeChild(modal);
            });
        }

        // اختبار تلقائي عند تحميل الصفحة
        document.addEventListener('DOMContentLoaded', function() {
            setTimeout(function() {
                if (typeof window.Bootstrap !== 'undefined') {
                    console.log('✅ Bootstrap المحلي تم تحميله بنجاح');
                    window.HotelSystem.showToast('النظام يعمل بدون انترنت بنجاح!', 'success');
                } else {
                    console.error('❌ فشل في تحميل Bootstrap المحلي');
                    window.HotelSystem.showToast('تحذير: بعض المكونات قد لا تعمل بشكل صحيح', 'warning');
                }
            }, 1000);
        });
    </script>
</body>
</html>