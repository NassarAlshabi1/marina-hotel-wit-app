/*!
 * Dashboard JavaScript - Marina Hotel System
 * Enhanced dashboard functionality and user experience
 * Version: 2.0
 */

(function() {
    'use strict';

    // ===== Global Variables =====
    const MarinaHotel = {
        version: '2.0.0',
        debug: true,
        animations: {
            duration: 300,
            easing: 'ease-in-out'
        },
        cache: new Map(),
        events: new Map()
    };

    // ===== Utility Functions =====
    const Utils = {
        // Debounce function for performance
        debounce: function(func, wait) {
            let timeout;
            return function executedFunction(...args) {
                const later = () => {
                    clearTimeout(timeout);
                    func(...args);
                };
                clearTimeout(timeout);
                timeout = setTimeout(later, wait);
            };
        },

        // Throttle function for scroll events
        throttle: function(func, limit) {
            let inThrottle;
            return function() {
                const args = arguments;
                const context = this;
                if (!inThrottle) {
                    func.apply(context, args);
                    inThrottle = true;
                    setTimeout(() => inThrottle = false, limit);
                }
            };
        },

        // Format numbers with Arabic locale
        formatNumber: function(number, locale = 'ar-SA') {
            return new Intl.NumberFormat(locale).format(number);
        },

        // Format currency
        formatCurrency: function(amount, currency = 'SAR') {
            return new Intl.NumberFormat('ar-SA', {
                style: 'currency',
                currency: currency,
                minimumFractionDigits: 0
            }).format(amount);
        },

        // Get current time in Yemen timezone
        getCurrentTime: function() {
            return new Date().toLocaleString('ar-SA', {
                timeZone: 'Asia/Aden',
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit',
                second: '2-digit'
            });
        },

        // Show toast notification
        showToast: function(message, type = 'info', duration = 5000) {
            const toastContainer = document.querySelector('.toast-container') || 
                                 this.createToastContainer();
            
            const toastId = 'toast-' + Date.now();
            const iconClass = this.getIconForType(type);
            
            const toastHTML = `
                <div id="${toastId}" class="toast align-items-center text-bg-${type} border-0" role="alert" aria-live="assertive" aria-atomic="true">
                    <div class="d-flex">
                        <div class="toast-body">
                            <i class="${iconClass} me-2"></i>
                            ${message}
                        </div>
                        <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast" aria-label="إغلاق"></button>
                    </div>
                </div>
            `;

            toastContainer.insertAdjacentHTML('beforeend', toastHTML);
            const newToast = document.getElementById(toastId);
            
            if (window.bootstrap) {
                const bsToast = new bootstrap.Toast(newToast, { delay: duration });
                bsToast.show();
                
                newToast.addEventListener('hidden.bs.toast', function() {
                    this.remove();
                });
            } else {
                // Fallback for when Bootstrap is not available
                setTimeout(() => {
                    newToast.style.opacity = '1';
                    newToast.style.transform = 'translateX(0)';
                }, 100);
                
                setTimeout(() => {
                    newToast.style.opacity = '0';
                    newToast.style.transform = 'translateX(100%)';
                    setTimeout(() => newToast.remove(), 300);
                }, duration);
            }
        },

        createToastContainer: function() {
            const container = document.createElement('div');
            container.className = 'toast-container position-fixed top-0 end-0 p-3';
            container.style.zIndex = '9999';
            document.body.appendChild(container);
            return container;
        },

        getIconForType: function(type) {
            const icons = {
                success: 'fas fa-check-circle',
                danger: 'fas fa-exclamation-triangle',
                warning: 'fas fa-exclamation-triangle',
                info: 'fas fa-info-circle',
                primary: 'fas fa-info-circle'
            };
            return icons[type] || 'fas fa-info-circle';
        },

        // Animate elements on scroll
        animateOnScroll: function() {
            const elements = document.querySelectorAll('.animate-on-scroll');
            
            if ('IntersectionObserver' in window) {
                const observer = new IntersectionObserver((entries) => {
                    entries.forEach(entry => {
                        if (entry.isIntersecting) {
                            entry.target.classList.add('fade-in-up');
                            observer.unobserve(entry.target);
                        }
                    });
                }, {
                    threshold: 0.1,
                    rootMargin: '0px 0px -50px 0px'
                });

                elements.forEach(el => {
                    observer.observe(el);
                });
            } else {
                // Fallback for older browsers
                elements.forEach((el, index) => {
                    setTimeout(() => {
                        el.classList.add('fade-in-up');
                    }, index * 200);
                });
            }
        },

        // Add loading state to buttons
        addLoadingState: function(button, text = 'جارٍ التحميل...') {
            if (button.dataset.originalText === undefined) {
                button.dataset.originalText = button.innerHTML;
            }
            
            button.innerHTML = `
                <span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>
                ${text}
            `;
            button.disabled = true;
        },

        // Remove loading state from buttons
        removeLoadingState: function(button) {
            if (button.dataset.originalText) {
                button.innerHTML = button.dataset.originalText;
                button.disabled = false;
            }
        },

        // Validate form inputs
        validateForm: function(form) {
            const inputs = form.querySelectorAll('input[required], select[required], textarea[required]');
            let isValid = true;
            
            inputs.forEach(input => {
                if (!input.value.trim()) {
                    this.showFieldError(input, 'هذا الحقل مطلوب');
                    isValid = false;
                } else {
                    this.removeFieldError(input);
                }
            });
            
            return isValid;
        },

        showFieldError: function(input, message) {
            input.classList.add('is-invalid');
            
            let errorElement = input.nextElementSibling;
            if (!errorElement || !errorElement.classList.contains('invalid-feedback')) {
                errorElement = document.createElement('div');
                errorElement.className = 'invalid-feedback';
                input.parentNode.insertBefore(errorElement, input.nextSibling);
            }
            
            errorElement.textContent = message;
        },

        removeFieldError: function(input) {
            input.classList.remove('is-invalid');
            
            const errorElement = input.nextElementSibling;
            if (errorElement && errorElement.classList.contains('invalid-feedback')) {
                errorElement.remove();
            }
        }
    };

    // ===== Dashboard Controller =====
    const DashboardController = {
        init: function() {
            this.initializeStats();
            this.initializeRoomGrid();
            this.initializeCharts();
            this.initializeRealTimeUpdates();
            this.bindEvents();
            
            if (MarinaHotel.debug) {
                console.log('🏨 Dashboard initialized successfully');
            }
        },

        initializeStats: function() {
            const statCards = document.querySelectorAll('.stat-card');
            
            statCards.forEach((card, index) => {
                card.classList.add('animate-on-scroll');
                card.style.animationDelay = `${index * 0.1}s`;
                
                // Add counter animation
                const numberElement = card.querySelector('.stat-number');
                if (numberElement) {
                    const finalNumber = parseInt(numberElement.textContent.replace(/[^0-9]/g, ''));
                    if (finalNumber > 0) {
                        this.animateCounter(numberElement, 0, finalNumber, 2000);
                    }
                }
            });
        },

        animateCounter: function(element, start, end, duration) {
            const startTime = performance.now();
            const originalText = element.textContent;
            const suffix = originalText.replace(/[0-9,]/g, '');
            
            const animate = (currentTime) => {
                const elapsed = currentTime - startTime;
                const progress = Math.min(elapsed / duration, 1);
                
                // Easing function
                const easeOutQuart = 1 - Math.pow(1 - progress, 4);
                const current = Math.floor(start + (end - start) * easeOutQuart);
                
                element.textContent = Utils.formatNumber(current) + suffix;
                
                if (progress < 1) {
                    requestAnimationFrame(animate);
                }
            };
            
            requestAnimationFrame(animate);
        },

        initializeRoomGrid: function() {
            const roomCards = document.querySelectorAll('.room-card');
            
            roomCards.forEach((card, index) => {
                card.classList.add('animate-on-scroll');
                card.style.animationDelay = `${index * 0.05}s`;
                
                // Add click handler
                card.addEventListener('click', this.handleRoomClick.bind(this));
                
                // Add hover effects
                card.addEventListener('mouseenter', function() {
                    this.style.transform = 'translateY(-5px) scale(1.02)';
                });
                
                card.addEventListener('mouseleave', function() {
                    this.style.transform = 'translateY(0) scale(1)';
                });
            });
        },

        handleRoomClick: function(event) {
            const roomCard = event.currentTarget;
            const roomNumber = roomCard.dataset.roomNumber;
            const roomStatus = roomCard.dataset.roomStatus;
            
            if (roomStatus === 'available') {
                // Redirect to booking page
                window.location.href = `bookings/add.php?room_number=${roomNumber}`;
            } else if (roomStatus === 'occupied') {
                // Show room details
                this.showRoomDetails(roomNumber);
            }
        },

        showRoomDetails: function(roomNumber) {
            // This would typically fetch room details via AJAX
            Utils.showToast(`تم النقر على الغرفة ${roomNumber}`, 'info');
        },

        initializeCharts: function() {
            // Initialize charts if Chart.js is available
            if (typeof Chart !== 'undefined') {
                this.initializeRevenueChart();
                this.initializeOccupancyChart();
            }
        },

        initializeRevenueChart: function() {
            const ctx = document.getElementById('revenueChart');
            if (!ctx) return;
            
            // Sample data - this would come from the server
            const data = {
                labels: ['يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو'],
                datasets: [{
                    label: 'الإيرادات',
                    data: [12000, 19000, 15000, 25000, 22000, 30000],
                    backgroundColor: 'rgba(102, 126, 234, 0.2)',
                    borderColor: 'rgba(102, 126, 234, 1)',
                    borderWidth: 3,
                    fill: true,
                    tension: 0.4
                }]
            };
            
            new Chart(ctx, {
                type: 'line',
                data: data,
                options: {
                    responsive: true,
                    plugins: {
                        legend: {
                            display: false
                        }
                    },
                    scales: {
                        y: {
                            beginAtZero: true,
                            ticks: {
                                callback: function(value) {
                                    return Utils.formatCurrency(value);
                                }
                            }
                        }
                    }
                }
            });
        },

        initializeOccupancyChart: function() {
            const ctx = document.getElementById('occupancyChart');
            if (!ctx) return;
            
            const data = {
                labels: ['شاغرة', 'محجوزة', 'صيانة'],
                datasets: [{
                    data: [15, 10, 2],
                    backgroundColor: [
                        'rgba(40, 167, 69, 0.8)',
                        'rgba(220, 53, 69, 0.8)',
                        'rgba(255, 193, 7, 0.8)'
                    ],
                    borderColor: [
                        'rgba(40, 167, 69, 1)',
                        'rgba(220, 53, 69, 1)',
                        'rgba(255, 193, 7, 1)'
                    ],
                    borderWidth: 2
                }]
            };
            
            new Chart(ctx, {
                type: 'doughnut',
                data: data,
                options: {
                    responsive: true,
                    plugins: {
                        legend: {
                            position: 'bottom'
                        }
                    }
                }
            });
        },

        initializeRealTimeUpdates: function() {
            // Update dashboard every 5 minutes
            setInterval(() => {
                this.updateDashboardData();
            }, 5 * 60 * 1000);
        },

        updateDashboardData: function() {
            // This would fetch updated data from the server
            if (MarinaHotel.debug) {
                console.log('🔄 Updating dashboard data...');
            }
            
            // Example: Update time
            const timeElements = document.querySelectorAll('.current-time');
            timeElements.forEach(element => {
                element.textContent = Utils.getCurrentTime();
            });
        },

        bindEvents: function() {
            // Bind global events
            document.addEventListener('click', this.handleGlobalClick.bind(this));
            document.addEventListener('submit', this.handleFormSubmit.bind(this));
            window.addEventListener('scroll', Utils.throttle(this.handleScroll.bind(this), 100));
            
            // Initialize tooltips
            this.initializeTooltips();
        },

        handleGlobalClick: function(event) {
            const target = event.target;
            
            // Handle button clicks
            if (target.classList.contains('btn-loading')) {
                Utils.addLoadingState(target);
            }
            
            // Handle confirmation dialogs
            if (target.dataset.confirm) {
                if (!confirm(target.dataset.confirm)) {
                    event.preventDefault();
                }
            }
        },

        handleFormSubmit: function(event) {
            const form = event.target;
            
            if (form.classList.contains('validate-form')) {
                if (!Utils.validateForm(form)) {
                    event.preventDefault();
                    Utils.showToast('يرجى تصحيح الأخطاء في النموذج', 'danger');
                }
            }
        },

        handleScroll: function() {
            const scrollTop = window.pageYOffset || document.documentElement.scrollTop;
            
            // Add shadow to navbar on scroll
            const navbar = document.querySelector('.navbar');
            if (navbar) {
                if (scrollTop > 0) {
                    navbar.classList.add('navbar-scrolled');
                } else {
                    navbar.classList.remove('navbar-scrolled');
                }
            }
        },

        initializeTooltips: function() {
            if (typeof bootstrap !== 'undefined') {
                const tooltipTriggerList = document.querySelectorAll('[data-bs-toggle="tooltip"]');
                const tooltipList = [...tooltipTriggerList].map(tooltipTriggerEl => 
                    new bootstrap.Tooltip(tooltipTriggerEl)
                );
            }
        }
    };

    // ===== Form Enhancement =====
    const FormEnhancer = {
        init: function() {
            this.enhanceFormInputs();
            this.setupValidation();
            this.setupAutoComplete();
        },

        enhanceFormInputs: function() {
            const inputs = document.querySelectorAll('.form-control, .form-select');
            
            inputs.forEach(input => {
                // Add floating label effect
                input.addEventListener('focus', function() {
                    this.parentElement.classList.add('focused');
                });
                
                input.addEventListener('blur', function() {
                    this.parentElement.classList.remove('focused');
                });
                
                // Format number inputs
                if (input.type === 'number' || input.classList.contains('number-input')) {
                    input.addEventListener('input', function() {
                        const value = this.value.replace(/[^0-9.]/g, '');
                        if (value !== this.value) {
                            this.value = value;
                        }
                    });
                }
                
                // Format phone inputs
                if (input.type === 'tel' || input.classList.contains('phone-input')) {
                    input.addEventListener('input', function() {
                        let value = this.value.replace(/[^0-9+]/g, '');
                        // Format Yemeni numbers
                        if (value.startsWith('7') && value.length <= 9) {
                            value = value.replace(/(\d{3})(\d{3})(\d{3})/, '$1 $2 $3');
                        }
                        this.value = value;
                    });
                }
            });
        },

        setupValidation: function() {
            const forms = document.querySelectorAll('form');
            
            forms.forEach(form => {
                const inputs = form.querySelectorAll('input, select, textarea');
                
                inputs.forEach(input => {
                    input.addEventListener('input', () => {
                        this.validateField(input);
                    });
                    
                    input.addEventListener('blur', () => {
                        this.validateField(input);
                    });
                });
            });
        },

        validateField: function(field) {
            const value = field.value.trim();
            const type = field.type;
            const required = field.hasAttribute('required');
            
            // Clear previous validation
            field.classList.remove('is-valid', 'is-invalid');
            
            if (required && !value) {
                this.showFieldError(field, 'هذا الحقل مطلوب');
                return false;
            }
            
            if (value) {
                switch (type) {
                    case 'email':
                        if (!this.validateEmail(value)) {
                            this.showFieldError(field, 'البريد الإلكتروني غير صحيح');
                            return false;
                        }
                        break;
                    case 'tel':
                        if (!this.validatePhone(value)) {
                            this.showFieldError(field, 'رقم الهاتف غير صحيح');
                            return false;
                        }
                        break;
                    case 'number':
                        if (isNaN(value) || value < 0) {
                            this.showFieldError(field, 'يجب أن يكون رقمًا صحيحًا');
                            return false;
                        }
                        break;
                }
            }
            
            // Show success state
            field.classList.add('is-valid');
            this.removeFieldError(field);
            return true;
        },

        validateEmail: function(email) {
            const re = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
            return re.test(email);
        },

        validatePhone: function(phone) {
            const cleanPhone = phone.replace(/[^0-9]/g, '');
            const patterns = [
                /^967[7][0-9]{8}$/,  // +967 7XXXXXXXX
                /^[7][0-9]{8}$/,     // 7XXXXXXXX
                /^00967[7][0-9]{8}$/ // 00967 7XXXXXXXX
            ];
            return patterns.some(pattern => pattern.test(cleanPhone));
        },

        showFieldError: function(field, message) {
            field.classList.add('is-invalid');
            Utils.showFieldError(field, message);
        },

        removeFieldError: function(field) {
            field.classList.remove('is-invalid');
            Utils.removeFieldError(field);
        },

        setupAutoComplete: function() {
            // Auto-complete for common fields
            const dateInputs = document.querySelectorAll('input[type="date"]');
            dateInputs.forEach(input => {
                if (!input.value && input.name.includes('checkin')) {
                    input.value = new Date().toISOString().split('T')[0];
                }
            });
        }
    };

    // ===== Performance Monitor =====
    const PerformanceMonitor = {
        init: function() {
            this.monitorPageLoad();
            this.optimizeImages();
            this.setupLazyLoading();
        },

        monitorPageLoad: function() {
            if (MarinaHotel.debug) {
                window.addEventListener('load', () => {
                    const loadTime = performance.now();
                    console.log(`📊 Page loaded in ${loadTime.toFixed(2)}ms`);
                });
            }
        },

        optimizeImages: function() {
            const images = document.querySelectorAll('img');
            
            images.forEach(img => {
                if (!img.getAttribute('loading')) {
                    img.setAttribute('loading', 'lazy');
                }
            });
        },

        setupLazyLoading: function() {
            if ('IntersectionObserver' in window) {
                const lazyImages = document.querySelectorAll('img[data-src]');
                
                const imageObserver = new IntersectionObserver((entries) => {
                    entries.forEach(entry => {
                        if (entry.isIntersecting) {
                            const img = entry.target;
                            img.src = img.dataset.src;
                            img.removeAttribute('data-src');
                            imageObserver.unobserve(img);
                        }
                    });
                });
                
                lazyImages.forEach(img => imageObserver.observe(img));
            }
        }
    };

    // ===== Application Initialization =====
    const App = {
        init: function() {
            // Wait for DOM to be ready
            if (document.readyState === 'loading') {
                document.addEventListener('DOMContentLoaded', () => this.initializeApp());
            } else {
                this.initializeApp();
            }
        },

        initializeApp: function() {
            console.log('🚀 Initializing Marina Hotel Dashboard...');
            
            try {
                // Initialize all modules
                DashboardController.init();
                FormEnhancer.init();
                PerformanceMonitor.init();
                
                // Setup animations
                Utils.animateOnScroll();
                
                // Setup global error handler
                this.setupErrorHandler();
                
                // Mark app as initialized
                document.body.classList.add('app-initialized');
                
                console.log('✅ Marina Hotel Dashboard initialized successfully!');
                
            } catch (error) {
                console.error('❌ Error initializing dashboard:', error);
                Utils.showToast('حدث خطأ في تهيئة النظام', 'danger');
            }
        },

        setupErrorHandler: function() {
            window.addEventListener('error', (event) => {
                console.error('Global error:', event.error);
                
                if (MarinaHotel.debug) {
                    Utils.showToast('حدث خطأ في التطبيق', 'danger');
                }
            });
        }
    };

    // ===== Export to global scope =====
    window.MarinaHotel = {
        ...MarinaHotel,
        Utils,
        DashboardController,
        FormEnhancer,
        PerformanceMonitor
    };

    // ===== Initialize Application =====
    App.init();

})();