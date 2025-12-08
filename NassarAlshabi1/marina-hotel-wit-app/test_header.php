<?php
session_start();

// تسجيل دخول مؤقت للاختبار
if (!isset($_SESSION['username'])) {
    $_SESSION['username'] = 'مدير النظام';
    $_SESSION['user_id'] = 1;
    $_SESSION['role'] = 'admin';
}

// تضمين الهيدر الجديد
include 'includes/header.php';
?>

<div class="card">
    <div class="card-header">
        <h2 class="text-center">
            <i class="fas fa-star text-warning"></i>
            اختبار الهيدر الجديد - CodePen Style
        </h2>
    </div>
    <div style="padding: 20px;">
        <p class="text-center">
            تم تطوير نظام التنقل الجديد بأسلوب CodePen الحديث مع القوائم الفرعية التفاعلية
        </p>
        
        <div class="row">
            <div class="col-md-4">
                <div class="card">
                    <div class="card-header">
                        <h4 style="color: #3498db;">
                            <i class="fas fa-bed"></i>
                            إدارة الغرف
                        </h4>
                    </div>
                    <div style="padding: 15px;">
                        <p>قم بإدارة جميع غرف الفندق بسهولة</p>
                        <ul style="list-style: none; padding: 0;">
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> قائمة الغرف</li>
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> إضافة غرفة جديدة</li>
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> متابعة حالة الغرف</li>
                        </ul>
                    </div>
                </div>
            </div>
            
            <div class="col-md-4">
                <div class="card">
                    <div class="card-header">
                        <h4 style="color: #27ae60;">
                            <i class="fas fa-calendar-alt"></i>
                            إدارة الحجوزات
                        </h4>
                    </div>
                    <div style="padding: 15px;">
                        <p>تتبع وإدارة جميع الحجوزات</p>
                        <ul style="list-style: none; padding: 0;">
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> قائمة الحجوزات</li>
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> حجز جديد</li>
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> تسجيل الخروج</li>
                        </ul>
                    </div>
                </div>
            </div>
            
            <div class="col-md-4">
                <div class="card">
                    <div class="card-header">
                        <h4 style="color: #17a2b8;">
                            <i class="fas fa-chart-line"></i>
                            التقارير والإحصائيات
                        </h4>
                    </div>
                    <div style="padding: 15px;">
                        <p>تقارير مالية وإحصائيات مفصلة</p>
                        <ul style="list-style: none; padding: 0;">
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> تقارير الإيرادات</li>
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> تقارير الإشغال</li>
                            <li><i class="fas fa-check" style="color: #27ae60;"></i> التقارير الشاملة</li>
                        </ul>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="row">
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h4 style="color: #f39c12;">
                            <i class="fas fa-users"></i>
                            إدارة الموظفين
                        </h4>
                    </div>
                    <div style="padding: 15px;">
                        <p>تنظيم شؤون الموظفين والرواتب</p>
                        <div class="text-center">
                            <a href="#" class="btn btn-primary">
                                <i class="fas fa-money-check-alt"></i>
                                سحوبات الراتب
                            </a>
                            <a href="#" class="btn btn-info">
                                <i class="fas fa-user-tie"></i>
                                إدارة الموظفين
                            </a>
                        </div>
                    </div>
                </div>
            </div>
            
            <div class="col-md-6">
                <div class="card">
                    <div class="card-header">
                        <h4 style="color: #e74c3c;">
                            <i class="fas fa-wallet"></i>
                            الإدارة المالية
                        </h4>
                    </div>
                    <div style="padding: 15px;">
                        <p>إدارة الشؤون المالية والمصروفات</p>
                        <div class="text-center">
                            <a href="#" class="btn btn-success">
                                <i class="fas fa-cash-register"></i>
                                الصندوق
                            </a>
                            <a href="#" class="btn btn-warning">
                                <i class="fas fa-receipt"></i>
                                المصروفات
                            </a>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="card">
            <div class="card-header">
                <h4 class="text-center">
                    <i class="fas fa-cogs" style="color: #6c757d;"></i>
                    الإعدادات والأدوات
                </h4>
            </div>
            <div style="padding: 15px;">
                <div class="row">
                    <div class="col-md-4 text-center">
                        <div style="padding: 20px; background: #f8f9fa; border-radius: 8px; margin-bottom: 15px;">
                            <i class="fas fa-user fa-3x" style="color: #3498db; margin-bottom: 10px;"></i>
                            <h6>إدارة المستخدمين</h6>
                            <p style="color: #6c757d; font-size: 14px;">تحكم في صلاحيات المستخدمين</p>
                        </div>
                    </div>
                    <div class="col-md-4 text-center">
                        <div style="padding: 20px; background: #f8f9fa; border-radius: 8px; margin-bottom: 15px;">
                            <i class="fas fa-user-friends fa-3x" style="color: #27ae60; margin-bottom: 10px;"></i>
                            <h6>إدارة النزلاء</h6>
                            <p style="color: #6c757d; font-size: 14px;">متابعة بيانات النزلاء</p>
                        </div>
                    </div>
                    <div class="col-md-4 text-center">
                        <div style="padding: 20px; background: #f8f9fa; border-radius: 8px; margin-bottom: 15px;">
                            <i class="fas fa-database fa-3x" style="color: #f39c12; margin-bottom: 10px;"></i>
                            <h6>النسخ الاحتياطي</h6>
                            <p style="color: #6c757d; font-size: 14px;">حماية البيانات</p>
                        </div>
                    </div>
                </div>
            </div>
        </div>
        
        <div class="text-center mt-3">
            <div class="alert alert-info">
                <i class="fas fa-info-circle"></i>
                <strong>نصائح الاستخدام:</strong>
                <ul style="list-style: none; margin: 10px 0; padding: 0;">
                    <li>• مرر الماوس فوق القوائم لرؤية الخيارات الفرعية</li>
                    <li>• استخدم زر القائمة في الأجهزة المحمولة</li>
                    <li>• جميع الأزرار والروابط تفاعلية</li>
                </ul>
            </div>
        </div>
    </div>
</div>

        </main>
    </div>
</body>
</html>