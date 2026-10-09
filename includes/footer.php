        </main>
    </div>

    <!-- Bootstrap JS -->
    <script src="<?= $base_path ?>includes/js/bootstrap.bundle.min.js"></script>

    <!-- تحميل JavaScript المحسن -->
    <script src="<?= $base_path ?>assets/js/enhanced-ui.js"></script>

    <!-- التنقل والتفاعل -->
    <script>
        // Mobile menu toggle
        document.getElementById('mobileToggle').addEventListener('click', function() {
            const nav = document.getElementById('mainNav');
            nav.classList.toggle('active');

            // Change icon
            const icon = this.querySelector('i');
            if (nav.classList.contains('active')) {
                icon.classList.remove('fa-bars');
                icon.classList.add('fa-times');
            } else {
                icon.classList.remove('fa-times');
                icon.classList.add('fa-bars');
            }
        });

        // Close mobile menu when clicking outside
        document.addEventListener('click', function(e) {
            const nav = document.getElementById('mainNav');
            const toggle = document.getElementById('mobileToggle');

            if (!nav.contains(e.target) && !toggle.contains(e.target)) {
                nav.classList.remove('active');
                const icon = toggle.querySelector('i');
                icon.classList.remove('fa-times');
                icon.classList.add('fa-bars');
            }
        });

        // Handle dropdown menus - prevent parent link navigation
        document.querySelectorAll('.nav-item.dropdown > .nav-link').forEach(link => {
            link.addEventListener('click', function(e) {
                // On mobile, always allow click to open dropdown
                if (window.innerWidth <= 768) {
                    return;
                }

                // Check if click was on the chevron icon
                const chevron = this.querySelector('.fa-chevron-down');
                const clickedChevron = chevron && chevron.contains(e.target);

                // If not chevron and dropdown is closed, prevent default
                if (!clickedChevron && !this.parentElement.classList.contains('show')) {
                    e.preventDefault();
                    e.stopPropagation();
                }
            });
        });

        // Highlight active page
        document.addEventListener('DOMContentLoaded', function() {
            const currentPath = window.location.pathname;
            const navLinks = document.querySelectorAll('.nav-link, .sub-nav-link');

            navLinks.forEach(link => {
                if (link.getAttribute('href') && currentPath.includes(link.getAttribute('href'))) {
                    link.classList.add('active');

                    // Also activate parent dropdown if this is a sub-item
                    if (link.classList.contains('sub-nav-link')) {
                        const parentItem = link.closest('.nav-item');
                        if (parentItem) {
                            parentItem.querySelector('.nav-link').classList.add('active');
                        }
                    }
                }
            });

            // Initialize Bootstrap dropdowns
            const dropdowns = document.querySelectorAll('.dropdown');
            dropdowns.forEach(dropdown => {
                dropdown.addEventListener('hide.bs.dropdown', function() {
                    this.querySelector('.nav-link').classList.remove('active');
                });

                dropdown.addEventListener('show.bs.dropdown', function() {
                    this.querySelector('.nav-link').classList.add('active');
                });
            });
        });
    </script>

    <!-- تحسينات إضافية للأداء -->
    <script>
        // تحسين الصور الكسولة
        if ('loading' in HTMLImageElement.prototype) {
            const images = document.querySelectorAll('img[data-src]');
            images.forEach(img => {
                img.src = img.dataset.src;
            });
        }

        // تحسين الروابط الخارجية
        document.addEventListener('DOMContentLoaded', function() {
            const externalLinks = document.querySelectorAll('a[href^="http"]:not([href*="' + window.location.hostname + '"])');
            externalLinks.forEach(link => {
                link.setAttribute('target', '_blank');
                link.setAttribute('rel', 'noopener noreferrer');
            });
        });

        // مراقبة الأداء
        if ('performance' in window) {
            window.addEventListener('load', function() {
                setTimeout(function() {
                    const perfData = performance.getEntriesByType('navigation')[0];
                    if (perfData && perfData.loadEventEnd > 3000) {
                        console.warn('تحذير: وقت تحميل الصفحة بطيء (' + Math.round(perfData.loadEventEnd) + 'ms)');
                    }
                }, 1000);
            });
        }
    </script>
</body>
</html>
