<!-- تحميل JavaScript المحسن -->
    <script src="<?= BASE_URL ?>assets/js/enhanced-ui.js"></script>
    
    <!-- Bootstrap JS محلي (إذا كان متوفراً) أو خارجي كـ fallback -->
    <script>
        // تحميل Bootstrap JS إذا لم يكن متوفراً محلياً
        if (typeof bootstrap === 'undefined') {
            const script = document.createElement('script');
            script.src = 'https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/js/bootstrap.bundle.min.js';
            document.head.appendChild(script);
        }
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
