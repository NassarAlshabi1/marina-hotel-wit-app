<?php
/**
 * ملف تحسين الأداء
 * يحتوي على دوال وإعدادات لتحسين أداء النظام
 */

/**
 * فئة لإدارة التخزين المؤقت
 */
class CacheManager {
    private $cache_dir;
    private $default_ttl = 3600; // ساعة واحدة
    
    public function __construct($cache_dir = null) {
        $this->cache_dir = $cache_dir ?: (ROOT_PATH . '/cache');
        
        // إنشاء مجلد التخزين المؤقت إذا لم يكن موجوداً
        if (!is_dir($this->cache_dir)) {
            mkdir($this->cache_dir, 0755, true);
        }
    }
    
    /**
     * حفظ البيانات في التخزين المؤقت
     */
    public function set($key, $data, $ttl = null) {
        $ttl = $ttl ?: $this->default_ttl;
        $cache_file = $this->getCacheFile($key);
        
        $cache_data = [
            'data' => $data,
            'expires' => time() + $ttl,
            'created' => time()
        ];
        
        return file_put_contents($cache_file, serialize($cache_data)) !== false;
    }
    
    /**
     * استرجاع البيانات من التخزين المؤقت
     */
    public function get($key) {
        $cache_file = $this->getCacheFile($key);
        
        if (!file_exists($cache_file)) {
            return null;
        }
        
        $cache_data = unserialize(file_get_contents($cache_file));
        
        // التحقق من انتهاء الصلاحية
        if ($cache_data['expires'] < time()) {
            $this->delete($key);
            return null;
        }
        
        return $cache_data['data'];
    }
    
    /**
     * حذف عنصر من التخزين المؤقت
     */
    public function delete($key) {
        $cache_file = $this->getCacheFile($key);
        
        if (file_exists($cache_file)) {
            return unlink($cache_file);
        }
        
        return true;
    }
    
    /**
     * مسح جميع ملفات التخزين المؤقت
     */
    public function clear() {
        $files = glob($this->cache_dir . '/*.cache');
        $cleared = 0;
        
        foreach ($files as $file) {
            if (unlink($file)) {
                $cleared++;
            }
        }
        
        return $cleared;
    }
    
    /**
     * الحصول على مسار ملف التخزين المؤقت
     */
    private function getCacheFile($key) {
        $safe_key = md5($key);
        return $this->cache_dir . '/' . $safe_key . '.cache';
    }
}

/**
 * فئة لتحسين استعلامات قاعدة البيانات
 */
class QueryOptimizer {
    private $conn;
    private $cache;
    private $query_log = [];
    
    public function __construct($connection) {
        $this->conn = $connection;
        $this->cache = new CacheManager();
    }
    
    /**
     * تنفيذ استعلام محسن مع تخزين مؤقت
     */
    public function query($sql, $params = [], $cache_key = null, $cache_ttl = 300) {
        $start_time = microtime(true);
        
        // إنشاء مفتاح تخزين مؤقت إذا لم يتم توفيره
        if ($cache_key === null) {
            $cache_key = 'query_' . md5($sql . serialize($params));
        }
        
        // محاولة الحصول على النتيجة من التخزين المؤقت
        if ($cache_ttl > 0) {
            $cached_result = $this->cache->get($cache_key);
            if ($cached_result !== null) {
                $this->logQuery($sql, microtime(true) - $start_time, true);
                return $cached_result;
            }
        }
        
        // تنفيذ الاستعلام
        try {
            if (empty($params)) {
                $result = $this->conn->query($sql);
            } else {
                $stmt = $this->conn->prepare($sql);
                if (!$stmt) {
                    throw new Exception("فشل في تحضير الاستعلام: " . $this->conn->error);
                }
                
                // ربط المعاملات
                if (!empty($params)) {
                    $types = str_repeat('s', count($params)); // افتراض أن جميع المعاملات نصوص
                    $stmt->bind_param($types, ...$params);
                }
                
                $stmt->execute();
                $result = $stmt->get_result();
                $stmt->close();
            }
            
            if (!$result) {
                throw new Exception("فشل في تنفيذ الاستعلام: " . $this->conn->error);
            }
            
            // تحويل النتيجة إلى مصفوفة
            $data = [];
            if ($result instanceof mysqli_result) {
                while ($row = $result->fetch_assoc()) {
                    $data[] = $row;
                }
                $result->free();
            }
            
            // حفظ النتيجة في التخزين المؤقت
            if ($cache_ttl > 0) {
                $this->cache->set($cache_key, $data, $cache_ttl);
            }
            
            $execution_time = microtime(true) - $start_time;
            $this->logQuery($sql, $execution_time, false);
            
            return $data;
            
        } catch (Exception $e) {
            $execution_time = microtime(true) - $start_time;
            $this->logQuery($sql, $execution_time, false, $e->getMessage());
            throw $e;
        }
    }
    
    /**
     * تسجيل الاستعلامات لمراقبة الأداء
     */
    private function logQuery($sql, $execution_time, $from_cache = false, $error = null) {
        $this->query_log[] = [
            'sql' => $sql,
            'execution_time' => $execution_time,
            'from_cache' => $from_cache,
            'error' => $error,
            'timestamp' => microtime(true)
        ];
        
        // تسجيل الاستعلامات البطيئة
        if ($execution_time > 1.0 && !$from_cache) {
            error_log("استعلام بطيء ({$execution_time}s): " . substr($sql, 0, 100));
        }
    }
    
    /**
     * الحصول على إحصائيات الاستعلامات
     */
    public function getQueryStats() {
        $total_queries = count($this->query_log);
        $cached_queries = array_filter($this->query_log, function($log) {
            return $log['from_cache'];
        });
        $slow_queries = array_filter($this->query_log, function($log) {
            return $log['execution_time'] > 1.0 && !$log['from_cache'];
        });
        $failed_queries = array_filter($this->query_log, function($log) {
            return $log['error'] !== null;
        });
        
        $total_time = array_sum(array_column($this->query_log, 'execution_time'));
        $avg_time = $total_queries > 0 ? $total_time / $total_queries : 0;
        
        return [
            'total_queries' => $total_queries,
            'cached_queries' => count($cached_queries),
            'slow_queries' => count($slow_queries),
            'failed_queries' => count($failed_queries),
            'total_execution_time' => $total_time,
            'average_execution_time' => $avg_time,
            'cache_hit_rate' => $total_queries > 0 ? (count($cached_queries) / $total_queries) * 100 : 0
        ];
    }
    
    /**
     * مسح سجل الاستعلامات
     */
    public function clearQueryLog() {
        $this->query_log = [];
    }
}

/**
 * دوال مساعدة للأداء
 */

/**
 * قياس وقت تنفيذ دالة
 */
function measure_execution_time($callback, $label = 'Operation') {
    $start_time = microtime(true);
    $result = $callback();
    $execution_time = microtime(true) - $start_time;
    
    if (DEBUG_MODE) {
        error_log("$label took {$execution_time}s to execute");
    }
    
    return ['result' => $result, 'execution_time' => $execution_time];
}

/**
 * ضغط المحتوى لتحسين سرعة التحميل
 */
function enable_compression() {
    if (!ob_get_level() && extension_loaded('zlib')) {
        ob_start('ob_gzhandler');
    }
}

/**
 * تعيين رؤوس التخزين المؤقت
 */
function set_cache_headers($max_age = 3600) {
    $expires = gmdate('D, d M Y H:i:s', time() + $max_age) . ' GMT';
    
    header("Cache-Control: public, max-age=$max_age");
    header("Expires: $expires");
    header("Last-Modified: " . gmdate('D, d M Y H:i:s', filemtime(__FILE__)) . ' GMT');
}

/**
 * تحسين الصور
 */
function optimize_image($source_path, $destination_path, $quality = 85) {
    $image_info = getimagesize($source_path);
    if (!$image_info) {
        return false;
    }
    
    $mime_type = $image_info['mime'];
    
    switch ($mime_type) {
        case 'image/jpeg':
            $image = imagecreatefromjpeg($source_path);
            break;
        case 'image/png':
            $image = imagecreatefrompng($source_path);
            break;
        case 'image/gif':
            $image = imagecreatefromgif($source_path);
            break;
        default:
            return false;
    }
    
    if (!$image) {
        return false;
    }
    
    // حفظ الصورة المحسنة
    switch ($mime_type) {
        case 'image/jpeg':
            return imagejpeg($image, $destination_path, $quality);
        case 'image/png':
            return imagepng($image, $destination_path, 9 - ($quality / 10));
        case 'image/gif':
            return imagegif($image, $destination_path);
    }
    
    imagedestroy($image);
    return false;
}

/**
 * تنظيف الملفات المؤقتة القديمة
 */
function cleanup_temp_files($directory, $max_age = 86400) {
    if (!is_dir($directory)) {
        return 0;
    }
    
    $files = glob($directory . '/*');
    $cleaned = 0;
    $current_time = time();
    
    foreach ($files as $file) {
        if (is_file($file) && ($current_time - filemtime($file)) > $max_age) {
            if (unlink($file)) {
                $cleaned++;
            }
        }
    }
    
    return $cleaned;
}

/**
 * مراقبة استخدام الذاكرة
 */
function get_memory_usage() {
    return [
        'current' => memory_get_usage(true),
        'peak' => memory_get_peak_usage(true),
        'limit' => ini_get('memory_limit')
    ];
}

// تفعيل الضغط تلقائياً
if (!DEBUG_MODE) {
    enable_compression();
}
?>
