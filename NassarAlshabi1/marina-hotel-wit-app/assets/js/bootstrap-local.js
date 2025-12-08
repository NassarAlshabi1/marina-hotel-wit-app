/**
 * Bootstrap 5.3.0 JavaScript Bundle - نسخة محلية مبسطة
 * تحتوي على الوظائف الأساسية المطلوبة للنظام
 */

(function() {
    'use strict';

    // إعدادات Bootstrap الأساسية
    const BOOTSTRAP_VERSION = '5.3.0';
    
    // وظائف المساعدة
    const Util = {
        // العثور على عنصر بواسطة المحدد
        getElement: (selector) => {
            if (typeof selector === 'string') {
                return document.querySelector(selector);
            }
            return selector;
        },

        // العثور على جميع العناصر
        getElements: (selector) => {
            return document.querySelectorAll(selector);
        },

        // إضافة مستمع حدث
        on: (element, event, handler) => {
            if (element && element.addEventListener) {
                element.addEventListener(event, handler);
            }
        },

        // إزالة مستمع حدث
        off: (element, event, handler) => {
            if (element && element.removeEventListener) {
                element.removeEventListener(event, handler);
            }
        },

        // إضافة كلاس
        addClass: (element, className) => {
            if (element && element.classList) {
                element.classList.add(className);
            }
        },

        // إزالة كلاس
        removeClass: (element, className) => {
            if (element && element.classList) {
                element.classList.remove(className);
            }
        },

        // تبديل كلاس
        toggleClass: (element, className) => {
            if (element && element.classList) {
                element.classList.toggle(className);
            }
        },

        // فحص وجود كلاس
        hasClass: (element, className) => {
            if (element && element.classList) {
                return element.classList.contains(className);
            }
            return false;
        }
    };

    // مكون شريط التنقل (Navbar)
    class Navbar {
        constructor(element) {
            this.element = Util.getElement(element);
            this.init();
        }

        init() {
            if (!this.element) return;

            const toggler = this.element.querySelector('.navbar-toggler');
            const collapse = this.element.querySelector('.navbar-collapse');

            if (toggler && collapse) {
                Util.on(toggler, 'click', () => {
                    Util.toggleClass(collapse, 'show');
                    
                    // تحديث aria-expanded
                    const expanded = Util.hasClass(collapse, 'show');
                    toggler.setAttribute('aria-expanded', expanded);
                });
            }
        }

        static init() {
            const navbars = Util.getElements('.navbar');
            navbars.forEach(navbar => new Navbar(navbar));
        }
    }

    // مكون القائمة المنسدلة (Dropdown)
    class Dropdown {
        constructor(element) {
            this.element = Util.getElement(element);
            this.toggle = this.element.querySelector('.dropdown-toggle');
            this.menu = this.element.querySelector('.dropdown-menu');
            this.isOpen = false;
            this.init();
        }

        init() {
            if (!this.toggle || !this.menu) return;

            // النقر على الزر
            Util.on(this.toggle, 'click', (e) => {
                e.preventDefault();
                this.toggleDropdown();
            });

            // إغلاق عند النقر خارج القائمة
            Util.on(document, 'click', (e) => {
                if (!this.element.contains(e.target) && this.isOpen) {
                    this.hideDropdown();
                }
            });

            // إغلاق عند الضغط على Escape
            Util.on(document, 'keydown', (e) => {
                if (e.key === 'Escape' && this.isOpen) {
                    this.hideDropdown();
                }
            });
        }

        toggleDropdown() {
            if (this.isOpen) {
                this.hideDropdown();
            } else {
                this.showDropdown();
            }
        }

        showDropdown() {
            Util.addClass(this.menu, 'show');
            this.toggle.setAttribute('aria-expanded', 'true');
            this.isOpen = true;
        }

        hideDropdown() {
            Util.removeClass(this.menu, 'show');
            this.toggle.setAttribute('aria-expanded', 'false');
            this.isOpen = false;
        }

        static init() {
            const dropdowns = Util.getElements('.dropdown');
            dropdowns.forEach(dropdown => new Dropdown(dropdown));
        }
    }

    // مكون النافذة المنبثقة (Modal)
    class Modal {
        constructor(element, options = {}) {
            this.element = Util.getElement(element);
            this.options = { ...Modal.defaults, ...options };
            this.isOpen = false;
            this.init();
        }

        static get defaults() {
            return {
                backdrop: true,
                keyboard: true,
                focus: true
            };
        }

        init() {
            if (!this.element) return;

            // إنشاء الخلفية
            this.createBackdrop();

            // أزرار الإغلاق
            const closeBtns = this.element.querySelectorAll('[data-bs-dismiss="modal"]');
            closeBtns.forEach(btn => {
                Util.on(btn, 'click', () => this.hide());
            });

            // إغلاق بالضغط على Escape
            if (this.options.keyboard) {
                Util.on(document, 'keydown', (e) => {
                    if (e.key === 'Escape' && this.isOpen) {
                        this.hide();
                    }
                });
            }
        }

        createBackdrop() {
            this.backdrop = document.createElement('div');
            this.backdrop.className = 'modal-backdrop fade';
            
            if (this.options.backdrop) {
                Util.on(this.backdrop, 'click', () => this.hide());
            }
        }

        show() {
            if (this.isOpen) return;

            // إضافة الخلفية
            document.body.appendChild(this.backdrop);
            document.body.style.overflow = 'hidden';

            // إظهار المودال
            Util.addClass(this.element, 'show');
            this.element.style.display = 'block';
            this.element.setAttribute('aria-hidden', 'false');

            // إضافة الكلاسات بعد تأخير قصير للانتقال السلس
            setTimeout(() => {
                Util.addClass(this.backdrop, 'show');
            }, 10);

            this.isOpen = true;

            // التركيز على المودال
            if (this.options.focus) {
                this.element.focus();
            }
        }

        hide() {
            if (!this.isOpen) return;

            // إزالة الكلاسات
            Util.removeClass(this.element, 'show');
            Util.removeClass(this.backdrop, 'show');

            // إخفاء المودال بعد انتهاء الانتقال
            setTimeout(() => {
                this.element.style.display = 'none';
                this.element.setAttribute('aria-hidden', 'true');
                
                if (this.backdrop.parentNode) {
                    document.body.removeChild(this.backdrop);
                }
                
                document.body.style.overflow = '';
            }, 300);

            this.isOpen = false;
        }

        static init() {
            const modals = Util.getElements('.modal');
            modals.forEach(modal => new Modal(modal));

            // أزرار فتح المودال
            const triggers = Util.getElements('[data-bs-toggle="modal"]');
            triggers.forEach(trigger => {
                Util.on(trigger, 'click', (e) => {
                    e.preventDefault();
                    const target = trigger.getAttribute('data-bs-target');
                    const modal = Util.getElement(target);
                    if (modal && modal._bsModal) {
                        modal._bsModal.show();
                    }
                });
            });
        }
    }

    // مكون التنبيه (Alert)
    class Alert {
        constructor(element) {
            this.element = Util.getElement(element);
            this.init();
        }

        init() {
            if (!this.element) return;

            const closeBtn = this.element.querySelector('[data-bs-dismiss="alert"]');
            if (closeBtn) {
                Util.on(closeBtn, 'click', () => this.close());
            }
        }

        close() {
            Util.addClass(this.element, 'fade');
            
            setTimeout(() => {
                if (this.element.parentNode) {
                    this.element.parentNode.removeChild(this.element);
                }
            }, 150);
        }

        static init() {
            const alerts = Util.getElements('.alert');
            alerts.forEach(alert => new Alert(alert));
        }
    }

    // مكون التبويب (Tab)
    class Tab {
        constructor(element) {
            this.element = Util.getElement(element);
            this.init();
        }

        init() {
            if (!this.element) return;

            const tabs = this.element.querySelectorAll('[data-bs-toggle="tab"]');
            tabs.forEach(tab => {
                Util.on(tab, 'click', (e) => {
                    e.preventDefault();
                    this.showTab(tab);
                });
            });
        }

        showTab(activeTab) {
            const target = activeTab.getAttribute('data-bs-target') || 
                          activeTab.getAttribute('href');
            
            if (!target) return;

            // إزالة الكلاس النشط من جميع التبويبات
            const allTabs = this.element.querySelectorAll('[data-bs-toggle="tab"]');
            const allPanes = document.querySelectorAll('.tab-pane');

            allTabs.forEach(tab => {
                Util.removeClass(tab, 'active');
                tab.setAttribute('aria-selected', 'false');
            });

            allPanes.forEach(pane => {
                Util.removeClass(pane, 'show');
                Util.removeClass(pane, 'active');
            });

            // تفعيل التبويب المحدد
            Util.addClass(activeTab, 'active');
            activeTab.setAttribute('aria-selected', 'true');

            // إظهار المحتوى المطابق
            const targetPane = Util.getElement(target);
            if (targetPane) {
                Util.addClass(targetPane, 'show');
                Util.addClass(targetPane, 'active');
            }
        }

        static init() {
            const tabContainers = Util.getElements('.nav-tabs, .nav-pills');
            tabContainers.forEach(container => new Tab(container));
        }
    }

    // مكون التلميح (Tooltip) - نسخة مبسطة
    class Tooltip {
        constructor(element, options = {}) {
            this.element = Util.getElement(element);
            this.options = { ...Tooltip.defaults, ...options };
            this.tooltip = null;
            this.init();
        }

        static get defaults() {
            return {
                placement: 'top',
                trigger: 'hover',
                delay: 0
            };
        }

        init() {
            if (!this.element) return;

            if (this.options.trigger === 'hover') {
                Util.on(this.element, 'mouseenter', () => this.show());
                Util.on(this.element, 'mouseleave', () => this.hide());
            } else if (this.options.trigger === 'click') {
                Util.on(this.element, 'click', () => this.toggle());
            }
        }

        show() {
            if (this.tooltip) return;

            const title = this.element.getAttribute('title') || 
                         this.element.getAttribute('data-bs-original-title');
            
            if (!title) return;

            this.tooltip = document.createElement('div');
            this.tooltip.className = `tooltip bs-tooltip-${this.options.placement}`;
            this.tooltip.innerHTML = `
                <div class="tooltip-arrow"></div>
                <div class="tooltip-inner">${title}</div>
            `;

            document.body.appendChild(this.tooltip);
            this.positionTooltip();

            setTimeout(() => {
                Util.addClass(this.tooltip, 'show');
            }, 10);
        }

        hide() {
            if (!this.tooltip) return;

            Util.removeClass(this.tooltip, 'show');
            
            setTimeout(() => {
                if (this.tooltip && this.tooltip.parentNode) {
                    document.body.removeChild(this.tooltip);
                    this.tooltip = null;
                }
            }, 150);
        }

        toggle() {
            if (this.tooltip) {
                this.hide();
            } else {
                this.show();
            }
        }

        positionTooltip() {
            if (!this.tooltip) return;

            const rect = this.element.getBoundingClientRect();
            const tooltipRect = this.tooltip.getBoundingClientRect();

            let top, left;

            switch (this.options.placement) {
                case 'top':
                    top = rect.top - tooltipRect.height - 5;
                    left = rect.left + (rect.width - tooltipRect.width) / 2;
                    break;
                case 'bottom':
                    top = rect.bottom + 5;
                    left = rect.left + (rect.width - tooltipRect.width) / 2;
                    break;
                case 'left':
                    top = rect.top + (rect.height - tooltipRect.height) / 2;
                    left = rect.left - tooltipRect.width - 5;
                    break;
                case 'right':
                    top = rect.top + (rect.height - tooltipRect.height) / 2;
                    left = rect.right + 5;
                    break;
            }

            this.tooltip.style.top = top + window.scrollY + 'px';
            this.tooltip.style.left = left + window.scrollX + 'px';
        }

        static init() {
            const tooltips = Util.getElements('[data-bs-toggle="tooltip"]');
            tooltips.forEach(tooltip => new Tooltip(tooltip));
        }
    }

    // مكون الإنهيار (Collapse)
    class Collapse {
        constructor(element, options = {}) {
            this.element = Util.getElement(element);
            this.options = { ...Collapse.defaults, ...options };
            this.isOpen = Util.hasClass(this.element, 'show');
            this.init();
        }

        static get defaults() {
            return {
                toggle: true
            };
        }

        init() {
            if (!this.element) return;

            // العثور على المحفزات
            const triggers = Util.getElements(`[data-bs-target="#${this.element.id}"], [href="#${this.element.id}"]`);
            
            triggers.forEach(trigger => {
                Util.on(trigger, 'click', (e) => {
                    e.preventDefault();
                    this.toggle();
                });
            });
        }

        toggle() {
            if (this.isOpen) {
                this.hide();
            } else {
                this.show();
            }
        }

        show() {
            if (this.isOpen) return;

            this.element.style.height = '0px';
            Util.addClass(this.element, 'collapsing');
            Util.removeClass(this.element, 'collapse');

            const height = this.element.scrollHeight;
            this.element.style.height = height + 'px';

            setTimeout(() => {
                Util.removeClass(this.element, 'collapsing');
                Util.addClass(this.element, 'collapse');
                Util.addClass(this.element, 'show');
                this.element.style.height = '';
            }, 350);

            this.isOpen = true;
        }

        hide() {
            if (!this.isOpen) return;

            this.element.style.height = this.element.scrollHeight + 'px';
            
            setTimeout(() => {
                Util.addClass(this.element, 'collapsing');
                Util.removeClass(this.element, 'collapse');
                Util.removeClass(this.element, 'show');
                this.element.style.height = '0px';
            }, 10);

            setTimeout(() => {
                Util.removeClass(this.element, 'collapsing');
                Util.addClass(this.element, 'collapse');
                this.element.style.height = '';
            }, 350);

            this.isOpen = false;
        }

        static init() {
            const collapses = Util.getElements('.collapse');
            collapses.forEach(collapse => new Collapse(collapse));
        }
    }

    // تهيئة جميع المكونات عند تحميل الصفحة
    const initBootstrap = () => {
        Navbar.init();
        Dropdown.init();
        Modal.init();
        Alert.init();
        Tab.init();
        Tooltip.init();
        Collapse.init();
    };

    // تحقق من حالة تحميل الصفحة
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initBootstrap);
    } else {
        initBootstrap();
    }

    // تصدير المكونات للاستخدام العام
    window.Bootstrap = {
        Navbar,
        Dropdown,
        Modal,
        Alert,
        Tab,
        Tooltip,
        Collapse,
        Util
    };

})();

// دوال مساعدة إضافية للنظام
(function() {
    'use strict';

    // وظائف خاصة بالنظام
    window.HotelSystem = {
        // إظهار رسالة Toast
        showToast: function(message, type = 'info') {
            const toast = document.createElement('div');
            toast.className = `alert alert-${type} alert-dismissible fade show position-fixed`;
            toast.style.cssText = 'top: 20px; right: 20px; z-index: 9999; min-width: 300px;';
            toast.innerHTML = `
                ${message}
                <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
            `;
            
            document.body.appendChild(toast);
            
            // إزالة تلقائية بعد 5 ثوانٍ
            setTimeout(() => {
                if (toast.parentNode) {
                    toast.parentNode.removeChild(toast);
                }
            }, 5000);
        },

        // تأكيد الحذف
        confirmDelete: function(message = 'هل أنت متأكد من الحذف؟') {
            return confirm(message);
        },

        // تحديد جميع النصوص
        selectAllText: function(element) {
            if (element.select) {
                element.select();
            } else if (window.getSelection) {
                const range = document.createRange();
                range.selectNode(element);
                window.getSelection().removeAllRanges();
                window.getSelection().addRange(range);
            }
        },

        // نسخ النص للحافظة
        copyToClipboard: function(text) {
            if (navigator.clipboard) {
                navigator.clipboard.writeText(text).then(() => {
                    this.showToast('تم نسخ النص بنجاح', 'success');
                });
            } else {
                // طريقة بديلة للمتصفحات القديمة
                const textArea = document.createElement('textarea');
                textArea.value = text;
                document.body.appendChild(textArea);
                textArea.select();
                document.execCommand('copy');
                document.body.removeChild(textArea);
                this.showToast('تم نسخ النص بنجاح', 'success');
            }
        },

        // تنسيق الأرقام
        formatNumber: function(number) {
            return new Intl.NumberFormat('ar-SA').format(number);
        },

        // تنسيق التاريخ
        formatDate: function(date) {
            return new Intl.DateTimeFormat('ar-SA').format(new Date(date));
        }
    };

})();