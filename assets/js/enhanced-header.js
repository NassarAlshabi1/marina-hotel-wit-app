/**
 * Enhanced Header JavaScript
 * تحسينات JavaScript لملف Header المحسن
 */

// إعدادات التطبيق
const AppConfig = {
    navbar: {
        scrollThreshold: 50,
        hideOnScroll: false,
        animationDuration: 300
    },
    dropdown: {
        hoverDelay: 150,
        animationDuration: 300
    },
    alerts: {
        autoHideDelay: 7000,
        animationDuration: 500
    },
    performance: {
        enableLazyLoading: true,
        enablePreloading: true,
        enableIntersectionObserver: true
    }
};

// فئة إدارة التطبيق الرئيسية
class EnhancedHeaderManager {
    constructor() {
        this.init();
    }

    init() {
        // انتظار تحميل DOM
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', () => this.initComponents());
        } else {
            this.initComponents();
        }
    }

    initComponents() {
        // تسجيل بداية التحميل
        console.log('🚀 Enhanced Header Manager initialized');

        // تهيئة المكونات
        this.initPerformanceOptimizations();
        this.initNavbar();
        this.initDropdowns();
        this.initForms();
        this.initTables();
        this.initButtons();
        this.initAlerts();
        this.initAnimations();
        this.initAccessibility();
        this.initPWA();
        this.initConnectionStatus();

        // تسجيل انتهاء التحميل
        console.log('✅ All components initialized successfully');
    }

    // تحسين الأداء
    initPerformanceOptimizations() {
        if (!AppConfig.performance.enableIntersectionObserver) return;

        // Intersection Observer للعناصر المتحركة
        const observerOptions = {
            threshold: 0.1,
            rootMargin: '0px 0px -50px 0px'
        };

        const observer = new IntersectionObserver((entries) => {
            entries.forEach(entry => {
                if (entry.isIntersecting) {
                    this.animateElement(entry.target);
                    observer.unobserve(entry.target);
                }
            });
        }, observerOptions);

        // مراقبة العناصر المتحركة
        document.querySelectorAll('.animated-element').forEach(el => {
            el.style.opacity = '0';
            el.style.transform = 'translateY(20px)';
            el.style.transition = 'all 0.6s cubic-bezier(0.4, 0, 0.2, 1)';
            observer.observe(el);
        });

        // تحسين الصور الكسولة
        if (AppConfig.performance.enableLazyLoading) {
            this.initLazyLoading();
        }

        // تحسين التحميل المسبق
        if (AppConfig.performance.enablePreloading) {
            this.initPreloading();
        }
    }

    animateElement(element) {
        element.style.opacity = '1';
        element.style.transform = 'translateY(0)';
    }

    initLazyLoading() {
        if ('IntersectionObserver' in window) {
            const imageObserver = new IntersectionObserver((entries) => {
                entries.forEach(entry => {
                    if (entry.isIntersecting) {
                        const img = entry.target;
                        img.src = img.dataset.src;
                        img.classList.remove('lazy');
                        img.classList.add('loaded');
                        imageObserver.unobserve(img);
                    }
                });
            });

            document.querySelectorAll('img[data-src]').forEach(img => {
                imageObserver.observe(img);
            });
        }
    }

    initPreloading() {
        const preloadLinks = [
            '/includes/css/bootstrap.min.css',
            '/includes/js/bootstrap.bundle.min.js',
            '/assets/css/enhanced-header.css'
        ];

        preloadLinks.forEach(href => {
            const link = document.createElement('link');
            link.rel = 'preload';
            link.href = href;
            link.as = href.endsWith('.css') ? 'style' : 'script';
            document.head.appendChild(link);
        });
    }

    // تحسين شريط التنقل
    initNavbar() {
        const navbar = document.getElementById('mainNavbar');
        if (!navbar) return;

        let lastScrollTop = 0;
        let scrollTimeout;

        const handleScroll = () => {
            const scrollTop = window.pageYOffset || document.documentElement.scrollTop;

            // إضافة تأثير الظل والشفافية
            if (scrollTop > AppConfig.navbar.scrollThreshold) {
                navbar.classList.add('scrolled');
            } else {
                navbar.classList.remove('scrolled');
            }

            // إخفاء/إظهار الشريط (اختياري)
            if (AppConfig.navbar.hideOnScroll) {
                if (scrollTop > lastScrollTop && scrollTop > 100) {
                    navbar.style.transform = 'translateY(-100%)';
                } else {
                    navbar.style.transform = 'translateY(0)';
                }
            }

            lastScrollTop = scrollTop;
        };

        // تحسين أداء التمرير
        window.addEventListener('scroll', () => {
            if (scrollTimeout) {
                clearTimeout(scrollTimeout);
            }
            scrollTimeout = setTimeout(handleScroll, 10);
        }, { passive: true });

        // تحديد الرابط النشط
        this.setActiveNavLink();

        // تحسين التنقل بلوحة المفاتيح
        this.initKeyboardNavigation();
    }

    setActiveNavLink() {
        const currentPath = window.location.pathname;
        const navLinks = document.querySelectorAll('.nav-link');

        navLinks.forEach(link => {
            const href = link.getAttribute('href');
            if (href && currentPath.includes(href)) {
                link.classList.add('active');
            } else {
                link.classList.remove('active');
            }
        });
    }

    initKeyboardNavigation() {
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Tab') {
                document.body.classList.add('keyboard-navigation');
            }
        });

        document.addEventListener('mousedown', () => {
            document.body.classList.remove('keyboard-navigation');
        });
    }

    // تحسين القوائم المنسدلة
    initDropdowns() {
        const dropdowns = document.querySelectorAll('.dropdown');

        dropdowns.forEach(dropdown => {
            const toggle = dropdown.querySelector('.dropdown-toggle');
            const menu = dropdown.querySelector('.dropdown-menu');

            if (!toggle || !menu) return;

            // تحسين الموضع للعربية
            menu.style.right = '0';
            menu.style.left = 'auto';

            // متغيرات للتحكم
            let hoverTimeout;
            let isOpen = false;

            // تحسين التفاعل للشاشات الكبيرة
            if (window.innerWidth > 768) {
                dropdown.addEventListener('mouseenter', () => {
                    clearTimeout(hoverTimeout);
                    this.openDropdown(menu, toggle);
                });

                dropdown.addEventListener('mouseleave', () => {
                    hoverTimeout = setTimeout(() => {
                        this.closeDropdown(menu, toggle);
                    }, AppConfig.dropdown.hoverDelay);
                });
            }

            // تحسين النقر
            toggle.addEventListener('click', (e) => {
                e.preventDefault();
                e.stopPropagation();

                if (isOpen) {
                    this.closeDropdown(menu, toggle);
                } else {
                    this.closeAllDropdowns();
                    this.openDropdown(menu, toggle);
                }

                isOpen = !isOpen;
            });

            // تحسين إمكانية الوصول
            toggle.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    toggle.click();
                }
            });
        });

        // إغلاق القوائم عند النقر خارجها
        document.addEventListener('click', (e) => {
            if (!e.target.closest('.dropdown')) {
                this.closeAllDropdowns();
            }
        });

        // إغلاق القوائم بمفتاح Escape
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.closeAllDropdowns();
                // إعادة التركيز للعنصر الذي فتح القائمة
                const activeToggle = document.querySelector('.dropdown-toggle[aria-expanded="true"]');
                if (activeToggle) {
                    activeToggle.focus();
                }
            }
        });
    }

    openDropdown(menu, toggle) {
        menu.classList.add('show');
        toggle.setAttribute('aria-expanded', 'true');
        menu.style.opacity = '0';
        menu.style.transform = 'translateY(-10px)';
        
        // تأثير الظهور
        requestAnimationFrame(() => {
            menu.style.opacity = '1';
            menu.style.transform = 'translateY(0)';
        });
    }

    closeDropdown(menu, toggle) {
        menu.style.opacity = '0';
        menu.style.transform = 'translateY(-10px)';
        
        setTimeout(() => {
            menu.classList.remove('show');
            toggle.setAttribute('aria-expanded', 'false');
        }, AppConfig.dropdown.animationDuration);
    }

    closeAllDropdowns() {
        document.querySelectorAll('.dropdown-menu.show').forEach(menu => {
            const toggle = menu.parentElement.querySelector('.dropdown-toggle');
            if (toggle) {
                this.closeDropdown(menu, toggle);
            }
        });
    }

    // تحسين النماذج
    initForms() {
        const formElements = document.querySelectorAll('.form-control, .form-select');

        formElements.forEach(element => {
            // تحسين التركيز
            element.addEventListener('focus', (e) => {
                const formGroup = e.target.closest('.form-group');
                if (formGroup) {
                    formGroup.classList.add('focused');
                }
                e.target.classList.add('focused');
            });

            element.addEventListener('blur', (e) => {
                const formGroup = e.target.closest('.form-group');
                if (formGroup) {
                    formGroup.classList.remove('focused');
                }
                e.target.classList.remove('focused');
            });

            // تحسين التحقق من الصحة
            element.addEventListener('input', (e) => {
                this.validateField(e.target);
            });

            // تحسين التحقق عند الإرسال
            element.addEventListener('invalid', (e) => {
                e.preventDefault();
                this.showFieldError(e.target, e.target.validationMessage);
            });
        });

        // تحسين إرسال النماذج
        document.querySelectorAll('form').forEach(form => {
            form.addEventListener('submit', (e) => {
                if (!this.validateForm(form)) {
                    e.preventDefault();
                }
            });
        });
    }

    validateField(field) {
        const isValid = field.checkValidity();
        field.classList.toggle('is-valid', isValid && field.value.trim() !== '');
        field.classList.toggle('is-invalid', !isValid);

        // إزالة رسائل الخطأ السابقة
        const errorMsg = field.parentElement.querySelector('.invalid-feedback');
        if (errorMsg) {
            errorMsg.remove();
        }

        // إضافة رسالة خطأ إذا لزم الأمر
        if (!isValid) {
            this.showFieldError(field, field.validationMessage);
        }

        return isValid;
    }

    showFieldError(field, message) {
        const errorDiv = document.createElement('div');
        errorDiv.className = 'invalid-feedback';
        errorDiv.textContent = message;
        field.parentElement.appendChild(errorDiv);
    }

    validateForm(form) {
        const fields = form.querySelectorAll('.form-control, .form-select');
        let isValid = true;

        fields.forEach(field => {
            if (!this.validateField(field)) {
                isValid = false;
            }
        });

        return isValid;
    }

    // تحسين الجداول
    initTables() {
        document.querySelectorAll('.table').forEach(table => {
            // تحسين الصفوف
            const rows = table.querySelectorAll('tbody tr');
            rows.forEach((row, index) => {
                // تأثير الظهور المتتالي
                row.style.animationDelay = `${index * 0.1}s`;
                
                // تحسين التفاعل
                row.addEventListener('mouseenter', () => {
                    row.style.backgroundColor = 'rgba(102, 126, 234, 0.1)';
                    row.style.transform = 'translateX(5px)';
                });

                row.addEventListener('mouseleave', () => {
                    row.style.backgroundColor = '';
                    row.style.transform = 'translateX(0)';
                });

                // إضافة تأثير النقر
                row.addEventListener('click', () => {
                    row.classList.add('table-row-clicked');
                    setTimeout(() => {
                        row.classList.remove('table-row-clicked');
                    }, 200);
                });
            });

            // تحسين التمرير الأفقي
            if (table.scrollWidth > table.clientWidth) {
                table.style.overflowX = 'auto';
                table.style.scrollbarWidth = 'thin';
            }

            // إضافة مؤشر التحميل
            if (table.querySelector('tbody').children.length === 0) {
                this.showTableLoading(table);
            }
        });
    }

    showTableLoading(table) {
        const tbody = table.querySelector('tbody');
        const colCount = table.querySelectorAll('thead th').length;
        
        const loadingRow = document.createElement('tr');
        loadingRow.className = 'table-loading';
        loadingRow.innerHTML = `
            <td colspan="${colCount}" class="text-center py-4">
                <div class="spinner-border text-primary" role="status">
                    <span class="visually-hidden">جاري التحميل...</span>
                </div>
                <div class="mt-2">جاري تحميل البيانات...</div>
            </td>
        `;
        
        tbody.appendChild(loadingRow);
    }

    // تحسين الأزرار
    initButtons() {
        document.querySelectorAll('.btn').forEach(button => {
            // تحسين التأثيرات
            button.addEventListener('mouseenter', () => {
                button.style.transform = 'translateY(-2px)';
            });

            button.addEventListener('mouseleave', () => {
                button.style.transform = 'translateY(0)';
            });

            // تأثير الضغط
            button.addEventListener('click', (e) => {
                this.createRippleEffect(button, e);
            });

            // تحسين إمكانية الوصول
            button.addEventListener('keydown', (e) => {
                if (e.key === 'Enter' || e.key === ' ') {
                    this.createRippleEffect(button, e);
                }
            });
        });
    }

    createRippleEffect(button, event) {
        const ripple = document.createElement('span');
        ripple.className = 'ripple';

        const rect = button.getBoundingClientRect();
        const size = Math.max(rect.width, rect.height);
        const x = event.clientX - rect.left - size / 2;
        const y = event.clientY - rect.top - size / 2;

        ripple.style.cssText = `
            position: absolute;
            border-radius: 50%;
            background: rgba(255, 255, 255, 0.6);
            transform: scale(0);
            animation: ripple 0.6s linear;
            left: ${x}px;
            top: ${y}px;
            width: ${size}px;
            height: ${size}px;
            pointer-events: none;
        `;

        button.style.position = 'relative';
        button.style.overflow = 'hidden';
        button.appendChild(ripple);

        setTimeout(() => {
            ripple.remove();
        }, 600);
    }

    // تحسين التنبيهات
    initAlerts() {
        document.querySelectorAll('.alert').forEach(alert => {
            // تأثير الظهور
            alert.style.animation = 'alertSlideIn 0.5s ease';

            // إغلاق تلقائي
            if (alert.classList.contains('alert-dismissible')) {
                setTimeout(() => {
                    const closeBtn = alert.querySelector('.btn-close');
                    if (closeBtn && alert.parentElement) {
                        this.fadeOutAlert(alert);
                    }
                }, AppConfig.alerts.autoHideDelay);
            }

            // تحسين زر الإغلاق
            const closeBtn = alert.querySelector('.btn-close');
            if (closeBtn) {
                closeBtn.addEventListener('click', () => {
                    this.fadeOutAlert(alert);
                });
            }
        });
    }

    fadeOutAlert(alert) {
        alert.style.animation = 'fadeOut 0.3s ease';
        setTimeout(() => {
            if (alert.parentElement) {
                alert.remove();
            }
        }, 300);
    }

    // تحسين الرسوم المتحركة
    initAnimations() {
        // إضافة CSS للرسوم المتحركة
        const style = document.createElement('style');
        style.textContent = `
            @keyframes ripple {
                to {
                    transform: scale(4);
                    opacity: 0;
                }
            }
            
            @keyframes alertSlideIn {
                from {
                    opacity: 0;
                    transform: translateY(-20px);
                }
                to {
                    opacity: 1;
                    transform: translateY(0);
                }
            }
            
            @keyframes fadeOut {
                from { opacity: 1; }
                to { opacity: 0; }
            }
            
            @keyframes slideInRight {
                from {
                    transform: translateX(100%);
                    opacity: 0;
                }
                to {
                    transform: translateX(0);
                    opacity: 1;
                }
            }
            
            @keyframes slideOutRight {
                from {
                    transform: translateX(0);
                    opacity: 1;
                }
                to {
                    transform: translateX(100%);
                    opacity: 0;
                }
            }
            
            @keyframes pulse {
                0%, 100% { transform: scale(1); }
                50% { transform: scale(1.05); }
            }
            
            @keyframes shimmer {
                0% { background-position: -200% 0; }
                100% { background-position: 200% 0; }
            }
            
            .table-row-clicked {
                animation: pulse 0.2s ease;
            }
            
            .loading-shimmer {
                background: linear-gradient(90deg, #f0f0f0 25%, #e0e0e0 50%, #f0f0f0 75%);
                background-size: 200% 100%;
                animation: shimmer 2s infinite;
            }
            
            .keyboard-navigation *:focus {
                outline: 2px solid var(--primary-color);
                outline-offset: 2px;
            }
        `;
        document.head.appendChild(style);
    }

    // تحسين إمكانية الوصول
    initAccessibility() {
        // تحسين التنقل بلوحة المفاتيح
        document.addEventListener('keydown', (e) => {
            // تحسين التنقل بمفتاح Tab
            if (e.key === 'Tab') {
                this.handleTabNavigation(e);
            }
        });

        // تحسين قارئ الشاشة
        this.enhanceScreenReader();

        // تحسين التباين
        this.enhanceContrast();
    }

    handleTabNavigation(e) {
        const focusableElements = document.querySelectorAll(
            'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
        );
        
        const firstElement = focusableElements[0];
        const lastElement = focusableElements[focusableElements.length - 1];

        if (e.shiftKey) {
            if (document.activeElement === firstElement) {
                lastElement.focus();
                e.preventDefault();
            }
        } else {
            if (document.activeElement === lastElement) {
                firstElement.focus();
                e.preventDefault();
            }
        }
    }

    enhanceScreenReader() {
        // إضافة aria-labels للعناصر التفاعلية
        document.querySelectorAll('.btn').forEach(btn => {
            if (!btn.getAttribute('aria-label') && !btn.textContent.trim()) {
                btn.setAttribute('aria-label', 'زر');
            }
        });

        // تحسين جداول البيانات
        document.querySelectorAll('.table').forEach(table => {
            if (!table.getAttribute('role')) {
                table.setAttribute('role', 'table');
            }
        });

        // تحسين النماذج
        document.querySelectorAll('.form-control').forEach(input => {
            const label = document.querySelector(`label[for="${input.id}"]`);
            if (!label && !input.getAttribute('aria-label')) {
                input.setAttribute('aria-label', input.placeholder || 'حقل إدخال');
            }
        });
    }

    enhanceContrast() {
        // فحص التباين وتحسينه إذا لزم الأمر
        const checkContrast = (element) => {
            const computedStyle = window.getComputedStyle(element);
            const backgroundColor = computedStyle.backgroundColor;
            const color = computedStyle.color;
            
            // يمكن إضافة منطق فحص التباين هنا
            // وتطبيق تحسينات حسب الحاجة
        };

        document.querySelectorAll('.btn, .alert, .card').forEach(checkContrast);
    }

    // تحسين PWA
    initPWA() {
        if ('serviceWorker' in navigator) {
            this.registerServiceWorker();
        }

        this.initInstallPrompt();
    }

    registerServiceWorker() {
        window.addEventListener('load', () => {
            navigator.serviceWorker.register('/sw.js')
                .then(registration => {
                    console.log('✅ Service Worker registered successfully');
                    this.handleServiceWorkerUpdate(registration);
                })
                .catch(error => {
                    console.log('❌ Service Worker registration failed:', error);
                });
        });
    }

    handleServiceWorkerUpdate(registration) {
        registration.addEventListener('updatefound', () => {
            const newWorker = registration.installing;
            newWorker.addEventListener('statechange', () => {
                if (newWorker.state === 'installed' && navigator.serviceWorker.controller) {
                    this.showUpdateAvailableNotification();
                }
            });
        });
    }

    showUpdateAvailableNotification() {
        this.showNotification(
            'يتوفر تحديث جديد للتطبيق. انقر لتحديث.',
            'info',
            10000,
            () => {
                window.location.reload();
            }
        );
    }

    initInstallPrompt() {
        let deferredPrompt;

        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            deferredPrompt = e;
            this.showInstallButton(deferredPrompt);
        });

        window.addEventListener('appinstalled', () => {
            console.log('✅ PWA installed successfully');
            this.hideInstallButton();
            this.showNotification('تم تثبيت التطبيق بنجاح!', 'success');
        });
    }

    showInstallButton(deferredPrompt) {
        const installButton = document.createElement('button');
        installButton.id = 'installPWA';
        installButton.innerHTML = '📱 تثبيت التطبيق';
        installButton.className = 'btn btn-primary position-fixed';
        installButton.style.cssText = `
            bottom: 20px;
            left: 20px;
            z-index: 1050;
            border-radius: 25px;
            padding: 12px 20px;
            font-size: 14px;
            font-weight: 600;
            box-shadow: 0 4px 15px rgba(0,0,0,0.2);
            animation: slideInLeft 0.3s ease;
        `;

        installButton.addEventListener('click', () => {
            deferredPrompt.prompt();
            deferredPrompt.userChoice.then(result => {
                if (result.outcome === 'accepted') {
                    console.log('User accepted the install prompt');
                }
                deferredPrompt = null;
                this.hideInstallButton();
            });
        });

        document.body.appendChild(installButton);
    }

    hideInstallButton() {
        const installButton = document.getElementById('installPWA');
        if (installButton) {
            installButton.style.animation = 'slideOutLeft 0.3s ease';
            setTimeout(() => {
                installButton.remove();
            }, 300);
        }
    }

    // تحسين حالة الاتصال
    initConnectionStatus() {
        window.addEventListener('online', () => {
            this.showConnectionStatus('🟢 متصل بالإنترنت', 'success');
        });

        window.addEventListener('offline', () => {
            this.showConnectionStatus('🔴 غير متصل - العمل في الوضع دون اتصال', 'warning');
        });
    }

    showConnectionStatus(message, type) {
        const statusDiv = document.createElement('div');
        statusDiv.className = `alert alert-${type} position-fixed`;
        statusDiv.style.cssText = `
            top: 90px;
            right: 20px;
            z-index: 1051;
            padding: 10px 15px;
            border-radius: 20px;
            font-size: 13px;
            font-weight: 500;
            min-width: 200px;
            text-align: center;
            animation: slideInRight 0.3s ease;
        `;
        statusDiv.textContent = message;

        document.body.appendChild(statusDiv);

        setTimeout(() => {
            statusDiv.style.animation = 'slideOutRight 0.3s ease';
            setTimeout(() => {
                statusDiv.remove();
            }, 300);
        }, 3000);
    }

    // دوال مساعدة
    showLoading() {
        const overlay = document.getElementById('loadingOverlay');
        if (overlay) {
            overlay.style.display = 'flex';
            overlay.style.animation = 'fadeIn 0.3s ease';
        }
    }

    hideLoading() {
        const overlay = document.getElementById('loadingOverlay');
        if (overlay) {
            overlay.style.animation = 'fadeOut 0.3s ease';
            setTimeout(() => {
                overlay.style.display = 'none';
            }, 300);
        }
    }

    showNotification(message, type = 'info', duration = 5000, callback = null) {
        const notification = document.createElement('div');
        notification.className = `alert alert-${type} position-fixed`;
        notification.style.cssText = `
            top: 100px;
            right: 20px;
            z-index: 1055;
            max-width: 350px;
            border-radius: 12px;
            box-shadow: 0 4px 20px rgba(0,0,0,0.15);
            animation: slideInRight 0.3s ease;
            cursor: pointer;
        `;

        const iconMap = {
            success: 'check-circle',
            error: 'exclamation-circle',
            warning: 'exclamation-triangle',
            info: 'info-circle'
        };

        notification.innerHTML = `
            <div class="d-flex align-items-center">
                <i class="fas fa-${iconMap[type] || 'info-circle'} me-2"></i>
                <div class="flex-grow-1">${message}</div>
                <button type="button" class="btn-close ms-2" aria-label="إغلاق"></button>
            </div>
        `;

        // إضافة مستمع النقر
        if (callback) {
            notification.addEventListener('click', callback);
        }

        // إضافة مستمع الإغلاق
        const closeBtn = notification.querySelector('.btn-close');
        closeBtn.addEventListener('click', (e) => {
            e.stopPropagation();
            this.hideNotification(notification);
        });

        document.body.appendChild(notification);

        // إغلاق تلقائي
        setTimeout(() => {
            this.hideNotification(notification);
        }, duration);
    }

    hideNotification(notification) {
        notification.style.animation = 'slideOutRight 0.3s ease';
        setTimeout(() => {
            if (notification.parentElement) {
                notification.remove();
            }
        }, 300);
    }

    // دالة للتحقق من الأداء
    checkPerformance() {
        if (window.performance && window.performance.timing) {
            const perfData = window.performance.timing;
            const loadTime = perfData.loadEventEnd - perfData.navigationStart;
            
            console.log(`📊 Page Load Time: ${loadTime}ms`);
            
            if (loadTime > 3000) {
                console.warn('⚠️ Slow page load detected');
            }
        }
    }
}

// إنشاء مثيل من المدير المحسن
const enhancedHeaderManager = new EnhancedHeaderManager();

// إضافة دوال عامة للاستخدام في الصفحات الأخرى
window.HeaderManager = {
    showLoading: () => enhancedHeaderManager.showLoading(),
    hideLoading: () => enhancedHeaderManager.hideLoading(),
    showNotification: (message, type, duration, callback) => 
        enhancedHeaderManager.showNotification(message, type, duration, callback),
    validateForm: (form) => enhancedHeaderManager.validateForm(form),
    showTableLoading: (table) => enhancedHeaderManager.showTableLoading(table)
};

// فحص الأداء عند التحميل
window.addEventListener('load', () => {
    enhancedHeaderManager.checkPerformance();
});

// إضافة CSS للرسوم المتحركة الإضافية
const additionalStyles = `
    @keyframes slideInLeft {
        from {
            transform: translateX(-100%);
            opacity: 0;
        }
        to {
            transform: translateX(0);
            opacity: 1;
        }
    }
    
    @keyframes slideOutLeft {
        from {
            transform: translateX(0);
            opacity: 1;
        }
        to {
            transform: translateX(-100%);
            opacity: 0;
        }
    }
`;

const styleSheet = document.createElement('style');
styleSheet.textContent = additionalStyles;
document.head.appendChild(styleSheet);