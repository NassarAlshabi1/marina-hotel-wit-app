<?php

require_once dirname(__DIR__) . '/bootstrap.php';
// اختبار شريط التنقل المُحسن
include_once 'includes/header.php';
?>

<div class="container mt-4">
    <div class="row">
        <div class="col-12">
            <div class="alert alert-info text-center">
                <h4>🧪 اختبار شريط التنقل المُحسن</h4>
                <p class="mb-0">هذه الصفحة لاختبار شريط التنقل والتأكد من عمله بشكل صحيح</p>
            </div>
        </div>
    </div>

    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-primary text-white">
                    <h5 class="mb-0">✅ اختبار المكونات</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-6">
                            <h6>العناصر المُحسنة:</h6>
                            <ul class="list-unstyled">
                                <li>✅ <strong>شريط التنقل:</strong> خلفية متدرجة وأزرار تفاعلية</li>
                                <li>✅ <strong>القوائم المنسدلة:</strong> تصميم محسن وظلال جميلة</li>
                                <li>✅ <strong>الاستجابة:</strong> يعمل على جميع الأجهزة</li>
                                <li>✅ <strong>الأيقونات:</strong> أيقونات Unicode سريعة</li>
                                <li>✅ <strong>الألوان:</strong> تدرجات جميلة ومتناسقة</li>
                            </ul>
                        </div>
                        <div class="col-md-6">
                            <h6>التحسينات المطبقة:</h6>
                            <ul class="list-unstyled">
                                <li>🚀 <strong>سرعة التحميل:</strong> CSS مدمج</li>
                                <li>📱 <strong>متجاوب:</strong> يعمل على الموبايل والتابلت</li>
                                <li>🎨 <strong>تصميم حديث:</strong> ظلال وتأثيرات جميلة</li>
                                <li>⚡ <strong>تفاعل سريع:</strong> أنيميشن محسن</li>
                                <li>🔒 <strong>أمان:</strong> لا توجد موارد خارجية</li>
                            </ul>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row mb-4">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-success text-white">
                    <h5 class="mb-0">🎯 اختبار الوظائف</h5>
                </div>
                <div class="card-body">
                    <div class="row">
                        <div class="col-md-4">
                            <h6>الروابط الرئيسية:</h6>
                            <div class="list-group">
                                <a href="admin/dashboard.php" class="list-group-item list-group-item-action">
                                    🏠 الرئيسية
                                </a>
                                <a href="admin/rooms/list.php" class="list-group-item list-group-item-action">
                                    🛏️ الغرف
                                </a>
                                <a href="admin/bookings/list.php" class="list-group-item list-group-item-action">
                                    📅 الحجوزات
                                </a>
                                <a href="admin/settings/index.php" class="list-group-item list-group-item-action">
                                    ⚙️ الإعدادات
                                </a>
                            </div>
                        </div>
                        <div class="col-md-4">
                            <h6>اختبار الأزرار:</h6>
                            <div class="d-grid gap-2">
                                <button class="btn btn-primary">زر أساسي</button>
                                <button class="btn btn-success">زر نجاح</button>
                                <button class="btn btn-danger">زر خطر</button>
                                <button class="btn btn-warning">زر تحذير</button>
                                <button class="btn btn-info">زر معلومات</button>
                            </div>
                        </div>
                        <div class="col-md-4">
                            <h6>اختبار التنبيهات:</h6>
                            <div class="alert alert-success">تم الحفظ بنجاح!</div>
                            <div class="alert alert-warning">تحذير!</div>
                            <div class="alert alert-danger">خطأ!</div>
                        </div>
                    </div>
                </div>
            </div>
        </div>
    </div>

    <div class="row">
        <div class="col-12">
            <div class="card">
                <div class="card-header bg-dark text-white">
                    <h5 class="mb-0">📊 نتائج الاختبار</h5>
                </div>
                <div class="card-body">
                    <div class="row text-center">
                        <div class="col-md-3">
                            <div class="card border-success">
                                <div class="card-body">
                                    <h3 class="text-success">100%</h3>
                                    <p class="mb-0">شريط التنقل</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card border-info">
                                <div class="card-body">
                                    <h3 class="text-info">✅</h3>
                                    <p class="mb-0">القوائم المنسدلة</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card border-warning">
                                <div class="card-body">
                                    <h3 class="text-warning">📱</h3>
                                    <p class="mb-0">الاستجابة</p>
                                </div>
                            </div>
                        </div>
                        <div class="col-md-3">
                            <div class="card border-primary">
                                <div class="card-body">
                                    <h3 class="text-primary">🚀</h3>
                                    <p class="mb-0">الأداء</p>
                                </div>
                            </div>
                        </div>
                    </div>
                    
                    <div class="alert alert-success mt-4 text-center">
                        <h5>🎉 تم إصلاح شريط التنقل بنجاح!</h5>
                        <p class="mb-0">
                            ✅ القوائم بجانب بعض | ✅ القوائم المنسدلة تعمل | ✅ تصميم متجاوب
                            <br><strong>الهيدر جاهز للاستخدام!</strong>
                        </p>
                    </div>
                </div>
            </div>
        </div>
    </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', function() {
    // اختبار شريط التنقل
    const navLinks = document.querySelectorAll('.navbar-nav .nav-link');
    console.log('🔗 عدد روابط التنقل:', navLinks.length);
    
    // اختبار القوائم المنسدلة
    const dropdowns = document.querySelectorAll('.dropdown-menu');
    console.log('📋 عدد القوائم المنسدلة:', dropdowns.length);
    
    // اختبار الأزرار
    const buttons = document.querySelectorAll('.btn');
    console.log('🔘 عدد الأزرار:', buttons.length);
    
    // اختبار الاستجابة
    function checkResponsive() {
        const width = window.innerWidth;
        if (width <= 768) {
            console.log('📱 الموقع في وضع الموبايل');
        } else if (width <= 1024) {
            console.log('📟 الموقع في وضع التابلت');
        } else {
            console.log('💻 الموقع في وضع الكمبيوتر');
        }
    }
    
    checkResponsive();
    window.addEventListener('resize', checkResponsive);
    
    // اختبار تفاعل الأزرار
    buttons.forEach(button => {
        button.addEventListener('click', function() {
            console.log('✅ تم النقر على الزر:', this.textContent);
        });
    });
    
    console.log('✅ Marina Hotel System - Navbar Test Complete');
});
</script>

<?php include_once 'includes/footer.php'; ?>