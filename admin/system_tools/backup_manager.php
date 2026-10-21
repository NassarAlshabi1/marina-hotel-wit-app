<?php
/**
 * نظام إدارة النسخ الاحتياطي
 * يوفر إنشاء واستعادة النسخ الاحتياطية للنظام
 */

require_once '../../includes/config.php';
require_once '../../includes/db.php';
require_once '../../includes/auth.php';
require_once '../../includes/security.php';

// التحقق من صلاحيات المدير
if (!isset($_SESSION['user_type']) || $_SESSION['user_type'] !== 'admin') {
    header("Location: ../../login.php?error=ليس لديك صلاحية للوصول إلى هذه الصفحة");
    exit();
}

/**
 * فئة إدارة النسخ الاحتياطي
 */
class BackupManager {
    private $conn;
    private $backup_dir;
    private $max_backups = 10;
    
    public function __construct($connection) {
        $this->conn = $connection;
        $this->backup_dir = ROOT_PATH . '/backups';
        
        // إنشاء مجلد النسخ الاحتياطي إذا لم يكن موجوداً
        if (!is_dir($this->backup_dir)) {
            mkdir($this->backup_dir, 0755, true);
        }
    }
    
    /**
     * إنشاء نسخة احتياطية كاملة
     */
    public function createFullBackup() {
        try {
            $timestamp = date('Y-m-d_H-i-s');
            $backup_name = "hotel_backup_{$timestamp}";
            $backup_path = $this->backup_dir . '/' . $backup_name;
            
            // إنشاء مجلد النسخة الاحتياطية
            mkdir($backup_path, 0755, true);
            
            // نسخ قاعدة البيانات
            $db_backup = $this->backupDatabase($backup_path . '/database.sql');
            
            // نسخ الملفات
            $files_backup = $this->backupFiles($backup_path . '/files');
            
            // إنشاء ملف معلومات النسخة الاحتياطية
            $this->createBackupInfo($backup_path, $timestamp);
            
            // ضغط النسخة الاحتياطية
            $zip_file = $this->compressBackup($backup_path, $backup_name);
            
            // حذف المجلد المؤقت
            $this->deleteDirectory($backup_path);
            
            // تنظيف النسخ القديمة
            $this->cleanupOldBackups();
            
            return [
                'success' => true,
                'message' => 'تم إنشاء النسخة الاحتياطية بنجاح',
                'file' => $zip_file,
                'size' => $this->formatFileSize(filesize($zip_file))
            ];
            
        } catch (Exception $e) {
            return [
                'success' => false,
                'message' => 'فشل في إنشاء النسخة الاحتياطية: ' . $e->getMessage()
            ];
        }
    }
    
    /**
     * نسخ قاعدة البيانات
     */
    private function backupDatabase($output_file) {
        $tables = [];
        $result = $this->conn->query("SHOW TABLES");
        
        while ($row = $result->fetch_row()) {
            $tables[] = $row[0];
        }
        
        $sql_dump = "-- نسخة احتياطية لقاعدة البيانات\n";
        $sql_dump .= "-- تاريخ الإنشاء: " . date('Y-m-d H:i:s') . "\n";
        $sql_dump .= "-- نظام إدارة فندق مارينا بلازا\n\n";
        
        $sql_dump .= "SET FOREIGN_KEY_CHECKS=0;\n";
        $sql_dump .= "SET SQL_MODE = \"NO_AUTO_VALUE_ON_ZERO\";\n";
        $sql_dump .= "SET time_zone = \"+00:00\";\n\n";
        
        foreach ($tables as $table) {
            // هيكل الجدول
            $result = $this->conn->query("SHOW CREATE TABLE `$table`");
            $row = $result->fetch_row();
            
            $sql_dump .= "-- هيكل الجدول `$table`\n";
            $sql_dump .= "DROP TABLE IF EXISTS `$table`;\n";
            $sql_dump .= $row[1] . ";\n\n";
            
            // بيانات الجدول
            $result = $this->conn->query("SELECT * FROM `$table`");
            if ($result->num_rows > 0) {
                $sql_dump .= "-- بيانات الجدول `$table`\n";
                
                while ($row = $result->fetch_assoc()) {
                    $sql_dump .= "INSERT INTO `$table` VALUES (";
                    $values = [];
                    foreach ($row as $value) {
                        if ($value === null) {
                            $values[] = 'NULL';
                        } else {
                            $values[] = "'" . $this->conn->real_escape_string($value) . "'";
                        }
                    }
                    $sql_dump .= implode(', ', $values) . ");\n";
                }
                $sql_dump .= "\n";
            }
        }
        
        $sql_dump .= "SET FOREIGN_KEY_CHECKS=1;\n";
        
        return file_put_contents($output_file, $sql_dump) !== false;
    }
    
    /**
     * نسخ الملفات المهمة
     */
    private function backupFiles($backup_files_dir) {
        mkdir($backup_files_dir, 0755, true);
        
        $important_dirs = [
            'uploads' => ROOT_PATH . '/uploads',
            'logs' => ROOT_PATH . '/logs',
            'assets' => ROOT_PATH . '/assets',
            'includes' => ROOT_PATH . '/includes'
        ];
        
        foreach ($important_dirs as $name => $source_dir) {
            if (is_dir($source_dir)) {
                $dest_dir = $backup_files_dir . '/' . $name;
                $this->copyDirectory($source_dir, $dest_dir);
            }
        }
        
        return true;
    }
    
    /**
     * نسخ مجلد بشكل تكراري
     */
    private function copyDirectory($source, $destination) {
        if (!is_dir($destination)) {
            mkdir($destination, 0755, true);
        }
        
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($source, RecursiveDirectoryIterator::SKIP_DOTS),
            RecursiveIteratorIterator::SELF_FIRST
        );
        
        foreach ($iterator as $item) {
            $dest_path = $destination . DIRECTORY_SEPARATOR . $iterator->getSubPathName();
            
            if ($item->isDir()) {
                if (!is_dir($dest_path)) {
                    mkdir($dest_path, 0755, true);
                }
            } else {
                copy($item, $dest_path);
            }
        }
    }
    
    /**
     * حذف مجلد بشكل تكراري
     */
    private function deleteDirectory($dir) {
        if (!is_dir($dir)) {
            return false;
        }
        
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($dir, RecursiveDirectoryIterator::SKIP_DOTS),
            RecursiveIteratorIterator::CHILD_FIRST
        );
        
        foreach ($iterator as $item) {
            if ($item->isDir()) {
                rmdir($item);
            } else {
                unlink($item);
            }
        }
        
        return rmdir($dir);
    }
    
    /**
     * إنشاء ملف معلومات النسخة الاحتياطية
     */
    private function createBackupInfo($backup_path, $timestamp) {
        $info = [
            'system_name' => SYSTEM_NAME,
            'system_version' => SYSTEM_VERSION,
            'backup_date' => $timestamp,
            'backup_type' => 'full',
            'php_version' => phpversion(),
            'mysql_version' => $this->conn->server_info,
            'created_by' => $_SESSION['username'] ?? 'system'
        ];
        
        file_put_contents(
            $backup_path . '/backup_info.json',
            json_encode($info, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE)
        );
    }
    
    /**
     * ضغط النسخة الاحتياطية
     */
    private function compressBackup($backup_path, $backup_name) {
        $zip_file = $this->backup_dir . '/' . $backup_name . '.zip';
        $zip = new ZipArchive();
        
        if ($zip->open($zip_file, ZipArchive::CREATE) !== TRUE) {
            throw new Exception("لا يمكن إنشاء ملف ZIP");
        }
        
        $iterator = new RecursiveIteratorIterator(
            new RecursiveDirectoryIterator($backup_path, RecursiveDirectoryIterator::SKIP_DOTS),
            RecursiveIteratorIterator::SELF_FIRST
        );
        
        foreach ($iterator as $file) {
            if ($file->isFile()) {
                $relative_path = str_replace($backup_path . DIRECTORY_SEPARATOR, '', $file);
                $zip->addFile($file, $relative_path);
            }
        }
        
        $zip->close();
        
        return $zip_file;
    }
    
    /**
     * تنظيف النسخ القديمة
     */
    private function cleanupOldBackups() {
        $backups = glob($this->backup_dir . '/hotel_backup_*.zip');
        
        if (count($backups) > $this->max_backups) {
            // ترتيب حسب تاريخ التعديل
            usort($backups, function($a, $b) {
                return filemtime($a) - filemtime($b);
            });
            
            // حذف النسخ الأقدم
            $to_delete = array_slice($backups, 0, count($backups) - $this->max_backups);
            foreach ($to_delete as $file) {
                unlink($file);
            }
        }
    }
    
    /**
     * الحصول على قائمة النسخ الاحتياطية
     */
    public function getBackupsList() {
        $backups = glob($this->backup_dir . '/hotel_backup_*.zip');
        $backup_list = [];
        
        foreach ($backups as $backup_file) {
            $filename = basename($backup_file);
            $size = filesize($backup_file);
            $date = filemtime($backup_file);
            
            $backup_list[] = [
                'filename' => $filename,
                'size' => $this->formatFileSize($size),
                'date' => date('Y-m-d H:i:s', $date),
                'path' => $backup_file
            ];
        }
        
        // ترتيب حسب التاريخ (الأحدث أولاً)
        usort($backup_list, function($a, $b) {
            return strtotime($b['date']) - strtotime($a['date']);
        });
        
        return $backup_list;
    }
    
    /**
     * تنسيق حجم الملف
     */
    private function formatFileSize($bytes) {
        $units = ['B', 'KB', 'MB', 'GB'];
        $bytes = max($bytes, 0);
        $pow = floor(($bytes ? log($bytes) : 0) / log(1024));
        $pow = min($pow, count($units) - 1);
        
        $bytes /= pow(1024, $pow);
        
        return round($bytes, 2) . ' ' . $units[$pow];
    }
    
    /**
     * تحميل نسخة احتياطية
     */
    public function downloadBackup($filename) {
        $file_path = $this->backup_dir . '/' . $filename;
        
        if (!file_exists($file_path)) {
            return false;
        }
        
        header('Content-Type: application/zip');
        header('Content-Disposition: attachment; filename="' . $filename . '"');
        header('Content-Length: ' . filesize($file_path));
        
        readfile($file_path);
        exit;
    }
    
    /**
     * حذف نسخة احتياطية
     */
    public function deleteBackup($filename) {
        $file_path = $this->backup_dir . '/' . $filename;
        
        if (file_exists($file_path)) {
            return unlink($file_path);
        }
        
        return false;
    }
}

// معالجة الطلبات
$backup_manager = new BackupManager($conn);
$security = new SecurityManager($conn);

$message = '';
$error = '';

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    // التحقق من رمز CSRF
    if (!$security->validateCSRFToken($_POST['csrf_token'] ?? '')) {
        $error = 'رمز الأمان غير صحيح';
    } else {
        $action = $_POST['action'] ?? '';
        
        switch ($action) {
            case 'create_backup':
                $result = $backup_manager->createFullBackup();
                if ($result['success']) {
                    $message = $result['message'] . ' (الحجم: ' . $result['size'] . ')';
                } else {
                    $error = $result['message'];
                }
                break;
                
            case 'delete_backup':
                $filename = $_POST['filename'] ?? '';
                if ($backup_manager->deleteBackup($filename)) {
                    $message = 'تم حذف النسخة الاحتياطية بنجاح';
                } else {
                    $error = 'فشل في حذف النسخة الاحتياطية';
                }
                break;
        }
    }
}

// معالجة التحميل
if (isset($_GET['download'])) {
    $filename = $_GET['download'];
    $backup_manager->downloadBackup($filename);
}

$backups = $backup_manager->getBackupsList();
?>

<!DOCTYPE html>
<html lang="ar" dir="rtl">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>إدارة النسخ الاحتياطي - <?php echo SYSTEM_NAME; ?></title>
    <!-- الخطوط والأيقونات المحلية -->
    <link href="<?= BASE_URL ?>assets/fonts/fonts.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/bootstrap-local.css" rel="stylesheet">
    <link href="<?= BASE_URL ?>assets/css/arabic-enhanced.css" rel="stylesheet">

    <!-- Fallback للخطوط الخارجية -->
    <link href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.4.0/css/all.min.css" rel="stylesheet" media="print" onload="this.media='all'">
</head>
<body>
    <div class="container">
        <div class="card">
            <div class="card-header">
                <h1><i class="fas fa-database"></i> إدارة النسخ الاحتياطي</h1>
            </div>
            
            <div class="card-body">
                <?php if ($message): ?>
                    <div class="alert alert-success">
                        <i class="fas fa-check-circle"></i> <?php echo htmlspecialchars($message); ?>
                    </div>
                <?php endif; ?>
                
                <?php if ($error): ?>
                    <div class="alert alert-danger">
                        <i class="fas fa-exclamation-circle"></i> <?php echo htmlspecialchars($error); ?>
                    </div>
                <?php endif; ?>
                
                <!-- إنشاء نسخة احتياطية جديدة -->
                <div class="card mb-4">
                    <div class="card-header">
                        <h3>إنشاء نسخة احتياطية جديدة</h3>
                    </div>
                    <div class="card-body">
                        <form method="POST">
                            <?php echo csrf_field(); ?>
                            <input type="hidden" name="action" value="create_backup">
                            
                            <p>سيتم إنشاء نسخة احتياطية كاملة تشمل:</p>
                            <ul>
                                <li>جميع بيانات قاعدة البيانات</li>
                                <li>ملفات النظام المهمة</li>
                                <li>الملفات المرفوعة</li>
                                <li>سجلات النظام</li>
                            </ul>
                            
                            <button type="submit" class="btn btn-primary">
                                <i class="fas fa-plus"></i> إنشاء نسخة احتياطية
                            </button>
                        </form>
                    </div>
                </div>
                
                <!-- قائمة النسخ الاحتياطية -->
                <div class="card">
                    <div class="card-header">
                        <h3>النسخ الاحتياطية الموجودة</h3>
                    </div>
                    <div class="card-body">
                        <?php if (empty($backups)): ?>
                            <p class="text-center">لا توجد نسخ احتياطية</p>
                        <?php else: ?>
                            <div class="table-responsive">
                                <table class="table">
                                    <thead>
                                        <tr>
                                            <th>اسم الملف</th>
                                            <th>التاريخ</th>
                                            <th>الحجم</th>
                                            <th>الإجراءات</th>
                                        </tr>
                                    </thead>
                                    <tbody>
                                        <?php foreach ($backups as $backup): ?>
                                            <tr>
                                                <td><?php echo htmlspecialchars($backup['filename']); ?></td>
                                                <td><?php echo $backup['date']; ?></td>
                                                <td><?php echo $backup['size']; ?></td>
                                                <td>
                                                    <a href="?download=<?php echo urlencode($backup['filename']); ?>" 
                                                       class="btn btn-sm btn-info">
                                                        <i class="fas fa-download"></i> تحميل
                                                    </a>
                                                    
                                                    <form method="POST" style="display: inline;" 
                                                          onsubmit="return confirm('هل أنت متأكد من حذف هذه النسخة الاحتياطية؟')">
                                                        <?php echo csrf_field(); ?>
                                                        <input type="hidden" name="action" value="delete_backup">
                                                        <input type="hidden" name="filename" value="<?php echo htmlspecialchars($backup['filename']); ?>">
                                                        <button type="submit" class="btn btn-sm btn-danger">
                                                            <i class="fas fa-trash"></i> حذف
                                                        </button>
                                                    </form>
                                                </td>
                                            </tr>
                                        <?php endforeach; ?>
                                    </tbody>
                                </table>
                            </div>
                        <?php endif; ?>
                    </div>
                </div>
            </div>
            
            <div class="card-footer">
                <a href="../dash.php" class="btn btn-secondary">
                    <i class="fas fa-arrow-right"></i> العودة للوحة التحكم
                </a>
            </div>
        </div>
    </div>
</body>
</html>
