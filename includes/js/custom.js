/*!
 * Marina Hotel - Custom JavaScript
 * Payment System Premium Features
 * Version: 2.0
 * Author: Marina Hotel Development Team
 */

(function() {
  'use strict';

  // ===== Global Variables =====
  let isLoaded = false;
  let animations = [];
  let intersectionObserver = null;

  // ===== Utility Functions =====
  const Utils = {
    // Debounce function
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

    // Throttle function
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

    // Format number with Arabic locale
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

    // Validate Arabic phone number
    validateYemeniPhone: function(phone) {
      const cleanPhone = phone.replace(/[^0-9]/g, '');
      const patterns = [
        /^967[7][0-9]{8}$/,  // +967 7XXXXXXXX
        /^[7][0-9]{8}$/,     // 7XXXXXXXX
        /^00967[7][0-9]{8}$/ // 00967 7XXXXXXXX
      ];
      return patterns.some(pattern => pattern.test(cleanPhone));
    },

    // Generate random ID
    generateId: function() {
      return 'marina_' + Math.random().toString(36).substr(2, 9);
    },

    // Get element offset
    getOffset: function(element) {
      const rect = element.getBoundingClientRect();
      return {
        top: rect.top + window.pageYOffset,
        left: rect.left + window.pageXOffset,
        width: rect.width,
        height: rect.height
      };
    }
  };

  // ===== Animation System =====
  const AnimationController = {
    init: function() {
      this.setupIntersectionObserver();
      this.initializeAnimations();
    },

    setupIntersectionObserver: function() {
      if (!window.IntersectionObserver) return;

      intersectionObserver = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            this.animateElement(entry.target);
            intersectionObserver.unobserve(entry.target);
          }
        });
      }, {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
      });
    },

    initializeAnimations: function() {
      // Animate cards
      document.querySelectorAll('.card').forEach((card, index) => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(30px)';
        card.setAttribute('data-animation', 'fadeInUp');
        card.setAttribute('data-delay', index * 100);
        
        if (intersectionObserver) {
          intersectionObserver.observe(card);
        } else {
          setTimeout(() => this.animateElement(card), index * 100);
        }
      });

      // Animate summary items
      document.querySelectorAll('.summary-item').forEach((item, index) => {
        item.style.opacity = '0';
        item.style.transform = 'scale(0.8)';
        item.setAttribute('data-animation', 'scaleIn');
        item.setAttribute('data-delay', index * 150);
        
        if (intersectionObserver) {
          intersectionObserver.observe(item);
        } else {
          setTimeout(() => this.animateElement(item), index * 150);
        }
      });
    },

    animateElement: function(element) {
      const animation = element.getAttribute('data-animation');
      const delay = parseInt(element.getAttribute('data-delay')) || 0;

      setTimeout(() => {
        switch (animation) {
          case 'fadeInUp':
            element.style.transition = 'all 0.6s cubic-bezier(0.4, 0, 0.2, 1)';
            element.style.opacity = '1';
            element.style.transform = 'translateY(0)';
            break;
          case 'scaleIn':
            element.style.transition = 'all 0.5s cubic-bezier(0.68, -0.55, 0.265, 1.55)';
            element.style.opacity = '1';
            element.style.transform = 'scale(1)';
            break;
          case 'slideInRight':
            element.style.transition = 'all 0.6s ease-out';
            element.style.opacity = '1';
            element.style.transform = 'translateX(0)';
            break;
        }
      }, delay);
    }
  };

  // ===== Form Enhancement =====
  const FormHandler = {
    init: function() {
      this.enhanceFormInputs();
      this.setupValidation();
      this.setupAutoComplete();
    },

    enhanceFormInputs: function() {
      // Add floating labels effect
      document.querySelectorAll('.form-control, .form-select').forEach(input => {
        // Focus effects
        input.addEventListener('focus', function() {
          this.parentElement.classList.add('focused');
          if (this.parentElement.querySelector('.form-label')) {
            this.parentElement.querySelector('.form-label').style.transform = 'translateY(-8px) scale(0.85)';
          }
        });

        input.addEventListener('blur', function() {
          this.parentElement.classList.remove('focused');
          if (!this.value && this.parentElement.querySelector('.form-label')) {
            this.parentElement.querySelector('.form-label').style.transform = 'translateY(0) scale(1)';
          }
        });

        // Auto-format numbers
        if (input.type === 'number' || input.classList.contains('number-input')) {
          input.addEventListener('input', function() {
            const value = this.value.replace(/[^0-9.]/g, '');
            if (value !== this.value) {
              this.value = value;
            }
          });
        }

        // Phone number formatting
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
      // Enhanced amount validation
      const amountInput = document.getElementById('amount');
      if (amountInput) {
        amountInput.addEventListener('input', Utils.debounce(function() {
          const value = parseFloat(this.value);
          const max = parseFloat(this.getAttribute('max'));
          const min = parseFloat(this.getAttribute('min')) || 0;

          // Clear previous validation
          this.classList.remove('is-valid', 'is-invalid');
          
          if (isNaN(value) || value <= min) {
            this.classList.add('is-invalid');
            this.setCustomValidity('المبلغ يجب أن يكون أكبر من ' + min);
            FormHandler.showValidationMessage(this, 'error', 'المبلغ يجب أن يكون أكبر من ' + min);
          } else if (value > max) {
            this.classList.add('is-invalid');
            this.setCustomValidity('المبلغ لا يمكن أن يتجاوز ' + Utils.formatNumber(max) + ' ريال');
            FormHandler.showValidationMessage(this, 'error', 'المبلغ لا يمكن أن يتجاوز ' + Utils.formatNumber(max) + ' ريال');
          } else {
            this.classList.add('is-valid');
            this.setCustomValidity('');
            FormHandler.showValidationMessage(this, 'success', 'المبلغ صحيح ✓');
          }
        }, 300));
      }

      // Date validation
      const dateInput = document.getElementById('payment_date');
      if (dateInput) {
        dateInput.addEventListener('change', function() {
          const selectedDate = new Date(this.value);
          const now = new Date();
          const maxDate = new Date(now.getTime() + (24 * 60 * 60 * 1000)); // Tomorrow

          this.classList.remove('is-valid', 'is-invalid');

          if (selectedDate > maxDate) {
            this.classList.add('is-invalid');
            FormHandler.showValidationMessage(this, 'error', 'لا يمكن اختيار تاريخ مستقبلي');
          } else {
            this.classList.add('is-valid');
            FormHandler.hideValidationMessage(this);
          }
        });
      }
    },

    setupAutoComplete: function() {
      // Auto-update payment date
      const dateInput = document.getElementById('payment_date');
      if (dateInput && !dateInput.value) {
        this.updatePaymentDateTime();
        
        // Update every minute
        setInterval(() => {
          if (document.activeElement !== dateInput) {
            this.updatePaymentDateTime();
          }
        }, 60000);
      }
    },

    updatePaymentDateTime: function() {
      const dateInput = document.getElementById('payment_date');
      if (dateInput && !dateInput.value) {
        const now = new Date();
        const localDateTime = now.toISOString().slice(0, 16);
        dateInput.value = localDateTime;
      }
    },

    showValidationMessage: function(input, type, message) {
      let messageElement = input.parentElement.querySelector('.validation-message');
      
      if (!messageElement) {
        messageElement = document.createElement('div');
        messageElement.className = 'validation-message small mt-1';
        input.parentElement.appendChild(messageElement);
      }

      messageElement.className = `validation-message small mt-1 text-${type === 'error' ? 'danger' : 'success'}`;
      messageElement.textContent = message;
      messageElement.style.opacity = '0';
      messageElement.style.transform = 'translateY(-10px)';
      
      setTimeout(() => {
        messageElement.style.transition = 'all 0.3s ease';
        messageElement.style.opacity = '1';
        messageElement.style.transform = 'translateY(0)';
      }, 10);
    },

    hideValidationMessage: function(input) {
      const messageElement = input.parentElement.querySelector('.validation-message');
      if (messageElement) {
        messageElement.style.opacity = '0';
        setTimeout(() => messageElement.remove(), 300);
      }
    }
  };

  // ===== Interactive Effects =====
  const InteractiveEffects = {
    init: function() {
      this.setupHoverEffects();
      this.setupClickEffects();
      this.setupProgressRing();
      this.setupCounterAnimations();
    },

    setupHoverEffects: function() {
      // Button hover effects
      document.querySelectorAll('.btn').forEach(btn => {
        btn.addEventListener('mouseenter', function() {
          this.style.transform = 'translateY(-2px) scale(1.02)';
        });

        btn.addEventListener('mouseleave', function() {
          this.style.transform = 'translateY(0) scale(1)';
        });

        btn.addEventListener('mousedown', function() {
          this.style.transform = 'translateY(0) scale(0.98)';
        });

        btn.addEventListener('mouseup', function() {
          this.style.transform = 'translateY(-2px) scale(1.02)';
        });
      });

      // Card hover effects
      document.querySelectorAll('.card').forEach(card => {
        card.addEventListener('mouseenter', function() {
          this.style.transform = 'translateY(-5px)';
          this.style.boxShadow = '0 20px 45px rgba(0, 0, 0, 0.15)';
        });

        card.addEventListener('mouseleave', function() {
          this.style.transform = 'translateY(0)';
          this.style.boxShadow = '0 15px 35px rgba(0, 0, 0, 0.1)';
        });
      });
    },

    setupClickEffects: function() {
      // Summary items click effect
      document.querySelectorAll('.summary-item').forEach(item => {
        item.addEventListener('click', function() {
          // Create ripple effect
          const ripple = document.createElement('div');
          ripple.className = 'ripple-effect';
          ripple.style.cssText = `
            position: absolute;
            border-radius: 50%;
            background: rgba(255, 255, 255, 0.6);
            transform: scale(0);
            animation: rippleAnimation 0.6s linear;
            pointer-events: none;
          `;

          const rect = this.getBoundingClientRect();
          const size = Math.max(rect.width, rect.height);
          ripple.style.width = ripple.style.height = size + 'px';
          ripple.style.left = (event.clientX - rect.left - size / 2) + 'px';
          ripple.style.top = (event.clientY - rect.top - size / 2) + 'px';

          this.style.position = 'relative';
          this.appendChild(ripple);

          setTimeout(() => ripple.remove(), 600);
        });
      });
    },

    setupProgressRing: function() {
      const progressRing = document.querySelector('.progress-ring .progress');
      if (progressRing) {
        const progress = progressRing.style.getPropertyValue('--progress') || '0';
        const circumference = 2 * Math.PI * 25; // radius = 25
        
        progressRing.style.strokeDasharray = circumference;
        progressRing.style.strokeDashoffset = circumference;

        // Animate progress
        setTimeout(() => {
          const offset = circumference - (parseInt(progress) / 100) * circumference;
          progressRing.style.strokeDashoffset = offset;
        }, 500);
      }
    },

    setupCounterAnimations: function() {
      document.querySelectorAll('.summary-item h3').forEach(counter => {
        const target = parseInt(counter.textContent.replace(/[^0-9]/g, ''));
        if (target > 0) {
          let current = 0;
          const increment = target / 60; // 1 second animation at 60fps
          const timer = setInterval(() => {
            current += increment;
            if (current >= target) {
              current = target;
              clearInterval(timer);
            }
            counter.textContent = Utils.formatNumber(Math.floor(current)) + ' ريال';
          }, 16);
        }
      });
    }
  };

  // ===== Toast Notifications =====
  const NotificationSystem = {
    init: function() {
      this.setupToasts();
    },

    setupToasts: function() {
      const toastElement = document.getElementById('flashToast');
      if (toastElement && window.bootstrap) {
        const toast = new bootstrap.Toast(toastElement, {
          delay: 5000,
          autohide: true
        });
        
        // Enhanced toast with sound effect (optional)
        toastElement.addEventListener('shown.bs.toast', function() {
          // You can add sound effect here if needed
          console.log('Toast shown with enhanced animation');
        });

        toast.show();
      }
    },

    showCustomToast: function(message, type = 'info', duration = 5000) {
      const toastContainer = document.querySelector('.toast-container') || this.createToastContainer();
      
      const toastHTML = `
        <div class="toast align-items-center text-bg-${type} border-0" role="alert">
          <div class="d-flex">
            <div class="toast-body">
              <i class="fas fa-${this.getIconForType(type)} me-2"></i>
              ${message}
            </div>
            <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
          </div>
        </div>
      `;

      toastContainer.insertAdjacentHTML('beforeend', toastHTML);
      const newToast = toastContainer.lastElementChild;
      
      if (window.bootstrap) {
        const toast = new bootstrap.Toast(newToast, { delay: duration });
        toast.show();
        
        newToast.addEventListener('hidden.bs.toast', function() {
          this.remove();
        });
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
        success: 'check-circle',
        danger: 'exclamation-triangle',
        warning: 'exclamation-triangle',
        info: 'info-circle',
        primary: 'info-circle'
      };
      return icons[type] || 'info-circle';
    }
  };

  // ===== Performance Optimization =====
  const PerformanceOptimizer = {
    init: function() {
      this.lazyLoadImages();
      this.optimizeAnimations();
      this.setupPrefetch();
    },

    lazyLoadImages: function() {
      if ('IntersectionObserver' in window) {
        const images = document.querySelectorAll('img[data-src]');
        const imageObserver = new IntersectionObserver((entries, observer) => {
          entries.forEach(entry => {
            if (entry.isIntersecting) {
              const img = entry.target;
              img.src = img.dataset.src;
              img.classList.remove('lazy');
              observer.unobserve(img);
            }
          });
        });

        images.forEach(img => imageObserver.observe(img));
      }
    },

    optimizeAnimations: function() {
      // Reduce animations on low-end devices
      if (navigator.hardwareConcurrency && navigator.hardwareConcurrency <= 4) {
        document.documentElement.style.setProperty('--animation-duration', '0.3s');
      }

      // Pause animations when tab is not visible
      document.addEventListener('visibilitychange', function() {
        const animations = document.querySelectorAll('[style*="animation"]');
        animations.forEach(el => {
          if (document.hidden) {
            el.style.animationPlayState = 'paused';
          } else {
            el.style.animationPlayState = 'running';
          }
        });
      });
    },

    setupPrefetch: function() {
      // Prefetch critical resources
      const prefetchUrls = [
        './list.php',
        './dashboard.php'
      ];

      prefetchUrls.forEach(url => {
        const link = document.createElement('link');
        link.rel = 'prefetch';
        link.href = url;
        document.head.appendChild(link);
      });
    }
  };

  // ===== Accessibility Enhancements =====
  const AccessibilityEnhancer = {
    init: function() {
      this.setupKeyboardNavigation();
      this.enhanceScreenReader();
      this.setupFocusManagement();
    },

    setupKeyboardNavigation: function() {
      // Enhanced keyboard navigation
      document.addEventListener('keydown', function(e) {
        // ESC key closes modals and dropdowns
        if (e.key === 'Escape') {
          const openModal = document.querySelector('.modal.show');
          const openDropdown = document.querySelector('.dropdown-menu.show');
          
          if (openModal && window.bootstrap) {
            bootstrap.Modal.getInstance(openModal)?.hide();
          }
          if (openDropdown && window.bootstrap) {
            bootstrap.Dropdown.getInstance(openDropdown.previousElementSibling)?.hide();
          }
        }

        // Tab navigation enhancement
        if (e.key === 'Tab') {
          document.body.classList.add('keyboard-navigation');
        }
      });

      // Remove keyboard navigation class on mouse use
      document.addEventListener('mousedown', function() {
        document.body.classList.remove('keyboard-navigation');
      });
    },

    enhanceScreenReader: function() {
      // Add ARIA labels for better screen reader support
      document.querySelectorAll('.btn').forEach(btn => {
        if (!btn.getAttribute('aria-label') && btn.textContent.trim()) {
          btn.setAttribute('aria-label', btn.textContent.trim());
        }
      });

      // Announce page changes
      const pageTitle = document.title;
      const announcement = document.createElement('div');
      announcement.setAttribute('aria-live', 'polite');
      announcement.setAttribute('aria-atomic', 'true');
      announcement.className = 'sr-only';
      announcement.textContent = `تم تحميل صفحة ${pageTitle}`;
      document.body.appendChild(announcement);
    },

    setupFocusManagement: function() {
      // Manage focus for modal dialogs
      document.addEventListener('shown.bs.modal', function(e) {
        const firstFocusable = e.target.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
        if (firstFocusable) {
          firstFocusable.focus();
        }
      });

      // Trap focus in modals
      document.addEventListener('keydown', function(e) {
        const modal = document.querySelector('.modal.show');
        if (modal && e.key === 'Tab') {
          const focusableElements = modal.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
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
      });
    }
  };

  // ===== Main Application =====
  const MarinaHotelApp = {
    init: function() {
      // Wait for DOM to be ready
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => this.initializeApp());
      } else {
        this.initializeApp();
      }
    },

    initializeApp: function() {
      console.log('🏨 Marina Hotel Payment System - Initializing...');

      try {
        // Initialize all modules
        AnimationController.init();
        FormHandler.init();
        InteractiveEffects.init();
        NotificationSystem.init();
        PerformanceOptimizer.init();
        AccessibilityEnhancer.init();

        // Set app as loaded
        isLoaded = true;
        document.body.classList.add('app-loaded');

        console.log('✅ Marina Hotel Payment System - Initialized successfully!');

        // Show welcome message
        setTimeout(() => {
          console.log('🎉 مرحباً بك في نظام إدارة الدفعات - مارينا هوتل');
        }, 1000);

      } catch (error) {
        console.error('❌ Error initializing Marina Hotel App:', error);
      }
    }
  };

  // ===== Global Error Handler =====
  window.addEventListener('error', function(e) {
    console.error('Marina Hotel App Error:', e.error);
  });

  // ===== Expose public API =====
  window.MarinaHotel = {
    Utils,
    NotificationSystem,
    FormHandler,
    version: '2.0.0'
  };

  // ===== Initialize Application =====
  MarinaHotelApp.init();

  // ===== CSS Animations =====
  const style = document.createElement('style');
  style.textContent = `
    @keyframes rippleAnimation {
      to {
        transform: scale(4);
        opacity: 0;
      }
    }

    .keyboard-navigation *:focus {
      outline: 2px solid #667eea !important;
      outline-offset: 2px !important;
    }

    .validation-message {
      transition: all 0.3s ease;
    }

    .app-loaded .card {
      animation: fadeInUp 0.6s ease-out forwards;
    }

    .app-loaded .summary-item {
      animation: scaleIn 0.5s cubic-bezier(0.68, -0.55, 0.265, 1.55) forwards;
    }

    @media (prefers-reduced-motion: reduce) {
      * {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
      }
    }
  `;
  document.head.appendChild(style);

})();/*!
 * Marina Hotel - Custom JavaScript
 * Payment System Premium Features
 * Version: 2.0
 * Author: Marina Hotel Development Team
 */

(function() {
  'use strict';

  // ===== Global Variables =====
  let isLoaded = false;
  let animations = [];
  let intersectionObserver = null;

  // ===== Utility Functions =====
  const Utils = {
    // Debounce function
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

    // Throttle function
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

    // Format number with Arabic locale
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

    // Validate Arabic phone number
    validateYemeniPhone: function(phone) {
      const cleanPhone = phone.replace(/[^0-9]/g, '');
      const patterns = [
        /^967[7][0-9]{8}$/,  // +967 7XXXXXXXX
        /^[7][0-9]{8}$/,     // 7XXXXXXXX
        /^00967[7][0-9]{8}$/ // 00967 7XXXXXXXX
      ];
      return patterns.some(pattern => pattern.test(cleanPhone));
    },

    // Generate random ID
    generateId: function() {
      return 'marina_' + Math.random().toString(36).substr(2, 9);
    },

    // Get element offset
    getOffset: function(element) {
      const rect = element.getBoundingClientRect();
      return {
        top: rect.top + window.pageYOffset,
        left: rect.left + window.pageXOffset,
        width: rect.width,
        height: rect.height
      };
    }
  };

  // ===== Animation System =====
  const AnimationController = {
    init: function() {
      this.setupIntersectionObserver();
      this.initializeAnimations();
    },

    setupIntersectionObserver: function() {
      if (!window.IntersectionObserver) return;

      intersectionObserver = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
          if (entry.isIntersecting) {
            this.animateElement(entry.target);
            intersectionObserver.unobserve(entry.target);
          }
        });
      }, {
        threshold: 0.1,
        rootMargin: '0px 0px -50px 0px'
      });
    },

    initializeAnimations: function() {
      // Animate cards
      document.querySelectorAll('.card').forEach((card, index) => {
        card.style.opacity = '0';
        card.style.transform = 'translateY(30px)';
        card.setAttribute('data-animation', 'fadeInUp');
        card.setAttribute('data-delay', index * 100);
        
        if (intersectionObserver) {
          intersectionObserver.observe(card);
        } else {
          setTimeout(() => this.animateElement(card), index * 100);
        }
      });

      // Animate summary items
      document.querySelectorAll('.summary-item').forEach((item, index) => {
        item.style.opacity = '0';
        item.style.transform = 'scale(0.8)';
        item.setAttribute('data-animation', 'scaleIn');
        item.setAttribute('data-delay', index * 150);
        
        if (intersectionObserver) {
          intersectionObserver.observe(item);
        } else {
          setTimeout(() => this.animateElement(item), index * 150);
        }
      });
    },

    animateElement: function(element) {
      const animation = element.getAttribute('data-animation');
      const delay = parseInt(element.getAttribute('data-delay')) || 0;

      setTimeout(() => {
        switch (animation) {
          case 'fadeInUp':
            element.style.transition = 'all 0.6s cubic-bezier(0.4, 0, 0.2, 1)';
            element.style.opacity = '1';
            element.style.transform = 'translateY(0)';
            break;
          case 'scaleIn':
            element.style.transition = 'all 0.5s cubic-bezier(0.68, -0.55, 0.265, 1.55)';
            element.style.opacity = '1';
            element.style.transform = 'scale(1)';
            break;
          case 'slideInRight':
            element.style.transition = 'all 0.6s ease-out';
            element.style.opacity = '1';
            element.style.transform = 'translateX(0)';
            break;
        }
      }, delay);
    }
  };

  // ===== Form Enhancement =====
  const FormHandler = {
    init: function() {
      this.enhanceFormInputs();
      this.setupValidation();
      this.setupAutoComplete();
    },

    enhanceFormInputs: function() {
      // Add floating labels effect
      document.querySelectorAll('.form-control, .form-select').forEach(input => {
        // Focus effects
        input.addEventListener('focus', function() {
          this.parentElement.classList.add('focused');
          if (this.parentElement.querySelector('.form-label')) {
            this.parentElement.querySelector('.form-label').style.transform = 'translateY(-8px) scale(0.85)';
          }
        });

        input.addEventListener('blur', function() {
          this.parentElement.classList.remove('focused');
          if (!this.value && this.parentElement.querySelector('.form-label')) {
            this.parentElement.querySelector('.form-label').style.transform = 'translateY(0) scale(1)';
          }
        });

        // Auto-format numbers
        if (input.type === 'number' || input.classList.contains('number-input')) {
          input.addEventListener('input', function() {
            const value = this.value.replace(/[^0-9.]/g, '');
            if (value !== this.value) {
              this.value = value;
            }
          });
        }

        // Phone number formatting
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
      // Enhanced amount validation
      const amountInput = document.getElementById('amount');
      if (amountInput) {
        amountInput.addEventListener('input', Utils.debounce(function() {
          const value = parseFloat(this.value);
          const max = parseFloat(this.getAttribute('max'));
          const min = parseFloat(this.getAttribute('min')) || 0;

          // Clear previous validation
          this.classList.remove('is-valid', 'is-invalid');
          
          if (isNaN(value) || value <= min) {
            this.classList.add('is-invalid');
            this.setCustomValidity('المبلغ يجب أن يكون أكبر من ' + min);
            FormHandler.showValidationMessage(this, 'error', 'المبلغ يجب أن يكون أكبر من ' + min);
          } else if (value > max) {
            this.classList.add('is-invalid');
            this.setCustomValidity('المبلغ لا يمكن أن يتجاوز ' + Utils.formatNumber(max) + ' ريال');
            FormHandler.showValidationMessage(this, 'error', 'المبلغ لا يمكن أن يتجاوز ' + Utils.formatNumber(max) + ' ريال');
          } else {
            this.classList.add('is-valid');
            this.setCustomValidity('');
            FormHandler.showValidationMessage(this, 'success', 'المبلغ صحيح ✓');
          }
        }, 300));
      }

      // Date validation
      const dateInput = document.getElementById('payment_date');
      if (dateInput) {
        dateInput.addEventListener('change', function() {
          const selectedDate = new Date(this.value);
          const now = new Date();
          const maxDate = new Date(now.getTime() + (24 * 60 * 60 * 1000)); // Tomorrow

          this.classList.remove('is-valid', 'is-invalid');

          if (selectedDate > maxDate) {
            this.classList.add('is-invalid');
            FormHandler.showValidationMessage(this, 'error', 'لا يمكن اختيار تاريخ مستقبلي');
          } else {
            this.classList.add('is-valid');
            FormHandler.hideValidationMessage(this);
          }
        });
      }
    },

    setupAutoComplete: function() {
      // Auto-update payment date
      const dateInput = document.getElementById('payment_date');
      if (dateInput && !dateInput.value) {
        this.updatePaymentDateTime();
        
        // Update every minute
        setInterval(() => {
          if (document.activeElement !== dateInput) {
            this.updatePaymentDateTime();
          }
        }, 60000);
      }
    },

    updatePaymentDateTime: function() {
      const dateInput = document.getElementById('payment_date');
      if (dateInput && !dateInput.value) {
        const now = new Date();
        const localDateTime = now.toISOString().slice(0, 16);
        dateInput.value = localDateTime;
      }
    },

    showValidationMessage: function(input, type, message) {
      let messageElement = input.parentElement.querySelector('.validation-message');
      
      if (!messageElement) {
        messageElement = document.createElement('div');
        messageElement.className = 'validation-message small mt-1';
        input.parentElement.appendChild(messageElement);
      }

      messageElement.className = `validation-message small mt-1 text-${type === 'error' ? 'danger' : 'success'}`;
      messageElement.textContent = message;
      messageElement.style.opacity = '0';
      messageElement.style.transform = 'translateY(-10px)';
      
      setTimeout(() => {
        messageElement.style.transition = 'all 0.3s ease';
        messageElement.style.opacity = '1';
        messageElement.style.transform = 'translateY(0)';
      }, 10);
    },

    hideValidationMessage: function(input) {
      const messageElement = input.parentElement.querySelector('.validation-message');
      if (messageElement) {
        messageElement.style.opacity = '0';
        setTimeout(() => messageElement.remove(), 300);
      }
    }
  };

  // ===== Interactive Effects =====
  const InteractiveEffects = {
    init: function() {
      this.setupHoverEffects();
      this.setupClickEffects();
      this.setupProgressRing();
      this.setupCounterAnimations();
    },

    setupHoverEffects: function() {
      // Button hover effects
      document.querySelectorAll('.btn').forEach(btn => {
        btn.addEventListener('mouseenter', function() {
          this.style.transform = 'translateY(-2px) scale(1.02)';
        });

        btn.addEventListener('mouseleave', function() {
          this.style.transform = 'translateY(0) scale(1)';
        });

        btn.addEventListener('mousedown', function() {
          this.style.transform = 'translateY(0) scale(0.98)';
        });

        btn.addEventListener('mouseup', function() {
          this.style.transform = 'translateY(-2px) scale(1.02)';
        });
      });

      // Card hover effects
      document.querySelectorAll('.card').forEach(card => {
        card.addEventListener('mouseenter', function() {
          this.style.transform = 'translateY(-5px)';
          this.style.boxShadow = '0 20px 45px rgba(0, 0, 0, 0.15)';
        });

        card.addEventListener('mouseleave', function() {
          this.style.transform = 'translateY(0)';
          this.style.boxShadow = '0 15px 35px rgba(0, 0, 0, 0.1)';
        });
      });
    },

    setupClickEffects: function() {
      // Summary items click effect
      document.querySelectorAll('.summary-item').forEach(item => {
        item.addEventListener('click', function() {
          // Create ripple effect
          const ripple = document.createElement('div');
          ripple.className = 'ripple-effect';
          ripple.style.cssText = `
            position: absolute;
            border-radius: 50%;
            background: rgba(255, 255, 255, 0.6);
            transform: scale(0);
            animation: rippleAnimation 0.6s linear;
            pointer-events: none;
          `;

          const rect = this.getBoundingClientRect();
          const size = Math.max(rect.width, rect.height);
          ripple.style.width = ripple.style.height = size + 'px';
          ripple.style.left = (event.clientX - rect.left - size / 2) + 'px';
          ripple.style.top = (event.clientY - rect.top - size / 2) + 'px';

          this.style.position = 'relative';
          this.appendChild(ripple);

          setTimeout(() => ripple.remove(), 600);
        });
      });
    },

    setupProgressRing: function() {
      const progressRing = document.querySelector('.progress-ring .progress');
      if (progressRing) {
        const progress = progressRing.style.getPropertyValue('--progress') || '0';
        const circumference = 2 * Math.PI * 25; // radius = 25
        
        progressRing.style.strokeDasharray = circumference;
        progressRing.style.strokeDashoffset = circumference;

        // Animate progress
        setTimeout(() => {
          const offset = circumference - (parseInt(progress) / 100) * circumference;
          progressRing.style.strokeDashoffset = offset;
        }, 500);
      }
    },

    setupCounterAnimations: function() {
      document.querySelectorAll('.summary-item h3').forEach(counter => {
        const target = parseInt(counter.textContent.replace(/[^0-9]/g, ''));
        if (target > 0) {
          let current = 0;
          const increment = target / 60; // 1 second animation at 60fps
          const timer = setInterval(() => {
            current += increment;
            if (current >= target) {
              current = target;
              clearInterval(timer);
            }
            counter.textContent = Utils.formatNumber(Math.floor(current)) + ' ريال';
          }, 16);
        }
      });
    }
  };

  // ===== Toast Notifications =====
  const NotificationSystem = {
    init: function() {
      this.setupToasts();
    },

    setupToasts: function() {
      const toastElement = document.getElementById('flashToast');
      if (toastElement && window.bootstrap) {
        const toast = new bootstrap.Toast(toastElement, {
          delay: 5000,
          autohide: true
        });
        
        // Enhanced toast with sound effect (optional)
        toastElement.addEventListener('shown.bs.toast', function() {
          // You can add sound effect here if needed
          console.log('Toast shown with enhanced animation');
        });

        toast.show();
      }
    },

    showCustomToast: function(message, type = 'info', duration = 5000) {
      const toastContainer = document.querySelector('.toast-container') || this.createToastContainer();
      
      const toastHTML = `
        <div class="toast align-items-center text-bg-${type} border-0" role="alert">
          <div class="d-flex">
            <div class="toast-body">
              <i class="fas fa-${this.getIconForType(type)} me-2"></i>
              ${message}
            </div>
            <button type="button" class="btn-close btn-close-white me-2 m-auto" data-bs-dismiss="toast"></button>
          </div>
        </div>
      `;

      toastContainer.insertAdjacentHTML('beforeend', toastHTML);
      const newToast = toastContainer.lastElementChild;
      
      if (window.bootstrap) {
        const toast = new bootstrap.Toast(newToast, { delay: duration });
        toast.show();
        
        newToast.addEventListener('hidden.bs.toast', function() {
          this.remove();
        });
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
        success: 'check-circle',
        danger: 'exclamation-triangle',
        warning: 'exclamation-triangle',
        info: 'info-circle',
        primary: 'info-circle'
      };
      return icons[type] || 'info-circle';
    }
  };

  // ===== Performance Optimization =====
  const PerformanceOptimizer = {
    init: function() {
      this.lazyLoadImages();
      this.optimizeAnimations();
      this.setupPrefetch();
    },

    lazyLoadImages: function() {
      if ('IntersectionObserver' in window) {
        const images = document.querySelectorAll('img[data-src]');
        const imageObserver = new IntersectionObserver((entries, observer) => {
          entries.forEach(entry => {
            if (entry.isIntersecting) {
              const img = entry.target;
              img.src = img.dataset.src;
              img.classList.remove('lazy');
              observer.unobserve(img);
            }
          });
        });

        images.forEach(img => imageObserver.observe(img));
      }
    },

    optimizeAnimations: function() {
      // Reduce animations on low-end devices
      if (navigator.hardwareConcurrency && navigator.hardwareConcurrency <= 4) {
        document.documentElement.style.setProperty('--animation-duration', '0.3s');
      }

      // Pause animations when tab is not visible
      document.addEventListener('visibilitychange', function() {
        const animations = document.querySelectorAll('[style*="animation"]');
        animations.forEach(el => {
          if (document.hidden) {
            el.style.animationPlayState = 'paused';
          } else {
            el.style.animationPlayState = 'running';
          }
        });
      });
    },

    setupPrefetch: function() {
      // Prefetch critical resources
      const prefetchUrls = [
        './list.php',
        './dashboard.php'
      ];

      prefetchUrls.forEach(url => {
        const link = document.createElement('link');
        link.rel = 'prefetch';
        link.href = url;
        document.head.appendChild(link);
      });
    }
  };

  // ===== Accessibility Enhancements =====
  const AccessibilityEnhancer = {
    init: function() {
      this.setupKeyboardNavigation();
      this.enhanceScreenReader();
      this.setupFocusManagement();
    },

    setupKeyboardNavigation: function() {
      // Enhanced keyboard navigation
      document.addEventListener('keydown', function(e) {
        // ESC key closes modals and dropdowns
        if (e.key === 'Escape') {
          const openModal = document.querySelector('.modal.show');
          const openDropdown = document.querySelector('.dropdown-menu.show');
          
          if (openModal && window.bootstrap) {
            bootstrap.Modal.getInstance(openModal)?.hide();
          }
          if (openDropdown && window.bootstrap) {
            bootstrap.Dropdown.getInstance(openDropdown.previousElementSibling)?.hide();
          }
        }

        // Tab navigation enhancement
        if (e.key === 'Tab') {
          document.body.classList.add('keyboard-navigation');
        }
      });

      // Remove keyboard navigation class on mouse use
      document.addEventListener('mousedown', function() {
        document.body.classList.remove('keyboard-navigation');
      });
    },

    enhanceScreenReader: function() {
      // Add ARIA labels for better screen reader support
      document.querySelectorAll('.btn').forEach(btn => {
        if (!btn.getAttribute('aria-label') && btn.textContent.trim()) {
          btn.setAttribute('aria-label', btn.textContent.trim());
        }
      });

      // Announce page changes
      const pageTitle = document.title;
      const announcement = document.createElement('div');
      announcement.setAttribute('aria-live', 'polite');
      announcement.setAttribute('aria-atomic', 'true');
      announcement.className = 'sr-only';
      announcement.textContent = `تم تحميل صفحة ${pageTitle}`;
      document.body.appendChild(announcement);
    },

    setupFocusManagement: function() {
      // Manage focus for modal dialogs
      document.addEventListener('shown.bs.modal', function(e) {
        const firstFocusable = e.target.querySelector('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
        if (firstFocusable) {
          firstFocusable.focus();
        }
      });

      // Trap focus in modals
      document.addEventListener('keydown', function(e) {
        const modal = document.querySelector('.modal.show');
        if (modal && e.key === 'Tab') {
          const focusableElements = modal.querySelectorAll('button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])');
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
      });
    }
  };

  // ===== Main Application =====
  const MarinaHotelApp = {
    init: function() {
      // Wait for DOM to be ready
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', () => this.initializeApp());
      } else {
        this.initializeApp();
      }
    },

    initializeApp: function() {
      console.log('🏨 Marina Hotel Payment System - Initializing...');

      try {
        // Initialize all modules
        AnimationController.init();
        FormHandler.init();
        InteractiveEffects.init();
        NotificationSystem.init();
        PerformanceOptimizer.init();
        AccessibilityEnhancer.init();

        // Set app as loaded
        isLoaded = true;
        document.body.classList.add('app-loaded');

        console.log('✅ Marina Hotel Payment System - Initialized successfully!');

        // Show welcome message
        setTimeout(() => {
          console.log('🎉 مرحباً بك في نظام إدارة الدفعات - مارينا هوتل');
        }, 1000);

      } catch (error) {
        console.error('❌ Error initializing Marina Hotel App:', error);
      }
    }
  };

  // ===== Global Error Handler =====
  window.addEventListener('error', function(e) {
    console.error('Marina Hotel App Error:', e.error);
  });

  // ===== Expose public API =====
  window.MarinaHotel = {
    Utils,
    NotificationSystem,
    FormHandler,
    version: '2.0.0'
  };

  // ===== Initialize Application =====
  MarinaHotelApp.init();

  // ===== CSS Animations =====
  const style = document.createElement('style');
  style.textContent = `
    @keyframes rippleAnimation {
      to {
        transform: scale(4);
        opacity: 0;
      }
    }

    .keyboard-navigation *:focus {
      outline: 2px solid #667eea !important;
      outline-offset: 2px !important;
    }

    .validation-message {
      transition: all 0.3s ease;
    }

    .app-loaded .card {
      animation: fadeInUp 0.6s ease-out forwards;
    }

    .app-loaded .summary-item {
      animation: scaleIn 0.5s cubic-bezier(0.68, -0.55, 0.265, 1.55) forwards;
    }

    @media (prefers-reduced-motion: reduce) {
      * {
        animation-duration: 0.01ms !important;
        animation-iteration-count: 1 !important;
        transition-duration: 0.01ms !important;
      }
    }
  `;
  document.head.appendChild(style);

})();