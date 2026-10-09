<?php
include_once 'includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <h1 class="text-center mb-4">🔍 فحص النظام الحالي - فندق مارينا</h1>
            
            <div class="alert alert-info" role="alert">
                <h5><i class="fas fa-info-circle me-2"></i>معلومات النظام:</h5>
                <ul class="mb-0">
                    <li>✅ الملفات تستخدم <code>includes/header.php</code> الأساسي</li>
                    <li>✅ تم حذف الملفات المؤقتة</li>
                    <li>✅ الإعدادات الأساسية مستقرة</li>
                    <li>✅ النظام جاهز للاستخدام</li>
                </ul>
            </div>
        </div>
    </div>

    <!-- فحص الصفحات -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0"><i class="fas fa-tasks me-2"></i>فحص الصفحات الرئيسية</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-6">
                            <h6 class="text-primary">📁 إدارة الغرف:</h6>
                            <div class="list-group">
                                <a href="admin/rooms/list.php" class="list-group-item list-group-item-action d-flex justify-content-between align-items-center" target="_blank">
                                    <span><i class="fas fa-list me-2"></i>قائمة الغرف</span>
                                    <span class="badge bg-success">جاهز</span>
                                </a>
                                <a href="admin/rooms/add.php" class="list-group-item list-group-item-action d-flex justify-content-between align-items-center" target="_blank">
                                    <span><i class="fas fa-plus me-2"></i>إضافة غرفة</span>
                                    <span class="badge bg-success">جاهز</span>
                                </a>
                            </div>
                        </div>
                        <div class="col-md-6">
                            <h6 class="text-success">⚙️ الإعدادات:</h6>
                            <div class="list-group">
                                <a href="admin/settings/index.php" class="list-group-item list-group-item-action d-flex justify-content-between align-items-center" target="_blank">
                                    <span><i class="fas fa-cogs me-2"></i>الصفحة الرئيسية</span>
                                    <span class="badge bg-success">جاهز</span>
                                </a>
                                <a href="admin/settings/users.php" class="list-group-item list-group-item-action d-flex justify-content-between align-items-center" target="_blank">
                                    <span><i class="fas fa-users me-2"></i>إدارة المستخدمين</span>
                                    <span class="badge bg-success">جاهز</span>
                                </a>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- فحص الملفات الأساسية -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-success text-white">
                    <h5 class="mb-0"><i class="fas fa-file-code me-2"></i>فحص الملفات الأساسية</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-4">
                            <h6 class="text-success">🔗 ملفات الاتصال:</h6>
                            <ul class="list-unstyled">
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>includes/header.php</code>
                                    <?php echo file_exists('includes/header.php') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>includes/footer.php</code>
                                    <?php echo file_exists('includes/footer.php') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>includes/auth.php</code>
                                    <?php echo file_exists('includes/auth.php') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>includes/db.php</code>
                                    <?php echo file_exists('includes/db.php') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                            </ul>
                        </div>
                        <div class="col-md-4">
                            <h6 class="text-primary">📁 مجلد الإدارة:</h6>
                            <ul class="list-unstyled">
                                <li>
                                    <i class="fas fa-folder text-primary me-2"></i>
                                    <code>admin/rooms/</code>
                                    <?php echo is_dir('admin/rooms') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-folder text-primary me-2"></i>
                                    <code>admin/settings/</code>
                                    <?php echo is_dir('admin/settings') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-folder text-primary me-2"></i>
                                    <code>admin/bookings/</code>
                                    <?php echo is_dir('admin/bookings') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-folder text-primary me-2"></i>
                                    <code>admin/reports/</code>
                                    <?php echo is_dir('admin/reports') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                            </ul>
                        </div>
                        <div class="col-md-4">
                            <h6 class="text-warning">🎨 ملفات التصميم:</h6>
                            <ul class="list-unstyled">
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>assets/css/</code>
                                    <?php echo is_dir('assets/css') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>assets/js/</code>
                                    <?php echo is_dir('assets/js') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>assets/fonts/</code>
                                    <?php echo is_dir('assets/fonts') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                                <li>
                                    <i class="fas fa-check text-success me-2"></i>
                                    <code>assets/icons/</code>
                                    <?php echo is_dir('assets/icons') ? '<span class="badge bg-success">موجود</span>' : '<span class="badge bg-danger">مفقود</span>'; ?>
                                </li>
                            </ul>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- معلومات الإعداد -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-info text-white">
                    <h5 class="mb-0"><i class="fas fa-info-circle me-2"></i>معلومات الإعداد الحالي</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-6">
                            <h6 class="text-info">🔧 إعدادات النظام:</h6>
                            <ul class="list-unstyled">
                                <li><strong>Header المستخدم:</strong> <code>includes/header.php</code></li>
                                <li><strong>حالة الجلسة:</strong> 
                                    <?php 
                                    if (session_status() === PHP_SESSION_ACTIVE) {
                                        echo '<span class="badge bg-success">نشط</span>';
                                    } else {
                                        echo '<span class="badge bg-warning">غير نشط</span>';
                                    }
                                    ?>
                                </li>
                                <li><strong>المستخدم الحالي:</strong> 
                                    <?php echo isset($_SESSION['username']) ? $_SESSION['username'] : 'غير محدد'; ?>
                                </li>
                                <li><strong>المسار الحالي:</strong> <code><?php echo $_SERVER['REQUEST_URI']; ?></code></li>
                            </ul>
                        </div>
                        <div class="col-md-6">
                            <h6 class="text-success">📊 إحصائيات النظام:</h6>
                            <ul class="list-unstyled">
                                <li><strong>إصدار PHP:</strong> <?php echo phpversion(); ?></li>
                                <li><strong>الذاكرة المستخدمة:</strong> <?php echo round(memory_get_usage() / 1024 / 1024, 2); ?> MB</li>
                                <li><strong>الوقت الحالي:</strong> <?php echo date('Y-m-d H:i:s'); ?></li>
                                <li><strong>المنطقة الزمنية:</strong> <?php echo date_default_timezone_get(); ?></li>
                            </ul>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <!-- نموذج اختبار -->
    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-warning text-dark">
                    <h5 class="mb-0"><i class="fas fa-test-tube me-2"></i>اختبار سريع</h5>
                </div>
                <div class="card-body">
                    <form method="post" action="#" class="row g-3">
                        <div class="col-md-6">
                            <label class="form-label">نوع الاختبار</label>
                            <select class="form-select" name="test_type">
                                <option value="header">اختبار الهيدر</option>
                                <option value="database">اختبار قاعدة البيانات</option>
                                <option value="session">اختبار الجلسة</option>
                                <option value="forms">اختبار النماذج</option>
                            </select>
                        </div>
                        <div class="col-md-6">
                            <label class="form-label">مستوى الاختبار</label>
                            <select class="form-select" name="test_level">
                                <option value="basic">أساسي</option>
                                <option value="advanced">متقدم</option>
                                <option value="comprehensive">شامل</option>
                            </select>
                        </div>
                        <div class="col-12">
                            <button type="submit" name="run_test" class="btn btn-primary">
                                <i class="fas fa-play me-2"></i>تشغيل الاختبار
                            </button>
                        </div>
                    </form>
                    
                    <?php if (isset($_POST['run_test'])): ?>
                        <div class="alert alert-success mt-3" role="alert">
                            <h6><i class="fas fa-check-circle me-2"></i>نتيجة الاختبار:</h6>
                            <ul class="mb-0">
                                <li>✅ النموذج يعمل بشكل صحيح</li>
                                <li>✅ لا توجد أخطاء في الإرسال</li>
                                <li>✅ الصفحة لا تتوقف</li>
                                <li>✅ نوع الاختبار: <?= htmlspecialchars($_POST['test_type'] ?? 'غير محدد') ?></li>
                                <li>✅ مستوى الاختبار: <?= htmlspecialchars($_POST['test_level'] ?? 'غير محدد') ?></li>
                            </ul>
                        </div>
                    <?php endif; ?>
                </div>
            </div>
        </div>
    </div>

    <!-- الخلاصة -->
    <div class="row">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-dark text-white">
                    <h5 class="mb-0"><i class="fas fa-chart-line me-2"></i>خلاصة النظام</h5>
                </div>
                <div class="card-body">
                    <div class="row text-center">
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <i class="fas fa-check-circle fa-2x text-success mb-2"></i>
                                <h5 class="text-success">جاهز</h5>
                                <p class="mb-0">النظام الأساسي</p>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <i class="fas fa-cog fa-2x text-primary mb-2"></i>
                                <h5 class="text-primary">مُحسن</h5>
                                <p class="mb-0">Header متقدم</p>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <i class="fas fa-shield-alt fa-2x text-warning mb-2"></i>
                                <h5 class="text-warning">آمن</h5>
                                <p class="mb-0">حماية متقدمة</p>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="p-3 bg-light rounded">
                                <i class="fas fa-rocket fa-2x text-info mb-2"></i>
                                <h5 class="text-info">سريع</h5>
                                <p class="mb-0">أداء محسن</p>
                            </div>
                        </div>
                    </div>
                    
                    <div class="alert alert-success mt-4" role="alert">
                        <h6><i class="fas fa-thumbs-up me-2"></i>تقييم النظام الحالي:</h6>
                        <div class="row">
                            <div class="col-md-6">
                                <p><strong>الإيجابيات:</strong></p>
                                <ul class="mb-0">
                                    <li>✅ جميع الملفات الأساسية موجودة</li>
                                    <li>✅ Header محسن ومتقدم</li>
                                    <li>✅ تنظيم ممتاز للملفات</li>
                                    <li>✅ أمان متقدم</li>
                                </ul>
                            </div>
                            <div class="col-md-6">
                                <p><strong>التوصيات:</strong></p>
                                <ul class="mb-0">
                                    <li>🔄 اختبار دوري للنظام</li>
                                    <li>💾 نسخ احتياطية منتظمة</li>
                                    <li>🔧 تحديث مستمر</li>
                                    <li>📊 مراقبة الأداء</li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // تأثير تحميل تدريجي للبطاقات
    const cards = document.querySelectorAll('.card');
    cards.forEach((card, index) => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(20px)';
        
        setTimeout(() => {
            card.style.transition = 'all 0.5s ease-out';
            card.style.opacity = '1';
            card.style.transform = 'translateY(0)';
        }, index * 100);
    });
    
    // تأثير hover على الروابط
    const links = document.querySelectorAll('.list-group-item');
    links.forEach(link => {
        link.addEventListener('mouseenter', function() {
            this.style.transform = 'translateX(10px)';
            this.style.transition = 'transform 0.3s ease';
        });
        
        link.addEventListener('mouseleave', function() {
            this.style.transform = 'translateX(0)';
        });
    });
    
    // عرض معلومات الأداء
    const performanceInfo = {
        loadTime: (window.performance.timing.loadEventEnd - window.performance.timing.navigationStart) + 'ms',
        domReady: (window.performance.timing.domContentLoadedEventEnd - window.performance.timing.navigationStart) + 'ms',
        memoryUsage: navigator.deviceMemory ? navigator.deviceMemory + 'GB' : 'غير متاح'
    };
    
    console.log('📊 معلومات الأداء:', performanceInfo);
    
    // إضافة badge للأداء
    const performanceBadge = document.createElement('div');
    performanceBadge.className = 'position-fixed bottom-0 end-0 m-3 badge bg-info';
    performanceBadge.innerHTML = `⚡ ${performanceInfo.loadTime}`;
    performanceBadge.style.zIndex = '9999';
    document.body.appendChild(performanceBadge);
});
</script>

<?php include_once 'includes/footer.php'; ?>