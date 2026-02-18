-- ==========================================
-- إنشاء مستخدم admin افتراضي لـ XAMPP
-- Run this in phpMyAdmin after creating hotel_db
-- ==========================================

USE hotel_db;

-- إنشاء جدول users إذا لم يكن موجوداً
CREATE TABLE IF NOT EXISTS users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    password VARCHAR(255) NOT NULL,
    full_name VARCHAR(100) NOT NULL,
    role VARCHAR(20) DEFAULT 'user',
    status VARCHAR(20) DEFAULT 'active',
    token VARCHAR(64) NULL,
    permissions TEXT NULL,
    last_activity TIMESTAMP NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_token (token),
    INDEX idx_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- حذف المستخدم admin القديم إن وجد
DELETE FROM users WHERE username = 'admin';

-- إنشاء مستخدم admin جديد
-- Username: admin
-- Password: admin123
-- (يمكنك تغيير كلمة المرور بعد أول تسجيل دخول)
INSERT INTO users (username, password, full_name, role, status, permissions) VALUES (
    'admin',
    '$2y$10$YourHashedPasswordHere', -- سيتم تحديثه عبر setup
    'مدير النظام',
    'admin',
    'active',
    '["*"]'
);

-- إنشاء جدول failed_logins إذا لم يكن موجوداً
CREATE TABLE IF NOT EXISTS failed_logins (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) NOT NULL,
    ip_address VARCHAR(45) NOT NULL,
    attempt_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_username (username),
    INDEX idx_ip (ip_address),
    INDEX idx_time (attempt_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- إنشاء جدول user_activity_log إذا لم يكن موجوداً
CREATE TABLE IF NOT EXISTS user_activity_log (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT NOT NULL,
    action VARCHAR(50) NOT NULL,
    details TEXT NULL,
    ip_address VARCHAR(45) NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_user (user_id),
    INDEX idx_action (action),
    INDEX idx_time (created_at),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- رسالة نجاح
SELECT 'تم إنشاء جداول المستخدمين بنجاح!' AS message;
SELECT 'استخدم: admin / admin123 لتسجيل الدخول' AS credentials;
