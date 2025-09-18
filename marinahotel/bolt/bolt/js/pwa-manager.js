// Progressive Web App Manager
class PWAManager {
    constructor() {
        this.deferredPrompt = null;
        this.isInstalled = false;
        this.serviceWorkerRegistration = null;
        
        this.init();
    }

    init() {
        this.checkInstallation();
        this.setupServiceWorker();
        this.setupInstallPrompt();
        this.setupUpdatePrompt();
        this.setupPushNotifications();
    }

    checkInstallation() {
        // Check if app is installed
        if (window.matchMedia('(display-mode: standalone)').matches || 
            window.navigator.standalone === true) {
            this.isInstalled = true;
            document.body.classList.add('pwa-installed');
        }
    }

    async setupServiceWorker() {
        if ('serviceWorker' in navigator) {
            try {
                this.serviceWorkerRegistration = await navigator.serviceWorker.register('/sw.js');
                console.log('Service Worker registered successfully');
                
                // Listen for updates
                this.serviceWorkerRegistration.addEventListener('updatefound', () => {
                    this.handleServiceWorkerUpdate();
                });
            } catch (error) {
                console.error('Service Worker registration failed:', error);
            }
        }
    }

    setupInstallPrompt() {
        window.addEventListener('beforeinstallprompt', (e) => {
            e.preventDefault();
            this.deferredPrompt = e;
            this.showInstallButton();
        });

        window.addEventListener('appinstalled', () => {
            this.isInstalled = true;
            this.hideInstallButton();
            showNotification('تم تثبيت التطبيق بنجاح!');
        });
    }

    showInstallButton() {
        if (this.isInstalled) return;

        const installButton = document.createElement('button');
        installButton.id = 'installButton';
        installButton.className = 'fixed bottom-20 right-4 bg-blue-600 text-white px-4 py-2 rounded-lg shadow-lg z-50';
        installButton.innerHTML = `
            <i class="fas fa-download ml-2"></i>
            تثبيت التطبيق
        `;
        
        installButton.addEventListener('click', () => {
            this.promptInstall();
        });
        
        document.body.appendChild(installButton);
    }

    hideInstallButton() {
        const installButton = document.getElementById('installButton');
        if (installButton) {
            installButton.remove();
        }
    }

    async promptInstall() {
        if (!this.deferredPrompt) return;

        this.deferredPrompt.prompt();
        const { outcome } = await this.deferredPrompt.userChoice;
        
        if (outcome === 'accepted') {
            console.log('User accepted the install prompt');
        } else {
            console.log('User dismissed the install prompt');
        }
        
        this.deferredPrompt = null;
        this.hideInstallButton();
    }

    handleServiceWorkerUpdate() {
        const updateButton = document.createElement('div');
        updateButton.className = 'fixed top-4 left-4 right-4 bg-blue-600 text-white p-4 rounded-lg shadow-lg z-50';
        updateButton.innerHTML = `
            <div class="flex justify-between items-center">
                <div>
                    <div class="font-semibold">تحديث متاح</div>
                    <div class="text-sm opacity-90">إصدار جديد من التطبيق متاح</div>
                </div>
                <button class="bg-white text-blue-600 px-3 py-1 rounded text-sm font-semibold" onclick="this.parentElement.parentElement.remove(); location.reload();">
                    تحديث
                </button>
            </div>
        `;
        
        document.body.appendChild(updateButton);
        
        setTimeout(() => {
            if (document.body.contains(updateButton)) {
                updateButton.remove();
            }
        }, 10000);
    }

    async setupPushNotifications() {
        if (!('Notification' in window) || !('serviceWorker' in navigator)) {
            return;
        }

        // Request permission
        if (Notification.permission === 'default') {
            await this.requestNotificationPermission();
        }
    }

    async requestNotificationPermission() {
        const permission = await Notification.requestPermission();
        
        if (permission === 'granted') {
            showNotification('تم تفعيل الإشعارات بنجاح');
            this.setupPushSubscription();
        } else {
            showNotification('تم رفض الإشعارات', 'warning');
        }
    }

    async setupPushSubscription() {
        if (!this.serviceWorkerRegistration) return;

        try {
            const subscription = await this.serviceWorkerRegistration.pushManager.subscribe({
                userVisibleOnly: true,
                applicationServerKey: this.urlBase64ToUint8Array('YOUR_VAPID_PUBLIC_KEY') // Replace with actual key
            });
            
            // Send subscription to server
            await this.sendSubscriptionToServer(subscription);
        } catch (error) {
            console.error('Failed to subscribe to push notifications:', error);
        }
    }

    urlBase64ToUint8Array(base64String) {
        const padding = '='.repeat((4 - base64String.length % 4) % 4);
        const base64 = (base64String + padding)
            .replace(/-/g, '+')
            .replace(/_/g, '/');

        const rawData = window.atob(base64);
        const outputArray = new Uint8Array(rawData.length);

        for (let i = 0; i < rawData.length; ++i) {
            outputArray[i] = rawData.charCodeAt(i);
        }
        return outputArray;
    }

    async sendSubscriptionToServer(subscription) {
        // Send subscription to your server
        console.log('Push subscription:', subscription);
    }

    showNotification(title, body, options = {}) {
        if (Notification.permission === 'granted') {
            const notification = new Notification(title, {
                body,
                icon: '/icon-192x192.png',
                badge: '/icon-72x72.png',
                ...options
            });
            
            notification.onclick = () => {
                window.focus();
                notification.close();
            };
        }
    }

    // Share API
    async share(data) {
        if (navigator.share) {
            try {
                await navigator.share(data);
                return true;
            } catch (error) {
                console.error('Error sharing:', error);
                return false;
            }
        } else {
            // Fallback to clipboard
            if (navigator.clipboard && data.url) {
                await navigator.clipboard.writeText(data.url);
                showNotification('تم نسخ الرابط');
                return true;
            }
            return false;
        }
    }

    // Get app info
    getAppInfo() {
        return {
            isInstalled: this.isInstalled,
            isOnline: navigator.onLine,
            hasServiceWorker: !!this.serviceWorkerRegistration,
            notificationPermission: Notification.permission,
            canShare: !!navigator.share
        };
    }
}

// Initialize PWA manager
const pwaManager = new PWAManager();

// Export for global use
window.pwaManager = pwaManager;