/**
 * ملف JavaScript المحسن لوحة الإدارة
 * يحتوي على وظائف تحسين تجربة المستخدم والتفاعل مع القوائم
 */

document.addEventListener('DOMContentLoaded', function() {
    // تحسين القوائم المنسدلة
    initDropdowns();
    
    // تحسين النماذج
    initForms();
    
    // تحسين الجداول
    initTables();
    
    // تحسين التنبيهات
    initAlerts();
    
    // تحسين الملاحة
    initNavigation();
});

/**
 * تحسين القوائم المنسدلة
 */
function initDropdowns() {
    const dropdowns = document.querySelectorAll('.dropdown');
    
    dropdowns.forEach(dropdown => {
        const toggle = dropdown.querySelector('.dropdown-toggle');
        const menu = dropdown.querySelector('.dropdown-menu');
        
        if (toggle && menu) {
            // إضافة تأثير hover للشاشات الكبيرة
            if (window.innerWidth > 768) {
                dropdown.addEventListener('mouseenter', function() {
                    showDropdown(menu, toggle);
                });
                
                dropdown.addEventListener('mouseleave', function() {
                    hideDropdown(menu, toggle);
                });
            }
            
            // تحسين النقر
            toggle.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                
                // إغلاق القوائم الأخرى
                hideAllDropdowns();
                
                // تبديل القائمة الحالية
                if (menu.classList.contains('show')) {
                    hideDropdown(menu, toggle);
                } else {
                    showDropdown(menu, toggle);
                }
            });
            
            // تحسين الوصول بلوحة المفاتيح
            toggle.addEventListener('keydown', function(e) {
                if (e.key === 'Enter' || e.key === ' ') {
                    e.preventDefault();
                    toggle.click();
                } else if (e.key === 'ArrowDown') {
                    e.preventDefault();
                    showDropdown(menu, toggle);
                    focusFirstMenuItem(menu);
                }
            });
            
            // تحسين الملاحة بالأسهم
            const menuItems = menu.querySelectorAll('.dropdown-item');
            menuItems.forEach((item, index) => {
                item.addEventListener('keydown', function(e) {
                    if (e.key === 'ArrowDown') {
                        e.preventDefault();
                        const nextItem = menuItems[index + 1];
                        if (nextItem) nextItem.focus();
                    } else if (e.key === 'ArrowUp') {
                        e.preventDefault();
                        const prevItem = menuItems[index - 1];
                        if (prevItem) {
                            prevItem.focus();
                        } else {
                            toggle.focus();
                        }
                    } else if (e.key === 'Escape') {
                        e.preventDefault();
                        hideDropdown(menu, toggle);
                        toggle.focus();
                    }
                });
            });
        }
    });
    
    // إغلاق القوائم عند النقر خارجها
    document.addEventListener('click', function(e) {
        if (!e.target.closest('.dropdown')) {
            hideAllDropdowns();
        }
    });
    
    // إغلاق القوائم بمفتاح Escape
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape') {
            hideAllDropdowns();
        }
    });
}

/**
 * عرض القائمة المنسدلة
 */
function showDropdown(menu, toggle) {
    menu.classList.add('show');
    toggle.setAttribute('aria-expanded', 'true');
    
    // إضافة تأثير الحركة
    menu.style.opacity = '0';
    menu.style.transform = 'translateY(-10px)';
    
    setTimeout(() => {
        menu.style.transition = 'opacity 0.3s ease, transform 0.3s ease';
        menu.style.opacity = '1';
        menu.style.transform = 'translateY(0)';
    }, 10);
}

/**
 * إخفاء القائمة المنسدلة
 */
function hideDropdown(menu, toggle) {
    menu.style.opacity = '0';
    menu.style.transform = 'translateY(-10px)';
    
    setTimeout(() => {
        menu.classList.remove('show');
        toggle.setAttribute('aria-expanded', 'false');
        menu.style.transition = '';
        menu.style.opacity = '';
        menu.style.transform = '';
    }, 300);
}

/**
 * إخفاء جميع القوائم المنسدلة
 */
function hideAllDropdowns() {
    const openMenus = document.querySelectorAll('.dropdown-menu.show');
    openMenus.forEach(menu => {
        const toggle = menu.parentElement.querySelector('.dropdown-toggle');
        if (toggle) {
            hideDropdown(menu, toggle);
        }
    });
}

/**
 * التركيز على أول عنصر في القائمة
 */
function focusFirstMenuItem(menu) {
    const firstItem = menu.querySelector('.dropdown-item');
    if (firstItem) {
        firstItem.focus();
    }
}

/**
 * تحسين النماذج
 */
function initForms() {
    const forms = document.querySelectorAll('form');
    
    forms.forEach(form => {
        // تحسين حقول الإدخال
        const inputs = form.querySelectorAll('input, textarea, select');
        inputs.forEach(input => {
            // إضافة تأثيرات التركيز
            input.addEventListener('focus', function() {
                this.parentElement.classList.add('focused');
            });
            
            input.addEventListener('blur', function() {
                this.parentElement.classList.remove('focused');
                if (this.value.trim() !== '') {
                    this.parentElement.classList.add('has-value');
                } else {
                    this.parentElement.classList.remove('has-value');
                }
            });
            
            // التحقق من وجود قيمة عند التحميل
            if (input.value.trim() !== '') {
                input.parentElement.classList.add('has-value');
            }
        });
        
        // تحسين التحقق من صحة النماذج
        form.addEventListener('submit', function(e) {
            const requiredFields = form.querySelectorAll('[required]');
            let isValid = true;
            
            requiredFields.forEach(field => {
                if (!field.value.trim()) {
                    field.classList.add('is-invalid');
                    isValid = false;
                } else {
                    field.classList.remove('is-invalid');
                }
            });
            
            if (!isValid) {
                e.preventDefault();
                showError('يرجى ملء جميع الحقول المطلوبة');
            }
        });
    });
}

/**
 * تحسين الجداول
 */
function initTables() {
    const tables = document.querySelectorAll('table');
    
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
        
        // تحسين الأزرار في الجداول
        const actionButtons = table.querySelectorAll('.btn');
        actionButtons.forEach(button => {
            button.addEventListener('click', function(e) {
                if (this.classList.contains('btn-danger')) {
                    if (!confirm('هل أنت متأكد من هذا الإجراء؟')) {
                        e.preventDefault();
                    }
                }
            });
        });
    });
}

/**
 * تحسين التنبيهات
 */
function initAlerts() {
    const alerts = document.querySelectorAll('.alert');
    
    alerts.forEach(alert => {
        // إضافة تأثير الظهور
        alert.style.opacity = '0';
        alert.style.transform = 'translateY(-20px)';
        
        setTimeout(() => {
            alert.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
            alert.style.opacity = '1';
            alert.style.transform = 'translateY(0)';
        }, 100);
        
        // الإخفاء التلقائي
        if (alert.classList.contains('alert-success')) {
            setTimeout(() => {
                hideAlert(alert);
            }, 5000);
        }
    });
}

/**
 * إخفاء التنبيه
 */
function hideAlert(alert) {
    alert.style.opacity = '0';
    alert.style.transform = 'translateY(-20px)';
    
    setTimeout(() => {
        alert.remove();
    }, 500);
}

/**
 * تحسين الملاحة
 */
function initNavigation() {
    const navLinks = document.querySelectorAll('.nav-link');
    
    navLinks.forEach(link => {
        // إضافة تأثيرات التركيز
        link.addEventListener('focus', function() {
            this.style.outline = '2px solid #007bff';
            this.style.outlineOffset = '2px';
        });
        
        link.addEventListener('blur', function() {
            this.style.outline = '';
            this.style.outlineOffset = '';
        });
    });
    
    // تحسين تنقل لوحة المفاتيح
    document.addEventListener('keydown', function(e) {
        if (e.altKey && e.key === 'm') {
            e.preventDefault();
            const firstNavLink = document.querySelector('.navbar-nav .nav-link');
            if (firstNavLink) {
                firstNavLink.focus();
            }
        }
    });
}

/**
 * عرض رسالة نجاح
 */
function showSuccess(message) {
    const alertDiv = document.createElement('div');
    alertDiv.className = 'alert alert-success alert-dismissible fade show';
    alertDiv.innerHTML = `
        <i class="fas fa-check-circle me-2"></i>
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
    `;
    
    insertAlert(alertDiv);
}

/**
 * عرض رسالة خطأ
 */
function showError(message) {
    const alertDiv = document.createElement('div');
    alertDiv.className = 'alert alert-danger alert-dismissible fade show';
    alertDiv.innerHTML = `
        <i class="fas fa-exclamation-circle me-2"></i>
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
    `;
    
    insertAlert(alertDiv);
}

/**
 * عرض رسالة تحذير
 */
function showWarning(message) {
    const alertDiv = document.createElement('div');
    alertDiv.className = 'alert alert-warning alert-dismissible fade show';
    alertDiv.innerHTML = `
        <i class="fas fa-exclamation-triangle me-2"></i>
        ${message}
        <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="إغلاق"></button>
    `;
    
    insertAlert(alertDiv);
}

/**
 * إدراج التنبيه في الصفحة
 */
function insertAlert(alertDiv) {
    const container = document.querySelector('.container');
    if (container) {
        container.insertBefore(alertDiv, container.firstChild);
        
        // إضافة تأثير الظهور
        alertDiv.style.opacity = '0';
        alertDiv.style.transform = 'translateY(-20px)';
        
        setTimeout(() => {
            alertDiv.style.transition = 'opacity 0.5s ease, transform 0.5s ease';
            alertDiv.style.opacity = '1';
            alertDiv.style.transform = 'translateY(0)';
        }, 100);
    }
}

/**
 * تأكيد الحذف
 */
function confirmDelete(message = 'هل أنت متأكد من الحذف؟') {
    return confirm(message);
}

/**
 * تحسين الأداء - تأخير التنفيذ
 */
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func(...args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

/**
 * تحسين الأداء - تحديد معدل التنفيذ
 */
function throttle(func, limit) {
    let inThrottle;
    return function() {
        const args = arguments;
        const context = this;
        if (!inThrottle) {
            func.apply(context, args);
            inThrottle = true;
            setTimeout(() => inThrottle = false, limit);
        }
    }
}

// تصدير الوظائف للاستخدام العام
window.showSuccess = showSuccess;
window.showError = showError;
window.showWarning = showWarning;
window.confirmDelete = confirmDelete;
window.debounce = debounce;
window.throttle = throttle;