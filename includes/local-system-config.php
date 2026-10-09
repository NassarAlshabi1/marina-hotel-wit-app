<?php
/*!
 * Local System Configuration - Marina Hotel
 * Configuration for offline-first system
 * Version: 2.0
 */

// Prevent direct access
if (!defined('MARINA_HOTEL_SYSTEM')) {
    define('MARINA_HOTEL_SYSTEM', true);
}

// ===== System Information =====
define('SYSTEM_NAME', 'نظام إدارة مارينا هوتل');
define('SYSTEM_VERSION', '2.0.0');
define('SYSTEM_TYPE', 'OFFLINE_FIRST');
define('LAST_UPDATED', '2024-12-24');

// ===== Local Assets Configuration =====
class LocalAssetsConfig {
    
    // Base paths for local assets
    const CSS_PATH = 'includes/css/';
    const JS_PATH = 'includes/js/';
    const FONTS_PATH = 'includes/fonts/';
    const IMAGES_PATH = 'includes/images/';
    
    // CSS Files mapping
    public static $cssFiles = [
        'bootstrap' => 'bootstrap.min.css',
        'fontawesome' => 'fontawesome.min.css',
        'cairo_font' => 'cairo-font.css',
        'tajawal_font' => 'tajawal-font.css',
        'custom' => 'custom.css',
        'dashboard' => 'dashboard.css'
    ];
    
    // JavaScript Files mapping
    public static $jsFiles = [
        'bootstrap' => 'bootstrap.bundle.min.js',
        'custom' => 'custom.js',
        'dashboard' => 'dashboard.js'
    ];
    
    // Font families available locally
    public static $fontFamilies = [
        'arabic_primary' => '"Tajawal", "Cairo", "Tahoma", sans-serif',
        'arabic_secondary' => '"Cairo", "Tajawal", "Arial", sans-serif',
        'latin_fallback' => '"Segoe UI", "Roboto", "Arial", sans-serif'
    ];
    
    /**
     * Get CSS file path
     */
    public static function getCssPath($name) {
        if (isset(self::$cssFiles[$name])) {
            return self::CSS_PATH . self::$cssFiles[$name];
        }
        return false;
    }
    
    /**
     * Get JavaScript file path
     */
    public static function getJsPath($name) {
        if (isset(self::$jsFiles[$name])) {
            return self::JS_PATH . self::$jsFiles[$name];
        }
        return false;
    }
    
    /**
     * Check if file exists locally
     */
    public static function fileExists($path) {
        $fullPath = __DIR__ . '/../' . $path;
        return file_exists($fullPath);
    }
    
    /**
     * Get all required CSS files for a page
     */
    public static function getRequiredCss($pageType = 'default') {
        $baseCss = [
            'bootstrap',
            'fontawesome', 
            'tajawal_font',
            'custom'
        ];
        
        switch ($pageType) {
            case 'dashboard':
                $baseCss[] = 'dashboard';
                break;
            case 'payment':
                $baseCss[] = 'cairo_font';
                break;
        }
        
        return $baseCss;
    }
    
    /**
     * Get all required JavaScript files for a page
     */
    public static function getRequiredJs($pageType = 'default') {
        $baseJs = [
            'bootstrap',
            'custom'
        ];
        
        switch ($pageType) {
            case 'dashboard':
                $baseJs[] = 'dashboard';
                break;
        }
        
        return $baseJs;
    }
    
    /**
     * Generate CSS includes HTML
     */
    public static function generateCssIncludes($pageType = 'default', $basePath = '') {
        $cssFiles = self::getRequiredCss($pageType);
        $html = "<!-- Local CSS Files -->\n";
        
        foreach ($cssFiles as $cssName) {
            $cssPath = self::getCssPath($cssName);
            if ($cssPath) {
                $fullPath = $basePath . $cssPath;
                $html .= "    <link href=\"{$fullPath}\" rel=\"stylesheet\">\n";
            }
        }
        
        return $html;
    }
    
    /**
     * Generate JavaScript includes HTML
     */
    public static function generateJsIncludes($pageType = 'default', $basePath = '') {
        $jsFiles = self::getRequiredJs($pageType);
        $html = "<!-- Local JavaScript Files -->\n";
        
        foreach ($jsFiles as $jsName) {
            $jsPath = self::getJsPath($jsName);
            if ($jsPath) {
                $fullPath = $basePath . $jsPath;
                $html .= "    <script src=\"{$fullPath}\"></script>\n";
            }
        }
        
        return $html;
    }
}

// ===== System Health Checker =====
class SystemHealthChecker {
    
    /**
     * Check if all required local files exist
     */
    public static function checkLocalFiles() {
        $results = [
            'css' => [],
            'js' => [],
            'missing' => [],
            'status' => 'ok'
        ];
        
        // Check CSS files
        foreach (LocalAssetsConfig::$cssFiles as $name => $file) {
            $path = LocalAssetsConfig::CSS_PATH . $file;
            if (LocalAssetsConfig::fileExists($path)) {
                $results['css'][$name] = 'exists';
            } else {
                $results['css'][$name] = 'missing';
                $results['missing'][] = $path;
                $results['status'] = 'error';
            }
        }
        
        // Check JavaScript files
        foreach (LocalAssetsConfig::$jsFiles as $name => $file) {
            $path = LocalAssetsConfig::JS_PATH . $file;
            if (LocalAssetsConfig::fileExists($path)) {
                $results['js'][$name] = 'exists';
            } else {
                $results['js'][$name] = 'missing';
                $results['missing'][] = $path;
                $results['status'] = 'error';
            }
        }
        
        return $results;
    }
    
    /**
     * Get system status
     */
    public static function getSystemStatus() {
        $fileCheck = self::checkLocalFiles();
        
        return [
            'system_name' => SYSTEM_NAME,
            'version' => SYSTEM_VERSION,
            'type' => SYSTEM_TYPE,
            'last_updated' => LAST_UPDATED,
            'files_status' => $fileCheck['status'],
            'missing_files' => $fileCheck['missing'],
            'total_css_files' => count(LocalAssetsConfig::$cssFiles),
            'total_js_files' => count(LocalAssetsConfig::$jsFiles),
            'offline_ready' => $fileCheck['status'] === 'ok'
        ];
    }
    
    /**
     * Generate system report
     */
    public static function generateReport() {
        $status = self::getSystemStatus();
        $fileCheck = self::checkLocalFiles();
        
        $report = "=== تقرير حالة النظام المحلي ===\n";
        $report .= "اسم النظام: {$status['system_name']}\n";
        $report .= "الإصدار: {$status['version']}\n";
        $report .= "النوع: {$status['type']}\n";
        $report .= "آخر تحديث: {$status['last_updated']}\n\n";
        
        $report .= "=== حالة الملفات ===\n";
        $report .= "ملفات CSS: {$status['total_css_files']}\n";
        $report .= "ملفات JavaScript: {$status['total_js_files']}\n";
        $report .= "جاهز للعمل بدون إنترنت: " . ($status['offline_ready'] ? 'نعم' : 'لا') . "\n\n";
        
        if (!empty($status['missing_files'])) {
            $report .= "=== الملفات المفقودة ===\n";
            foreach ($status['missing_files'] as $file) {
                $report .= "- {$file}\n";
            }
        }
        
        $report .= "\n=== تفاصيل ملفات CSS ===\n";
        foreach ($fileCheck['css'] as $name => $status_file) {
            $icon = $status_file === 'exists' ? '✅' : '❌';
            $report .= "{$icon} {$name}: {$status_file}\n";
        }
        
        $report .= "\n=== تفاصيل ملفات JavaScript ===\n";
        foreach ($fileCheck['js'] as $name => $status_file) {
            $icon = $status_file === 'exists' ? '✅' : '❌';
            $report .= "{$icon} {$name}: {$status_file}\n";
        }
        
        return $report;
    }
}

// ===== Page Helper Functions =====
class PageHelper {
    
    /**
     * Get page type based on current script
     */
    public static function getPageType() {
        $scriptName = basename($_SERVER['SCRIPT_NAME'], '.php');
        
        $pageTypes = [
            'dash' => 'dashboard',
            'dashboard' => 'dashboard',
            'payment' => 'payment',
            'payment_premium' => 'payment',
            'payment500' => 'payment',
            'add' => 'form',
            'add2' => 'form',
            'edit' => 'form',
            'list' => 'table',
            'reports' => 'reports'
        ];
        
        return isset($pageTypes[$scriptName]) ? $pageTypes[$scriptName] : 'default';
    }
    
    /**
     * Generate page-specific includes
     */
    public static function generatePageIncludes($basePath = '') {
        $pageType = self::getPageType();
        
        $html = "<!-- === Marina Hotel Local System === -->\n";
        $html .= "<!-- Page Type: {$pageType} -->\n";
        $html .= "<!-- System Version: " . SYSTEM_VERSION . " -->\n\n";
        
        $html .= LocalAssetsConfig::generateCssIncludes($pageType, $basePath);
        
        return $html;
    }
    
    /**
     * Generate page-specific JavaScript includes
     */
    public static function generatePageJsIncludes($basePath = '') {
        $pageType = self::getPageType();
        
        $html = "<!-- === Marina Hotel Local JavaScript === -->\n";
        $html .= LocalAssetsConfig::generateJsIncludes($pageType, $basePath);
        
        return $html;
    }
}

// ===== Utility Functions =====

/**
 * Check if system is running locally
 */
function isLocalSystem() {
    $localHosts = ['localhost', '127.0.0.1', '::1'];
    return in_array($_SERVER['HTTP_HOST'], $localHosts) || 
           strpos($_SERVER['HTTP_HOST'], '.local') !== false;
}

/**
 * Get system info as JSON
 */
function getSystemInfoJson() {
    return json_encode(SystemHealthChecker::getSystemStatus(), JSON_UNESCAPED_UNICODE | JSON_PRETTY_PRINT);
}

/**
 * Log system events
 */
function logSystemEvent($event, $details = '') {
    if (defined('MARINA_HOTEL_DEBUG') && MARINA_HOTEL_DEBUG) {
        $timestamp = date('Y-m-d H:i:s');
        $logEntry = "[{$timestamp}] {$event}";
        if ($details) {
            $logEntry .= " - {$details}";
        }
        error_log($logEntry);
    }
}

// ===== Auto-initialization =====
if (isLocalSystem()) {
    // Log system initialization
    logSystemEvent('Local system initialized', 'Version: ' . SYSTEM_VERSION);
    
    // Set debug mode for local development
    if (!defined('MARINA_HOTEL_DEBUG')) {
        define('MARINA_HOTEL_DEBUG', true);
    }
}

// ===== Export Configuration =====
$GLOBALS['MARINA_LOCAL_CONFIG'] = [
    'assets' => LocalAssetsConfig::class,
    'health' => SystemHealthChecker::class,
    'page' => PageHelper::class,
    'version' => SYSTEM_VERSION,
    'type' => SYSTEM_TYPE
];
?>