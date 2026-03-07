/**
 * ملف JavaScript محسن لواجهة المستخدم
 * يوفر تفاعل محسن وتحقق من صحة البيانات
 */

// إعدادات عامة
const UI_CONFIG = {
    animationDuration: 300,
    debounceDelay: 300,
    toastDuration: 5000,
    loadingText: 'جاري التحميل...',
    errorText: 'حدث خطأ',
    successText: 'تم بنجاح'
};

/**
 * فئة إدارة واجهة المستخدم
 */
class UIManager {
    constructor() {
        this.init();
    }
    
    init() {
        this.setupEventListeners();
        this.initializeComponents();
        this.setupFormValidation();
        this.setupTooltips();
    }
    
    /**
     * إعداد مستمعي الأحداث
     */
    setupEventListeners() {
        // تحسين تجربة النماذج
        document.addEventListener('DOMContentLoaded', () => {
            this.enhanceForms();
            this.setupLoadingStates();
            this.initializeDataTables();
        });
        
        // معالجة الأخطاء العامة
        window.addEventListener('error', (e) => {
            console.error('خطأ في JavaScript:', e.error);
            this.showToast('حدث خطأ في الواجهة', 'error');
        });
        
        // معالجة الضغط على Escape
        document.addEventListener('keydown', (e) => {
            if (e.key === 'Escape') {
                this.closeModals();
                this.hideToasts();
            }
        });
    }
    
    /**
     * تحسين النماذج
     */
    enhanceForms() {
        const forms = document.querySelectorAll('form');
        
        forms.forEach(form => {
            // إضافة تحقق في الوقت الفعلي
            this.addRealTimeValidation(form);
            
            // منع الإرسال المتكرر
            this.preventDoubleSubmit(form);
            
            // حفظ البيانات تلقائياً
            this.setupAutoSave(form);
        });
    }
    
    /**
     * إضافة تحقق في الوقت الفعلي
     */
    addRealTimeValidation(form) {
        const inputs = form.querySelectorAll('input, select, textarea');
        
        inputs.forEach(input => {
            // تحقق عند فقدان التركيز
            input.addEventListener('blur', () => {
                this.validateField(input);
            });
            
            // تحقق أثناء الكتابة (مع تأخير)
            input.addEventListener('input', this.debounce(() => {
                this.validateField(input);
            }, UI_CONFIG.debounceDelay));
        });
    }
    
    /**
     * التحقق من صحة حقل واحد
     */
    validateField(field) {
        const value = field.value.trim();
        const type = field.type;
        const required = field.hasAttribute('required');
        let isValid = true;
        let errorMessage = '';
        
        // إزالة رسائل الخطأ السابقة
        this.clearFieldError(field);
        
        // التحقق من الحقول المطلوبة
        if (required && !value) {
            isValid = false;
            errorMessage = 'هذا الحقل مطلوب';
        }
        
        // التحقق حسب نوع الحقل
        if (value && !isValid) {
            switch (type) {
                case 'email':
                    if (!this.isValidEmail(value)) {
                        isValid = false;
                        errorMessage = 'يرجى إدخال بريد إلكتروني صحيح';
                    }
                    break;
                    
                case 'tel':
                    if (!this.isValidPhone(value)) {
                        isValid = false;
                        errorMessage = 'يرجى إدخال رقم هاتف صحيح';
                    }
                    break;
                    
                case 'number':
                    if (isNaN(value)) {
                        isValid = false;
                        errorMessage = 'يرجى إدخال رقم صحيح';
                    }
                    break;
                    
                case 'password':
                    if (value.length < 8) {
                        isValid = false;
                        errorMessage = 'كلمة المرور يجب أن تكون 8 أحرف على الأقل';
                    }
                    break;
            }
        }
        
        // عرض النتيجة
        if (!isValid) {
            this.showFieldError(field, errorMessage);
        } else {
            this.showFieldSuccess(field);
        }
        
        return isValid;
    }
    
    /**
     * عرض خطأ في الحقل
     */
    showFieldError(field, message) {
        field.classList.add('is-invalid');
        field.classList.remove('is-valid');
        
        const errorDiv = document.createElement('div');
        errorDiv.className = 'invalid-feedback';
        errorDiv.textContent = message;
        
        field.parentNode.appendChild(errorDiv);
    }
    
    /**
     * عرض نجاح في الحقل
     */
    showFieldSuccess(field) {
        field.classList.add('is-valid');
        field.classList.remove('is-invalid');
    }
    
    /**
     * مسح خطأ الحقل
     */
    clearFieldError(field) {
        field.classList.remove('is-invalid', 'is-valid');
        const errorDiv = field.parentNode.querySelector('.invalid-feedback');
        if (errorDiv) {
            errorDiv.remove();
        }
    }
    
    /**
     * منع الإرسال المتكرر للنماذج
     */
    preventDoubleSubmit(form) {
        form.addEventListener('submit', (e) => {
            const submitBtn = form.querySelector('button[type="submit"]');
            
            if (submitBtn && submitBtn.disabled) {
                e.preventDefault();
                return false;
            }
            
            if (submitBtn) {
                submitBtn.disabled = true;
                submitBtn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> ' + UI_CONFIG.loadingText;
                
                // إعادة تفعيل الزر بعد 5 ثوان كحماية
                setTimeout(() => {
                    submitBtn.disabled = false;
                    submitBtn.innerHTML = submitBtn.getAttribute('data-original-text') || 'إرسال';
                }, 5000);
            }
        });
    }
    
    /**
     * إعداد الحفظ التلقائي
     */
    setupAutoSave(form) {
        if (!form.hasAttribute('data-autosave')) return;
        
        const inputs = form.querySelectorAll('input, select, textarea');
        const formId = form.id || 'form_' + Date.now();
        
        // استرجاع البيانات المحفوظة
        this.loadAutoSavedData(formId, inputs);
        
        // حفظ البيانات عند التغيير
        inputs.forEach(input => {
            input.addEventListener('input', this.debounce(() => {
                this.saveFormData(formId, inputs);
            }, 1000));
        });
    }
    
    /**
     * حفظ بيانات النموذج
     */
    saveFormData(formId, inputs) {
        const data = {};
        inputs.forEach(input => {
            if (input.name && input.type !== 'password') {
                data[input.name] = input.value;
            }
        });
        
        localStorage.setItem('autosave_' + formId, JSON.stringify(data));
    }
    
    /**
     * تحميل البيانات المحفوظة
     */
    loadAutoSavedData(formId, inputs) {
        const savedData = localStorage.getItem('autosave_' + formId);
        if (!savedData) return;
        
        try {
            const data = JSON.parse(savedData);
            inputs.forEach(input => {
                if (input.name && data[input.name] && input.type !== 'password') {
                    input.value = data[input.name];
                }
            });
        } catch (e) {
            console.error('خطأ في تحميل البيانات المحفوظة:', e);
        }
    }
    
    /**
     * عرض رسالة منبثقة
     */
    showToast(message, type = 'info', duration = UI_CONFIG.toastDuration) {
        const toast = document.createElement('div');
        toast.className = `toast toast-${type}`;
        toast.innerHTML = `
            <div class="toast-content">
                <i class="fas fa-${this.getToastIcon(type)}"></i>
                <span>${message}</span>
                <button class="toast-close" onclick="this.parentElement.parentElement.remove()">
                    <i class="fas fa-times"></i>
                </button>
            </div>
        `;
        
        // إضافة إلى الصفحة
        let toastContainer = document.querySelector('.toast-container');
        if (!toastContainer) {
            toastContainer = document.createElement('div');
            toastContainer.className = 'toast-container';
            document.body.appendChild(toastContainer);
        }
        
        toastContainer.appendChild(toast);
        
        // إزالة تلقائية
        setTimeout(() => {
            if (toast.parentNode) {
                toast.remove();
            }
        }, duration);
        
        return toast;
    }
    
    /**
     * الحصول على أيقونة الرسالة المنبثقة
     */
    getToastIcon(type) {
        const icons = {
            success: 'check-circle',
            error: 'exclamation-circle',
            warning: 'exclamation-triangle',
            info: 'info-circle'
        };
        return icons[type] || 'info-circle';
    }
    
    /**
     * إخفاء جميع الرسائل المنبثقة
     */
    hideToasts() {
        const toasts = document.querySelectorAll('.toast');
        toasts.forEach(toast => toast.remove());
    }
    
    /**
     * إغلاق النوافذ المنبثقة
     */
    closeModals() {
        const modals = document.querySelectorAll('.modal.show');
        modals.forEach(modal => {
            modal.classList.remove('show');
        });
    }
    
    /**
     * دالة التأخير
     */
    debounce(func, wait) {
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
     * التحقق من صحة البريد الإلكتروني
     */
    isValidEmail(email) {
        const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
        return emailRegex.test(email);
    }
    
    /**
     * التحقق من صحة رقم الهاتف اليمني
     */
    isValidPhone(phone) {
        const phoneRegex = /^(967|00967|\+967)?[0-9]{8,9}$/;
        return phoneRegex.test(phone.replace(/\s+/g, ''));
    }
    
    /**
     * تهيئة المكونات
     */
    initializeComponents() {
        // تهيئة الجداول
        this.initializeDataTables();
        
        // تهيئة التواريخ
        this.initializeDatePickers();
        
        // تهيئة الرسوم البيانية
        this.initializeCharts();
    }
    
    /**
     * تهيئة الجداول المحسنة
     */
    initializeDataTables() {
        const tables = document.querySelectorAll('.data-table');
        
        tables.forEach(table => {
            // إضافة البحث
            this.addTableSearch(table);
            
            // إضافة الترتيب
            this.addTableSorting(table);
            
            // إضافة التصفية
            this.addTableFiltering(table);
        });
    }
    
    /**
     * إضافة البحث للجدول
     */
    addTableSearch(table) {
        const searchInput = document.createElement('input');
        searchInput.type = 'text';
        searchInput.placeholder = 'البحث في الجدول...';
        searchInput.className = 'table-search form-control';
        
        // إدراج قبل الجدول
        table.parentNode.insertBefore(searchInput, table);
        
        searchInput.addEventListener('input', this.debounce((e) => {
            this.filterTable(table, e.target.value);
        }, 300));
    }
    
    /**
     * تصفية الجدول
     */
    filterTable(table, searchTerm) {
        const rows = table.querySelectorAll('tbody tr');
        const term = searchTerm.toLowerCase();
        
        rows.forEach(row => {
            const text = row.textContent.toLowerCase();
            row.style.display = text.includes(term) ? '' : 'none';
        });
    }
    
    /**
     * إعداد حالات التحميل
     */
    setupLoadingStates() {
        // إضافة مؤشر تحميل للروابط المهمة
        const importantLinks = document.querySelectorAll('a[data-loading]');
        
        importantLinks.forEach(link => {
            link.addEventListener('click', (e) => {
                this.showLoadingOverlay();
            });
        });
    }
    
    /**
     * عرض طبقة التحميل
     */
    showLoadingOverlay() {
        const overlay = document.createElement('div');
        overlay.className = 'loading-overlay';
        overlay.innerHTML = `
            <div class="loading-spinner">
                <i class="fas fa-spinner fa-spin fa-3x"></i>
                <p>${UI_CONFIG.loadingText}</p>
            </div>
        `;
        
        document.body.appendChild(overlay);
        
        // إزالة بعد 10 ثوان كحماية
        setTimeout(() => {
            if (overlay.parentNode) {
                overlay.remove();
            }
        }, 10000);
    }
    
    /**
     * إخفاء طبقة التحميل
     */
    hideLoadingOverlay() {
        const overlay = document.querySelector('.loading-overlay');
        if (overlay) {
            overlay.remove();
        }
    }
}

// تهيئة مدير واجهة المستخدم
const uiManager = new UIManager();

// دوال مساعدة عامة
window.showToast = (message, type, duration) => {
    return uiManager.showToast(message, type, duration);
};

window.showLoading = () => {
    uiManager.showLoadingOverlay();
};

window.hideLoading = () => {
    uiManager.hideLoadingOverlay();
};

// تصدير للاستخدام في ملفات أخرى
if (typeof module !== 'undefined' && module.exports) {
    module.exports = UIManager;
}
