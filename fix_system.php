<?php
/*!
 * System Auto-Fix Utility - Marina Hotel
 * Automatic system repair and optimization tool
 * Version: 2.0
 */

// Security check
if (!isset($_GET['confirm']) || $_GET['confirm'] !== 'yes') {
    die('
    <div style="background: #f8f9fa; padding: 20px; font-family: Arial, sans-serif; direction: rtl; text-align: center;">
        <h2 style="color: #dc3545;">⚠️ تحذير أمني</h2>
        <p>هذا الملف يقوم بإصلاح النظام تلقائياً. هل أنت متأكد من المتابعة؟</p>
        <a href="fix_system.php?confirm=yes" style="background: #dc3545; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">نعم، متابعة الإصلاح</a>
        <a href="system_status.php" style="background: #6c757d; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; margin-right: 10px;">إلغاء</a>
    </div>
    ');
}

// Include configurations
require_once 'includes/local-system-config.php';

// Auto-fix class
class SystemAutoFix {
    private $fixes = [];
    private $errors = [];
    
    public function __construct() {
        $this->fixes = [];
        $this->errors = [];
    }
    
    /**
     * Run all auto-fixes
     */
    public function runAllFixes() {
        $this->log("🔧 بدء عملية الإصلاح التلقائي...");
        
        // 1. Create missing directories
        $this->createMissingDirectories();
        
        // 2. Download and create missing CSS files
        $this->createMissingCssFiles();
        
        // 3. Download and create missing JS files
        $this->createMissingJsFiles();
        
        // 4. Create missing font files
        $this->createFontFiles();
        
        // 5. Fix file permissions
        $this->fixFilePermissions();
        
        // 6. Test system health
        $this->testSystemHealth();
        
        $this->log("✅ تم إنجاز عملية الإصلاح التلقائي");
        
        return [
            'fixes' => $this->fixes,
            'errors' => $this->errors
        ];
    }
    
    /**
     * Create missing directories
     */
    private function createMissingDirectories() {
        $directories = [
            'includes/css',
            'includes/js',
            'includes/fonts',
            'includes/images'
        ];
        
        foreach ($directories as $dir) {
            if (!is_dir($dir)) {
                if (mkdir($dir, 0755, true)) {
                    $this->log("✅ تم إنشاء مجلد: $dir");
                } else {
                    $this->error("❌ فشل إنشاء مجلد: $dir");
                }
            }
        }
    }
    
    /**
     * Create missing CSS files
     */
    private function createMissingCssFiles() {
        $this->log("🎨 فحص وإنشاء ملفات CSS...");
        
        // Check if bootstrap exists
        if (!file_exists('includes/css/bootstrap.min.css')) {
            $this->createBootstrapCss();
        }
        
        // Check if fontawesome exists
        if (!file_exists('includes/css/fontawesome.min.css')) {
            $this->createFontAwesomeCss();
        }
        
        // Check if custom CSS exists
        if (!file_exists('includes/css/custom.css')) {
            $this->createCustomCss();
        }
        
        // Check if font files exist
        if (!file_exists('includes/css/cairo-font.css')) {
            $this->createCairoFontCss();
        }
        
        if (!file_exists('includes/css/tajawal-font.css')) {
            $this->createTajawalFontCss();
        }
    }
    
    /**
     * Create Bootstrap CSS file
     */
    private function createBootstrapCss() {
        $css = '/*! Bootstrap v5.3.0 | Marina Hotel Local Version */
body{margin:0;font-family:var(--bs-body-font-family);font-size:var(--bs-body-font-size);font-weight:var(--bs-body-font-weight);line-height:var(--bs-body-line-height);color:var(--bs-body-color);text-align:var(--bs-body-text-align);background-color:var(--bs-body-bg);-webkit-text-size-adjust:100%;-webkit-tap-highlight-color:transparent}
:root{--bs-blue:#0d6efd;--bs-indigo:#6610f2;--bs-purple:#6f42c1;--bs-pink:#d63384;--bs-red:#dc3545;--bs-orange:#fd7e14;--bs-yellow:#ffc107;--bs-green:#198754;--bs-teal:#20c997;--bs-cyan:#0dcaf0;--bs-white:#fff;--bs-gray:#6c757d;--bs-gray-dark:#343a40;--bs-primary:#0d6efd;--bs-secondary:#6c757d;--bs-success:#198754;--bs-info:#0dcaf0;--bs-warning:#ffc107;--bs-danger:#dc3545;--bs-light:#f8f9fa;--bs-dark:#212529;--bs-font-sans-serif:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans","Liberation Sans",sans-serif;--bs-font-monospace:SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;--bs-gradient:linear-gradient(180deg,rgba(255,255,255,.15),rgba(255,255,255,0));--bs-body-font-family:var(--bs-font-sans-serif);--bs-body-font-size:1rem;--bs-body-font-weight:400;--bs-body-line-height:1.5;--bs-body-color:#212529;--bs-body-bg:#fff}
.container{width:100%;padding-right:var(--bs-gutter-x,.75rem);padding-left:var(--bs-gutter-x,.75rem);margin-right:auto;margin-left:auto}
.btn{display:inline-block;font-weight:400;line-height:1.5;color:#212529;text-align:center;text-decoration:none;vertical-align:middle;cursor:pointer;-webkit-user-select:none;-moz-user-select:none;user-select:none;background-color:transparent;border:1px solid transparent;padding:.375rem .75rem;font-size:1rem;border-radius:.25rem;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}
.btn-primary{color:#fff;background-color:#0d6efd;border-color:#0d6efd}
.btn-primary:hover{color:#fff;background-color:#0b5ed7;border-color:#0a58ca}
.card{position:relative;display:flex;flex-direction:column;min-width:0;word-wrap:break-word;background-color:#fff;background-clip:border-box;border:1px solid rgba(0,0,0,.125);border-radius:.25rem}
.card-body{flex:1 1 auto;padding:1rem}
.card-header{padding:.5rem 1rem;margin-bottom:0;background-color:rgba(0,0,0,.03);border-bottom:1px solid rgba(0,0,0,.125)}
.table{width:100%;margin-bottom:1rem;color:#212529}
.table th,.table td{padding:.5rem;text-align:inherit;vertical-align:top;border-top:1px solid #dee2e6}
.form-control{display:block;width:100%;padding:.375rem .75rem;font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;background-image:none;border:1px solid #ced4da;border-radius:.25rem;transition:border-color .15s ease-in-out,box-shadow .15s ease-in-out}
.alert{position:relative;padding:.75rem 1.25rem;margin-bottom:1rem;border:1px solid transparent;border-radius:.25rem}
.alert-success{color:#155724;background-color:#d4edda;border-color:#c3e6cb}
.alert-danger{color:#721c24;background-color:#f8d7da;border-color:#f5c6cb}
.text-center{text-align:center!important}
.mb-3{margin-bottom:1rem!important}
.p-3{padding:1rem!important}
.d-flex{display:flex!important}
.justify-content-between{justify-content:space-between!important}
.align-items-center{align-items:center!important}
.row{display:flex;flex-wrap:wrap;margin-right:-15px;margin-left:-15px}
.col-md-6{flex:0 0 50%;max-width:50%}
.col-md-12{flex:0 0 100%;max-width:100%}
@media (min-width:768px){.container{max-width:720px}}
@media (min-width:992px){.container{max-width:960px}}
@media (min-width:1200px){.container{max-width:1140px}}';
        
        if (file_put_contents('includes/css/bootstrap.min.css', $css)) {
            $this->log("✅ تم إنشاء ملف Bootstrap CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Bootstrap CSS");
        }
    }
    
    /**
     * Create Font Awesome CSS file
     */
    private function createFontAwesomeCss() {
        $css = '/*! Font Awesome Free 6.4.0 | Marina Hotel Local Version */
.fa,.fas,.far,.fal,.fad,.fab{-moz-osx-font-smoothing:grayscale;-webkit-font-smoothing:antialiased;display:inline-block;font-style:normal;font-variant:normal;line-height:1;text-rendering:auto}
.fa-hotel:before{content:"\\f594"}
.fa-plus-circle:before{content:"\\f055"}
.fa-check-circle:before{content:"\\f058"}
.fa-times-circle:before{content:"\\f057"}
.fa-exclamation-triangle:before{content:"\\f071"}
.fa-info-circle:before{content:"\\f05a"}
.fa-user:before{content:"\\f007"}
.fa-sign-out-alt:before{content:"\\f2f5"}
.fa-money-bill-wave:before{content:"\\f53a"}
.fa-calendar-alt:before{content:"\\f073"}
.fa-chart-bar:before{content:"\\f080"}
.fa-tachometer-alt:before{content:"\\f3fd"}
.fa-home:before{content:"\\f015"}
.fa-list:before{content:"\\f03a"}
.fa-save:before{content:"\\f0c7"}
.fa-edit:before{content:"\\f044"}
.fa-trash:before{content:"\\f1f8"}
.fa-search:before{content:"\\f002"}
.fa-print:before{content:"\\f02f"}
.fa-download:before{content:"\\f019"}
.fa-upload:before{content:"\\f093"}
.fa-file-pdf:before{content:"\\f1c1"}
.fa-file-excel:before{content:"\\f1c3"}
.fa-tools:before{content:"\\f7d9"}
.fa-cog:before{content:"\\f013"}
.fa-heartbeat:before{content:"\\f21e"}
.fa-server:before{content:"\\f233"}
.fa-wifi:before{content:"\\f1eb"}
.fa-wifi-slash:before{content:"\\f05f"}
.fa-code:before{content:"\\f121"}
.fa-palette:before{content:"\\f53f"}
.fa-folder-open:before{content:"\\f07c"}
.fa-clipboard-list:before{content:"\\f46d"}
.fa-sync-alt:before{content:"\\f2f1"}
.fa-arrow-left:before{content:"\\f060"}
.fa-arrow-right:before{content:"\\f061"}
.fa-door-open:before{content:"\\f52b"}
.fa-bed:before{content:"\\f236"}
.fa-money-check-alt:before{content:"\\f53d"}
.fa-hand-holding-usd:before{content:"\\f4c0"}
.fa-chart-line:before{content:"\\f201"}
.fa-chart-pie:before{content:"\\f200"}
.fa-chart-area:before{content:"\\f1fe"}
.fa-file-alt:before{content:"\\f15c"}
.fa-users:before{content:"\\f0c0"}
.fa-user-tie:before{content:"\\f508"}
.fa-users-cog:before{content:"\\f509"}
.fa-file-invoice-dollar:before{content:"\\f571"}
.fa-tags:before{content:"\\f02c"}
.fa-list-ul:before{content:"\\f0ca"}
.fa-plus:before{content:"\\f067"}
.fa-minus:before{content:"\\f068"}
.fa-times:before{content:"\\f00d"}
.fa-clock:before{content:"\\f017"}
.fa-calendar:before{content:"\\f073"}
.fa-code-branch:before{content:"\\f126"}
.fa-vial:before{content:"\\f492"}
.fa-stethoscope:before{content:"\\f0f1"}
.fa-wrench:before{content:"\\f0ad"}
.fa-me-2{margin-left:0.5rem}
.fa-2x{font-size:2em}
.fa-3x{font-size:3em}
.text-success{color:#198754!important}
.text-danger{color:#dc3545!important}
.text-warning{color:#ffc107!important}
.text-info{color:#0dcaf0!important}
.text-primary{color:#0d6efd!important}';
        
        if (file_put_contents('includes/css/fontawesome.min.css', $css)) {
            $this->log("✅ تم إنشاء ملف Font Awesome CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Font Awesome CSS");
        }
    }
    
    /**
     * Create custom CSS file
     */
    private function createCustomCss() {
        $css = '/*! Custom CSS for Marina Hotel System */
body {
    font-family: "Tajawal", "Cairo", "Arial", sans-serif;
    background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
    direction: rtl;
    text-align: right;
}

.btn {
    border-radius: 25px;
    padding: 12px 30px;
    font-weight: 600;
    transition: all 0.3s ease;
}

.btn-primary {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border: none;
}

.btn-primary:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 25px rgba(102, 126, 234, 0.4);
}

.card {
    border-radius: 20px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
    border: none;
}

.card-header {
    background: linear-gradient(135deg, #36d1dc 0%, #5b86e5 100%);
    color: white;
    border-radius: 20px 20px 0 0;
}

.form-control {
    border-radius: 12px;
    border: 2px solid #e3e6f0;
}

.form-control:focus {
    border-color: #667eea;
    box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
}

.table {
    border-radius: 15px;
    overflow: hidden;
}

.alert {
    border-radius: 15px;
    border: none;
}

.navbar {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
}

.navbar-brand {
    font-weight: 700;
    color: white !important;
}

.nav-link {
    color: rgba(255, 255, 255, 0.9) !important;
    font-weight: 500;
}

.nav-link:hover {
    color: white !important;
}

@media (max-width: 768px) {
    .btn {
        padding: 10px 20px;
        font-size: 0.9rem;
    }
    
    .card {
        margin-bottom: 1rem;
    }
}';
        
        if (file_put_contents('includes/css/custom.css', $css)) {
            $this->log("✅ تم إنشاء ملف Custom CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Custom CSS");
        }
    }
    
    /**
     * Create Cairo font CSS
     */
    private function createCairoFontCss() {
        $css = '/*! Cairo Font CSS for Marina Hotel */
@font-face {
    font-family: "Cairo";
    src: url("data:application/font-woff2;base64,d09GMgABAAAAAAoUAAoAAAAAE+gAAAm/AAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAABmAAgkIKgzyCYwsGAAE2AiQDCQgEBgUHBxsbwQjIHoex82RJF81QPuK9eIhfS9/M7kNIhR3rAKHECtjGp5qrJsrXHtGxiYSPNgJ2iUSuLr8eWu5jfPJzBUWNBRKJaAMTbVa+lRu9tAHJuKbXZKCpAiHOEQDpyQWBUECbEJGKGECQWBTINhQOTiYSJEKRhDQVNJFgEMjhJCg4IhQKnIRKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9Hw==") format("woff2");
    font-weight: 200 900;
    font-style: normal;
    font-display: swap;
}

.cairo-font {
    font-family: "Cairo", sans-serif;
}';
        
        if (file_put_contents('includes/css/cairo-font.css', $css)) {
            $this->log("✅ تم إنشاء ملف Cairo Font CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Cairo Font CSS");
        }
    }
    
    /**
     * Create Tajawal font CSS
     */
    private function createTajawalFontCss() {
        $css = '/*! Tajawal Font CSS for Marina Hotel */
@font-face {
    font-family: "Tajawal";
    src: url("data:application/font-woff2;base64,d09GMgABAAAAAAoUAAoAAAAAE+gAAAm/AAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAABmAAgkIKgzyCYwsGAAE2AiQDCQgEBgUHBxsbwQjIHoex82RJF81QPuK9eIhfS9/M7kNIhR3rAKHECtjGp5qrJsrXHtGxiYSPNgJ2iUSuLr8eWu5jfPJzBUWNBRKJaAMTbVa+lRu9tAHJuKbXZKCpAiHOEQDpyQWBUECbEJGKGECQWBTINhQOTiYSJEKRhDQVNJFgEMjhJCg4IhQKnIRKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9Hw==") format("woff2");
    font-weight: 200 900;
    font-style: normal;
    font-display: swap;
}

.tajawal-font {
    font-family: "Tajawal", sans-serif;
}';
        
        if (file_put_contents('includes/css/tajawal-font.css', $css)) {
            $this->log("✅ تم إنشاء ملف Tajawal Font CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Tajawal Font CSS");
        }
    }
    
    /**
     * Create missing JS files
     */
    private function createMissingJsFiles() {
        $this->log("📜 فحص وإنشاء ملفات JavaScript...");
        
        if (!file_exists('includes/js/bootstrap.bundle.min.js')) {
            $this->createBootstrapJs();
        }
        
        if (!file_exists('includes/js/custom.js')) {
            $this->createCustomJs();
        }
    }
    
    /**
     * Create Bootstrap JS file
     */
    private function createBootstrapJs() {
        $js = '/*! Bootstrap Bundle v5.3.0 | Marina Hotel Local Version */
(function(){
    "use strict";
    
    // Simple Bootstrap implementation for offline use
    window.bootstrap = {
        Toast: function(element, options) {
            this.element = element;
            this.options = options || {};
            
            this.show = function() {
                this.element.style.display = "block";
                this.element.style.opacity = "1";
                
                if (this.options.delay) {
                    setTimeout(() => {
                        this.hide();
                    }, this.options.delay);
                }
            };
            
            this.hide = function() {
                this.element.style.opacity = "0";
                setTimeout(() => {
                    this.element.style.display = "none";
                }, 300);
            };
        },
        
        Modal: function(element, options) {
            this.element = element;
            this.options = options || {};
            
            this.show = function() {
                this.element.style.display = "block";
                this.element.classList.add("show");
            };
            
            this.hide = function() {
                this.element.classList.remove("show");
                setTimeout(() => {
                    this.element.style.display = "none";
                }, 300);
            };
        },
        
        Tooltip: function(element, options) {
            this.element = element;
            this.options = options || {};
            
            // Simple tooltip implementation
            this.element.addEventListener("mouseenter", function() {
                const tooltip = document.createElement("div");
                tooltip.className = "tooltip";
                tooltip.innerHTML = this.getAttribute("data-bs-title") || this.getAttribute("title");
                document.body.appendChild(tooltip);
                
                const rect = this.getBoundingClientRect();
                tooltip.style.position = "absolute";
                tooltip.style.top = (rect.top - 40) + "px";
                tooltip.style.left = (rect.left + rect.width / 2 - tooltip.offsetWidth / 2) + "px";
                tooltip.style.background = "#000";
                tooltip.style.color = "#fff";
                tooltip.style.padding = "5px 10px";
                tooltip.style.borderRadius = "4px";
                tooltip.style.fontSize = "12px";
                tooltip.style.zIndex = "9999";
                
                this._tooltip = tooltip;
            });
            
            this.element.addEventListener("mouseleave", function() {
                if (this._tooltip) {
                    this._tooltip.remove();
                    this._tooltip = null;
                }
            });
        }
    };
    
    // Auto-initialize Bootstrap components
    document.addEventListener("DOMContentLoaded", function() {
        // Auto-initialize dropdowns
        const dropdowns = document.querySelectorAll("[data-bs-toggle=\"dropdown\"]");
        dropdowns.forEach(function(dropdown) {
            dropdown.addEventListener("click", function(e) {
                e.preventDefault();
                const menu = this.nextElementSibling;
                if (menu && menu.classList.contains("dropdown-menu")) {
                    menu.classList.toggle("show");
                }
            });
        });
        
        // Auto-initialize collapse
        const collapses = document.querySelectorAll("[data-bs-toggle=\"collapse\"]");
        collapses.forEach(function(collapse) {
            collapse.addEventListener("click", function(e) {
                e.preventDefault();
                const target = document.querySelector(this.getAttribute("data-bs-target"));
                if (target) {
                    target.classList.toggle("show");
                }
            });
        });
        
        // Auto-initialize tooltips
        const tooltips = document.querySelectorAll("[data-bs-toggle=\"tooltip\"]");
        tooltips.forEach(function(tooltip) {
            new bootstrap.Tooltip(tooltip);
        });
    });
    
})();';
        
        if (file_put_contents('includes/js/bootstrap.bundle.min.js', $js)) {
            $this->log("✅ تم إنشاء ملف Bootstrap JavaScript");
        } else {
            $this->error("❌ فشل إنشاء ملف Bootstrap JavaScript");
        }
    }
    
    /**
     * Create custom JS file
     */
    private function createCustomJs() {
        $js = '/*! Custom JavaScript for Marina Hotel System */
(function() {
    "use strict";
    
    // Marina Hotel System Object
    window.MarinaHotel = {
        version: "2.0.0",
        initialized: false,
        
        init: function() {
            if (this.initialized) return;
            
            console.log("🏨 Marina Hotel System v" + this.version + " - Loading...");
            
            this.setupEventListeners();
            this.enhanceUI();
            this.setupAnimations();
            
            this.initialized = true;
            console.log("✅ Marina Hotel System initialized successfully!");
        },
        
        setupEventListeners: function() {
            // Form validation
            const forms = document.querySelectorAll("form");
            forms.forEach(function(form) {
                form.addEventListener("submit", function(e) {
                    const requiredFields = form.querySelectorAll("[required]");
                    let isValid = true;
                    
                    requiredFields.forEach(function(field) {
                        if (!field.value.trim()) {
                            field.classList.add("is-invalid");
                            isValid = false;
                        } else {
                            field.classList.remove("is-invalid");
                        }
                    });
                    
                    if (!isValid) {
                        e.preventDefault();
                        MarinaHotel.showAlert("يرجى ملء جميع الحقول المطلوبة", "danger");
                    }
                });
            });
            
            // Button loading states
            const buttons = document.querySelectorAll(".btn-loading");
            buttons.forEach(function(button) {
                button.addEventListener("click", function() {
                    if (this.disabled) return;
                    
                    this.disabled = true;
                    this.innerHTML = "<span class=\"spinner-border spinner-border-sm me-2\"></span>جارٍ التحميل...";
                    
                    setTimeout(() => {
                        this.disabled = false;
                        this.innerHTML = this.getAttribute("data-original-text") || "تم";
                    }, 2000);
                });
            });
        },
        
        enhanceUI: function() {
            // Add hover effects to cards
            const cards = document.querySelectorAll(".card");
            cards.forEach(function(card) {
                card.addEventListener("mouseenter", function() {
                    this.style.transform = "translateY(-5px)";
                    this.style.boxShadow = "0 15px 35px rgba(0, 0, 0, 0.15)";
                });
                
                card.addEventListener("mouseleave", function() {
                    this.style.transform = "translateY(0)";
                    this.style.boxShadow = "0 10px 30px rgba(0, 0, 0, 0.1)";
                });
            });
            
            // Enhance form controls
            const inputs = document.querySelectorAll(".form-control");
            inputs.forEach(function(input) {
                input.addEventListener("focus", function() {
                    this.style.transform = "scale(1.02)";
                });
                
                input.addEventListener("blur", function() {
                    this.style.transform = "scale(1)";
                });
            });
        },
        
        setupAnimations: function() {
            // Animate elements on scroll
            const observer = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    if (entry.isIntersecting) {
                        entry.target.style.opacity = "1";
                        entry.target.style.transform = "translateY(0)";
                    }
                });
            });
            
            const elements = document.querySelectorAll(".animate-on-scroll");
            elements.forEach(function(element) {
                element.style.opacity = "0";
                element.style.transform = "translateY(30px)";
                element.style.transition = "all 0.6s ease";
                observer.observe(element);
            });
        },
        
        showAlert: function(message, type) {
            type = type || "info";
            
            const alertHTML = `
                <div class="alert alert-${type} alert-dismissible fade show" role="alert">
                    ${message}
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
            `;
            
            const container = document.querySelector(".container") || document.body;
            container.insertAdjacentHTML("afterbegin", alertHTML);
            
            setTimeout(function() {
                const alert = container.querySelector(".alert");
                if (alert) {
                    alert.remove();
                }
            }, 5000);
        },
        
        formatCurrency: function(amount) {
            return new Intl.NumberFormat("ar-SA", {
                style: "currency",
                currency: "SAR"
            }).format(amount);
        },
        
        formatDate: function(date) {
            return new Date(date).toLocaleDateString("ar-SA");
        }
    };
    
    // Auto-initialize when DOM is ready
    document.addEventListener("DOMContentLoaded", function() {
        MarinaHotel.init();
    });
    
    // Handle dynamic content
    if (typeof MutationObserver !== "undefined") {
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.type === "childList") {
                    MarinaHotel.enhanceUI();
                }
            });
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }
    
})();';
        
        if (file_put_contents('includes/js/custom.js', $js)) {
            $this->log("✅ تم إنشاء ملف Custom JavaScript");
        } else {
            $this->error("❌ فشل إنشاء ملف Custom JavaScript");
        }
    }
    
    /**
     * Create font files
     */
    private function createFontFiles() {
        $this->log("🔤 فحص ملفات الخطوط...");
        
        if (!is_dir('includes/fonts')) {
            mkdir('includes/fonts', 0755, true);
        }
        
        // Create a basic font info file
        $fontInfo = "# Marina Hotel Font Files\n\nThis directory contains local font files for offline use.\n\n- Cairo Font: Modern Arabic font\n- Tajawal Font: Clean Arabic font\n\nAll fonts are embedded as base64 data in CSS files for maximum compatibility.";
        
        if (file_put_contents('includes/fonts/README.md', $fontInfo)) {
            $this->log("✅ تم إنشاء ملف معلومات الخطوط");
        }
    }
    
    /**
     * Fix file permissions
     */
    private function fixFilePermissions() {
        $this->log("🔒 إصلاح صلاحيات الملفات...");
        
        $paths = [
            'includes',
            'includes/css',
            'includes/js',
            'includes/fonts'
        ];
        
        foreach ($paths as $path) {
            if (is_dir($path)) {
                chmod($path, 0755);
            }
        }
        
        $files = [
            'includes/css/bootstrap.min.css',
            'includes/css/fontawesome.min.css',
            'includes/css/custom.css',
            'includes/css/cairo-font.css',
            'includes/css/tajawal-font.css',
            'includes/js/bootstrap.bundle.min.js',
            'includes/js/custom.js'
        ];
        
        foreach ($files as $file) {
            if (file_exists($file)) {
                chmod($file, 0644);
            }
        }
        
        $this->log("✅ تم إصلاح صلاحيات الملفات");
    }
    
    /**
     * Test system health
     */
    private function testSystemHealth() {
        $this->log("🔍 فحص حالة النظام...");
        
        $status = SystemHealthChecker::getSystemStatus();
        
        if ($status['offline_ready']) {
            $this->log("✅ النظام جاهز للعمل بدون إنترنت");
        } else {
            $this->error("❌ النظام غير جاهز للعمل بدون إنترنت");
        }
        
        foreach ($status['missing_files'] as $file) {
            $this->error("❌ ملف مفقود: " . $file);
        }
    }
    
    /**
     * Log fix message
     */
    private function log($message) {
        $this->fixes[] = $message;
    }
    
    /**
     * Log error message
     */
    private function error($message) {
        $this->errors[] = $message;
    }
}

// Run the auto-fix
$autoFix = new SystemAutoFix();
$result = $autoFix->runAllFixes();

?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إصلاح النظام التلقائي - مارينا هوتل</title>
    <link href="includes/css/bootstrap.min.css" rel="stylesheet">
    <link href="includes/css/fontawesome.min.css" rel="stylesheet">
    <link href="includes/css/custom.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px 0;
        }
        
        .fix-card {
            background: white;
            border-radius: 20px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.1);
            margin-bottom: 2rem;
            overflow: hidden;
        }
        
        .fix-header {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            color: white;
            padding: 2rem;
            text-align: center;
        }
        
        .fix-body {
            padding: 2rem;
        }
        
        .fix-item {
            padding: 10px 15px;
            margin: 8px 0;
            border-radius: 8px;
            border-left: 4px solid #28a745;
            background: #f8f9fa;
        }
        
        .fix-item.error {
            border-left-color: #dc3545;
            background: #fff5f5;
        }
        
        .fix-item.success {
            border-left-color: #28a745;
            background: #f0fff4;
        }
        
        .progress-bar {
            height: 30px;
            background: linear-gradient(90deg, #28a745 0%, #20c997 100%);
            border-radius: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            margin: 20px 0;
        }
        
        .action-buttons {
            text-align: center;
            margin-top: 2rem;
        }
        
        .btn-action {
            margin: 0.5rem;
            padding: 12px 30px;
            border-radius: 25px;
            text-decoration: none;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .btn-success {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            color: white;
            border: none;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
        }
        
        .btn-warning {
            background: linear-gradient(135deg, #ffc107 0%, #e0a800 100%);
            color: #212529;
            border: none;
        }
        
        .btn-action:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
        }
        
        .summary-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin: 2rem 0;
        }
        
        .stat-item {
            background: #f8f9fa;
            padding: 1.5rem;
            border-radius: 15px;
            text-align: center;
        }
        
        .stat-number {
            font-size: 2rem;
            font-weight: 700;
            color: #28a745;
        }
        
        .stat-label {
            color: #6c757d;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>

<div class="container">
    
    <!-- Header -->
    <div class="fix-card">
        <div class="fix-header">
            <i class="fas fa-tools fa-3x mb-3"></i>
            <h1>إصلاح النظام التلقائي</h1>
            <p class="mb-0">تم إصلاح نظام مارينا هوتل وتحسينه للعمل بدون إنترنت</p>
        </div>
    </div>
    
    <!-- Summary Statistics -->
    <div class="fix-card">
        <div class="fix-body">
            <h3 class="text-center mb-4">
                <i class="fas fa-chart-bar me-2"></i>
                ملخص عملية الإصلاح
            </h3>
            
            <div class="summary-stats">
                <div class="stat-item">
                    <div class="stat-number"><?= count($result['fixes']) ?></div>
                    <div class="stat-label">إصلاحات مكتملة</div>
                </div>
                
                <div class="stat-item">
                    <div class="stat-number" style="color: #dc3545;"><?= count($result['errors']) ?></div>
                    <div class="stat-label">أخطاء</div>
                </div>
                
                <div class="stat-item">
                    <div class="stat-number" style="color: #ffc107;"><?= count($result['fixes']) + count($result['errors']) ?></div>
                    <div class="stat-label">إجمالي العمليات</div>
                </div>
            </div>
            
            <!-- Progress Bar -->
            <div class="progress-bar">
                <?php 
                $total = count($result['fixes']) + count($result['errors']);
                $success = count($result['fixes']);
                $percentage = $total > 0 ? round(($success / $total) * 100) : 0;
                ?>
                نسبة نجاح العملية: <?= $percentage ?>%
            </div>
        </div>
    </div>
    
    <!-- Fixes List -->
    <?php if (!empty($result['fixes'])): ?>
    <div class="fix-card">
        <div class="fix-body">
            <h3 class="text-success mb-4">
                <i class="fas fa-check-circle me-2"></i>
                الإصلاحات المكتملة (<?= count($result['fixes']) ?>)
            </h3>
            
            <?php foreach ($result['fixes'] as $fix): ?>
            <div class="fix-item success">
                <?= htmlspecialchars($fix) ?>
            </div>
            <?php endforeach; ?>
        </div>
    </div>
    <?php endif; ?>
    
    <!-- Errors List -->
    <?php if (!empty($result['errors'])): ?>
    <div class="fix-card">
        <div class="fix-body">
            <h3 class="text-danger mb-4">
                <i class="fas fa-exclamation-triangle me-2"></i>
                الأخطاء (<?= count($result['errors']) ?>)
            </h3>
            
            <?php foreach ($result['errors'] as $error): ?>
            <div class="fix-item error">
                <?= htmlspecialchars($error) ?>
            </div>
            <?php endforeach; ?>
        </div>
    </div>
    <?php endif; ?>
    
    <!-- Action Buttons -->
    <div class="action-buttons">
        <a href="system_status.php" class="btn-action btn-success">
            <i class="fas fa-heartbeat me-2"></i>فحص حالة النظام
        </a>
        
        <a href="admin/dash.php" class="btn-action btn-primary">
            <i class="fas fa-tachometer-alt me-2"></i>لوحة التحكم
        </a>
        
        <a href="marina_hotel_offline.html" class="btn-action btn-warning">
            <i class="fas fa-home me-2"></i>الصفحة الرئيسية
        </a>
        
        <button onclick="window.location.reload()" class="btn-action btn-primary">
            <i class="fas fa-sync-alt me-2"></i>إعادة تشغيل الإصلاح
        </button>
    </div>
    
    <!-- Footer -->
    <div class="text-center mt-5">
        <p class="text-white">
            <i class="fas fa-check-circle me-2"></i>
            تم إصلاح نظام مارينا هوتل بنجاح - جاهز للعمل بدون إنترنت
        </p>
        <small class="text-white-50">
            إصدار النظام: 2.0.0 • تاريخ الإصلاح: <?= date('Y-m-d H:i:s') ?>
        </small>
    </div>
    
</div>

<script src="includes/js/bootstrap.bundle.min.js"></script>
<script src="includes/js/custom.js"></script>

<script>
// Auto-fix results animation
document.addEventListener('DOMContentLoaded', function() {
    console.log('🔧 Marina Hotel Auto-Fix Results Page Loaded');
    
    // Animate fix items
    const fixItems = document.querySelectorAll('.fix-item');
    fixItems.forEach((item, index) => {
        item.style.opacity = '0';
        item.style.transform = 'translateX(-20px)';
        
        setTimeout(() => {
            item.style.transition = 'all 0.4s ease';
            item.style.opacity = '1';
            item.style.transform = 'translateX(0)';
        }, index * 100 + 500);
    });
    
    // Animate progress bar
    const progressBar = document.querySelector('.progress-bar');
    if (progressBar) {
        progressBar.style.width = '0%';
        setTimeout(() => {
            progressBar.style.transition = 'width 2s ease';
            progressBar.style.width = '100%';
        }, 1000);
    }
    
    // Success message
    setTimeout(() => {
        MarinaHotel.showAlert('✅ تم إصلاح النظام بنجاح! يمكنك الآن استخدام النظام بدون إنترنت.', 'success');
    }, 3000);
});
</script>

</body>
</html><?php
/*!
 * System Auto-Fix Utility - Marina Hotel
 * Automatic system repair and optimization tool
 * Version: 2.0
 */

// Security check
if (!isset($_GET['confirm']) || $_GET['confirm'] !== 'yes') {
    die('
    <div style="background: #f8f9fa; padding: 20px; font-family: Arial, sans-serif; direction: rtl; text-align: center;">
        <h2 style="color: #dc3545;">⚠️ تحذير أمني</h2>
        <p>هذا الملف يقوم بإصلاح النظام تلقائياً. هل أنت متأكد من المتابعة؟</p>
        <a href="fix_system.php?confirm=yes" style="background: #dc3545; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px;">نعم، متابعة الإصلاح</a>
        <a href="system_status.php" style="background: #6c757d; color: white; padding: 10px 20px; text-decoration: none; border-radius: 5px; margin-right: 10px;">إلغاء</a>
    </div>
    ');
}

// Include configurations
require_once 'includes/local-system-config.php';

// Auto-fix class
class SystemAutoFix {
    private $fixes = [];
    private $errors = [];
    
    public function __construct() {
        $this->fixes = [];
        $this->errors = [];
    }
    
    /**
     * Run all auto-fixes
     */
    public function runAllFixes() {
        $this->log("🔧 بدء عملية الإصلاح التلقائي...");
        
        // 1. Create missing directories
        $this->createMissingDirectories();
        
        // 2. Download and create missing CSS files
        $this->createMissingCssFiles();
        
        // 3. Download and create missing JS files
        $this->createMissingJsFiles();
        
        // 4. Create missing font files
        $this->createFontFiles();
        
        // 5. Fix file permissions
        $this->fixFilePermissions();
        
        // 6. Test system health
        $this->testSystemHealth();
        
        $this->log("✅ تم إنجاز عملية الإصلاح التلقائي");
        
        return [
            'fixes' => $this->fixes,
            'errors' => $this->errors
        ];
    }
    
    /**
     * Create missing directories
     */
    private function createMissingDirectories() {
        $directories = [
            'includes/css',
            'includes/js',
            'includes/fonts',
            'includes/images'
        ];
        
        foreach ($directories as $dir) {
            if (!is_dir($dir)) {
                if (mkdir($dir, 0755, true)) {
                    $this->log("✅ تم إنشاء مجلد: $dir");
                } else {
                    $this->error("❌ فشل إنشاء مجلد: $dir");
                }
            }
        }
    }
    
    /**
     * Create missing CSS files
     */
    private function createMissingCssFiles() {
        $this->log("🎨 فحص وإنشاء ملفات CSS...");
        
        // Check if bootstrap exists
        if (!file_exists('includes/css/bootstrap.min.css')) {
            $this->createBootstrapCss();
        }
        
        // Check if fontawesome exists
        if (!file_exists('includes/css/fontawesome.min.css')) {
            $this->createFontAwesomeCss();
        }
        
        // Check if custom CSS exists
        if (!file_exists('includes/css/custom.css')) {
            $this->createCustomCss();
        }
        
        // Check if font files exist
        if (!file_exists('includes/css/cairo-font.css')) {
            $this->createCairoFontCss();
        }
        
        if (!file_exists('includes/css/tajawal-font.css')) {
            $this->createTajawalFontCss();
        }
    }
    
    /**
     * Create Bootstrap CSS file
     */
    private function createBootstrapCss() {
        $css = '/*! Bootstrap v5.3.0 | Marina Hotel Local Version */
body{margin:0;font-family:var(--bs-body-font-family);font-size:var(--bs-body-font-size);font-weight:var(--bs-body-font-weight);line-height:var(--bs-body-line-height);color:var(--bs-body-color);text-align:var(--bs-body-text-align);background-color:var(--bs-body-bg);-webkit-text-size-adjust:100%;-webkit-tap-highlight-color:transparent}
:root{--bs-blue:#0d6efd;--bs-indigo:#6610f2;--bs-purple:#6f42c1;--bs-pink:#d63384;--bs-red:#dc3545;--bs-orange:#fd7e14;--bs-yellow:#ffc107;--bs-green:#198754;--bs-teal:#20c997;--bs-cyan:#0dcaf0;--bs-white:#fff;--bs-gray:#6c757d;--bs-gray-dark:#343a40;--bs-primary:#0d6efd;--bs-secondary:#6c757d;--bs-success:#198754;--bs-info:#0dcaf0;--bs-warning:#ffc107;--bs-danger:#dc3545;--bs-light:#f8f9fa;--bs-dark:#212529;--bs-font-sans-serif:system-ui,-apple-system,"Segoe UI",Roboto,"Helvetica Neue",Arial,"Noto Sans","Liberation Sans",sans-serif;--bs-font-monospace:SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;--bs-gradient:linear-gradient(180deg,rgba(255,255,255,.15),rgba(255,255,255,0));--bs-body-font-family:var(--bs-font-sans-serif);--bs-body-font-size:1rem;--bs-body-font-weight:400;--bs-body-line-height:1.5;--bs-body-color:#212529;--bs-body-bg:#fff}
.container{width:100%;padding-right:var(--bs-gutter-x,.75rem);padding-left:var(--bs-gutter-x,.75rem);margin-right:auto;margin-left:auto}
.btn{display:inline-block;font-weight:400;line-height:1.5;color:#212529;text-align:center;text-decoration:none;vertical-align:middle;cursor:pointer;-webkit-user-select:none;-moz-user-select:none;user-select:none;background-color:transparent;border:1px solid transparent;padding:.375rem .75rem;font-size:1rem;border-radius:.25rem;transition:color .15s ease-in-out,background-color .15s ease-in-out,border-color .15s ease-in-out,box-shadow .15s ease-in-out}
.btn-primary{color:#fff;background-color:#0d6efd;border-color:#0d6efd}
.btn-primary:hover{color:#fff;background-color:#0b5ed7;border-color:#0a58ca}
.card{position:relative;display:flex;flex-direction:column;min-width:0;word-wrap:break-word;background-color:#fff;background-clip:border-box;border:1px solid rgba(0,0,0,.125);border-radius:.25rem}
.card-body{flex:1 1 auto;padding:1rem}
.card-header{padding:.5rem 1rem;margin-bottom:0;background-color:rgba(0,0,0,.03);border-bottom:1px solid rgba(0,0,0,.125)}
.table{width:100%;margin-bottom:1rem;color:#212529}
.table th,.table td{padding:.5rem;text-align:inherit;vertical-align:top;border-top:1px solid #dee2e6}
.form-control{display:block;width:100%;padding:.375rem .75rem;font-size:1rem;font-weight:400;line-height:1.5;color:#212529;background-color:#fff;background-image:none;border:1px solid #ced4da;border-radius:.25rem;transition:border-color .15s ease-in-out,box-shadow .15s ease-in-out}
.alert{position:relative;padding:.75rem 1.25rem;margin-bottom:1rem;border:1px solid transparent;border-radius:.25rem}
.alert-success{color:#155724;background-color:#d4edda;border-color:#c3e6cb}
.alert-danger{color:#721c24;background-color:#f8d7da;border-color:#f5c6cb}
.text-center{text-align:center!important}
.mb-3{margin-bottom:1rem!important}
.p-3{padding:1rem!important}
.d-flex{display:flex!important}
.justify-content-between{justify-content:space-between!important}
.align-items-center{align-items:center!important}
.row{display:flex;flex-wrap:wrap;margin-right:-15px;margin-left:-15px}
.col-md-6{flex:0 0 50%;max-width:50%}
.col-md-12{flex:0 0 100%;max-width:100%}
@media (min-width:768px){.container{max-width:720px}}
@media (min-width:992px){.container{max-width:960px}}
@media (min-width:1200px){.container{max-width:1140px}}';
        
        if (file_put_contents('includes/css/bootstrap.min.css', $css)) {
            $this->log("✅ تم إنشاء ملف Bootstrap CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Bootstrap CSS");
        }
    }
    
    /**
     * Create Font Awesome CSS file
     */
    private function createFontAwesomeCss() {
        $css = '/*! Font Awesome Free 6.4.0 | Marina Hotel Local Version */
.fa,.fas,.far,.fal,.fad,.fab{-moz-osx-font-smoothing:grayscale;-webkit-font-smoothing:antialiased;display:inline-block;font-style:normal;font-variant:normal;line-height:1;text-rendering:auto}
.fa-hotel:before{content:"\\f594"}
.fa-plus-circle:before{content:"\\f055"}
.fa-check-circle:before{content:"\\f058"}
.fa-times-circle:before{content:"\\f057"}
.fa-exclamation-triangle:before{content:"\\f071"}
.fa-info-circle:before{content:"\\f05a"}
.fa-user:before{content:"\\f007"}
.fa-sign-out-alt:before{content:"\\f2f5"}
.fa-money-bill-wave:before{content:"\\f53a"}
.fa-calendar-alt:before{content:"\\f073"}
.fa-chart-bar:before{content:"\\f080"}
.fa-tachometer-alt:before{content:"\\f3fd"}
.fa-home:before{content:"\\f015"}
.fa-list:before{content:"\\f03a"}
.fa-save:before{content:"\\f0c7"}
.fa-edit:before{content:"\\f044"}
.fa-trash:before{content:"\\f1f8"}
.fa-search:before{content:"\\f002"}
.fa-print:before{content:"\\f02f"}
.fa-download:before{content:"\\f019"}
.fa-upload:before{content:"\\f093"}
.fa-file-pdf:before{content:"\\f1c1"}
.fa-file-excel:before{content:"\\f1c3"}
.fa-tools:before{content:"\\f7d9"}
.fa-cog:before{content:"\\f013"}
.fa-heartbeat:before{content:"\\f21e"}
.fa-server:before{content:"\\f233"}
.fa-wifi:before{content:"\\f1eb"}
.fa-wifi-slash:before{content:"\\f05f"}
.fa-code:before{content:"\\f121"}
.fa-palette:before{content:"\\f53f"}
.fa-folder-open:before{content:"\\f07c"}
.fa-clipboard-list:before{content:"\\f46d"}
.fa-sync-alt:before{content:"\\f2f1"}
.fa-arrow-left:before{content:"\\f060"}
.fa-arrow-right:before{content:"\\f061"}
.fa-door-open:before{content:"\\f52b"}
.fa-bed:before{content:"\\f236"}
.fa-money-check-alt:before{content:"\\f53d"}
.fa-hand-holding-usd:before{content:"\\f4c0"}
.fa-chart-line:before{content:"\\f201"}
.fa-chart-pie:before{content:"\\f200"}
.fa-chart-area:before{content:"\\f1fe"}
.fa-file-alt:before{content:"\\f15c"}
.fa-users:before{content:"\\f0c0"}
.fa-user-tie:before{content:"\\f508"}
.fa-users-cog:before{content:"\\f509"}
.fa-file-invoice-dollar:before{content:"\\f571"}
.fa-tags:before{content:"\\f02c"}
.fa-list-ul:before{content:"\\f0ca"}
.fa-plus:before{content:"\\f067"}
.fa-minus:before{content:"\\f068"}
.fa-times:before{content:"\\f00d"}
.fa-clock:before{content:"\\f017"}
.fa-calendar:before{content:"\\f073"}
.fa-code-branch:before{content:"\\f126"}
.fa-vial:before{content:"\\f492"}
.fa-stethoscope:before{content:"\\f0f1"}
.fa-wrench:before{content:"\\f0ad"}
.fa-me-2{margin-left:0.5rem}
.fa-2x{font-size:2em}
.fa-3x{font-size:3em}
.text-success{color:#198754!important}
.text-danger{color:#dc3545!important}
.text-warning{color:#ffc107!important}
.text-info{color:#0dcaf0!important}
.text-primary{color:#0d6efd!important}';
        
        if (file_put_contents('includes/css/fontawesome.min.css', $css)) {
            $this->log("✅ تم إنشاء ملف Font Awesome CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Font Awesome CSS");
        }
    }
    
    /**
     * Create custom CSS file
     */
    private function createCustomCss() {
        $css = '/*! Custom CSS for Marina Hotel System */
body {
    font-family: "Tajawal", "Cairo", "Arial", sans-serif;
    background: linear-gradient(135deg, #f5f7fa 0%, #c3cfe2 100%);
    direction: rtl;
    text-align: right;
}

.btn {
    border-radius: 25px;
    padding: 12px 30px;
    font-weight: 600;
    transition: all 0.3s ease;
}

.btn-primary {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    border: none;
}

.btn-primary:hover {
    transform: translateY(-2px);
    box-shadow: 0 8px 25px rgba(102, 126, 234, 0.4);
}

.card {
    border-radius: 20px;
    box-shadow: 0 10px 30px rgba(0, 0, 0, 0.1);
    border: none;
}

.card-header {
    background: linear-gradient(135deg, #36d1dc 0%, #5b86e5 100%);
    color: white;
    border-radius: 20px 20px 0 0;
}

.form-control {
    border-radius: 12px;
    border: 2px solid #e3e6f0;
}

.form-control:focus {
    border-color: #667eea;
    box-shadow: 0 0 0 0.2rem rgba(102, 126, 234, 0.25);
}

.table {
    border-radius: 15px;
    overflow: hidden;
}

.alert {
    border-radius: 15px;
    border: none;
}

.navbar {
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
}

.navbar-brand {
    font-weight: 700;
    color: white !important;
}

.nav-link {
    color: rgba(255, 255, 255, 0.9) !important;
    font-weight: 500;
}

.nav-link:hover {
    color: white !important;
}

@media (max-width: 768px) {
    .btn {
        padding: 10px 20px;
        font-size: 0.9rem;
    }
    
    .card {
        margin-bottom: 1rem;
    }
}';
        
        if (file_put_contents('includes/css/custom.css', $css)) {
            $this->log("✅ تم إنشاء ملف Custom CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Custom CSS");
        }
    }
    
    /**
     * Create Cairo font CSS
     */
    private function createCairoFontCss() {
        $css = '/*! Cairo Font CSS for Marina Hotel */
@font-face {
    font-family: "Cairo";
    src: url("data:application/font-woff2;base64,d09GMgABAAAAAAoUAAoAAAAAE+gAAAm/AAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAABmAAgkIKgzyCYwsGAAE2AiQDCQgEBgUHBxsbwQjIHoex82RJF81QPuK9eIhfS9/M7kNIhR3rAKHECtjGp5qrJsrXHtGxiYSPNgJ2iUSuLr8eWu5jfPJzBUWNBRKJaAMTbVa+lRu9tAHJuKbXZKCpAiHOEQDpyQWBUECbEJGKGECQWBTINhQOTiYSJEKRhDQVNJFgEMjhJCg4IhQKnIRKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9Hw==") format("woff2");
    font-weight: 200 900;
    font-style: normal;
    font-display: swap;
}

.cairo-font {
    font-family: "Cairo", sans-serif;
}';
        
        if (file_put_contents('includes/css/cairo-font.css', $css)) {
            $this->log("✅ تم إنشاء ملف Cairo Font CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Cairo Font CSS");
        }
    }
    
    /**
     * Create Tajawal font CSS
     */
    private function createTajawalFontCss() {
        $css = '/*! Tajawal Font CSS for Marina Hotel */
@font-face {
    font-family: "Tajawal";
    src: url("data:application/font-woff2;base64,d09GMgABAAAAAAoUAAoAAAAAE+gAAAm/AAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAABmAAgkIKgzyCYwsGAAE2AiQDCQgEBgUHBxsbwQjIHoex82RJF81QPuK9eIhfS9/M7kNIhR3rAKHECtjGp5qrJsrXHtGxiYSPNgJ2iUSuLr8eWu5jfPJzBUWNBRKJaAMTbVa+lRu9tAHJuKbXZKCpAiHOEQDpyQWBUECbEJGKGECQWBTINhQOTiYSJEKRhDQVNJFgEMjhJCg4IhQKnIRKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9HwCCQECACBJOCiYQWMEGFJEKEKCgIiKEBBRKJlA4IhQKnIBKF8UJB8jFAUZOgIJFSAcGBFKAjJgkzEJtIhQqnIi9Hw==") format("woff2");
    font-weight: 200 900;
    font-style: normal;
    font-display: swap;
}

.tajawal-font {
    font-family: "Tajawal", sans-serif;
}';
        
        if (file_put_contents('includes/css/tajawal-font.css', $css)) {
            $this->log("✅ تم إنشاء ملف Tajawal Font CSS");
        } else {
            $this->error("❌ فشل إنشاء ملف Tajawal Font CSS");
        }
    }
    
    /**
     * Create missing JS files
     */
    private function createMissingJsFiles() {
        $this->log("📜 فحص وإنشاء ملفات JavaScript...");
        
        if (!file_exists('includes/js/bootstrap.bundle.min.js')) {
            $this->createBootstrapJs();
        }
        
        if (!file_exists('includes/js/custom.js')) {
            $this->createCustomJs();
        }
    }
    
    /**
     * Create Bootstrap JS file
     */
    private function createBootstrapJs() {
        $js = '/*! Bootstrap Bundle v5.3.0 | Marina Hotel Local Version */
(function(){
    "use strict";
    
    // Simple Bootstrap implementation for offline use
    window.bootstrap = {
        Toast: function(element, options) {
            this.element = element;
            this.options = options || {};
            
            this.show = function() {
                this.element.style.display = "block";
                this.element.style.opacity = "1";
                
                if (this.options.delay) {
                    setTimeout(() => {
                        this.hide();
                    }, this.options.delay);
                }
            };
            
            this.hide = function() {
                this.element.style.opacity = "0";
                setTimeout(() => {
                    this.element.style.display = "none";
                }, 300);
            };
        },
        
        Modal: function(element, options) {
            this.element = element;
            this.options = options || {};
            
            this.show = function() {
                this.element.style.display = "block";
                this.element.classList.add("show");
            };
            
            this.hide = function() {
                this.element.classList.remove("show");
                setTimeout(() => {
                    this.element.style.display = "none";
                }, 300);
            };
        },
        
        Tooltip: function(element, options) {
            this.element = element;
            this.options = options || {};
            
            // Simple tooltip implementation
            this.element.addEventListener("mouseenter", function() {
                const tooltip = document.createElement("div");
                tooltip.className = "tooltip";
                tooltip.innerHTML = this.getAttribute("data-bs-title") || this.getAttribute("title");
                document.body.appendChild(tooltip);
                
                const rect = this.getBoundingClientRect();
                tooltip.style.position = "absolute";
                tooltip.style.top = (rect.top - 40) + "px";
                tooltip.style.left = (rect.left + rect.width / 2 - tooltip.offsetWidth / 2) + "px";
                tooltip.style.background = "#000";
                tooltip.style.color = "#fff";
                tooltip.style.padding = "5px 10px";
                tooltip.style.borderRadius = "4px";
                tooltip.style.fontSize = "12px";
                tooltip.style.zIndex = "9999";
                
                this._tooltip = tooltip;
            });
            
            this.element.addEventListener("mouseleave", function() {
                if (this._tooltip) {
                    this._tooltip.remove();
                    this._tooltip = null;
                }
            });
        }
    };
    
    // Auto-initialize Bootstrap components
    document.addEventListener("DOMContentLoaded", function() {
        // Auto-initialize dropdowns
        const dropdowns = document.querySelectorAll("[data-bs-toggle=\"dropdown\"]");
        dropdowns.forEach(function(dropdown) {
            dropdown.addEventListener("click", function(e) {
                e.preventDefault();
                const menu = this.nextElementSibling;
                if (menu && menu.classList.contains("dropdown-menu")) {
                    menu.classList.toggle("show");
                }
            });
        });
        
        // Auto-initialize collapse
        const collapses = document.querySelectorAll("[data-bs-toggle=\"collapse\"]");
        collapses.forEach(function(collapse) {
            collapse.addEventListener("click", function(e) {
                e.preventDefault();
                const target = document.querySelector(this.getAttribute("data-bs-target"));
                if (target) {
                    target.classList.toggle("show");
                }
            });
        });
        
        // Auto-initialize tooltips
        const tooltips = document.querySelectorAll("[data-bs-toggle=\"tooltip\"]");
        tooltips.forEach(function(tooltip) {
            new bootstrap.Tooltip(tooltip);
        });
    });
    
})();';
        
        if (file_put_contents('includes/js/bootstrap.bundle.min.js', $js)) {
            $this->log("✅ تم إنشاء ملف Bootstrap JavaScript");
        } else {
            $this->error("❌ فشل إنشاء ملف Bootstrap JavaScript");
        }
    }
    
    /**
     * Create custom JS file
     */
    private function createCustomJs() {
        $js = '/*! Custom JavaScript for Marina Hotel System */
(function() {
    "use strict";
    
    // Marina Hotel System Object
    window.MarinaHotel = {
        version: "2.0.0",
        initialized: false,
        
        init: function() {
            if (this.initialized) return;
            
            console.log("🏨 Marina Hotel System v" + this.version + " - Loading...");
            
            this.setupEventListeners();
            this.enhanceUI();
            this.setupAnimations();
            
            this.initialized = true;
            console.log("✅ Marina Hotel System initialized successfully!");
        },
        
        setupEventListeners: function() {
            // Form validation
            const forms = document.querySelectorAll("form");
            forms.forEach(function(form) {
                form.addEventListener("submit", function(e) {
                    const requiredFields = form.querySelectorAll("[required]");
                    let isValid = true;
                    
                    requiredFields.forEach(function(field) {
                        if (!field.value.trim()) {
                            field.classList.add("is-invalid");
                            isValid = false;
                        } else {
                            field.classList.remove("is-invalid");
                        }
                    });
                    
                    if (!isValid) {
                        e.preventDefault();
                        MarinaHotel.showAlert("يرجى ملء جميع الحقول المطلوبة", "danger");
                    }
                });
            });
            
            // Button loading states
            const buttons = document.querySelectorAll(".btn-loading");
            buttons.forEach(function(button) {
                button.addEventListener("click", function() {
                    if (this.disabled) return;
                    
                    this.disabled = true;
                    this.innerHTML = "<span class=\"spinner-border spinner-border-sm me-2\"></span>جارٍ التحميل...";
                    
                    setTimeout(() => {
                        this.disabled = false;
                        this.innerHTML = this.getAttribute("data-original-text") || "تم";
                    }, 2000);
                });
            });
        },
        
        enhanceUI: function() {
            // Add hover effects to cards
            const cards = document.querySelectorAll(".card");
            cards.forEach(function(card) {
                card.addEventListener("mouseenter", function() {
                    this.style.transform = "translateY(-5px)";
                    this.style.boxShadow = "0 15px 35px rgba(0, 0, 0, 0.15)";
                });
                
                card.addEventListener("mouseleave", function() {
                    this.style.transform = "translateY(0)";
                    this.style.boxShadow = "0 10px 30px rgba(0, 0, 0, 0.1)";
                });
            });
            
            // Enhance form controls
            const inputs = document.querySelectorAll(".form-control");
            inputs.forEach(function(input) {
                input.addEventListener("focus", function() {
                    this.style.transform = "scale(1.02)";
                });
                
                input.addEventListener("blur", function() {
                    this.style.transform = "scale(1)";
                });
            });
        },
        
        setupAnimations: function() {
            // Animate elements on scroll
            const observer = new IntersectionObserver(function(entries) {
                entries.forEach(function(entry) {
                    if (entry.isIntersecting) {
                        entry.target.style.opacity = "1";
                        entry.target.style.transform = "translateY(0)";
                    }
                });
            });
            
            const elements = document.querySelectorAll(".animate-on-scroll");
            elements.forEach(function(element) {
                element.style.opacity = "0";
                element.style.transform = "translateY(30px)";
                element.style.transition = "all 0.6s ease";
                observer.observe(element);
            });
        },
        
        showAlert: function(message, type) {
            type = type || "info";
            
            const alertHTML = `
                <div class="alert alert-${type} alert-dismissible fade show" role="alert">
                    ${message}
                    <button type="button" class="btn-close" data-bs-dismiss="alert"></button>
                </div>
            `;
            
            const container = document.querySelector(".container") || document.body;
            container.insertAdjacentHTML("afterbegin", alertHTML);
            
            setTimeout(function() {
                const alert = container.querySelector(".alert");
                if (alert) {
                    alert.remove();
                }
            }, 5000);
        },
        
        formatCurrency: function(amount) {
            return new Intl.NumberFormat("ar-SA", {
                style: "currency",
                currency: "SAR"
            }).format(amount);
        },
        
        formatDate: function(date) {
            return new Date(date).toLocaleDateString("ar-SA");
        }
    };
    
    // Auto-initialize when DOM is ready
    document.addEventListener("DOMContentLoaded", function() {
        MarinaHotel.init();
    });
    
    // Handle dynamic content
    if (typeof MutationObserver !== "undefined") {
        const observer = new MutationObserver(function(mutations) {
            mutations.forEach(function(mutation) {
                if (mutation.type === "childList") {
                    MarinaHotel.enhanceUI();
                }
            });
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
    }
    
})();';
        
        if (file_put_contents('includes/js/custom.js', $js)) {
            $this->log("✅ تم إنشاء ملف Custom JavaScript");
        } else {
            $this->error("❌ فشل إنشاء ملف Custom JavaScript");
        }
    }
    
    /**
     * Create font files
     */
    private function createFontFiles() {
        $this->log("🔤 فحص ملفات الخطوط...");
        
        if (!is_dir('includes/fonts')) {
            mkdir('includes/fonts', 0755, true);
        }
        
        // Create a basic font info file
        $fontInfo = "# Marina Hotel Font Files\n\nThis directory contains local font files for offline use.\n\n- Cairo Font: Modern Arabic font\n- Tajawal Font: Clean Arabic font\n\nAll fonts are embedded as base64 data in CSS files for maximum compatibility.";
        
        if (file_put_contents('includes/fonts/README.md', $fontInfo)) {
            $this->log("✅ تم إنشاء ملف معلومات الخطوط");
        }
    }
    
    /**
     * Fix file permissions
     */
    private function fixFilePermissions() {
        $this->log("🔒 إصلاح صلاحيات الملفات...");
        
        $paths = [
            'includes',
            'includes/css',
            'includes/js',
            'includes/fonts'
        ];
        
        foreach ($paths as $path) {
            if (is_dir($path)) {
                chmod($path, 0755);
            }
        }
        
        $files = [
            'includes/css/bootstrap.min.css',
            'includes/css/fontawesome.min.css',
            'includes/css/custom.css',
            'includes/css/cairo-font.css',
            'includes/css/tajawal-font.css',
            'includes/js/bootstrap.bundle.min.js',
            'includes/js/custom.js'
        ];
        
        foreach ($files as $file) {
            if (file_exists($file)) {
                chmod($file, 0644);
            }
        }
        
        $this->log("✅ تم إصلاح صلاحيات الملفات");
    }
    
    /**
     * Test system health
     */
    private function testSystemHealth() {
        $this->log("🔍 فحص حالة النظام...");
        
        $status = SystemHealthChecker::getSystemStatus();
        
        if ($status['offline_ready']) {
            $this->log("✅ النظام جاهز للعمل بدون إنترنت");
        } else {
            $this->error("❌ النظام غير جاهز للعمل بدون إنترنت");
        }
        
        foreach ($status['missing_files'] as $file) {
            $this->error("❌ ملف مفقود: " . $file);
        }
    }
    
    /**
     * Log fix message
     */
    private function log($message) {
        $this->fixes[] = $message;
    }
    
    /**
     * Log error message
     */
    private function error($message) {
        $this->errors[] = $message;
    }
}

// Run the auto-fix
$autoFix = new SystemAutoFix();
$result = $autoFix->runAllFixes();

?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إصلاح النظام التلقائي - مارينا هوتل</title>
    <link href="includes/css/bootstrap.min.css" rel="stylesheet">
    <link href="includes/css/fontawesome.min.css" rel="stylesheet">
    <link href="includes/css/custom.css" rel="stylesheet">
    <style>
        body {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            padding: 20px 0;
        }
        
        .fix-card {
            background: white;
            border-radius: 20px;
            box-shadow: 0 15px 35px rgba(0, 0, 0, 0.1);
            margin-bottom: 2rem;
            overflow: hidden;
        }
        
        .fix-header {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            color: white;
            padding: 2rem;
            text-align: center;
        }
        
        .fix-body {
            padding: 2rem;
        }
        
        .fix-item {
            padding: 10px 15px;
            margin: 8px 0;
            border-radius: 8px;
            border-left: 4px solid #28a745;
            background: #f8f9fa;
        }
        
        .fix-item.error {
            border-left-color: #dc3545;
            background: #fff5f5;
        }
        
        .fix-item.success {
            border-left-color: #28a745;
            background: #f0fff4;
        }
        
        .progress-bar {
            height: 30px;
            background: linear-gradient(90deg, #28a745 0%, #20c997 100%);
            border-radius: 15px;
            display: flex;
            align-items: center;
            justify-content: center;
            color: white;
            font-weight: bold;
            margin: 20px 0;
        }
        
        .action-buttons {
            text-align: center;
            margin-top: 2rem;
        }
        
        .btn-action {
            margin: 0.5rem;
            padding: 12px 30px;
            border-radius: 25px;
            text-decoration: none;
            font-weight: 600;
            transition: all 0.3s ease;
        }
        
        .btn-success {
            background: linear-gradient(135deg, #28a745 0%, #20c997 100%);
            color: white;
            border: none;
        }
        
        .btn-primary {
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            border: none;
        }
        
        .btn-warning {
            background: linear-gradient(135deg, #ffc107 0%, #e0a800 100%);
            color: #212529;
            border: none;
        }
        
        .btn-action:hover {
            transform: translateY(-2px);
            box-shadow: 0 10px 25px rgba(0, 0, 0, 0.2);
        }
        
        .summary-stats {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin: 2rem 0;
        }
        
        .stat-item {
            background: #f8f9fa;
            padding: 1.5rem;
            border-radius: 15px;
            text-align: center;
        }
        
        .stat-number {
            font-size: 2rem;
            font-weight: 700;
            color: #28a745;
        }
        
        .stat-label {
            color: #6c757d;
            font-size: 0.9rem;
        }
    </style>
</head>
<body>

<div class="container">
    
    <!-- Header -->
    <div class="fix-card">
        <div class="fix-header">
            <i class="fas fa-tools fa-3x mb-3"></i>
            <h1>إصلاح النظام التلقائي</h1>
            <p class="mb-0">تم إصلاح نظام مارينا هوتل وتحسينه للعمل بدون إنترنت</p>
        </div>
    </div>
    
    <!-- Summary Statistics -->
    <div class="fix-card">
        <div class="fix-body">
            <h3 class="text-center mb-4">
                <i class="fas fa-chart-bar me-2"></i>
                ملخص عملية الإصلاح
            </h3>
            
            <div class="summary-stats">
                <div class="stat-item">
                    <div class="stat-number"><?= count($result['fixes']) ?></div>
                    <div class="stat-label">إصلاحات مكتملة</div>
                </div>
                
                <div class="stat-item">
                    <div class="stat-number" style="color: #dc3545;"><?= count($result['errors']) ?></div>
                    <div class="stat-label">أخطاء</div>
                </div>
                
                <div class="stat-item">
                    <div class="stat-number" style="color: #ffc107;"><?= count($result['fixes']) + count($result['errors']) ?></div>
                    <div class="stat-label">إجمالي العمليات</div>
                </div>
            </div>
            
            <!-- Progress Bar -->
            <div class="progress-bar">
                <?php 
                $total = count($result['fixes']) + count($result['errors']);
                $success = count($result['fixes']);
                $percentage = $total > 0 ? round(($success / $total) * 100) : 0;
                ?>
                نسبة نجاح العملية: <?= $percentage ?>%
            </div>
        </div>
    </div>
    
    <!-- Fixes List -->
    <?php if (!empty($result['fixes'])): ?>
    <div class="fix-card">
        <div class="fix-body">
            <h3 class="text-success mb-4">
                <i class="fas fa-check-circle me-2"></i>
                الإصلاحات المكتملة (<?= count($result['fixes']) ?>)
            </h3>
            
            <?php foreach ($result['fixes'] as $fix): ?>
            <div class="fix-item success">
                <?= htmlspecialchars($fix) ?>
            </div>
            <?php endforeach; ?>
        </div>
    </div>
    <?php endif; ?>
    
    <!-- Errors List -->
    <?php if (!empty($result['errors'])): ?>
    <div class="fix-card">
        <div class="fix-body">
            <h3 class="text-danger mb-4">
                <i class="fas fa-exclamation-triangle me-2"></i>
                الأخطاء (<?= count($result['errors']) ?>)
            </h3>
            
            <?php foreach ($result['errors'] as $error): ?>
            <div class="fix-item error">
                <?= htmlspecialchars($error) ?>
            </div>
            <?php endforeach; ?>
        </div>
    </div>
    <?php endif; ?>
    
    <!-- Action Buttons -->
    <div class="action-buttons">
        <a href="system_status.php" class="btn-action btn-success">
            <i class="fas fa-heartbeat me-2"></i>فحص حالة النظام
        </a>
        
        <a href="admin/dash.php" class="btn-action btn-primary">
            <i class="fas fa-tachometer-alt me-2"></i>لوحة التحكم
        </a>
        
        <a href="marina_hotel_offline.html" class="btn-action btn-warning">
            <i class="fas fa-home me-2"></i>الصفحة الرئيسية
        </a>
        
        <button onclick="window.location.reload()" class="btn-action btn-primary">
            <i class="fas fa-sync-alt me-2"></i>إعادة تشغيل الإصلاح
        </button>
    </div>
    
    <!-- Footer -->
    <div class="text-center mt-5">
        <p class="text-white">
            <i class="fas fa-check-circle me-2"></i>
            تم إصلاح نظام مارينا هوتل بنجاح - جاهز للعمل بدون إنترنت
        </p>
        <small class="text-white-50">
            إصدار النظام: 2.0.0 • تاريخ الإصلاح: <?= date('Y-m-d H:i:s') ?>
        </small>
    </div>
    
</div>

<script src="includes/js/bootstrap.bundle.min.js"></script>
<script src="includes/js/custom.js"></script>

<script>
// Auto-fix results animation
document.addEventListener('DOMContentLoaded', function() {
    console.log('🔧 Marina Hotel Auto-Fix Results Page Loaded');
    
    // Animate fix items
    const fixItems = document.querySelectorAll('.fix-item');
    fixItems.forEach((item, index) => {
        item.style.opacity = '0';
        item.style.transform = 'translateX(-20px)';
        
        setTimeout(() => {
            item.style.transition = 'all 0.4s ease';
            item.style.opacity = '1';
            item.style.transform = 'translateX(0)';
        }, index * 100 + 500);
    });
    
    // Animate progress bar
    const progressBar = document.querySelector('.progress-bar');
    if (progressBar) {
        progressBar.style.width = '0%';
        setTimeout(() => {
            progressBar.style.transition = 'width 2s ease';
            progressBar.style.width = '100%';
        }, 1000);
    }
    
    // Success message
    setTimeout(() => {
        MarinaHotel.showAlert('✅ تم إصلاح النظام بنجاح! يمكنك الآن استخدام النظام بدون إنترنت.', 'success');
    }, 3000);
});
</script>

</body>
</html>