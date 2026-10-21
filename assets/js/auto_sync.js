/**
 * نظام المزامنة التلقائية - جانب العميل
 * Auto Sync System - Client Side
 * يعمل كل دقيقتين (120 ثانية)
 */

class AutoSync {
    constructor() {
        this.syncInterval = 120000; // دقيقتان بالميلي ثانية
        this.isOnline = navigator.onLine;
        this.lastSyncTime = null;
        this.syncTimer = null;
        this.retryCount = 0;
        this.maxRetries = 3;
        
        this.init();
    }
    
    init() {
        // بدء المزامنة التلقائية
        this.startAutoSync();
        
        // مراقبة حالة الاتصال بالإنترنت
        this.setupNetworkMonitoring();
        
        // مزامنة عند تحميل الصفحة
        this.syncNow();
        
        // إضافة مؤشر حالة المزامنة
        this.createSyncIndicator();
        
        console.log('🔄 تم تفعيل نظام المزامنة التلقائية - كل دقيقتين');
    }
    
    startAutoSync() {
        if (this.syncTimer) {
            clearInterval(this.syncTimer);
        }
        
        this.syncTimer = setInterval(() => {
            if (this.isOnline) {
                this.syncNow();
            }
        }, this.syncInterval);
    }
    
    async syncNow() {
        if (!this.isOnline) {
            this.updateSyncIndicator('offline', 'غير متصل');
            return;
        }
        
        try {
            this.updateSyncIndicator('syncing', 'جاري المزامنة...');
            
            // إرسال طلب المزامنة
            const response = await fetch('sync_cron.php?manual_run=1', {
                method: 'GET',
                headers: {
                    'X-Requested-With': 'XMLHttpRequest'
                }
            });
            
            if (response.ok) {
                this.lastSyncTime = new Date();
                this.retryCount = 0;
                this.updateSyncIndicator('success', 'تمت المزامنة');
                
                // إرسال إشعار للخادم بالبيانات الجديدة
                this.sendLocalChangesToServer();
                
                console.log('✅ تمت المزامنة بنجاح:', this.lastSyncTime.toLocaleTimeString('ar-SA'));
            } else {
                throw new Error('فشل في الاتصال بالخادم');
            }
            
        } catch (error) {
            this.handleSyncError(error);
        }
    }
    
    async sendLocalChangesToServer() {
        // جمع البيانات المحلية المعلقة (إذا كانت موجودة)
        const pendingData = this.getPendingLocalData();
        
        if (pendingData.length > 0) {
            try {
                const response = await fetch('api/sync.php', {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json',
                        'X-Requested-With': 'XMLHttpRequest'
                    },
                    body: JSON.stringify({
                        action: 'sync_local_data',
                        data: pendingData
                    })
                });
                
                if (response.ok) {
                    // مسح البيانات المحلية بعد المزامنة الناجحة
                    this.clearPendingLocalData();
                }
            } catch (error) {
                console.warn('تحذير: فشل في إرسال البيانات المحلية:', error.message);
            }
        }
    }
    
    getPendingLocalData() {
        // الحصول على البيانات المعلقة من localStorage
        const pending = localStorage.getItem('pendingSyncData');
        return pending ? JSON.parse(pending) : [];
    }
    
    clearPendingLocalData() {
        localStorage.removeItem('pendingSyncData');
    }
    
    addPendingData(type, data) {
        // إضافة بيانات جديدة للمزامنة المعلقة
        const pending = this.getPendingLocalData();
        pending.push({
            type: type,
            data: data,
            timestamp: new Date().toISOString()
        });
        localStorage.setItem('pendingSyncData', JSON.stringify(pending));
    }
    
    handleSyncError(error) {
        this.retryCount++;
        console.error(`❌ خطأ في المزامنة (المحاولة ${this.retryCount}):`, error.message);
        
        if (this.retryCount < this.maxRetries) {
            this.updateSyncIndicator('error', `خطأ - إعادة المحاولة ${this.retryCount}/${this.maxRetries}`);
            
            // إعادة المحاولة بعد 30 ثانية
            setTimeout(() => {
                this.syncNow();
            }, 30000);
        } else {
            this.updateSyncIndicator('failed', 'فشل في المزامنة');
            this.retryCount = 0; // إعادة تعيين العداد للمحاولة التالية
        }
    }
    
    setupNetworkMonitoring() {
        window.addEventListener('online', () => {
            this.isOnline = true;
            console.log('🌐 تم الاتصال بالإنترنت - استئناف المزامنة');
            this.syncNow();
        });
        
        window.addEventListener('offline', () => {
            this.isOnline = false;
            console.log('📴 انقطع الاتصال بالإنترنت - توقف المزامنة');
            this.updateSyncIndicator('offline', 'غير متصل');
        });
    }
    
    createSyncIndicator() {
        // إنشاء مؤشر حالة المزامنة
        const indicator = document.createElement('div');
        indicator.id = 'sync-indicator';
        indicator.style.cssText = `
            position: fixed;
            top: 80px;
            right: 20px;
            background: #fff;
            border: 1px solid #ddd;
            border-radius: 5px;
            padding: 8px 12px;
            font-size: 12px;
            box-shadow: 0 2px 5px rgba(0,0,0,0.1);
            z-index: 1000;
            transition: all 0.3s ease;
            min-width: 120px;
            text-align: center;
        `;
        
        document.body.appendChild(indicator);
        this.updateSyncIndicator('ready', 'جاهز للمزامنة');
    }
    
    updateSyncIndicator(status, message) {
        const indicator = document.getElementById('sync-indicator');
        if (!indicator) return;
        
        const colors = {
            ready: '#28a745',
            syncing: '#007bff',
            success: '#28a745',
            error: '#ffc107',
            failed: '#dc3545',
            offline: '#6c757d'
        };
        
        const icons = {
            ready: '⏳',
            syncing: '🔄',
            success: '✅',
            error: '⚠️',
            failed: '❌',
            offline: '📴'
        };
        
        indicator.style.borderColor = colors[status] || '#ddd';
        indicator.style.color = colors[status] || '#333';
        indicator.innerHTML = `${icons[status] || '🔄'} ${message}`;
        
        // إخفاء المؤشر بعد 5 ثوانٍ للحالات الناجحة
        if (status === 'success') {
            setTimeout(() => {
                if (indicator) {
                    indicator.style.opacity = '0.5';
                }
            }, 5000);
        } else {
            indicator.style.opacity = '1';
        }
    }
    
    // دالة لإضافة بيانات جديدة للمزامنة (للاستخدام من الصفحات الأخرى)
    static addToSync(type, data) {
        if (window.autoSyncInstance) {
            window.autoSyncInstance.addPendingData(type, data);
        }
    }
    
    // دالة لتشغيل مزامنة فورية (للاستخدام من الصفحات الأخرى)
    static syncNow() {
        if (window.autoSyncInstance) {
            window.autoSyncInstance.syncNow();
        }
    }
}

// تشغيل النظام عند تحميل الصفحة
document.addEventListener('DOMContentLoaded', function() {
    // التأكد من أن النظام يعمل في صفحات الإدارة فقط
    if (window.location.pathname.includes('/admin/') || window.location.pathname.includes('admin')) {
        window.autoSyncInstance = new AutoSync();
        
        // إضافة دوال عامة للوصول السهل
        window.addToSync = AutoSync.addToSync;
        window.syncNow = AutoSync.syncNow;
    }
});

// تصدير الكلاس للاستخدام في ملفات أخرى
if (typeof module !== 'undefined' && module.exports) {
    module.exports = AutoSync;
}
