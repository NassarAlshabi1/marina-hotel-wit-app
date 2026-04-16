-- ===================================================
-- إضافة جداول التزامن الناقصة
-- Migration: 001_add_sync_tables.sql
-- ===================================================

USE hotel_db;

-- جدول فئات المصروفات
CREATE TABLE IF NOT EXISTS expense_categories (
    id INT AUTO_INCREMENT PRIMARY KEY,
    local_uuid VARCHAR(36) UNIQUE,
    name VARCHAR(100) NOT NULL,
    icon_name VARCHAR(50) DEFAULT 'category',
    color_hex VARCHAR(10) DEFAULT '#607D8B',
    budget_limit DECIMAL(10,2) DEFAULT 0,
    is_active TINYINT(1) DEFAULT 1,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    INDEX idx_active (is_active, deleted_at),
    INDEX idx_updated (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- جدول ملاحظات الورديات
CREATE TABLE IF NOT EXISTS shift_notes (
    id INT AUTO_INCREMENT PRIMARY KEY,
    local_uuid VARCHAR(36) UNIQUE,
    hotel_day_key VARCHAR(20) NOT NULL,
    note_text TEXT NOT NULL,
    priority VARCHAR(20) DEFAULT 'normal',
    category VARCHAR(50) DEFAULT 'general',
    is_completed TINYINT(1) DEFAULT 0,
    created_by INT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    INDEX idx_hotel_day (hotel_day_key, deleted_at),
    INDEX idx_priority (priority, is_completed),
    INDEX idx_updated (updated_at),
    FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- جدول الإغلاقات اليومية
CREATE TABLE IF NOT EXISTS daily_closures (
    id INT AUTO_INCREMENT PRIMARY KEY,
    local_uuid VARCHAR(36) UNIQUE,
    hotel_day_key VARCHAR(20) UNIQUE NOT NULL,
    total_income DECIMAL(10,2) DEFAULT 0,
    total_expenses DECIMAL(10,2) DEFAULT 0,
    total_bookings INT DEFAULT 0,
    total_checkouts INT DEFAULT 0,
    opening_balance DECIMAL(10,2) DEFAULT 0,
    closing_balance DECIMAL(10,2) DEFAULT 0,
    closed_by INT NULL,
    closed_at TIMESTAMP NULL,
    notes TEXT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at TIMESTAMP NULL,
    INDEX idx_hotel_day (hotel_day_key),
    INDEX idx_closed (closed_at, deleted_at),
    INDEX idx_updated (updated_at),
    FOREIGN KEY (closed_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- إضافة بيانات افتراضية لفئات المصروفات
INSERT INTO expense_categories (local_uuid, name, icon_name, color_hex, budget_limit, is_active) VALUES
(UUID(), 'مصاريف تشغيلية', 'business', '#2196F3', 5000.00, 1),
(UUID(), 'صيانة', 'build', '#FF9800', 3000.00, 1),
(UUID(), 'رواتب', 'account_balance_wallet', '#4CAF50', 10000.00, 1),
(UUID(), 'مشتريات', 'shopping_cart', '#9C27B0', 2000.00, 1),
(UUID(), 'فواتير', 'receipt', '#F44336', 1500.00, 1),
(UUID(), 'أخرى', 'more_horiz', '#607D8B', 1000.00, 1)
ON DUPLICATE KEY UPDATE name = VALUES(name);

SELECT '✓ تم إنشاء الجداول الناقصة بنجاح' AS status;
