/**
 * ملف JavaScript لتحسين تفاعل صفحات التقارير
 */

// تصدير التقارير
function exportReport(type, action) {
    let startDate = '';
    let endDate = '';
    
    // جلب التواريخ حسب نوع التقرير
    switch(type) {
        case 'bookings':
            startDate = document.getElementById('bookings_start_date').value;
            endDate = document.getElementById('bookings_end_date').value;
            break;
        case 'financial':
            startDate = document.getElementById('financial_start_date').value;
            endDate = document.getElementById('financial_end_date').value;
            break;
        default:
            startDate = document.getElementById('start_date')?.value || '';
            endDate = document.getElementById('end_date')?.value || '';
    }
    
    // بناء URL التصدير
    let url = `reports.php?export=${action}&type=${type}`;
    if (startDate) url += `&start_date=${startDate}`;
    if (endDate) url += `&end_date=${endDate}`;
    
    // فتح في نافذة جديدة للعرض أو تحميل مباشر
    if (action === 'view') {
        window.open(url, '_blank');
    } else {
        window.location.href = url;
    }
}

// تصدير إلى Excel من صفحة التقارير
function exportToExcel() {
    const startDate = document.getElementById('start_date')?.value || '';
    const endDate = document.getElementById('end_date')?.value || '';
    const reportType = document.getElementById('report_type')?.value || 'all';
    
    let url = 'export_excel.php?';
    const params = new URLSearchParams();
    
    if (startDate) params.append('start_date', startDate);
    if (endDate) params.append('end_date', endDate);
    if (reportType) params.append('report_type', reportType);
    
    url += params.toString();
    window.location.href = url;
}

// تصدير إلى PDF من صفحة التقارير
function exportToPDF() {
    const startDate = document.getElementById('start_date')?.value || '';
    const endDate = document.getElementById('end_date')?.value || '';
    const reportType = document.getElementById('report_type')?.value || 'all';
    
    let url = 'export_pdf.php?';
    const params = new URLSearchParams();
    
    if (startDate) params.append('start_date', startDate);
    if (endDate) params.append('end_date', endDate);
    if (reportType) params.append('report_type', reportType);
    
    url += params.toString();
    window.open(url, '_blank');
}

// اختصارات التاريخ
document.addEventListener('DOMContentLoaded', function() {
    // إضافة أحداث للاختصارات
    const shortcuts = document.querySelectorAll('.date-shortcut');
    shortcuts.forEach(shortcut => {
        shortcut.addEventListener('click', function() {
            const range = this.getAttribute('data-range');
            setDateRange(range);
        });
    });
    
    // إضافة أحداث أزرار التصدير
    const exportButtons = document.querySelectorAll('[onclick*="exportReport"]');
    exportButtons.forEach(button => {
        button.addEventListener('click', function(e) {
            // إضافة تأثير التحميل
            this.disabled = true;
            this.innerHTML = '<i class="fas fa-spinner fa-spin"></i> جاري التصدير...';
            
            // إعادة تفعيل الزر بعد 3 ثوانٍ
            setTimeout(() => {
                this.disabled = false;
                this.innerHTML = this.getAttribute('data-original-text') || 'تصدير';
            }, 3000);
        });
    });
});

// تعيين نطاق التاريخ
function setDateRange(range) {
    const startDateInput = document.getElementById('start_date');
    const endDateInput = document.getElementById('end_date');
    
    if (!startDateInput || !endDateInput) return;
    
    const today = new Date();
    let startDate, endDate;
    
    switch(range) {
        case 'today':
            startDate = endDate = formatDate(today);
            break;
            
        case 'yesterday':
            const yesterday = new Date(today);
            yesterday.setDate(today.getDate() - 1);
            startDate = endDate = formatDate(yesterday);
            break;
            
        case 'this_week':
            const thisWeekStart = new Date(today);
            thisWeekStart.setDate(today.getDate() - today.getDay());
            startDate = formatDate(thisWeekStart);
            endDate = formatDate(today);
            break;
            
        case 'last_week':
            const lastWeekEnd = new Date(today);
            lastWeekEnd.setDate(today.getDate() - today.getDay() - 1);
            const lastWeekStart = new Date(lastWeekEnd);
            lastWeekStart.setDate(lastWeekEnd.getDate() - 6);
            startDate = formatDate(lastWeekStart);
            endDate = formatDate(lastWeekEnd);
            break;
            
        case 'this_month':
            startDate = formatDate(new Date(today.getFullYear(), today.getMonth(), 1));
            endDate = formatDate(new Date(today.getFullYear(), today.getMonth() + 1, 0));
            break;
            
        case 'last_month':
            const lastMonth = new Date(today.getFullYear(), today.getMonth() - 1, 1);
            startDate = formatDate(lastMonth);
            endDate = formatDate(new Date(today.getFullYear(), today.getMonth(), 0));
            break;
            
        case 'this_year':
            startDate = formatDate(new Date(today.getFullYear(), 0, 1));
            endDate = formatDate(today);
            break;
    }
    
    if (startDate && endDate) {
        startDateInput.value = startDate;
        endDateInput.value = endDate;
        
        // تطبيق التصفية تلقائياً
        const form = startDateInput.closest('form');
        if (form) {
            form.submit();
        }
    }
}

// تنسيق التاريخ
function formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

// التحقق من صحة التواريخ
function validateDateRange() {
    const startDate = document.getElementById('start_date')?.value;
    const endDate = document.getElementById('end_date')?.value;
    
    if (startDate && endDate && startDate > endDate) {
        alert('تاريخ البداية يجب أن يكون أقل من أو يساوي تاريخ النهاية');
        return false;
    }
    return true;
}

// معاينة التقرير قبل التصدير
function previewReport(type) {
    if (!validateDateRange()) return;
    
    const startDate = document.getElementById('start_date')?.value || '';
    const endDate = document.getElementById('end_date')?.value || '';
    
    let url = `report.php?report_type=${type}`;
    if (startDate) url += `&start_date=${startDate}`;
    if (endDate) url += `&end_date=${endDate}`;
    
    window.open(url, '_blank');
}

// تحديث الإحصائيات في الوقت الفعلي
function refreshStats() {
    const refreshButton = document.getElementById('refresh-stats');
    if (refreshButton) {
        refreshButton.disabled = true;
        refreshButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> جاري التحديث...';
        
        // إعادة تحميل الصفحة
        setTimeout(() => {
            location.reload();
        }, 1000);
    }
}

// طباعة مخصصة للتقارير
function printReport() {
    // إخفاء العناصر غير المطلوبة للطباعة
    const noPrintElements = document.querySelectorAll('.no-print');
    noPrintElements.forEach(element => {
        element.style.display = 'none';
    });
    
    // طباعة
    window.print();
    
    // إعادة إظهار العناصر
    noPrintElements.forEach(element => {
        element.style.display = '';
    });
}

// تحسين عرض الجداول على الأجهزة المحمولة
function initializeTableResponsive() {
    const tables = document.querySelectorAll('.table-responsive table');
    tables.forEach(table => {
        if (window.innerWidth < 768) {
            // إضافة شريط التمرير الأفقي للجداول
            table.style.minWidth = '600px';
        }
    });
}

// تفعيل التبويبات
function initializeTabs() {
    const tabs = document.querySelectorAll('[data-toggle="tab"]');
    tabs.forEach(tab => {
        tab.addEventListener('click', function(e) {
            e.preventDefault();
            
            // إزالة الفئة النشطة من جميع التبويبات
            const allTabs = document.querySelectorAll('[data-toggle="tab"]');
            const allPanes = document.querySelectorAll('.tab-pane');
            
            allTabs.forEach(t => t.classList.remove('active'));
            allPanes.forEach(p => {
                p.classList.remove('show', 'active');
            });
            
            // تفعيل التبويب المحدد
            this.classList.add('active');
            const target = this.getAttribute('href');
            const targetPane = document.querySelector(target);
            if (targetPane) {
                targetPane.classList.add('show', 'active');
            }
        });
    });
}

// تشغيل الدوال عند تحميل الصفحة
document.addEventListener('DOMContentLoaded', function() {
    initializeTableResponsive();
    initializeTabs();
    
    // إضافة معالج لتغيير حجم النافذة
    window.addEventListener('resize', initializeTableResponsive);
    
    // التحقق من صحة النماذج
    const forms = document.querySelectorAll('form[method="GET"]');
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            if (!validateDateRange()) {
                e.preventDefault();
            }
        });
    });
});/**
 * ملف JavaScript لتحسين تفاعل صفحات التقارير
 */

// تصدير التقارير
function exportReport(type, action) {
    let startDate = '';
    let endDate = '';
    
    // جلب التواريخ حسب نوع التقرير
    switch(type) {
        case 'bookings':
            startDate = document.getElementById('bookings_start_date').value;
            endDate = document.getElementById('bookings_end_date').value;
            break;
        case 'financial':
            startDate = document.getElementById('financial_start_date').value;
            endDate = document.getElementById('financial_end_date').value;
            break;
        default:
            startDate = document.getElementById('start_date')?.value || '';
            endDate = document.getElementById('end_date')?.value || '';
    }
    
    // بناء URL التصدير
    let url = `reports.php?export=${action}&type=${type}`;
    if (startDate) url += `&start_date=${startDate}`;
    if (endDate) url += `&end_date=${endDate}`;
    
    // فتح في نافذة جديدة للعرض أو تحميل مباشر
    if (action === 'view') {
        window.open(url, '_blank');
    } else {
        window.location.href = url;
    }
}

// تصدير إلى Excel من صفحة التقارير
function exportToExcel() {
    const startDate = document.getElementById('start_date')?.value || '';
    const endDate = document.getElementById('end_date')?.value || '';
    const reportType = document.getElementById('report_type')?.value || 'all';
    
    let url = 'export_excel.php?';
    const params = new URLSearchParams();
    
    if (startDate) params.append('start_date', startDate);
    if (endDate) params.append('end_date', endDate);
    if (reportType) params.append('report_type', reportType);
    
    url += params.toString();
    window.location.href = url;
}

// تصدير إلى PDF من صفحة التقارير
function exportToPDF() {
    const startDate = document.getElementById('start_date')?.value || '';
    const endDate = document.getElementById('end_date')?.value || '';
    const reportType = document.getElementById('report_type')?.value || 'all';
    
    let url = 'export_pdf.php?';
    const params = new URLSearchParams();
    
    if (startDate) params.append('start_date', startDate);
    if (endDate) params.append('end_date', endDate);
    if (reportType) params.append('report_type', reportType);
    
    url += params.toString();
    window.open(url, '_blank');
}

// اختصارات التاريخ
document.addEventListener('DOMContentLoaded', function() {
    // إضافة أحداث للاختصارات
    const shortcuts = document.querySelectorAll('.date-shortcut');
    shortcuts.forEach(shortcut => {
        shortcut.addEventListener('click', function() {
            const range = this.getAttribute('data-range');
            setDateRange(range);
        });
    });
    
    // إضافة أحداث أزرار التصدير
    const exportButtons = document.querySelectorAll('[onclick*="exportReport"]');
    exportButtons.forEach(button => {
        button.addEventListener('click', function(e) {
            // إضافة تأثير التحميل
            this.disabled = true;
            this.innerHTML = '<i class="fas fa-spinner fa-spin"></i> جاري التصدير...';
            
            // إعادة تفعيل الزر بعد 3 ثوانٍ
            setTimeout(() => {
                this.disabled = false;
                this.innerHTML = this.getAttribute('data-original-text') || 'تصدير';
            }, 3000);
        });
    });
});

// تعيين نطاق التاريخ
function setDateRange(range) {
    const startDateInput = document.getElementById('start_date');
    const endDateInput = document.getElementById('end_date');
    
    if (!startDateInput || !endDateInput) return;
    
    const today = new Date();
    let startDate, endDate;
    
    switch(range) {
        case 'today':
            startDate = endDate = formatDate(today);
            break;
            
        case 'yesterday':
            const yesterday = new Date(today);
            yesterday.setDate(today.getDate() - 1);
            startDate = endDate = formatDate(yesterday);
            break;
            
        case 'this_week':
            const thisWeekStart = new Date(today);
            thisWeekStart.setDate(today.getDate() - today.getDay());
            startDate = formatDate(thisWeekStart);
            endDate = formatDate(today);
            break;
            
        case 'last_week':
            const lastWeekEnd = new Date(today);
            lastWeekEnd.setDate(today.getDate() - today.getDay() - 1);
            const lastWeekStart = new Date(lastWeekEnd);
            lastWeekStart.setDate(lastWeekEnd.getDate() - 6);
            startDate = formatDate(lastWeekStart);
            endDate = formatDate(lastWeekEnd);
            break;
            
        case 'this_month':
            startDate = formatDate(new Date(today.getFullYear(), today.getMonth(), 1));
            endDate = formatDate(new Date(today.getFullYear(), today.getMonth() + 1, 0));
            break;
            
        case 'last_month':
            const lastMonth = new Date(today.getFullYear(), today.getMonth() - 1, 1);
            startDate = formatDate(lastMonth);
            endDate = formatDate(new Date(today.getFullYear(), today.getMonth(), 0));
            break;
            
        case 'this_year':
            startDate = formatDate(new Date(today.getFullYear(), 0, 1));
            endDate = formatDate(today);
            break;
    }
    
    if (startDate && endDate) {
        startDateInput.value = startDate;
        endDateInput.value = endDate;
        
        // تطبيق التصفية تلقائياً
        const form = startDateInput.closest('form');
        if (form) {
            form.submit();
        }
    }
}

// تنسيق التاريخ
function formatDate(date) {
    const year = date.getFullYear();
    const month = String(date.getMonth() + 1).padStart(2, '0');
    const day = String(date.getDate()).padStart(2, '0');
    return `${year}-${month}-${day}`;
}

// التحقق من صحة التواريخ
function validateDateRange() {
    const startDate = document.getElementById('start_date')?.value;
    const endDate = document.getElementById('end_date')?.value;
    
    if (startDate && endDate && startDate > endDate) {
        alert('تاريخ البداية يجب أن يكون أقل من أو يساوي تاريخ النهاية');
        return false;
    }
    return true;
}

// معاينة التقرير قبل التصدير
function previewReport(type) {
    if (!validateDateRange()) return;
    
    const startDate = document.getElementById('start_date')?.value || '';
    const endDate = document.getElementById('end_date')?.value || '';
    
    let url = `report.php?report_type=${type}`;
    if (startDate) url += `&start_date=${startDate}`;
    if (endDate) url += `&end_date=${endDate}`;
    
    window.open(url, '_blank');
}

// تحديث الإحصائيات في الوقت الفعلي
function refreshStats() {
    const refreshButton = document.getElementById('refresh-stats');
    if (refreshButton) {
        refreshButton.disabled = true;
        refreshButton.innerHTML = '<i class="fas fa-spinner fa-spin"></i> جاري التحديث...';
        
        // إعادة تحميل الصفحة
        setTimeout(() => {
            location.reload();
        }, 1000);
    }
}

// طباعة مخصصة للتقارير
function printReport() {
    // إخفاء العناصر غير المطلوبة للطباعة
    const noPrintElements = document.querySelectorAll('.no-print');
    noPrintElements.forEach(element => {
        element.style.display = 'none';
    });
    
    // طباعة
    window.print();
    
    // إعادة إظهار العناصر
    noPrintElements.forEach(element => {
        element.style.display = '';
    });
}

// تحسين عرض الجداول على الأجهزة المحمولة
function initializeTableResponsive() {
    const tables = document.querySelectorAll('.table-responsive table');
    tables.forEach(table => {
        if (window.innerWidth < 768) {
            // إضافة شريط التمرير الأفقي للجداول
            table.style.minWidth = '600px';
        }
    });
}

// تفعيل التبويبات
function initializeTabs() {
    const tabs = document.querySelectorAll('[data-toggle="tab"]');
    tabs.forEach(tab => {
        tab.addEventListener('click', function(e) {
            e.preventDefault();
            
            // إزالة الفئة النشطة من جميع التبويبات
            const allTabs = document.querySelectorAll('[data-toggle="tab"]');
            const allPanes = document.querySelectorAll('.tab-pane');
            
            allTabs.forEach(t => t.classList.remove('active'));
            allPanes.forEach(p => {
                p.classList.remove('show', 'active');
            });
            
            // تفعيل التبويب المحدد
            this.classList.add('active');
            const target = this.getAttribute('href');
            const targetPane = document.querySelector(target);
            if (targetPane) {
                targetPane.classList.add('show', 'active');
            }
        });
    });
}

// تشغيل الدوال عند تحميل الصفحة
document.addEventListener('DOMContentLoaded', function() {
    initializeTableResponsive();
    initializeTabs();
    
    // إضافة معالج لتغيير حجم النافذة
    window.addEventListener('resize', initializeTableResponsive);
    
    // التحقق من صحة النماذج
    const forms = document.querySelectorAll('form[method="GET"]');
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            if (!validateDateRange()) {
                e.preventDefault();
            }
        });
    });
});