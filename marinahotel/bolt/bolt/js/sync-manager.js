// Synchronization Manager for Cross-Device Data Sync
class SyncManager {
    constructor() {
        this.syncEndpoint = '/api/sync';
        this.deviceId = this.generateDeviceId();
        this.lastSyncTime = localStorage.getItem('lastSyncTime') || 0;
        this.pendingChanges = JSON.parse(localStorage.getItem('pendingChanges') || '[]');
        this.syncInterval = null;
        this.isOnline = navigator.onLine;
        
        this.init();
    }

    init() {
        this.setupEventListeners();
        this.startPeriodicSync();
        
        // Initial sync if online
        if (this.isOnline) {
            this.performSync();
        }
    }

    generateDeviceId() {
        let deviceId = localStorage.getItem('deviceId');
        if (!deviceId) {
            deviceId = 'device_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
            localStorage.setItem('deviceId', deviceId);
        }
        return deviceId;
    }

    setupEventListeners() {
        // Online/Offline events
        window.addEventListener('online', () => {
            this.isOnline = true;
            this.performSync();
            showNotification('تم الاتصال بالإنترنت - جاري المزامنة...');
        });

        window.addEventListener('offline', () => {
            this.isOnline = false;
            showNotification('انقطع الاتصال بالإنترنت - سيتم الحفظ محلياً', 'warning');
        });

        // Page visibility change
        document.addEventListener('visibilitychange', () => {
            if (!document.hidden && this.isOnline) {
                this.performSync();
            }
        });

        // Before unload
        window.addEventListener('beforeunload', () => {
            if (this.pendingChanges.length > 0) {
                this.savePendingChanges();
            }
        });
    }

    startPeriodicSync() {
        // Sync every 30 seconds when online
        this.syncInterval = setInterval(() => {
            if (this.isOnline && this.pendingChanges.length > 0) {
                this.performSync();
            }
        }, 30000);
    }

    stopPeriodicSync() {
        if (this.syncInterval) {
            clearInterval(this.syncInterval);
            this.syncInterval = null;
        }
    }

    // Add change to pending queue
    addChange(table, operation, data, id = null) {
        const change = {
            id: Date.now() + '_' + Math.random().toString(36).substr(2, 9),
            table,
            operation, // 'create', 'update', 'delete'
            data,
            recordId: id,
            timestamp: new Date().toISOString(),
            deviceId: this.deviceId,
            synced: false
        };

        this.pendingChanges.push(change);
        this.savePendingChanges();

        // Try to sync immediately if online
        if (this.isOnline) {
            this.performSync();
        }

        return change.id;
    }

    savePendingChanges() {
        localStorage.setItem('pendingChanges', JSON.stringify(this.pendingChanges));
    }

    async performSync() {
        if (!this.isOnline || this.pendingChanges.length === 0) {
            return;
        }

        try {
            // Send pending changes to server
            const response = await this.sendChangesToServer();
            
            if (response.success) {
                // Mark changes as synced
                this.pendingChanges = this.pendingChanges.filter(change => !change.synced);
                this.savePendingChanges();
                
                // Get updates from server
                await this.getUpdatesFromServer();
                
                this.lastSyncTime = Date.now();
                localStorage.setItem('lastSyncTime', this.lastSyncTime.toString());
                
                this.showSyncStatus('success', 'تم تحديث البيانات بنجاح');
            }
        } catch (error) {
            console.error('Sync failed:', error);
            this.showSyncStatus('error', 'فشل في مزامنة البيانات');
        }
    }

    async sendChangesToServer() {
        // Simulate API call - replace with actual Supabase sync
        return new Promise((resolve) => {
            setTimeout(() => {
                // Mark all pending changes as synced
                this.pendingChanges.forEach(change => {
                    change.synced = true;
                });
                
                resolve({ success: true });
            }, 1000);
        });
    }

    async getUpdatesFromServer() {
        // Simulate getting updates from server
        return new Promise((resolve) => {
            setTimeout(() => {
                // Here you would fetch updates from server
                // and apply them to local data
                resolve({ updates: [] });
            }, 500);
        });
    }

    showSyncStatus(type, message) {
        const indicator = document.createElement('div');
        indicator.className = `fixed top-4 right-4 p-3 rounded-lg text-white text-sm z-50 ${
            type === 'success' ? 'bg-green-500' : 
            type === 'error' ? 'bg-red-500' : 'bg-blue-500'
        }`;
        indicator.innerHTML = `
            <div class="flex items-center">
                <i class="fas fa-sync-alt ${type === 'success' ? '' : 'fa-spin'} ml-2"></i>
                ${message}
            </div>
        `;
        
        document.body.appendChild(indicator);
        
        setTimeout(() => {
            indicator.style.opacity = '0';
            setTimeout(() => {
                if (document.body.contains(indicator)) {
                    document.body.removeChild(indicator);
                }
            }, 300);
        }, 3000);
    }

    // Public methods for data operations
    syncCreate(table, data) {
        return this.addChange(table, 'create', data);
    }

    syncUpdate(table, id, data) {
        return this.addChange(table, 'update', data, id);
    }

    syncDelete(table, id) {
        return this.addChange(table, 'delete', null, id);
    }

    // Force sync
    forcSync() {
        if (this.isOnline) {
            this.performSync();
        } else {
            showNotification('لا يوجد اتصال بالإنترنت', 'error');
        }
    }

    // Get sync status
    getSyncStatus() {
        return {
            isOnline: this.isOnline,
            pendingChanges: this.pendingChanges.length,
            lastSyncTime: this.lastSyncTime,
            deviceId: this.deviceId
        };
    }

    // Clear all pending changes (use with caution)
    clearPendingChanges() {
        this.pendingChanges = [];
        this.savePendingChanges();
    }

    // Export data for backup
    exportSyncData() {
        return {
            deviceId: this.deviceId,
            pendingChanges: this.pendingChanges,
            lastSyncTime: this.lastSyncTime,
            exportTime: new Date().toISOString()
        };
    }

    // Import data from backup
    importSyncData(syncData) {
        if (syncData.deviceId && syncData.pendingChanges) {
            this.pendingChanges = [...this.pendingChanges, ...syncData.pendingChanges];
            this.savePendingChanges();
            
            if (this.isOnline) {
                this.performSync();
            }
            
            return true;
        }
        return false;
    }
}

// Initialize sync manager
const syncManager = new SyncManager();

// Export for global use
window.syncManager = syncManager;