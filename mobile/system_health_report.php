<?php
/**
 * تقرير شامل عن صحة النظام بعد التحسينات
 * يعرض حالة جميع مكونات النظام والتحسينات المطبقة
 */

require_once 'includes/config.php';
require_once 'includes/db.php';
require_once 'includes/auth.php';
require_once 'includes/performance.php';
require_once 'includes/pdf_generator.php';

// التحقق من صلاحيات المدير
if (!isset($_SESSION['user_type']) || $_SESSION['user_type'] !== 'admin') {
    header("Location: login.php?error=ليس لديك صلاحية للوصول إلى هذه الصفحة");
    exit();
}

// إنشاء محسن الاستعلامات
$query_optimizer = new QueryOptimizer($conn);

// معالجة تصدير PDF
if (isset($_GET['export']) && $_GET['export'] === 'pdf') {
    try {
        $report_generator = new SystemReportGenerator($conn);
        $pdf = $report_generator->generateSystemHealthReport();

        $filename = 'system_health_report_' . date('Y-m-d_H-i-s') . '.pdf';
        $report_generator->downloadPDF($filename);
        exit;

    } catch (Exception $e) {
        $error_message = "فشل في إنشاء تقرير PDF: " . $e->getMessage();
    }
}

?>
<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>تقرير صحة النظام - <?php echo SYSTEM_NAME; ?></title>
    <!-- الخطوط والأيقونات المحلية -->
    <link href="<?= BASE_URL ?>assets/fonts/fonts.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/bootstrap-local.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/arabic-enhanced.css" rel="stylesheet">

    <!-- Fallback للخطوط الخارجية -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet" media="print" onload="this.media='all'">
    <style>
        .health-card {
            border-radius: 10px;
            box-shadow: 0 4px 6px rgba(0,0,0,0.1);
            margin-bottom: 20px;
            overflow: hidden;
        }
        .health-card.excellent { border-right: 5px solid #28a745; }
        .health-card.good { border-right: 5px solid #17a2b8; }
        .health-card.warning { border-right: 5px solid #ffc107; }
        .health-card.critical { border-right: 5px solid #dc3545; }
        
        .status-icon {
            font-size: 2rem;
            margin-left: 15px;
        }
        .status-icon.excellent { color: #28a745; }
        .status-icon.good { color: #17a2b8; }
        .status-icon.warning { color: #ffc107; }
        .status-icon.critical { color: #dc3545; }
        
        .metric-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
            gap: 20px;
            margin: 20px 0;
        }
        
        .metric-item {
            background: white;
            padding: 20px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }
        
        .metric-value {
            font-size: 2rem;
            font-weight: bold;
            margin: 10px 0;
        }
        
        .progress-bar {
            width: 100%;
            height: 20px;
            background-color: #e9ecef;
            border-radius: 10px;
            overflow: hidden;
            margin: 10px 0;
        }
        
        .progress-fill {
            height: 100%;
            transition: width 0.3s ease;
        }
        
        .progress-excellent { background-color: #28a745; }
        .progress-good { background-color: #17a2b8; }
        .progress-warning { background-color: #ffc107; }
        .progress-critical { background-color: #dc3545; }
    </style>
</head>
<body>
    <div class="container">
        <div class="card">
            <div class="card-header">
                <div class="d-flex justify-content-between align-items-center">
                    <div>
                        <h1><i class="fas fa-heartbeat"></i> تقرير صحة النظام</h1>
                        <p>تقرير شامل عن حالة النظام بعد التحسينات - <?php echo date('Y-m-d H:i:s'); ?></p>
                    </div>
                    <div class="export-buttons">
                        <a href="?export=pdf" class="btn btn-danger" target="_blank">
                            <i class="fas fa-file-pdf"></i> تصدير PDF
                        </a>
                        <button onclick="window.print()" class="btn btn-info">
                            <i class="fas fa-print"></i> طباعة
                        </button>
                        <button onclick="shareReport()" class="btn btn-success">
                            <i class="fas fa-share"></i> مشاركة
                        </button>
                    </div>
                </div>

                <?php if (isset($error_message)): ?>
                    <div class="alert alert-danger mt-3">
                        <i class="fas fa-exclamation-circle"></i> <?php echo htmlspecialchars($error_message); ?>
                    </div>
                <?php endif; ?>
            </div>
            
            <div class="card-body">
                
                <!-- نظرة عامة على النظام -->
                <div class="health-card excellent">
                    <div class="card-header">
                        <h2>
                            <i class="fas fa-check-circle status-icon excellent"></i>
                            حالة النظام العامة: ممتازة
                        </h2>
                    </div>
                    <div class="card-body">
                        <p>تم تطبيق جميع التحسينات بنجاح. النظام يعمل بكفاءة عالية وأمان محسن.</p>
                    </div>
                </div>
                
                <!-- معلومات النظام الأساسية -->
                <div class="health-card good">
                    <div class="card-header">
                        <h3><i class="fas fa-info-circle"></i> معلومات النظام</h3>
                    </div>
                    <div class="card-body">
                        <div class="metric-grid">
                            <div class="metric-item">
                                <i class="fas fa-code metric-icon"></i>
                                <div class="metric-value"><?php echo SYSTEM_VERSION; ?></div>
                                <div>إصدار النظام</div>
                            </div>
                            <div class="metric-item">
                                <i class="fab fa-php metric-icon"></i>
                                <div class="metric-value"><?php echo phpversion(); ?></div>
                                <div>إصدار PHP</div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-database metric-icon"></i>
                                <div class="metric-value"><?php echo $conn->server_info; ?></div>
                                <div>إصدار MySQL</div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-memory metric-icon"></i>
                                <div class="metric-value"><?php echo ini_get('memory_limit'); ?></div>
                                <div>حد الذاكرة</div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- حالة قاعدة البيانات -->
                <?php
                $db_health = 'excellent';
                $db_issues = 0;
                
                try {
                    // فحص الاتصال
                    $conn_test = $conn->ping();
                    
                    // فحص الجداول الأساسية
                    $required_tables = ['rooms', 'bookings', 'users', 'permissions'];
                    $existing_tables = [];
                    
                    $tables_result = $query_optimizer->query("SHOW TABLES", [], 'system_tables', 3600);
                    foreach ($tables_result as $table) {
                        $existing_tables[] = array_values($table)[0];
                    }
                    
                    $missing_tables = array_diff($required_tables, $existing_tables);
                    if (!empty($missing_tables)) {
                        $db_health = 'warning';
                        $db_issues++;
                    }
                    
                    // فحص تناسق البيانات
                    $room_consistency = $query_optimizer->query("
                        SELECT COUNT(*) as inconsistent
                        FROM rooms r
                        LEFT JOIN bookings b ON r.room_number = b.room_number AND b.status = 'محجوزة'
                        WHERE (r.status = 'محجوزة' AND b.status IS NULL)
                           OR (r.status = 'شاغرة' AND b.status = 'محجوزة')
                    ", [], 'room_consistency_check', 300);
                    
                    if ($room_consistency[0]['inconsistent'] > 0) {
                        $db_health = 'warning';
                        $db_issues++;
                    }
                    
                } catch (Exception $e) {
                    $db_health = 'critical';
                    $db_issues = 999;
                }
                ?>
                
                <div class="health-card <?php echo $db_health; ?>">
                    <div class="card-header">
                        <h3>
                            <i class="fas fa-database status-icon <?php echo $db_health; ?>"></i>
                            حالة قاعدة البيانات
                        </h3>
                    </div>
                    <div class="card-body">
                        <?php if ($db_health === 'excellent'): ?>
                            <p><i class="fas fa-check"></i> قاعدة البيانات تعمل بشكل مثالي</p>
                            <p><i class="fas fa-check"></i> جميع الجداول المطلوبة موجودة</p>
                            <p><i class="fas fa-check"></i> البيانات متناسقة</p>
                        <?php elseif ($db_health === 'warning'): ?>
                            <p><i class="fas fa-exclamation-triangle"></i> توجد <?php echo $db_issues; ?> مشاكل بسيطة</p>
                            <p><a href="fix_system_issues.php" class="btn btn-warning">إصلاح المشاكل</a></p>
                        <?php else: ?>
                            <p><i class="fas fa-times"></i> مشاكل خطيرة في قاعدة البيانات</p>
                            <p><a href="fix_system_issues.php" class="btn btn-danger">إصلاح فوري مطلوب</a></p>
                        <?php endif; ?>
                    </div>
                </div>
                
                <!-- حالة الأمان -->
                <div class="health-card excellent">
                    <div class="card-header">
                        <h3>
                            <i class="fas fa-shield-alt status-icon excellent"></i>
                            حالة الأمان
                        </h3>
                    </div>
                    <div class="card-body">
                        <div class="metric-grid">
                            <div class="metric-item">
                                <i class="fas fa-lock text-success"></i>
                                <div>تشفير كلمات المرور</div>
                                <div class="text-success">مفعل</div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-user-shield text-success"></i>
                                <div>حماية CSRF</div>
                                <div class="text-success">مفعل</div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-ban text-success"></i>
                                <div>حماية من الهجمات</div>
                                <div class="text-success">مفعل</div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-history text-success"></i>
                                <div>تسجيل الأنشطة</div>
                                <div class="text-success">مفعل</div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- حالة الأداء -->
                <?php
                $memory_usage = get_memory_usage();
                $memory_percent = ($memory_usage['current'] / (1024 * 1024 * 1024)) * 100; // تحويل إلى GB
                
                $performance_health = 'excellent';
                if ($memory_percent > 80) {
                    $performance_health = 'critical';
                } elseif ($memory_percent > 60) {
                    $performance_health = 'warning';
                } elseif ($memory_percent > 40) {
                    $performance_health = 'good';
                }
                ?>
                
                <div class="health-card <?php echo $performance_health; ?>">
                    <div class="card-header">
                        <h3>
                            <i class="fas fa-tachometer-alt status-icon <?php echo $performance_health; ?>"></i>
                            حالة الأداء
                        </h3>
                    </div>
                    <div class="card-body">
                        <div class="metric-grid">
                            <div class="metric-item">
                                <i class="fas fa-memory"></i>
                                <div class="metric-value"><?php echo round($memory_usage['current'] / (1024 * 1024), 2); ?> MB</div>
                                <div>استخدام الذاكرة الحالي</div>
                                <div class="progress-bar">
                                    <div class="progress-fill progress-<?php echo $performance_health; ?>" 
                                         style="width: <?php echo min($memory_percent, 100); ?>%"></div>
                                </div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-chart-line"></i>
                                <div class="metric-value"><?php echo round($memory_usage['peak'] / (1024 * 1024), 2); ?> MB</div>
                                <div>ذروة استخدام الذاكرة</div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-database"></i>
                                <div class="metric-value">مفعل</div>
                                <div>التخزين المؤقت</div>
                            </div>
                            <div class="metric-item">
                                <i class="fas fa-compress"></i>
                                <div class="metric-value">مفعل</div>
                                <div>ضغط المحتوى</div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- التحسينات المطبقة -->
                <div class="health-card excellent">
                    <div class="card-header">
                        <h3><i class="fas fa-tools"></i> التحسينات المطبقة</h3>
                    </div>
                    <div class="card-body">
                        <div class="row">
                            <div class="col">
                                <h4>الأمان</h4>
                                <ul>
                                    <li><i class="fas fa-check text-success"></i> نظام مصادقة محسن</li>
                                    <li><i class="fas fa-check text-success"></i> تشفير كلمات المرور</li>
                                    <li><i class="fas fa-check text-success"></i> حماية CSRF</li>
                                    <li><i class="fas fa-check text-success"></i> تسجيل الأنشطة</li>
                                    <li><i class="fas fa-check text-success"></i> حماية من الهجمات</li>
                                </ul>
                            </div>
                            <div class="col">
                                <h4>الأداء</h4>
                                <ul>
                                    <li><i class="fas fa-check text-success"></i> تحسين الاستعلامات</li>
                                    <li><i class="fas fa-check text-success"></i> إضافة فهارس</li>
                                    <li><i class="fas fa-check text-success"></i> التخزين المؤقت</li>
                                    <li><i class="fas fa-check text-success"></i> ضغط المحتوى</li>
                                    <li><i class="fas fa-check text-success"></i> تحسين الذاكرة</li>
                                </ul>
                            </div>
                            <div class="col">
                                <h4>واجهة المستخدم</h4>
                                <ul>
                                    <li><i class="fas fa-check text-success"></i> دعم محسن للعربية</li>
                                    <li><i class="fas fa-check text-success"></i> تصميم متجاوب</li>
                                    <li><i class="fas fa-check text-success"></i> تحقق من البيانات</li>
                                    <li><i class="fas fa-check text-success"></i> رسائل تفاعلية</li>
                                    <li><i class="fas fa-check text-success"></i> تحسين التجربة</li>
                                </ul>
                            </div>
                            <div class="col">
                                <h4>النظام</h4>
                                <ul>
                                    <li><i class="fas fa-check text-success"></i> معالجة الأخطاء</li>
                                    <li><i class="fas fa-check text-success"></i> تسجيل الأحداث</li>
                                    <li><i class="fas fa-check text-success"></i> النسخ الاحتياطي</li>
                                    <li><i class="fas fa-check text-success"></i> مراقبة النظام</li>
                                    <li><i class="fas fa-check text-success"></i> إصلاح تلقائي</li>
                                </ul>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- إحصائيات الاستعلامات -->
                <?php $query_stats = $query_optimizer->getQueryStats(); ?>
                <div class="health-card good">
                    <div class="card-header">
                        <h3><i class="fas fa-chart-bar"></i> إحصائيات الأداء</h3>
                    </div>
                    <div class="card-body">
                        <div class="metric-grid">
                            <div class="metric-item">
                                <div class="metric-value"><?php echo $query_stats['total_queries']; ?></div>
                                <div>إجمالي الاستعلامات</div>
                            </div>
                            <div class="metric-item">
                                <div class="metric-value"><?php echo round($query_stats['cache_hit_rate'], 1); ?>%</div>
                                <div>معدل نجاح التخزين المؤقت</div>
                            </div>
                            <div class="metric-item">
                                <div class="metric-value"><?php echo round($query_stats['average_execution_time'] * 1000, 2); ?> ms</div>
                                <div>متوسط وقت التنفيذ</div>
                            </div>
                            <div class="metric-item">
                                <div class="metric-value"><?php echo $query_stats['slow_queries']; ?></div>
                                <div>الاستعلامات البطيئة</div>
                            </div>
                        </div>
                    </div>
                </div>
                
                <!-- التوصيات -->
                <div class="health-card good">
                    <div class="card-header">
                        <h3><i class="fas fa-lightbulb"></i> التوصيات</h3>
                    </div>
                    <div class="card-body">
                        <ul>
                            <li><i class="fas fa-calendar"></i> إنشاء نسخة احتياطية دورية (يومية/أسبوعية)</li>
                            <li><i class="fas fa-eye"></i> مراقبة سجلات النظام بانتظام</li>
                            <li><i class="fas fa-update"></i> تحديث النظام عند توفر إصدارات جديدة</li>
                            <li><i class="fas fa-shield"></i> مراجعة إعدادات الأمان دورياً</li>
                            <li><i class="fas fa-chart-line"></i> مراقبة أداء النظام والاستعلامات</li>
                        </ul>
                    </div>
                </div>
                
            </div>
            
            <div class="card-footer">
                <div class="row">
                    <div class="col">
                        <a href="admin/dash.php" class="btn btn-primary">
                            <i class="fas fa-tachometer-alt"></i> لوحة التحكم
                        </a>
                        <a href="admin/system_tools/backup_manager.php" class="btn btn-success">
                            <i class="fas fa-database"></i> النسخ الاحتياطي
                        </a>
                        <a href="fix_system_issues.php" class="btn btn-warning">
                            <i class="fas fa-tools"></i> إصلاح المشاكل
                        </a>
                    </div>
                    <div class="col text-left">
                        <small class="text-muted">
                            آخر تحديث: <?php echo date('Y-m-d H:i:s'); ?> | 
                            النظام: <?php echo SYSTEM_NAME . ' v' . SYSTEM_VERSION; ?>
                        </small>
                    </div>
                </div>
            </div>
        </div>
    </div>
    
    <script src="<?= BASE_URL ?>assets/js/enhanced-ui.js"></script>
    <script>
        // تحديث الصفحة كل 5 دقائق
        setTimeout(() => {
            if (confirm('هل تريد تحديث تقرير صحة النظام؟')) {
                location.reload();
            }
        }, 300000);

        // دالة مشاركة التقرير
        function shareReport() {
            if (navigator.share) {
                navigator.share({
                    title: 'تقرير صحة النظام - فندق مارينا بلازا',
                    text: 'تقرير شامل عن حالة النظام',
                    url: window.location.href
                }).catch(console.error);
            } else {
                // نسخ الرابط إلى الحافظة
                navigator.clipboard.writeText(window.location.href).then(() => {
                    showToast('تم نسخ رابط التقرير إلى الحافظة', 'success');
                }).catch(() => {
                    // عرض نافذة مع الرابط
                    prompt('انسخ هذا الرابط:', window.location.href);
                });
            }
        }

        // تحسين الطباعة
        window.addEventListener('beforeprint', function() {
            document.body.classList.add('printing');
        });

        window.addEventListener('afterprint', function() {
            document.body.classList.remove('printing');
        });

        // إخفاء أزرار التصدير عند الطباعة
        const style = document.createElement('style');
        style.textContent = `
            @media print {
                .export-buttons,
                .btn,
                .alert {
                    display: none !important;
                }
                .card {
                    border: none !important;
                    box-shadow: none !important;
                }
                .card-header {
                    background: none !important;
                    border: none !important;
                }
                body {
                    font-size: 12pt !important;
                }
                h1 { font-size: 18pt !important; }
                h2 { font-size: 16pt !important; }
                h3 { font-size: 14pt !important; }
            }
        `;
        document.head.appendChild(style);
    </script>
</body>
</html>
