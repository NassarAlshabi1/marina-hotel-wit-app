// Mobile Adaptation and Responsive Behavior
class MobileAdapter {
    constructor() {
        this.isMobile = this.detectMobile();
        this.isTablet = this.detectTablet();
        this.isTouch = this.detectTouch();
        this.orientation = this.getOrientation();
        
        this.init();
        this.setupEventListeners();
    }

    detectMobile() {
        return window.innerWidth <= 768 || /Android|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini/i.test(navigator.userAgent);
    }

    detectTablet() {
        return window.innerWidth >= 768 && window.innerWidth <= 1024;
    }

    detectTouch() {
        return 'ontouchstart' in window || navigator.maxTouchPoints > 0;
    }

    getOrientation() {
        return window.innerHeight > window.innerWidth ? 'portrait' : 'landscape';
    }

    init() {
        this.setupViewport();
        this.setupMobileNavigation();
        this.setupTouchOptimizations();
        this.setupOfflineDetection();
        this.setupPullToRefresh();
        
        if (this.isMobile) {
            document.body.classList.add('mobile-device');
            this.adaptForMobile();
        }
        
        if (this.isTablet) {
            document.body.classList.add('tablet-device');
        }
        
        if (this.isTouch) {
            document.body.classList.add('touch-device');
        }
    }

    setupViewport() {
        // Ensure proper viewport settings
        let viewport = document.querySelector('meta[name="viewport"]');
        if (!viewport) {
            viewport = document.createElement('meta');
            viewport.name = 'viewport';
            document.head.appendChild(viewport);
        }
        viewport.content = 'width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover';
    }

    setupMobileNavigation() {
        if (!this.isMobile) return;

        // Create mobile header
        const mobileHeader = document.createElement('div');
        mobileHeader.className = 'mobile-header';
        mobileHeader.innerHTML = `
            <div class="mobile-header-content">
                <button class="mobile-menu-btn" id="mobileMenuBtn">
                    <i class="fas fa-bars"></i>
                </button>
                <div class="mobile-title" id="mobileTitle">لوحة التحكم</div>
                <div class="mobile-user-info">
                    <i class="fas fa-user-circle"></i>
                </div>
            </div>
        `;
        document.body.insertBefore(mobileHeader, document.body.firstChild);

        // Create mobile navigation
        const mobileNav = document.createElement('div');
        mobileNav.className = 'mobile-nav';
        mobileNav.innerHTML = `
            <div class="mobile-nav-items">
                <a href="#" class="mobile-nav-item active" data-section="dashboard">
                    <i class="fas fa-tachometer-alt"></i>
                    <span>الرئيسية</span>
                </a>
                <a href="#" class="mobile-nav-item" data-section="rooms">
                    <i class="fas fa-bed"></i>
                    <span>الغرف</span>
                </a>
                <a href="#" class="mobile-nav-item" data-section="bookings">
                    <i class="fas fa-calendar-check"></i>
                    <span>الحجوزات</span>
                </a>
                <a href="#" class="mobile-nav-item" data-section="payments">
                    <i class="fas fa-credit-card"></i>
                    <span>المدفوعات</span>
                </a>
                <a href="#" class="mobile-nav-item" data-section="reports">
                    <i class="fas fa-chart-bar"></i>
                    <span>التقارير</span>
                </a>
            </div>
        `;
        document.body.appendChild(mobileNav);

        // Setup mobile navigation events
        this.setupMobileNavEvents();
    }

    setupMobileNavEvents() {
        // Mobile navigation clicks
        document.querySelectorAll('.mobile-nav-item').forEach(item => {
            item.addEventListener('click', (e) => {
                e.preventDefault();
                const section = item.dataset.section;
                
                // Update active state
                document.querySelectorAll('.mobile-nav-item').forEach(nav => nav.classList.remove('active'));
                item.classList.add('active');
                
                // Update title
                const titles = {
                    dashboard: 'لوحة التحكم',
                    rooms: 'إدارة الغرف',
                    bookings: 'الحجوزات',
                    payments: 'المدفوعات',
                    reports: 'التقارير'
                };
                document.getElementById('mobileTitle').textContent = titles[section];
                
                // Show section
                showSection(section);
            });
        });

        // Mobile menu button
        document.getElementById('mobileMenuBtn')?.addEventListener('click', () => {
            this.showMobileMenu();
        });
    }

    showMobileMenu() {
        const menuItems = [
            { icon: 'fas fa-receipt', text: 'المصروفات', section: 'expenses' },
            { icon: 'fas fa-users', text: 'الموظفين', section: 'employees' },
            { icon: 'fas fa-cog', text: 'الإعدادات', section: 'settings' },
            { icon: 'fas fa-sign-out-alt', text: 'تسجيل الخروج', action: 'logout' }
        ];

        const menuHTML = menuItems.map(item => `
            <div class="mobile-menu-item" data-section="${item.section}" data-action="${item.action}">
                <i class="${item.icon}"></i>
                <span>${item.text}</span>
            </div>
        `).join('');

        const modal = document.createElement('div');
        modal.className = 'fixed inset-0 bg-black bg-opacity-50 flex items-end justify-center z-50';
        modal.innerHTML = `
            <div class="bg-white w-full max-w-md rounded-t-xl p-6 animate-slide-up">
                <div class="flex justify-between items-center mb-4">
                    <h3 class="text-lg font-semibold">القائمة</h3>
                    <button class="mobile-menu-close text-gray-500">
                        <i class="fas fa-times"></i>
                    </button>
                </div>
                <div class="space-y-2">
                    ${menuHTML}
                </div>
            </div>
        `;

        document.body.appendChild(modal);

        // Handle menu item clicks
        modal.querySelectorAll('.mobile-menu-item').forEach(item => {
            item.addEventListener('click', () => {
                const section = item.dataset.section;
                const action = item.dataset.action;
                
                if (action === 'logout') {
                    logout();
                } else if (section) {
                    showSection(section);
                    document.getElementById('mobileTitle').textContent = item.querySelector('span').textContent;
                }
                
                document.body.removeChild(modal);
            });
        });

        // Close menu
        modal.querySelector('.mobile-menu-close').addEventListener('click', () => {
            document.body.removeChild(modal);
        });

        modal.addEventListener('click', (e) => {
            if (e.target === modal) {
                document.body.removeChild(modal);
            }
        });
    }

    adaptForMobile() {
        // Adapt content area
        const mainContent = document.querySelector('.lg\\:mr-64');
        if (mainContent) {
            mainContent.className = 'mobile-content';
        }

        // Adapt sections
        document.querySelectorAll('[id$="Section"]').forEach(section => {
            section.classList.add('mobile-section');
        });

        // Adapt room grid
        const roomsGrid = document.getElementById('roomsGrid');
        if (roomsGrid) {
            roomsGrid.className = 'grid room-grid-mobile';
        }

        // Adapt tables
        this.adaptTablesForMobile();

        // Adapt forms
        this.adaptFormsForMobile();

        // Adapt charts
        this.adaptChartsForMobile();
    }

    adaptTablesForMobile() {
        document.querySelectorAll('table').forEach(table => {
            const container = document.createElement('div');
            container.className = 'mobile-table-container';
            table.parentNode.insertBefore(container, table);
            container.appendChild(table);
            table.classList.add('mobile-table');
        });
    }

    adaptFormsForMobile() {
        document.querySelectorAll('form').forEach(form => {
            form.classList.add('mobile-form');
        });

        // Prevent zoom on input focus (iOS)
        document.querySelectorAll('input, select, textarea').forEach(input => {
            if (input.type !== 'file') {
                input.style.fontSize = '16px';
            }
        });
    }

    adaptChartsForMobile() {
        // Charts will be handled by Chart.js responsive options
        document.querySelectorAll('canvas').forEach(canvas => {
            canvas.style.maxWidth = '100%';
            canvas.style.height = 'auto';
        });
    }

    setupTouchOptimizations() {
        if (!this.isTouch) return;

        // Add touch feedback
        document.addEventListener('touchstart', (e) => {
            if (e.target.matches('button, .btn, .nav-item, .mobile-nav-item, .room-card')) {
                e.target.style.opacity = '0.7';
            }
        });

        document.addEventListener('touchend', (e) => {
            if (e.target.matches('button, .btn, .nav-item, .mobile-nav-item, .room-card')) {
                setTimeout(() => {
                    e.target.style.opacity = '';
                }, 150);
            }
        });

        // Prevent double-tap zoom
        let lastTouchEnd = 0;
        document.addEventListener('touchend', (e) => {
            const now = (new Date()).getTime();
            if (now - lastTouchEnd <= 300) {
                e.preventDefault();
            }
            lastTouchEnd = now;
        }, false);
    }

    setupOfflineDetection() {
        const offlineIndicator = document.createElement('div');
        offlineIndicator.className = 'offline-indicator';
        offlineIndicator.textContent = 'لا يوجد اتصال بالإنترنت';
        document.body.appendChild(offlineIndicator);

        const updateOnlineStatus = () => {
            if (navigator.onLine) {
                offlineIndicator.classList.remove('show');
            } else {
                offlineIndicator.classList.add('show');
            }
        };

        window.addEventListener('online', updateOnlineStatus);
        window.addEventListener('offline', updateOnlineStatus);
        updateOnlineStatus();
    }

    setupPullToRefresh() {
        if (!this.isMobile) return;

        let startY = 0;
        let currentY = 0;
        let pulling = false;

        const pullIndicator = document.createElement('div');
        pullIndicator.className = 'pull-indicator';
        pullIndicator.innerHTML = '<i class="fas fa-sync-alt"></i>';
        document.body.appendChild(pullIndicator);

        document.addEventListener('touchstart', (e) => {
            if (window.scrollY === 0) {
                startY = e.touches[0].pageY;
                pulling = true;
            }
        });

        document.addEventListener('touchmove', (e) => {
            if (!pulling) return;

            currentY = e.touches[0].pageY;
            const diff = currentY - startY;

            if (diff > 0 && diff < 100) {
                e.preventDefault();
                pullIndicator.style.top = `${diff - 60}px`;
                
                if (diff > 60) {
                    pullIndicator.classList.add('active');
                }
            }
        });

        document.addEventListener('touchend', () => {
            if (pulling && pullIndicator.classList.contains('active')) {
                // Trigger refresh
                this.refreshData();
            }
            
            pulling = false;
            pullIndicator.classList.remove('active');
            pullIndicator.style.top = '-60px';
        });
    }

    refreshData() {
        showNotification('جاري تحديث البيانات...');
        
        // Simulate refresh
        setTimeout(() => {
            // Reload current section data
            const currentSection = document.querySelector('[id$="Section"]:not(.hidden)');
            if (currentSection) {
                const sectionName = currentSection.id.replace('Section', '');
                loadSectionContent(sectionName);
            }
            showNotification('تم تحديث البيانات بنجاح');
        }, 1000);
    }

    setupEventListeners() {
        // Orientation change
        window.addEventListener('orientationchange', () => {
            setTimeout(() => {
                this.orientation = this.getOrientation();
                this.handleOrientationChange();
            }, 100);
        });

        // Resize
        window.addEventListener('resize', () => {
            this.isMobile = this.detectMobile();
            this.isTablet = this.detectTablet();
            this.handleResize();
        });

        // Keyboard events for mobile
        if (this.isMobile) {
            this.setupMobileKeyboardHandling();
        }
    }

    handleOrientationChange() {
        // Adjust layout for orientation
        document.body.classList.toggle('landscape', this.orientation === 'landscape');
        document.body.classList.toggle('portrait', this.orientation === 'portrait');
    }

    handleResize() {
        // Update mobile/tablet classes
        document.body.classList.toggle('mobile-device', this.isMobile);
        document.body.classList.toggle('tablet-device', this.isTablet);
    }

    setupMobileKeyboardHandling() {
        // Handle virtual keyboard
        let initialViewportHeight = window.innerHeight;

        window.addEventListener('resize', () => {
            const currentHeight = window.innerHeight;
            const heightDiff = initialViewportHeight - currentHeight;

            if (heightDiff > 150) {
                // Keyboard is likely open
                document.body.classList.add('keyboard-open');
            } else {
                // Keyboard is likely closed
                document.body.classList.remove('keyboard-open');
            }
        });

        // Scroll to input when focused
        document.addEventListener('focusin', (e) => {
            if (e.target.matches('input, textarea, select')) {
                setTimeout(() => {
                    e.target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                }, 300);
            }
        });
    }

    // Public methods for external use
    showMobileNotification(message, type = 'info') {
        const notification = document.createElement('div');
        notification.className = `fixed top-4 left-4 right-4 p-4 rounded-lg text-white z-50 ${
            type === 'success' ? 'bg-green-500' : 
            type === 'error' ? 'bg-red-500' : 
            type === 'warning' ? 'bg-yellow-500' : 'bg-blue-500'
        }`;
        notification.textContent = message;
        
        document.body.appendChild(notification);
        
        setTimeout(() => {
            notification.style.opacity = '0';
            setTimeout(() => {
                document.body.removeChild(notification);
            }, 300);
        }, 3000);
    }

    vibrate(pattern = [100]) {
        if ('vibrate' in navigator) {
            navigator.vibrate(pattern);
        }
    }

    isOnline() {
        return navigator.onLine;
    }

    getConnectionType() {
        if ('connection' in navigator) {
            return navigator.connection.effectiveType;
        }
        return 'unknown';
    }
}

// Initialize mobile adapter
const mobileAdapter = new MobileAdapter();

// Export for global use
window.mobileAdapter = mobileAdapter;