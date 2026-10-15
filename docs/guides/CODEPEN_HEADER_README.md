# هيدر CodePen للتنقل مع القوائم الفرعية

## نظرة عامة
تم تطوير هيدر جديد بأسلوب CodePen الحديث يتضمن نظام تنقل متقدم مع قوائم فرعية تفاعلية لتحسين تجربة المستخدم في نظام إدارة الفندق.

## المميزات الرئيسية

### 🎨 التصميم
- **تصميم حديث**: مستوحى من واجهة CodePen مع ألوان احترافية
- **تأثيرات بصرية**: انتقالات سلسة وتأثيرات hover جذابة
- **تدرجات لونية**: استخدام التدرجات اللونية الحديثة
- **أيقونات FontAwesome**: أيقونات واضحة ومعبرة

### 📱 التصميم المتجاوب
- **دعم كامل للأجهزة المحمولة**: قائمة hamburger للشاشات الصغيرة
- **تكيف تلقائي**: تغيير حجم العناصر حسب حجم الشاشة
- **تجربة محسنة**: سهولة التنقل على جميع الأجهزة

### 🔧 الوظائف المتقدمة

#### القوائم الفرعية التفاعلية
- **الغرف**: قائمة الغرف، إضافة غرفة، حالة الغرف
- **الحجوزات**: قائمة الحجوزات، حجز جديد، تسجيل الخروج
- **التقارير**: تقارير الإيرادات، تقارير الإشغال، التقارير الشاملة
- **الموظفين**: سحوبات الراتب، إدارة الموظفين
- **المالية**: الصندوق، المصروفات، تقارير الصندوق
- **الإعدادات**: المستخدمين، النزلاء، النسخ الاحتياطي

#### قائمة المستخدم
- **معلومات المستخدم**: عرض اسم المستخدم الحالي
- **الملف الشخصي**: رابط للملف الشخصي
- **تسجيل الخروج**: خيار آمن لتسجيل الخروج

## الملفات المتضمنة

### 🔤 ملفات النظام
- `includes/header-codepen.php` - الهيدر الجديد
- `../../scripts/php/diagnostics/test_codepen_header.php` - صفحة اختبار ومعاينة
- `switch_header.php` - أداة تغيير الهيدر

### 🎯 المكونات

#### CSS المدمج
```css
/* Navigation Container */
.codepen-nav {
    background: #2c3e50;
    position: fixed;
    top: 0;
    box-shadow: 0 2px 10px rgba(0,0,0,0.1);
    border-bottom: 3px solid #3498db;
}

/* Main Navigation */
.main-nav {
    display: flex;
    list-style: none;
    align-items: center;
}

/* Sub Navigation */
.sub-nav {
    position: absolute;
    background: #34495e;
    opacity: 0;
    visibility: hidden;
    transform: translateY(-10px);
    transition: all 0.3s ease;
}
```

#### JavaScript المدمج
```javascript
// Mobile menu toggle
document.getElementById('mobileToggle').addEventListener('click', function() {
    const nav = document.getElementById('mainNav');
    nav.classList.toggle('active');
});

// Highlight active page
document.addEventListener('DOMContentLoaded', function() {
    const currentPath = window.location.pathname;
    const navLinks = document.querySelectorAll('.nav-link, .sub-nav-link');
    
    navLinks.forEach(link => {
        if (link.getAttribute('href') && currentPath.includes(link.getAttribute('href'))) {
            link.classList.add('active');
        }
    });
});
```

## طريقة الاستخدام

### 1. التثبيت السريع
```bash
# انتقل إلى مجلد المشروع
cd /path/to/marina-hotel

# قم بتشغيل أداة تغيير الهيدر
php switch_header.php
```

### 2. الاستخدام اليدوي
```php
// في أي صفحة تريد استخدام الهيدر الجديد
<?php include 'includes/header-codepen.php'; ?>

<!-- محتوى الصفحة -->
<div class="bg-white rounded shadow p-3">
    <h1>محتوى الصفحة</h1>
</div>

<!-- إغلاق الهيدر -->
</main>
</div>
</body>
</html>
```

### 3. التخصيص
```css
/* تخصيص الألوان */
.codepen-nav {
    background: #your-color;
    border-bottom-color: #your-accent-color;
}

.nav-link:hover {
    color: #your-hover-color;
}

/* تخصيص الخط */
body {
    font-family: 'Your-Font', sans-serif;
}
```

## البنية التقنية

### متطلبات النظام
- PHP 7.0 أو أحدث
- دعم sessions
- FontAwesome 6.4.0
- متصفح حديث مع دعم CSS3

### الأمان
- ✅ حماية من XSS
- ✅ فحص الصلاحيات
- ✅ تشفير البيانات الحساسة
- ✅ إدارة الجلسات الآمنة

### الأداء
- ⚡ CSS مُحسن ومدمج
- ⚡ JavaScript مُحسن
- ⚡ تحميل الخطوط من CDN
- ⚡ Output buffering للسرعة

## التخصيص المتقدم

### إضافة قوائم فرعية جديدة
```php
<li class="nav-item">
    <a href="#" class="nav-link">
        <i class="fas fa-your-icon"></i>
        القائمة الجديدة
        <i class="fas fa-chevron-down"></i>
    </a>
    <ul class="sub-nav">
        <li class="sub-nav-item">
            <a href="your-link.php" class="sub-nav-link">
                <i class="fas fa-sub-icon"></i>
                الخيار الأول
            </a>
        </li>
        <!-- المزيد من الخيارات -->
    </ul>
</li>
```

### تخصيص الألوان
```css
:root {
    --primary-color: #your-primary;
    --secondary-color: #your-secondary;
    --accent-color: #your-accent;
    --text-color: #your-text;
    --hover-color: #your-hover;
}
```

### إضافة تأثيرات مخصصة
```css
.nav-link {
    position: relative;
    overflow: hidden;
}

.nav-link::before {
    content: '';
    position: absolute;
    bottom: 0;
    left: 0;
    width: 0;
    height: 2px;
    background: var(--accent-color);
    transition: width 0.3s ease;
}

.nav-link:hover::before {
    width: 100%;
}
```

## الاختبار والتطوير

### اختبار الهيدر الجديد
1. افتح `../../scripts/php/diagnostics/test_codepen_header.php` في المتصفح
2. تأكد من ظهور جميع القوائم
3. اختبر التنقل على الأجهزة المحمولة
4. تأكد من عمل القوائم الفرعية

### تطبيق الهيدر
1. افتح `switch_header.php`
2. اختر "تطبيق هيدر CodePen"
3. تأكد من عمل النظام بشكل صحيح
4. في حالة وجود مشاكل، استخدم "استرجاع الهيدر الأصلي"

## الدعم والمساعدة

### المشاكل الشائعة
1. **القوائم الفرعية لا تظهر**: تأكد من تضمين CSS بشكل صحيح
2. **الأيقونات لا تظهر**: تأكد من تحميل FontAwesome
3. **لا يعمل على الأجهزة المحمولة**: تأكد من JavaScript

### نصائح التحسين
- استخدم الضغط للـ CSS و JavaScript
- قم بتحسين الصور والأيقونات
- استخدم التخزين المؤقت للمتصفح
- اختبر على متصفحات مختلفة

## الخلاصة
هيدر CodePen الجديد يوفر تجربة مستخدم محسنة مع:
- تصميم حديث وجذاب
- تنقل سهل ومنظم
- قوائم فرعية تفاعلية
- دعم كامل للأجهزة المحمولة
- أداء محسن وسريع

للحصول على أفضل تجربة، يُنصح بتطبيق الهيدر الجديد واختباره على بيئة التطوير أولاً قبل النشر في الإنتاج.