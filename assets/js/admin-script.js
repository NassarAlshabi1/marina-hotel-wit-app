/* Marina Hotel Admin System - Local JavaScript */
/* تفاعلات محلية للوحة الإدارة */

document.addEventListener('DOMContentLoaded', function() {
    
    // Mobile menu toggle
    const mobileToggle = document.getElementById('mobileToggle');
    const mainNav = document.getElementById('mainNav');
    
    if (mobileToggle && mainNav) {
        mobileToggle.addEventListener('click', function() {
            mainNav.classList.toggle('active');
            
            // Change icon
            const icon = this.querySelector('i');
            if (mainNav.classList.contains('active')) {
                icon.classList.remove('fa-bars');
                icon.classList.add('fa-times');
            } else {
                icon.classList.remove('fa-times');
                icon.classList.add('fa-bars');
            }
        });

        // Close mobile menu when clicking outside
        document.addEventListener('click', function(e) {
            if (!mainNav.contains(e.target) && !mobileToggle.contains(e.target)) {
                mainNav.classList.remove('active');
                const icon = mobileToggle.querySelector('i');
                icon.classList.remove('fa-times');
                icon.classList.add('fa-bars');
            }
        });
    }

    // Smooth scrolling for anchor links
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function (e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                target.scrollIntoView({
                    behavior: 'smooth',
                    block: 'start'
                });
            }
        });
    });

    // Auto-hide alerts after 5 seconds
    const alerts = document.querySelectorAll('.alert');
    alerts.forEach(alert => {
        setTimeout(() => {
            alert.style.opacity = '0';
            alert.style.transform = 'translateY(-20px)';
            setTimeout(() => {
                alert.remove();
            }, 300);
        }, 5000);
    });

    // Form validation
    const forms = document.querySelectorAll('form');
    forms.forEach(form => {
        form.addEventListener('submit', function(e) {
            const requiredFields = form.querySelectorAll('[required]');
            let isValid = true;

            requiredFields.forEach(field => {
                if (!field.value.trim()) {
                    isValid = false;
                    field.style.borderColor = '#ff416c';
                    field.style.boxShadow = '0 0 0 3px rgba(255, 65, 108, 0.1)';
                } else {
                    field.style.borderColor = '#e1e5e9';
                    field.style.boxShadow = 'none';
                }
            });

            if (!isValid) {
                e.preventDefault();
                showAlert('يرجى ملء جميع الحقول المطلوبة', 'danger');
            }
        });
    });

    // Table search functionality
    const searchInputs = document.querySelectorAll('.table-search');
    searchInputs.forEach(input => {
        input.addEventListener('keyup', function() {
            const filter = this.value.toLowerCase();
            const table = this.closest('.card').querySelector('table');
            const rows = table.querySelectorAll('tbody tr');

            rows.forEach(row => {
                const text = row.textContent.toLowerCase();
                if (text.includes(filter)) {
                    row.style.display = '';
                } else {
                    row.style.display = 'none';
                }
            });
        });
    });

    // Confirmation dialogs
    const deleteButtons = document.querySelectorAll('.btn-delete, .btn-danger[href*="delete"]');
    deleteButtons.forEach(button => {
        button.addEventListener('click', function(e) {
            if (!confirm('هل أنت متأكد من أنك تريد حذف هذا العنصر؟')) {
                e.preventDefault();
            }
        });
    });

    // Print functionality
    const printButtons = document.querySelectorAll('.btn-print');
    printButtons.forEach(button => {
        button.addEventListener('click', function() {
            window.print();
        });
    });

    // Auto-refresh for dashboard
    if (window.location.pathname.includes('dash.php')) {
        setInterval(() => {
            // Refresh dashboard stats every 5 minutes
            location.reload();
        }, 300000);
    }

    // Number formatting
    const numberElements = document.querySelectorAll('.number-format');
    numberElements.forEach(element => {
        const number = parseFloat(element.textContent);
        if (!isNaN(number)) {
            element.textContent = number.toLocaleString('ar-YE');
        }
    });

    // Date formatting
    const dateElements = document.querySelectorAll('.date-format');
    dateElements.forEach(element => {
        const date = new Date(element.textContent);
        if (!isNaN(date.getTime())) {
            element.textContent = date.toLocaleDateString('ar-YE');
        }
    });

    // Tooltip functionality
    const tooltipElements = document.querySelectorAll('[data-tooltip]');
    tooltipElements.forEach(element => {
        element.addEventListener('mouseenter', function() {
            const tooltip = document.createElement('div');
            tooltip.className = 'tooltip';
            tooltip.textContent = this.getAttribute('data-tooltip');
            tooltip.style.cssText = `
                position: absolute;
                background: #333;
                color: white;
                padding: 0.5rem;
                border-radius: 5px;
                font-size: 0.875rem;
                z-index: 1000;
                pointer-events: none;
                opacity: 0;
                transition: opacity 0.3s ease;
            `;
            document.body.appendChild(tooltip);

            const rect = this.getBoundingClientRect();
            tooltip.style.left = rect.left + 'px';
            tooltip.style.top = (rect.top - tooltip.offsetHeight - 5) + 'px';
            
            setTimeout(() => {
                tooltip.style.opacity = '1';
            }, 100);

            this.addEventListener('mouseleave', function() {
                tooltip.remove();
            });
        });
    });

    // Loading states for buttons
    const submitButtons = document.querySelectorAll('button[type="submit"]');
    submitButtons.forEach(button => {
        button.addEventListener('click', function() {
            const originalText = this.innerHTML;
            this.innerHTML = '<i class="fas fa-spinner fa-spin"></i> جاري المعالجة...';
            this.disabled = true;

            // Re-enable after 3 seconds (fallback)
            setTimeout(() => {
                this.innerHTML = originalText;
                this.disabled = false;
            }, 3000);
        });
    });

    // Auto-save for forms
    const autoSaveForms = document.querySelectorAll('.auto-save');
    autoSaveForms.forEach(form => {
        const inputs = form.querySelectorAll('input, textarea, select');
        inputs.forEach(input => {
            input.addEventListener('change', function() {
                localStorage.setItem(`form_${form.id}_${this.name}`, this.value);
            });

            // Restore saved values
            const savedValue = localStorage.getItem(`form_${form.id}_${input.name}`);
            if (savedValue) {
                input.value = savedValue;
            }
        });

        // Clear saved data on successful submit
        form.addEventListener('submit', function() {
            inputs.forEach(input => {
                localStorage.removeItem(`form_${form.id}_${input.name}`);
            });
        });
    });

    // Chart animations (if charts exist)
    const chartElements = document.querySelectorAll('.chart');
    chartElements.forEach(chart => {
        chart.style.opacity = '0';
        chart.style.transform = 'translateY(20px)';
        
        setTimeout(() => {
            chart.style.transition = 'all 0.6s ease';
            chart.style.opacity = '1';
            chart.style.transform = 'translateY(0)';
        }, 200);
    });

    // Keyboard shortcuts
    document.addEventListener('keydown', function(e) {
        // Ctrl+S to save forms
        if (e.ctrlKey && e.key === 's') {
            e.preventDefault();
            const form = document.querySelector('form');
            if (form) {
                form.submit();
            }
        }

        // Escape to close modals
        if (e.key === 'Escape') {
            const modals = document.querySelectorAll('.modal.show');
            modals.forEach(modal => {
                modal.classList.remove('show');
            });
        }
    });

    // Lazy loading for images
    const images = document.querySelectorAll('img[data-src]');
    const imageObserver = new IntersectionObserver((entries, observer) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const img = entry.target;
                img.src = img.dataset.src;
                img.removeAttribute('data-src');
                observer.unobserve(img);
            }
        });
    });

    images.forEach(img => imageObserver.observe(img));

    // Performance monitoring
    if ('performance' in window) {
        window.addEventListener('load', function() {
            const loadTime = performance.timing.loadEventEnd - performance.timing.navigationStart;
            console.log(`Page loaded in ${loadTime}ms`);
        });
    }
});

// Utility functions
function showAlert(message, type = 'info') {
    const alert = document.createElement('div');
    alert.className = `alert alert-${type}`;
    alert.innerHTML = `
        <i class="fas fa-${type === 'success' ? 'check' : type === 'danger' ? 'exclamation-triangle' : 'info-circle'}"></i>
        ${message}
    `;
    
    const container = document.querySelector('.main-content');
    if (container) {
        container.insertBefore(alert, container.firstChild);
        
        setTimeout(() => {
            alert.style.opacity = '0';
            alert.style.transform = 'translateY(-20px)';
            setTimeout(() => {
                alert.remove();
            }, 300);
        }, 5000);
    }
}

function formatCurrency(amount) {
    return new Intl.NumberFormat('ar-YE', {
        style: 'currency',
        currency: 'YER'
    }).format(amount);
}

function formatDate(date) {
    return new Date(date).toLocaleDateString('ar-YE', {
        year: 'numeric',
        month: 'long',
        day: 'numeric'
    });
}

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

// Export functions for global use
window.MarinaAdmin = {
    showAlert,
    formatCurrency,
    formatDate,
    debounce
};
